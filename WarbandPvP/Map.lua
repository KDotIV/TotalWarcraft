local _, A = ...
local TEMPLATE = "WarbandPvPMapPinTemplate"
local PRESENCE_TEMPLATE = "WarbandPvPPresencePinTemplate"
local WARBAND_TEMPLATE, GROUP_TEMPLATE = "WarbandPvPWarbandPinTemplate", "WarbandPvPWarbandGroupPinTemplate"

local function drawSwords(owner)
    owner.strokes = {}
    if type(owner.CreateLine) ~= "function" then
        owner.fallback = owner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        owner.fallback:SetPoint("CENTER"); owner.fallback:SetText("X")
        return
    end
    local segments = {
        {5,5,19,19,3}, {20,20,24,24,2}, {17,23,23,17,2},
        {23,5,9,19,3}, {8,20,4,24,2}, {5,17,11,23,2},
    }
    -- Native solid-color strokes, not sampled file textures or atlases.
    for pass = 1, 2 do
        for _, s in ipairs(segments) do
            local line = owner:CreateLine(nil, "OVERLAY", nil, pass)
            line:SetStartPoint("TOPLEFT", owner, s[1], -s[2])
            line:SetEndPoint("TOPLEFT", owner, s[3], -s[4])
            line:SetThickness(s[5] + (pass == 1 and 2 or 0))
            line:SetColorTexture(pass == 1 and .02 or 1, pass == 1 and .02 or 1, pass == 1 and .02 or 1, 1)
            if pass == 2 then owner.strokes[#owner.strokes+1] = line end
            line:Show()
        end
    end
end

local function colorSwords(owner, c)
    for _, line in ipairs(owner.strokes) do line:SetColorTexture(c[1],c[2],c[3],1); line:Show() end
    if owner.fallback then owner.fallback:SetTextColor(c[1],c[2],c[3]); owner.fallback:Show() end
end

WarbandPvPMapPinMixin = CreateFromMixins(MapCanvasPinMixin)
function WarbandPvPMapPinMixin:OnLoad()
    -- WorldMap registers exploration and fog ABOVE DEFAULT. Use its POI layer
    -- so the artwork is drawn above terrain rather than merely remaining hittable.
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1, 1)
    self:SetAlphaLimits(1, 1, 1)
    drawSwords(self)
end
function WarbandPvPMapPinMixin:OnAcquired(r, x, y)
    self.record = r
--@dev
    local c = r.test and A.testColor or A.colors[r.kind]
--@enddev
--@release     local c = A.colors[r.kind]
    colorSwords(self, c)
    self:SetPosition(x or r.x, y or r.y)
end
function WarbandPvPMapPinMixin:OnReleased()
    if self:IsMouseOver() then GameTooltip:Hide() end
    self.record = nil
    MapCanvasPinMixin.OnReleased(self)
end
function WarbandPvPMapPinMixin:OnMouseEnter()
    if self.record then A.Tooltip(self, self.record) end
end
function WarbandPvPMapPinMixin:OnMouseLeave() GameTooltip:Hide(); A.tooltipRecord=nil end
function WarbandPvPMapPinMixin:OnMouseClickAction(button)
    if button == "LeftButton" and self.record then A.ShowDetails(self.record) end
end

-- A green plus distinguishes cooperative locations from report swords.
WarbandPvPPresencePinMixin = CreateFromMixins(MapCanvasPinMixin)
function WarbandPvPPresencePinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1, 1); self:SetAlphaLimits(1, 1, 1)
    local marker = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    marker:SetPoint("CENTER"); marker:SetText("+"); marker:SetTextColor(.3, 1, .6)
    self.marker = marker
end
function WarbandPvPPresencePinMixin:OnAcquired(p, x, y)
    self.presence = p; self:SetPosition(x or p.x, y or p.y)
end
function WarbandPvPPresencePinMixin:OnReleased()
    if self:IsMouseOver() then GameTooltip:Hide() end
    self.presence = nil; MapCanvasPinMixin.OnReleased(self)
end
function WarbandPvPPresencePinMixin:OnMouseEnter()
    A.tooltipRecord = nil
    local p = self.presence
    if not p or p.expiresAt <= GetServerTime() then return end
    local function state(v) return v == "1" and "yes" or v == "0" and "no" or "unknown" end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("WBP group member: " .. A.CleanText(p.name, 128), .3, 1, .6)
    GameTooltip:AddLine(A.LocationText(p), 1, 1, 1)
    GameTooltip:AddLine("Shared PvP flag: " .. state(p.flagged) .. " | Combat: " .. state(p.combat), 1, 1, 1)
    GameTooltip:AddLine("Presence only; not confirmed PvP. Layer unknown.", .8, .8, .8, true)
    GameTooltip:AddLine("Position age: " .. math.max(0, GetServerTime() - p.updatedAt) .. "s", .7, .7, .7)
    GameTooltip:Show()
