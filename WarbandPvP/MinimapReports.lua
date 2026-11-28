local _,A=...
local M={pins={},cache={},entries={},groups={},count=0,status="waiting for login"}
A.minimapReports=M
local SIZE,OVERLAP,FAST,SLOW=18,18,.1,1
local function secret(v) return issecretvalue and issecretvalue(v) end
local function read(fn,...)
    if type(fn)~="function" then return end
    local ok,a,b,c,d=pcall(fn,...)
    if ok and not secret(a) and not secret(b) and not secret(c) and not secret(d) then return a,b,c,d end
end
local function finite(v) return not secret(v) and type(v)=="number" and v==v and math.abs(v)<1e8 end
local function identifier(v,minimum) return finite(v) and v>=minimum and v==math.floor(v) end
local function status(value)
    if M.status==value then return end
    M.status=value
    if A.Trace and (not M.lastTrace or GetTime()-M.lastTrace>=5) then
        M.lastTrace=GetTime(); A.Trace("MINIMAP_REPORTS",value)
    end
end
local function stop()
    if M.timer then M.timer:Cancel(); M.timer=nil end
    M.interval=nil
end
local function release(pin)
    if M.hover==pin then GameTooltip:Hide(); A.tooltipRecord=nil; M.hover=nil end
    pin.record=nil; pin.activity=nil; pin:Hide()
end
local function hide()
    for _,pin in ipairs(M.pins) do if pin.record then release(pin) end end
    M.count=0; M.dirty=true
end
local function pause(reason) stop(); hide(); status(reason) end
local function tooltip(pin)
    local r=pin.record
    if not r or not A.records[r.id] or r.expiresAt<=GetServerTime() then return end
    A.Tooltip(pin,r,pin.activity)
    GameTooltip:AddLine("Reported "..math.max(0,GetServerTime()-r.updatedAt).."s ago",.7,.7,.7)
    GameTooltip:Show(); M.tipSecond=GetServerTime()
end
local function acquire(i)
    local pin=M.pins[i]
    if not pin then
        pin=CreateFrame("Button",nil,M.host); M.pins[i]=pin
        pin:SetSize(SIZE,SIZE); pin:EnableMouse(true); pin:RegisterForClicks("LeftButtonUp")
        pin:SetScript("OnEnter",function(self) M.hover=self; tooltip(self) end)
        pin:SetScript("OnLeave",function(self)
            if M.hover==self then GameTooltip:Hide(); A.tooltipRecord=nil; M.hover=nil end
        end)
        pin:SetScript("OnClick",A.UIAction("minimap report",function(self,button)
            if button=="LeftButton" and self.record then A.ShowDetails(self.record) end
        end))
    end
    return pin
end
local function world(mapID,x,y)
    local vector=read(CreateVector2D,x,y)
    if not vector then return end
    local id,pos=read(C_Map and C_Map.GetWorldPosFromMapPos,mapID,vector)
    if not identifier(id,0) or not pos then return end
    local north,west=read(function() return pos:GetXY() end)
    if finite(north) and finite(west) then return id,north,west end
end
local function outdoorMap(mapID)
    local info=read(C_Map and C_Map.GetMapInfo,mapID)
    local kind=info and read(function() return info.mapType end)
    local types=Enum and Enum.UIMapType
    return types and kind~=nil and (kind==types.Zone or kind==types.Continent) or false
end
local function position()
    local mapID=read(C_Map and C_Map.GetBestMapForUnit,"player")
    if not identifier(mapID,1) then return end
    local north,west,_,id=read(UnitPosition,"player")
    if not identifier(id,0) or not finite(north) or not finite(west) then
        local loc=read(A.CurrentLocation)
        if not loc then return end
        id,north,west=world(loc.mapID,loc.x,loc.y); mapID=loc.mapID
    end
    if id then return id,north,west,mapID end
end
local function supported()
    return M.host and C_Map and type(C_Map.GetWorldPosFromMapPos)=="function"
        and C_Minimap and type(C_Minimap.GetViewRadius)=="function" and type(CreateVector2D)=="function"
end
local tick
local function schedule(interval)
    if M.timer and M.interval==interval then return end
    stop(); M.interval=interval
    local timer
    timer=C_Timer.NewTicker(interval,function() if M.timer==timer then tick() end end)
    M.timer=timer
end
local function rotated()
    local value=read(C_CVar and C_CVar.GetCVarBool or GetCVarBool,"rotateMinimap")
    if type(value)~="boolean" then
        value=read(C_CVar and C_CVar.GetCVar or GetCVar,"rotateMinimap")
        if value~="0" and value~="1" then return end
        value=value=="1"
    end
    if value and C_Minimap.IsRotateMinimapIgnored then
        local ignored=read(C_Minimap.IsRotateMinimapIgnored)
        if type(ignored)~="boolean" then return end
        value=not ignored
    end
    return value
