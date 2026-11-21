local _,A=...
local LIMIT=1500
local entries,head,count,dropped={},1,0,0
local began,budget,refill=0,40,0
local function clean(v,n)
    if issecretvalue and issecretvalue(v) then return "<restricted>" end
    if type(v)~="string" and type(v)~="number" and type(v)~="boolean" then return "unavailable" end
    return tostring(v):gsub("|",""):gsub("[%c]"," "):sub(1,n)
end
function A.Trace(kind,message)
    --@dev
    if A.DiagnosticTrace then A.DiagnosticTrace(kind,message) end
    --@enddev
    local now=GetTime()
    budget=math.min(40,budget+math.max(0,now-refill)*8); refill=now
    if budget<1 then dropped=dropped+1; return end
    budget=budget-1
    local row=string.format("%d +%.3f %s %s",GetServerTime(),now-began,clean(kind,48),clean(message,600))
    if count==LIMIT then entries[head]=row; head=head%LIMIT+1; dropped=dropped+1
    else entries[(head+count-1)%LIMIT+1]=row; count=count+1 end
end
function A.SessionLogText()
    local rows={"TotalWarcraft session log v1 | addon="..(A.release or "unknown").." | flavor="..(A.buildFlavor or "dev").." | omitted="..dropped,
        "Local session only; resets on reload/login. Names and in-game locations may appear. No chat contents. No automatic upload.",
        "Observations do not prove PvP participation or a shared layer."}
    for i=0,count-1 do rows[#rows+1]=entries[(head+i-1)%LIMIT+1] end
    return table.concat(rows,"\n")
end
function A.ShowExport()
    A.Trace("EXPORT","session log requested")
    if not A.exportPanel then
        local f=A.Surface("WarbandPvPSessionExport",680,720,"SESSION JOURNAL")
        A.Label(f,28,-174,620,"Ctrl+A, Ctrl+C to copy. Review names and locations before sharing.")
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",28,-208); scroll:SetPoint("BOTTOMRIGHT",-46,58)
        local edit=CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true); edit:SetFontObject(ChatFontNormal); edit:SetWidth(596); edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed",function() f:Hide() end)
        scroll:SetScrollChild(edit); f.edit=edit; A.exportPanel=f
    end
    local f=A.exportPanel
    f.edit:SetText(A.SessionLogText()); f:Show(); f.edit:SetFocus(); f.edit:HighlightText()
end
function A.InitSessionLog()
    began=GetTime(); refill=began
    A.Trace("SESSION","started; addon="..(A.release or "unknown").." player="..clean(A.WB.UnitName("player"),64))
    -- Observe calls for attribution; never invoke or replace the native API.
    if type(hooksecurefunc)=="function" and C_PartyInfo and type(C_PartyInfo.InviteUnit)=="function" then
        pcall(hooksecurefunc,C_PartyInfo,"InviteUnit",function(target)
            if not A.nativeInviteInProgress then A.Trace("NATIVE_INVITE_CALL","outside TotalWarcraft invitation flow; origin unverified; target="..clean(target,64)) end
        end)
    end
    local frame=CreateFrame("Frame")
    local times={}
    for _,event in ipairs({"PLAYER_LOGIN","PLAYER_LOGOUT","PLAYER_ENTERING_WORLD","ZONE_CHANGED_NEW_AREA",
        "GROUP_ROSTER_UPDATE","PARTY_LEADER_CHANGED","SHARD_TRANSFER_IMMINENT","SHARD_TRANSFER","SHARD_TRANSFER_CANCELLED","UNIT_PHASE"}) do
        pcall(frame.RegisterEvent,frame,event)
    end
    frame:SetScript("OnEvent",function(_,event,unit)
        if event=="UNIT_PHASE" and unit~="player" then return end
        if times[event] and GetTime()-times[event]<1 then return end
        times[event]=GetTime()
        local loc=A.CurrentLocation()
        local phase=A.WB.Read(UnitPhaseReason,"player")
        A.Trace(event,"map="..(loc and loc.mapID or "unavailable").." phase="..clean(phase,48).." layer=unverified")
    end)
end
