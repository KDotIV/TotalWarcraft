local _,A=...
local P=A.WB
local R={}
A.autoReports=R
local function stopTimer()
    if R.timer then R.timer:Cancel(); R.timer=nil end
end

local function skip(reason)
    if R.skip~=reason and A.Trace then A.Trace("REPORT_AUTO_SKIP",reason) end
    R.skip=reason
end

local function duelRequested()
    -- Requests can be declined. The bounded hold becomes a combat-long latch
    -- if combat starts, so a long duel cannot outlive the request timeout.
    R.duelUntil=GetTime()+60
    if P.Read(UnitAffectingCombat,"player")==true then R.duelCombat=true end
end

function A.ReportBlockedByDuel()
    if R.duelCombat or R.duelActive or GetTime()<(R.duelUntil or 0) then
        if P.Read(UnitAffectingCombat,"player")==true then R.duelCombat=true end
        return true
    end
    return false
end

function A.SetAutoReportsEnabled(enabled)
    A.db.autoReports=enabled==true
    stopTimer()
    if A.db.autoReports then A.UpdateAutoReports() end
    if A.RefreshHome then A.RefreshHome() end
    if A.Trace then A.Trace("AUTO_REPORTS",A.db.autoReports and "on" or "off") end
end

function A.AutoReportTick()
    if not A.db or A.db.autoReports==false then return end
    if P.Read(UnitAffectingCombat,"player")~=true then A.UpdateAutoReports(); return end
--@dev
    if A.testMode or P.IsSimulation() then return end
--@enddev
    local now=GetTime()
    if R.checkedAt and now-R.checkedAt<1 then return end
    R.checkedAt=now
    if R.attempted then stopTimer(); return end
    if R.awaitPeace then return skip("waiting for a confirmed combat end") end
    if A.ReportBlockedByDuel() then return skip("duel hold") end
    if P.Read(IsInInstance)~=false then return skip("instance or instance state unavailable") end
    if P.Read(IsInGuild)~=true then return skip("guild required") end
    -- An accepted manual report during this combat already serves the same purpose.
    if (A.db.lastSubmit or 0)>=(R.startedAt or GetServerTime()) then R.attempted=true; stopTimer(); return end
    if GetServerTime()-(A.db.lastSubmit or 0)<120 or (A.lastAttempt and now-A.lastAttempt<5) then return skip("cooldown") end
    -- Combat plus a nearby flag alone is insufficient. Require the current target
    -- to be a visible, attackable opposing player who is also in combat.
    if P.Read(UnitExists,"target")~=true or P.Read(UnitIsVisible,"target")~=true
        or P.Read(UnitIsPlayer,"target")~=true or P.Read(UnitIsPVP,"target")~=true
        or P.Read(UnitAffectingCombat,"target")~=true or P.Read(UnitCanAttack,"player","target")~=true
        or P.Read(UnitIsDeadOrGhost,"target")~=false then return skip("target combat/flag/visibility/hostility checks unavailable or not eligible") end
    local own,other=P.Read(UnitFactionGroup,"player"),P.Read(UnitFactionGroup,"target")
    if not ((own=="Horde" and other=="Alliance") or (own=="Alliance" and other=="Horde")) then return skip("opposing faction required") end
    for _,unit in ipairs({"player","target"}) do
        if P.Read(UnitIsPVPFreeForAll,unit)~=false or P.Read(UnitIsPVPSanctuary,unit)~=false then return skip("sanctuary/FFA rules active or unavailable") end
    end
    R.attempted=true -- Failed sends do not cause an automatic retry loop.
    stopTimer()
    local ok,message=A.Report("automatic")
    if A.Trace then A.Trace("REPORT_AUTO","accepted="..tostring(ok==true).." "..A.CleanText(message,160)) end
    if ok then A.Print("PvP report sent to your guild.") end
end

function A.UpdateAutoReports()
    if not A.db then return end
    local combat=P.Read(UnitAffectingCombat,"player")
    if combat~=true then
        stopTimer()
        if combat==false then
            R.startedAt=nil; R.attempted=nil; R.checkedAt=nil; R.skip=nil
            R.awaitPeace=nil
            if R.duelCombat then R.duelUntil=math.max(R.duelUntil or 0,GetTime()+10); R.duelCombat=nil end
        else R.awaitPeace=true end -- Unreadable combat state must not reset an active fight/duel latch.
        return
    end
    if not R.startedAt then R.startedAt=GetServerTime() end
    if R.attempted then stopTimer(); return end
    if A.db.autoReports==false then return end
    if not R.timer then R.timer=C_Timer.NewTicker(1,A.AutoReportTick) end
    A.AutoReportTick()
end

function A.InitAutoReports()
    A.db.autoReports=A.db.autoReports~=false
    R.awaitPeace=true -- A reload during combat may have missed the duel request.
    local f=CreateFrame("Frame"); R.events=f
    for _,event in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_TARGET_CHANGED","PLAYER_ENTERING_WORLD",
        "DUEL_REQUESTED","DUEL_TO_THE_DEATH_REQUESTED","DUEL_INBOUNDS","DUEL_OUTOFBOUNDS","DUEL_FINISHED"}) do
        f:RegisterEvent(event)
    end
    f:SetScript("OnEvent",function(_,event)
        if event=="DUEL_REQUESTED" or event=="DUEL_TO_THE_DEATH_REQUESTED" then duelRequested()
        elseif event=="DUEL_INBOUNDS" or event=="DUEL_OUTOFBOUNDS" then R.duelActive=true
        elseif event=="DUEL_FINISHED" then
            R.duelActive=nil; R.duelUntil=GetTime()+10
            if P.Read(UnitAffectingCombat,"player")==true then R.duelCombat=true end
        end
        A.UpdateAutoReports()
    end)
    -- Observe outgoing duel requests without replacing or invoking the action.
    if type(hooksecurefunc)=="function" and type(StartDuel)=="function" then
        pcall(hooksecurefunc,"StartDuel",duelRequested)
    end
    A.UpdateAutoReports()
end
