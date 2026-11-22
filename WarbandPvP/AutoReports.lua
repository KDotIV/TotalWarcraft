local _,A=...
local P=A.WB
local R={}
A.autoReports=R
local function secret(v) return issecretvalue and issecretvalue(v) end
local function field(t,k)
    if secret(t) or type(t)~="table" then return end
    return P.Read(function() return t[k] end)
end
local function number(v,lo,hi)
    return not secret(v) and type(v)=="number" and v==v and v>=lo and v<=hi
end
local function name(v)
    if secret(v) or type(v)~="string" or #v==0 or #v>100 or v:find("[|%c]") then return end
    return v:lower():gsub("%s+","-")
end
local function array(t,limit)
    if secret(t) or type(t)~="table" then return end
    local result={}
    for i=1,limit+1 do
        local ok,v=pcall(function() return t[i] end)
        if not ok or secret(v) then return end
        if v==nil then return result end
        if i>limit or type(v)~="table" then return end
        result[i]=v
    end
end
local function trace(kind,message) if A.Trace then A.Trace(kind,message) end end
local function quiet()
    return P.Read(UnitAffectingCombat,"player")==false and P.Read(InCombatLockdown)==false
end
local function meter(fn,...)
    if quiet() then return P.Read(field(C_DamageMeter,fn),...) end
end
local function catalog()
    if meter("IsDamageMeterAvailable")~=true then return end
    local rows=array(meter("GetAvailableCombatSessions"),64); if not rows then return end
    local ids={}
    for _,item in ipairs(rows) do
        local id=field(item,"sessionID")
        if not number(id,1,2147483647) or id%1~=0 then return end
        ids[id]=true
    end
    return ids
end
local function cancel()
    if R.timer then R.timer:Cancel(); R.timer=nil end
    R.capture=nil
end
local function skip(reason)
    if R.skip~=reason then trace("REPORT_AUTO_SKIP",reason) end
    R.skip=reason
end
local function duelRequested()
    R.duelUntil=GetTime()+60
    if P.Read(UnitAffectingCombat,"player")==true then R.duelCombat=true end
    if R.capture then R.capture.blocked=true end
end
function A.ReportBlockedByDuel()
    if R.duelCombat or R.duelActive or GetTime()<(R.duelUntil or 0) then
        if P.Read(UnitAffectingCombat,"player")==true then R.duelCombat=true end
        return true
    end
    return false
end
local function allowed()
    return not A.ReportBlockedByDuel() and P.Read(IsInInstance)==false
        and P.Read(UnitIsPVPFreeForAll,"player")==false and P.Read(UnitIsPVPSanctuary,"player")==false
end
local function location()
    local l=P.Read(A.CurrentLocation)
    local map,x,y=field(l,"mapID"),field(l,"x"),field(l,"y")
    if number(map,1,100000) and map%1==0 and number(x,0,1) and number(y,0,1) then return {mapID=map,x=x,y=y} end
end
local function observe(unit)
    local c=R.capture
    if not c or c.state~="combat" or c.blocked or secret(unit) or type(unit)~="string" then return end
    if unit~="target" and unit~="focus" and unit~="targettarget" and not unit:match("^nameplate%d+$") then return end
    if P.Read(UnitExists,unit)~=true or P.Read(UnitIsVisible,unit)~=true or P.Read(UnitIsPlayer,unit)~=true
        or P.Read(UnitIsPVP,unit)~=true or P.Read(UnitCanAttack,"player",unit)~=true
        or P.Read(UnitIsPVPFreeForAll,unit)~=false or P.Read(UnitIsPVPSanctuary,unit)~=false then return end
    local own,other=P.Read(UnitFactionGroup,"player"),P.Read(UnitFactionGroup,unit)
    if not ((own=="Horde" and other=="Alliance") or (own=="Alliance" and other=="Horde")) then return end
    local guid,key=P.Read(UnitGUID,unit),name(P.Read(P.UnitName,unit))
    if not name(guid) or not key then return end
    if not c.opponents[guid] then
        if c.count>=64 then c.blocked=true; return end
        c.opponents[guid]=true; c.count=c.count+1
        trace("REPORT_OPPONENT","visible opposing PvP player="..key.." count="..c.count)
    end
    if c.names[key] and c.names[key]~=guid then c.ambiguous[key]=true end
    c.names[key]=guid
