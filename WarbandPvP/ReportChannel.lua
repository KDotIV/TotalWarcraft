local _,A=...
local NAME="TotalWarcraftReportComms"
local C={name=NAME,state="waiting for login"}
A.reportChannel=C
local function secret(v) return issecretvalue and issecretvalue(v) end
local function read(fn,...)
    if type(fn)~="function" then return end
    local ok,v=pcall(fn,...); if ok and not secret(v) then return v end
end
local function index()
    local id=read(GetChannelName,NAME)
    if type(id)=="number" and id==math.floor(id) and id>0 and id<=100 then return id end
end
local function cancel()
    if C.timer then C.timer:Cancel(); C.timer=nil end
end
local function state(value)
    if C.state==value then return end
    C.state=value
    if A.Trace then A.Trace("REPORT_CHANNEL",value) end
    if A.db and A.RefreshUI then A.RefreshUI() end
end
local function memberships()
    if type(GetChannelList)~="function" then return end
    local ok,values=pcall(function() return {GetChannelList()} end)
    if not ok or #values>300 or #values%3~=0 then return end
    local names={}
    for i=1,#values,3 do
        local name=values[i+1]
        if secret(name) or type(name)~="string" then return end
        if name:lower():sub(1,#"totalwarcraft")=="totalwarcraft" then names[#names+1]=name end
    end
    return names
end
function A.ReportChannelID()
    if not C.started or C.cleanup or C.blocked or C.stopping then return end
    return index()
end
function A.ReportChannelStatus()
    local id=A.ReportChannelID()
    return id and ("connected (channel "..id..")") or C.state
end
function A.IsReportChannel(localID,channelName)
    local id=A.ReportChannelID()
    if not id or secret(localID) or secret(channelName) then return false end
    -- Native receive indexes belong to THIS client, never the sender's client.
    -- Reject conflicting metadata rather than accepting traffic from another channel.
    local named=type(channelName)=="string" and channelName~=""
    local numbered=type(localID)=="number" and localID>0
    if named and channelName:lower()~=NAME:lower() then return false end
    if numbered and localID~=id then return false end
    return named or numbered
end
function A.SendReportChannel(prefix,packet)
    local id=A.ReportChannelID()
    if not id or not A.reportReady then return false end
    local result=read(C_ChatInfo and C_ChatInfo.SendAddonMessage,prefix,packet,"CHANNEL",tostring(id))
    return result==true or result==(Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0)
end
local function step()
    if C.working or C.stopping then return end
    C.working=true
    local function work()
        if GetTime()>=C.deadline then cancel(); state("unavailable; retry on next world entry"); return end
        if C.cleanup then
            local names=memberships()
            if not names then state("waiting for channel list"); return end
            if #names>0 then
                if GetTime()>=C.nextAttempt and C.attempts<3 then
                    C.attempts=C.attempts+1; C.nextAttempt=GetTime()+5
                    -- Snapshot first: leaving channels can renumber the remaining list.
                    for _,name in ipairs(names) do read(LeaveChannelByName,name) end
                end
                return
            end
            C.cleanup=false; C.attempts=0; C.nextAttempt=0
        end
        local id=index()
        if id then cancel(); state("connected (channel "..id..")"); return end
        state("joining report channel")
        if GetTime()>=C.nextAttempt and C.attempts<3 then
            C.attempts=C.attempts+1; C.nextAttempt=GetTime()+5
            local join=JoinTemporaryChannel or JoinChannelByName
            read(join,NAME)
            id=index()
            if id then cancel(); state("connected (channel "..id..")") end
        end
    end
    work(); C.working=false
end
local function connect(preflight)
    if C.stopping or C.timer then return end
    if not preflight and C.lastConnect and GetTime()-C.lastConnect<30 then return end
    C.lastConnect=GetTime(); C.deadline=GetTime()+30
    C.blocked=false; C.cleanup=preflight or C.cleanup; C.attempts=0; C.nextAttempt=0
    state(C.cleanup and "clearing old TotalWarcraft channels" or "joining report channel")
    C.timer=C_Timer.NewTicker(1,step); step()
end
function A.OnReportChannelEvent(event,...)
    if event=="PLAYER_LOGOUT" then C.stopping=true; cancel(); return end
    if event=="PLAYER_LOGIN" or event=="PLAYER_ENTERING_WORLD" then
        if not A.db or not A.ForeverClient() then return end
        if not C.started then
            C.started=true
            -- One-time removal of the retired channel-test log; never replay test traffic.
            A.db.channelDiagnostics=nil
            connect(true)
        elseif not A.ReportChannelID() then connect(false) end
    elseif event=="CHAT_MSG_CHANNEL_NOTICE" then
        local notice,_,_,channelName,_,_,_,_,base=...
        if secret(notice) or secret(base) or secret(channelName) then return end
        local name=type(base)=="string" and base~="" and base or channelName
        if type(name)~="string" or name:lower()~=NAME:lower() or not C.started or C.working or C.cleanup then return end
        if notice=="NOT_ALLOWED_IN_CHANNEL" or notice=="BANNED" or notice=="MUTED" then
            C.blocked=true; cancel(); state("unavailable: "..notice)
        elseif C.timer then step()
        elseif notice=="YOU_LEFT" then state("report channel disconnected"); connect(false)
        elseif notice=="YOU_CHANGED" and not C.blocked then state("connected (channel "..tostring(index() or "pending")..")") end
    end
end
function A.InitReportChannel()
    local frame=CreateFrame("Frame"); C.events=frame
    for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","CHAT_MSG_CHANNEL_NOTICE","PLAYER_LOGOUT"}) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent",function(_,event,...) A.OnReportChannelEvent(event,...) end)
end
