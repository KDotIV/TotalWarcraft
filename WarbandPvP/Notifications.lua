local _, A = ...
local function label(parent, x, y, width, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", x, y); text:SetWidth(width); text:SetJustifyH("LEFT")
    return text
end
local function surface(kind, name, w, h)
    local f = CreateFrame(kind, name, UIParent, "BackdropTemplate")
    f:SetSize(w, h); f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    f:SetBackdropColor(.045,.055,.07,.97); f:SetBackdropBorderColor(.35,.5,.65)
    return f
end
function A.CountText(r)
--@dev
    if r.test then return r.count .. " simulated participants (TEST)" end
--@enddev

    if r.countUnknown then return "Fight size unknown" end
--@dev
    return r.count .. (r.estimated and " estimated participants" or " reported participants")
--@enddev
--@release     return "Fight size unknown"
end
function A.ShowDetails(r)
    if not r or r.expiresAt <= GetServerTime() or not A.records[r.id] then return end
    if not A.details then
        local f = A.Surface("WarbandPvPDetails",580,720,"FIELD REPORT")
        A.details = f
        f.title = label(f,30,-174,520,"GameFontNormalLarge")
        f.body = label(f,30,-220,520); f.body:SetSpacing(5)
        A.Button(f,"Enemy scouting",30,-578,520,function() A.ShowEnemyScout(f.record) end)
        A.Button(f,"Show on map",30,-620,248,function() A.OpenMap(f.record) end)
        A.Button(f,"Rally to report",302,-620,248,function()
            if not f.record then return end
            local ok,msg=A.StartWarband("Report response",f.record.id); A.Print(msg)
            if ok then A.ShowWarbands() end
        end)
        f.ctaValid=function() return f.record and A.records[f.record.id] and A.records[f.record.id].expiresAt>GetServerTime() end
    end
    local f = A.details; f.record = r
    f.title:SetText(A.DisplayTitle(r))
    f.body:SetText(A.LocationText(r) .. "\n" .. A.CountText(r)
        .. "\nReported by: " .. r.reporter
        .. "\nRuleset: " .. r.ruleset .. " | Layer: unknown"
        .. "\nRally to this location, or ask the reporter for a party invite."
        .. "\nA rally marker does not prove the reporter is still there."
        .. "\n" .. A.ScoutSummary(r)
        .. (r.opposition ~= "" and "\nReported opposition: " .. r.opposition or "")
        .. "\n" .. r.note
        .. "\n" .. (r.expiresAt <= GetServerTime() and "Expired report" or "Expires in " .. (r.expiresAt - GetServerTime()) .. "s"))
    f:Show()
end
function A.RefreshReportSurfaces()
    local now = GetServerTime()
    for _, f in ipairs({A.toast or false, A.details or false}) do
        if f and f.record then
            local r = A.records[f.record.id]
            if not r or r.expiresAt <= now then f.record=nil; if f.ctaWindow then A.InvalidateWindow(f) else f:Hide() end
            elseif f == A.details and f:IsShown() then A.ShowDetails(r) end
        end
    end
    -- A report hovered from a list row may outlive its row unless explicitly cleared.
    if A.tooltipRecord and (not A.records[A.tooltipRecord.id] or A.tooltipRecord.expiresAt <= now) then
        GameTooltip:Hide(); A.tooltipRecord=nil
    end
    if A.RefreshScoutUI then A.RefreshScoutUI() end
end
function A.ShowToast(r)
    if A.ActiveWindow() then return end
    if not A.toast then
        local f = surface("Button",nil,300,88)
        A.toast = f; f:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-30,-180)
        f:SetFrameStrata("HIGH"); f:RegisterForClicks("LeftButtonUp","RightButtonUp")
        f.title=label(f,12,-10,275,"GameFontNormal")
        f.location=label(f,12,-31,275)
        f.hint=label(f,12,-53,275)
        f:SetScript("OnClick",function(self,button)
            if button == "LeftButton" and self.record then A.ShowDetails(self.record) end
            self:Hide()
        end)
    end
    local f=A.toast; f.record=r
    f.title:SetText(A.DisplayTitle(r))
    f.location:SetText(A.LocationText(r))
    f.hint:SetText(A.CountText(r) .. "\nClick: details   Right-click: dismiss")
    if A.toastTimer then A.toastTimer:Cancel() end
    f:Show(); A.toastTimer=C_Timer.NewTimer(10,function() f:Hide(); A.toastTimer=nil end)
end
