-- LiteRotation/UI.lua
-- One icon: the next spell to cast. Red while out of range, green while it is not castable yet (its cooldown or
-- power). Waits and out-of-mana pauses are not shown: the icon shows the spell they lead to. Drag to move while
-- unlocked; /lrot lock to lock it.

local _, ns = ...
local LR = ns.LR

local SIZE = 52

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
    b:Hide()
    return b
end

function LR:CreateUI()
    local db = self.db
    local f = CreateFrame("Frame", "LiteRotationFrame", UIParent)
    f:SetSize(SIZE, SIZE)
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
        if LR.lastSnap and LR.lastSnap.outOfRange then
            GameTooltip:AddLine("Out of range", 1, 0.35, 0.35)
        end
        for i, s in ipairs(r.seq) do
            if s.def.kind ~= "wait" then
                GameTooltip:AddLine(("%d. %s"):format(i, s.name or s.key), 1, 1, 1)
            end
        end
        GameTooltip:AddLine(("%.1f value/sec"):format(r.value), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    f.icon = makeIcon(f, SIZE)
    f.icon:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    self.frame = f
end

function LR:SetLocked(locked)
    self.db.locked = locked
    if self.frame then
        self.frame:EnableMouse(not locked)
    end
end

-- The first real spell of the planned line, skipping waits (the sim may wait for power or a cooldown first), and
-- whether the line waits before it.
local function nextSpell(result)
    for i, s in ipairs(result.seq) do
        if s.def.kind ~= "wait" then
            return s, i > 1
        end
    end
end

-- Not castable yet: the line waits first, its own cooldown outlasts the GCD or cast under way, or power is short.
local function notReady(s, waits, snap)
    if waits then
        return true
    end
    if not snap then
        return false
    end
    local cd = snap.cds[s.cdKey or s.key] or 0
    return cd > (snap.ready or 0) + 0.05 or (s.cost or 0) > (snap.power or 0)
end

function LR:ShowResult(result, snap)
    local f = self.frame
    if not f then
        return
    end
    local b = f.icon
    local s, waits = nil, false
    if result then
        s, waits = nextSpell(result)
    end
    if not s then
        b:Hide()
        return
    end
    b.tex:SetTexture(s.icon or 134400)
    if snap and snap.outOfRange then
        b.tex:SetVertexColor(1, 0.35, 0.35) -- out of range: red
    elseif notReady(s, waits, snap) then
        b.tex:SetVertexColor(0.35, 1, 0.35) -- not castable yet (cooldown or power): green
    else
        b.tex:SetVertexColor(1, 1, 1)
    end
    b:Show()
end
