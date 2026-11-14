-- LiteRotation/Classes/Hunter.lua
-- The Hunter kit. On Forever the Hunter spends mana (not focus). Rank IDs and fallback costs are WoW Forever's, as
-- recorded in Hekili_Hunter/Hunter.lua.
--
-- Auto Shot runs by itself and is never recommended; casting Aimed Shot or Multi-Shot pauses it, so those are charged
-- the Auto Shot damage their cast time costs (`pausesAuto`). Shots need range and strikes need melee: spells the game
-- says are out of range are left out. Hunter's Mark is valued as its attack power bonus on your ranged attacks
-- (14 attack power = 1 damage per second) for as long as the target lives.
--
-- Not modelled: the pet, aspects, traps, stings other than Serpent Sting, Rapid Fire, Summon Hawk, Wing Clip.

local _, ns = ...
local LR = ns.LR

LR:RegisterKit("HUNTER", {
    autoShot = true,
    spells = {
        hunters_mark = {
            kind = "spell",
            ranks = { 1130, 14323, 14324, 14325, 1213268 },
            cost = { 15, 30, 45, 60, 60 },
            cast = 0,
            debuff = "hunters_mark",
            dotDur = 120,
            update = function(s)
                s.dot = s.ap and (s.ap / 14) * s.dotDur or nil
            end,
        },
        serpent_sting = {
            kind = "spell",
            ranks = { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 },
            cost = { 15, 30, 50, 80, 115, 150, 190, 230, 250 },
            cast = 0,
            debuff = "serpent_sting",
            dotDur = 15,
        },
        arcane_shot = {
            kind = "spell",
            ranks = { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 },
            cost = { 25, 35, 50, 80, 105, 135, 160, 190 },
            cast = 0,
            cd = 6,
        },
        aimed_shot = {
            kind = "spell",
            ranks = { 19434, 20900, 20901, 20902, 20903, 20904 },
            cost = { 75, 115, 160, 210, 260, 310 },
            cast = 3,
            cd = 6,
            weapon = "ranged",
            pausesAuto = true,
        },
        multi_shot = {
            kind = "spell",
            ranks = { 2643 },
            cost = 60,
            cast = 0.5,
            cd = 6,
            weapon = "ranged",
            pausesAuto = true,
        },
        raptor_strike = {
            kind = "spell",
            ranks = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 },
            cost = { 10, 25, 35, 45, 55, 70, 85, 100 },
            cast = 0,
            cd = 6,
            nextSwing = true,
        },
        mongoose_bite = {
            kind = "spell",
            ranks = { 1495, 14269, 14270, 14271 },
            cost = { 30, 40, 50, 65 },
            cast = 0,
            cd = 5,
            reactive = true, -- only after the target dodges: the game says when it is usable
        },
    },

    -- Multi-Shot shines on groups and costs a lot of mana while leveling.
    defaultsOff = { multi_shot = true },
})
