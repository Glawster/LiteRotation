-- LiteRotation/Core.lua
-- Namespace, secret-safe reads, saved settings, the class kit registry and the spellbook scan.
--
-- WoW Forever hides many values from addons ("secret values": mana, health, some GUIDs and cooldowns, at least in
-- combat). Every read of game state goes through LR.read / LR.plain, which turn a secret or erroring answer into nil,
-- so each caller has an explicit fallback instead of a Lua error.

local _, ns = ...
local LR = {}
ns.LR = LR
_G.LiteRotation = LR -- for /dump and debugging

LR.kits = {}

---------------------------------------------------------------------------------------------------------------------
-- Secret-safe reads
---------------------------------------------------------------------------------------------------------------------

local issecret = _G.issecretvalue or function()
    return false
end

--- v itself when readable, nil when secret.
function LR.plain(v)
    if issecret(v) then
        return nil
    end
    return v
end
local plain = LR.plain

--- Calls fn(...) protected; returns up to six results, each nil if secret (or all nil on error / missing fn).
function LR.read(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then
        return nil
    end
    return plain(a), plain(b), plain(c), plain(d), plain(e), plain(f)
end

--- A field of a table answer, nil if the table or the field is secret.
function LR.field(t, k)
    if t == nil or issecret(t) or type(t) ~= "table" then
        return nil
    end
    local ok, v = pcall(function()
        return t[k]
    end)
    if not ok then
        return nil
    end
    return plain(v)
end

function LR.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffLiteRotation|r: " .. msg)
end

---------------------------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------------------------

LR.defaults = {
    point = { "CENTER", "UIParent", "CENTER", 0, -180 },
    scale = 1,
    locked = false,
    onlyWithTarget = true,
    -- Expected lifetime (s) of a target by classification; health is secret, so this is a guess you can tune.
    ttl = { normal = 18, elite = 45, rare = 45, rareelite = 60, worldboss = 180 },
    -- How much a point of mana is worth, as a share of your best spell's damage per mana. Higher = more frugal
    -- (more wanding / fewer Shadow Bolts); lower = burn mana.
    manaWeight = 1.0,
    -- How much a point of health is worth relative to a point of mana (Life Tap's price, Drain Life's healing).
    healthWeight = 0.8,
    depth = 3, -- actions looked ahead
    disabled = {}, -- spell keys the player turned off: [key] = true
}

local function fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                fill(dst[k], v)
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" and k ~= "point" and k ~= "disabled" then
            fill(dst[k], v)
        end
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Class kits
---------------------------------------------------------------------------------------------------------------------

--- A class file registers its kit: { spells = { key = def, ... }, defaultsOff = { key = true }, ... }.
function LR:RegisterKit(class, kit)
    self.kits[class] = kit
end

-- The highest known rank of a rank list: index, spellID (0, nil when none known).
local function knownRank(ids)
    local IsSpellKnown = C_SpellBook and C_SpellBook.IsSpellKnown
    for i = #ids, 1, -1 do
        local k = LR.read(IsSpellKnown, ids[i])
        if k == nil and _G.IsSpellKnown then
            k = LR.read(_G.IsSpellKnown, ids[i])
        end
        if k then
            return i, ids[i]
        end
    end
    return 0, nil
end
LR.knownRank = knownRank

local function byRank(v, r)
    if type(v) == "table" then
        return v[r] or v[#v]
    end
    return v
end
LR.byRank = byRank

--- The spell's power cost from the client (mana), nil if unreadable.
local function clientCost(id)
    local costs = LR.read(C_Spell and C_Spell.GetSpellPowerCost, id)
    if type(costs) ~= "table" then
        return nil
    end
    for _, c in ipairs(costs) do
        local ty, cost = LR.field(c, "type"), LR.field(c, "cost")
        if ty == 0 and type(cost) == "number" then
            return cost
        end
    end
    return nil
end

--- Cast time in seconds from the client (includes talents and haste), nil if unreadable.
local function clientCast(id)
    local info = LR.read(C_Spell and C_Spell.GetSpellInfo, id)
    local ms = LR.field(info, "castTime")
    if type(ms) == "number" then
        return ms / 1000
    end
    return nil
end
LR.clientCast = clientCast

--- Base cooldown in seconds from the client, nil if unreadable.
local function clientCooldown(id)
    local ms = LR.read(_G.GetSpellBaseCooldown, id)
    if type(ms) == "number" then
        return ms / 1000
    end
    return nil
end

--- Rebuilds LR.spells: one entry per kit spell you know, at your highest rank, with its numbers.
--- Each entry: key, def, id, rank, name, icon, cost, cast, cd, gcd, and the tooltip's damage fields.
function LR:ScanSpells()
    local kit = self.kit
    if not kit then
        return
    end
    local spells, byId = {}, {}
    for key, def in pairs(kit.spells) do
        local rank, id = knownRank(def.ranks)
        if rank > 0 then
            local s = { key = key, def = def, id = id, rank = rank }
            local info = LR.read(C_Spell.GetSpellInfo, id)
            s.name = LR.field(info, "name") or key
            s.icon = LR.field(info, "iconID") or 134400
            s.cost = clientCost(id) or byRank(def.cost, rank) or 0
            s.baseCast = byRank(def.cast, rank) or 0
            s.cd = byRank(def.cd, rank) or clientCooldown(id) or 0
            s.gcd = def.gcd == false and 0 or 1.5
            local tip = ns.Tooltip.Parse(ns.Tooltip.Text(id))
            s.direct, s.dot, s.dotDur, s.manaGain, s.healthCost = tip.direct, tip.dot, tip.dotDur, tip.manaGain, tip.healthCost
            s.tipOk = tip.ok
            if def.dotDur then -- the kit's duration wins (tooltips round or omit it)
                s.dotDur = byRank(def.dotDur, rank)
            end
            if def.prepare then
                def.prepare(s)
            end
            spells[#spells + 1] = s
            for _, rid in ipairs(def.ranks) do
                byId[rid] = s
            end
        end
    end
    table.sort(spells, function(a, b)
        return a.key < b.key
    end)
    self.spells, self.spellById = spells, byId
    if kit.OnScan then
        kit.OnScan(self)
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "LiteRotation" then
        LiteRotationDB = LiteRotationDB or {}
        fill(LiteRotationDB, LR.defaults)
        LR.db = LiteRotationDB
    elseif event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        LR.class = class
        LR.kit = LR.kits[class]
        if not LR.kit then
            LR.Print("no kit for %s yet; idle.", tostring(class))
            return
        end
        -- First run for this kit: its default-off spells (cooldowns, shard spenders) start disabled.
        LR.db.seenDefaults = LR.db.seenDefaults or {}
        if not LR.db.seenDefaults[class] then
            for key in pairs(LR.kit.defaultsOff or {}) do
                LR.db.disabled[key] = true
            end
            LR.db.seenDefaults[class] = true
        end
        LR:ScanSpells()
        LR:StartState()
        LR:CreateUI()
    end
end)
