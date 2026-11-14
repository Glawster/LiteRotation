-- LiteRotation/Classes/Shaman.lua
-- The Shaman kit (mana): Lightning Bolt, the shocks and Stormstrike.
-- Rank IDs and fallback costs are WoW Forever's, as recorded in Hekili_Shaman/Shaman.lua (Frost Shock's are
-- Classic's).
--
-- Earth, Flame and Frost Shock share one 6 s cooldown (`cdGroup = "shock"`): casting one puts all three on cooldown,
-- so the simulator weighs Flame Shock's damage over time against Earth Shock's burst for the same slot. Stormstrike
-- is valued as a weapon hit. Fire Nova needs a fire totem down, so it is offered only when the game says it is usable.
--
-- Not modelled: weapon imbues (Rockbiter, Flametongue, Windfury, Frostbrand), Lightning Shield, totems, Stormstrike's
-- nature damage bonus, Elemental Mastery, Clearcasting, auto attacks, healing.

local _, ns = ...
local LR = ns.LR

-- Stormstrike's tooltip may name no number: a full weapon hit.
local function weaponHit(s)
    if not s.tipOk then
        s.weaponPct, s.tipOk = 100, true
    end
end

LR:RegisterKit("SHAMAN", {
    spells = {
        lightning_bolt = {
            kind = "spell",
            ranks = { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 },
            cost = { 15, 30, 45, 60, 85, 110, 135, 160, 190, 220 },
            cast = { 1.5, 2, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5 },
        },
        chain_lightning = { -- jumps to more enemies, and costly while leveling: off by default
            kind = "spell",
            ranks = { 421, 930, 2860, 10605 },
            cost = { 245, 360, 425, 495 },
            cast = 2,
            cd = 6,
        },
        earth_shock = {
            kind = "spell",
            ranks = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 },
            cost = { 30, 50, 85, 145, 240, 345, 450 },
            cast = 0,
            cd = 6,
            cdGroup = "shock",
        },
        flame_shock = {
            kind = "spell",
            ranks = { 8050, 8052, 8053, 10447, 10448, 29228 },
            cost = { 55, 95, 160, 250, 345, 410 },
            cast = 0,
            cd = 6,
            cdGroup = "shock",
            debuff = "flame_shock",
            dotDur = 12,
        },
        frost_shock = {
            kind = "spell",
            ranks = { 8056, 8058, 10472, 10473 },
            cost = { 115, 225, 325, 430 },
            cast = 0,
            cd = 6,
            cdGroup = "shock",
        },
        stormstrike = {
            kind = "spell",
            ranks = { 17364 },
            cost = 121,
            cast = 0,
            cd = 6,
            weapon = "melee",
            prepare = weaponHit,
        },
        fire_nova = { -- hits every enemy near your fire totem: off by default
            kind = "spell",
            ranks = { 408341, 408342, 408343, 408344, 408345 },
            cost = { 65, 120, 210, 290, 375 },
            cast = 0,
            cd = 10,
            reactive = true, -- needs a fire totem down
        },
    },

    defaultsOff = { chain_lightning = true, fire_nova = true },
})