end
function WarbandPvPPresencePinMixin:OnMouseLeave() GameTooltip:Hide() end

WarbandPvPWarbandPinMixin = CreateFromMixins(MapCanvasPinMixin)
function WarbandPvPWarbandPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1,1,1); self:SetAlphaLimits(1,1,1); A.DrawWarbandIcon(self)
end
function WarbandPvPWarbandPinMixin:OnAcquired(r,x,y)
--@dev
    self.warband=r; self:SetPosition(x,y); A.ColorWarbandIcon(self,r.simulated)
--@enddev
--@release     self.warband=r; self:SetPosition(x,y); A.ColorWarbandIcon(self)
end
function WarbandPvPWarbandPinMixin:OnReleased()
    if self:IsMouseOver() then GameTooltip:Hide() end
    self.warband=nil; MapCanvasPinMixin.OnReleased(self)
end
function WarbandPvPWarbandPinMixin:OnMouseEnter() A.WarbandTooltip(self,self.warband) end
function WarbandPvPWarbandPinMixin:OnMouseLeave() GameTooltip:Hide(); A.warbands.tooltipID=nil end
function WarbandPvPWarbandPinMixin:OnMouseClickAction(button)
    if button=="LeftButton" then A.ShowWarbandDetails(self.warband) end
end
WarbandPvPWarbandGroupPinMixin=CreateFromMixins(WarbandPvPWarbandPinMixin)
function WarbandPvPWarbandGroupPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1,1,1); self:SetAlphaLimits(1,1,1)
    self.marker=self:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    self.marker:SetPoint("CENTER"); self.marker:SetTextColor(1,.8,.4)
end
function WarbandPvPWarbandGroupPinMixin:OnAcquired(data,x,y)
    self.warband=data.warband; self.group=data.group
    self.marker:SetText(tostring(data.group.slot)); self:SetPosition(x,y)
--@dev
    self.marker:SetTextColor(data.warband.simulated and .8 or 1,data.warband.simulated and .45 or .8,data.warband.simulated and 1 or .4)
--@enddev
--@release     self.marker:SetTextColor(.92,.73,.36)
end
function WarbandPvPWarbandGroupPinMixin:OnMouseEnter() A.WarbandTooltip(self,self.warband,self.group) end
function WarbandPvPWarbandGroupPinMixin:OnReleased()
    self.group=nil; WarbandPvPWarbandPinMixin.OnReleased(self)
end

local function apiCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, ...)
    if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then return end
    return a, b
end
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
function A.MapPosition(r, hostMap)
    local api = OpenMapAPI
    -- Native gamepad positioning hides pins outside the host map's 0..1 bounds.
    local gamepad = InputUtil and apiCall(InputUtil.IsGamepadUIEnabled)
    if api and api.major == 1 and gamepad ~= true and apiCall(api.IsStitched) == true then
        local u, v = apiCall(api.WorldFromMap, r.mapID, r.x, r.y)
        if finite(u) and finite(v) then
            local x, y = apiCall(api.MapFromWorld, hostMap, u, v)
            if finite(x) and finite(y) then return x, y end
        end
    end
    if r.mapID == hostMap then return r.x, r.y end
end

local Provider = CreateFromMixins(MapCanvasDataProviderMixin)
function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    self:GetMap():RemoveAllPinsByTemplate(PRESENCE_TEMPLATE)
    self:GetMap():RemoveAllPinsByTemplate(WARBAND_TEMPLATE)
    self:GetMap():RemoveAllPinsByTemplate(GROUP_TEMPLATE)
