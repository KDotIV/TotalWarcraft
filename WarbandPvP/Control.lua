local _, A = ...
local PREFIX = "WBP_CTL1"
local verbs = {status=true, ["test-on"]=true, ["test-off"]=true, ["presence-on"]=true,
    ["presence-off"]=true, report=true, ["capture-start"]=true, ["capture-stop"]=true, snapshot=true,
    ["warband-five"]=true,["warband-watch"]=true,["warband-join"]=true,["warband-leave"]=true}
local controller, lastSent, lastReceived, sequence = nil, nil, nil, 0
local pending, seen = {}, {}
local function secret(v) return issecretvalue and issecretvalue(v) end
local function read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, ...)
    if not ok or secret(a) or secret(b) then return end
    return a, b
end
local function name(value)
    if secret(value) or type(value) ~= "string" or #value > 128 or value:find("[|%c]") then return end
    value = value:match("^%s*(.-)%s*$"):gsub("%s+", " ")
    if value ~= "" then return value end
end
local function key(value)
    value = name(value)
    return value and value:lower():gsub("%s+", "-")
end
local function matches(expected, actual)
    local a, b = key(expected), key(actual)
    if not a or not b then return false end
    if a == b then return true end
    -- Only strip a known local-realm suffix; never guess Forever realm pools or
    -- authorize someone merely sharing a first name.
    local _, realm = read(UnitFullName, "player")
    for _, r in pairs({read(GetNormalizedRealmName), read(GetRealmName), realm}) do
        r = key(r)
        if r then
            local suffix = "-" .. r
            local aa = a:sub(-#suffix) == suffix and a:sub(1,-#suffix-1) or a
            local bb = b:sub(-#suffix) == suffix and b:sub(1,-#suffix-1) or b
            if aa == bb then return true end
        end
    end
    return false
end
local function send(packet, target)
    if #packet > 255 then return false end
    local result = read(C_ChatInfo and C_ChatInfo.SendAddonMessage, PREFIX, packet, "WHISPER", target)
    return result == true or result == (Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0)
end
local function reply(target, nonce, ok, message)
    -- No payload text can introduce delimiters or WoW markup into a reply.
    local payload = table.concat({"1","A",nonce,tostring(GetServerTime()),ok and "1" or "0",A.CleanText(message,140)},"\t")
    if not send(payload,target) then A.Print("Remote test ran, but its reply could not be sent.") end
end
local function fresh(value)
    if not value or not value:match("^%d+$") then return false end
    local n = tonumber(value)
    return n and n >= GetServerTime()-30 and n <= GetServerTime()+5
end
local function status()
    return (A.release or "unknown") .. " test=" .. tostring(A.testMode==true)
        .. " presence=" .. tostring(A.presenceEnabled==true) .. " capture=" .. tostring(A.DiagnosticActive())
        .. " reports=" .. #A.List() .. " peers=" .. #A.PresenceList()
        .. " wb=" .. (A.warbands.simulationCount and ("TEST/"..A.warbands.simulationCount) or "LIVE")
        .. "/" .. (A.warbands.host and "host" or A.warbands.member and ("group"..A.warbands.member.slot) or A.warbands.join and "pending" or "none")
end
local function execute(verb,sender)
    if verb == "status" then return true,status()
    elseif verb == "test-on" then A.SetTestMode(true)
    elseif verb == "test-off" then A.SetTestMode(false)
    elseif verb == "presence-on" then
        A.SetPresenceEnabled(true)
        if not A.presenceEnabled then return false,"Presence messaging unavailable." end
    elseif verb == "presence-off" then A.SetPresenceEnabled(false)
    elseif verb == "capture-start" then A.LayerCommand("start remote-test")
    elseif verb == "capture-stop" then A.LayerCommand("stop")
    elseif verb == "snapshot" then A.LayerCommand("snap remote-request")
    elseif verb:match("^warband%-%a+$") then return A.RemoteWarbandTest(verb,sender)
    elseif verb == "report" then
        if not A.testMode then return false,"Test mode must be ON; remote real reports are disabled." end
        -- Use the known guild adapter, never an arbitrary replacement transport.
        if A.adapter ~= A.GuildSend then return false,"Remote reports require the default guild transport." end
        return A.Report()
    end
    return true,status()
end
function A.OnControlMessage(prefix, packet, route, sender)
    if secret(prefix) or secret(packet) or secret(route) or secret(sender) then return end
    if prefix ~= PREFIX or route ~= "WHISPER" or not A.controlReady or not name(sender)
        or type(packet) ~= "string" or #packet > 255 then return end
    local f={}
    for field in (packet.."\t"):gmatch("(.-)\t") do f[#f+1]=field; if #f>8 then return end end
    if f[1]~="1" or not f[3] or #f[3]>40 or not f[3]:match("^%d+%-%d+%-%d+$") or not fresh(f[4]) then return end
    local now=GetTime()
    if f[2]=="A" then
        local request=pending[f[3]]
        if #f~=6 or (f[5]~="0" and f[5]~="1") or not request or now-request.time>30
            or not matches(request.target,sender) then return end
        pending[f[3]]=nil
        A.Print("Remote " .. A.CleanText(sender,128) .. " " .. request.verb .. ": "
            .. (f[5]=="1" and "OK - " or "FAILED - ") .. A.CleanText(f[6],140))
        if A.Trace then A.Trace("CONTROL_REPLY", "sender=" .. A.CleanText(sender,128) .. " verb=" .. request.verb .. " ok=" .. f[5]) end
        return
    end
    if f[2]~="Q" or #f~=8 or not verbs[f[8]] or not controller or not matches(controller,sender) then return end
    if not A.RefreshScope() then return end
    local faction=read(UnitFactionGroup,"player")
    if (faction~="Horde" and faction~="Alliance") or f[5]~=(faction=="Horde" and "H" or "A")
        or f[6]~=A.scopeRuleset or f[7]~=tostring(A.scopeRegion) then return end
    local count=0
    for nonce, at in pairs(seen) do if now-at>60 then seen[nonce]=nil else count=count+1 end end
    if seen[f[3]] or count>=32 then return end
    -- Drop rapid repeats before sending replies, so a request burst cannot amplify.
    if lastReceived and now-lastReceived<5 then return end
    seen[f[3]]=now; lastReceived=now
    local safe, accepted, message=pcall(execute,f[8],sender)
    if not safe then accepted=false; message="Command failed locally; inspect the tester's Lua errors." end
    if A.Trace then A.Trace("CONTROL_REQUEST", "sender=" .. A.CleanText(sender,128) .. " verb=" .. f[8] .. " accepted=" .. tostring(accepted==true)) end
    A.Print("Remote test command from " .. A.CleanText(sender,128) .. ": " .. f[8])
    reply(sender,f[3],accepted==true,message or "Command completed.")
end
function A.ControlCommand(input)
    local cmd,arg=input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd=cmd:lower()
    if cmd=="allow" then
        local allowed=name(arg)
        if not allowed or not A.controlReady then A.Print("Use /tw control allow First Surname while addon messaging is available."); return end
        controller=allowed; seen={}; lastReceived=nil
        A.Print("Remote testing authorized for " .. allowed .. " this session: simulated reports/warbands, test mode, group location sharing and local captures.")
        A.Print("/tw control off revokes access and stops test mode, presence and capture. Reload also revokes access.")
    elseif cmd=="off" then
        controller=nil; seen={}
        A.SetTestMode(false); A.SetPresenceEnabled(false); A.LayerCommand("stop")
        A.Print("Remote testing disabled.")
    else
        A.Print("Remote controller: " .. (controller or "none") .. " (session only). /tw control allow First Surname | off")
    end
end
function A.RemoteCommand(input)
    local target,verb=input:match("^%s*(.-)%s+(%S+)%s*$")
    target=name(target); verb=verb and verb:lower()
    if not target or not verbs[verb] then
        A.Print("/tw remote First Surname <status|test-on|test-off|presence-on|presence-off|report|capture-start|capture-stop|snapshot|warband-five|warband-watch|warband-join|warband-leave>"); return
    end
    if not A.controlReady or not A.RefreshScope() then A.Print("Remote testing messaging/scope unavailable."); return end
    local now=GetTime()
    if lastSent and now-lastSent<5 then A.Print("Wait five seconds between remote test commands."); return end
    local count=0
    for id,r in pairs(pending) do if now-r.time>30 then pending[id]=nil else count=count+1 end end
    if count>=8 then A.Print("Wait for pending remote commands to finish."); return end
    local faction=read(UnitFactionGroup,"player")
    if faction~="Horde" and faction~="Alliance" then A.Print("Faction unavailable."); return end
    sequence=sequence+1
    local nonce=string.format("%d-%d-%d",GetServerTime(),math.floor(now*1000)%1000000000,sequence)
    local packet=table.concat({"1","Q",nonce,tostring(GetServerTime()),faction=="Horde" and "H" or "A",
        A.scopeRuleset,tostring(A.scopeRegion),verb},"\t")
    lastSent=now
    pending[nonce]={target=target,verb=verb,time=now}
    if not send(packet,target) then pending[nonce]=nil; A.Print("Remote command send rejected/unavailable."); return end
    A.Print("Remote " .. verb .. " sent to " .. target .. "; awaiting reply.")
    if A.Trace then A.Trace("CONTROL_SEND", "target=" .. A.CleanText(target,128) .. " verb=" .. verb .. " nonce=" .. nonce) end
    C_Timer.NewTimer(30,function()
        if pending[nonce] then
            pending[nonce]=nil
            A.Print("No reply from " .. target .. ". Check online status, authorization, exact name and scope. No retry was sent.")
        end
    end)
end
function A.InitControl()
    controller=nil
    local result=read(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix,PREFIX)
    local codes=Enum and Enum.RegisterAddonMessagePrefixResult
    A.controlReady=result==true or result==(codes and codes.Success or 0) or result==(codes and codes.DuplicatePrefix or 1)
    if not A.controlReady then return end
    local frame=CreateFrame("Frame"); frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent",function(_,_,...) A.OnControlMessage(...) end)
end
