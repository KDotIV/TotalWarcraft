local _,A=...
local P,W=A.WB,A.warbands
local F={pending={},probed={},choices={},status="Recruitment idle. Start a warband, or explicitly search for one to join."}
A.finder=F
-- Finder is a public recruitment directory, never a world-layer selector.
-- All identity/UUID data travels over our scoped addon protocol, not listing text.
local function secret(v) return issecretvalue and issecretvalue(v) end
local function field(t,k)
    if secret(t) or type(t)~="table" then return end
    return P.Read(function() return t[k] end)
end
local function call(name,...)
    local fn=C_LFGList and C_LFGList[name]
    if type(fn)~="function" then return false end
    local ok,v=pcall(fn,...)
    return ok and not secret(v) and v~=false,v
end
local function status(text)
    if F.status==text then return end
    F.status=text
    if A.Trace then A.Trace("FINDER",text) end
    if A.RefreshFinderUI then A.RefreshFinderUI() end
    if A.RefreshWarbandUI then A.RefreshWarbandUI() end
end
local function live()
--@dev
    if A.testMode or P.IsSimulation() then return false end
--@enddev
    return W.enabled and W.ready and P.Scope()~=nil
end
local function api(name,...) return P.Read(C_LFGList and C_LFGList[name],...) end
local function available()
    return api("IsPremadeGroupFinderEnabled")==true
end
local function number(v) return not secret(v) and type(v)=="number" and v==v and v%1==0 and v>0 and v<1000000 end
function A.FinderChoices(refresh)
    if not refresh and F.choicesAt and GetTime()-F.choicesAt<15 then return F.choices end
    F.choicesAt=GetTime()
    local choices,seen={},{}
    if not available() then F.choices=choices; return choices end
    local categories=api("GetAvailableCategories")
    for i=1,40 do
        local category=field(categories,i); if not category then break end
        -- Forever's native PvP and Custom categories. Never queue dungeon/BG content.
        if category==118 or category==120 then
            local ci=api("GetLfgCategoryInfo",category)
            local activities=api("GetAvailableActivities",category)
            for j=1,100 do
                local id=field(activities,j); if not id then break end
                if number(id) and not seen[id] then
                    local info=api("GetActivityInfoTable",id)
                    local name=field(info,"fullName")
                    if field(info,"categoryID")==category and type(name)=="string" and #name>0 and #name<=160 then
                        seen[id]=true
                        choices[#choices+1]={id=id,category=category,name=A.CleanText(name,100),zoneName=name,
                            manual=field(ci,"autoChooseActivity")~=false}
                    end
                end
            end
        end
    end
    table.sort(choices,function(a,b) return a.name==b.name and a.id<b.id or a.name<b.name end)
    F.choices=choices; return choices
end
local function selection()
    for _,c in ipairs(A.FinderChoices()) do if c.id==A.db.finderActivity then return c end end
end
local function zoneChoice(mapID)
    local name=field(P.Read(C_Map and C_Map.GetMapInfo,mapID),"name")
    if type(name)~="string" or name=="" then return nil,"Rally zone unavailable; public posting paused." end
    local match
    -- Exact localized native zone name, only in Forever's Competitive category.
    -- Activity mapID is not assumed to be a UI map ID. No fuzzy zone guesses.
    for _,c in ipairs(A.FinderChoices()) do
        if c.category==118 and c.zoneName==name then
            if match then return nil,"Multiple Competitive entries for "..A.CleanText(name,80).."; public posting paused." end
            match=c
        end
    end
    if match then return match end
    return nil,"No Competitive listing for "..A.CleanText(name,80).."; public posting paused."
end
local function party()
    if not live() then return end
    local h,m=W.host,W.member
    if not h and not m then return end
    local info=A.WarbandNativeInfo()
    if not info or info.mode=="member" or info.count>=5 then return end
    if h and h.recruiting then
        local loc=h.mode=="follow" and A.CurrentLocation() or h.rally
        return {id=h.id,session=W.session,owner=h.owner,slot=1,mapID=loc and loc.mapID}
    end
    local r=m and W.records[m.id]
    if m and m.untilAt>GetTime() and P.Key(m.host)==P.Key(P.UnitName("player"))
        and r and r.session==m.session and r.expiresAt>GetServerTime() and r.recruiting then
        return {id=m.id,session=m.session,owner=m.owner,slot=m.slot,mapID=r.mapID}
    end