end
local function compatible(entry,mapID)
    return entry.record.mapID==mapID or (entry.outdoor and M.outdoor)
end
local function sameKind(a,b)
    if a.faction~=b.faction or a.ruleset~=b.ruleset then return false end
    --@dev
    if (a.test==true)~=(b.test==true) or (a.demo==true)~=(b.demo==true) then return false end
    --@enddev
    return true
end
local function draw(id,north,west,mapID,radius,width,height,facing,shape,level)
    local rx,ry=width/2,height/2
    -- Leave room for the whole icon, including at the circular boundary.
    local margin=(SIZE/2*(shape=="ROUND" and math.sqrt(2) or 1)+2)/math.min(rx,ry)
    local limit=1-margin
    local sin,cos=math.sin(facing),math.cos(facing)
    local count=0
    for _,entry in ipairs(M.entries) do
        local r=entry.record
        if entry.world==id and compatible(entry,mapID) then
            -- Native world x increases north and world y increases west.
            local east,south=west-entry.west,north-entry.north
            local x=(east*cos-south*sin)/radius
            local y=-(east*sin+south*cos)/radius
            local inside=limit>0 and (shape=="SQUARE" and math.max(math.abs(x),math.abs(y))<=limit
                or shape=="ROUND" and x*x+y*y<=limit*limit)
            if inside then
                x,y=x*rx,y*ry
                local group
                for i=1,count do
                    local g=M.groups[i]
                    if sameKind(g.record,r) and (x-g.x)^2+(y-g.y)^2<OVERLAP*OVERLAP then group=g; break end
                end
                if not group then
                    count=count+1; group=M.groups[count]
                    if not group then group={reporters={}}; M.groups[count]=group end
                    for key in pairs(group.reporters) do group.reporters[key]=nil end
                    group.record=r; group.x=x; group.y=y; group.count=0
                end
                local key=A.WB.Key(r.reporter)
                if key and not group.reporters[key] then group.reporters[key]=true; group.count=group.count+1 end
            end
        end
    end
    for i=1,count do
        local group=M.groups[i]; local pin=acquire(i)
        if pin.record~=group.record and M.hover==pin then GameTooltip:Hide(); A.tooltipRecord=nil; M.hover=nil end
        pin.record=group.record; pin.activity=group
        group.label=group.count>1 and (group.count.." nearby reporters") or ""
        local color=A.colors[group.record.kind] or A.colors.report
        --@dev
        color=group.record.test and A.testColor or color
        --@enddev
        if pin.artColor~=color then A.DrawReportMarker(pin,SIZE,color); pin.artColor=color end
        if pin.baseLevel~=level then pin:SetFrameLevel(level+5); pin.baseLevel=level end
        pin:ClearAllPoints(); pin:SetPoint("CENTER",M.host,"CENTER",group.x,group.y); pin:Show()
    end
    for i=count+1,#M.pins do if M.pins[i].record then release(M.pins[i]) end end
    M.count=count
end
tick=function()
    if not A.db or not A.db.minimapReports or M.stopping then pause("off"); return end
    if M.loading then pause("changing world"); return end
    if not supported() then pause("API unavailable"); return end
    if read(M.host.IsVisible,M.host)~=true then pause("hidden"); return end
    if #M.entries==0 then pause("no reports"); return end
    if M.expires and GetServerTime()>=M.expires then A.RefreshMinimapReports(); return end
    if read(IsInInstance)~=false then pause("outside world map"); return end
    local id,north,west,mapID=position()
    if not id then hide(); status("position unavailable"); schedule(SLOW); return end
    if M.mapID~=mapID then M.outdoor=outdoorMap(mapID) end
    local candidate,unmapped=false,false
    for _,entry in ipairs(M.entries) do
        if not entry.world then unmapped=true end
        if entry.world==id and compatible(entry,mapID) then candidate=true; break end
    end
    if not candidate then pause(unmapped and "report coordinates unavailable" or "no reports in this area"); return end
    local radius=read(C_Minimap.GetViewRadius)
    local width,height=read(M.host.GetWidth,M.host),read(M.host.GetHeight,M.host)
    local level=read(M.host.GetFrameLevel,M.host)
    local rotate=rotated()
    local facing=0
    if rotate==true then facing=read(GetPlayerFacing) end
    if not finite(radius) or radius<=0 or not finite(width) or width<=SIZE+4 or not finite(height) or height<=SIZE+4
        or not finite(level) or rotate==nil or not finite(facing) then
        hide(); status("view unavailable"); schedule(SLOW); return
    end
    local shape=type(GetMinimapShape)=="function" and read(GetMinimapShape) or "ROUND"
    -- Unknown masks use a conservative circle; the native mask is never changed.
    if shape~="SQUARE" then shape="ROUND" end
    if M.dirty or M.world~=id or M.north~=north or M.west~=west or M.mapID~=mapID or M.radius~=radius
        or M.width~=width or M.height~=height or M.facing~=facing or M.shape~=shape or M.level~=level then
        draw(id,north,west,mapID,radius,width,height,facing,shape,level)
        M.world,M.north,M.west,M.mapID=id,north,west,mapID
        M.radius,M.width,M.height,M.facing,M.shape,M.level=radius,width,height,facing,shape,level
        M.dirty=false
    end
    if M.hover and M.tipSecond~=GetServerTime() then tooltip(M.hover) end
    status("ready"); schedule(M.count>0 and FAST or SLOW)
