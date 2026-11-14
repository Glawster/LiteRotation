-- LiteRotation/Tooltip.lua
-- Reads a spell's damage from its tooltip description (English client). The parse is plain Lua with no game calls,
-- so tests can run it outside the game.
--
-- Shapes understood (Classic wording):
--   direct        "causing 13 to 18 Shadow damage", "for 11 Fire damage", "causes 301 damage"
--   over time     "40 Shadow damage over 12 sec", "20 to 30 Fire damage over 15 sec"
--   per tick      "15 damage every 3 sec ... Lasts 30 sec", "Transfers 10 health every 1 sec ... Lasts 5 sec",
--                 "Transfers 15 health from the target to the caster every 3 sec. Lasts 30 sec."
--   Life Tap      "Converts 30 health into 30 mana."
-- Result: { ok, direct, dot, dotDur, manaGain, healthCost } (damage as an average; dot as its total).

local _, ns = ...
local T = {}
ns.Tooltip = T

local function num(s)
    return s and tonumber((s:gsub(",", "")))
end

local OVER_RANGE = "(%d[%d,]*) to (%d[%d,]*) %a* ?damage over ([%d%.]+) sec"
local OVER_ONE = "(%d[%d,]*) %a* ?damage over ([%d%.]+) sec"

function T.Parse(text)
    local r = { ok = false }
    if type(text) ~= "string" or text == "" then
        return r
    end
    local t = text:gsub("[\r\n]+", " ")

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
        local per, every = t:match("(%d[%d,]*) %a* ?damage every ([%d%.]+) sec")
        if not per then
            per, every = t:match("(%d[%d,]*) health every ([%d%.]+) sec")
        end
        if not per then
            per, every = t:match("(%d[%d,]*) health from the target to the caster every ([%d%.]+) sec")
        end
        if per then
            local d = t:match("[Ll]asts ([%d%.]+) sec") or t:match("[Ff]or ([%d%.]+) sec")
            if d then
                r.dot, r.dotDur = num(per) * tonumber(d) / tonumber(every), tonumber(d)
            end
        end
    end

    -- Direct damage: what remains once the over-time phrases are removed.
    local rest = t:gsub(OVER_RANGE, ""):gsub(OVER_ONE, "")
    a, b = rest:match("(%d[%d,]*) to (%d[%d,]*) %a* ?damage")
    if a then
        r.direct = (num(a) + num(b)) / 2
    else
        a = rest:match("(%d[%d,]*) %a* ?damage")
        if a then
            r.direct = num(a)
        end
    end

    local hp, mana = t:match("[Cc]onverts (%d[%d,]*) health into (%d[%d,]*) mana")
    if mana then
        r.manaGain, r.healthCost = num(mana), num(hp)
    end

    r.ok = (r.direct or r.dot or r.manaGain) ~= nil
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