end
-- Refuse to touch unreadable entries. Observe a stable content fingerprint, not
-- duration or roster counts, and relinquish ownership after outside replacement.
local function fingerprint(entry)
    if type(entry)~="table" or secret(entry) then return end
    local ids=field(entry,"activityIDs"); local id=field(ids,1)
    if not number(id) or field(ids,2)~=nil then return end
    local parts={tostring(id)}
    for _,key in ipairs({"name","comment","voiceChat","voiceMode","autoAccept","privateGroup",
        "requiredItemLevel","requiredHonorLevel","requiredDungeonScore","requiredPvpRating",
        "playstyle","generalPlaystyle","isCrossFactionListing","newPlayerFriendly","questID"}) do
        local ok,v=pcall(function() return entry[key] end)
        if not ok or secret(v) then return end
        local t=type(v)
        if v~=nil and t~="string" and t~="number" and t~="boolean" then return end
        if t=="string" and #v>2048 then return end
        if t=="number" and (v~=v or math.abs(v)>1000000000) then return end
        local s=tostring(v); parts[#parts+1]=#s..":"..s
    end
    return table.concat(parts,"|"),id
end
local function active()
    local has=api("HasActiveEntryInfo")
    if has==false then return false end
    if has~=true then return nil end
    return true,api("GetActiveEntryInfo")
end
local function reconcile(created)
    local has,entry=active(); local fp,id=fingerprint(entry)
    local op=F.operation
    if op then
        if op.kind=="update" and created==true then
            F.operation=nil; F.owned=nil; status("Finder listing replaced; TotalWarcraft released control."); return
        end
        if op.kind=="remove" and has==false then F.operation=nil; F.owned=nil; status("Recruitment listing removed.")
        elseif op.kind~="remove" and has==true and fp and id==op.activity and field(entry,"comment")==""
            and field(entry,"autoAccept")==false and field(entry,"privateGroup")==false
            and field(entry,"isCrossFactionListing")==false then
            F.owned={fingerprint=fp,activity=id,warband=op.warband}; F.operation=nil
            status("Listed in "..(op.zoneName or "the rally zone").."; joins stay in TotalWarcraft.")
        end
    elseif F.owned and (created==true or has==false or (fp and fp~=F.owned.fingerprint)) then
        F.owned=nil
        status(has==false and "Recruitment listing closed." or "Existing listing changed; TotalWarcraft released control.")
    end
end
function A.FinderSync(retry)
    if not A.db then return end
    if not live() or A.db.finderEnabled~=true then
        F.search=nil; F.pending={}
        for key,item in pairs(W.queue) do
            local kind=item.packet:sub(3,3)
            if kind=="D" or kind=="F" then W.queue[key]=nil end
        end
    end
    local p=party()
    if A.db.finderEnabled~=true then p=nil end
    -- Discovery alone is not consent to recruit. An idle addon does not inspect
    -- native listings, enumerate activities, or react to combat/roster changes.
    -- Finish cleanup only for a listing this session actually owns/created.
    if not p and not F.owned and not F.operation then return end
    reconcile()
    if F.operation then return end
    local chosen,zoneReason
    if p then chosen,zoneReason=zoneChoice(p.mapID) end
    local has,entry=active(); local fp=fingerprint(entry)
    if has==nil or (has and not fp) then status("Recruitment state unavailable; known contacts still work."); return end
    if F.owned and has and fp~=F.owned.fingerprint then F.owned=nil end
    if has and not F.owned then status("Your existing Finder listing is left under your control."); return end
    local shouldRemove=F.owned and (not p or not chosen or chosen.manual or F.owned.warband~=p.id)
    local key=shouldRemove and ("remove:"..F.owned.fingerprint)
        or p and chosen and (p.id..":"..chosen.id..":"..tostring(chosen.manual)) or "idle"
    if not retry and F.attemptKey==key then return end
    if retry and F.lastAttempt and GetTime()-F.lastAttempt<5 then status("Wait a few seconds before retrying recruitment."); return end
    if P.Read(InCombatLockdown)~=false then status("Recruitment waits until combat ends."); return end
    if shouldRemove then
        F.attemptKey=key; F.lastAttempt=GetTime()
        F.operation={kind="remove",at=GetTime()}
        local ok=call("RemoveListing")
        if not ok then F.operation=nil; status("Listing removal blocked; retry from Recruitment.")
        else reconcile(); if F.operation then status("Waiting for listing removal confirmation.") end end
        return
    end
    if not p then
        status(A.db.finderEnabled and "Recruitment ready when you lead a warband party with space." or "Public recruitment off; known contacts still work.")
        return
    end
    if not chosen then status(zoneReason or "Rally zone unavailable; public posting paused."); return end
    if chosen.manual then status("This activity needs manual Finder text; background posting unavailable."); return end
    if F.owned and F.owned.activity==chosen.id then return end
    if F.lastAttempt and GetTime()-F.lastAttempt<5 then return end
    F.attemptKey=key; F.lastAttempt=GetTime()
    if not available() then status("Finder unavailable; use known contacts in TotalWarcraft."); return end
    -- Clear through the supported API only. Never set/paste protected edit boxes.
    if not call("ClearCreationTextFields") then status("Listing text unavailable; background posting blocked."); return end
    local kind=F.owned and "update" or "create"
    F.operation={kind=kind,activity=chosen.id,zoneName=chosen.name,warband=p.id,at=GetTime()}
    local ok,value=call(kind=="update" and "UpdateListing" or "CreateListing",{
        activityIDs={chosen.id},isAutoAccept=false,isCrossFactionListing=false,isPrivateGroup=false,
        newPlayerFriendly=false,generalPlaystyle=0,voiceMode=0})
    if not ok or value~=true then F.operation=nil; status("Posting blocked by WoW; retry here or use known contacts.")
    else reconcile(); if F.operation then status("Waiting for recruitment listing confirmation.") end end
end
function A.SetFinderEnabled(enabled)
    A.db.finderEnabled=enabled==true
    if not A.db.finderEnabled then F.search=nil; F.pending={} end
    F.attemptKey=nil
    A.FinderSync(true)
    if A.RefreshFinderUI then A.RefreshFinderUI() end
end
function A.SelectFinderActivity(id)
    if F.operation then return false,"Wait for the current listing operation." end
    for _,c in ipairs(A.FinderChoices()) do if c.id==id then
        A.db.finderActivity=id
        return true,"Search activity selected. Public listings follow your warband's rally zone."
    end end
    return false,"That activity is not available on this client."
end
function A.FinderSearch()
    -- Called only by the explicit Search button or /tw find. Search results
    -- subscribe to listings; neither this path nor a result handler joins them.
    if not W.enabled then A.SetWarbandsEnabled(true) end
    if not live() or A.db.finderEnabled~=true then return false,"Enable discovery and public recruitment first." end
    local c=selection()
    if not c then local loc=A.CurrentLocation(); c=zoneChoice(loc and loc.mapID) end
    if not c then return false,"Choose a suitable activity in Recruitment first." end
    if F.search or (F.lastSearch and GetTime()-F.lastSearch<30) then return false,"Recruitment searches are limited to once every 30 seconds." end
    if P.Read(InCombatLockdown)~=false then return false,"Search after combat." end
    F.search={activity=c.id,untilAt=GetTime()+12}; F.lastSearch=GetTime()
    local ok=call("Search",c.category,0,0,nil,false,nil,{c.id})
    if not ok then F.search=nil; status("Recruitment search blocked; retry here when available."); return false,F.status end
    status("Searching for TotalWarcraft party leaders."); return true,F.status
end
local function results()
    local search=F.search; F.search=nil
    if not search or search.untilAt<=GetTime() or not live() or A.db.finderEnabled~=true then return end
    local _,ids=P.Read(C_LFGList and C_LFGList.GetSearchResults)
    local probes=0
    for i=1,50 do
        local id=field(ids,i); if not id then break end
        if number(id) then
            local r=api("GetSearchResultInfo",id); local name=field(r,"leaderName")
            local key=P.Name(name) and P.Key(name)
            local count=field(r,"numMembers")
            if key and key~=P.Key(P.UnitName("player")) and not W.watches[key]
                and field(r,"isDelisted")==false and field(r,"hasSelf")==false
                and field(field(r,"activityIDs"),1)==search.activity
                and type(count)=="number" and count>=1 and count<5
                and (not F.probed[key] or GetTime()-F.probed[key]>=60) then
                local nonce=P.UUID()
                if A.QueueWarbandWhisper(P.Request("D",nil,nil,nonce),name,"FINDER:"..key) then
                    F.pending[key]={nonce=nonce,untilAt=GetTime()+25}; F.probed[key]=GetTime(); probes=probes+1
                end
                if probes>=8 then break end
            end
        end
    end
    status(probes>0 and "Checking fresh TotalWarcraft affiliations; open the warband board." or "No new eligible leaders found; known contacts still work.")
end
function A.OnFinderDiscovery(f,sender,key)
    if not live() or A.db.finderEnabled~=true then return end
    if f[2]=="D" then
        local p=party()
        if not p or not F.owned or F.operation then return end
        local has,entry=active(); local fp=fingerprint(entry)
        if has~=true or fp~=F.owned.fingerprint or F.owned.warband~=p.id then return end
        local rate=W.rates[key]
        if not rate or (rate.finderAt and GetTime()-rate.finderAt<30) then return end
        rate.finderAt=GetTime()
        A.QueueWarbandWhisper(P.Request("F",p.id,p.session,f[5],{p.owner,p.slot}),sender,"FINDER_REPLY:"..key)
    elseif f[2]=="F" then
        local pending=F.pending[key]
        if not pending or pending.untilAt<=GetTime() or pending.nonce~=f[5] then return end
        F.pending[key]=nil
        local ownerKey=P.Key(f[10])
        if not ownerKey or ownerKey==P.Key(P.UnitName("player")) or W.watches[ownerKey] then return end
        local ok=A.WatchWarband(f[10],f[3],f[4])
        if ok then W.watches[ownerKey].finderUntil=GetTime()+120 end
    end
end
function A.FinderTick()
    local now=GetTime()
    if F.tickAt and now-F.tickAt<1 then return end
    F.tickAt=now
    for key,v in pairs(F.pending) do if v.untilAt<=now then F.pending[key]=nil end end
    for key,at in pairs(F.probed) do if now-at>=60 then F.probed[key]=nil end end
    for key,w in pairs(W.watches) do
        if w.finderUntil and w.finderUntil<=now and not (W.member and W.member.ownerKey==key) and not (W.join and W.join.ownerKey==key) then A.UnwatchWarband(w.name) end
    end
    if F.search and F.search.untilAt<=now then F.search=nil; status("Search timed out; retry from Recruitment.") end
    if F.operation and now-F.operation.at>=10 then
        F.operation=nil; status("Listing change unconfirmed; retry from Recruitment.")
    end
    A.FinderSync()
end
function A.InitFinder()
    A.db.finderEnabled=A.db.finderEnabled~=false
    if not number(A.db.finderActivity) then A.db.finderActivity=nil end
    F.events=CreateFrame("Frame")
    for _,e in ipairs({"LFG_LIST_SEARCH_RESULTS_RECEIVED","LFG_LIST_SEARCH_FAILED","LFG_LIST_ACTIVE_ENTRY_UPDATE"}) do pcall(F.events.RegisterEvent,F.events,e) end
    F.events:SetScript("OnEvent",function(_,e,created)
        if e=="LFG_LIST_SEARCH_RESULTS_RECEIVED" then results()
        elseif e=="LFG_LIST_SEARCH_FAILED" and F.search then F.search=nil; status("Recruitment search failed; retry here.")
        elseif e=="LFG_LIST_ACTIVE_ENTRY_UPDATE" and (F.owned or F.operation) then reconcile(created) end
    end)
end
