local _,A=...
-- Development only: local observations, never a report, transport or proof badge.
local D={revision=1,active=false,state="idle",result="not run"}
A.damageDiagnostics=D
local db,frame,deadline,reader
local ROWS,SESSIONS,SOURCES,SPELLS=600,64,64,512
local function secret(v) return issecretvalue and issecretvalue(v) end
local function safe(v) if not secret(v) then return v end end
local function field(t,k)
    if secret(t) or type(t)~="table" then return end
    local ok,v=pcall(function() return t[k] end)
    if ok then return safe(v) end
end
local function call(fn,...)
    if type(fn)~="function" then return end
    local ok,v=pcall(fn,...); if ok then return safe(v) end
end
local function text(v)
    if secret(v) then return "<restricted>" end
    local t=type(v)
    if t~="string" and t~="number" and t~="boolean" then return "unavailable" end
    return tostring(v):gsub("|",""):gsub("[%c]"," "):sub(1,100)
end
local function number(v,lo,hi)
    return not secret(v) and type(v)=="number" and v==v and v>=lo and v<=hi
end
local function id(v) return number(v,1,2147483647) and v%1==0 end
local function name(v)
    if secret(v) or type(v)~="string" or #v==0 or #v>100 or v:find("[|%c]") then return end
    return v:lower():gsub("%s+","-") -- preserve all name components; no short-name guessing
