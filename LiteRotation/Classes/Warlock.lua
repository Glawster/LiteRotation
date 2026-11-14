-- LiteRotation/Classes/Warlock.lua
-- The Warlock kit: which spells exist (every rank's ID), what kind of action each is, and the mechanics a tooltip
-- cannot say. Damage numbers come from the tooltips at run time; costs and cast times come from the client, with the
-- tables here as fallbacks. Rank IDs and fallback costs are WoW Forever's, as recorded in Hekili_Warlock/Warlock.lua.
--
-- kind: "spell"   direct and/or damage over time, from the tooltip (debuff = the target aura it leaves)
--       "channel" damage spread over a channel of `channel` seconds (heals = it also heals you)
--       "tap"     Life Tap: health into mana
--       "wand"    Shoot: auto-repeat wand, damage from your wand
-- requires = a debuff of ours that must be on the target; consumes = a debuff the cast removes; shard = needs a
-- Soul Shard. cd overrides the client's base cooldown when given.

local _, ns = ...
local LR = ns.LR

LR:RegisterKit("WARLOCK", {
    spells = {
        shadow_bolt = {
            kind = "spell",
            ranks = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 },
            cost = { 25, 40, 70, 110, 160, 210, 265, 315, 370, 380 },
            cast = { 1.7, 2.2, 2.8, 3, 3, 3, 3, 3, 3, 3 },
            travel = true,
        },
        immolate = {
            kind = "spell",
            ranks = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 },
            cost = { 25, 45, 90, 155, 220, 295, 370, 380 },
            cast = 2,
            debuff = "immolate",
            dotDur = 15,
        },
        corruption = {
            kind = "spell",
            ranks = { 172, 6222, 6223, 7648, 11671, 11672, 25311 },
            cost = { 35, 55, 100, 160, 225, 290, 340 },
            cast = 2,
            debuff = "corruption",
            dotDur = { 12, 15, 18, 18, 18, 18, 18 },
        },
        bane_of_agony = {
            kind = "spell",
            ranks = { 980, 1014, 6217, 11711, 11712, 11713 },
            cost = { 25, 50, 90, 130, 170, 215 },
            cast = 0,
            debuff = "bane", -- one Bane per target
            dotDur = 24,
        },
        siphon_life = {
            kind = "spell",
            ranks = { 18265, 18879, 18880, 18881 },
            cost = { 150, 205, 285, 365 },
            cast = 0,
            debuff = "siphon_life",
            dotDur = 30,
            heals = true,
        },
        drain_life = {
            kind = "channel",
            ranks = { 689, 699, 709, 7651, 11699, 11700 },
            cost = { 55, 85, 135, 185, 240, 300 },
            channel = 5,
            heals = true,
        },
        drain_soul = {
            kind = "channel",
            ranks = { 1120, 8288, 8289, 11675 },
            cost = { 55, 125, 210, 290 },
            channel = 15,
        },
        wrack = { -- Forever's own channel
            kind = "channel",
            ranks = { 1316697 },
            cost = 200,
            channel = 6,
        },
        searing_pain = {
            kind = "spell",
            ranks = { 5676, 17919, 17920, 17921, 17922, 17923 },
            cost = { 45, 68, 91, 118, 141, 168 },
            cast = 1.5,
        },
        incinerate = { -- Forever's own
            kind = "spell",
            ranks = { 412758, 1293812, 1293813 },
            cost = { 205, 265, 325 },
            cast = 2.5,
            travel = true,
        },
        conflagrate = {
            kind = "spell",
            ranks = { 1293817, 1293818, 17962, 18930, 18931, 18932 },
            cost = { 100, 130, 165, 200, 230, 255 },
            cast = 0,
            cd = 10,
            requires = "immolate",
            consumes = "immolate",
        },
        death_coil = {
            kind = "spell",
            ranks = { 6789, 17925, 17926 },
            cost = { 435, 525, 600 },
            cast = 0,
            cd = 120,
        },
        shadowburn = {
            kind = "spell",
            ranks = { 17877, 18867, 18868, 18869, 18870, 18871 },
            cost = { 105, 130, 190, 245, 305, 365 },
            cast = 0,
            cd = 15,
            shard = true,
        },
        soul_fire = {
            kind = "spell",
            ranks = { 6353, 17924 },
            cost = { 305, 335 },
            cast = 6,
            cd = 60,
            shard = true,
            travel = true,
        },
        life_tap = {
            kind = "tap",
            ranks = { 1454, 1455, 1456, 11687, 11688, 11689 },
            cost = 0,
            cast = 0,
        },
        shoot = {
            kind = "wand",
            ranks = { 5019 },
            cost = 0,
            cast = 0,
            gcd = false,
            prepare = function(s)
                s.tipOk = true -- its damage is the wand's, read at each update
            end,
        },
    },

    -- Off until you turn them on (/lrot toggle <spell>): long cooldowns you may want for emergencies, and the
    -- Soul Shard spenders.
    defaultsOff = { death_coil = true, shadowburn = true, soul_fire = true, drain_soul = true },

    -- Instant Shadow Bolt from Nightfall (Shadow Trance), when the player's auras are readable.
    procs = { shadow_trance = 17941 },
    SOUL_SHARD = 6265,
})
