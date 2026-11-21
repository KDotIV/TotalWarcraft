local _,A=...
local P,W=A.WB,A.warbands

local function fixtureInfo(count)
    if A.testMode~=true then return nil,"Run /wb test on before simulating a warband party." end
    if P.Read(IsInRaid)~=false or P.Read(IsInInstance)~=false then return nil,"Test outdoors and outside raids." end
    local own=P.UnitName("player")
    if not own then return nil,"Character identity unavailable." end
    -- Override only this feature's roster input. Never replace native WoW APIs,
    -- invent real sender identities, or add dummy members to the message roster.
    return {mode="leader",leader=own,count=count}
end
function A.WarbandSimulationInfo() return fixtureInfo(W.simulationCount) end
function A.WarbandModeStatus()
    if P.IsSimulation() then return "TEST party="..W.simulationCount.." (1 real + "..(W.simulationCount-1).." dummy)" end
    return "LIVE"
end
function A.SetWarbandSimulation(arg)
    if arg=="" or arg=="status" then return true,A.WarbandModeStatus().." | /wb simulate 1-5|off" end
    local count
    if arg~="off" then
        count=P.Integer(arg,1,5)
        if not count then return false,"Use /wb simulate 1-5|off (count includes your real character)." end
        if not W.ready or not W.testReady or not P.Scope() then return false,"Simulation messaging/scope unavailable." end
        local info,reason=fixtureInfo(count); if not info then return false,reason end
        if not P.IsSimulation() and (W.host or W.member or W.join) then
            return false,"Leave/end the live warband yourself before enabling simulation."
        end
        if P.IsSimulation() then
            W.simulationCount=count
            if W.host then W.host.dirty=true end
            if W.member then W.member.sentAt=nil end
            A.SetWarbandsEnabled(true)
            return true,"[TEST] Party roster: 1 real character + "..(count-1).." dummy slots. Real position; no native group changes."
        end
    elseif not P.IsSimulation() then return true,"Warband simulation already OFF." end

    -- Withdraw through the OLD prefix first. Queued terminal messages retain it;
    -- ordinary unsent snapshots/joins are removed by SetWarbandsEnabled(false).
    A.SetWarbandsEnabled(false)
    W.ledgers=W.ledgers or {}
    W.ledgers[P.ActivePrefix()]={history=W.history,owners=W.owners}
    W.simulationCount=count
    local ledger=W.ledgers[P.ActivePrefix()] or {history={},owners={}}
    W.history,W.owners=ledger.history,ledger.owners
    W.subscribers={}
    if count then A.SetWarbandsEnabled(true) end
    if A.Trace then A.Trace("WARBAND_SIMULATION",A.WarbandModeStatus()) end
    if A.RefreshWarbandUI then A.RefreshWarbandUI() end
    if A.RefreshMap then A.RefreshMap() end
    return true,count and ("[TEST] Party roster: 1 real character + "..(count-1).." dummy slots. Start or join a test warband; native parties stay unchanged.")
        or "Warband simulation OFF; test listings/membership cleared. Discovery is OFF."
end

function A.WarbandDisplayTitle(r) return (r.simulated and "[TEST] " or "")..r.title end
function A.WarbandCountText(r)
    if not r.simulated then return "WBP members: "..r.count.." (organizer-reported)" end
    local total,dummies=0,0
    for _,g in pairs(r.groups or {}) do if g.expiresAt>GetServerTime() then
        total=total+g.count; dummies=dummies+g.count-1
    end end
    return "Real WBP clients: "..r.count.." | simulated roster: "..total.." slots ("..dummies.." dummy)"
end
function A.WarbandGroupCountText(r,g)
    return r.simulated and ("1 real + "..(g.count-1).." dummy slots") or ("roster "..g.count.." (reported)")
end

-- Fixed remote-test verbs only. Control.lua supplies the authorized event sender;
-- joining is restricted to that controller's test listing, never a live warband.
function A.RemoteWarbandTest(verb,sender)
    if A.testMode~=true then return false,"Test mode must be ON for remote warband simulation." end
    if verb=="warband-five" then return A.SetWarbandSimulation("5") end
    if not P.IsSimulation() then return false,"Enable warband-five on this tester first." end
    if verb=="warband-watch" then return A.WatchWarband(sender) end
    if verb=="warband-leave" then A.LeaveWarband(); return true,"Left the simulated warband; native group unchanged." end
    if verb=="warband-join" then
        for _,r in ipairs(A.WarbandList()) do
            if r.simulated and r.ownerKey==P.Key(sender) then return A.JoinWarband(r.id) end
        end
        return false,"No fresh test warband from your controller. Use warband-watch, wait 30s, then retry."
    end
    return false,"Unknown warband test command."
end
