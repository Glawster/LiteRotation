-- LiteRotation/Classes/Warrior.lua
-- The Warrior kit: rage, stances, and recommendations for the stance you are in (it never suggests a swap).
--   any stance: Heroic Strike (next swing), Mortal Strike, Bloodthirst, Slam, Battle Shout, Demoralizing Shout,
--               Victory Rush
--   Battle:     Overpower (after a dodge), Rend, Execute, Thunder Clap (off by default)
--   Defensive:  Revenge (after a block, dodge or parry), Shield Slam, Rend
--   Berserker:  Whirlwind, Execute
-- Rank IDs and fallback costs are WoW Forever's, as recorded in Hekili_Warrior/Warrior.lua.
--
-- Spells usable only after a trigger (Overpower, Revenge, Victory Rush, Execute below 20% health, Shield Slam with a
-- shield) are offered when the game says they are usable. Execute converts the rage left after its cost into extra
-- damage; the kit values that and charges for spending all your rage. Battle Shout is valued as its attack power
-- bonus (14 attack power = 1 damage per second) for its whole duration, since it carries on to the next mob;
-- Demoralizing Shout as the damage its attack power cut prevents while the target lives.
--
-- Not modelled: stance swaps, Charge, Intercept, Bloodrage, Berserker Rage, Sweeping Strikes, Death Wish, Sunder
-- Armor, Hamstring, rage refunds on a miss, Execute spending all rage in the rage estimate.

local _, ns = ...
local LR = ns.LR
local T = ns.Tooltip
local N, num = T.N, T.num
local read = LR.read

-- The stance's spell ID (GetShapeshiftFormInfo's 4th return) to the kit's form key.
local STANCE_BY_SPELL = {
    [2457] = "battle",
    [71] = "defensive",
    [2458] = "berserker",
}

local BATTLE = { battle = true }
local DEFENSIVE = { defensive = true }
local BERSERKER = { berserker = true }
local NOT_BERSERKER = { battle = true, defensive = true }
local NOT_DEFENSIVE = { battle = true, berserker = true }

-- Execute: "converting each extra point of rage into 3 additional damage".
local function executeParse(s, text)
    local t = (text or ""):gsub("[\r\n]+", " ")
    s.perRage = num(t:match("into " .. N .. " additional damage"))
        or num(t:match("each extra point of rage into " .. N))
end

local function executeValue(n, s)
    return (s.dmgDirect or s.direct or 0) + (s.perRage or 0) * math.max(0, n.power - s.cost)
end

-- Execute spends all your rage: leave just its cost for the simulator to subtract.
local function executeOnCast(n, s)
    n.power = math.min(n.power, s.cost)
end

-- A strike whose tooltip names no number (Whirlwind's "weapon damage"): a full weapon hit.
local function weaponHit(s)
    if not s.tipOk then
        s.weaponPct, s.tipOk = 100, true
    end
end

LR:RegisterKit("WARRIOR", {
    power = "rage",
    Form = function()
        local i = read(GetShapeshiftForm)
        if not i or i == 0 then
            return "none"
        end
        local _, _, _, spellID = read(GetShapeshiftFormInfo, i)
        return STANCE_BY_SPELL[spellID] or "other"
    end,
    Power = function()
        return "rage"
    end,

    spells = {
        heroic_strike = {
            kind = "spell",
            ranks = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 },
            cost = 15,
            cast = 0,
            nextSwing = true,
            cdGroup = "next_swing", -- one queued strike at a time, shared with Cleave
        },
        cleave = { -- two targets: off by default
            kind = "spell",
            ranks = { 845, 7369, 11608, 11609, 20569 },
            cost = 20,
            cast = 0,
            nextSwing = true,
            cdGroup = "next_swing",
        },
        mortal_strike = {
            kind = "spell",
            ranks = { 12294, 21551, 21552, 21553 },
            cost = 30,
            cast = 0,
            cd = 6,
            weapon = "melee",
        },
        bloodthirst = {
            kind = "spell",
            ranks = { 23881, 23892, 23893, 23894 },
            cost = 30,
            cast = 0,
            cd = 6,
        },
        slam = {
            kind = "spell",
            ranks = { 1240193, 1464, 8820, 11604, 11605, 1310196, 1310197, 1310198, 1310199, 1310200 },
            cost = 15,
            cast = 1.5,
            weapon = "melee",
        },
        whirlwind = {
            kind = "spell",
            forms = BERSERKER,
            ranks = { 1680 },
            cost = 25,
            cast = 0,
            cd = 10,
            weapon = "melee",
            prepare = weaponHit,
        },
        overpower = {
            kind = "spell",
            forms = BATTLE,
            ranks = { 7384, 7887, 11584, 11585 },
            cost = 5,
            cast = 0,
            cd = 5,
            weapon = "melee",
            reactive = true, -- only after the target dodges
        },
        revenge = {
            kind = "spell",
            forms = DEFENSIVE,
            ranks = { 6572, 6574, 7379, 11600, 11601, 25288 },
            cost = 5,
            cast = 0,
            cd = 5,
            reactive = true, -- only after you block, dodge or parry
        },
        shield_slam = {
            kind = "spell",
            ranks = { 23922, 23923, 23924, 23925 },
            cost = 20,
            cast = 0,
            cd = 6,
            reactive = true, -- needs a shield: the game says when it is usable
        },
        execute = {
            kind = "spell",
            forms = NOT_DEFENSIVE,
            ranks = { 5308, 20658, 20660, 20661, 20662 },
            cost = 15,
            cast = 0,
            reactive = true, -- only below 20% health: the game says when it is usable
            parse = executeParse,
            value = executeValue,
            onCast = executeOnCast,
        },
        victory_rush = {
            kind = "spell",
            ranks = { 402927 },
            cost = 0,
            cast = 0,
            cd = 30,
            reactive = true, -- only after a kill
        },
        rend = {
            kind = "spell",
            forms = NOT_BERSERKER,
            ranks = { 772, 6546, 6547, 6548, 11572, 11573, 11574 },
            cost = 10,
            cast = 0,
            debuff = "rend",
            dotDur = { 9, 12, 15, 18, 21, 21, 21 },
        },
        thunder_clap = { -- hits every enemy nearby: off by default
            kind = "spell",
            forms = NOT_BERSERKER,
            ranks = { 6343, 8198, 8204, 8205, 11580, 11581 },
            cost = 20,
            cast = 0,
            cd = 6,
        },
        battle_shout = {
            kind = "spell",
            ranks = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 },
            cost = 10,
            cast = 0,
            debuff = "battle_shout",
            self = true,
            persists = true,
            dotDur = 120,
            update = function(s)
                s.dot = s.ap and (s.ap / 14) * s.dotDur or nil
            end,
        },
        demoralizing_shout = {
            kind = "spell",
            ranks = { 1160, 6190, 11554, 11555, 11556 },
            cost = 10,
            cast = 0,
            debuff = "demoralizing_shout",
            dotDur = 45,
            update = function(s)
                s.dot = s.ap and (s.ap / 14) * s.dotDur or nil
            end,
        },
    },

    defaultsOff = { cleave = true, thunder_clap = true },
})