end
local function incoming(c,sid)
    local kind=field(field(Enum,"DamageMeterType"),"DamageTaken")
    if not number(kind,0,100) then return end
    local rows=array(field(meter("GetCombatSessionFromID",sid,kind),"combatSources"),64)
    if not rows then return end
    local count,matched=0,false
    for _,s in ipairs(rows) do
        if field(s,"isLocalPlayer")==true then count=count+1; matched=field(s,"sourceGUID")==c.selfGUID end
    end
    if count~=1 or not matched then return end
    local spells=array(field(meter("GetCombatSessionSourceFromID",sid,kind,c.selfGUID,nil),"combatSpells"),512)
    if not spells then return end
    for _,spell in ipairs(spells) do
        local d=field(spell,"combatSpellDetails")
        local key=name(field(d,"unitName"))
        if key and c.names[key] and not c.ambiguous[key] and number(field(d,"amount"),.000001,1e12)
            and field(d,"isMob")==false and field(d,"isPet")==false then
                trace("REPORT_DAMAGE_SOURCE","session="..sid.." enemy="..key.." damage="..field(d,"amount"))
                return true
            end
    end
end
local inspect
local function schedule(c)
    R.timer=C_Timer.NewTimer(c.reads==0 and .5 or 1.5,function()
        R.timer=nil
        if R.capture==c then inspect(c) end
    end)
end
inspect=function(c)
    local loc=location()
    if not quiet() or not allowed() or not loc or loc.mapID~=c.loc.mapID or c.blocked
        or GetTime()-c.started>900 or not A.db.autoReports then cancel(); R.baseline=nil; return end
    c.reads=c.reads+1
    local ids=catalog(); local sid,total=nil,0
    if ids then for id in pairs(ids) do if not c.baseline[id] then sid=id; total=total+1 end end end
    trace("REPORT_VERIFY","read="..c.reads.." freshSessions="..total.." observedOpponents="..c.count)
    if total>1 or (c.sid and sid and c.sid~=sid) then
        skip("multiple/changed meter sessions"); cancel(); R.baseline=ids; return
    end
    c.sid=sid or c.sid
    if total==1 and c.updated[sid] and incoming(c,sid) then
        -- Incoming damage suffices; later fights cannot erase this completed observation.
        cancel(); R.baseline=ids; R.attempted=true
        trace("REPORT_DAMAGE_CHECK","incoming opposing-player damage confirmed; session="..sid)
        local ok,message=A.Report("automatic",c.loc)
        trace("REPORT_AUTO","accepted="..tostring(ok==true).." "..A.CleanText(message,160))
        if ok then A.Print("PvP report submitted to the shared channel.") end
    elseif c.reads>=3 then
        skip("no readable attributable incoming player damage"); cancel(); R.baseline=ids
    else schedule(c) end
end
function A.UpdateAutoReports()
    if not A.db then return end
--@dev
    if (A.DamageDiagnosticActive and A.DamageDiagnosticActive()) or A.testMode or P.IsSimulation() then
        cancel(); R.baseline=nil; R.awaitPeace=true; return
    end
--@enddev
    local combat=P.Read(UnitAffectingCombat,"player")
    if combat~=true and combat~=false then cancel(); R.baseline=nil; R.awaitPeace=true; return end
    if not A.db.autoReports then cancel(); R.baseline=nil; R.awaitPeace=true; return end
    if combat==false then
        R.startedAt=nil
        if R.duelCombat then R.duelUntil=math.max(R.duelUntil or 0,GetTime()+10); R.duelCombat=nil end
        if R.capture then
            if R.capture.state=="combat" then
                R.capture.state="reading"
                trace("REPORT_CAPTURE_END","opponents="..R.capture.count.." blocked="..tostring(R.capture.blocked==true))
                if R.capture.count==0 or R.capture.blocked then cancel(); R.baseline=nil
                else schedule(R.capture) end
            end
        end
        R.awaitPeace=nil
        if not R.capture then
            if not R.baseline then R.baseline=catalog() end
            R.attempted=nil; R.skip=nil
        end
        return
    end
    if R.capture and R.capture.state=="reading" then cancel(); R.baseline=nil; R.awaitPeace=true end
    if not R.startedAt then R.startedAt=GetServerTime(); R.attempted=nil end
    if R.attempted then cancel(); return end
    if R.awaitPeace then return end
    if not allowed() then if R.capture then R.capture.blocked=true end; return skip("duel/instance/FFA/sanctuary exclusion") end
    if (A.db.lastSubmit or 0)>=R.startedAt or GetServerTime()-(A.db.lastSubmit or 0)<120 then
        R.attempted=true; cancel(); return skip("shared report cooldown")
    end
    if not R.capture then
        if not R.baseline then R.awaitPeace=true; return skip("fresh out-of-combat meter baseline unavailable") end
        local loc=location(); local guid=P.Read(UnitGUID,"player")
        if not loc or not name(guid) then R.awaitPeace=true; return skip("identity/location unavailable") end
        R.capture={state="combat",baseline=R.baseline,loc=loc,selfGUID=guid,started=GetTime(),
            updated={},updates=0,names={},ambiguous={},opponents={},count=0,reads=0}
        R.baseline=nil
        trace("REPORT_CAPTURE_START","map="..loc.mapID.." guild="..tostring(P.Read(IsInGuild)==true))
        observe("target"); observe("focus"); observe("targettarget")
        local plates=P.Read(C_NamePlate and C_NamePlate.GetNamePlates)
        if type(plates)=="table" then for i=1,64 do local p=field(plates,i); if not p then break end; observe(field(p,"namePlateUnitToken")) end end
    end
    observe("target"); observe("focus")
