-- LiteRotation/UI.lua
-- One large icon (cast this next) and two smaller ones (the rest of the planned line). Drag to move while unlocked;
-- /lrot lock to lock it.

local _, ns = ...
local LR = ns.LR

local SIZES = { 52, 34, 34 }

local function makeIcon(parent, size)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size, size)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetColorTexture(0, 0, 0, 0.8)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.cd:SetDrawEdge(false)
    b.cd:SetHideCountdownNumbers(true)
    b:Hide()
    return b
end

function LR:CreateUI()
    local db = self.db
    local f = CreateFrame("Frame", "LiteRotationFrame", UIParent)
    f:SetSize(SIZES[1] + SIZES[2] + SIZES[3] + 12, SIZES[1])
    f:SetScale(db.scale or 1)
    local p = db.point
    f:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    f:SetMovable(true)
    f:EnableMouse(not db.locked)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local a, _, rp, x, y = frame:GetPoint()
        db.point = { a, "UIParent", rp, x, y }
    end)
    f:SetScript("OnEnter", function(frame)
        local r = LR.result
        if not r or not r.seq[1] then
            return
        end
        GameTooltip:SetOwner(frame, "ANCHOR_TOP")
        GameTooltip:AddLine("LiteRotation")
        for i, s in ipairs(r.seq) do
            GameTooltip:AddLine(("%d. %s"):format(i, s.name or s.key), 1, 1, 1)
        end
        GameTooltip:AddLine(("%.1f value/sec"):format(r.value), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    f.icons = {}
    local x = 0
    for i, size in ipairs(SIZES) do
        local b = makeIcon(f, size)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
        x = x + size + 6
        if i > 1 then
            b:SetAlpha(0.75)
        end
        f.icons[i] = b
    end
    self.frame = f
end

function LR:SetLocked(locked)
    self.db.locked = locked
    if self.frame then
        self.frame:EnableMouse(not locked)
    end
end

function LR:ShowResult(result, snap)
    local f = self.frame
    if not f then
        return
    end
    if not result or not result.seq[1] then
        for _, b in ipairs(f.icons) do
            b:Hide()
        end
        return
    end
    for i, b in ipairs(f.icons) do
        local s = result.seq[i]
        if s then
            b.tex:SetTexture(s.icon or 134400)
            b:Show()
        else
            b:Hide()
        end
    end
    -- The main icon's swirl: how long until it can be cast (GCD, cast in progress, its cooldown).
    if snap then
        local wait = snap.ready
        local first = result.seq[1]
        local cdKey = first and (first.cdKey or first.key)
        if cdKey and snap.cds[cdKey] then
            wait = math.max(wait, snap.cds[cdKey])
        end
        local b = f.icons[1]
        if wait > 0.05 then
            if not b.cdUntil or math.abs(b.cdUntil - (snap.now + wait)) > 0.1 then
                b.cd:SetCooldown(snap.now, wait)
                b.cdUntil = snap.now + wait
            end
        else
            b.cd:Clear()
            b.cdUntil = nil
        end
    end
end
