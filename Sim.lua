-- LiteRotation/Sim.lua
-- The light simulation: try every sequence of `depth` actions from your known spells, play each forward, and keep
-- the sequence with the best value per second. Pure Lua (no game calls), so it runs in tests outside the game.
--
-- Value of a sequence, in damage:
--     damage committed (direct hits that land before the target dies; DoT ticks up to the DoT's end or the target's
--     death, minus the ticks a refresh throws away; a channel's share before the target dies; a self effect such as
--     a seal counts its whole duration, since it carries on to the next mob)
--   + powerValue * (power at the end - power at the start)     -- spending mana/energy/rage costs, regen earns
--   + cpValue    * (combo points at the end - at the start)    -- builders earn, finishers spend
--   + healValue  * (healing done - health spent)               -- Drain Life / Siphon Life heal, Life Tap costs
-- divided by the time the sequence takes. powerValue is your best filler's damage per point of power times the
-- manaWeight setting, scaled up as your power runs low; healValue is powerValue times healthWeight.
--
-- A spell entry `s` (Core.lua's scan, refreshed by State.lua's snapshot) carries: key, def, cost, castNow, gcd, cd,
-- dmgDirect (direct damage now, weapon included), dot/dotDur, cpDirect/cpDot/cpDur. `def` is the kit's definition:
-- kind ("spell", "channel", "tap", "wand"), debuff, persists, requires, consumes, shard, cp ("gen"/"finisher"),
-- nextSwing, pausesAuto, heals, channel, and the hooks value(n, s, ctx) and onCast(n, s, ctx).

local _, ns = ...
ns = ns or {}
local Sim = {}
ns.Sim = Sim

local FSR = 5
local MAX_DELAY = 1.5 -- an action may wait this long for its cooldown or power
local CP_MAX = 5
local min, max = math.min, math.max

local function copy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = v
    end
    return c
end

local function clone(st)
    return {
        t = st.t,
        power = st.power,
        fsrEnd = st.fsrEnd,
        shards = st.shards,
        cp = st.cp,
        cds = copy(st.cds),
        debuffs = copy(st.debuffs),
        rates = copy(st.rates),
        vars = copy(st.vars),
        dmg = st.dmg,
        heal = st.heal,
    }
end

-- Power regenerated from st.t to `to`: for mana, the five-second rule's rate before fsrEnd and the normal rate after;
-- for energy and rage one steady rate (regenOut).
local function advance(st, to, ctx)
    if to <= st.t then
        return
    end
    local inside = max(0, min(to, st.fsrEnd) - st.t)
    local outside = (to - st.t) - inside
    st.power = min(ctx.powerMax, st.power + inside * ctx.regenIn + outside * ctx.regenOut)
    st.t = to
end

-- When st could afford `cost`, or nil if not within `limit` seconds.
local function affordAt(st, cost, ctx, limit)
    if st.power >= cost then
        return st.t
    end
    local need = cost - st.power
    local wait = max(0, st.fsrEnd - st.t)
    local gainedBefore = wait * ctx.regenIn
    local at
    if gainedBefore >= need then
        at = st.t + (ctx.regenIn > 0 and need / ctx.regenIn or math.huge)
    elseif ctx.regenOut > 0 then
        at = st.t + wait + (need - gainedBefore) / ctx.regenOut
    else
        return nil
    end
    if at - st.t > limit then
        return nil
    end
    return at
end

