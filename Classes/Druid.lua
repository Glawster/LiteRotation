-- LiteRotation/Classes/Druid.lua
-- The Druid kit: recommendations for the form you are in (it never suggests shifting).
--   caster / Moonkin: Wrath, Starfire, Moonfire, Insect Swarm (mana)
--   Cat:  Claw, Rake and Shred build combo points; Rip and Ferocious Bite spend them (energy, 1 s GCD)
--   Bear: Maul on the next swing, Swipe, Primal Bite, Lacerate (rage)
-- Rank IDs and fallback costs are WoW Forever's, as recorded in Hekili_Druid/Druid.lua (Primal Bite is Forever's
-- renamed Mangle; Lacerate's rank 1 is a talent there).
--
-- Not modelled: shifting, Faerie Fire, Pounce / Ravage / Prowl (stealth openers), Tiger's Fury, Enrage, Clearcasting,
-- Lacerate's stacks, healing.

local _, ns = ...
local LR = ns.LR
local read = LR.read

local CASTER = { caster = true, moonkin = true }
local CAT = { cat = true }
local BEAR = { bear = true }

-- The form's spell ID (GetShapeshiftFormInfo's 4th return) to the kit's form key.
local FORM_BY_SPELL = {
    [768] = "cat",
    [5487] = "bear",
    [9634] = "bear", -- Dire Bear Form
    [24858] = "moonkin",
    [783] = "travel",
    [1066] = "aquatic",
}

LR:RegisterKit("DRUID", {
    Form = function()
        local i = read(GetShapeshiftForm)
        if not i or i == 0 then
            return "caster"
        end
        local _, _, _, spellID = read(GetShapeshiftFormInfo, i)
        return FORM_BY_SPELL[spellID] or "other"
    end,
    Power = function(form)
        if form == "cat" then
            return "energy"
        elseif form == "bear" then
            return "rage"
        end
        return "mana"
    end,

    spells = {
        -- Caster and Moonkin
        wrath = {
            kind = "spell",
            forms = CASTER,
            ranks = { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 },
            cost = { 10, 20, 40, 50, 70, 80, 100, 120 },
            cast = { 1.5, 1.7, 2, 2, 2, 2, 2, 2 },
        },
        starfire = {
            kind = "spell",
            forms = CASTER,
            ranks = { 2912, 8949, 8950, 8951, 9875, 9876, 25298 },
            cost = { 95, 135, 180, 230, 275, 315, 340 },
            cast = 3.5,
        },
        moonfire = {
            kind = "spell",
            forms = CASTER,
            ranks = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 },
            cost = { 25, 50, 75, 105, 150, 190, 235, 280, 325, 375 },
            cast = 0,
            debuff = "moonfire",
            dotDur = { 9, 12, 12, 12, 12, 12, 12, 12, 12, 12 },
        },
        insect_swarm = {
            kind = "spell",
            forms = CASTER,
            ranks = { 5570, 24974, 24975, 24976, 24977 },
            cost = { 45, 85, 100, 140, 160 },
            cast = 0,
            debuff = "insect_swarm",
            dotDur = 12,
        },

        -- Cat
        claw = {
            kind = "spell",
            forms = CAT,
            power = "energy",
            ranks = { 1082, 3029, 5201, 9849, 9850 },
            cost = 45,
            cast = 0,
            gcd = 1,
            weapon = "melee",
            cp = "gen",
        },
        shred = { -- needs you behind the target, which the addon can't see: off by default
            kind = "spell",
            forms = CAT,
            power = "energy",
            ranks = { 5221, 6800, 8992, 9829, 9830 },
            cost = 60,
            cast = 0,
            gcd = 1,
            weapon = "melee",
            cp = "gen",
        },
        rake = {
            kind = "spell",
            forms = CAT,
            power = "energy",
            ranks = { 1822, 1823, 1824, 9904, 1289140 },
            cost = 40,
            cast = 0,
            gcd = 1,
            cp = "gen",
            debuff = "rake",
            dotDur = 9,
        },
        rip = {
            kind = "spell",
            forms = CAT,
            power = "energy",
            ranks = { 1079, 9492, 9493, 9752, 9894, 9896, 1289141 },
            cost = 30,
            cast = 0,
            gcd = 1,
            cp = "finisher",
            debuff = "rip",
            dotDur = 12,
        },
        ferocious_bite = {
            kind = "spell",
            forms = CAT,
            power = "energy",
            ranks = { 1328618, 22568, 22827, 22828, 22829, 31018, 1289142 },
            cost = 35,
            cast = 0,
            gcd = 1,
            cp = "finisher",
        },

        -- Bear
        maul = {
            kind = "spell",
            forms = BEAR,
            power = "rage",
            ranks = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 },
            cost = 15,
            cast = 0,
            nextSwing = true,
        },
        swipe = {
            kind = "spell",
            forms = BEAR,
            power = "rage",
            ranks = { 779, 780, 769, 9754, 9908 },
            cost = 20,
            cast = 0,
        },
        primal_bite = { -- Forever's Mangle
            kind = "spell",
            forms = BEAR,
            power = "rage",
            ranks = { 407995, 1238069, 1238070, 1238073 },
            cost = 20,
            cast = 0,
            cd = 6,
            weapon = "melee",
        },
        lacerate = {
            kind = "spell",
            forms = BEAR,
            power = "rage",
            ranks = { 1328617, 1328616, 414644, 1235826, 1235827 },
            cost = 15,
            cast = 0,
            debuff = "lacerate",
            dotDur = 15,
        },
    },

    defaultsOff = { shred = true },
})
