local _,A=...
A.colors={report={.88,.27,.16}}
--@dev
A.colors.heat={1,.42,.20}; A.colors.defense={.35,.75,1}; A.colors.raid={1,.76,.28}
A.testColor={.8,.45,1}
--@enddev
local label,button=A.Label,A.Button
function A.Tooltip(owner, r)
    if r.expiresAt <= GetServerTime() then return end
    A.tooltipRecord = r
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(A.DisplayTitle(r), 1, .82, .35)
    GameTooltip:AddLine(A.LocationText(r), 1, 1, 1)
    GameTooltip:AddLine(A.CountText(r), 1, 1, 1)
    if r.reporter ~= "" then GameTooltip:AddLine("Reported by: " .. r.reporter, .7, .7, .7) end
    if r.opposition ~= "" then GameTooltip:AddLine("Reported opposition: " .. r.opposition, 1, .6, .5, true) end
    if r.note ~= "" then GameTooltip:AddLine(r.note, .8, .8, .8, true) end
    GameTooltip:AddLine(A.ScoutSummary(r),1,.65,.3,true)
    GameTooltip:AddLine("Expires in " .. math.max(0, r.expiresAt - GetServerTime()) .. "s", .6, .6, .6)
    GameTooltip:Show()
end


function A.ClearReports()
    A.records={}
    if A.toast then A.toast:Hide() end
    if A.details then A.InvalidateWindow(A.details); A.details.record=nil end
    A.Trace("CLEAR","local report board cleared"); A.Changed()
end
function A.ShowHome()
    if not A.home then
        local f=A.Surface("WarbandPvPHome",580,720,"WARBAND-PVP")
        A.home=f
        label(f,30,-164,520,"FIELD COMMAND  /  Reports, rallies and troop movement","GameFontNormal")
        f.status=label(f,30,-194,520,""); f.status:SetHeight(50)
        button(f,"Report PvP here",30,-258,248,A.RunReport)
        button(f,"Read field reports",302,-258,248,function() A.BuildUI(); A.panel:Show() end)
        button(f,"Warbands",30,-310,248,A.ShowWarbands)
        button(f,"Group locations",302,-310,248,A.ShowPresence)
        button(f,"Session journal / Export",30,-362,248,A.ShowExport)
        button(f,"Keybindings",302,-362,248,A.ShowBindings)
        f.mute=button(f,"",30,-414,248,function()
            A.db.muted=not A.db.muted
            if A.db.muted and A.toast then A.toast:Hide() end
            A.RefreshHome()
        end)
        button(f,"Field guide / Status",302,-414,248,A.ShowHelp)
        label(f,30,-478,520,"Reports are observations. Warbands show potential action.\nNeither confirms fight size or a shared layer.")
        label(f,30,-535,520,"Discovery: guild, party, named organizers and optional recruitment.\nLocation sharing is opt-in for this session.")
        label(f,30,-594,520,"Report: crossed crimson swords   Warband: gold axe and sword\nGroup leader: numbered gold marker   Presence: jade cross")
        f:HookScript("OnShow",A.RefreshHome)
    end
    A.home:Show(); A.RefreshHome()
end
function A.ToggleHome()
    if A.home and A.home:IsShown() then A.CloseWindows() else A.ShowHome() end
