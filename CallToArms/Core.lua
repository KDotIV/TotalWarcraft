local name, A = ...
A.release = "0.5.2-alpha"
function A.Print(message) print("|cffedbf69Call to Arms:|r " .. message) end

function A.Changed()
    if A.RefreshReportSurfaces then A.RefreshReportSurfaces() end
    A.RefreshUI(); A.RefreshMap()
    if not A.timer and next(A.records) then
        A.timer = C_Timer.NewTicker(15, function()
            A.Prune(GetServerTime())
            if A.RefreshReportSurfaces then A.RefreshReportSurfaces() end
            A.RefreshUI(); A.RefreshMap()
            if not next(A.records) then A.timer:Cancel(); A.timer = nil end
        end)
    end
end

function A.Notify(r)
    if A.db.muted then return end
    local now = GetTime()
    local field = r.test and "lastTestNotice" or "lastNotice"
    if A[field] and now - A[field] < (r.test and 5 or 30) then return end
    A[field] = now
    A.ShowToast(r)
end

function A.SetTestMode(enabled)
    A.testMode = enabled == true
    if not A.testMode then
        for id, r in pairs(A.records) do if r.test then A.records[id] = nil end end
        for _, f in ipairs({A.toast or false, A.details or false}) do
            if f and f.record and f.record.test then f:Hide() end
        end
    end
    A.Changed()
    A.Print(A.testMode and "TEST MODE ON for this session. /cta report sends simulated guild reports."
        or "Test mode off; simulated reports cleared and incoming tests ignored.")
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

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GAME_RULES_CHANGED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == name then
        if type(CallToArmsDB) ~= "table" then CallToArmsDB = {} end
        A.db = CallToArmsDB
        if A.db.ruleset ~= "pvp" and A.db.ruleset ~= "normal" and A.db.ruleset ~= "rp" and A.db.ruleset ~= "rppvp" then A.db.ruleset = "pvp" end
        A.db.muted = A.db.muted == true
        if type(A.db.lastSubmit) ~= "number" or A.db.lastSubmit ~= A.db.lastSubmit or A.db.lastSubmit > GetServerTime() then A.db.lastSubmit = 0 end
        -- Guild packets use a narrow versioned protocol, never ordinary chat.
        A.testMode = false
        if A.RefreshScope then A.RefreshScope() end
        if A.InitGuildTransport then A.InitGuildTransport() end
        if A.InitPresence then A.InitPresence() end
        if A.InitDiagnostics then A.InitDiagnostics() end
        if A.InitControl then A.InitControl() end
        CallToArms = {
            Report = A.RunReport,
            Receive = A.Receive,
            SetTransport = function(send)
                if send ~= nil and type(send) ~= "function" then return false end
                A.adapter = send; A.RefreshUI(); return true
            end,
            Version = 1,
        }
        SLASH_CALLTOARMS1 = "/cta"
        BINDING_HEADER_CALLTOARMS = "Call to Arms"
        BINDING_NAME_CALLTOARMS_REPORT = "Report PvP at my location"
        SlashCmdList.CALLTOARMS = function(command)
            local input = command:match("^%s*(.-)%s*$")
            command = input:lower()
            if command == "report" then A.RunReport()
            elseif command == "control" then A.ControlCommand("")
            elseif command:match("^control ") then A.ControlCommand(input:sub(9))
            elseif command == "remote" then A.RemoteCommand("")
            elseif command:match("^remote ") then A.RemoteCommand(input:sub(8))
            elseif command == "layer" then A.LayerCommand("")
            elseif command:match("^layer ") then A.LayerCommand(command:sub(7))
            elseif command == "evidence" then A.Print(A.EvidenceStatus())
            elseif command == "presence on" then A.SetPresenceEnabled(true)
            elseif command == "presence off" then A.SetPresenceEnabled(false)
            elseif command == "presence" or command == "presence status" then A.PrintPresenceStatus()
            elseif command == "test on" then A.SetTestMode(true)
            elseif command == "test off" then A.SetTestMode(false)
            elseif command == "status" then
                if A.RefreshScope then A.RefreshScope() end
                A.Print(A.release .. " | guild=" .. tostring(IsInGuild()) .. " | messaging=" .. tostring(A.guildReady == true)
                    .. " | ruleset=" .. (A.scopeRuleset or "UNKNOWN - network disabled")
                    .. " | region=" .. tostring(A.scopeRegion) .. " | test=" .. tostring(A.testMode == true)
                    .. " | presence=" .. tostring(A.presenceEnabled == true)
                    .. " | capture=" .. tostring(A.DiagnosticActive and A.DiagnosticActive() or false))
            elseif command == "mapdebug" then A.MapDebug()
            elseif command == "pincheck" then A.PinCheck()
            elseif command == "demo" then A.Demo()
            elseif command == "clear" then
                A.records = {}; if A.toast then A.toast:Hide() end; if A.details then A.details:Hide() end; A.Changed()
            elseif command:match("^ruleset ") then
                A.Print("Network rulesets are detected from the game; manual overrides are disabled. Use /cta status.")
            else A.BuildUI(); A.panel:SetShown(not A.panel:IsShown()) end
        end
    elseif event == "GAME_RULES_CHANGED" then
        if A.db and A.RefreshScope then A.RefreshScope() end
    elseif event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and (addon == "Blizzard_WorldMap" or addon == "OpenMap")) then
        if A.db and A.RefreshScope then A.RefreshScope() end
        A.AttachMap()
    end
end)
