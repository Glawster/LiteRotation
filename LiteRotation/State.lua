-- LiteRotation/State.lua
-- What we believe about the fight, kept from our own cast events because Forever hides most of it:
--   * our cast / channel in progress and the GCD (from UNIT_SPELLCAST_* and the spell's cast time)
--   * our cooldowns (cast time + the spell's base cooldown)
--   * our DoTs on each target (the target's auras are unreadable in combat: we record what we cast)
--   * mana: the client's value when readable; otherwise an estimate (spend on cast, regen by the five-second rule)
--     kept inside the bounds IsSpellUsable gives (usable => mana >= cost; "not enough mana" => mana < cost)
--   * the target's expected remaining life (health is secret: a per-classification guess minus time engaged)
-- LR:Snapshot() packs this for the simulator; LR:Tick() runs the simulator and updates the display.

local _, ns = ...
local LR = ns.LR
local read, field = LR.read, LR.field

local GCD = 1.5
local FSR = 5 -- the five-second rule

local S = {
    castSpell = nil,
    castEnd = 0,
    chanSpell = nil,
    chanEnd = 0,
    gcdEnd = 0,
    cdEnd = {}, -- [key] = time ready
    lastSpend = -100,
    swap = 0, -- target swaps, the key when the GUID is secret
    targets = {}, -- [targetKey] = { debuffs = { [name] = expires }, engaged = time|nil, seen = time }
    mana = { est = nil, max = nil, lo = 0, hi = math.huge, plain = false, at = 0 },
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
        t = { debuffs = {}, engaged = nil, seen = GetTime() }
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
-- Mana
---------------------------------------------------------------------------------------------------------------------

local MANA = 0

--- Mana regenerated per second outside the five-second rule, and inside it.
local function regenRates()
    local base, casting = read(_G.GetManaRegen)
    if type(base) == "number" and type(casting) == "number" then
        return base, casting
    end
    -- Classic's formula for a Warlock: 8 + Spirit/4 per 2 s tick, none while casting.
    local _, spirit = read(UnitStat, "player", 5)
    spirit = type(spirit) == "number" and spirit or 20
    return (8 + spirit / 4) / 2, 0
end

local function updateMana(now)
    local M = S.mana
    local mx = read(UnitPowerMax, "player", MANA)
    if type(mx) == "number" and mx > 0 then
        M.max = mx
    end
    local cur = read(UnitPower, "player", MANA)
    if type(cur) == "number" then
        M.est, M.lo, M.hi, M.plain, M.at = cur, cur, cur, true, now
        return
    end
    M.plain = false

    -- Advance the estimate by regen since the last update.
    local outside, inside = regenRates()
    if M.est then
        local dt = now - M.at
        local rate = (now - S.lastSpend >= FSR) and outside or inside
        M.est = M.est + rate * math.max(0, dt)
    end
    M.at = now

    -- Bounds from usability: each known spell's cost brackets the mana.
    local lo, hi = 0, math.huge
    for _, s in ipairs(LR.spells or {}) do
        if s.cost and s.cost > 0 then
            local usable, noMana = read(C_Spell.IsSpellUsable, s.id)
            if usable == true then
                lo = math.max(lo, s.cost)
            elseif noMana == true then
                hi = math.min(hi, s.cost - 1)
            end
        end
    end
    M.lo, M.hi = lo, hi
    if not M.max then
        local level = read(UnitLevel, "player") or 1
        M.max = 100 + 25 * level -- a rough guess, raised by what we observe
    end
    M.max = math.max(M.max, lo)
    if not M.est then
        M.est = math.min(M.max, hi)
    end
    M.est = math.min(math.max(M.est, lo), hi, M.max)
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
    local M = S.mana
    if s.cost > 0 then
        S.lastSpend = now
        if not M.plain and M.est then
            M.est = math.max(0, M.est - s.cost)
        end
    end
    if def.kind == "tap" and not M.plain and M.est and s.manaGain then
        M.est = math.min(M.max or math.huge, M.est + s.manaGain)
    end
    if s.cd and s.cd > 0 then
        S.cdEnd[s.key] = now + s.cd
    end
    if s.gcd > 0 and castTime(s) == 0 then
        S.gcdEnd = now + GCD
    end
    if def.kind ~= "tap" and def.kind ~= "wand" then
        local t = target(true)
        if t then
            t.engaged = t.engaged or now
            if def.debuff and s.dotDur then
                t.debuffs[def.debuff] = now + s.dotDur
            end
            if def.consumes then
                t.debuffs[def.consumes] = nil
            end
        end
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
    if s.gcd > 0 then
        S.gcdEnd = now + GCD
    end
end

function events.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    local s = spellOf(spellID)
    if unit ~= "player" or not s then
        return
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
    S.gcdEnd = now + GCD
end

function events.UNIT_SPELLCAST_CHANNEL_STOP(unit)
    if unit == "player" then
        -- a paid channel holds the five-second rule until it ends
        if S.chanSpell and S.chanSpell.cost > 0 then
            S.lastSpend = GetTime()
        end
        S.chanSpell, S.chanEnd = nil, 0
    end
end

function events.PLAYER_TARGET_CHANGED()
    S.swap = S.swap + 1
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
events.SPELL_DATA_LOAD_RESULT = function()
    if LR.tooltipPending then
        rescan()
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Snapshot
---------------------------------------------------------------------------------------------------------------------

local function wand()
    if not read(_G.HasWandEquipped) then
        return nil
    end
    local speed, lo, hi = read(UnitRangedDamage, "player")
    if type(speed) ~= "number" or speed <= 0 or type(lo) ~= "number" or type(hi) ~= "number" then
        return nil
    end
    return { avg = (lo + hi) / 2, speed = speed }
end

local function hasAura(spellID)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local a = read(get, spellID)
    return a ~= nil
end

--- Everything the simulator needs, relative to now (time 0).
function LR:Snapshot()
    local now = GetTime()
    updateMana(now)
    local t = target(false)
    local snap = {
        now = now,
        ready = math.max(0, S.gcdEnd - now, S.castEnd - now, S.chanEnd - now),
        pending = (S.castSpell and S.castEnd > now) and S.castSpell or nil,
        mana = S.mana.est or 0,
        manaMax = S.mana.max or 1,
        manaPlain = S.mana.plain,
        fsrLeft = math.max(0, S.lastSpend + FSR - now),
        cds = {},
        debuffs = {},
        ttl = ttlFor(t, now),
        shards = read(C_Item and C_Item.GetItemCount or _G.GetItemCount, self.kit.SOUL_SHARD or 0) or 0,
        wand = wand(),
        procs = {},
        spells = {},
    }
    snap.regenOut, snap.regenIn = regenRates()
    for key, ends in pairs(S.cdEnd) do
        if ends > now then
            snap.cds[key] = ends - now
        end
    end
    if t then
        for name, ends in pairs(t.debuffs) do
            if ends > now then
                snap.debuffs[name] = ends - now
            end
        end
    end
    for name, id in pairs(self.kit.procs or {}) do
        snap.procs[name] = hasAura(id)
    end
    for _, s in ipairs(self.spells or {}) do
        if not self.db.disabled[s.key] and s.tipOk then
            s.castNow = castTime(s)
            if s.key == "shadow_bolt" and snap.procs.shadow_trance then
                s.castNow = 0
            end
            snap.spells[#snap.spells + 1] = s
        end
    end
    return snap
end

---------------------------------------------------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local elapsed = 0
local INTERVAL = 0.15

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
