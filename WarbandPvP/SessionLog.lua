local _,A=...
local LIMIT=1500
local entries,head,count,dropped={},1,0,0
local began,budget,refill=0,40,0
local issues,issueHead,issueCount,issueDropped={},1,0,0
local issueBudget,issueRefill=8,0
local sequence=0
local inventory,inventoryCount,environment={},0,"Client information unavailable"
local errorHook,handlingError,lastAction
local uiErrorsFiltered=0
local routineNames={}
for _,name in ipairs({"ERR_ABILITY_COOLDOWN","ERR_SPELL_COOLDOWN","ERR_ITEM_COOLDOWN",
    "ERR_BADATTACKFACING","ERR_BADATTACKPOS","ERR_OUT_OF_RANGE","ERR_SPELL_OUT_OF_RANGE",
    "ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS","ERR_OUT_OF_MANA","ERR_OUT_OF_RAGE","ERR_OUT_OF_ENERGY","ERR_OUT_OF_FOCUS",
    "ERR_NO_ATTACK_TARGET","ERR_GENERIC_NO_TARGET","SPELL_FAILED_NOT_READY","SPELL_FAILED_MOVING",
    "SPELL_FAILED_STUNNED","SPELL_FAILED_INTERRUPTED","SPELL_FAILED_UNIT_NOT_INFRONT",
    "SPELL_FAILED_OUT_OF_RANGE","SPELL_FAILED_SPELL_IN_PROGRESS"}) do routineNames[name]=true end
local routineMessages={}
local function refreshRoutineMessages()
    routineMessages={}
    for name in pairs(routineNames) do
        local value=A.WB.Read(function() return _G[name] end)
        if type(value)=="string" and value~="" then routineMessages[value]=true end
    end
    -- Exact observed English variants also cover clients missing those globals.
    for _,message in ipairs({"Spell is not ready yet.","You are facing the wrong way!","Out of range.","Interrupted",
        "Can't do that while moving","Another action is in progress","Not enough mana",
        "There is nothing to attack.","Can't do that while stunned"}) do routineMessages[message]=true end
end
local function routineError(code,message)
    if not (issecretvalue and issecretvalue(message)) and type(message)=="string" and routineMessages[message] then return true end
    if issecretvalue and issecretvalue(code) then return false end
    if type(code)~="number" or code<1 or code>100000 or code~=math.floor(code) then return false end
    local name=A.WB.Read(GetGameMessageInfo,code)
    -- Generic ERR_SPELL_FAILED_S (code 57 on this client) is deliberately excluded:
    -- it carries multiple messages, including errors we still need to see.
    return type(name)=="string" and routineNames[name]==true
end
local function clean(v,n)
    if issecretvalue and issecretvalue(v) then return "<restricted>" end
    if type(v)~="string" and type(v)~="number" and type(v)~="boolean" then return "unavailable" end
    return tostring(v):gsub("|",""):gsub("[%c]"," "):sub(1,n)
end
A.LogValue=clean
local function row(kind,message,maxLength)
    sequence=sequence+1
    return {order=sequence,text=string.format("%d +%.3f %s %s",GetServerTime(),GetTime()-began,clean(kind,48),clean(message,maxLength))}
end
function A.LogContext()
    local P=A.WB
    local loc=P.Read(A.CurrentLocation)
    return "combat="..clean(P.Read(UnitAffectingCombat,"player"),24)
        .." lockdown="..clean(P.Read(InCombatLockdown),24).." map="..clean(loc and loc.mapID,16)
end
function A.Trace(kind,message)
    --@dev
    if A.DiagnosticTrace then A.DiagnosticTrace(kind,message) end
    --@enddev
    local now=GetTime()
    budget=math.min(40,budget+math.max(0,now-refill)*8); refill=now
    if budget<1 then dropped=dropped+1; return end
    budget=budget-1
    local entry=row(kind,message,600)
    if count==LIMIT then entries[head]=entry; head=head%LIMIT+1; dropped=dropped+1
    else entries[(head+count-1)%LIMIT+1]=entry; count=count+1 end
end
-- Reserve a small independent budget/buffer so routine event floods cannot hide errors.
function A.TraceIssue(kind,message,stack)
    if handlingError then return end
    handlingError=true
    local ok=pcall(function()
        local now=GetTime()
        issueBudget=math.min(8,issueBudget+math.max(0,now-issueRefill)); issueRefill=now
        if issueBudget<1 then issueDropped=issueDropped+1; return end
        issueBudget=issueBudget-1
        local context=A.LogContext()
        if lastAction and now-lastAction.time<=10 then context=context.." recentAction="..lastAction.label end
        local text=clean(message,500).." | "..context
        if stack then text=text.." | stack="..clean(stack,900) end
        local entry=row(kind,text,1600)
        if issueCount==64 then issues[issueHead]=entry; issueHead=issueHead%64+1; issueDropped=issueDropped+1
        else issues[(issueHead+issueCount-1)%64+1]=entry; issueCount=issueCount+1 end
    end)
    handlingError=false
    if not ok then issueDropped=issueDropped+1 end
end
local function packed(...) return {n=select("#",...),...} end
function A.UIAction(label,fn)
    return function(...)
        local args=packed(...)
        lastAction={label=clean(label,100),time=GetTime()}
        A.Trace("UI_ACTION",lastAction.label.." "..A.LogContext())
        local result
        local ok,err=xpcall(function() result=packed(fn(unpack(args,1,args.n))) end,function(e)
            A.TraceIssue("UI_LUA_ERROR",e,A.WB.Read(debugstack,2,8,4)); return e
        end)
        -- Preserve the normal error handler/UI, including other addons' handlers.
        if not ok then error(err,0) end
        A.Trace("UI_ACTION_DONE",clean(label,100))
        return unpack(result,1,result.n)
    end