end
function A.RefreshHome()
    if not A.home or not A.home:IsShown() then return end
    local fresh=A.PresenceSummary()
    A.home.status:SetText((UnitFactionGroup("player") or "Unknown faction").." | "..(A.scopeRuleset or "Scope unavailable").." | "..A.release
        .."\n"..#A.List().." field reports | "..#A.WarbandList().." warbands | "..fresh.." sharing peers")
    A.home.mute:SetText(A.db.muted and "Alerts: muted" or "Alerts: on")
end
function A.BuildUI()
    if A.panel then return end
    local p=A.Surface("WarbandPvPPanel",580,720,"FIELD REPORTS"); A.panel=p
    A.filter,A.page="all",1
    p.status=label(p,30,-164,520,"")
    p.rows={}
    for i=1,5 do
        local row=CreateFrame("Button",nil,p)
        row:SetSize(520,66); row:SetPoint("TOPLEFT",30,-208-(i-1)*70)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.bar=row:CreateTexture(nil,"ARTWORK"); row.bar:SetSize(3,52); row.bar:SetPoint("LEFT")
        row.title=label(row,13,-5,490,"","GameFontNormal")
        row.where=label(row,13,-26,490,"")
        row.meta=label(row,13,-44,490,"")
        row:SetScript("OnClick",function(self) if self.record then A.ShowDetails(self.record) end end)
        row:SetScript("OnEnter",function(self) if self.record then A.Tooltip(self,self.record) end end)
        row:SetScript("OnLeave",function() GameTooltip:Hide(); A.tooltipRecord=nil end)
        p.rows[i]=row
    end
    p.empty=label(p,35,-270,510,"No active field reports.\n\nReport an observed fight to WBP users in your guild.\nReports expire after five minutes; fight size stays unknown.")
    button(p,"Previous",30,-565,110,function() A.page=math.max(1,A.page-1); A.RefreshUI() end)
    p.page=label(p,240,-571,140,"")
    button(p,"Next",440,-565,110,function() A.page=A.page+1; A.RefreshUI() end)
    button(p,"Report PvP here",30,-615,248,A.RunReport)
    button(p,"Clear local reports",302,-615,248,A.ClearReports)
    p:HookScript("OnShow",A.RefreshUI)
end
function A.RefreshUI()
    A.RefreshHome()
    if A.RefreshPresenceUI then A.RefreshPresenceUI() end
    local p=A.panel
    if not p or not p:IsShown() then return end
    local list=A.List(); local pages=math.max(1,math.ceil(#list/5)); A.page=math.min(A.page,pages)
    p.status:SetText((A.guildReady and A.scopeRuleset and "Guild reports" or "Transport unavailable").." | Observations, not confirmed combatants")
    p.page:SetText(A.page.." / "..pages); p.empty:SetShown(#list==0)
    for i,row in ipairs(p.rows) do
        local r=list[(A.page-1)*5+i]; row.record=r; row:SetShown(r~=nil)
        if r then
            local c=A.colors[r.kind]
            --@dev
            if r.test then c=A.testColor end
            --@enddev
            row.bar:SetColorTexture(c[1],c[2],c[3],1)
            row.title:SetText(A.DisplayTitle(r)); row.where:SetText(A.LocationText(r))
            row.meta:SetText(A.CountText(r).." | "..math.ceil((r.expiresAt-GetServerTime())/60).."m left")
        end
    end
end
function A.ShowPresence()
    if not A.presencePanel then
        local f=A.Surface("WarbandPvPPresence",580,720,"GROUP LOCATIONS"); A.presencePanel=f
        f.toggle=button(f,"",30,-164,250,function() A.SetPresenceEnabled(not A.presenceEnabled) end)
        label(f,30,-211,520,"Shares your location and readable flag/combat status with your\noutdoor party or raid. Flags are not evidence of PvP participation.")
        f.body=label(f,30,-270,520,""); f.body:SetSpacing(5)
        button(f,"Previous",30,-620,110,function() A.presencePage=math.max(1,(A.presencePage or 1)-1); A.RefreshPresenceUI() end)
        button(f,"Next",440,-620,110,function() A.presencePage=(A.presencePage or 1)+1; A.RefreshPresenceUI() end)
        f:HookScript("OnShow",A.RefreshPresenceUI)
    end
    A.presencePanel:Show(); A.RefreshPresenceUI()
end
function A.RefreshPresenceUI()
    local f=A.presencePanel; if not f or not f:IsShown() then return end
    f.toggle:SetText(A.presenceEnabled and "Sharing: on (session only)" or "Sharing: off")
    local peers=A.PresenceList(); local pages=math.max(1,math.ceil(#peers/8)); A.presencePage=math.min(A.presencePage or 1,pages)
    local rows={"Fresh sharing peers: "..#peers.." | Page "..A.presencePage.." / "..pages,""}
    for i=(A.presencePage-1)*8+1,math.min(#peers,A.presencePage*8) do
        local p=peers[i]; rows[#rows+1]=p.name.."\n"..A.LocationText(p)
    end
    if #peers==0 then rows[#rows+1]="No fresh locations. Both players must enable sharing\nand be in the same outdoor native group." end
    rows[#rows+1]="\nLayer unverified. Locations expire after 30 seconds."
    f.body:SetText(table.concat(rows,"\n"))
end
function A.ShowHelp()
    if not A.helpPanel then
        local f=A.Surface("WarbandPvPHelp",580,720,"FIELD GUIDE"); A.helpPanel=f
        f.body=label(f,30,-164,520,""); f.body:SetSpacing(5)
    end
    local f=A.helpPanel
    f.body:SetText("1. Report an observed fight with Report PvP here.\nGuild WBP users receive a five-minute map marker.\nTwo-minute cooldown; no automatic fight-size estimate.\n\n2. Open Warbands and enable discovery. Start a rally,\nor join a listing. A warband coordinates up to four normal parties.\nWBP membership is separate from WoW's party invitation.\nThe host attempts an invite; the recruit accepts it in WoW.\n\n3. Open Recruitment to choose a suitable public activity,\nsearch or retry. Native API restrictions may prevent posting.\nYou can also watch a known organizer by full character name.\n\n4. Join the assigned party and travel to the rally zone.\nThe game controls transfers; WBP cannot force or confirm a layer.\n\nShortcuts: /wb report | /wb | /wb presence on/off\n/wb show | /wb finder | /wb find | /wb export | /wb clear\nAll player features are available from the command board.\n\nStatus: "..A.release.." | "..(A.scopeRuleset or "unknown ruleset").." / "..tostring(A.scopeRegion).."\nGuild messaging: "..tostring(A.guildReady).." | Warband messaging: "..tostring(A.warbands.ready).."\nLog stays local and resets on reload/login; export before reloading.")
    f:Show()
end
local actions={{"Command board","WARBANDPVP_OPEN"},{"Report PvP here","WARBANDPVP_REPORT"},{"Warbands","WARBANDPVP_WARBANDS"},{"Session export","WARBANDPVP_EXPORT"}}
function A.AssignBinding(action,key)
    if InCombatLockdown() then return false,"Change bindings after combat." end
    if type(SetBinding)~="function" or type(SaveBindings)~="function" or type(GetBindingAction)~="function" then return false,"Use the game's Key Bindings menu." end
    key=(key or ""):upper():gsub("%s","")
    if #key>40 then return false,"Key combination too long." end
    local current=key~="" and GetBindingAction(key) or ""
    if current~="" and current~=action then return false,"That key belongs to "..current..". Choose another key in this panel." end
    local old1,old2=GetBindingKey(action)
    if key~="" and SetBinding(key,action)~=true then return false,"Unrecognized key. Example: CTRL-SHIFT-C." end
    for _,old in ipairs({old1 or false,old2 or false}) do if old and old~=key then SetBinding(old) end end
    SaveBindings(GetCurrentBindingSet())
    return true,key=="" and "Binding cleared." or ("Bound "..key..".")
end
function A.ShowBindings()
    if not A.bindingPanel then
        local f=A.Surface("WarbandPvPBindings",580,720,"KEYBINDINGS"); A.bindingPanel=f
        label(f,30,-164,520,"Enter a key such as CTRL-SHIFT-C. Existing bindings are protected.\nSaved to your current account/character binding set.")
        for i,entry in ipairs(actions) do
            local action=entry[2]; local y=-226-(i-1)*88
            label(f,30,y,510,entry[1],"GameFontNormal")
            local edit=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
            edit:SetPoint("TOPLEFT",36,y-26); edit:SetSize(260,26); edit:SetAutoFocus(false); edit:SetMaxLetters(40)
            edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
            edit:SetText(type(GetBindingKey)=="function" and GetBindingKey(action) or "")
            button(f,"Apply",312,y-26,110,function() local _,msg=A.AssignBinding(action,edit:GetText()); A.Print(msg); edit:ClearFocus() end)
            button(f,"Clear",434,y-26,110,function() local ok,msg=A.AssignBinding(action,""); if ok then edit:SetText("") end; A.Print(msg) end)
        end
    end
    A.bindingPanel:Show()
end
