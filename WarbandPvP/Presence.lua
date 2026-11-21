local _, A = ...
-- Cooperative self-location only. This store never feeds report counts or heat.
local PREFIX, INTERVAL, TTL = "WBP_PRES1", 10, 30
local peers, roster, aliases = {}, {}, {}
local budget, refill, lastAttempt = 80, 0, nil
local rejectedAt = {}
local function secret(v) return issecretvalue and issecretvalue(v) end
local function read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, ...)
    if not ok or secret(a) or secret(b) then return end
    return a, b
end
local function number(v, lo, hi)
    return not secret(v) and type(v) == "number" and v == v and v >= lo and v <= hi
end
local function fullName(name, realm)
    if type(name) ~= "string" or name == "" or #name > 128 then return end
    if type(realm) == "string" and realm ~= "" then
        realm = realm:gsub("%s", "")
        if name:sub(-#realm-1) ~= "-" .. realm then name = name .. "-" .. realm end
    elseif not name:find("-", 1, true) then
        realm = read(GetNormalizedRealmName)
        if type(realm) == "string" and realm ~= "" then
            name = name .. "-" .. realm
        elseif not (A.ForeverClient and A.ForeverClient()) then
            return
        end
        -- Forever may hide realm metadata. The resulting name is accepted only
        -- when it uniquely matches a readable member of our actual party roster.
    end
    return name:gsub("%s", "")
end
local function route()
    if read(IsInInstance) ~= false then return end
    local home = Enum and Enum.PartyCategory and Enum.PartyCategory.Home or 1
    if read(IsInRaid, home) == true then return "RAID" end
    if read(IsInGroup, home) == true then return "PARTY" end
end
local function changed()
    if A.RefreshMap then A.RefreshMap() end
    if A.RefreshHome then A.RefreshHome() end
    if A.RefreshPresenceUI then A.RefreshPresenceUI() end
end
function A.ClearPresence()
    peers = {}
end
function A.RefreshPresenceRoster()
    roster, aliases = {}, {}
    local active = route()
    local ownGUID = read(UnitGUID, "player")
    local interface = read(function() return select(4, GetBuildInfo()) end)
    local forever = type(interface) == "number" and interface >= 16000 and interface < 20000
    local function alias(key, member)
        if not key then return end
        local old = aliases[key]
        if old == nil or (old and old.guid == member.guid) then aliases[key] = member
        else aliases[key] = false end -- ambiguous names never select an arbitrary GUID
    end
    if active and type(ownGUID) == "string" then
        for i = 1, active == "RAID" and 40 or 4 do
            local unit = (active == "RAID" and "raid" or "party") .. i
            local guid = read(UnitGUID, unit)
            local name, realm = read(UnitFullName, unit)
            local id = fullName(name, realm)
            local first, surname = read(UnitName, unit)
            local compound = forever and type(first) == "string" and type(surname) == "string"
                and first ~= "" and surname ~= "" and (first .. " " .. surname) or nil
            if not id and compound then id = fullName(compound) end
            if id and type(guid) == "string" and guid ~= ownGUID and read(UnitIsPlayer, unit) == true then
                local member = roster[guid] or {guid=guid, unit=unit, name=id}
                roster[guid] = member; alias(id, member)
                -- Forever UnitName can return first/surname separately while chat uses
                -- a space or hyphen. Accept only aliases built from this actual roster.
                if compound then
                    alias(fullName(compound), member)
                    alias(fullName(first .. "-" .. surname), member)
                    alias(fullName(compound, realm), member)
                    alias(fullName(first .. "-" .. surname, realm), member)
                end
            end
        end
    end
    -- Never resolve an unqualified collision with our own name to a remote peer.
    local ownName, ownRealm = read(UnitFullName, "player")
    local ownFirst, ownSecond = read(UnitName, "player")
    local selfKeys = {fullName(ownName,ownRealm), fullName(ownFirst)}
    if forever and type(ownFirst) == "string" and type(ownSecond) == "string" and ownSecond ~= "" then
        selfKeys[#selfKeys+1] = fullName(ownFirst .. " " .. ownSecond)
        selfKeys[#selfKeys+1] = fullName(ownFirst .. "-" .. ownSecond)
    end
    for _, key in pairs(selfKeys) do aliases[key] = false end
    local present = {}
    for _, member in pairs(roster) do present[member.guid] = true end
    for guid in pairs(peers) do if not present[guid] then peers[guid] = nil end end
    return active
end
function A.PresencePeerForUnit(unit)
    if not A.presenceEnabled then return end
    local guid = read(UnitGUID, unit)
    local peer = type(guid) == "string" and peers[guid]
    if peer and peer.expiresAt > GetServerTime() then return peer end
end
local function bitValue(fn)
    local v = read(fn, "player")
    return v == true and "1" or v == false and "0" or "?"
end
function A.SendPresence()
    if not A.presenceEnabled or not A.presenceReady or not A.RefreshScope() then return end
    local active = route()
    if not active then return end
    local clock = GetTime()
    if lastAttempt and clock - lastAttempt < INTERVAL then return end
    -- Count failed attempts too: no rapid retries after a rejected send.
    lastAttempt = clock
    local loc = read(A.CurrentLocation)
    local faction = read(UnitFactionGroup, "player")
    if type(loc) ~= "table" or not number(loc.mapID, 1, 100000) or loc.mapID % 1 ~= 0
        or not number(loc.x, 0, 1) or not number(loc.y, 0, 1)
        or (faction ~= "Horde" and faction ~= "Alliance") then return end
    local packet = table.concat({"1", tostring(GetServerTime()), tostring(loc.mapID),
        tostring(math.floor(loc.x * 10000 + .5)), tostring(math.floor(loc.y * 10000 + .5)),
        faction == "Horde" and "H" or "A", A.scopeRuleset, tostring(A.scopeRegion),
        bitValue(UnitIsPVP), bitValue(UnitAffectingCombat)}, "\t")
    if #packet > 255 then return end
    local result = read(C_ChatInfo and C_ChatInfo.SendAddonMessage, PREFIX, packet, active)
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
    A.presenceSendStatus = (result == success or result == true) and "accepted (delivery unconfirmed)" or "rejected/unavailable"
    if A.Trace then A.Trace("PRESENCE_SEND", "route=" .. active .. " result=" .. A.presenceSendStatus) end
end
local function rejected(reason, sender)
    if not A.Trace then return end
    local now = GetTime()
    if rejectedAt[reason] and now - rejectedAt[reason] < 5 then return end
    rejectedAt[reason] = now
    A.Trace("PRESENCE_REJECT", "reason=" .. reason .. " sender=" .. A.CleanText(sender,128))
end
local function integer(s, lo, hi)
    if not s or not s:match("^%d+$") then return end
    local n = tonumber(s)
    if number(n, lo, hi) then return n end
end
function A.OnPresenceMessage(prefix, packet, channel, sender)
    if secret(prefix) or secret(packet) or secret(channel) or secret(sender) then return end
    if not A.presenceEnabled or prefix ~= PREFIX or type(packet) ~= "string" or #packet > 255
        or (channel ~= "PARTY" and channel ~= "RAID") or channel ~= route() then return end
    local id = fullName(sender)
    local member = id and aliases[id]
    if not member then rejected("sender_not_uniquely_in_roster", sender); return end
    local clock = GetTime()
    budget = math.min(80, budget + math.max(0, clock - refill) * 8); refill = clock
    if budget < 1 then return end
    budget = budget - 1
    if not A.RefreshScope() then return end
    local f = {}
    for value in (packet .. "\t"):gmatch("(.-)\t") do
        f[#f+1] = value; if #f > 10 then return end
    end
    if #f ~= 10 or f[1] ~= "1" then rejected("packet_shape",sender); return end
    local now = GetServerTime()
    local time, map = integer(f[2], now - TTL + 1, now + 5), integer(f[3], 1, 100000)
    local x, y, region = integer(f[4], 0, 10000), integer(f[5], 0, 10000), integer(f[8], 1, 99)
    local faction = read(UnitFactionGroup, "player")
    if not time or not map or not x or not y or not region or region ~= A.scopeRegion or f[7] ~= A.scopeRuleset
        or (faction ~= "Horde" and faction ~= "Alliance")
        or f[6] ~= (faction == "Horde" and "H" or "A") then rejected("scope_location_or_time",sender); return end
    for i = 9, 10 do if f[i] ~= "0" and f[i] ~= "1" and f[i] ~= "?" then return end end
    local old = peers[member.guid]
    if old and (time <= old.updatedAt or clock - old.receivedAt < 5) then return end
    peers[member.guid] = {guid=member.guid, name=member.name, mapID=map, x=x/10000, y=y/10000,
        updatedAt=time, expiresAt=math.min(time + TTL, now + TTL), receivedAt=clock,
        flagged=f[9], combat=f[10]}
    if A.Trace then A.Trace("PRESENCE_RECEIVE", "sender=" .. A.CleanText(sender,128) .. " guid=" .. A.CleanText(member.guid,128) .. " at=" .. time) end
    changed()
end
function A.PresenceList()
    local list = {}
    if not A.presenceEnabled or not route() then return list end
    local now = GetServerTime()
    for guid, p in pairs(peers) do
        if p.expiresAt <= now then peers[guid] = nil else list[#list+1] = p end
    end
    table.sort(list, function(a,b) return a.name < b.name end)
    return list
end
function A.PresenceSummary()
    local fresh, nearby, unknown = 0, 0, 0
    for _, p in ipairs(A.PresenceList()) do
        fresh = fresh + 1
        local member = roster[p.guid]
        local distance, checked = read(UnitDistanceSquared, member and member.unit)
        if checked == true and number(distance, 0, math.huge) and distance < math.huge then
            if distance <= 10000 then nearby = nearby + 1 end
        else unknown = unknown + 1 end
    end
    return fresh, nearby, unknown
end
function A.PrintPresenceStatus()
    local fresh, nearby, unknown = A.PresenceSummary()
    A.Print("Group presence " .. (A.presenceEnabled and "ON" or "OFF") .. " | messaging=" .. tostring(A.presenceReady == true)
        .. " | route=" .. (route() or "none (outdoor party/raid required)")
        .. " | " .. fresh .. " sharing peers; " .. nearby .. " checked within 100yd; " .. unknown .. " unknown range.")
    A.Print("Presence is not PvP participation. Layer unknown. Last send: " .. (A.presenceSendStatus or "none"))
end
function A.PresenceTick()
    A.RefreshPresenceRoster()
    A.PresenceList()
    A.SendPresence()
    changed()
end
function A.SetPresenceEnabled(enabled)
    A.presenceEnabled = enabled == true and A.presenceReady == true
    if A.presenceTimer then A.presenceTimer:Cancel(); A.presenceTimer = nil end
    A.ClearPresence()
    if A.presenceEnabled then
        A.PresenceTick()
        A.presenceTimer = C_Timer.NewTicker(INTERVAL, A.PresenceTick)
        A.Print("Sharing your location and readable flag/combat status with your outdoor party/raid for this session.")
    else
        changed()
        A.Print("Group presence off. Previously shared positions expire on other clients within 30 seconds.")
    end
    if A.RefreshUI then A.RefreshUI() end
    A.PrintPresenceStatus()
end
function A.InitPresence()
    A.presenceEnabled = false
    local result = read(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    local codes = Enum and Enum.RegisterAddonMessagePrefixResult
    A.presenceReady = result == true or result == (codes and codes.Success or 0)
        or result == (codes and codes.DuplicatePrefix or 1)
    if not A.presenceReady then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON"); f:RegisterEvent("GROUP_ROSTER_UPDATE"); f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then A.OnPresenceMessage(...)
        elseif A.presenceEnabled then
            if event == "PLAYER_ENTERING_WORLD" then A.ClearPresence() end
            A.RefreshPresenceRoster(); changed()
        end
    end)
end