end
function A.AutoReportTick() A.UpdateAutoReports() end
function A.SetAutoReportsEnabled(enabled)
    A.db.autoReports=enabled==true; cancel(); R.baseline=nil; R.awaitPeace=true
    A.UpdateAutoReports()
    if A.RefreshHome then A.RefreshHome() end
    trace("AUTO_REPORTS",A.db.autoReports and "on" or "off")
end
function A.InitAutoReports()
    cancel(); R.baseline=nil; R.startedAt=nil; R.awaitPeace=true
    A.db.autoReports=A.db.autoReports~=false
    if R.events then R.events:UnregisterAllEvents() end
    local f=CreateFrame("Frame"); R.events=f
    for _,event in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_TARGET_CHANGED","PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED","PLAYER_LOGIN","PLAYER_ENTERING_WORLD","ZONE_CHANGED_NEW_AREA","SHARD_TRANSFER","SHARD_TRANSFER_IMMINENT",
        "DAMAGE_METER_COMBAT_SESSION_UPDATED","DAMAGE_METER_RESET","DUEL_REQUESTED","DUEL_TO_THE_DEATH_REQUESTED",
        "DUEL_INBOUNDS","DUEL_OUTOFBOUNDS","DUEL_FINISHED"}) do pcall(f.RegisterEvent,f,event) end
    f:SetScript("OnEvent",function(_,event,...)
        local second=math.floor(GetTime())
        if R.second~=second then R.second=second; R.budget=100 end
        R.budget=R.budget-1
        if R.budget<0 then cancel(); R.baseline=nil; R.awaitPeace=true; return end
        if event=="DUEL_REQUESTED" or event=="DUEL_TO_THE_DEATH_REQUESTED" then duelRequested()
        elseif event=="DUEL_INBOUNDS" or event=="DUEL_OUTOFBOUNDS" then R.duelActive=true
        elseif event=="DUEL_FINISHED" then
            R.duelActive=nil; R.duelUntil=GetTime()+10
            if P.Read(UnitAffectingCombat,"player")==true then R.duelCombat=true end
        elseif event=="PLAYER_ENTERING_WORLD" or event=="ZONE_CHANGED_NEW_AREA" or event=="SHARD_TRANSFER"
            or event=="SHARD_TRANSFER_IMMINENT" or event=="DAMAGE_METER_RESET" then
            cancel(); R.baseline=nil; R.awaitPeace=true
        elseif event=="DAMAGE_METER_COMBAT_SESSION_UPDATED" then
            -- A meter notification may arrive before PLAYER_REGEN_DISABLED.
            -- Capture the already-observed combat transition before assigning it.
            if not R.capture and P.Read(UnitAffectingCombat,"player")==true then A.UpdateAutoReports() end
            local _,sid=...
            if number(sid,1,2147483647) and sid%1==0 then
                local c=R.capture
                if c then
                    if not c.updated[sid] then c.updates=c.updates+1 end
                    if c.updates>64 then c.blocked=true else c.updated[sid]=true end
                elseif R.baseline and not R.baseline[sid] then R.baseline=nil end
            end
        end
        A.UpdateAutoReports()
        if event=="NAME_PLATE_UNIT_ADDED" then observe(...) end
    end)
    if not R.duelHook and type(hooksecurefunc)=="function" and type(StartDuel)=="function" then
        R.duelHook=pcall(hooksecurefunc,"StartDuel",duelRequested)
    end
    A.UpdateAutoReports()
end
