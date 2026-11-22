local _,A=...
local P,W=A.WB,A.warbands
local PREFIX="WBP_SCOUT1"
local S={pending={},orphans={},rates={},probed={},tokens=16,refill=0}
A.scouting=S
A.ScoutDisclosure="Start / Join makes your warband affiliation and reported size scoutable."
local function secret(v) return issecretvalue and issecretvalue(v) end
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function updateTimer()
    local active=next(S.pending) or next(S.orphans) or next(S.probed) or next(S.rates)
    if not active then
        for _,r in pairs(A.records) do
            if r.scout and r.scout.state=="known" then active=true; break end
        end
    end
    if active and not S.timer then S.timer=C_Timer.NewTicker(1,A.ScoutTick)
    elseif not active and S.timer then S.timer:Cancel(); S.timer=nil end
end
local function live()
--@dev
    if A.testMode or P.IsSimulation() then return false end
--@enddev
    return S.ready and P.Scope()~=nil and P.Read(IsInInstance)==false
end
local function opposite(faction)
    local own=P.Read(UnitFactionGroup,"player")
    return (own=="Horde" and faction=="Alliance") or (own=="Alliance" and faction=="Horde")
end
local function enemy(unit)
    if P.Read(UnitExists,unit)~=true or P.Read(UnitIsPlayer,unit)~=true
        or P.Read(UnitIsVisible,unit)~=true then return end
    local faction=P.Read(UnitFactionGroup,unit)
    if not opposite(faction) then return end
    local name=P.UnitName(unit)
    if name then return {name=name,key=P.Key(name),faction=faction} end
end
local function observed(name)
    local key=name and P.Key(name)
    for _,unit in ipairs({"target","mouseover","focus","targettarget"}) do
        local e=enemy(unit); if e and (not key or e.key==key) then return e end
    end
    -- Replies require a locally visible requester. Never enumerate hidden players.
    if not key then return end
    local plates=P.Read(C_NamePlate and C_NamePlate.GetNamePlates)
    if type(plates)~="table" then return end
    for i=1,64 do
        local plate=P.Read(function() return plates[i] end)
        if not plate then break end
        local forbidden=P.Read(function() return plate.IsForbidden and plate:IsForbidden() end)
        if forbidden==false then
            local token=P.Read(function() return plate.namePlateUnitToken end)
            if type(token)=="string" then local e=enemy(token); if e and e.key==key then return e end end
        end
    end
end
local function send(packet,route,target)
    if not packet then return false end
    if route=="CHANNEL" then return A.SendReportChannel(PREFIX,packet) end
    local restricted=C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
    if type(restricted)=="function" and P.Read(restricted)~=false then return false end
    local result=P.Read(C_ChatInfo and C_ChatInfo.SendAddonMessage,PREFIX,packet,route,target)
    local ok=result==true or result==(Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0)
    if A.Trace then A.Trace("SCOUT_SEND",packet:sub(3,3).." "..route.." "..(ok and "accepted; receipt unconfirmed" or "unavailable")) end
    return ok
end
local function changed()
    updateTimer()
    -- A held-open map tooltip must not retain expired affiliation text.
    if A.tooltipRecord then GameTooltip:Hide(); A.tooltipRecord=nil end
    if A.RefreshReportSurfaces then A.RefreshReportSurfaces() end
end
function A.BeginEnemyScout(report,token)
    if not live() or not report or not A.records[report.id] then return end
--@dev
    if report.test then return end
--@enddev
    local e=observed(); if not e then return end
    local now=GetTime()
    if count(S.pending)>=8 or (S.probed[e.key] and now-S.probed[e.key]<30) then return end
    local faction,ruleset,region=P.Scope(); if not faction then return end
    local nonce=P.UUID(); S.probed[e.key]=now
    local r=A.records[report.id]
    r.scout={state="pending",enemy=e.name,nonce=nonce}
    S.pending[nonce]={id=r.id,token=token,enemy=e.name,key=e.key,faction=e.faction,untilAt=now+10}
    local packet=P.Pack({"1","Q",nonce,tostring(GetServerTime()),faction,ruleset,region})
    if not send(packet,"WHISPER",e.name) then S.pending[nonce]=nil; r.scout.state="unknown" end
    changed()