end
local function attach()
    if M.host or not Minimap then return end
    M.host=Minimap
    M.host:HookScript("OnHide",function() pause("hidden") end)
    M.host:HookScript("OnShow",function() A.RefreshMinimapReports() end)
    M.host:HookScript("OnSizeChanged",function() M.dirty=true; tick() end)
end
function A.RefreshMinimapReports(invalidate)
    if not M.events or not A.db then return end
    attach()
    if invalidate then M.cache={} end
    if not A.db.minimapReports or M.stopping then pause("off"); return end
    if M.loading then pause("changing world"); return end
    if not supported() then pause("API unavailable"); return end
    if read(M.host.IsVisible,M.host)~=true then pause("hidden"); return end
    local entries,cache=M.entries,M.cache
    for i=#entries,1,-1 do entries[i]=nil end
    M.expires=nil
    for _,r in ipairs(A.List()) do
        local allowed=true
        --@dev
        allowed=not r.test or A.testMode==true
        --@enddev
        if allowed then
            local e=cache[r.id]
            if not e or not e.world or e.mapID~=r.mapID or e.x~=r.x or e.y~=r.y then
                local id,north,west=world(r.mapID,r.x,r.y)
                e={world=id,north=north,west=west,mapID=r.mapID,x=r.x,y=r.y,outdoor=outdoorMap(r.mapID)}
                cache[r.id]=e
            end
            e.record=r; entries[#entries+1]=e
            M.expires=math.min(M.expires or r.expiresAt,r.expiresAt)
        end
    end
    for key,e in pairs(cache) do if not A.records[key] or e.record.expiresAt<=GetServerTime() then cache[key]=nil end end
    M.dirty=true; tick()
end
function A.SetMinimapReportsEnabled(enabled)
    A.db.minimapReports=enabled==true
    A.RefreshMinimapReports()
    if A.RefreshHome then A.RefreshHome() end
end
function A.MinimapReportStatus()
    return M.status..(M.status=="ready" and (" ("..M.count.." visible)") or "")
end
function A.InitMinimapReports()
    if M.events then return end
    A.db.minimapReports=A.db.minimapReports~=false
    local f=CreateFrame("Frame"); M.events=f
    for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_LOGOUT","PLAYER_REGEN_ENABLED",
        "ZONE_CHANGED","ZONE_CHANGED_INDOORS","ZONE_CHANGED_NEW_AREA","MINIMAP_ZONE_CHANGED","MINIMAP_UPDATE_ZOOM",
        "CVAR_UPDATE","DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED","SHARD_TRANSFER_IMMINENT","SHARD_TRANSFER","SHARD_TRANSFER_CANCELLED"}) do
        pcall(f.RegisterEvent,f,event)
    end
    f:SetScript("OnEvent",function(_,event,cvar)
        if event=="PLAYER_LOGOUT" then M.stopping=true; pause("logged out"); return end
        if event=="PLAYER_LEAVING_WORLD" or event=="SHARD_TRANSFER_IMMINENT" then M.loading=true; pause("changing world"); return end
        if event=="CVAR_UPDATE" and (secret(cvar) or (cvar~="rotateMinimap" and cvar~="ROTATE_MINIMAP")) then return end
        if event=="PLAYER_ENTERING_WORLD" or event=="SHARD_TRANSFER" or event=="SHARD_TRANSFER_CANCELLED" then M.loading=false end
        A.RefreshMinimapReports(event=="PLAYER_ENTERING_WORLD")
    end)
    A.RefreshMinimapReports()
end
