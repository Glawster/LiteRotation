-- LiteRotation/Commands.lua
-- /lrot                    help
-- /lrot lock | unlock      lock or move the display
-- /lrot scale <n>          display scale
-- /lrot spells             your known spells as the simulator sees them (rank, cost, cast, tooltip damage)
-- /lrot log [on|off]       switch the decision log on or off (off by default; recording costs a little work)
-- /lrot why                the decision log: your last 10 casts, what was recommended and why
-- /lrot toggle <spell>     turn a spell on/off for recommendations (e.g. /lrot toggle death_coil)
-- /lrot ttl [class] <sec>  expected target lifetime (class: normal, elite, rare, rareelite, worldboss)
-- /lrot mana <w>           mana weight (higher = more frugal); /lrot health <w>: health weight
-- /lrot depth <n>          actions looked ahead (1-4)
-- /lrot probe              which game values are readable on this client (secret ones print as SECRET)
-- /lrot rescan             re-read spells and tooltips

local _, ns = ...
local LR = ns.LR
local Print = LR.Print

local function fmt(v)
    if v == nil then
        return "-"
    end
    if type(v) == "number" then
        return (v == math.floor(v)) and tostring(v) or ("%.1f"):format(v)
    end
    return tostring(v)
end

local function spells()
    if not LR.spells or #LR.spells == 0 then
        Print("no known spells from the %s kit.", tostring(LR.class))
        return
    end
    local W = LR.S and LR.S.weapon or {}
    for _, s in ipairs(LR.spells) do
        local off = LR.db.disabled[s.key] and " |cffff6666[off]|r" or ""
        local bad = s.tipOk and "" or " |cffffaa00[no tooltip damage: skipped]|r"
        local extra = {}
        if s.manaGain then
            extra[#extra + 1] = "mana +" .. fmt(s.manaGain)
        end
        if s.cpDirect or s.cpDot then
            local t = s.cpDirect or s.cpDot
            extra[#extra + 1] = ("1-5 points %s..%s%s"):format(fmt(t[1]), fmt(t[5]), s.cpDot and " over time" or "")
        end
        if s.bonus then
            extra[#extra + 1] = "bonus " .. fmt(s.bonus)
        end
        if s.weaponPct then
            extra[#extra + 1] = fmt(s.weaponPct) .. "% weapon"
        end
        if s.ap then
            extra[#extra + 1] = "+" .. fmt(s.ap) .. " AP"
        end
        if s.perHit or s.judge then
            extra[#extra + 1] = ("per hit %s, judgement %s"):format(fmt(s.perHit), fmt(s.judge))
        end
        Print(
            "%s r%d (id %d): %s %s, cast %s, cd %s, direct %s (now %s), dot %s/%ss%s%s%s",
            s.key,
            s.rank,
            s.id,
            s.power,
            fmt(s.cost),
            fmt(LR.CastTime(s)),
            fmt(s.cd),
            fmt(s.direct),
            fmt(LR.DirectNow(s, W)),
            fmt(s.dot),
            fmt(s.dotDur),
            #extra > 0 and (", " .. table.concat(extra, ", ")) or "",
            off,
            bad
        )
    end
    Print(
        "weapon: melee %s every %ss, ranged %s every %ss (last readable values)",
        fmt(W.mhAvg),
        fmt(W.mhSpeed),
        fmt(W.rAvg),
        fmt(W.rSpeed)
    )
end

local function probe()
    local issecret = _G.issecretvalue or function()
        return false
    end
    local function show(label, fn, ...)
        if type(fn) ~= "function" then
            Print("%s: absent", label)
            return
        end
        local ok, a, b = pcall(fn, ...)
        if not ok then
            Print("%s: error", label)
        elseif issecret(a) or issecret(b) then
            Print("%s: |cffff6666SECRET|r", label)
        else
            Print("%s: %s %s", label, tostring(a), b ~= nil and tostring(b) or "")
        end
    end
    local sb = LR.spells and LR.spells[1]
    local id = sb and sb.id or 686
    show("UnitPower mana", UnitPower, "player", 0)
    show("UnitPowerMax mana", UnitPowerMax, "player", 0)
    show("GetManaRegen", _G.GetManaRegen)
    show("UnitStat spirit", function()
        return select(2, UnitStat("player", 5))
    end)
    show("IsSpellUsable", C_Spell.IsSpellUsable, id)
    show("GetSpellCooldown", function()
        local c = C_Spell.GetSpellCooldown(id)
        return c and c.startTime, c and c.duration
    end)
    show("GetSpellInfo castTime", function()
        local i = C_Spell.GetSpellInfo(id)
        return i and i.castTime
    end)
    show("UnitCastingInfo end", function()
        return select(5, UnitCastingInfo("player"))
    end)
    show("UnitGUID target", UnitGUID, "target")
    show("UnitIsDead target", UnitIsDead, "target")
    show("UnitCanAttack target", UnitCanAttack, "player", "target")
    show("UnitClassification", UnitClassification, "target")
    show("UnitHealth target", UnitHealth, "target")
    show("UnitRangedDamage", UnitRangedDamage, "player")
    show("UnitDamage", UnitDamage, "player")
    show("UnitAttackSpeed", UnitAttackSpeed, "player")
    show("UnitPower energy", UnitPower, "player", 3)
    show("UnitPower rage", UnitPower, "player", 1)
    show("GetComboPoints", GetComboPoints, "player", "target")
    show("Shapeshift form", function()
        local i = GetShapeshiftForm()
        return i, i and i > 0 and select(4, GetShapeshiftFormInfo(i)) or nil
    end)
    show("IsSpellInRange", C_Spell.IsSpellInRange, id, "target")
    show("UnitCreatureType", UnitCreatureType, "target")
    show("Nightfall aura read", function()
        return C_UnitAuras.GetPlayerAuraBySpellID(17941) ~= nil
    end)
    show("Soul Shards", C_Item and C_Item.GetItemCount or GetItemCount, 6265)
    show("Description", function()
        return (C_Spell.GetSpellDescription(id) or ""):sub(1, 80)
    end)
end

SLASH_LITEROTATION1 = "/lrot"
SlashCmdList.LITEROTATION = function(msg)
    local cmd, a, b = msg:lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
    local db = LR.db
    if cmd == "lock" then
        LR:SetLocked(true)
        Print("locked.")
    elseif cmd == "unlock" then
        LR:SetLocked(false)
        Print("unlocked: drag to move.")
    elseif cmd == "scale" and tonumber(a) then
        db.scale = tonumber(a)
        if LR.frame then
            LR.frame:SetScale(db.scale)
        end
    elseif cmd == "spells" then
        spells()
    elseif cmd == "why" then
        LR:PrintLog()
    elseif cmd == "log" then
        if a == "on" or a == "off" then
            LR:SetLogging(a == "on")
        else
            LR:SetLogging(not db.log)
        end
    elseif cmd == "toggle" and a ~= "" then
        db.disabled[a] = not db.disabled[a] or nil
        Print("%s %s.", a, db.disabled[a] and "off" or "on")
    elseif cmd == "ttl" then
        local class, sec = a, tonumber(b)
        if tonumber(a) then
            class, sec = "normal", tonumber(a)
        end
        if sec and db.ttl[class] then
            db.ttl[class] = sec
        end
        Print(
            "target lifetime: normal %ds, elite %ds, rare %ds, rareelite %ds, worldboss %ds.",
            db.ttl.normal,
            db.ttl.elite,
            db.ttl.rare,
            db.ttl.rareelite,
            db.ttl.worldboss
        )
    elseif cmd == "mana" and tonumber(a) then
        db.manaWeight = tonumber(a)
        Print("mana weight %.2f.", db.manaWeight)
    elseif cmd == "health" and tonumber(a) then
        db.healthWeight = tonumber(a)
        Print("health weight %.2f.", db.healthWeight)
    elseif cmd == "depth" and tonumber(a) then
        db.depth = math.max(1, math.min(4, math.floor(tonumber(a))))
        Print("looking %d actions ahead.", db.depth)
    elseif cmd == "probe" then
        probe()
    elseif cmd == "rescan" then
        LR:ScanSpells()
        Print("rescanned: %d spells.", #(LR.spells or {}))
    else
        Print(
            "commands: lock, unlock, scale <n>, spells, log [on|off], why, toggle <spell>, ttl [class] <sec>, mana <w>, health <w>, depth <n>, probe, rescan"
        )
    end
end
