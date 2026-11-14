-- LiteRotation/Sim.lua
-- The light simulation: try every sequence of `depth` actions from your known spells, play each forward, and keep
-- the sequence with the best value per second. Pure Lua (no game calls), so it runs in tests outside the game.
--
-- Value of a sequence, in damage:
--     damage committed (direct hits that land before the target dies; DoT ticks up to the DoT's end or the target's
--     death, minus the ticks a refresh throws away; a channel's share before the target dies)
--   + manaValue  * (mana at the end - mana at the start)       -- spending mana costs, regen earns
--   + healValue  * (healing done - health spent)               -- Drain Life / Siphon Life heal, Life Tap costs
-- divided by the time the sequence takes. manaValue is your best spell's damage per mana times the manaWeight
-- setting, scaled up as your mana runs low; healValue is manaValue times healthWeight.

local _, ns = ...
ns = ns or {}
local Sim = {}
ns.Sim = Sim

local GCD = 1.5
local FSR = 5
local MAX_DELAY = 1.5 -- an action may wait this long for its cooldown or mana
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
        mana = st.mana,
        fsrEnd = st.fsrEnd,
        shards = st.shards,
        cds = copy(st.cds),
        debuffs = copy(st.debuffs),
        dmg = st.dmg,
        heal = st.heal,
    }
end

-- Mana regenerated from st.t to `to`: the five-second rule's rate before fsrEnd, the normal rate after.
local function advance(st, to, ctx)
    if to <= st.t then
        return
    end
    local inside = max(0, min(to, st.fsrEnd) - st.t)
    local outside = (to - st.t) - inside
    st.mana = min(ctx.manaMax, st.mana + inside * ctx.regenIn + outside * ctx.regenOut)
    st.t = to
end

-- When st could afford `cost`, or nil if not within `limit` seconds.
local function affordAt(st, cost, ctx, limit)
    if st.mana >= cost then
        return st.t
    end
    local need = cost - st.mana
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

--- Plays spell s from state st. Returns the new state, or nil when s cannot be cast there.
--- `effectsOnly`: apply mana, debuffs and cooldowns without taking time (the cast already under way).
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
    if def.requires and not ((n.debuffs[def.requires] or 0) > land) then
        return nil
    end
    if def.shard and n.shards < 1 then
        return nil
    end
    if def.kind == "wand" and not ctx.wand then
        return nil
    end
    advance(n, start, ctx)

    local ttl = ctx.ttl
    local occupy
    if def.kind == "channel" then
        occupy = def.channel
    elseif def.kind == "wand" then
        occupy = ctx.wand.speed
    else
        occupy = max(cast, s.gcd)
    end

    local dmg, heal, hpSpent = 0, 0, 0
    if def.kind == "wand" then
        dmg = ctx.wand.avg * max(0, min(occupy, ttl - start)) / ctx.wand.speed
    elseif def.kind == "channel" then
        local total = (s.dot or 0) + (s.direct or 0)
        dmg = total * max(0, min(occupy, ttl - start)) / occupy
        if def.heals then
            heal = dmg
        end
    elseif def.kind == "tap" then
        n.mana = min(ctx.manaMax, n.mana + (s.manaGain or 0))
        hpSpent = s.healthCost or s.manaGain or 0
    else
        if s.direct and land < ttl then
            dmg = dmg + s.direct
        end
        if s.dot and s.dotDur and s.dotDur > 0 and def.debuff then
            local rate = s.dot / s.dotDur
            local newEnd = land + s.dotDur
            local oldEnd = n.debuffs[def.debuff] or 0
            local gain = rate * max(0, min(newEnd, ttl) - min(land, ttl))
            local lost = rate * max(0, min(oldEnd, ttl) - land)
            dmg = dmg + gain - lost
            if def.heals then
                heal = heal + gain - lost
            end
            n.debuffs[def.debuff] = newEnd
        end
        if def.consumes then
            local oldEnd = n.debuffs[def.consumes] or 0
            local rate = ctx.dotRate[def.consumes] or 0
            dmg = dmg - rate * max(0, min(oldEnd, ttl) - land)
            n.debuffs[def.consumes] = nil
        end
        if def.shard then
            n.shards = n.shards - 1
        end
    end

    if s.cost > 0 then
        n.mana = n.mana - s.cost
        n.fsrEnd = (def.kind == "channel" and start + occupy or land) + FSR
    end
    if s.cd and s.cd > 0 then
        n.cds[s.key] = land + s.cd
    end
    if effectsOnly then
        return n
    end
    n.dmg = n.dmg + dmg
    n.heal = n.heal + heal - hpSpent
    advance(n, start + occupy, ctx)
    return n