end
function Provider:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    if not map:IsShown() then return end
    for _, r in ipairs(A.List()) do
        local x, y = A.MapPosition(r, map:GetMapID())
        if x and y then map:AcquirePin(TEMPLATE, r, x, y) end
    end
    for _, p in ipairs(A.PresenceList and A.PresenceList() or {}) do
        local x, y = A.MapPosition(p, map:GetMapID())
        if x and y then map:AcquirePin(PRESENCE_TEMPLATE, p, x, y) end
    end
    for _,r in ipairs(A.WarbandList and A.WarbandList() or {}) do
        local x,y=A.MapPosition(r,map:GetMapID())
        if x and y then map:AcquirePin(WARBAND_TEMPLATE,r,x,y) end
        local w=A.warbands
        if (w.host and w.host.id==r.id) or (w.member and w.member.id==r.id) then
            for _,g in pairs(r.groups or {}) do
                if g.expiresAt>GetServerTime() then
                    local gx,gy=A.MapPosition(g,map:GetMapID())
                    if gx and gy then map:AcquirePin(GROUP_TEMPLATE,{warband=r,group=g},gx,gy) end
                end
            end
        end
    end
end

function A.LocationText(r)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r.mapID)
    return string.format("%s  /  %.1f, %.1f", info and info.name or ("Map " .. r.mapID), r.x * 100, r.y * 100)
end

function A.CurrentLocation()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
    local id = apiCall(C_Map.GetBestMapForUnit, "player")
    if not finite(id) or id < 1 or id > 100000 or id % 1 ~= 0 then return end
    local pos = apiCall(C_Map.GetPlayerMapPosition, id, "player")
    if not pos then return end
    local x, y = apiCall(function() return pos:GetXY() end)
    if not finite(x) or not finite(y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
    return {mapID = id, x = x, y = y}
end

function A.OpenMap(r)
    if InCombatLockdown() then A.Print("Open the map after combat to select this location."); return end
    if not WorldMapFrame and C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_WorldMap") end
    if not WorldMapFrame or not WorldMapFrame.SetMapID then A.Print("World map unavailable."); return end
    A.CloseWindows()
    WorldMapFrame:Show(); WorldMapFrame:SetMapID(r.mapID)
    A.AttachMap(); A.RefreshMap()
end

function A.RefreshMap()
    if A.mapProvider then A.mapProvider:RefreshAllData() end
end

function A.AttachMap()
    local api = OpenMapAPI
    if not A.openMapCallbacks and api and api.major == 1 and type(api.RegisterCallback) == "function" then
        local function refresh() A.RefreshMap() end
        local ok = pcall(function()
            api.RegisterCallback(A, "OpenMap_StitchedChanged", refresh)
        end)
        A.openMapCallbacks = ok
    end
    if A.mapAttached or not WorldMapFrame or not WorldMapFrame.AddDataProvider
        or not WorldMapFrame.AcquirePin or not WorldMapFrame.RemoveAllPinsByTemplate then return end
    A.mapProvider = CreateFromMixins(Provider)
    WorldMapFrame:AddDataProvider(A.mapProvider)
    A.mapAttached = true
    A.RefreshMap()
end

--@dev
function A.MapDebug()
    A.AttachMap()
    local map = WorldMapFrame
    if not A.mapAttached then A.Print("Native map provider unavailable."); return end
    A.Print("Native map=" .. tostring(map:GetMapID()) .. " shown=" .. tostring(map:IsShown())
        .. " pins=" .. tostring(map:GetNumActivePinsByTemplate(TEMPLATE)))
    for pin in map:EnumeratePinsByTemplate(TEMPLATE) do
        A.Print("Pin level=" .. tostring(pin:GetFrameLevel()) .. " alpha=" .. tostring(pin:GetEffectiveAlpha())
            .. " layer=" .. tostring(pin:GetFrameLevelType())
            .. " renderer=native-lines strokes=" .. tostring(#pin.strokes)
            .. " size=" .. tostring(pin:GetWidth()) .. "x" .. tostring(pin:GetHeight()))
        break
    end
end

-- An independent reference at screen center separates map layering from drawing.
function A.PinCheck()
    if not A.pinCheck then
        local f = CreateFrame("Frame", "WarbandPvPPinCheck", UIParent, "BackdropTemplate")
        f:SetSize(220,100); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
        f:SetBackdropColor(.04,.04,.05,.98)
        local text = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        text:SetPoint("TOP",0,-12); text:SetText("Pin rendering check")
        local symbol = CreateFrame("Frame",nil,f)
        symbol:SetSize(28,28); symbol:SetPoint("CENTER",0,-5)
        drawSwords(symbol); colorSwords(symbol,A.testColor)
        local hint = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        hint:SetPoint("BOTTOM",0,10); hint:SetText("/wb pincheck to close")
        A.RegisterWindow(f); f:Hide(); A.pinCheck = f
    end
    A.pinCheck:SetShown(not A.pinCheck:IsShown())
end

--@enddev
