local _,A=...
-- Opt-in channel troubleshooting. Never calls the report/model adapters.
local PREFIX,CHANNEL="TW_CHTEST1","TotalWarcraftTest"
local D={revision=2,active=false,state="idle",sent=0,rx=0,acks=0,echoes=0}
A.channelDiagnostics=D
local db,frame,ticker
local ROWS,DURATION,INTERVAL,PEERS,MAX_SENDS=500,180,15,16,72
local function secret(v) return issecretvalue and issecretvalue(v) end
local function call(fn,...)
    if type(fn)~="function" then return end
    local ok,v=pcall(fn,...); if ok and not secret(v) then return v end
end
local function text(v)
    if secret(v) then return "<restricted>" end
    if type(v)~="string" and type(v)~="number" and type(v)~="boolean" then return "unavailable" end
    return tostring(v):gsub("[|%c]"," "):sub(1,128)
end
local function integer(v,lo,hi)
    return not secret(v) and type(v)=="number" and v==v and v>=lo and v<=hi and v%1==0
end
local function row(kind,message)
    if not db then return end
    if #db.entries>=ROWS then table.remove(db.entries,1); db.dropped=db.dropped+1 end
    db.entries[#db.entries+1]=string.format("%d +%.2f %s %s",GetServerTime(),GetTime()-(D.started or GetTime()),kind,message:sub(1,700))
end
local function channelID()
    local id=call(GetChannelName,CHANNEL)
    if integer(id,1,100) then return id end
end
local function preferIndex20(id)
    if D.indexAttempted then return end
    D.indexAttempted=true
    if id==20 then row("CHANNEL_INDEX","already at preferred index 20"); return end
    -- Numbers are local UI assignments. Never route to an assumed index, evict
    -- another channel, or fill slots with dummy memberships to force a number.
    local occupied=call(GetChannelName,20)
    if occupied~=0 then row("CHANNEL_INDEX","20 occupied/unreadable; retaining assigned index "..id); return end
    local swap=C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
    if type(swap)~="function" then row("CHANNEL_INDEX","reorder API unavailable; retaining assigned index "..id); return end
    local ok,result=pcall(swap,id,20)
    local actual=channelID()
    row("CHANNEL_INDEX","requested=20 callOK="..tostring(ok).." result="..text(result).." actual="..text(actual))
    if actual~=20 then A.Print("Preferred channel index 20 was not confirmed; using the test channel's assigned number.") end
end
local function mapID()
    local id=call(C_Map and C_Map.GetBestMapForUnit,"player")
    return integer(id,1,100000) and id or 0
end
local function context()
    row("CONTEXT","map="..mapID().." guild="..text(call(IsInGuild)).." group="..text(call(IsInGroup))
        .." combat="..text(call(InCombatLockdown)).." realm="..text(call(GetRealmName))
        .." normalizedRealm="..text(call(GetNormalizedRealmName)).." realmID="..text(call(GetRealmID)))
    local ci=C_ChatInfo or {}
    row("RESTRICTIONS","addon="..text(call(ci.AreOutgoingAddonChatMessagesRestricted))
        .." chatLockdown="..text(call(ci.InChatMessagingLockdown)).." (informational; not a delivery result)")
end
local function summary()
    return "Channel test v"..D.revision.." | "..D.state.." | channel="..text(D.channel).." (preferred 20) | remote probes="..D.rx.." | remote ACKs="..D.acks
        .." | self echoes="..D.echoes.." | accepted sends="..D.sent.." (send acceptance is not receipt)"
end
local function stop(reason)
    D.active=false; D.state="stopped: "..reason
    if ticker then ticker:Cancel(); ticker=nil end
    if frame then frame:UnregisterAllEvents() end
    D.queue={}
    if D.owned and channelID() then
        local ok=pcall(LeaveChannelByName,CHANNEL)
        row("LEAVE",ok and "requested for test-owned channel" or "failed; /leave "..CHANNEL)
    end
    D.owned=false
    row("STOP",summary()); A.Print(summary()); A.Print("/tw channel export copies both-client delivery evidence.")
    if A.channelPanel then A.channelPanel.status:SetText(summary()) end
end
local function packet(kind,run,seq)
    return table.concat({"1",kind,run,tostring(seq),tostring(GetServerTime()),tostring(D.region),D.ruleset,
        D.faction,tostring(mapID()),D.label,D.run},"\t")
end
local function send(kind,run,seq)
    if D.blocked or D.attempts>=MAX_SENDS then return end
    local id=channelID(); if not id then return end
    local payload=packet(kind,run,seq)
    if #payload>255 then stop("packet limit"); return end
    D.attempts=D.attempts+1
    local ok,result=pcall(C_ChatInfo.SendAddonMessage,PREFIX,payload,"CHANNEL",tostring(id))
    local accepted=ok and not secret(result) and (result==0 or result==true)
    if accepted then D.sent=D.sent+1; D.failures=0 else D.failures=D.failures+1 end
    row("SEND",kind.." seq="..seq.." channel="..id.." accepted="..tostring(accepted).." result="..text(result).." automatic=true")
    if not accepted and D.failures>=3 then
        D.blocked=true; row("SEND_PAUSED","three rejections; receive-only until timeout")
        A.Print("Channel sends rejected three times; listening until timeout. /tw channel export.")
    end
end
local function matchingChannel(id,name)
    if secret(id) or secret(name) then return false end
    local current=channelID()
    if integer(id,1,100) then return id==current end
    return type(name)=="string" and (name==CHANNEL or name:match("^%d+%. (.+)$")==CHANNEL)
end
local function decode(payload)
    if secret(payload) or type(payload)~="string" or #payload>255 then return end
    local f={}; for v in (payload.."\t"):gmatch("(.-)\t") do f[#f+1]=v; if #f>11 then return end end
    if #f~=11 or f[1]~="1" or (f[2]~="P" and f[2]~="A") then return end
    for _,i in ipairs({3,11}) do if #f[i]>48 or not f[i]:match("^%d+%-%d+%-%d+$") then return end end
    local seq,stamp,region,map=tonumber(f[4]),tonumber(f[5]),tonumber(f[6]),tonumber(f[9])
    if not integer(seq,1,12) or not integer(stamp,GetServerTime()-60,GetServerTime()+30)
        or region~=D.region or f[7]~=D.ruleset or f[8]~=D.faction or not integer(map,0,100000)
        or #f[10]>24 or not f[10]:match("^[%w_-]+$") then return end
    if f[2]=="P" and f[3]~=f[11] then return end
    return {kind=f[2],run=f[3],seq=seq,map=map,label=f[10],from=f[11]}
end
local function receive(prefix,payload,route,sender,_,zoneID,localID,name)
    if secret(prefix) or secret(route) or secret(sender) or prefix~=PREFIX or route~="CHANNEL"
        or type(sender)~="string" or #sender<1 or #sender>128 or sender:find("[|%c]") then return end
    if not matchingChannel(localID,name) then
        if not D.badChannel then row("UNCONFIRMED_ROUTE","localID="..text(localID).." name="..text(name).." zoneID="..text(zoneID)); D.badChannel=true end
        return
    end
    local p=decode(payload); if not p then return end
    if p.from==D.run then
        if D.echoes<MAX_SENDS then D.echoes=D.echoes+1; row("SELF_ECHO",p.kind.." seq="..p.seq.." (not remote delivery)") end
        return
    end
    -- Only ACKs for an outstanding probe from this exact local run count.
    if p.kind=="A" and (p.run~=D.run or not D.pending[p.seq] or GetTime()-D.pending[p.seq]>60) then return end
    local key=sender:lower()
    local peer=D.peers[key]
    if not peer then
        if D.peerCount>=PEERS then return end
        peer={seen={},acks={}}; D.peers[key]=peer; D.peerCount=D.peerCount+1
    end
    if p.kind=="P" then
        if peer.run~=p.run then
            -- One remote run per sender per local test avoids replay churn.
            if peer.run then return end
            peer.run=p.run
        end
        if peer.seen[p.seq] then return end
        peer.seen[p.seq]=true; D.rx=D.rx+1
        row("REMOTE_PROBE","sender="..sender.." run="..p.run.." seq="..p.seq.." map="..p.map.." label="..p.label)
        if D.rx==1 then A.Print("Channel test: remote probe received from "..sender..". Automatic ACK queued.") end
        if #D.queue<PEERS then D.queue[#D.queue+1]={run=p.run,seq=p.seq,at=GetTime()} end
    else
        if peer.acks[p.seq] then return end
        peer.acks[p.seq]=true; D.acks=D.acks+1
        row("REMOTE_ACK","sender="..sender.." seq="..p.seq.." map="..p.map.." label="..p.label.." rtt="..string.format("%.2f",GetTime()-D.pending[p.seq]))
        if D.acks==1 then A.Print("Channel test: round-trip ACK received from "..sender..". Both directions demonstrated for this probe.") end
    end
end
function A.OnChannelDiagnosticEvent(event,...)
    if not D.active then return end
    if event=="PLAYER_LOGOUT" then stop("logout"); return end
    local second=math.floor(GetTime())
    if D.second~=second then D.second=second; D.budget=40 end
    D.budget=D.budget-1; if D.budget<0 then return end
    if event=="CHAT_MSG_ADDON" then receive(...)
    elseif event=="CHAT_MSG_CHANNEL_NOTICE" then
        local notice,_,_,channelName,_,_,_,index,base=...
        if secret(notice) or not (matchingChannel(index,base) or matchingChannel(nil,channelName)) then return end
        row("CHANNEL_NOTICE",text(notice).." index="..text(index).." base="..text(base))
        if notice=="NOT_ALLOWED_IN_CHANNEL" or notice=="BANNED" or notice=="MUTED" then
            D.blocked=true; row("SEND_PAUSED","server channel notice; receive-only until timeout")
            A.Print("Channel test server notice: "..notice..". /tw channel export.")
        end
    elseif event=="ZONE_CHANGED_NEW_AREA" or event=="PLAYER_ENTERING_WORLD" then row(event,""); context() end
end
local function tick()
    if not D.active then return end
    if A.channelPanel and A.channelPanel:IsShown() then A.channelPanel.status:SetText(summary()) end
    if GetTime()-D.started>=DURATION then stop("three-minute limit"); return end
    local ruleset,region=A.CurrentScope()
    if ruleset~=D.ruleset or region~=D.region or call(UnitFactionGroup,"player")~=D.faction then stop("scope changed"); return end
    local id=channelID()
    if id then preferIndex20(id); id=channelID() end
    if id~=D.channel then D.channel=id; row("CHANNEL",id and ("ready id="..id) or "not joined") end
    if not id then
        if GetTime()-D.started>=30 then stop("channel unavailable after 30 seconds") end
        return
    end
    for _=1,2 do
        local item=table.remove(D.queue,1); if not item then break end
        if GetTime()-item.at<=30 then send("A",item.run,item.seq) end
    end
    if GetTime()>=D.nextSend and D.seq<12 and not D.blocked then
        D.seq=D.seq+1; D.nextSend=GetTime()+INTERVAL; D.pending[D.seq]=GetTime()
        send("P",D.run,D.seq)
    end
end
local function start(label)
    if D.active then A.Print("Channel test already active. /tw channel stop first."); return end
    local ruleset,region=A.CurrentScope(); local faction=call(UnitFactionGroup,"player")
    if not ruleset or (faction~="Horde" and faction~="Alliance") then A.Print("Forever ruleset/faction unavailable."); return end
    local ci=C_ChatInfo
    if not ci or type(ci.SendAddonMessage)~="function" or type(ci.RegisterAddonMessagePrefix)~="function"
        or type(GetChannelName)~="function" or type(LeaveChannelByName)~="function" then A.Print("Channel test APIs unavailable."); return end
    local registered=call(ci.RegisterAddonMessagePrefix,PREFIX)
    if registered~=0 and registered~=1 and registered~=true then A.Print("Channel test prefix registration failed."); return end
    label=label~="" and label or "delivery"
    if #label>24 or not label:match("^[%w_-]+$") then A.Print("Use a label of 1-24 letters, digits, underscores or hyphens."); return end
    D.started=GetTime(); D.run=string.format("%d-%d-%d",GetServerTime(),math.floor(GetTime()*1000)%1000000000,math.random(100000,999999))
    D.ruleset,D.region,D.faction,D.label=ruleset,region,faction,label
    D.sent,D.rx,D.acks,D.echoes,D.seq,D.attempts,D.failures,D.peerCount=0,0,0,0,0,0,0,0
    D.peers,D.queue,D.pending={},{},{}; D.blocked,D.badChannel,D.second=nil,nil,nil
    D.channel=nil; D.indexAttempted=nil; D.nextSend=GetTime()+5; D.active=true; D.state="running"
    D.owned=not channelID()
    row("START","revision="..D.revision.." label="..label.." run="..D.run.." channel="..CHANNEL.." preferredIndex=20 ruleset="..ruleset.." region="..region.." faction="..faction)
    for i=1,4 do row("BUILD","field"..i.."="..text(call(function() return select(i,GetBuildInfo()) end))) end
    row("PLAYER",text(call(A.WB.UnitName,"player"))); context()
    if not frame then frame=CreateFrame("Frame"); frame:SetScript("OnEvent",function(_,e,...) A.OnChannelDiagnosticEvent(e,...) end) end
    for _,event in ipairs({"CHAT_MSG_ADDON","CHAT_MSG_CHANNEL_NOTICE","ZONE_CHANGED_NEW_AREA","PLAYER_ENTERING_WORLD","PLAYER_LOGOUT"}) do
        local ok,result=pcall(frame.RegisterEvent,frame,event)
        if not ok or secret(result) or result==false then stop("event registration unavailable"); return end
    end
    if D.owned then
        local join=JoinTemporaryChannel or JoinChannelByName
        if type(join)~="function" then stop("channel join API unavailable"); return end
        local ok,result=pcall(join,CHANNEL)
        row("JOIN","temporary="..tostring(join==JoinTemporaryChannel).." callOK="..tostring(ok).." result="..text(result))
        if not ok then stop("join error"); return end
    else row("JOIN","already joined; leave ownership remains with player") end
    ticker=C_Timer.NewTicker(1,tick)
    A.Print("Channel test v"..D.revision.." started: "..label..". Automatic probes begin in 5s, then every 15s for 3 minutes. /tw channel status | stop | export.")
end
function A.ChannelDiagnosticText()
    return "TotalWarcraft channel diagnostics v1 | addon="..text(A.release).." | revision="..D.revision.." | omitted="..db.dropped
        .."\n"..summary().."\nCHANNEL probes/ACKs; no guild/whisper fallback, chat text or PvP pins."
        .."\nNames, realms and map IDs included. Saved log only; never resumes on reload.\n"..table.concat(db.entries,"\n")
end
local function export()
    if not A.channelExport then
        local f=A.Surface("WarbandPvPChannelExport",760,720,"CHANNEL CHECK")
        A.Label(f,28,-174,690,"Ctrl+A, Ctrl+C to copy. Export BOTH clients. Review names before sharing.")
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",28,-208); scroll:SetPoint("BOTTOMRIGHT",-46,58)
        local edit=CreateFrame("EditBox",nil,scroll); edit:SetMultiLine(true); edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(670); edit:SetAutoFocus(false); edit:SetScript("OnEscapePressed",function() f:Hide() end)
        scroll:SetScrollChild(edit); f.edit=edit; A.channelExport=f
    end
    local f=A.channelExport; f.edit:SetText(A.ChannelDiagnosticText()); f:Show(); f.edit:SetFocus(); f.edit:HighlightText()
end
function A.ChannelCommand(input)
    local cmd,arg=input:match("^%s*(%S*)%s*(.-)%s*$"); cmd=cmd:lower()
    if cmd=="start" then start(arg)
    elseif cmd=="stop" then if D.active then stop("user stopped") else A.Print(summary()) end
    elseif cmd=="export" then export()
    elseif cmd=="clear" then
        if D.active then stop("cleared") end
        db.entries={}; db.dropped=0; D.sent,D.rx,D.acks,D.echoes=0,0,0,0; D.state="idle"; A.Print("Channel test log cleared.")
    else A.Print(summary()); A.Print("/tw channel start <label> | status | stop | export | clear. No PvP reports.") end
end
function A.InitChannelDiagnostics()
    if D.active then stop("reinitialize") end
    db=A.db.channelDiagnostics
    if type(db)~="table" then db={} end
    local rows={}
    if type(db.entries)=="table" then
        for i=math.max(1,#db.entries-ROWS+1),#db.entries do
            local v=db.entries[i]; if not secret(v) and type(v)=="string" then rows[#rows+1]=v:sub(1,800) end
        end
    end
    db.entries=rows; db.dropped=integer(db.dropped,0,1e9) and db.dropped or 0
    A.db.channelDiagnostics=db
end
function A.ShowChannelCheck()
    if not A.channelPanel then
        local f=A.Surface("WarbandPvPChannelCheck",580,720,"CHANNEL CHECK"); A.channelPanel=f
        A.Label(f,30,-174,520,"Check automatic delivery with another TotalWarcraft user.")
        A.Label(f,30,-214,520,"Both players run this check on the same faction and ruleset.\nNo combat or shared guild is needed.\n\nProbes and replies run automatically for three minutes.\nRemote probes and ACKs confirm receipt; self echoes do not.\n\nThis check does not publish PvP reports or map pins.\nThe channel prefers index 20 when the slot is available.\nExport both clients' logs to compare delivery and map IDs.")
        A.Label(f,30,-392,520,"Run label (for example, unguilded or continents)")
        f.label=CreateFrame("EditBox",nil,f,"InputBoxTemplate"); f.label:SetSize(500,26)
        f.label:SetPoint("TOPLEFT",35,-418); f.label:SetAutoFocus(false); f.label:SetMaxLetters(24); f.label:SetText("delivery")
        f.label:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        A.Button(f,"Run check",30,-470,245,function() start(f.label:GetText()); f.status:SetText(summary()) end)
        A.Button(f,"Stop",305,-470,245,function() A.ChannelCommand("stop"); f.status:SetText(summary()) end)
        A.Button(f,"Export log",30,-520,245,export)
        A.Button(f,"Clear log",305,-520,245,function() A.ChannelCommand("clear"); f.status:SetText(summary()) end)
        f.status=A.Label(f,30,-572,520,"")
    end
    A.channelPanel.status:SetText(summary()); A.channelPanel:Show()
end