end

-- A pause when nothing can be cast (out of mana, no wand): one second of regen.
local WAIT = { key = "wait", def = { kind = "wait" }, cost = 0, gcd = 0, name = "Wait", icon = 136106 }

local function value(st, ctx)
    local dt = st.t - ctx.t0
    if dt <= 0 then
        return -math.huge
    end
    local v = st.dmg + ctx.manaValue * (st.mana - ctx.mana0) + ctx.healValue * st.heal
    return v / dt
end

-- Depth-first search; fills best[1..depth] with the best line from st. Returns that line's value.
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
            if d == 1 then
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
        line[d] = WAIT
        top = search(n, depth - 1, ctx, line, best)
        line[d] = nil
    end
    return top
end

--- snap: from LR:Snapshot() (or a test). db: settings (manaWeight, healthWeight, depth).
--- Returns { seq = { spell, ... }, value = per-second value, firsts = { [key] = best value starting with it } }.
function Sim.Run(snap, db)
    local spells = snap.spells
    -- What a point of mana is worth: the damage per mana of your best repeatable filler (a direct-damage spell with
    -- no cooldown and no DoT slot), because spare mana ends up there. A DoT's high efficiency is capped by its one
    -- slot per target, so it must not set the price. With no filler known, any mana spell's.
    local dpm, anyDpm = 0, 0
    local dotRate = {}
    for _, s in ipairs(spells) do
        local dmg = (s.direct or 0) + (s.dot or 0)
        if s.cost > 0 and dmg > 0 then
            anyDpm = max(anyDpm, dmg / s.cost)
            if not s.def.debuff and not (s.cd and s.cd > 0) and s.def.kind == "spell" and not s.def.requires then
                dpm = max(dpm, dmg / s.cost)
            end
        end
        if s.def.debuff and s.dot and s.dotDur then
            dotRate[s.def.debuff] = s.dot / s.dotDur
        end
    end
    if dpm == 0 then
        dpm = anyDpm
    end
    local frac = snap.manaMax > 0 and min(1, snap.mana / snap.manaMax) or 1
    local manaValue = (db.manaWeight or 1) * dpm * (0.25 + (1 - frac))

    local st = {
        t = 0,
        mana = snap.mana,
        fsrEnd = snap.fsrLeft,
        shards = snap.shards or 0,
        cds = copy(snap.cds),
        debuffs = copy(snap.debuffs),
        dmg = 0,
        heal = 0,
    }
    local ctx = {
        spells = spells,
        ttl = snap.ttl,
        manaMax = snap.manaMax,
        regenIn = snap.regenIn or 0,
        regenOut = snap.regenOut or 0,
        wand = snap.wand,
        dotRate = dotRate,
        manaValue = manaValue,
        healValue = manaValue * (db.healthWeight or 0.8),
        firsts = {},
    }
    -- The cast under way lands first: its mana, DoT and cooldown are already decided.
    if snap.pending then
        st.t = snap.ready
        st = play(st, snap.pending, ctx, true) or st
    end
    advance(st, snap.ready, ctx)
    ctx.t0, ctx.mana0 = st.t, st.mana

    local best = { value = -math.huge, seq = {} }
    search(st, db.depth or 3, ctx, {}, best)
    best.firsts = ctx.firsts
    best.manaValue = manaValue
    return best
end

return Sim
