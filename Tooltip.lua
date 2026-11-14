-- LiteRotation/Tooltip.lua
-- Reads a spell's damage from its tooltip description (English client). The parse is plain Lua with no game calls,
-- so tests can run it outside the game.
--
-- Shapes understood (Classic wording):
--   direct        "causing 13 to 18 Shadow damage", "for 11 Fire damage", "causes 301 damage"
--   over time     "40 Shadow damage over 12 sec", "20 to 30 Fire damage over 15 sec"
--   per tick      "15 damage every 3 sec ... Lasts 30 sec", "Transfers 10 health every 1 sec ... Lasts 5 sec",
--                 "Transfers 15 health from the target to the caster every 3 sec. Lasts 30 sec."
--   combo points  "1 point: 50-66 damage", "1 point: 42 damage over 12 sec" (one line per point)
--   weapon        "causing 27 additional damage", "for an additional 30 damage" (additional: on top of a weapon hit),
--                 "225% damage plus 54", "70% weapon damage" (weaponPct), "increases melee damage by 5" (bonus)
--   attack power  "increasing the ranged attack power ... by 20" (ap)
--   Life Tap      "Converts 30 health into 30 mana."
-- Result fields: ok, direct, dot, dotDur, cpDirect[c], cpDot[c], cpDur, additional, weaponPct, bonus, ap, manaGain,
-- healthCost. Damage is an average; dot is the total over dotDur.

local _, ns = ...
ns = ns or {}
local T = {}
ns.Tooltip = T

local function num(s)
    return s and tonumber((s:gsub(",", "")))
end
T.num = num

local N = "(%d[%d,]*)"
local OVER_RANGE = N .. " to " .. N .. "[%a ]-damage over ([%d%.]+) sec"
local OVER_ONE = N .. "[%a ]-damage over ([%d%.]+) sec"
local CP_DOT = "(%d) points?%s*:%s*" .. N .. "[%a ]-damage over ([%d%.]+) sec"
local CP_RANGE = "(%d) points?%s*:%s*" .. N .. "%s*%-%s*" .. N .. "[%a ]-damage"
local CP_TO = "(%d) points?%s*:%s*" .. N .. " to " .. N .. "[%a ]-damage"
local CP_ONE = "(%d) points?%s*:%s*" .. N .. "[%a ]-damage"
T.N = N

local function comboPoints(t, r)
    local any = false
    for c, a, d in t:gmatch(CP_DOT) do
        r.cpDot = r.cpDot or {}
        r.cpDot[tonumber(c)], r.cpDur, any = num(a), tonumber(d), true
    end
    if any then
        return true
    end
    for _, pat in ipairs({ CP_RANGE, CP_TO }) do
        for c, a, b in t:gmatch(pat) do
            r.cpDirect = r.cpDirect or {}
            r.cpDirect[tonumber(c)], any = (num(a) + num(b)) / 2, true
        end
        if any then
            return true
        end
    end
    for c, a in t:gmatch(CP_ONE) do
        r.cpDirect = r.cpDirect or {}
        r.cpDirect[tonumber(c)], any = num(a), true
    end
    return any
end

function T.Parse(text)
    local r = { ok = false }
    if type(text) ~= "string" or text == "" then
        return r
    end
    local t = text:gsub("[\r\n]+", " ")

    if comboPoints(t, r) then
        r.ok = true
        return r
    end

    -- Damage over time.
    local a, b, dur = t:match(OVER_RANGE)
    if a then
        r.dot, r.dotDur = (num(a) + num(b)) / 2, tonumber(dur)
    else
        a, dur = t:match(OVER_ONE)
        if a then
            r.dot, r.dotDur = num(a), tonumber(dur)
        end
    end
    if not r.dot then
        local per, every = t:match(N .. "[%a ]-damage every ([%d%.]+) sec")
        if not per then
            per, every = t:match(N .. " health every ([%d%.]+) sec")
        end
        if not per then
            per, every = t:match(N .. " health from the target to the caster every ([%d%.]+) sec")
        end
        if per then
            local d = t:match("[Ll]asts ([%d%.]+) sec") or t:match("[Ff]or ([%d%.]+) sec")
            if d then
                r.dot, r.dotDur = num(per) * tonumber(d) / tonumber(every), tonumber(d)
            end
        end
    end

    -- Weapon-based phrasing (checked before direct damage, which would misread "225% damage plus 54").
    local pct, plus = t:match("(%d+)%% damage plus " .. N)
    if pct then
        r.weaponPct, r.direct = tonumber(pct), num(plus)
    else
        pct = t:match("(%d+)%%[%a ]-weapon damage")
        if pct then
            r.weaponPct = tonumber(pct)
        end
    end
    r.bonus = num(t:match("[Ii]ncreases? [%a ]-damage by " .. N))
    r.ap = num(t:match("attack power[%a ]-by " .. N))

    -- Direct damage: what remains once the over-time phrases are removed.
    local rest = t:gsub(OVER_RANGE, ""):gsub(OVER_ONE, "")
    if not r.direct then
        a, b = rest:match(N .. " to " .. N .. "[%a ]-damage")
        if a then
            r.direct = (num(a) + num(b)) / 2
        else
            a = rest:match(N .. "[%a ]-damage")
            if a then
                r.direct = num(a)
            end
        end
    end
    -- "additional" next to a number (Claw's "27 additional damage", Multi-Shot's "an additional 30 damage") means
    -- on top of a weapon hit; Rake's "an additional 39 damage over 9 sec" was removed with its over-time phrase.
    r.additional = (rest:find(N .. " additional") or rest:find("additional " .. N)) ~= nil

    local hp, mana = t:match("[Cc]onverts " .. N .. " health into " .. N .. " mana")
    if mana then
        r.manaGain, r.healthCost = num(mana), num(hp)
    end

    r.ok = (r.direct or r.dot or r.manaGain or r.weaponPct or r.bonus or r.ap) ~= nil
    return r
end

--- The spell's description text, "" when the client has not loaded it yet (a load is then requested;
--- SPELL_DATA_LOAD_RESULT triggers a rescan in State.lua).
function T.Text(id)
    local LR = ns.LR
    local desc = LR.read(C_Spell and C_Spell.GetSpellDescription, id)
    if type(desc) == "string" and desc ~= "" then
        return desc
    end
    if C_Spell and C_Spell.RequestLoadSpellData then
        pcall(C_Spell.RequestLoadSpellData, id)
    end
    LR.tooltipPending = true
    return ""
end

return T