end
local function affiliation()
    if not W.enabled then return end
    local h,m=W.host,W.member
    local id=h and h.id or m and m.untilAt>GetTime() and m.id
    local r=id and W.records[id]
    if not r or r.expiresAt<=GetServerTime() or r.updatedAt<=GetServerTime()-90 then return end
    if m and not h and (m.session~=r.session or m.ownerKey~=r.ownerKey) then return end
--@dev
    if r.simulated then return end
--@enddev
    return r
end
local function scope(f)
    local own,ruleset,region=P.Scope()
    return own and (f[5]=="H" or f[5]=="A") and f[5]~=own and f[6]==ruleset and f[7]==region
end
local function readableText(s,max)
    return type(s)=="string" and #s>0 and #s<=max and not s:find("[|%c]")
end
local function snapshot(f,relay)
    local at=P.Integer(f[4],GetServerTime()-89,GetServerTime()+5)
    local id=f[relay and 9 or 8]
    -- R: nonce, time, scope, UUID/session/seq, members/parties/state/title.
    -- S: report token, time, scope, observed name, UUID, members/parties/state/title.
    local members=P.Integer(f[relay and 10 or 11],1,P.MAX_MEMBERS)
    local parties=P.Integer(f[relay and 11 or 12],0,P.MAX_GROUPS)
    local state=f[relay and 12 or 13]; local title=f[relay and 13 or 14]
    if not at or not P.UUIDValid(id) or not members or not parties or not readableText(title,40)
        or not ({forming=true,roaming=true,rallying=true})[state] then return end
    if not relay and (not P.UUIDValid(f[9]) or not P.Integer(f[10],1,2147483647)) then return end
    return {state="known",warbandID=id,title=title,members=members,parties=parties,
        activity=state,updatedAt=at,expiresAt=at+90}
end
local function attach(id,intel)
    local r=A.records[id]
    if not r or r.expiresAt<=GetServerTime() or intel.expiresAt<=GetServerTime()
        or intel.updatedAt<r.updatedAt-90 or intel.updatedAt>r.updatedAt+15 then return false end
--@dev
    if r.test or r.demo then return false end
--@enddev
    if r.scout and r.scout.state=="known" then return false end
    intel.expiresAt=math.min(intel.expiresAt,r.expiresAt)
    r.scout=intel; changed(); return true
end
function A.ResolveEnemyScout(report)
    local orphan=S.orphans[report.id]
    if not orphan then return end
    S.orphans[report.id]=nil
    if orphan.untilAt>GetTime() then attach(report.id,orphan.intel) end
