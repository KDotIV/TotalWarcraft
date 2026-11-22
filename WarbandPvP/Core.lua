local name, A = ...
A.release = A.release or "0.7.8-dev"
function A.Print(message) print("|cffedbf69TotalWarcraft:|r " .. message) end

function A.Changed()
    if A.timer and not next(A.records) then A.timer:Cancel(); A.timer=nil end
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
    if A.IsOwnReport(r) then A.Trace("ALERT_SKIP","own report id="..r.id); return end
    if A.db.muted then A.Trace("ALERT_SKIP","alerts muted id="..r.id); return end
    local now = GetTime()
--@dev
    local field = r.test and "lastTestNotice" or "lastNotice"
    if A[field] and now - A[field] < (r.test and 5 or 30) then return end
--@enddev
--@release     local field = "lastNotice"
--@release     if A[field] and now - A[field] < 30 then return end
    if A.ShowToast(r) then A[field] = now end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GAME_RULES_CHANGED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == name then
        if type(WarbandPvPDB) ~= "table" then WarbandPvPDB = {} end
        A.db = WarbandPvPDB
        if A.db.ruleset ~= "pvp" and A.db.ruleset ~= "normal" and A.db.ruleset ~= "rp" and A.db.ruleset ~= "rppvp" then A.db.ruleset = "pvp" end
        A.db.muted = A.db.muted == true
        if type(A.db.lastSubmit) ~= "number" or A.db.lastSubmit ~= A.db.lastSubmit or A.db.lastSubmit > GetServerTime() then A.db.lastSubmit = 0 end
        -- Reports use a narrow versioned protocol, never ordinary chat.
        --@dev
        A.testMode = false
        --@enddev
        if A.RefreshScope then A.RefreshScope() end
        if A.InitReportTransport then A.InitReportTransport() end
        if A.InitPresence then A.InitPresence() end
        --@dev
        A.InitDiagnostics(); A.InitDamageDiagnostics(); A.InitControl()
        --@enddev
        if A.InitWarbands then A.InitWarbands() end
        A.InitSessionLog()
        A.InitNotifications()
        A.InitReportChannel()
        A.InitFinder()
        A.InitScouting()
        A.InitAutoReports()
        WarbandPvP = {
            Report = A.RunReport,
            Open = A.ToggleHome,
            Warbands = A.ShowWarbands,
            Export = A.ShowExport,
--@dev
            Receive = A.Receive,
            SetTransport = function(send)
                if send ~= nil and type(send) ~= "function" then return false end
                A.adapter = send; A.RefreshUI(); return true
            end,
--@enddev

            Version = 1,
        }
        -- Keep installation/settings/binding and wire identifiers stable for upgrades.
        TotalWarcraft = WarbandPvP
        SLASH_WARBANDPVP1 = "/tw"
        SLASH_WARBANDPVP2 = "/totalwarcraft"
        SLASH_WARBANDPVP3 = "/wb"
        BINDING_HEADER_WARBANDPVP = "TotalWarcraft"
        BINDING_NAME_WARBANDPVP_REPORT = "Report PvP at my location"
        BINDING_NAME_WARBANDPVP_OPEN = "Open command board"
        BINDING_NAME_WARBANDPVP_WARBANDS = "Open warbands"
        BINDING_NAME_WARBANDPVP_EXPORT = "Export session journal"
        SlashCmdList.WARBANDPVP = function(command)
            local input = command:match("^%s*(.-)%s*$")
            command = input:lower()
            A.Trace("COMMAND",A.LogValue(command:match("^(%S+)") or "home",32))
            if command == "report" then A.RunReport()
            elseif command == "auto on" then A.SetAutoReportsEnabled(true)
            elseif command == "auto off" then A.SetAutoReportsEnabled(false)
            elseif command == "show" then A.ShowWarbands()
            elseif command == "finder" then A.ShowFinder()
            elseif command == "find" then local _,msg=A.FinderSearch(); A.Print(msg)
            elseif ({on=true,off=true,start=true,stop=true,leave=true,watch=true,unwatch=true,join=true,invite=true,rally=true,follow=true,recruit=true,state=true})[command:match("^(%S+)")] then A.WarbandCommand(input)
            elseif command == "presence on" then A.SetPresenceEnabled(true)
            elseif command == "presence off" then A.SetPresenceEnabled(false)
            elseif command == "presence" or command == "presence status" then A.PrintPresenceStatus()
            elseif command == "export" then A.ShowExport()
            elseif command == "help" then A.ShowHelp()
            elseif command == "status" then A.ShowHelp(9)
            --@dev
            elseif A.DevelopmentCommand(command,input) then
            --@enddev
            elseif command == "clear" then
                A.ClearReports()
            elseif command:match("^ruleset ") then
                A.Print("Network rulesets are detected from the game; manual overrides are disabled. Use /tw status.")
            elseif command == "" then A.ToggleHome()
            else A.Print("Unknown command. Open /tw for all features and shortcuts.") end
        end
    elseif event == "GAME_RULES_CHANGED" then
        if A.db and A.RefreshScope then A.RefreshScope() end
    elseif event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and (addon == "Blizzard_WorldMap" or addon == "OpenMap")) then
        if A.db and A.RefreshScope then A.RefreshScope() end
        A.AttachMap()
    end
end)
