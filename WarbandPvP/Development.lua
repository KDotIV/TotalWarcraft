local _,A=...
function A.SetTestMode(enabled)
    if enabled~=true and A.WB and A.WB.IsSimulation() then A.SetWarbandSimulation("off") end
    A.testMode = enabled == true
    if A.ClearScouting then A.ClearScouting() end
    if A.FinderSync then A.FinderSync() end
    if not A.testMode then
        for id, r in pairs(A.records) do if r.test then A.records[id] = nil end end
        for _, f in ipairs({A.toast or false, A.details or false}) do
            if f and f.record and f.record.test then f:Hide() end
        end
    end
    A.Changed()
    A.Print(A.testMode and "TEST MODE ON for this session. /wb report sends simulated guild reports."
        or "Test mode off; simulated reports/warbands cleared and incoming tests ignored.")
end

function A.Demo()
    local loc = A.CurrentLocation()
    if not loc then A.Print("Move outdoors to preview reports at your location."); return end
    local now = GetServerTime()
    for i, kind in ipairs({"heat", "defense", "raid"}) do
        A.Receive({version = 1, id = "demo:" .. kind, kind = kind,
            faction = UnitFactionGroup("player"), ruleset = A.db.ruleset,
            mapID = loc.mapID, x = math.min(.98, loc.x + (i - 1) * .03), y = loc.y,
            updatedAt = now, expiresAt = now + 300, count = 4 + i * 4,
            title = ({"Fighting reported nearby", "Reinforcements requested", "Guild raid rally"})[i],
            reporter = "Preview organizer", opposition = "Example guild", note = "Sample data only.",
            demo = true, estimated = true, cityAllowed = true})
    end
    A.BuildUI(); A.panel:Show()
end

function A.DevelopmentCommand(command,input)
    if command:match("^simulate") then A.WarbandCommand("simulate "..(input:match("^%S+%s*(.*)$") or ""))
    elseif command == "control" then A.ControlCommand("")
    elseif command:match("^control ") then A.ControlCommand(input:sub(9))
    elseif command == "remote" then A.RemoteCommand("")
    elseif command:match("^remote ") then A.RemoteCommand(input:sub(8))
    elseif command == "layer" then A.LayerCommand("")
    elseif command:match("^layer ") then A.LayerCommand(command:sub(7))
    elseif command == "evidence" then A.Print(A.EvidenceStatus())
    elseif command == "test on" then A.SetTestMode(true)
    elseif command == "test off" then A.SetTestMode(false)
    elseif command == "mapdebug" then A.MapDebug()
    elseif command == "pincheck" then A.PinCheck()
    elseif command == "demo" then A.Demo()
    else return false end
    return true
end