end
local function row(kind,message)
    if not db then return end
    if #db.entries>=ROWS then table.remove(db.entries,1); db.dropped=db.dropped+1 end
    db.entries[#db.entries+1]=string.format("%d +%.2f %s %s",GetServerTime(),GetTime()-(D.armedAt or GetTime()),kind,message:sub(1,900))
end
local function cancel(which)
    if which then which:Cancel() end
end
local function quiet()
    return call(UnitAffectingCombat,"player")==false and call(InCombatLockdown)==false
end
local function location()
    local l=call(A.CurrentLocation)
    local map,x,y=field(l,"mapID"),field(l,"x"),field(l,"y")
    if id(map) and number(x,0,1) and number(y,0,1) then return {mapID=map,x=x,y=y} end
end
local function flagsOK()
    return call(IsInInstance)==false and call(UnitIsPVPFreeForAll,"player")==false
        and call(UnitIsPVPSanctuary,"player")==false and call(A.ReportBlockedByDuel)==false
end
local function block(reason)
    if not D.blocked then D.blocked=reason; D.result="excluded: "..reason; row("EXCLUDED",reason) end
end
local function checkContext()
    if not flagsOK() then block("duel/instance/FFA/sanctuary state excluded or unavailable") end
    local l=location()
    if not l or not D.loc or l.mapID~=D.loc.mapID then block("location unavailable or zone changed") end
end
local function aliases(unit)
    local a={}
    local n=call(A.WB.UnitName,unit); local k=name(n)
    if k then a[k]=true end
    -- WB.UnitName handles Forever first/surname. No first-name-only aliases.
    return a,n
end
local function observe(unit)
    if not D.active or (D.state~="armed" and D.state~="combat") then return end
    if secret(unit) or type(unit)~="string" then return end
    if unit~="target" and unit~="focus" and not unit:match("^nameplate%d+$") then return end
    if call(UnitExists,unit)~=true or call(UnitIsVisible,unit)~=true or call(UnitIsPlayer,unit)~=true then return end
    local own,other=call(UnitFactionGroup,"player"),call(UnitFactionGroup,unit)
    if not ((own=="Horde" and other=="Alliance") or (own=="Alliance" and other=="Horde")) then return end
    if call(UnitIsPVP,unit)~=true or call(UnitCanAttack,"player",unit)~=true
        or call(UnitIsPVPFreeForAll,unit)~=false or call(UnitIsPVPSanctuary,unit)~=false then return end
    local guid=call(UnitGUID,unit); local keys,n=aliases(unit)
    if not name(guid) or not next(keys) then return end
    if not D.opponents[guid] then
        if D.opponentCount>=64 then block("opponent capacity"); return end
        D.opponentCount=D.opponentCount+1
        D.opponents[guid]={guid=guid,name=n,faction=other,keys=keys,at=GetTime()}
        row("OPPONENT","name="..text(n).." faction="..text(other).." guid="..text(guid))
    end
    D.opponents[guid].at=GetTime()
    for k in pairs(keys) do
        local old=D.names[k]
        if old and old~=guid then D.names[k]=false; D.ambiguous[k]=true
        elseif not D.ambiguous[k] then D.names[k]=guid end
    end
end
local function meter(fn,...)
    -- Every native meter read, including session enumeration, is gated here.
    if not quiet() then return end
    return call(field(C_DamageMeter,fn),...)
end
local function sessions()
    local list=meter("GetAvailableCombatSessions")
    if type(list)~="table" then return nil,"session list unavailable/restricted" end
    local found={}
    for i=1,SESSIONS+1 do
        local item=field(list,i)
        if not item then
            -- A secret entry is not a trustworthy end of the list.
            local ok,v=pcall(function() return list[i] end)
            if not ok or secret(v) then return nil,"session entry restricted" end
            break
        end
        if i>SESSIONS then return nil,"session capacity" end
        local sid=field(item,"sessionID")
        if not id(sid) then return nil,"session identity unavailable" end
        found[sid]=true
    end
    return found
end
local function finish(reason)
    cancel(reader); reader=nil; cancel(deadline); deadline=nil
    D.active=false; D.state="stopped"
    if frame then frame:UnregisterAllEvents() end
    row("STOP",reason.."; result="..D.result.."; no report sent")
    if A.UpdateAutoReports then A.UpdateAutoReports() end
end
local function matched(v)
    local k=name(v); local guid=k and D.names[k]
    return guid and not D.ambiguous[k] and D.opponents[guid] or nil
end
local function readCategory(sid,category,totals)
    local types=field(Enum,"DamageMeterType"); local kind=field(types,category)
    if not number(kind,0,100) then row("API",category.." enum unavailable"); return end
    local session=meter("GetCombatSessionFromID",sid,kind)
    local sources=field(session,"combatSources")
    if type(sources)~="table" then row("API",category.." source list unavailable/restricted"); return end
    local selected={}; local localCount=0
    for i=1,SOURCES+1 do
        local s=field(sources,i)
        if not s then
            local ok,v=pcall(function() return sources[i] end)
            if not ok or secret(v) then block("source entry restricted") end
            break
        end
        if i>SOURCES then block("source capacity"); break end
        local guid=field(s,"sourceGUID")
        if i<=8 then row("SOURCE",category.." guid="..text(guid).." name="..text(field(s,"name"))
            .." local="..text(field(s,"isLocalPlayer")).." total="..text(field(s,"totalAmount"))) end
        if category=="EnemyDamageTaken" then
            if name(guid) and D.opponents[guid] then selected[#selected+1]={guid=guid,opponent=D.opponents[guid]} end
        elseif field(s,"isLocalPlayer")==true then
            localCount=localCount+1
            if name(guid) and guid==D.selfGUID then selected[#selected+1]={guid=guid} end
        end
    end
    if category~="EnemyDamageTaken" and localCount~=1 then row("API",category.." local source missing/ambiguous"); return end
    if #selected==0 then row("API",category.." no readable matching source GUID"); return end
    if #selected>8 then block("source query capacity"); return end
    for _,s in ipairs(selected) do
        local details=meter("GetCombatSessionSourceFromID",sid,kind,s.guid,nil)
        local spells=field(details,"combatSpells")
        if type(spells)~="table" then row("API",category.." spell list unavailable/restricted")
        else
            for i=1,SPELLS+1 do
                local spell=field(spells,i)
                if not spell then
                    local ok,v=pcall(function() return spells[i] end)
                    if not ok or secret(v) then block("spell entry restricted") end
                    break
                end
                totals.rows=totals.rows+1
                if totals.rows>SPELLS then block("spell capacity"); return end
                local d=field(spell,"combatSpellDetails")
                local unit=field(d,"unitName"); local amount=field(d,"amount")
                local mob,pet=field(d,"isMob"),field(d,"isPet")
                -- Log only whitelisted readable fields. Never stringify raw API tables.
                if totals.logged<96 then
                    row("METER_ROW",category.." source="..text(s.guid).." spell="..text(field(spell,"spellID"))
                        .." unit="..text(unit).." amount="..text(amount).." total="..text(field(spell,"totalAmount"))
                        .." mob="..text(mob).." pet="..text(pet).." class="..text(field(d,"unitClassFilename")))
                    totals.logged=totals.logged+1
                end
                if number(amount,.000001,1e12) and mob==false and pet==false then
                    local opponent=category=="EnemyDamageTaken" and s.opponent or matched(unit)
                    local eligible=opponent and (category~="EnemyDamageTaken" or D.selfNames[name(unit)])
                    if eligible then
                        local evidence=totals.pairs[opponent.guid] or {incoming=false,outgoing=false,name=opponent.name}
                        if category=="DamageTaken" then evidence.incoming=true else evidence.outgoing=true end
                        totals.pairs[opponent.guid]=evidence
                    end
                end
            end
        end
    end
end
local function inspect()
    if not D.active or D.state~="reading" then return end
    D.reads=D.reads+1
    D.result=D.blocked and ("excluded: "..D.blocked) or "no readable attributable result"
    checkContext()
    if not quiet() then block("combat resumed or combat state unavailable"); finish("read cancelled"); return end
    if meter("IsDamageMeterAvailable")~=true then row("API","meter unavailable/restricted"); return end
    local list,err=sessions()
    if not list then row("API",err); return end
    local candidates={}
    for sid in pairs(list) do if not D.baseline[sid] then candidates[#candidates+1]=sid end end
    table.sort(candidates)
    row("READ","attempt="..D.reads.." newSessions="..#candidates)
    if #candidates~=1 then
        if #candidates>1 then block("multiple new sessions; attribution ambiguous") end
        return
    end
    local sid=candidates[1]
    if D.sessionID and D.sessionID~=sid then block("meter session changed") end
    D.sessionID=sid
    row("SESSION","id="..sid.." eventCorrelated="..tostring(D.updated[sid]==true))
    local totals={rows=0,logged=0,pairs={}}
    for _,category in ipairs({"DamageTaken","DamageDone","EnemyDamageTaken"}) do readCategory(sid,category,totals) end
    local incoming,outgoing,exchange=0,0,0
    if not D.blocked and D.updated[sid] then
        for _,e in pairs(totals.pairs) do
            incoming=incoming+(e.incoming and 1 or 0); outgoing=outgoing+(e.outgoing and 1 or 0)
            exchange=exchange+(e.incoming and e.outgoing and 1 or 0)
            row("PAIR_CANDIDATE","opponent="..text(e.name).." incoming="..tostring(e.incoming).." outgoing="..tostring(e.outgoing))
        end
    end
    D.result=D.blocked and ("excluded: "..D.blocked)
        or ("candidates incoming="..incoming.." outgoing="..outgoing.." exchange="..exchange)
    row("RESULT",D.result.."; native category semantics require live review; not server proof")
    -- Always inspect the final bounded snapshot too: delayed outgoing rows may arrive later.
end
local function schedule()
    cancel(reader)
    reader=C_Timer.NewTimer(D.reads==0 and .5 or 1.5,function()
        reader=nil; inspect()
        if not D.active then return end
        if D.reads>=3 then
            finish("three post-combat reads complete")
            A.Print("Damage capture complete: "..D.result..". /tw damage export to copy.")
        else schedule() end
    end)
end
function A.OnDamageDiagnosticEvent(event,...)
    if not D.active then return end
    local now=GetTime()
    if now>=D.armedAt+900 then finish("15-minute limit"); return end
    if event=="PLAYER_LOGOUT" then finish("logout"); return end
    if event=="ZONE_CHANGED_NEW_AREA" or event=="PLAYER_ENTERING_WORLD" or event=="SHARD_TRANSFER"
        or event=="SHARD_TRANSFER_IMMINENT" then block("zone/transfer event"); finish("context changed"); return end
    if event=="DAMAGE_METER_RESET" then block("meter reset"); finish("meter reset"); return end
    if event:match("^DUEL_") then block("duel event"); return end
    if event=="PLAYER_REGEN_DISABLED" then
        if D.state=="reading" then block("new combat before capture finished"); finish("new combat"); return end
        if D.state~="armed" then return end
        D.state="combat"; D.startedAt=now; row("COMBAT_START","observed")
        D.opponents={}; D.opponentCount=0; D.names={}; D.ambiguous={}
        checkContext(); observe("target"); observe("focus"); return
    elseif event=="PLAYER_REGEN_ENABLED" then
        if D.state~="combat" then return end
        D.state="reading"; D.endedAt=now; D.reads=0; checkContext()
        row("COMBAT_END","waiting for post-combat meter data"); schedule(); return
    end
    -- Bound noisy update/nameplate events; overflow invalidates this diagnostic.
    local second=math.floor(now)
    if D.second~=second then D.second=second; D.budget=100 end
    D.budget=D.budget-1; if D.budget<0 then block("event burst limit"); return end
    if event=="PLAYER_TARGET_CHANGED" then observe("target")
    elseif event=="PLAYER_FOCUS_CHANGED" then observe("focus")
    elseif event=="NAME_PLATE_UNIT_ADDED" then observe(...)
    elseif event=="DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        local kind,sid=...; kind=safe(kind); sid=safe(sid)
        if id(sid) then
            local target=D.state=="armed" and D.baseline or D.updated
            if not target[sid] then
                local n=0; for _ in pairs(target) do n=n+1 end
                if n>=SESSIONS then block("session event capacity"); finish("session capacity"); return end
                target[sid]=true
                row("METER_EVENT","phase="..D.state.." type="..text(kind).." session="..sid)
            end
        elseif not D.unknownSessionEvent then
            D.unknownSessionEvent=true; row("METER_EVENT","session identity unavailable/restricted")
        end
    end
end
local EVENTS={"PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_TARGET_CHANGED","PLAYER_FOCUS_CHANGED",
    "NAME_PLATE_UNIT_ADDED","ZONE_CHANGED_NEW_AREA","PLAYER_ENTERING_WORLD","SHARD_TRANSFER",
    "SHARD_TRANSFER_IMMINENT","PLAYER_LOGOUT","DAMAGE_METER_COMBAT_SESSION_UPDATED","DAMAGE_METER_RESET",
    "DUEL_REQUESTED","DUEL_TO_THE_DEATH_REQUESTED","DUEL_INBOUNDS","DUEL_OUTOFBOUNDS","DUEL_FINISHED"}
local function start(label)
    if D.active then A.Print("A capture is already active. /tw damage stop first."); return end
    if not quiet() then A.Print("Start damage capture while out of combat."); return end
    if A.testMode or A.WB.IsSimulation() then A.Print("Turn off simulated testing with /tw test off first."); return end
    D.armedAt=GetTime(); D.result="no readable attributable result"; D.state="idle"; D.blocked=nil
    row("START","damage-check="..D.revision.." label="..text(label).." addon="..text(A.release))
    for i=1,4 do row("BUILD","field"..i.."="..text(call(function() return select(i,GetBuildInfo()) end))) end
    for _,api in ipairs({"IsDamageMeterAvailable","GetAvailableCombatSessions","GetCombatSessionFromID","GetCombatSessionSourceFromID"}) do
        local fn=field(C_DamageMeter,api)
        row("API_PRESENT",api.."="..tostring(type(fn)=="function"))
    end
    if meter("IsDamageMeterAvailable")~=true then
        row("UNAVAILABLE","native meter unavailable; no capture armed")
        A.Print("Native damage meter unavailable. /tw damage export records the result."); return
    end
    local baseline,err=sessions()
    if not baseline then row("UNAVAILABLE",err); A.Print("Cannot read meter sessions. /tw damage export."); return end
    D.loc=location(); D.selfGUID=call(UnitGUID,"player"); D.selfNames=aliases("player")
    if not D.loc or not name(D.selfGUID) or not next(D.selfNames) then
        row("UNAVAILABLE","local identity/location unavailable"); A.Print("Local identity/location unavailable. /tw damage export."); return
    end
    if not flagsOK() then row("UNAVAILABLE","exclusion state blocked/unavailable"); A.Print("Cannot arm in a duel, instance, FFA or sanctuary, or with unreadable exclusion state."); return end
    D.baseline=baseline; D.updated={}; D.sessionID=nil; D.opponents={}; D.opponentCount=0
    D.names={}; D.ambiguous={}; D.reads=0; D.unknownSessionEvent=nil; D.state="armed"; D.active=true
    local known={}; for sid in pairs(baseline) do known[#known+1]=sid end; table.sort(known)
    row("BASELINE","existing session IDs="..table.concat(known,","))
    row("LOCATION",string.format("map=%d x=%.4f y=%.4f",D.loc.mapID,D.loc.x,D.loc.y))
    if not frame then frame=CreateFrame("Frame"); frame:SetScript("OnEvent",function(_,event,...) A.OnDamageDiagnosticEvent(event,...) end) end
    for _,event in ipairs(EVENTS) do
        local ok,result=pcall(frame.RegisterEvent,frame,event)
        if not ok or secret(result) or result==false then block("event unavailable: "..event) end
    end
    observe("target"); observe("focus")
    deadline=C_Timer.NewTimer(900,function() deadline=nil; if D.active then finish("15-minute limit"); A.Print("Damage capture timed out. /tw damage export.") end end)
    A.UpdateAutoReports()
    A.Print("Damage capture armed for ONE fight (15-minute limit). Normal reports paused; no test broadcasts. /tw damage status | stop | export.")
end
function A.DamageDiagnosticActive() return D.active end
function A.DamageDiagnosticText()
    return "TotalWarcraft damage diagnostics v1 | addon="..text(A.release).." | revision="..D.revision.." | omitted="..db.dropped
        .."\nLocal dev capture. Names and locations included; no upload. Candidates need native API review, not server proof.\n"
        ..table.concat(db.entries,"\n")
end
local function export()
    if not A.damageExport then
        local f=A.Surface("WarbandPvPDamageExport",760,720,"DAMAGE CHECK - DEVELOPMENT")
        A.Label(f,28,-174,690,"Ctrl+A, Ctrl+C to copy. Results stay local. Review names before sharing.")
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",28,-208); scroll:SetPoint("BOTTOMRIGHT",-46,58)
        local edit=CreateFrame("EditBox",nil,scroll); edit:SetMultiLine(true); edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(670); edit:SetAutoFocus(false); edit:SetScript("OnEscapePressed",function() f:Hide() end)
        scroll:SetScrollChild(edit); f.edit=edit; A.damageExport=f
    end
    local f=A.damageExport; f.edit:SetText(A.DamageDiagnosticText()); f:Show(); f.edit:SetFocus(); f.edit:HighlightText()
end
function A.DamageCommand(input)
    local cmd,arg=input:match("^%s*(%S*)%s*(.-)%s*$"); cmd=cmd:lower()
    if cmd=="start" then start(arg)
    elseif cmd=="stop" then if D.active then finish("user stopped") end; A.Print("Damage capture stopped. /tw damage export.")
    elseif cmd=="export" then export()
    elseif cmd=="clear" then if D.active then finish("clear") end; db.entries={}; db.dropped=0; D.result="not run"; A.Print("Damage log cleared.")
    else
        A.Print("Damage check v1 | "..D.state.." | "..D.result.." | rows="..#db.entries)
        A.Print("/tw damage start <label> | status | stop | export | clear. Dev only; normal reports pause during capture.")
    end
end
function A.InitDamageDiagnostics()
    if D.active then finish("reinitialize") end
    db=WarbandPvPDiagnosticsDB.damage
    if type(db)~="table" then db={} end
    local rows={}
    if type(db.entries)=="table" then
        for i=math.max(1,#db.entries-ROWS+1),#db.entries do
            local v=safe(db.entries[i]); if type(v)=="string" then rows[#rows+1]=v:sub(1,1000) end
        end
    end
    db.entries=rows; db.dropped=number(db.dropped,0,1e9) and math.floor(db.dropped) or 0
    db.version=1; WarbandPvPDiagnosticsDB.damage=db
    -- Never resume a capture across reload/login; only readable log strings persist.
end
