local _,A=...
function A.ShowEnemyScout(r)
    if not r or not A.records[r.id] or r.expiresAt<=GetServerTime() then return end
    local S=A.scouting
    if not S.panel then
        local f=A.Surface("WarbandPvPScouting",580,720,"ENEMY SCOUTING"); S.panel=f
        local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
        title:SetPoint("TOPLEFT",30,-174); title:SetWidth(520); title:SetJustifyH("LEFT"); f.title=title
        local body=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        body:SetPoint("TOPLEFT",30,-214); body:SetWidth(520); body:SetJustifyH("LEFT"); body:SetSpacing(5); f.body=body
        A.Button(f,"Show report on map",30,-620,248,function() if f.record then A.OpenMap(f.record) end end)
        A.Button(f,"Field report",302,-620,248,function() if f.record then A.ShowDetails(f.record) end end)
        f.ctaValid=function() return f.record and A.records[f.record.id] and A.records[f.record.id].expiresAt>GetServerTime() end
        f:HookScript("OnShow",A.RefreshScoutUI)
    end
    S.panel.record=r; S.panel:Show(); A.RefreshScoutUI()
end
function A.RefreshScoutUI()
    local f=A.scouting and A.scouting.panel
    if not f or not f:IsShown() then return end
    local r=f.record and A.records[f.record.id]
    if not r or r.expiresAt<=GetServerTime() then f.record=nil; A.InvalidateWindow(f); return end
    f.record=r; f.title:SetText("Scout report: "..(r.scout and r.scout.enemy or "Unknown enemy"))
    local s=r.scout
    local lines={A.ScoutSummary(r),""}
    if s and s.state=="known" and s.expiresAt>GetServerTime() then
        lines[#lines+1]="Affiliation: "..s.title
        lines[#lines+1]="Reported WBP members: "..s.members
        lines[#lines+1]="Reported parties: "..(s.parties>0 and s.parties or "unknown")
        lines[#lines+1]="Reported orders: "..s.activity
        lines[#lines+1]="Snapshot age: "..math.max(0,GetServerTime()-s.updatedAt).."s | expires in "..math.max(0,s.expiresAt-GetServerTime()).."s"
        lines[#lines+1]="Warband ID: "..s.warbandID
        lines[#lines+1]="\nEnemy self-report, relayed by the observer.\nMembership size is not a count of nearby enemies or PvP fighters."
    else
        lines[#lines+1]="Target a visible opposing-faction player, then use /wb report.\nA cooperating Warband-PvP member may return their affiliation."
        lines[#lines+1]="\nNo usable reply means unknown. The player may not use WBP,\nmay not belong to a warband, or WoW may block the exchange."
        lines[#lines+1]="Cross-faction delivery depends on the game and may be unavailable."
    end
    lines[#lines+1]="\nObserver: "..r.reporter
    lines[#lines+1]="Report location: "..A.LocationText(r)
    lines[#lines+1]="This marks the observation, not live enemy positions or a layer."
    f.body:SetText(table.concat(lines,"\n"))
end
