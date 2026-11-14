-- LiteRotation/Classes/Paladin.lua
-- The Paladin kit (melee leveling: Retribution or Protection). Rank IDs and fallback costs are WoW Forever's, as
-- recorded in Hekili_Paladin/Paladin.lua.
--
-- Seals are effects on yourself (`self`, `persists`): one at a time (they share the effect key "seal"), worth their
-- extra damage per swing for their whole 30 s, since a seal carries on to the next mob. A seal's tooltip gives two
-- numbers this kit reads: the damage it adds to each swing (perHit; Seal of Command's "70% weapon damage" proc is
-- valued at 7 procs a minute) and the damage its Judgement deals (judge). On Forever Judgement does not consume the
-- seal (Hekili's research), so Judgement is simply that damage, off the GCD, whenever a seal is up.
--
-- Not modelled: Seal of the Crusader and Seal of Fury (no damage of their own in this model), Holy Shield, blessings,
-- auras, Sanctified Judgement's refund, the judgement debuffs.

local _, ns = ...
local LR = ns.LR
local T = ns.Tooltip
local N, num = T.N, T.num

local SEAL_DUR = 30
local COMMAND_PPM = 7 -- Seal of Command's procs per minute (Classic)

-- Reads a seal's tooltip: the sentence about unleashing / judging it gives the Judgement damage; the rest gives the
-- damage added to each swing.
local function sealParse(s, text)
    local t = (text or ""):gsub("[\r\n]+", " ")
    s.direct, s.dot, s.bonus, s.additional = nil, nil, nil, nil
    local judgeSentence
    for sentence in t:gmatch("[^%.]+") do
        if sentence:find("[Uu]nleash") or sentence:find("[Jj]udge") then
            judgeSentence = sentence
            break
        end
    end
    local rest = t
    if judgeSentence then
        local a, b = judgeSentence:match(N .. " to " .. N)
        if a then
            s.judge = (num(a) + num(b)) / 2
        else
            s.judge = num(judgeSentence:match(N .. "[%a ]-damage"))
        end
        local i, j = t:find(judgeSentence, 1, true)
        rest = t:sub(1, i - 1) .. t:sub(j + 1)
    end
    local a, b = rest:match(N .. " to " .. N .. "[%a ]-damage")
    if a then
        s.perHit = (num(a) + num(b)) / 2
    else
        s.perHit = num(rest:match(N .. "[%a ]-damage"))
    end
    s.weaponPct = tonumber(rest:match("(%d+)%%[%a ]-weapon damage"))
    s.dotDur = SEAL_DUR
    s.tipOk = (s.perHit or s.weaponPct or s.judge) ~= nil
end

-- A seal's worth per second with your weapon now, as the effect's total over its duration.
local function sealUpdate(s, _, W)
    local perSec = 0
    if s.perHit and W.mhSpeed then
        perSec = perSec + s.perHit / W.mhSpeed
    end
    if s.weaponPct and W.mhAvg then
        perSec = perSec + COMMAND_PPM / 60 * s.weaponPct / 100 * W.mhAvg
    end
    s.dot = perSec > 0 and perSec * SEAL_DUR or nil
end

-- In the simulation, the seal just cast sets what Judgement will deal.
local function sealOnCast(n, s)
    n.vars.sealJudge = s.judge
end

local function seal(ranks, cost)
    return {
        kind = "spell",
        ranks = ranks,
        cost = cost,
        cast = 0,
        debuff = "seal",
        self = true,
        persists = true,
        parse = sealParse,
        update = sealUpdate,
        onCast = sealOnCast,
    }
end

LR:RegisterKit("PALADIN", {
    spells = {
        seal_of_righteousness = seal(
            { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 },
            { 20, 20, 40, 60, 90, 120, 140, 170, 200 }
        ),
        seal_of_command = seal({ 20375, 20915, 20918, 20919, 20920 }, { 65, 110, 140, 180, 210 }),
        judgement = {
            kind = "spell",
            ranks = { 20271 },
            cost = 30,
            cast = 0,
            gcd = false,
            requires = "seal",
            value = function(n)
                return n.vars.sealJudge
            end,
            prepare = function(s)
                s.tipOk = true -- its damage is the seal's
            end,
        },
        holy_strike = { -- Forever's melee strike
            kind = "spell",
            ranks = { 679, 678, 1866, 680, 2495, 5569, 10332, 10333 },
            cost = { 5, 9, 12, 14, 16, 17, 19, 20 },
            cast = 0,
            weapon = "melee",
        },
        exorcism = {
            kind = "spell",
            ranks = { 879, 5614, 5615, 10312, 10313, 10314, 415068, 415069, 415070, 415071, 415072, 415073 },
            cost = { 85, 135, 180, 235, 285, 345, 85, 135, 180, 235, 285, 345 },
            cast = 0,
            cd = 15,
            -- ranks 1-6 only hit Undead and Demons; Forever's later ranks hit anything
            creature = { Undead = true, Demon = true },
            creatureUpTo = 6,
        },
        hammer_of_wrath = {
            kind = "spell",
            ranks = { 24275, 24274, 24239 },
            cost = { 295, 360, 425 },
            cast = 1,
            cd = 6,
            reactive = true, -- only below 20% health: the game says when it is usable
        },
        holy_shock = {
            kind = "spell",
            ranks = { 1311606, 20473, 20929, 20930 },
            cost = { 160, 225, 275, 325 },
            cast = 0,
            cd = 10,
        },
        consecration = {
            kind = "spell",
            ranks = { 26573, 20116, 20922, 20923, 20924 },
            cost = { 135, 235, 320, 435, 565 },
            cast = 0,
            cd = 8,
            debuff = "consecration",
            dotDur = 8,
        },
    },

    -- Consecration is mostly for groups of mobs and costs a lot of mana while leveling.
    defaultsOff = { consecration = true },

    -- Judgement deals the damage of the seal you have up.
    Snapshot = function(snap, S, lr)
        local src = S.self.src.seal
        local s = src and lr.spellByKey and lr.spellByKey[src]
        if s and snap.debuffs.seal then
            snap.vars.sealJudge = s.judge
        end
    end,
})
