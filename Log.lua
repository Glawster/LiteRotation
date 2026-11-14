-- LiteRotation/Log.lua
-- The decision log: while it is on (/lrot log), every spell you cast is recorded with what LiteRotation recommended
-- at that moment and why: your power, the target's expected lifetime, the score of each possible first action and
-- the planned line. /lrot why prints the last 10 entries. It is off by default; while off, nothing is recorded and
-- the simulator skips scoring each first action separately.

local _, ns = ...
local LR = ns.LR
local Print = LR.Print

local MAX_ENTRIES = 10
local ALTERNATIVES = 3 -- other first actions listed per entry

LR.decisions = {} -- newest last; this session only

local function nameOf(key)
    local s = LR.spellByKey and LR.spellByKey[key]
    if s and s.name then
        return s.name
    end
    if key == "wait" then
        return "Wait"
    elseif key == "oom" then
        return "Out of mana"
    end
    return key
end

local function score(v)
    return v and ("%.1f/s"):format(v) or "-"
end

-- One log line from the current recommendation, for the spell just cast.
local function describe(cast, result, snap)
    local cols = {}
    local rec = result.seq[1]
    local firsts = result.firsts or {}

    if rec and rec.key == cast.key then
        cols[#cols + 1] = ("|cff66ff66%s|r: recommended (%s)"):format(nameOf(cast.key), score(firsts[cast.key]))
    else
        local castScore = firsts[cast.key]
        cols[#cols + 1] = ("|cffffaa00%s|r: %s; recommended %s (%s)"):format(
            nameOf(cast.key),
            castScore and ("scored " .. score(castScore)) or "not considered (off, out of range or unaffordable)",
            rec and nameOf(rec.key) or "nothing",
            rec and score(firsts[rec.key]) or "-"
        )
    end

    cols[#cols + 1] = ("%s %d/%d%s, ttl %ds"):format(
        snap.powerType,
        math.floor(snap.power),
        snap.powerMax,
        snap.powerPlain and "" or " est.",
        snap.ttl
    )
    if snap.cp and snap.cp > 0 then
        cols[#cols + 1] = ("combo points %d"):format(snap.cp)
    end

    local keys = {}
    for k in pairs(firsts) do
        if k ~= cast.key and not (rec and k == rec.key) then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b)
        return firsts[a] > firsts[b]
    end)
    local alt = {}
    for i = 1, math.min(ALTERNATIVES, #keys) do
        alt[i] = ("%s %s"):format(nameOf(keys[i]), score(firsts[keys[i]]))
    end
    if #alt > 0 then
        cols[#cols + 1] = "others: " .. table.concat(alt, ", ")
    end

    local plan = {}
    for i, s in ipairs(result.seq) do
        plan[i] = nameOf(s.key)
    end
    cols[#cols + 1] = "plan: " .. table.concat(plan, " > ")
    return table.concat(cols, "; ")
end

--- Record a cast. Called by State.lua only while db.log is on.
function LR:LogCast(s)
    local result, snap = self.result, self.lastSnap
    local entry
    if result and snap then
        entry = describe(s, result, snap)
    else
        entry = ("%s: no recommendation at the time (no attackable target)"):format(nameOf(s.key))
    end
    local log = self.decisions
    log[#log + 1] = { time = date("%H:%M:%S"), text = entry }
    if #log > MAX_ENTRIES then
        table.remove(log, 1)
    end
end

function LR:SetLogging(on)
    self.db.log = on
    if not on then
        self.decisions = {}
    end
    Print("decision log %s.", on and "on: cast some spells, then /lrot why" or "off")
end

function LR:PrintLog()
    if not self.db.log then
        Print("the decision log is off: /lrot log turns it on, then /lrot why shows your last %d casts.", MAX_ENTRIES)
        return
    end
    if #self.decisions == 0 then
        Print("no casts logged yet.")
        return
    end
    Print("last %d casts, oldest first:", #self.decisions)
    for _, e in ipairs(self.decisions) do
        Print("%s %s", e.time, e.text)
    end
end
