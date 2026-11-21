local _, A = ...
local P=A.WB
local W={records={},history={},owners={},watches={},subscribers={},queue={},invites={},inviteConsents={},rates={}}
A.warbands=W
local HOME=Enum and Enum.PartyCategory and Enum.PartyCategory.Home or 1
local lastFlush=-10; local budget,refill=40,0
local function size(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function trace(kind,message) if A.Trace then A.Trace("WARBAND_"..kind,message) end end
local function changed()
    if A.RefreshWarbandUI then A.RefreshWarbandUI() end
    if A.RefreshMap then A.RefreshMap() end
end
local function enqueue(packet,route,target,key)
    if not packet then return false end
    key=key or (route..":"..(target or "")..":"..packet:sub(1,3))
    key=P.ActivePrefix()..":"..key
    if not W.queue[key] and size(W.queue)>=96 then trace("DROP","outgoing queue full"); return false end
    local previous=W.queue[key]; local kind=packet:sub(3,3)
    W.queue[key]={packet=packet,route=route,target=target,at=GetTime(),prefix=P.ActivePrefix(),
        order=previous and previous.order or GetTime(),priority=(kind=="A" or kind=="G") and 1 or 0,key=key}
    return true
end
local function whisper(packet,target,key) return enqueue(packet,"WHISPER",target,key) end
function A.QueueWarbandWhisper(packet,target,key) return whisper(packet,target,key) end
local function flush()
    if GetTime()-lastFlush<.25 then return end
    local nextItem
    for key,item in pairs(W.queue) do
        if GetTime()-item.at>25 then W.queue[key]=nil
        elseif not nextItem or item.priority<nextItem.priority
            or (item.priority==nextItem.priority and (item.order<nextItem.order or (item.order==nextItem.order and key<nextItem.key))) then nextItem=item end
    end
    if not nextItem then return end
    W.queue[nextItem.key]=nil; lastFlush=GetTime()
    local result=P.Read(C_ChatInfo and C_ChatInfo.SendAddonMessage,nextItem.prefix,nextItem.packet,nextItem.route,nextItem.target)
    local ok=result==true or result==(Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0)
    W.sendStatus=ok and "accepted; delivery unconfirmed" or "rejected/unavailable"
    trace("SEND",nextItem.prefix.." "..nextItem.route.." "..nextItem.packet:sub(1,3).." "..W.sendStatus)
end
function A.WarbandNativeInfo()
    if P.Read(IsInRaid,HOME)~=false then return nil,"Normal parties only; raids are not supported." end
    if P.Read(IsInInstance)~=false then return nil,"Move outdoors before using warbands." end
    local own=P.UnitName("player"); if not own then return nil,"Character identity unavailable." end
    local grouped=P.Read(IsInGroup,HOME)
    if grouped==false then return {mode="solo",leader=own,count=1} end
    if grouped~=true then return nil,"Group state unavailable." end
    local count=P.Read(GetNumGroupMembers,HOME)
    if type(count)~="number" or count%1~=0 or count<2 or count>5 then return nil,"Party roster unavailable." end
    local faction=P.Read(UnitFactionGroup,"player"); local leader
    for _,unit in ipairs({"player","party1","party2","party3","party4"}) do
        if unit=="player" or P.Read(UnitExists,unit)==true then
            if P.Read(UnitFactionGroup,unit)~=faction then return nil,"All party members must have a readable matching faction." end
            if P.Read(UnitIsGroupLeader,unit)==true then leader=P.UnitName(unit) end
        end
    end
    if not leader then return nil,"Party leader unavailable." end
    return {mode=P.Key(leader)==P.Key(own) and "leader" or "member",leader=leader,count=count}
end
local function coordinationInfo()
--@dev
    if P.IsSimulation() then return A.WarbandSimulationInfo() end
--@enddev

    return A.WarbandNativeInfo()
end
local function rootMatch(f,sender)
    local m=W.member
    return m and f[3]==m.id and f[4]==m.session and P.Key(sender)==m.ownerKey
end
local function broadcast(packet,kind,id)
    if P.Read(IsInGuild)==true then enqueue(packet,"GUILD",nil,kind..id..":GUILD") end
    if P.Read(IsInGroup,HOME)==true and P.Read(IsInRaid,HOME)==false then enqueue(packet,"PARTY",nil,kind..id..":PARTY") end
    local targets={}
    for key,s in pairs(W.subscribers) do if s.untilAt>GetTime() then targets[key]=s.name end end
    for key,m in pairs(W.host and W.host.members or {}) do if key~=P.Key(P.UnitName("player")) then targets[key]=m.name end end
    for key,name in pairs(targets) do whisper(packet,name,kind..id..":"..key) end
end
local function closeHistory(id,owner,session,seq)
    W.history[id]={owner=owner,session=session,maxSeq=seq,closed=true,untilAt=GetTime()+190,seq={}}
end
local function forgetMember(key)
    local h=W.host; local m=h and h.members[key]; if not m then return end
    h.members[key]=nil; W.invites[key]=nil
    local g=h.groups[m.slot]
    if g and g.key==key then
        g.active=false
        -- Retire this slot until all its members leave; never silently reassign
        -- a vanished group's recruits to a different host under the same slot.
        g.retired=true
    end
    local occupied=false; for _,other in pairs(h.members) do if other.slot==m.slot then occupied=true end end
    if not occupied and m.slot~=1 then h.groups[m.slot]=nil end
    h.dirty=true
end
function A.WarbandPrune()
    local dirty=false; local now,clock=GetServerTime(),GetTime()
    for id,r in pairs(W.records) do
        if r.expiresAt<=now then W.records[id]=nil; dirty=true end
        for slot,g in pairs(r.groups or {}) do if g.expiresAt<=now then r.groups[slot]=nil; dirty=true end end
    end
    for id,h in pairs(W.history) do if h.untilAt<=clock then W.history[id]=nil end end
    for key,o in pairs(W.owners) do if o.untilAt<=clock then W.owners[key]=nil end end
    for key,s in pairs(W.subscribers) do if s.untilAt<=clock then W.subscribers[key]=nil end end
    for key,r in pairs(W.rates) do if r.at+190<=clock then W.rates[key]=nil end end
    for key,i in pairs(W.invites) do if i.untilAt<=clock then W.invites[key]=nil; dirty=true end end
    if W.join and W.join.untilAt<=clock then W.join=nil; A.Print("Warband join timed out; no automatic retry."); dirty=true end
    if W.member and W.member.untilAt<=clock then W.member=nil; W.invites={}; A.Print("Warband membership expired; rejoin the listing. Your WoW party was not changed."); dirty=true end
    if W.host then
        for key,m in pairs(W.host.members) do
            if key~=W.host.ownerKey and m.untilAt<=clock then forgetMember(key); dirty=true end
        end
    end
    return dirty
end
function A.WarbandList()
    local list={}; if not W.enabled then return list end
    for _,r in pairs(W.records) do if r.expiresAt>GetServerTime() then list[#list+1]=r end end
    table.sort(list,function(a,b) return a.title<b.title or (a.title==b.title and a.id<b.id) end)
    return list
end
local function ownGroup(info)
    local h=W.host; local g=h.groups[1]; local m=h.members[h.ownerKey]
    m.nativeHost=info.leader; m.count=info.count
    local loc=A.CurrentLocation()
    g.count=info.count; g.active=loc~=nil; g.updatedAt=GetServerTime()
    if loc then g.mapID,g.x,g.y=loc.mapID,loc.x,loc.y end
end
local function groupPayload(h)
    local rows={}
    for slot=1,P.MAX_GROUPS do
        local g=h.groups[slot]
        if g and not g.retired and g.active and g.updatedAt+P.TTL>GetServerTime() then
            local values={slot,g.mapID,math.floor(g.x*10000+.5),math.floor(g.y*10000+.5),g.count,math.max(0,GetServerTime()-g.updatedAt)}
            for i,v in ipairs(values) do values[i]=P.Base36(v) end
            rows[#rows+1]=table.concat(values,",")
        end
    end
    return table.concat(rows,";")
end
local function readGroups(data,at)
    if type(data)~="string" or #data>100 then return end
    local result={}; local count=0
    if data=="" then return result end
    for row in (data..";"):gmatch("(.-);") do
        count=count+1; if count>P.MAX_GROUPS then return end
        local v={}; for s in (row..","):gmatch("(.-),") do v[#v+1]=s; if #v>6 then return end end
        if #v~=6 then return end
        local slot,map,x,y,n,age=P.Unbase36(v[1],P.MAX_GROUPS),P.Unbase36(v[2],100000),P.Unbase36(v[3],10000),P.Unbase36(v[4],10000),P.Unbase36(v[5],5),P.Unbase36(v[6],89)
        if not slot or slot<1 or not map or map<1 or not x or not y or not n or n<1 or not age or result[slot] then return end
        result[slot]={slot=slot,mapID=map,x=x/10000,y=y/10000,count=n,updatedAt=at-age,
            expiresAt=math.min(at-age+P.TTL,GetServerTime()+P.TTL)}
    end
    return result
end
local function publish()
    local h=W.host; if not h then return end
    local info,reason=coordinationInfo()
    if not info or info.mode=="member" then A.StopWarband(reason or "Coordinator no longer leads a normal party."); return end
    ownGroup(info)
    local loc=h.mode=="follow" and A.CurrentLocation() or h.rally
    if not loc then A.StopWarband("Location unavailable; restart when outdoors."); return end
    h.seq=h.seq+1
    local fields=P.Header("A",h.id,W.session,h.seq); if not fields then return end
    local tail={h.revision,loc.mapID,math.floor(loc.x*10000+.5),math.floor(loc.y*10000+.5),h.status,h.recruiting and "1" or "0",h.mode,size(h.members),h.title}
    for _,v in ipairs(tail) do fields[#fields+1]=tostring(v) end
    local packet=P.Pack(fields); local r=P.DecodeState(fields)
    if not packet or not r then A.Print("Warband snapshot could not be encoded."); return end
    r.owner=h.owner; r.ownerKey=h.ownerKey; r.groups=readGroups(groupPayload(h),GetServerTime())
    W.records[h.id]=r
    broadcast(packet,"A",h.id)
    h.seq=h.seq+1; local groups=P.Header("G",h.id,W.session,h.seq); groups[11]=groupPayload(h)
    broadcast(P.Pack(groups),"G",h.id)
    h.lastPublish=GetTime(); h.lastLoc=loc; h.dirty=false
    trace("SNAPSHOT","id="..h.id.." seq="..h.seq.." members="..size(h.members))
    changed()
end
function A.StartWarband(title,reportID)
    if W.host or W.member or W.join then return false,"Leave/end your current warband or pending join first." end
    if not W.ready or not P.Scope() then return false,"Warband messaging/scope unavailable." end
    if W.lastStart and GetTime()-W.lastStart<15 then return false,"Wait 15 seconds between starting warbands." end
    if type(title)~="string" or #title<1 or #title>40 or title:find("[|%c]") then return false,"Use a warband name of 1-40 bytes without markup." end
    local info,reason=coordinationInfo(); if not info then return false,reason end
    if info.mode=="member" then return false,"Your normal party leader must start or join first." end
    local loc=A.CurrentLocation(); if not loc then return false,"Current outdoor location unavailable." end
    local report=reportID and A.records[reportID]
    if reportID and (not report or report.expiresAt<=GetServerTime()) then return false,"That field report expired." end
--@dev
    if report and report.test and not P.IsSimulation() then return false,"Use a simulated warband for a test report." end
--@enddev
    W.enabled=true; W.lastStart=GetTime()
    local owner=P.UnitName("player"); local key=P.Key(owner)
    W.host={id=P.UUID(),owner=owner,ownerKey=key,title=title,status=report and "rallying" or "forming",mode=report and "rally" or "follow",rally=report and {mapID=report.mapID,x=report.x,y=report.y} or loc,sourceReportID=reportID,
        recruiting=true,seq=0,revision=1,members={},groups={}}
    W.host.members[key]={name=owner,session=W.session,slot=1,nativeHost=info.leader,count=info.count,untilAt=math.huge}
    W.host.groups[1]={name=owner,key=key,count=info.count}
    publish(); flush()
--@dev
    if not P.IsSimulation() then A.Print(A.ScoutDisclosure) end
--@enddev
--@release     A.Print(A.ScoutDisclosure)
    if A.FinderSync then A.FinderSync(true) end
--@dev
    return true,(P.IsSimulation() and "[TEST] Simulated warband started. " or "Warband started. ").."Guild/party subscribers can join; group leaders share positions. UUID: "..W.host.id
--@enddev
--@release     return true,"Warband started. Guild/party subscribers can join; group leaders share positions. UUID: "..W.host.id
end
function A.StopWarband(reason)
    local h=W.host; if not h then return end
    -- Remove every unsent old state before enqueueing terminal snapshots.
    for key,item in pairs(W.queue) do if item.packet:find(h.id,1,true) then W.queue[key]=nil end end
    h.seq=h.seq+1; local fields=P.Header("E",h.id,W.session,h.seq)
    if fields then broadcast(P.Pack(fields),"E",h.id) end
    closeHistory(h.id,h.ownerKey,W.session,h.seq)
    W.records[h.id]=nil; W.host=nil; W.invites={}; W.inviteConsents={}; W.subscribers={}
    trace("END",h.id.." "..(reason or "user")); changed(); flush()
    if A.FinderSync then A.FinderSync() end
    A.Print("Warband ended: "..(reason or "user")..". WoW parties remain unchanged.")
end
function A.LeaveWarband()
    if W.host then A.StopWarband("organizer ended it"); return end
    local m=W.member or W.join
    if m then
        for key,item in pairs(W.queue) do if item.packet:find(m.id,1,true) then W.queue[key]=nil end end
        whisper(P.Request("L",m.id,m.session,P.UUID(),{m.memberSession}),m.owner,"LEAVE:"..m.id)
    end
    W.member=nil; W.join=nil; W.invites={}; W.inviteConsents={}; changed(); flush()
    if A.FinderSync then A.FinderSync() end
end
function A.SetWarbandsEnabled(enabled)
    if not enabled then
        A.LeaveWarband()
        for _,s in pairs(W.watches) do whisper(P.Request("X",nil,nil,P.UUID()),s.name,"UNWATCH:"..P.Key(s.name)) end
        W.watches={}; W.records={}
        for key,item in pairs(W.queue) do
            local kind=item.packet:sub(3,3)
            if kind~="L" and kind~="X" and kind~="E" then W.queue[key]=nil end
        end
    end
    W.enabled=enabled==true and W.ready==true; changed()
    if A.FinderSync then A.FinderSync(); if W.enabled then A.FinderSearch() end end
--@dev
    A.Print(W.enabled and ((P.IsSimulation() and "[TEST] " or "").."Warband discovery ON this session (guild/party and named subscriptions).") or "Warband discovery OFF.")
--@enddev
--@release     A.Print(W.enabled and "Warband discovery ON this session (guild/party and named subscriptions)." or "Warband discovery OFF.")
end
function A.WatchWarband(name,expectedID,expectedSession)
    local key=P.Key(name)
    if not key or not W.ready or not P.Scope() then return false,"Valid full character name and messaging required." end
    if not W.watches[key] and size(W.watches)>=8 then return false,"At most eight named subscriptions." end
    if W.watches[key] and GetTime()-W.watches[key].at<5 then return false,"Wait before resubscribing." end
    W.enabled=true; W.watches[key]={name=name,at=GetTime(),expectedID=expectedID,expectedSession=expectedSession}
    whisper(P.Request("S",nil,nil,P.UUID()),name,"SUB:"..key); flush()
    return true,"Subscribed to "..name.."; their active warband will appear when received."
end
function A.UnwatchWarband(name)
    local key=P.Key(name); local watch=key and W.watches[key]
    if not watch then return false,"No subscription for that character." end
    W.watches[key]=nil
    for q,item in pairs(W.queue) do
        if item.route=="WHISPER" and P.Key(item.target)==key and item.packet:sub(3,3)=="S" then W.queue[q]=nil end
    end
    whisper(P.Request("X",nil,nil,P.UUID()),watch.name,"UNWATCH:"..key); flush(); changed()
    return true,"Subscription removed."
end
function A.JoinWarband(id)
    local r=W.records[id]
    if W.host or W.join or (W.member and W.member.id~=id) then return false,"Already in a warband or waiting for a join reply." end
    if not r or r.expiresAt<=GetServerTime() or (not r.recruiting and not (W.member and W.member.id==id)) then return false,"Listing expired or recruiting closed." end
    local info,reason=coordinationInfo(); if not info then return false,reason end
--@dev
    if not P.IsSimulation() then A.Print(A.ScoutDisclosure) end
--@enddev
--@release     A.Print(A.ScoutDisclosure)
    local nonce=P.UUID()
    local memberSession=W.member and W.member.memberSession or P.UUID()
    W.join={id=id,session=r.session,owner=r.owner,ownerKey=r.ownerKey,nonce=nonce,memberSession=memberSession,untilAt=GetTime()+30}
    whisper(P.Request("J",id,r.session,nonce,{info.mode,info.leader,info.count,memberSession}),r.owner,"JOIN:"..id)
--@dev
    flush(); changed(); return true,P.IsSimulation() and "[TEST] Joining as a separate simulated party host; no native invitation." or "Joining WBP warband; native party invitations are a separate step."
--@enddev
--@release     flush(); changed(); return true,"Joining WBP warband; native party invitations are a separate step."
end
local function capacity(h,slot)
    local g=h.groups[slot]; if not g or g.retired then return 0 end
    local waiting,joined=0,0
    for _,m in pairs(h.members) do if m.slot==slot then
        if P.Key(m.nativeHost)==g.key then joined=joined+1 else waiting=waiting+1 end
    end end
    return 5-math.max(g.count or 1,joined)-waiting
end
local function handleJoin(f,sender,key)
    local h=W.host
    local code,slot,host="closed",0,"-"
--@dev
    if P.IsSimulation() and (f[10]~="leader" or P.Key(f[11])~=key) then code="invalid-test-party"
    elseif h.recruiting or (h.members[key] and h.members[key].session==f[13]) then
--@enddev
--@release     if h.recruiting or (h.members[key] and h.members[key].session==f[13]) then
        local existing=h.members[key]
        if existing and existing.session==f[13] then
            local g=h.groups[existing.slot]
            if not g or g.retired then code="group-host-unavailable"
            else
                slot=existing.slot; host=g.name; code="joined"
                if key~=g.key and P.Key(f[11])~=g.key then
                    if g.key==h.ownerKey then W.invites[key]={name=sender,slot=slot,untilAt=GetTime()+30}
                    else whisper(P.Request("I",h.id,W.session,P.UUID(),{slot,sender}),g.name,"INVITE:"..key) end
                end
            end
        elseif existing then code="old-session-wait"
        elseif size(h.members)>=P.MAX_MEMBERS then code="warband-full"
        else
            local mode,native,count=f[10],f[11],tonumber(f[12])
            if mode=="member" then
                for i,g in pairs(h.groups) do if not g.retired and g.key==P.Key(native) then slot=i end end
                if slot==0 then code="party-leader-first" end
            elseif mode=="leader" then
                if P.Key(native)~=key then code="invalid-leader" else
                    for i=1,P.MAX_GROUPS do if not h.groups[i] then slot=i; break end end
                    if slot==0 then code="groups-full" end
                end
            else
                if P.Key(native)~=key then code="invalid-leader" else
                    for i=1,P.MAX_GROUPS do if capacity(h,i)>0 then slot=i; break end end
                    if slot==0 then for i=1,P.MAX_GROUPS do if not h.groups[i] then slot=i; break end end end
                    if slot==0 then code="groups-full" end
                end
            end
            if slot>0 then
                local g=h.groups[slot]
                if not g then g={name=sender,key=key,count=count,active=false}; h.groups[slot]=g end
                local assigned=0; for _,m in pairs(h.members) do if m.slot==slot then assigned=assigned+1 end end
                if mode=="member" and assigned>=5 then slot=0; code="party-full"
                else
                    h.members[key]={name=sender,session=f[13],slot=slot,nativeHost=native,count=count,seq=0,untilAt=GetTime()+90,lastAck=GetTime()}
                    host=g.name; code="joined"; h.dirty=true
                    if key~=g.key and P.Key(native)~=g.key then
                        local packet=P.Request("I",h.id,W.session,P.UUID(),{slot,sender})
                        if g.key==h.ownerKey then W.invites[key]={name=sender,slot=slot,consented=true,untilAt=GetTime()+30}
                        else whisper(packet,g.name,"INVITE:"..key) end
                    end
                end
            end
        end
    end
    whisper(P.Request("R",h.id,W.session,f[5],{code,slot,host}),sender,"JOIN_REPLY:"..key)
    trace("JOIN",key.." "..code.." slot="..slot); changed()
end
function A.InviteWarbandMember(name)
--@dev
    if P.IsSimulation() then return false,"[TEST] Native party invitations are disabled for simulated warbands." end
--@enddev

    local key=P.Key(name); local invite=key and W.invites[key]
    if not invite or invite.untilAt<=GetTime() then return false,"No fresh request for that player." end
    local info,reason=A.WarbandNativeInfo()
    if not info or info.mode=="member" or info.count>=5 then return false,reason or "You must lead a party with space." end
    if P.Read(InCombatLockdown)~=false then return false,"Use Invite after combat." end
    local fn=C_PartyInfo and C_PartyInfo.InviteUnit
    if type(fn)~="function" then return false,"Invite API unavailable; invite this player using the game UI." end
    if P.UnitFor(invite.name) then W.invites[key]=nil; changed(); return true,"Already in your party." end
    if invite.attemptedAt and GetTime()-invite.attemptedAt<5 then return false,"Wait before retrying the invitation." end
    invite.attemptedAt=GetTime()
    local ok,result=pcall(fn,invite.name)
    local accepted=ok and not (issecretvalue and issecretvalue(result)) and result~=false
    invite.blocked=not accepted; changed()
    if A.Trace then A.Trace("PARTY_INVITE", "player="..invite.name.." result="..(accepted and "attempted; acceptance unconfirmed" or "blocked")) end
    return accepted,accepted and "Invitation attempted; accept WoW's invitation to join the party." or "Invitation blocked. Retry here when available."
end
local function autoInvite()
--@dev
    if P.IsSimulation() or A.testMode then return end
--@enddev
    if P.Read(InCombatLockdown)~=false then return end
    local now=GetTime(); W.inviteAttempts=W.inviteAttempts or {}
    for key,c in pairs(W.inviteConsents) do if c.untilAt<=now then W.inviteConsents[key]=nil end end
    for i=#W.inviteAttempts,1,-1 do if now-W.inviteAttempts[i]>=60 then table.remove(W.inviteAttempts,i) end end
    if #W.inviteAttempts>=6 or (W.lastAutoInvite and now-W.lastAutoInvite<3) then return end
    local chosen
    for key,invite in pairs(W.invites) do
        local consent=W.inviteConsents[key]
        local root=W.host or W.member
        local session=W.host and W.session or W.member and W.member.session
        local allowed=invite.consented or (consent and root and consent.id==root.id and consent.session==session and consent.slot==invite.slot and consent.untilAt>now)
        if P.UnitFor(invite.name) then W.invites[key]=nil
        elseif allowed and not invite.attemptedAt and invite.untilAt>now and (not chosen or invite.name<chosen.name) then chosen=invite end
    end
    if not chosen then return end
    local info=A.WarbandNativeInfo()
    if not info or info.mode=="member" or info.count>=5 then return end
    W.lastAutoInvite=now; W.inviteAttempts[#W.inviteAttempts+1]=now
    -- Exactly one automatic attempt per request; native confirmation stays native.
    A.InviteWarbandMember(chosen.name)
    chosen.attemptedAt=now
end
local function handleUpdate(f,sender,key)
    local h=W.host; local m=h and h.members[key]
    if not m or #f~=17 or f[3]~=h.id or f[4]~=W.session or f[5]~=m.session then return end
--@dev
    if P.IsSimulation() and (f[12]~="leader" or P.Key(f[13])~=key) then return end
--@enddev

    local seq=P.Integer(f[6],1,2147483647); local at=P.Integer(f[7],GetServerTime()-89,GetServerTime()+5)
    local expires=P.Integer(f[8],GetServerTime()+1,GetServerTime()+95)
    local count=P.Integer(f[14],1,5); local map=P.Integer(f[15],1,100000)
    local x,y=P.Integer(f[16],0,10000),P.Integer(f[17],0,10000)
    if not seq or seq<=(m.seq or 0) or not at or not expires or expires-at~=90 or not count or not map or not x or not y
        or not ({solo=true,leader=true,member=true})[f[12]] or not P.Name(f[13]) or not P.ScopeMatches(f[9],f[10],f[11]) then return end
    m.seq=seq; m.untilAt=GetTime()+math.min(90,expires-GetServerTime()); m.nativeHost=f[13]; m.count=count
    local g=h.groups[m.slot]
    if g and g.key==key and not g.retired then
        g.active=f[12]~="member" and P.Key(f[13])==key
        g.count=count; g.mapID=map; g.x=x/10000; g.y=y/10000; g.updatedAt=at; h.dirty=true
    end
    if GetTime()-(m.lastAck or 0)>=30 then
        whisper(P.Request("K",h.id,W.session,m.session,{seq,m.slot,g and g.name or "-"}),sender,"LEASE:"..key)
        m.lastAck=GetTime()
    end
end
local function handleState(f,sender,key,route)
    if not W.enabled then return end
    local r=P.DecodeState(f); if not r then return end
    if route=="GUILD" then if P.Read(IsInGuild)~=true then return end
    elseif route=="PARTY" then
        local unit=P.UnitFor(sender)
        if P.Read(IsInGroup,HOME)~=true or P.Read(IsInRaid,HOME)~=false or not unit or P.Read(UnitIsGroupLeader,unit)~=true then return end
    elseif route=="WHISPER" then
        if not W.watches[key] and not (W.join and W.join.ownerKey==key) and not (W.member and W.member.ownerKey==key) then return end
        local watch=W.watches[key]
        if watch and watch.expectedID and (watch.expectedID~=r.id or watch.expectedSession~=r.session) then return end
    else return end
    if key==P.Key(P.UnitName("player")) then return end
    local old=W.history[r.id]
    if old and (old.owner~=key or old.session~=r.session or old.closed or r.seq<=(old.seq[f[2]] or 0)) then return end
    if not old and size(W.history)>=256 then return end
    local record=W.records[r.id]
    local owner=W.owners[key]
    if f[2]=="A" and owner and owner.id~=r.id and (r.updatedAt<=owner.updatedAt or GetTime()-owner.createdAt<15) then return end
    if f[2]=="A" and not owner and size(W.owners)>=128 then return end
    if f[2]=="G" and not record then return end
    local groups=f[2]=="G" and readGroups(f[11],r.updatedAt)
    if f[2]=="G" and not groups then return end
    if f[2]=="A" and not record and size(W.records)>=64 then return end
    old=old or {owner=key,session=r.session,seq={},maxSeq=0}
    if f[2]=="E" and r.seq<old.maxSeq then return end
    old.seq[f[2]]=r.seq; old.maxSeq=math.max(old.maxSeq,r.seq); old.untilAt=GetTime()+190; W.history[r.id]=old
    if f[2]=="E" then
        old.closed=true; W.records[r.id]=nil
        if W.join and W.join.id==r.id and W.join.ownerKey==key then W.join=nil end
        if W.member and W.member.id==r.id and W.member.ownerKey==key then W.member=nil; W.invites={}; A.Print("Your WBP warband ended. WoW parties remain unchanged.") end
    elseif f[2]=="G" then record.groups=groups
    else
        W.owners[key]={id=r.id,updatedAt=r.updatedAt,untilAt=GetTime()+190,
            createdAt=owner and owner.id==r.id and owner.createdAt or GetTime()}
        for id,prior in pairs(W.history) do if id~=r.id and prior.owner==key then prior.closed=true end end
        for id,prior in pairs(W.records) do if prior.ownerKey==key and id~=r.id then
            closeHistory(id,key,prior.session,prior.seq); W.records[id]=nil
        end end
        r.owner=sender; r.ownerKey=key; r.groups=record and record.groups or {}; W.records[r.id]=r
    end
    trace("RECEIVE",P.ActivePrefix().." "..f[2].." id="..r.id.." seq="..r.seq.." sender="..key); changed()
end
function A.OnWarbandMessage(prefix,packet,route,sender)
    if issecretvalue and (issecretvalue(prefix) or issecretvalue(packet) or issecretvalue(route) or issecretvalue(sender)) then return end
    if prefix~=P.ActivePrefix() or not W.ready or not W.enabled or not P.Name(sender) or type(packet)~="string" or #packet>255 then return end
--@dev
    if P.IsSimulation() and (not W.testReady or A.testMode~=true) then return end
--@enddev

    local key=P.Key(sender); local now=GetTime()
    local rate=W.rates[key]
    if not rate then if size(W.rates)>=128 then return end; rate={at=now,tokens=8}; W.rates[key]=rate end
    rate.tokens=math.min(8,rate.tokens+math.max(0,now-rate.at)*2); rate.at=now
    if rate.tokens<1 then return end; rate.tokens=rate.tokens-1
    budget=math.min(40,budget+math.max(0,now-refill)*8); refill=now
    if budget<1 then return end; budget=budget-1
    local f=P.Fields(packet); if not f then return end
    if f[2]=="A" or f[2]=="G" or f[2]=="E" then handleState(f,sender,key,route); return end
    if route~="WHISPER" or not W.enabled then return end
    if f[2]=="U" then handleUpdate(f,sender,key); return end
    if not P.DecodeRequest(f) then return end
    if (f[2]=="D" or f[2]=="F") and A.OnFinderDiscovery then A.OnFinderDiscovery(f,sender,key); return end
    -- A delegated party host needs consent from the actual recruit as well as
    -- the coordinator's assignment before making an automatic native invitation.
    if f[2]=="V" then
        local root=W.host or W.member
        local session=W.host and W.session or W.member and W.member.session
        local slot=W.host and 1 or W.member and W.member.slot
        if root and f[3]==root.id and f[4]==session and tonumber(f[10])==slot
            and P.Key(f[11])==P.Key(P.UnitName("player")) and (W.inviteConsents[key] or size(W.inviteConsents)<20) then
            W.inviteConsents[key]={id=f[3],session=f[4],slot=slot,untilAt=now+30-math.max(0,GetServerTime()-tonumber(f[6]))}
        end
        return
    end
    if f[2]=="K" and rootMatch(f,sender) and f[5]==W.member.memberSession then
        local seq=tonumber(f[10]); if seq<=(W.member.ackSeq or 0) or seq>(W.member.seq or 0) then return end
        W.member.ackSeq=seq; W.member.untilAt=now+90-math.max(0,GetServerTime()-tonumber(f[6])); return
    end
    if f[2]=="R" then
        local j=W.join
        if not j or j.untilAt<=now or j.ownerKey~=key or f[3]~=j.id or f[4]~=j.session or f[5]~=j.nonce then return end
        W.join=nil
        local listing=W.records[j.id]
        if not listing or listing.session~=j.session or listing.expiresAt<=GetServerTime() then changed(); return end
        if f[10]=="joined" and tonumber(f[11])>0 and f[12]~="-" then
            local previous=W.member
            W.member={id=j.id,session=j.session,owner=sender,ownerKey=key,slot=tonumber(f[11]),host=f[12],
                memberSession=j.memberSession,untilAt=now+90-math.max(0,GetServerTime()-tonumber(f[6])),seq=previous and previous.seq or 0,ackSeq=previous and previous.ackSeq or 0}
            if P.Key(f[12])~=P.Key(P.UnitName("player")) then
                whisper(P.Request("V",j.id,j.session,j.memberSession,{f[11],f[12]}),f[12],"INVITE_CONSENT:"..j.id)
            end
--@dev
            A.Print((P.IsSimulation() and "[TEST] " or "").."Joined WBP warband, group "..f[11].." led by "..f[12]..(P.IsSimulation() and ". Dummy roster only; no native grouping or layer test." or ". Accept a normal party invitation if needed; layer unverified."))
--@enddev
--@release             A.Print("Joined WBP warband, group "..f[11].." led by "..f[12]..". Accept a normal party invitation if needed; layer unverified.")
        else A.Print("Warband join: "..A.CleanText(f[10],32)) end
        changed(); return
    end
--@dev
    if f[2]=="I" and not P.IsSimulation() and rootMatch(f,sender) and P.Key(W.member.host)==P.Key(P.UnitName("player")) and tonumber(f[10])==W.member.slot then
--@enddev
--@release     if f[2]=="I" and rootMatch(f,sender) and P.Key(W.member.host)==P.Key(P.UnitName("player")) and tonumber(f[10])==W.member.slot then
        if rate.inviteNonce~=f[5] and size(W.invites)<5 then
            rate.inviteNonce=f[5]
            W.invites[P.Key(f[11])]={name=f[11],slot=tonumber(f[10]),untilAt=now+30-math.max(0,GetServerTime()-tonumber(f[6]))}; changed()
        end
        return
    end
    local h=W.host; if not h then return end
    if f[2]=="S" or f[2]=="X" then
        if rate.controlAt and now-rate.controlAt<5 then return end; rate.controlAt=now
        if f[2]=="X" then W.subscribers[key]=nil
        elseif W.subscribers[key] or size(W.subscribers)<8 then W.subscribers[key]={name=sender,untilAt=now+120}; h.dirty=true end
        return
    end
    if f[3]~=h.id or f[4]~=W.session then return end
    if f[2]=="L" then
        local m=h.members[key]
        if key~=h.ownerKey and (not m or m.session==f[10]) then
            rate.leftSession=f[10]; forgetMember(key); changed()
        end
    elseif f[2]=="J" then
        if rate.leftSession==f[13] then return end
        if rate.controlAt and now-rate.controlAt<5 then return end; rate.controlAt=now
        if rate.nonce==f[5] then return end; rate.nonce=f[5]
        handleJoin(f,sender,key)
    end
end
local function memberTick()
    local m=W.member; if not m or (m.sentAt and GetTime()-m.sentAt<15) then return end
    local info,reason=coordinationInfo()
    if not info then A.LeaveWarband(); A.Print(reason); return end
    local loc=A.CurrentLocation(); if not loc then return end
    local f,r,g=P.Scope(); if not f then return end
    m.seq=m.seq+1; m.sentAt=GetTime()
    local packet=P.Pack({"1","U",m.id,m.session,m.memberSession,tostring(m.seq),tostring(GetServerTime()),tostring(GetServerTime()+90),f,r,g,
        info.mode,info.leader,tostring(info.count),tostring(loc.mapID),tostring(math.floor(loc.x*10000+.5)),tostring(math.floor(loc.y*10000+.5))})
    whisper(packet,m.owner,"MEMBER:"..m.id)
end
function A.WarbandTick()
    if A.FinderTick then A.FinderTick() end
    if not W.enabled and not next(W.queue) then return end
    if W.lastMaintenance and GetTime()-W.lastMaintenance<1 then flush(); return end
    W.lastMaintenance=GetTime()
    local dirty=A.WarbandPrune()
    if W.enabled then
        if W.host then
            local info,reason=coordinationInfo()
            if not info or info.mode=="member" then A.StopWarband(reason or "Coordinator no longer leads a party.")
            else
                local loc=A.CurrentLocation(); local old=W.host.lastLoc
                local moved=loc and old and (loc.mapID~=old.mapID or math.abs(loc.x-old.x)+math.abs(loc.y-old.y)>.001)
                local interval=(W.host.dirty or (W.host.mode=="follow" and moved)) and 15 or 30
                if GetTime()-(W.host.lastPublish or -30)>=interval then publish() end
            end
        end
        memberTick()
        autoInvite()
        for key,s in pairs(W.watches) do if GetTime()-s.at>=60 then
            s.at=GetTime(); whisper(P.Request("S",nil,nil,P.UUID()),s.name,"SUB:"..key)
        end end
    end
    if dirty then changed() end
    flush()
end
function A.WarbandArrival(r)
    local m=W.member
--@dev
    if r.simulated then return "[TEST] Dummy party roster; native grouping/layer not tested" end
--@enddev

    if W.host and W.host.id==r.id then return "Coordinator; layer unverified" end
    if not m or m.id~=r.id then return "Not a member" end
    if not r.groups or not r.groups[m.slot] then return "Group host position unavailable; layer unverified" end
    local info=A.WarbandNativeInfo()
    if not info or P.Key(info.leader)~=P.Key(m.host) then return "Joined WBP; waiting for native party "..m.slot end
    return (W.transferPending and "World refresh pending" or "In assigned party; co-location unverified")
end
function A.WarbandCommand(input)
    local cmd,arg=input:match("^%s*(%S*)%s*(.-)%s*$"); cmd=cmd:lower()
    local ok,msg
--@dev
    if cmd=="simulate" then ok,msg=A.SetWarbandSimulation(arg)
    elseif cmd=="on" or cmd=="off" then A.SetWarbandsEnabled(cmd=="on")
--@enddev
--@release     if cmd=="on" or cmd=="off" then A.SetWarbandsEnabled(cmd=="on")
    elseif cmd=="start" then ok,msg=A.StartWarband(arg)
    elseif cmd=="stop" or cmd=="leave" then A.LeaveWarband()
    elseif cmd=="watch" then ok,msg=A.WatchWarband(arg)
    elseif cmd=="unwatch" then ok,msg=A.UnwatchWarband(arg)
    elseif cmd=="join" then ok,msg=A.JoinWarband(arg)
    elseif cmd=="invite" then ok,msg=A.InviteWarbandMember(arg)
    elseif cmd=="status" then
        A.Print("Warbands "..(W.enabled and "ON" or "OFF").." | "..A.WarbandModeStatus().." | listings="..#A.WarbandList().." | "..(W.host and ("organizing "..W.host.id) or W.member and ("member "..W.member.id.." group="..W.member.slot) or "not joined").." | send="..(W.sendStatus or "none"))
    elseif cmd=="rally" or cmd=="follow" or cmd=="recruit" or cmd=="state" then
        local h=W.host
        if not h then msg="Only the warband coordinator can change its listing."
        elseif cmd=="rally" then
            local loc=A.CurrentLocation(); if loc then h.rally=loc; h.mode="rally"; h.status="rallying"; h.dirty=true; h.revision=h.revision+1 else msg="Location unavailable." end
        elseif cmd=="follow" then h.mode="follow"; h.dirty=true; h.revision=h.revision+1
        elseif cmd=="recruit" and (arg=="on" or arg=="off") then h.recruiting=arg=="on"; h.dirty=true
        elseif cmd=="state" and ({forming=true,roaming=true,rallying=true})[arg] then h.status=arg; h.dirty=true
        else msg="Use recruit on/off or state forming/roaming/rallying." end
        if h and h.dirty then msg="Warband update queued (up to 15 seconds)." end
        if A.FinderSync then A.FinderSync() end
        changed()
    else A.ShowWarbands() end
    if msg then A.Print(msg) end
end
function A.ResetWarbandScope()
--@dev
    if P.IsSimulation() and A.SetWarbandSimulation then A.SetWarbandSimulation("off") end
--@enddev

    if W.host then A.StopWarband("audience scope changed") end
    W.member=nil; W.join=nil; W.invites={}; W.inviteConsents={}; W.records={}; W.watches={}; W.subscribers={}; W.queue={}; W.enabled=false
    changed()
end
function A.InitWarbands()
--@dev
    W.session=P.UUID(); W.enabled=false; W.simulationCount=nil
--@enddev
--@release     W.session=P.UUID(); W.enabled=false
    local result=P.Read(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix,P.PREFIX)
    local codes=Enum and Enum.RegisterAddonMessagePrefixResult
    W.ready=result==true or result==(codes and codes.Success or 0) or result==(codes and codes.DuplicatePrefix or 1)
    if not W.ready then return end
--@dev
    local testResult=P.Read(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix,P.TEST_PREFIX)
    W.testReady=testResult==true or testResult==(codes and codes.Success or 0) or testResult==(codes and codes.DuplicatePrefix or 1)
--@enddev

    local frame=CreateFrame("Frame")
    for _,e in ipairs({"CHAT_MSG_ADDON","GROUP_ROSTER_UPDATE","PARTY_LEADER_CHANGED","PLAYER_ENTERING_WORLD","PLAYER_LOGOUT","SHARD_TRANSFER_IMMINENT","SHARD_TRANSFER","SHARD_TRANSFER_CANCELLED"}) do pcall(frame.RegisterEvent,frame,e) end
    frame:SetScript("OnEvent",function(_,e,...)
        if e=="CHAT_MSG_ADDON" then A.OnWarbandMessage(...)
        elseif e=="PLAYER_LOGOUT" then A.LeaveWarband()
        else
            if e=="SHARD_TRANSFER_IMMINENT" then W.transferPending=true
            elseif e=="SHARD_TRANSFER" or e=="SHARD_TRANSFER_CANCELLED" or e=="PLAYER_ENTERING_WORLD" then W.transferPending=false end
            if W.host then W.host.dirty=true end
            A.WarbandTick(); changed()
        end
    end)
    W.timer=C_Timer.NewTicker(.25,A.WarbandTick)
end

function A.WarbandModeStatus() return "LIVE" end
function A.WarbandDisplayTitle(r) return r.title end
function A.WarbandCountText(r) return "WBP members: "..r.count.." (organizer-reported)" end
function A.WarbandGroupCountText(r,g) return "roster "..g.count.." (reported)" end