end
function A.OnScoutMessage(prefix,packet,route,sender,_,zoneID,localID,channelName)
    if secret(prefix) or secret(packet) or secret(route) or secret(sender) then return end
    if prefix~=PREFIX or not live() or not P.Name(sender) then return end
    if route=="CHANNEL" then
        if not A.IsReportChannel(localID,channelName) then return end
    elseif route~="WHISPER" and (route~="GUILD" or P.Read(IsInGuild)~=true) then return end
    local f=P.Fields(packet)
    if not f or not scope(f) then return end
    local now=GetTime(); local key=P.Key(sender)
    local rate=S.rates[key]
    if not rate then if count(S.rates)>=64 then return end; rate={at=now,tokens=4}; S.rates[key]=rate end
    updateTimer()
    rate.tokens=math.min(4,rate.tokens+math.max(0,now-rate.at)/5); rate.at=now
    S.tokens=math.min(16,S.tokens+math.max(0,now-S.refill)*2); S.refill=now
    if rate.tokens<1 or S.tokens<1 then return end
    rate.tokens=rate.tokens-1; S.tokens=S.tokens-1
    if f[2]=="Q" and route=="WHISPER" then
        if #f~=7 or not P.UUIDValid(f[3]) or not P.Integer(f[4],GetServerTime()-10,GetServerTime()+5)
            or (rate.replyAt and now-rate.replyAt<30) then return end
        local visible=observed(sender); local r=affiliation()
        if not visible or not r or f[5]~=(visible.faction=="Horde" and "H" or "A") then return end
        rate.replyAt=now
        local parties=0
        for _,g in pairs(r.groups or {}) do if g.expiresAt>GetServerTime() then parties=parties+1 end end
        local own,ruleset,region=P.Scope()
        send(P.Pack({"1","R",f[3],tostring(r.updatedAt),own,ruleset,region,r.id,r.session,tostring(r.seq),
            tostring(r.count),tostring(parties),r.status,r.title}),"WHISPER",sender)
    elseif f[2]=="R" and route=="WHISPER" and #f==14 then
        local pending=S.pending[f[3]]
        if not pending or pending.untilAt<=now or pending.key~=key
            or f[5]~=(pending.faction=="Horde" and "H" or "A") then return end
        local intel=snapshot(f,false); if not intel then return end
        S.pending[f[3]]=nil; intel.enemy=pending.enemy
        if not attach(pending.id,intel) then return end
        if A.Trace then A.Trace("SCOUT_RECEIVE","report="..pending.id.." enemy="..intel.enemy.." affiliation=self-reported") end
        send(P.Pack({"1","S",pending.token,f[4],f[5],f[6],f[7],intel.enemy,intel.warbandID,
            tostring(intel.members),tostring(intel.parties),intel.activity,intel.title}),"CHANNEL")
    elseif f[2]=="S" and (route=="CHANNEL" or route=="GUILD") and #f==13 then
        if type(f[3])~="string" or #f[3]>40 or not f[3]:match("^%d+%-%d+%-%d+$") or not P.Name(f[8]) then return end
        local intel=snapshot(f,true); if not intel then return end
        intel.enemy=f[8]
        local id=A.ReportID(sender,f[3])
        if A.records[id] then
            if attach(id,intel) and A.Trace then A.Trace("SCOUT_RELAY","report="..id.." reporter="..sender) end
        elseif not S.orphans[id] and count(S.orphans)<32 then
            S.orphans[id]={intel=intel,untilAt=now+10}
        end
    end
end
function A.ScoutTick()
    local now=GetTime()
    if S.lastTick and now-S.lastTick<1 then return end
    S.lastTick=now; local dirty=false
    for nonce,p in pairs(S.pending) do if p.untilAt<=now or not live() then
        S.pending[nonce]=nil
        local r=A.records[p.id]
        if r and r.scout and r.scout.nonce==nonce then r.scout.state="unknown"; dirty=true end
    end end
    for id,o in pairs(S.orphans) do if o.untilAt<=now then S.orphans[id]=nil end end
    for key,at in pairs(S.probed) do if now-at>=30 then S.probed[key]=nil end end
    for key,r in pairs(S.rates) do if now-r.at>=120 then S.rates[key]=nil end end
    for _,r in pairs(A.records) do if r.scout and r.scout.state=="known" and r.scout.expiresAt<=GetServerTime() then
        r.scout={state="expired",enemy=r.scout.enemy}; dirty=true
    end end
    if dirty then changed() elseif A.RefreshScoutUI then A.RefreshScoutUI() end
    updateTimer()
end
function A.ClearScouting()
    S.pending={}; S.orphans={}; S.probed={}; S.rates={}
    for _,r in pairs(A.records) do r.scout=nil end
    changed()
end
function A.ScoutSummary(r)
    local s=r and r.scout
    if s and s.state=="known" and s.expiresAt>GetServerTime() then
        return "Enemy warband: "..s.title.." | "..s.members.." members (reported)"
    end
    return ""
end
function A.InitScouting()
    local result=P.Read(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix,PREFIX)
    local codes=Enum and Enum.RegisterAddonMessagePrefixResult
    S.ready=result==true or result==(codes and codes.Success or 0) or result==(codes and codes.DuplicatePrefix or 1)
    local frame=CreateFrame("Frame"); S.events=frame
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent",function(_,_,...) A.OnScoutMessage(...) end)
end