end
local function observeErrors()
    if errorHook or type(hooksecurefunc)~="function" or not ScriptErrorsFrame
        or type(ScriptErrorsFrame.DisplayMessageInternal)~="function" then return end
    errorHook=pcall(hooksecurefunc,ScriptErrorsFrame,"DisplayMessageInternal",function(_,message,kind,stack)
        -- No locals, error-handler replacement, UI suppression or CVar changes.
        if not (issecretvalue and issecretvalue(kind)) and kind==0 then A.TraceIssue("LUA_ERROR",message,stack) end
    end)
end
local function addonInfo(name)
    local P,api=A.WB,C_AddOns
    if not api or (issecretvalue and issecretvalue(name)) or type(name)~="string" or #name>100 then return end
    local loaded=P.Read(api.IsAddOnLoaded,name)
    if loaded==true and (inventory[name] or inventoryCount<256) then
        if not inventory[name] then inventoryCount=inventoryCount+1 end
        inventory[name]=clean(P.Read(api.GetAddOnMetadata,name,"Version"),64)
    end
end
local function sessionInfo()
    local P=A.WB
    refreshRoutineMessages()
    local version,build=P.Read(GetBuildInfo)
    local interface=P.Read(function() return select(4,GetBuildInfo()) end)
    environment="Client="..clean(version,24).." build="..clean(build,24).." interface="..clean(interface,24)
        .." ruleset="..clean(A.scopeRuleset,24).." faction="..clean(P.Read(UnitFactionGroup,"player"),24)
    local total=C_AddOns and P.Read(C_AddOns.GetNumAddOns)
    if type(total)=="number" then
        for i=1,math.min(total,256) do addonInfo(P.Read(C_AddOns.GetAddOnInfo,i)) end
    end
    observeErrors()
end
function A.SessionLogText()
    local addons={}; for name,version in pairs(inventory) do addons[#addons+1]=clean(name,100).."="..version end
    table.sort(addons)
    local rows={"TotalWarcraft session log v2 | addon="..(A.release or "unknown").." | flavor="..(A.buildFlavor or "dev").." | omitted="..dropped.." | issuesOmitted="..issueDropped.." | uiErrorsFiltered="..uiErrorsFiltered,
        "Local session only; resets on reload/login. Names and in-game locations may appear. No chat event capture or automatic upload. Error text may contain addon data.",
        "Bounded journal: latest 1500 activity / 64 issue entries. Observations do not prove PvP participation or a shared layer.",
        environment.." | Lua error observer="..(errorHook and "attached" or "unavailable; owned UI errors still captured"),
        "Loaded addons (up to 256): "..table.concat(addons,", ")}
    local combined={}
    for i=0,count-1 do combined[#combined+1]=entries[(head+i-1)%LIMIT+1] end
    for i=0,issueCount-1 do combined[#combined+1]=issues[(issueHead+i-1)%64+1] end
    table.sort(combined,function(a,b) return a.order<b.order end)
    for _,entry in ipairs(combined) do rows[#rows+1]=entry.text end
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
    began=GetTime(); refill=began; issueRefill=began
    sessionInfo()
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
        "GROUP_ROSTER_UPDATE","PARTY_LEADER_CHANGED","SHARD_TRANSFER_IMMINENT","SHARD_TRANSFER","SHARD_TRANSFER_CANCELLED","UNIT_PHASE",
        "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_DEAD","PLAYER_ALIVE","PLAYER_UNGHOST","PLAYER_TARGET_CHANGED",
        "ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN","UI_ERROR_MESSAGE","ADDON_LOADED","LUA_WARNING"}) do
        pcall(frame.RegisterEvent,frame,event)
    end
    frame:SetScript("OnEvent",function(_,event,unit,detail)
        if event=="ADDON_LOADED" then addonInfo(unit); observeErrors(); return end
        if event=="PLAYER_LOGIN" then sessionInfo() end
        if event=="ADDON_ACTION_BLOCKED" or event=="ADDON_ACTION_FORBIDDEN" then
            A.TraceIssue(event,"namedAddon="..clean(unit,100).." function="..clean(detail,160)); return
        end
        if event=="LUA_WARNING" then A.TraceIssue(event,unit); return end
        -- Filter only our journal, before its throttle/budget; native feedback stays intact.
        if event=="UI_ERROR_MESSAGE" and routineError(unit,detail) then uiErrorsFiltered=uiErrorsFiltered+1; return end
        if event=="UNIT_PHASE" and unit~="player" then return end
        if (event=="UI_ERROR_MESSAGE" or event=="PLAYER_TARGET_CHANGED" or event=="UNIT_PHASE")
            and times[event] and GetTime()-times[event]<1 then return end
        times[event]=GetTime()
        if event=="UI_ERROR_MESSAGE" then
            A.Trace("UI_ERROR_MESSAGE","code="..clean(unit,24).." message="..clean(detail,240).." "..A.LogContext()); return
        end
        if event=="PLAYER_TARGET_CHANGED" then
            A.Trace(event,"player="..clean(A.WB.Read(UnitIsPlayer,"target"),24).." pvp="..clean(A.WB.Read(UnitIsPVP,"target"),24)
                .." attackable="..clean(A.WB.Read(UnitCanAttack,"player","target"),24).." "..A.LogContext()); return
        end
        local loc=A.CurrentLocation()
        local phase=A.WB.Read(UnitPhaseReason,"player")
        A.Trace(event,"map="..(loc and loc.mapID or "unavailable").." phase="..clean(phase,48).." layer=unverified "..A.LogContext())
    end)
end