-- Applies a DoT-like effect (a DoT, Hunter's Mark, a seal) from `land`; returns the damage it adds.
local function applyEffect(n, key, total, dur, land, horizon, heals)
    if not (dur and dur > 0 and key) then
        return 0, 0
    end
    local rate = (total or 0) / dur -- an effect with no damage of its own (a seal for Judgement) still counts as up
    local newEnd = land + dur
    local oldEnd = n.debuffs[key] or 0
    local oldRate = n.rates[key] or rate
    local gain = rate * max(0, min(newEnd, horizon) - min(land, horizon))
    local lost = oldRate * max(0, min(oldEnd, horizon) - land)
    n.debuffs[key], n.rates[key] = newEnd, rate
    local d = gain - lost
    return d, heals and d or 0
end

--- Plays spell s from state st. Returns the new state, or nil when s cannot be cast there.
--- `effectsOnly`: apply power, effects and cooldowns without taking time (the cast already under way).
local function play(st, s, ctx, effectsOnly)
    local def = s.def
    local n = clone(st)
    local start = n.t
    if not effectsOnly then
        local ready = n.cds[s.key] or 0
        if ready > start + MAX_DELAY then
            return nil
        end
        start = max(start, ready)
        if s.cost > 0 then
            local at = affordAt(n, s.cost, ctx, MAX_DELAY)
            if not at then
                return nil
            end
            start = max(start, at)
        end
    end
    local cast = effectsOnly and 0 or (s.castNow or 0) -- a cast under way lands at `ready`, where st.t already is
    local land = start + cast
    if def.requires and (n.debuffs[def.requires] or 0) <= land then
        return nil
    end
    if def.shard and n.shards < 1 then
        return nil
    end
    if def.kind == "wand" and not ctx.wand then
        return nil
    end
    if def.cp == "finisher" and n.cp < 1 then
        return nil
    end
    advance(n, start, ctx)

    local ttl = ctx.ttl
    local occupy
    if def.kind == "channel" then
        occupy = def.channel
    elseif def.kind == "wand" then
        occupy = ctx.wand.speed
    elseif def.nextSwing then
        occupy = 0 -- off the GCD: it rides your next swing
    else
        occupy = max(cast, s.gcd)
    end

    local dmg, heal, hpSpent = 0, 0, 0
    if def.kind == "wand" then
        dmg = ctx.wand.avg * max(0, min(occupy, ttl - start)) / ctx.wand.speed
    elseif def.kind == "channel" then
        local total = (s.dot or 0) + (s.dmgDirect or 0)
        dmg = total * max(0, min(occupy, ttl - start)) / occupy
        if def.heals then
            heal = dmg
        end
    elseif def.kind == "tap" then
        n.power = min(ctx.powerMax, n.power + (s.manaGain or 0))
        hpSpent = s.healthCost or s.manaGain or 0
    else
        local direct, dot, dur = s.dmgDirect, s.dot, s.dotDur
        if def.cp == "finisher" then
            local c = min(n.cp, CP_MAX)
            direct = s.cpDirect and s.cpDirect[c]
            dot, dur = s.cpDot and s.cpDot[c], s.cpDur or s.dotDur
        end
        if def.value then
            direct = def.value(n, s, ctx)
        end
        if direct and land < ttl then
            dmg = dmg + direct
        end
        local d, h = applyEffect(n, def.debuff, dot, dur, land, def.persists and math.huge or ttl, def.heals)
        dmg, heal = dmg + d, heal + h
        if def.consumes then
            local oldEnd = n.debuffs[def.consumes] or 0
            local rate = n.rates[def.consumes] or ctx.dotRate[def.consumes] or 0
            dmg = dmg - rate * max(0, min(oldEnd, ttl) - land)
            n.debuffs[def.consumes], n.rates[def.consumes] = nil, nil
        end
        if def.pausesAuto and ctx.autoDps then
            dmg = dmg - ctx.autoDps * cast -- Auto Shot stops while you cast
        end
        if def.shard then
            n.shards = n.shards - 1
        end
        if def.cp == "gen" then
            n.cp = min(CP_MAX, n.cp + 1)
        elseif def.cp == "finisher" then
            n.cp = 0
        end
    end
    if def.onCast then
        def.onCast(n, s, ctx)
    end

    if s.cost > 0 then
        n.power = n.power - s.cost
        if ctx.powerType == "mana" then
            n.fsrEnd = (def.kind == "channel" and start + occupy or land) + FSR
        end
    end
    if s.cd and s.cd > 0 then
        n.cds[s.key] = land + s.cd
    end
    if def.nextSwing then -- one queued at a time: the next can follow the swing that takes this one
        n.cds[s.key] = max(n.cds[s.key] or 0, start + (ctx.swing or 2))
    end
    if effectsOnly then
        return n
    end
    n.dmg = n.dmg + dmg
    n.heal = n.heal + heal - hpSpent
    advance(n, start + occupy, ctx)
    return n
end
Sim.play = play

-- A pause when nothing can be cast: one second of regen. Out of mana gets its own action and a mana potion icon,
-- so the display tells you to drink or use a potion rather than just wait.
local WAIT = { key = "wait", def = { kind = "wait" }, cost = 0, gcd = 0, name = "Wait", icon = 136106 }
local OOM = {
    key = "oom",
    def = { kind = "wait" },
    cost = 0,
    gcd = 0,
    name = "Out of mana: drink or use a mana potion",
    icon = "Interface\\Icons\\INV_Potion_76",
}
Sim.WAIT, Sim.OOM = WAIT, OOM

local function value(st, ctx)
    local dt = st.t - ctx.t0
    if dt <= 0 then
        return -math.huge
    end
    local v = st.dmg
        + ctx.powerValue * (st.power - ctx.power0)
        + ctx.healValue * st.heal
        + ctx.cpValue * (st.cp - ctx.cp0)
    return v / dt
end

-- Depth-first search; fills best.seq with the best line from st. Returns that line's value.
local function search(st, depth, ctx, line, best)
    if depth == 0 then
        local v = value(st, ctx)
        if v > best.value then
            best.value = v
            for i = 1, #line do
                best.seq[i] = line[i]
            end
            for i = #line + 1, #best.seq do
                best.seq[i] = nil
            end
        end
        return v
    end
    local any, top = false, -math.huge
    local d = #line + 1
    for _, s in ipairs(ctx.spells) do
        local n = play(st, s, ctx)
        if n then
            any = true
            line[d] = s
            local v = search(n, depth - 1, ctx, line, best)
            line[d] = nil
            if d == 1 and ctx.firsts then
                ctx.firsts[s.key] = max(ctx.firsts[s.key] or -math.huge, v)
            end
            if v > top then
                top = v
            end
        end
    end
    if not any then
        local n = clone(st)
        advance(n, n.t + 1, ctx)
        line[d] = (ctx.powerType == "mana" and st.power < ctx.minCost) and OOM or WAIT
        top = search(n, depth - 1, ctx, line, best)
        line[d] = nil
    end
    return top
end

-- A spell that can be repeated freely: its damage per point of power prices power.
local function isFiller(s)
    local def = s.def
    return def.kind == "spell"
        and not def.debuff
        and not def.requires
        and not def.reactive
        and def.cp ~= "finisher"
        and not (s.cd and s.cd > 0)
end

--- snap: from LR:Snapshot() (or a test). db: settings (manaWeight, healthWeight, depth).
--- Returns { seq = { spell, ... }, value = per-second value, firsts = { [key] = best value starting with it } }
--- (firsts is only filled while the decision log is on: db.log).
function Sim.Run(snap, db)
    local spells = snap.spells
    local dpm, anyDpm, cpBest, minCost = 0, 0, 0, math.huge
    local dotRate = {}
    for _, s in ipairs(spells) do
        local dmg = (s.dmgDirect or 0) + (s.dot or 0)
        if s.cost > 0 then
            minCost = min(minCost, s.cost)
        end
        if s.cost > 0 and dmg > 0 then
            anyDpm = max(anyDpm, dmg / s.cost)
            if isFiller(s) then
                dpm = max(dpm, dmg / s.cost)
            end
        end
        if s.def.debuff and s.dot and s.dotDur and s.dotDur > 0 then
            dotRate[s.def.debuff] = s.dot / s.dotDur
        end
        if s.def.cp == "finisher" then
            local top = ((s.cpDirect and s.cpDirect[CP_MAX]) or 0) + ((s.cpDot and s.cpDot[CP_MAX]) or 0)
            cpBest = max(cpBest, top)
        end
    end
    if dpm == 0 then
        dpm = anyDpm
    end
    local frac = snap.powerMax > 0 and min(1, snap.power / snap.powerMax) or 1
    local powerValue = (db.manaWeight or 1) * dpm * (0.25 + (1 - frac))

    local st = {
        t = 0,
        power = snap.power,
        fsrEnd = snap.fsrLeft or 0,
        shards = snap.shards or 0,
        cp = snap.cp or 0,
        cds = copy(snap.cds or {}),
        debuffs = copy(snap.debuffs or {}),
        rates = copy(snap.rates or {}),
        vars = copy(snap.vars or {}),
        dmg = 0,
        heal = 0,
    }
    local ctx = {
        spells = spells,
        ttl = snap.ttl,
        powerType = snap.powerType or "mana",
        powerMax = snap.powerMax,
        regenIn = snap.regenIn or 0,
        regenOut = snap.regenOut or 0,
        wand = snap.wand,
        autoDps = snap.autoDps,
        swing = snap.swing,
        dotRate = dotRate,
        powerValue = powerValue,
        healValue = powerValue * (db.healthWeight or 0.8),
        cpValue = cpBest / CP_MAX * 0.8, -- a combo point is worth most of its share of a full finisher
        minCost = minCost,
        -- The score of each possible first action: only collected for the decision log.
        firsts = db.log and {} or nil,
    }
    -- The cast under way lands first: its power, effects and cooldown are already decided.
    if snap.pending then
        st.t = snap.ready
        st = play(st, snap.pending, ctx, true) or st
    end
    advance(st, snap.ready, ctx)
    ctx.t0, ctx.power0, ctx.cp0 = st.t, st.power, st.cp

    local best = { value = -math.huge, seq = {} }
    search(st, db.depth or 3, ctx, {}, best)
    best.firsts = ctx.firsts or {}
    best.powerValue = powerValue
    return best
end

return Sim
