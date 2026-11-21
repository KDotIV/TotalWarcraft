local _,A=...
local P,W=A.WB,A.warbands
local function label(parent,x,y,width,font)
    local t=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT",x,y); t:SetWidth(width); t:SetJustifyH("LEFT"); return t
end
local function button(parent,text,x,y,width,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT",x,y); b:SetSize(width,24); b:SetText(text); b:SetScript("OnClick",fn); return b
end
function A.DrawWarbandIcon(owner)
    owner.warbandStrokes={}
    -- Native geometry keeps the approved 28x28 silhouette above map fog without
    -- a file-texture dependency. Banner, axe head/shaft, sword and cross guard.
    local parts={
        {14,3,14,14,1.4}, {15,4,18,4,3,true},
        {8,8,22,24,2.2}, {4,7,7,5,4}, {4,9,7,10,4},
        {6,24,10,19,2.4}, {10,17,21,5,3}, {7,16,13,21,2},
    }
    if type(owner.CreateLine)~="function" then
        local t=owner:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); t:SetPoint("CENTER"); t:SetText("W"); return
    end
    for _,s in ipairs(parts) do for pass=1,2 do
        local l=owner:CreateLine(nil,"OVERLAY",nil,pass)
        l:SetStartPoint("TOPLEFT",owner,s[1],-s[2]); l:SetEndPoint("TOPLEFT",owner,s[3],-s[4])
        l:SetThickness(s[5]+(pass==1 and 2 or 0))
        if pass==1 then l:SetColorTexture(.025,.03,.035,1)
        elseif s[6] then l:SetColorTexture(.72,.37,.22,1)
        else l:SetColorTexture(.9,.77,.49,1) end
        if pass==2 then owner.warbandStrokes[#owner.warbandStrokes+1]={line=l,banner=s[6]} end
        l:Show()
    end end
end
--@dev
function A.ColorWarbandIcon(owner,simulated)
--@enddev
--@release function A.ColorWarbandIcon(owner)
    for _,s in ipairs(owner.warbandStrokes or {}) do
--@dev
        if simulated then s.line:SetColorTexture(.8,.45,1,1)
        elseif s.banner then s.line:SetColorTexture(.72,.37,.22,1)
--@enddev
--@release         if s.banner then s.line:SetColorTexture(.72,.19,.12,1)
        else s.line:SetColorTexture(.9,.77,.49,1) end
    end
end
function A.WarbandTooltip(owner,r,group)
    if not r or r.expiresAt<=GetServerTime() then return end
    A.tooltipRecord=nil; W.tooltipID=r.id
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    GameTooltip:AddLine(A.WarbandDisplayTitle(r)..(group and (" - Group "..group.slot) or ""),.95,.8,.45)
    GameTooltip:AddLine(A.LocationText(group or r),1,1,1)
    GameTooltip:AddLine("Organizer: "..r.owner,.8,.8,.8)
    GameTooltip:AddLine(r.status.." | "..(r.recruiting and "Recruiting" or "Recruiting closed"),1,1,1)
    GameTooltip:AddLine(A.WarbandCountText(r),1,1,1,true)
    if group then GameTooltip:AddLine("Party: "..A.WarbandGroupCountText(r,group),1,1,1) end
--@dev
    GameTooltip:AddLine(r.simulated and "TEST: dummy roster; real host positions. No PvP/layer evidence." or "Potential activity; not confirmed PvP. Layer unverified.",.8,.8,.8,true)
--@enddev
--@release     GameTooltip:AddLine("Potential activity; not confirmed PvP. Layer unverified.",.8,.8,.8,true)
    GameTooltip:AddLine("Updated "..math.max(0,GetServerTime()-(group or r).updatedAt).."s ago",.7,.7,.7)
    GameTooltip:Show()
end

function A.ShowWarbandDetails(r)
    if not r or not W.records[r.id] or r.expiresAt<=GetServerTime() then return end
    if not W.details then
        local f=A.Surface("WarbandPvPWarbandDetails",580,720,"WARBAND ORDERS"); W.details=f
        f.title=label(f,30,-170,520,"GameFontNormalLarge"); f.body=label(f,30,-210,520); f.body:SetSpacing(4)
        label(f,30,-550,520):SetText(A.ScoutDisclosure)
        button(f,"Show rally on map",30,-578,248,function() if f.record then A.OpenMap(f.record) end end)
        f.join=button(f,"Join warband",302,-578,248,function() if f.record then local _,msg=A.JoinWarband(f.record.id); A.Print(msg) end end)
        button(f,"Warband controls",30,-628,248,A.ShowWarbands)
        f.ctaValid=function() return f.record and W.records[f.record.id] and W.records[f.record.id].expiresAt>GetServerTime() end
        f:HookScript("OnShow",A.RefreshWarbandUI)
    end
    W.details.record=W.records[r.id]; W.details:Show(); A.RefreshWarbandUI()
end
function A.ShowWarbands()
    if not W.panel then
        local f=A.Surface("WarbandPvPWarbands",580,720,"WARBANDS"); W.panel=f; W.page=1
        f.status=label(f,30,-166,520)
        f.toggle=button(f,"",30,-202,248,function() A.SetWarbandsEnabled(not W.enabled) end)
        f.leave=button(f,"Leave / end",302,-202,248,function() A.LeaveWarband() end)
        local edit=CreateFrame("EditBox",nil,f,"InputBoxTemplate"); edit:SetSize(340,24); edit:SetPoint("TOPLEFT",36,-244)
        edit:SetAutoFocus(false); edit:SetMaxBytes(40); edit:SetText("Roaming warband"); edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end); f.name=edit
        f.start=button(f,"Start warband",394,-242,156,function() local _,msg=A.StartWarband(edit:GetText()); A.Print(msg); edit:ClearFocus() end)
        f.hostControls={}
        local function hostButton(title,x,y,width,command)
            local b=button(f,title,x,y,width,function() A.WarbandCommand(command) end)
            f.hostControls[#f.hostControls+1]=b; return b
        end
        hostButton("Rally here",30,-282,160,"rally"); hostButton("Follow me",210,-282,160,"follow")
        f.recruit=button(f,"Recruiting",390,-282,160,function() A.WarbandCommand("recruit "..(W.host and W.host.recruiting and "off" or "on")) end)
        hostButton("Forming",30,-318,160,"state forming"); hostButton("Roaming",210,-318,160,"state roaming"); hostButton("Rallying",390,-318,160,"state rallying")
        f.rows={}
        for i=1,3 do
            local row=CreateFrame("Button",nil,f); row:SetSize(520,54); row:SetPoint("TOPLEFT",30,-360-(i-1)*58)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.title=label(row,8,-3,504,"GameFontNormal"); row.meta=label(row,8,-23,504)
            row:SetScript("OnClick",function(self) A.ShowWarbandDetails(self.record) end)
            row:SetScript("OnEnter",function(self) A.WarbandTooltip(self,self.record) end)
            row:SetScript("OnLeave",function() W.tooltipID=nil; GameTooltip:Hide() end)
            f.rows[i]=row
        end
        f.empty=label(f,38,-400,504); f.empty:SetText("No active warbands received.\nEnable discovery, start one or watch a named organizer below.")
        button(f,"Previous",30,-540,110,function() W.page=math.max(1,W.page-1); A.RefreshWarbandUI() end)
        f.page=label(f,260,-547,140)
        button(f,"Next",440,-540,110,function() W.page=W.page+1; A.RefreshWarbandUI() end)
        f.inviteText=label(f,30,-582,340)
        f.invite=button(f,"Invite to party",394,-580,156,function()
            if f.pendingName then local _,msg=A.InviteWarbandMember(f.pendingName); A.Print(msg) end
        end)
        button(f,"Watch organizers",30,-628,248,A.ShowWarbandWatches)
        label(f,30,-608,520):SetText(A.ScoutDisclosure)
        button(f,"Recruitment",302,-628,248,A.ShowFinder)
        f:HookScript("OnShow",A.RefreshWarbandUI)
    end
    W.panel:Show(); A.RefreshWarbandUI()
end
function A.ShowWarbandWatches()
    if not W.watchPanel then
        local f=A.Surface("WarbandPvPWatches",580,720,"SCOUT THE RALLY BOARD"); W.watchPanel=f
        label(f,30,-166,520):SetText("Subscribe to a same-faction organizer by full character name.\nTheir fresh warband appears when received. Up to eight subscriptions.")
        local edit=CreateFrame("EditBox",nil,f,"InputBoxTemplate"); edit:SetSize(340,24); edit:SetPoint("TOPLEFT",36,-218)
        edit:SetAutoFocus(false); edit:SetMaxBytes(64); edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        button(f,"Watch",394,-216,156,function() local _,msg=A.WatchWarband(edit:GetText()); A.Print(msg); edit:ClearFocus(); A.RefreshWatchUI() end)
        f.rows={}
        for i=1,8 do
            local row={name=label(f,30,-274-(i-1)*42,350)}
            row.remove=button(f,"Unwatch",414,-268-(i-1)*42,136,function() if row.key then A.UnwatchWarband(row.key); A.RefreshWatchUI() end end)
            f.rows[i]=row
        end
        label(f,30,-628,520):SetText("Turning discovery off clears subscriptions and leaves your warband.\nDiscovery and subscriptions reset when you reload or log out.")
        f:HookScript("OnShow",A.RefreshWatchUI)
    end
    W.watchPanel:Show(); A.RefreshWatchUI()
end
function A.RefreshWatchUI()
    local f=W.watchPanel; if not f or not f:IsShown() then return end
    local list={}; for key,value in pairs(W.watches) do list[#list+1]={key=key,name=value.name} end
    table.sort(list,function(a,b) return a.name<b.name end)
    for i,row in ipairs(f.rows) do
        local value=list[i]; row.key=value and value.key
        row.name:SetText(value and value.name or (i==1 and "No named subscriptions." or "")); row.remove:SetShown(value~=nil)
    end
end
function A.RefreshWarbandUI()
    if A.RefreshHome then A.RefreshHome() end
    A.RefreshWatchUI()
    if W.tooltipID then GameTooltip:Hide(); W.tooltipID=nil end
    local f=W.panel
    if f and f:IsShown() then
        local list=A.WarbandList(); local pages=math.max(1,math.ceil(#list/3)); W.page=math.min(W.page,pages)
        local status=W.host and "Organizing" or W.member and ("Joined group "..W.member.slot.." | host: "..W.member.host) or W.join and "Waiting for join reply" or "Not joined"
        --@dev
        if P.IsSimulation() then status="[TEST] 1 real + "..(W.simulationCount-1).." dummy | "..status end
        --@enddev
        local recruitment=A.finder and A.finder.owned and "Listing active" or A.finder and A.finder.operation and "Change pending" or "See Recruitment"
        f.status:SetText(A.CleanText(status,65).."\nLayer unverified | "..recruitment)
        f.toggle:SetText(W.enabled and "Discovery: ON" or "Discovery: OFF")
        f.start:SetEnabled(not W.host and not W.member and not W.join)
        f.leave:SetEnabled(W.host~=nil or W.member~=nil or W.join~=nil)
        f.recruit:SetEnabled(W.host~=nil)
        for _,control in ipairs(f.hostControls) do control:SetEnabled(W.host~=nil) end
        f.recruit:SetText(W.host and (W.host.recruiting and "Close recruiting" or "Open recruiting") or "Recruiting")
        f.page:SetText(W.page.." / "..pages); f.empty:SetShown(#list==0)
        for i,row in ipairs(f.rows) do
            local r=list[(W.page-1)*3+i]; row.record=r; row:SetShown(r~=nil)
            if r then row.title:SetText(A.WarbandDisplayTitle(r).." | "..r.status); row.meta:SetText(A.LocationText(r).."\n"..r.count.." TotalWarcraft clients | "..r.owner) end
        end
        local chosen
        for _,invite in pairs(W.invites) do if invite.untilAt>GetTime() and (not chosen or invite.name<chosen.name) then chosen=invite end end
        f.pendingName=chosen and chosen.name; f.invite:SetEnabled(chosen~=nil)
        f.invite:SetText(chosen and chosen.attemptedAt and "Retry invite" or "Invite to party")
        f.inviteText:SetText(chosen and ((chosen.attemptedAt and not chosen.blocked and "Awaiting party acceptance:\n" or "Party invitation needed:\n")..chosen.name) or "No pending party invitations.")
    end
    local d=W.details
    if d and d:IsShown() and d.record then
        local r=W.records[d.record.id]
        if not r or r.expiresAt<=GetServerTime() then d.record=nil; A.InvalidateWindow(d); return end
        d.record=r; d.title:SetText(A.WarbandDisplayTitle(r))
        local lines={"Organizer: "..r.owner,A.LocationText(r).." ("..r.mode..")",
            r.status.." | "..(r.recruiting and "Recruiting" or "Closed"),A.WarbandCountText(r),A.WarbandArrival(r),""}
        for i=1,P.MAX_GROUPS do
            local g=r.groups and r.groups[i]
            if g and g.expiresAt>GetServerTime() then lines[#lines+1]="Group "..i..": "..A.LocationText(g).." | "..A.WarbandGroupCountText(r,g) end
        end
        lines[#lines+1]="\nGroup dots show leader positions, not everyone at that spot."
        lines[#lines+1]="Potential activity; no confirmed PvP or same-layer claim."
        local mine=W.member and W.member.id==r.id
        d.join:SetText(mine and "Request party invite" or "Join warband")
        d.body:SetText(table.concat(lines,"\n")); d.join:SetEnabled(not W.host and (not W.member or mine) and not W.join and (r.recruiting or mine))
        --@dev
        if r.simulated then
            d.join:SetText(mine and "Joined test group" or "Join test warband")
            d.join:SetEnabled(not W.host and not W.member and not W.join and r.recruiting)
        end
        --@enddev
    end
end
function A.ShowFinder()
    local F=A.finder
    if not F.panel then
        local f=A.Surface("WarbandPvPFinder",580,720,"RECRUITMENT"); F.panel=f; F.page=1
        f.status=label(f,30,-166,520); f.status:SetHeight(52)
        f.toggle=button(f,"",30,-226,248,function() A.SetFinderEnabled(not A.db.finderEnabled) end)
        button(f,"Search warbands",302,-226,248,function()
            local _,msg=A.FinderSearch(); A.Print(msg)
        end)
        label(f,30,-270,520):SetText("Search lists warbands; click Join to request membership.\nPublic listings follow the rally zone under Competitive.")
        f.selected=label(f,30,-310,520,"GameFontNormal")
        f.rows={}
        for i=1,5 do
            local b=button(f,"",30,-348-(i-1)*36,520,function(self)
                if self.activity then local _,msg=A.SelectFinderActivity(self.activity); A.Print(msg); A.RefreshFinderUI() end
            end)
            f.rows[i]=b
        end
        f.empty=label(f,30,-366,520)
        f.empty:SetText("No suitable activities exposed by this client.\nNamed organizers and guild discovery remain available.")
        button(f,"Previous",30,-540,110,function() F.page=math.max(1,F.page-1); A.RefreshFinderUI() end)
        f.page=label(f,260,-547,140)
        button(f,"Next",440,-540,110,function() F.page=F.page+1; A.RefreshFinderUI() end)
        label(f,30,-580,520):SetText("Start / Join stays on the warband board. Accept WoW's party invite.\n* Discovery only: this category requires manual listing text.\nA listing or party invitation does not select or confirm a layer.")
        button(f,"Retry listing change",30,-628,248,function() A.FinderSync(true); A.RefreshFinderUI() end)
        button(f,"Warband board",302,-628,248,A.ShowWarbands)
        f:HookScript("OnShow",A.RefreshFinderUI)
    end
    A.FinderChoices(true); F.panel:Show(); A.RefreshFinderUI()
end
function A.RefreshFinderUI()
    local F=A.finder; local f=F and F.panel
    if not f or not f:IsShown() then return end
    local choices=A.FinderChoices(); local pages=math.max(1,math.ceil(#choices/5)); F.page=math.min(F.page,pages)
    f.status:SetText(F.status)
    f.toggle:SetText(A.db.finderEnabled and "Public recruitment: ON" or "Public recruitment: OFF")
    local selected="None"
    for _,c in ipairs(choices) do if c.id==A.db.finderActivity then selected=c.name end end
    f.selected:SetText("Search activity: "..selected); f.page:SetText(F.page.." / "..pages); f.empty:SetShown(#choices==0)
    for i,row in ipairs(f.rows) do
        local c=choices[(F.page-1)*5+i]; row.activity=c and c.id; row:SetShown(c~=nil)
        if c then row:SetText((c.id==A.db.finderActivity and "> " or "")..c.name..(c.manual and " *" or "")) end
    end
end
