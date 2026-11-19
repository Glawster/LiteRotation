-- LiteRotation/State.lua
-- What we believe about the fight, kept from our own cast events because Forever hides most of it:
--   * our cast / channel in progress and the GCD (from UNIT_SPELLCAST_* and the spell's cast time)
--   * our cooldowns (cast time + the spell's base cooldown)
--   * our effects: DoTs and marks on each target (the target's auras are unreadable in combat: we record what we
--     cast), and effects on ourselves such as a Paladin's seal
--   * power (mana, energy or rage): the client's value when readable; otherwise an estimate (spent on cast, regen by
--     type) kept inside the bounds IsSpellUsable gives (usable => power >= cost; "not enough" => power < cost)
--   * combo points: the client's count when readable, else counted from our builders and finishers
--   * weapon damage and speed, cached whenever readable (likely only out of combat)
--   * the target's expected remaining life (health is secret: a per-classification guess minus time engaged)
-- LR:Snapshot() packs this for the simulator; LR:Tick() runs the simulator and updates the display.

local _, ns = ...
local LR = ns.LR
local read = LR.read

local FSR = 5 -- the five-second rule

local S = {
    castSpell = nil,
    castEnd = 0,
    chanSpell = nil,
    chanEnd = 0,
    gcdEnd = 0,
    cdEnd = {}, -- [key] = time ready
    lastSpend = -100, -- our last mana spend (the five-second rule)
    swap = 0, -- target swaps, the key when the GUID is secret
    targets = {}, -- [targetKey] = { debuffs = { [effect] = expires }, rates = { [effect] = dmg/s }, engaged, seen }
    self = { debuffs = {}, rates = {}, src = {} }, -- effects on ourselves (seals): [effect] = expires / rate / spell key
    cp = 0, -- combo points, counted when the client's count is secret
    power = {}, -- [type] = { est, max, lo, hi, plain, at }
    weapon = {}, -- mhAvg, mhSpeed, rAvg, rSpeed: the last readable values
}
LR.S = S

---------------------------------------------------------------------------------------------------------------------
-- Target
---------------------------------------------------------------------------------------------------------------------

local function targetKey()
    if not read(UnitExists, "target") then
        return nil
    end
    local guid = read(UnitGUID, "target")
    if type(guid) == "string" and guid ~= "" then
        return guid
    end
    return "swap" .. S.swap
end

local function target(create)
    local k = targetKey()
    if not k then
        return nil
    end
    local t = S.targets[k]
    if not t and create then
        t = { debuffs = {}, rates = {}, engaged = nil, seen = GetTime() }
        S.targets[k] = t
    end
    return t
end
LR.Target = target

local function targetAlive()
    if not read(UnitExists, "target") then
        return false
    end
    local dead = read(UnitIsDead, "target")
    if dead == true then
        return false
    end
    local hostile = read(UnitCanAttack, "player", "target")
    return hostile ~= false
end

local function ttlFor(t, now)
    local class = read(UnitClassification, "target") or "normal"
    local base = LR.db.ttl[class] or LR.db.ttl.normal
    if t and t.engaged then
        return math.max(2, base - (now - t.engaged))
    end
    return base
end

---------------------------------------------------------------------------------------------------------------------
-- Weapons
---------------------------------------------------------------------------------------------------------------------

local function updateWeapon()
    local W = S.weapon
    local lo, hi = read(UnitDamage, "player")
    if type(lo) == "number" and type(hi) == "number" and hi > 0 then
        W.mhAvg = (lo + hi) / 2
    end
    local speed = read(UnitAttackSpeed, "player")
    if type(speed) == "number" and speed > 0 then
        W.mhSpeed = speed
    end
    local rs, rlo, rhi = read(UnitRangedDamage, "player")
    if type(rs) == "number" and rs > 0 and type(rlo) == "number" and type(rhi) == "number" then
        W.rSpeed, W.rAvg = rs, (rlo + rhi) / 2
    end
    W.wand = read(_G.HasWandEquipped) == true
    local base, pos, neg = read(UnitAttackPower, "player")
    if type(base) == "number" and type(pos) == "number" and type(neg) == "number" then
        W.ap = base + pos + neg
    end
    return W
end

---------------------------------------------------------------------------------------------------------------------
-- Power
---------------------------------------------------------------------------------------------------------------------

local function powerState(p)
    local R = S.power[p]
    if not R then
        R = { est = nil, max = nil, lo = 0, hi = math.huge, plain = false, at = 0 }
        S.power[p] = R
    end
    return R
end
LR.PowerState = powerState

-- Rage from a white hit (Classic: 7.5 x damage / the level's conversion value).
local function rageConversion(level)
    return 0.0091107836 * level * level + 3.225598133 * level + 4.2652911
end

--- Power regenerated per second: (outside the five-second rule, inside it). Energy and rage have one rate.
local function regenRates(p, inCombat)
    if p == "energy" then
        return 10, 10 -- 20 every 2 s
    elseif p == "rage" then
        if not inCombat then
            return 0, 0
        end
        local W = S.weapon
        local level = read(UnitLevel, "player") or 1
        local perSec = 3
        if W.mhAvg and W.mhSpeed then
            -- white hits, plus about a third more from hits taken (unseen: a guess)
            perSec = 7.5 * W.mhAvg / rageConversion(level) / W.mhSpeed * 1.3
        end
        return perSec, perSec
    end
    local base, casting = read(_G.GetManaRegen)
    if type(base) == "number" and type(casting) == "number" then
        return base, casting
    end
    -- Classic's formula: about 8 + Spirit/4 per 2 s tick for casters, none while casting.
    local _, spirit = read(UnitStat, "player", 5)
    spirit = type(spirit) == "number" and spirit or 20
    return (8 + spirit / 4) / 2, 0
end

local function updatePower(p, now, inCombat, spells)
    local R = powerState(p)
    local num = LR.POWER[p]
    local mx = read(UnitPowerMax, "player", num)
    if type(mx) == "number" and mx > 0 then
        R.max = mx
    end
    local cur = read(UnitPower, "player", num)
    if type(cur) == "number" then
        R.est, R.lo, R.hi, R.plain, R.at = cur, cur, cur, true, now
        return R
    end
    R.plain = false

    -- Advance the estimate by regen since the last update.
    local outside, inside = regenRates(p, inCombat)
    if R.est then
        local dt = math.max(0, now - R.at)
        local rate = (p ~= "mana" or now - S.lastSpend >= FSR) and outside or inside
        if p == "rage" and not inCombat then
            rate = -1 -- rage fades out of combat
        end
        R.est = math.max(0, R.est + rate * dt)
    end
    R.at = now

    -- Bounds from usability: each castable spell's cost brackets the power.
    local lo, hi = 0, math.huge
    for _, s in ipairs(spells) do
        if s.power == p and s.cost > 0 then
            local usable, short = read(C_Spell.IsSpellUsable, s.id)
            if usable == true then
                lo = math.max(lo, s.cost)
            elseif short == true then
                hi = math.min(hi, s.cost - 1)
            end
        end
    end
    R.lo, R.hi = lo, hi
    if not R.max then
        if p == "mana" then
            local level = read(UnitLevel, "player") or 1
            R.max = 100 + 25 * level -- a rough guess, raised by what we observe
        else
            R.max = 100
        end
    end
    R.max = math.max(R.max, lo)
    if not R.est then
        R.est = (p == "rage") and lo or math.min(R.max, hi)
    end
    R.est = math.min(math.max(R.est, lo), hi, R.max)
    return R
end

---------------------------------------------------------------------------------------------------------------------
-- Own casts
---------------------------------------------------------------------------------------------------------------------

local function spellOf(spellID)
    spellID = LR.plain(spellID)
    return spellID and LR.spellById and LR.spellById[spellID]
end

local function castTime(s)
    if s.def.kind == "channel" then
        return s.def.channel
    end
    local c = LR.clientCast(s.id)
    if c == nil then
        c = s.baseCast
    end
    return c
end
LR.CastTime = castTime

local function onSucceeded(s, now)
    local def = s.def
    local R = powerState(s.power)
    if s.cost > 0 then
        if s.power == "mana" then
            S.lastSpend = now
        end
        if not R.plain and R.est then
            R.est = math.max(0, R.est - s.cost)
        end
    end
    if def.powerGain and not R.plain and R.est then -- Enrage: rage now (the estimate takes it all at once)
        R.est = math.min(R.max or math.huge, R.est + def.powerGain)
    end
    if def.kind == "tap" then
        local M = powerState("mana")
        if not M.plain and M.est and s.manaGain then
            M.est = math.min(M.max or math.huge, M.est + s.manaGain)
        end
    end
    if s.cd and s.cd > 0 then
        S.cdEnd[s.cdKey or s.key] = now + s.cd
    end
    if s.gcd > 0 and castTime(s) == 0 and not def.nextSwing then
        S.gcdEnd = now + s.gcd
    end

    -- Effects: the rate is fixed at the cast (a finisher's by the combo points it spent).
    local total, dur = s.dot, s.dotDur
    if def.cp == "finisher" then
        local c = math.min(math.max(S.cp, 1), 5)
        total, dur = s.cpDot and s.cpDot[c], s.cpDur or s.dotDur
    end
    if def.self then
        if def.debuff and dur and dur > 0 then
            S.self.debuffs[def.debuff] = now + dur
            S.self.rates[def.debuff] = (total or 0) / dur
            S.self.src[def.debuff] = s.key
        end
    elseif def.kind ~= "tap" and def.kind ~= "wand" then
        local t = target(true)
        if t then
            t.engaged = t.engaged or now
            if def.debuff and dur and dur > 0 then
                t.debuffs[def.debuff] = now + dur
                t.rates[def.debuff] = (total or 0) / dur
            end
            if def.consumes then
                t.debuffs[def.consumes], t.rates[def.consumes] = nil, nil
            end
        end
    end
    if def.cp == "gen" then
        S.cp = math.min(5, S.cp + 1)
    elseif def.cp == "finisher" then
        S.cp = 0
    end
end

local events = {}

function events.UNIT_SPELLCAST_START(unit, _, spellID)
    local s = spellOf(spellID)
    if unit ~= "player" or not s then
        return
    end
    local now = GetTime()
    local _, _, _, _, endMs = read(UnitCastingInfo, "player")
    S.castSpell = s
    S.castEnd = type(endMs) == "number" and endMs / 1000 or now + castTime(s)
    if LR.db.log then
        LR:LogCast(s) -- logged when the cast starts, against the recommendation it was chosen from
    end
    if s.gcd > 0 then
        S.gcdEnd = now + s.gcd
    end
end

function events.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    local s = spellOf(spellID)
    if unit ~= "player" or not s then
        return
    end
    if LR.db.log and S.castSpell ~= s then
        LR:LogCast(s) -- an instant or channel (cast-time spells were logged at their start)
    end
    onSucceeded(s, GetTime())
    if S.castSpell == s then
        S.castSpell, S.castEnd = nil, 0
    end
end

local function stopCast(unit)
    if unit == "player" then
        S.castSpell, S.castEnd = nil, 0
    end
end
events.UNIT_SPELLCAST_STOP = stopCast
events.UNIT_SPELLCAST_FAILED = stopCast
events.UNIT_SPELLCAST_INTERRUPTED = stopCast

function events.UNIT_SPELLCAST_CHANNEL_START(unit, _, spellID)
    local s = spellOf(spellID)
    if unit ~= "player" or not s then
        return
    end
    local now = GetTime()
    local _, _, _, _, endMs = read(UnitChannelInfo, "player")
    S.chanSpell = s
    S.chanEnd = type(endMs) == "number" and endMs / 1000 or now + castTime(s)
    S.gcdEnd = now + s.gcd
end

function events.UNIT_SPELLCAST_CHANNEL_STOP(unit)
    if unit == "player" then
        -- a paid channel holds the five-second rule until it ends
        if S.chanSpell and S.chanSpell.cost > 0 and S.chanSpell.power == "mana" then
            S.lastSpend = GetTime()
        end
        S.chanSpell, S.chanEnd = nil, 0
    end
end

function events.PLAYER_TARGET_CHANGED()
    S.swap = S.swap + 1
    S.cp = 0 -- combo points belong to the old target
end

function events.PLAYER_REGEN_ENABLED()
    -- Out of combat: forget targets not seen engaged recently.
    local now = GetTime()
    for k, t in pairs(S.targets) do
        if not t.engaged or now - t.engaged > 120 then
            S.targets[k] = nil
        else
            t.engaged = nil
        end
    end
end

local function rescan()
    LR.rescanAt = GetTime() + 0.5 -- batched: these events come in bursts
end
events.SPELLS_CHANGED = rescan
events.PLAYER_LEVEL_UP = rescan
events.LEARNED_SPELL_IN_TAB = rescan
events.PLAYER_EQUIPMENT_CHANGED = rescan -- tooltips may include weapon damage
events.SPELL_DATA_LOAD_RESULT = function()
    if LR.tooltipPending then
        rescan()
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Snapshot
---------------------------------------------------------------------------------------------------------------------

--- A spell's direct damage now, weapon hit included where its tooltip says so.
local function directNow(s, W)
    local def = s.def
    if def.nextSwing then
        return s.bonus or s.direct -- it replaces a white swing: the gain is the bonus
    end
    local base = s.direct or 0
    if def.weapon then
        local avg = def.weapon == "ranged" and W.rAvg or W.mhAvg
        if avg then
            if s.weaponPct then
                base = base + avg * s.weaponPct / 100
            elseif s.bonus then
                base = s.bonus + avg -- "increases ranged damage by X": a weapon shot plus X
            elseif s.additional or s.weaponPlus then
                base = base + avg
            end
        end
    elseif s.bonus and base == 0 then
        base = s.bonus
    end
    if s.apPct and W.ap then -- "damage equal to 45% of your attack power"
        base = base + W.ap * s.apPct / 100
    end
    return base > 0 and base or nil
end
LR.DirectNow = directNow

local function hasAura(spellID)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local a = read(get, spellID)
    return a ~= nil
end

local function isSecret(v)
    return v ~= nil and LR.plain(v) == nil
end

-- One of your debuffs on the target, by index: spell ID and expiry. `secret` when the game hides it, nil past the
-- end of the list.
local function auraAt(i)
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if byIndex then
        local ok, a = pcall(byIndex, "target", i, "HARMFUL|PLAYER")
        if not ok or isSecret(a) then
            return "secret"
        end
        if a == nil then
            return nil
        end
        local id = LR.field(a, "spellId")
        if id == nil then
            return "secret"
        end
        return id, LR.field(a, "expirationTime")
    end
    local ok, name, _, _, _, _, expires, _, _, _, id = pcall(_G.UnitAura, "target", i, "HARMFUL|PLAYER")
    if not ok or isSecret(name) or isSecret(id) then
        return "secret"
    end
    if name == nil then
        return nil
    end
    return id, LR.plain(expires)
end

--- Your aura from spell def on the target, when the game shows it: "up" and its expiry (nil if hidden), "down",
--- or "unknown" while the target's auras are secret (in combat on Forever).
local function targetAura(def)
    if not read(UnitExists, "target") then
        return "unknown"
    end
    local ranks = {}
    for _, id in ipairs(def.ranks) do
        ranks[id] = true
    end
    for i = 1, 40 do
        local id, expires = auraAt(i)
        if id == "secret" then
            return "unknown"
        elseif id == nil then
            return "down"
        elseif ranks[id] then
            return "up", expires
        end
    end
    return "unknown"
end
LR.TargetAura = targetAura

-- Correct our record of `auraCheck` effects (Hunter's Mark) from the target's auras whenever the game shows them:
-- a mark cast before a /reload, or one we missed, counts. A mark that is gone is forgotten, but only out of combat:
-- in combat an empty list may just mean the game is hiding it.
local function syncTargetAuras(all, now, inCombat)
    for _, s in ipairs(all) do
        local def = s.def
        if def.auraCheck and def.debuff then
            local state, expires = targetAura(def)
            if state == "up" then
                local t = target(true)
                if type(expires) == "number" and expires > 0 then
                    t.debuffs[def.debuff] = expires
                elseif (t.debuffs[def.debuff] or 0) <= now then
                    t.debuffs[def.debuff] = now + (s.dotDur or def.dotDur or 0)
                end
                t.rates[def.debuff] = t.rates[def.debuff] or (s.dot and s.dotDur and s.dot / s.dotDur) or 0
            elseif state == "down" and not inCombat then
                local t = target(false)
                if t then
                    t.debuffs[def.debuff], t.rates[def.debuff] = nil, nil
                end
            end
        end
    end
end

-- Whether s may be recommended right now (form, power, range, trigger, target type).
local function castableNow(s, form, powerType, db, ignoreRange)
    local def = s.def
    if db.disabled[s.key] or not s.tipOk then
        return false
    end
    if def.forms and not def.forms[form or "caster"] then
        return false
    end
    if s.cost > 0 and s.power ~= powerType then
        return false
    end
    if def.kind == "wand" and not S.weapon.wand then
        return false
    end
    if not ignoreRange and read(C_Spell.IsSpellInRange, s.id, "target") == false then
        return false
    end
    if def.reactive then
        local usable, short = read(C_Spell.IsSpellUsable, s.id)
        if not (usable == true or short == true) then
            return false
        end
    end
    if def.creature and (not def.creatureUpTo or s.rank <= def.creatureUpTo) then
        local ct = read(UnitCreatureType, "target")
        if not (ct and def.creature[ct]) then
            return false
        end
    end
    return true
end

--- Everything the simulator needs, relative to now (time 0).
function LR:Snapshot()
    local now = GetTime()
    local kit = self.kit
    local inCombat = read(UnitAffectingCombat, "player") == true
    local W = updateWeapon()
    local form = kit.Form and kit.Form() or nil
    local powerType = (kit.Power and kit.Power(form)) or kit.power or "mana"
    local all = self.spells or {}
    local R = updatePower(powerType, now, inCombat, all)
    if powerType ~= "mana" and powerState("mana").est then
        updatePower("mana", now, inCombat, all) -- keep the mana estimate moving while shapeshifted
    end
    local t = target(false)

    local cp = read(GetComboPoints, "player", "target")
    if type(cp) == "number" then
        S.cp = cp
    end

    local snap = {
        now = now,
        form = form,
        powerType = powerType,
        ready = math.max(0, S.gcdEnd - now, S.castEnd - now, S.chanEnd - now),
        pending = (S.castSpell and S.castEnd > now) and S.castSpell or nil,
        power = R.est or 0,
        powerMax = R.max or 1,
        powerPlain = R.plain,
        fsrLeft = powerType == "mana" and math.max(0, S.lastSpend + FSR - now) or 0,
        cp = S.cp,
        cds = {},
        debuffs = {},
        rates = {},
        vars = {},
        ttl = ttlFor(t, now),
        shards = read(C_Item and C_Item.GetItemCount or _G.GetItemCount, kit.SOUL_SHARD or 0) or 0,
        swing = W.mhSpeed,
        procs = {},
        spells = {},
    }
    snap.regenOut, snap.regenIn = regenRates(powerType, inCombat)
    if W.wand and W.rAvg and W.rSpeed then
        snap.wand = { avg = W.rAvg, speed = W.rSpeed }
    end
    if kit.autoShot and W.rAvg and W.rSpeed then
        snap.autoDps = W.rAvg / W.rSpeed
    end
    for key, ends in pairs(S.cdEnd) do
        if ends > now then
            snap.cds[key] = ends - now
        end
    end
    local function addEffects(src)
        for name, ends in pairs(src.debuffs) do
            if ends > now then
                snap.debuffs[name] = ends - now
                snap.rates[name] = src.rates[name]
            end
        end
    end
    addEffects(S.self)
    syncTargetAuras(all, now, inCombat)
    t = target(false)
    if t then
        addEffects(t)
    end
    for name, id in pairs(kit.procs or {}) do
        snap.procs[name] = hasAura(id)
    end

    -- Every known spell's numbers now (weapon damage, hooks), then the ones that may be cast.
    for _, s in ipairs(all) do
        s.castNow = castTime(s)
        if s.def.update then
            s.def.update(s, snap, W)
        end
        s.dmgDirect = directNow(s, W)
    end
    if kit.Snapshot then
        kit.Snapshot(snap, S, self)
    end
    for _, s in ipairs(all) do
        if castableNow(s, form, powerType, self.db) then
            snap.spells[#snap.spells + 1] = s
        end
    end
    -- Nothing in range: plan as if in range, so the display shows what to cast on arrival (tinted red) rather than
    -- an empty plan that looks like being out of mana.
    if #snap.spells == 0 then
        for _, s in ipairs(all) do
            if castableNow(s, form, powerType, self.db, true) then
                snap.spells[#snap.spells + 1] = s
                snap.outOfRange = true
            end
        end
    end
    return snap
end

---------------------------------------------------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local elapsed = 0
local INTERVAL = 0.2

function LR:Tick()
    if self.rescanAt and GetTime() >= self.rescanAt then
        self.rescanAt, self.tooltipPending = nil, false
        self:ScanSpells()
    end
    local inCombat = read(UnitAffectingCombat, "player")
    local show = targetAlive() or (inCombat and not self.db.onlyWithTarget)
    if not show then
        self.result = nil
        self:ShowResult(nil)
        return
    end
    local snap = self:Snapshot()
    self.lastSnap = snap
    self.result = ns.Sim.Run(snap, self.db)
    self:ShowResult(self.result, snap)
end

function LR:StartState()
    for ev in pairs(events) do
        pcall(driver.RegisterEvent, driver, ev)
    end
    driver:SetScript("OnEvent", function(_, ev, ...)
        events[ev](...)
    end)
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= INTERVAL then
            elapsed = 0
            LR:Tick()
        end
    end)
end
