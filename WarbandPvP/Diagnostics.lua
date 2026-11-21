local _, A = ...
local LIMIT, MAX_SECONDS = 1200, 900
local db, frame, ticker, started, session, lastSnapshot, pending
local counts, eventTimes = {}, {}
local evidenceSecond, evidenceBudget, evidenceSkipped = -1, 200, 0
local function secret(v) return issecretvalue and issecretvalue(v) end
local function scalar(v)
    if secret(v) then return "<secret>" end
    local kind = type(v)
    if kind == "string" then return v:gsub("|", ""):gsub("[%c]", " "):sub(1, 120) end
    if kind == "number" then
        return v == v and math.abs(v) < math.huge and tostring(v) or "<nonfinite>"
    end
    if kind == "boolean" then return v and "true" or "false" end
    return kind == "nil" and "nil" or "<" .. kind .. ">"
end
local function probe(fn, ...)
    if type(fn) ~= "function" then return "<unavailable>", "<unavailable>", "<unavailable>", "<unavailable>" end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return "<error>", "<error>", "<error>", "<error>" end
    return scalar(a), scalar(b), scalar(c), scalar(d)
end
local function add(kind, message)
    if not db then return end
    local row = string.format("%d t=%.3f run=%s %s %s", GetServerTime(), GetTime(), session or "manual", kind, message)
    db.entries[#db.entries+1] = row:sub(1, 1600)
    if #db.entries > LIMIT then table.remove(db.entries, 1); db.dropped = db.dropped + 1 end
end
function A.DiagnosticActive() return started ~= nil end
-- Called only with small, locally generated strings by the reporting adapters.
function A.DiagnosticTrace(kind, message)
    if started then add(kind, message) end
end
local function unitRow(unit)
    local name, realm = probe(UnitFullName, unit)
    local first, second = probe(UnitName, unit)
    local distance, checked = probe(UnitDistanceSquared, unit)
    local phase = probe(UnitPhaseReason, unit)
    local reason = Enum and Enum.PhaseReason
    if reason then
        for key, value in pairs(reason) do
            if not secret(value) and phase == tostring(value) then phase = key .. "(" .. phase .. ")"; break end
        end
    end
    local peer = A.PresencePeerForUnit and A.PresencePeerForUnit(unit)
    return "unit=" .. unit .. " guid=" .. probe(UnitGUID, unit)
        .. " fullName=" .. name .. " realm=" .. realm .. " unitName=" .. first .. "/" .. second
        .. " exists=" .. probe(UnitExists, unit) .. " connected=" .. probe(UnitIsConnected, unit)
        .. " player=" .. probe(UnitIsPlayer, unit) .. " leader=" .. probe(UnitIsGroupLeader, unit)
        .. " map=" .. probe(C_Map and C_Map.GetBestMapForUnit, unit)
        .. " partyShard=" .. probe(UnitInPartyShard, unit) .. " phase=" .. phase
        .. " visible=" .. probe(UnitIsVisible, unit) .. " distanceSq=" .. distance .. " checked=" .. checked
        .. " pvpFlag=" .. probe(UnitIsPVP, unit) .. " combat=" .. probe(UnitAffectingCombat, unit)
        .. " hostile=" .. probe(UnitCanAttack, "player", unit)
        .. " targetMatches=" .. probe(UnitIsUnit, "target", unit)
        .. " peerAge=" .. (peer and tostring(math.max(0, GetServerTime()-peer.updatedAt)) or "none")
end
local function snapshot(label)
    if not db then return end
    lastSnapshot = GetTime(); pending = false
    local loc = A.CurrentLocation and A.CurrentLocation()
    local location = loc and (scalar(loc.mapID) .. ":" .. scalar(loc.x) .. "," .. scalar(loc.y)) or "unavailable"
    add("SNAPSHOT", "label=" .. scalar(label) .. " location=" .. location
        .. " scope=" .. scalar(A.scopeRuleset) .. "/" .. scalar(A.scopeRegion)
        .. " combatLock=" .. probe(InCombatLockdown) .. " eviction=" .. probe(GetEvictionTimeRemaining)
        .. " test=" .. tostring(A.testMode == true) .. " presence=" .. tostring(A.presenceEnabled == true)
        .. " reports=" .. #A.List() .. " peers=" .. #(A.PresenceList and A.PresenceList() or {}))
    add("UNIT", unitRow("player"))
    local home = Enum and Enum.PartyCategory and Enum.PartyCategory.Home or 1
    local raid = probe(IsInRaid, home) == "true"
    for i = 1, raid and 40 or 4 do
        local unit = (raid and "raid" or "party") .. i
        if probe(UnitExists, unit) ~= "false" then add("UNIT", unitRow(unit)) end
    end
    for _, unit in ipairs({"target", "focus"}) do
        if probe(UnitExists, unit) ~= "false" then add("UNIT", unitRow(unit)) end
    end
end
local function flushEvidence()
    local keys = {}
    for key in pairs(counts) do keys[#keys+1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do add("EVIDENCE", key .. " events=" .. counts[key]) end
    if evidenceSkipped > 0 then add("EVIDENCE_DROPPED", tostring(evidenceSkipped) .. " over 200 events/second cap") end
    evidenceSkipped = 0
    counts = {}
end
function A.EvidenceStatus()
    return "confirmedParticipants=unknown source=none; UNIT_COMBAT has no attacker; flags/targets/presence are context only"
end
local function stop(reason)
    if not started then return end
    flushEvidence(); snapshot("stop")
    add("STOP", reason or "user")
    started = nil
    if ticker then ticker:Cancel(); ticker = nil end
    if frame then frame:UnregisterAllEvents() end
    pending = false
end
local EVENTS = {"SHARD_TRANSFER_IMMINENT", "SHARD_TRANSFER", "SHARD_TRANSFER_CANCELLED",
    "GROUP_ROSTER_UPDATE", "GROUP_JOINED", "GROUP_LEFT", "PARTY_LEADER_CHANGED",
    "PARTY_INVITE_REQUEST", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
    "UNIT_PHASE", "UNIT_CONNECTION", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GAME_RULES_CHANGED", "PLAYER_LOGOUT",
    "UNIT_COMBAT", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED"}
local function evidence(event, unit, action)
    local second = math.floor(GetTime())
    if second ~= evidenceSecond then evidenceSecond = second; evidenceBudget = 200 end
    if evidenceBudget <= 0 then evidenceSkipped = math.min(1000000,evidenceSkipped+1); return end
    evidenceBudget = evidenceBudget - 1
    if secret(unit) or type(unit) ~= "string" then return end
    local allowed = unit == "player" or unit == "target" or unit == "focus"
        or unit:match("^party[1-4]$") or unit:match("^raid%d+$")
    if not allowed then return end
    local index = tonumber(unit:match("^raid(%d+)$"))
    if index and (index < 1 or index > 40) then return end
    -- Only count event occurrence and affected-unit context. Never inspect amount,
    -- spell target, cast GUID or other payloads; never infer the missing attacker.
    local key = event .. " unit=" .. unit
    if event == "UNIT_COMBAT" then
        local safeAction = scalar(action)
        if safeAction ~= "WOUND" and safeAction ~= "HEAL" and safeAction ~= "DODGE"
            and safeAction ~= "PARRY" and safeAction ~= "BLOCK" and safeAction ~= "MISS" then safeAction = "other/unknown" end
        key = key .. " action=" .. safeAction
    end
    key = key .. " player=" .. probe(UnitIsPlayer, unit) .. " attribution=unknown"
    counts[key] = math.min(1000000, (counts[key] or 0) + 1)
end
function A.OnDiagnosticEvent(event, ...)
    if not started then return end
    if event == "UNIT_COMBAT" or event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        evidence(event, ...); return
    end
    local now = GetTime()
    if eventTimes[event] and now - eventTimes[event] < .25 then pending = true; return end
    eventTimes[event] = now
    local arg = ...
    add("EVENT", event .. " arg=" .. scalar(arg) .. " eviction=" .. probe(GetEvictionTimeRemaining))
    if event == "PLAYER_LOGOUT" then stop("logout"); return end
    if not lastSnapshot or now - lastSnapshot >= 1 then snapshot(event) else pending = true end
end
local function start(label)
    stop("restart")
    session = scalar(label ~= "" and label or "test"):sub(1, 40) .. "-" .. GetServerTime()
    started = GetTime(); eventTimes = {}; counts = {}; evidenceSecond=-1; evidenceSkipped=0
    add("START", "addon=" .. (A.release or "unknown") .. " build=" .. probe(GetBuildInfo)
        .. " buildNumber=" .. select(2, probe(GetBuildInfo)) .. " player=" .. probe(UnitName, "player"))
    add("POLICY", A.EvidenceStatus() .. "; observations only, no automatic synced verdict; local log, no diagnostic broadcasts")
    if not frame then frame = CreateFrame("Frame"); frame:SetScript("OnEvent", function(_, event, ...) A.OnDiagnosticEvent(event, ...) end) end
    for _, event in ipairs(EVENTS) do
        local ok, result = pcall(frame.RegisterEvent, frame, event)
        add("REGISTER", event .. "=" .. (ok and not secret(result) and result ~= false and "ok" or "unavailable"))
    end
    snapshot("start")
    ticker = C_Timer.NewTicker(1, function()
        if not started then return end
        if GetTime() - started >= MAX_SECONDS then stop("15-minute limit"); A.Print("Diagnostic capture stopped at 15 minutes."); return end
        if pending or GetTime() - (lastSnapshot or 0) >= 5 then flushEvidence(); snapshot("sample") end
    end)
    A.diagnosticTicker = ticker
    A.Print("Layer/evidence capture started for up to 15 minutes. Each tester runs this command. /wb layer export to copy.")
end
function A.DiagnosticText()
    if not db then return "Diagnostics not initialized." end
    return "WBP diagnostics v1 | addon=" .. (A.release or "unknown") .. " | dropped=" .. db.dropped
        .. "\nLocal observations; merge all testers' exports by server time and run label. Not proof of layer/PvP by itself.\n"
        .. "NPC/object GUIDs are opaque session-local observations; do not compare them across clients to infer a layer.\n"
        .. table.concat(db.entries, "\n")
end
local function export()
    if started then flushEvidence() end
    if not A.diagnosticExport then
        local f = CreateFrame("Frame", "WarbandPvPDiagnosticExport", UIParent, "BackdropTemplate")
        f:SetSize(760,480); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); f:SetBackdropColor(.04,.05,.07,.98)
        local title = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        title:SetPoint("TOPLEFT",16,-14); title:SetText("WBP diagnostics - Ctrl+A, Ctrl+C to copy; Escape to close")
        local close = CreateFrame("Button",nil,f,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT")
        local scroll = CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",16,-42); scroll:SetPoint("BOTTOMRIGHT",-32,16)
        local edit = CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true); edit:SetFontObject(ChatFontNormal); edit:SetWidth(700); edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed",function() f:Hide() end)
        scroll:SetScrollChild(edit); f.edit=edit; A.diagnosticExport=f
        table.insert(UISpecialFrames,"WarbandPvPDiagnosticExport")
        A.RegisterWindow(f); f:Hide()
    end
    local f=A.diagnosticExport
    f.edit:SetText(A.DiagnosticText()); f:Show(); f.edit:SetFocus(); f.edit:HighlightText()
end
function A.LayerCommand(input)
    local cmd, arg = input:match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "start" then start(arg)
    elseif cmd == "stop" then stop("user"); A.Print("Capture stopped. /wb layer export or reload/logout to save it to disk.")
    elseif cmd == "snap" then
        flushEvidence(); snapshot(arg); A.Print("Diagnostic snapshot recorded. Values below are observations, not a synced verdict.")
        local home = Enum and Enum.PartyCategory and Enum.PartyCategory.Home or 1
        local raid = probe(IsInRaid, home) == "true"
        local units = {"player"}
        for i=1,raid and 40 or 4 do units[#units+1]=(raid and "raid" or "party") .. i end
        for _,unit in ipairs(units) do
            if unit == "player" or probe(UnitExists,unit) == "true" then
                local d, checked = probe(UnitDistanceSquared,unit)
                A.Print(unit .. " " .. probe(UnitName,unit) .. " | phase=" .. probe(UnitPhaseReason,unit)
                    .. " shard=" .. probe(UnitInPartyShard,unit) .. " visible=" .. probe(UnitIsVisible,unit)
                    .. " distanceSq=" .. d .. " checked=" .. checked)
            end
        end
    elseif cmd == "mark" then add("MANUAL", scalar(arg)); A.Print("Manual observation recorded (not automatic verification).")
    elseif cmd == "export" then export()
    elseif cmd == "clear" then stop("clear"); db.entries={}; db.dropped=0; A.Print("Diagnostic log cleared.")
    else
        A.Print("Layer capture " .. (started and "ON" or "OFF") .. " | rows=" .. #db.entries .. " | dropped=" .. db.dropped)
        A.Print("/wb layer start <run-label> | snap <label> | mark <observation> | stop | export | clear")
    end
end
function A.InitDiagnostics()
    if type(WarbandPvPDiagnosticsDB) ~= "table" then WarbandPvPDiagnosticsDB = {} end
    db = WarbandPvPDiagnosticsDB
    local valid = {}
    if type(db.entries) == "table" then
        for i = math.max(1, #db.entries-LIMIT+1), #db.entries do
            local row = db.entries[i]
            if not secret(row) and type(row) == "string" then valid[#valid+1]=row:sub(1,1600) end
        end
    end
    db.entries=valid
    if secret(db.dropped) or type(db.dropped) ~= "number" or db.dropped ~= db.dropped
        or db.dropped < 0 or db.dropped > 1000000000 then db.dropped=0 end
    db.version=1
    -- Capturing never resumes on login/reload. Existing logs remain available.
end
