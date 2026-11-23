local _,A=...
local pages={
    {"Getting started", [[Form normal parties to seek out world PvP or answer an attack.

Create Warband opens the rally board. Enable discovery,
start a warband or join a listing, then accept your party invite.
Travel to the rally and coordinate with your assigned host.

Eligible outdoor PvP combat shares a report with your faction.
Read field reports to view locations or rally a warband there.
Set a report key in Keybindings for manual observations.

Only one TotalWarcraft window opens at a time. Back restores the
previous window; drag its header to move it. Show on map
closes the dialog and selects the report or rally's zone.

Use the topic buttons above or Previous / Next below.
/tw opens the board. /wb remains an alias. /tw help: guide.]]},
    {"Reports & safeguards", [[Every five seconds in combat, check for new damage to/from
an observed, attackable, PvP-flagged opposing player.
NPC and pet damage alone do not qualify.

Duels, sanctuary/FFA rules and instances suppress automatic
reports. Loading during combat waits for a fresh fight.
Unavailable or restricted checks skip automatic reporting.
Either damage direction is enough. Combat ending cancels
the timer; no delayed automatic report follows the fight.

One automatic attempt per combat; a shared two-minute
cooldown follows a successful report. Shared-channel users get
a five-minute marker, including unguilded players. Toggle on /tw.
Manual report: your keybind or /tw report; duel holds still apply.

"Combatants" counts readable flagged players observed within
100 yards. It is partial, not a verified fight size. Unavailable
counts and enemy affiliations are omitted from the tooltip.]]},
    {"Reading the map", [[Crimson crossed swords: a reported PvP location.
Recent nearby reports strengthen the color and grow the pin
slightly. Multiple reporters add a slow pulsing red glow.
Heavy activity adds red crossed weapons and a small skull.

Reports must be in the same map area and recent to add heat.
Each reporter counts once; overlapping player counts are
never added together. Heat fades as reports age or expire.
The strongest marker suggests activity, not confirmed teams,
kills or a 10-versus-10 battle. Hover for a short activity label.

Gold axe / sword: a warband rally or organizer location.
Numbered gold markers: your warband's party hosts.
Jade crosses: opted-in native group members.

Click a report for details, its map location or Rally to report.
OpenMap is optional. Positions do not confirm a shared layer.]]},
    {"Creating & joining warbands", [[Enable discovery on the rally board, enter a name and Start.
A warband ID coordinates up to four normal five-player parties.
Raid groups cannot join as warband parties.

Join requests TotalWarcraft membership. Your assigned host attempts
a native invite; accept WoW's invitation to join the party.
Blocked invites can be retried from the board. A party leader
can bring their existing party as another warband group.

Rally here fixes your rally point; Follow me tracks the organizer.
Change forming / roaming / rallying orders and recruitment.
Rally to report starts your own warband at that report's position.
It does not automatically enlist the reporter.

Start / Join makes affiliation and reported size enemy-scoutable.
Leave ends TotalWarcraft membership without removing your native party.
The game decides transfers; TotalWarcraft cannot force or prove a layer.]]},
    {"Discovery, recruitment & locations", [[Discovery reaches guild, party and named subscribers.
Watch organizers subscribes to a full character name.
Discovery and watches reset on login / reload; listings expire
after 90 seconds without a fresh update.

Recruiting party leaders post under the rally's Competitive
zone. No exact native match means no public posting.
/tw finder selects a search activity and controls recruitment.
Search lists warbands; click Join to request membership.
Public listings are visible to ordinary Finder users too.
/tw find searches on demand, at most once per 30 seconds.

Group locations shares your position and readable flags with
your outdoor native party / raid. Both sides must enable it.
Sharing is session-only; locations expire after 30 seconds.
Group presence is not proof of PvP participation or layering.]]},
    {"Enemy scouting & privacy", [[Report while targeting a visible opposing TotalWarcraft player.
A cooperating warband member may return their affiliation,
reported membership size, party count and current orders.
Open Enemy warband from the report when information exists.

Only your same-faction report recipients receive the
relayed information. It expires within 90 seconds of its update.
This describes membership, not nearby enemies or live movement.
No reply leaves the field hidden. It never means "no warband".
Cross-faction delivery may be blocked by the game.

Starting or joining makes your own affiliation scoutable by
visible enemy TotalWarcraft scouts. No external backend is involved.

Export keeps bounded combat/UI/network/error logs and addon versions.
Names, locations and error text may appear. Review before sharing.
Export before reload / logout; the journal resets each session.]]},
    {"Commands & keybindings", [[/tw                     Open / close the command board
/tw show                Warband board (start or join)
/tw report              Report your current location
/tw auto on / off       Enable / disable automatic reports
/tw finder              Recruitment settings and retries
/tw find                Search recruitment listings
/tw presence on / off   Enable / disable group location sharing
/tw presence status     Print sharing status
/tw export              Copy the current session journal
/tw clear               Clear local field reports only
/tw help                Open this guide
/tw status              Open support and transport status

Keybindings: command board, manual report, warband board,
session export. Set them on /tw > Keybindings or in WoW's
Key Bindings menu. No keys are assigned by default.
Warband-specific commands are on the next page.]]},
    {"Warband commands", [[/tw on / off       Enable / disable discovery
/tw start NAME     Start a warband with this title
/tw join UUID      Request membership in a listed warband
/tw leave          Leave / end your warband (/tw stop also works)
/tw watch NAME     Subscribe to an organizer's full name
/tw unwatch NAME   Remove that subscription
/tw invite NAME    Retry an authorized native party invite
/tw rally          Set your current position as the rally
/tw follow         Follow the organizer's position
/tw recruit on     Open recruitment (/tw recruit off closes it)
/tw state forming  Set orders: forming, roaming or rallying

Names may contain spaces; UUID is the listing's warband ID.
Rally, follow, recruitment and orders require the coordinator.
Updates are throttled and can take up to 15 seconds.
All of these controls are also on the warband board.]]},
    {"Support & session status", [[Report bugs using the issue link below, or leave a comment on
the TotalWarcraft CurseForge project.

Include your addon version, Forever client version, the steps
that caused the problem and what you expected to happen.
If relevant, include a screenshot and the /tw export journal.
Copy the journal before reloading; review names and locations.

Copy issue link with Ctrl+A, Ctrl+C:]]},
}

function A.ShowHelp(page)
    if not A.helpPanel then
        local f=A.Surface("WarbandPvPHelp",580,720,"HELP"); A.helpPanel=f
        for i,item in ipairs({{"Reports",2},{"Warbands",4},{"Commands",7},{"Support",9}}) do
            local target=item[2]
            A.Button(f,item[1],30+(i-1)*132,-174,124,function() A.ShowHelp(target) end)
        end
        f.title=A.Label(f,30,-220,520,"","GameFontNormalLarge")
        f.body=A.Label(f,30,-258,520,""); f.body:SetSpacing(4)
        f.link=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
        f.link:SetSize(510,26); f.link:SetPoint("TOPLEFT",35,-432); f.link:SetAutoFocus(false)
        f.link:SetScript("OnEditFocusGained",function(self) self:HighlightText() end)
        f.link:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        f.status=A.Label(f,30,-490,520,""); f.status:SetSpacing(4)
        A.Button(f,"Previous",30,-620,110,function() A.ShowHelp(math.max(1,f.page-1)) end)
        f.counter=A.Label(f,260,-627,90,"")
        A.Button(f,"Next",440,-620,110,function() A.ShowHelp(math.min(#pages,f.page+1)) end)
    end
    local f=A.helpPanel
    f.page=type(page)=="number" and math.max(1,math.min(#pages,math.floor(page))) or 1
    f.title:SetText(pages[f.page][1]); f.body:SetText(pages[f.page][2])
    f.counter:SetText(f.page.." / "..#pages)
    local support=f.page==9
    f.link:SetShown(support); f.status:SetShown(support)
    f.link:SetText("https://github.com/KDotIV/TotalWarcraft/issues")
    f.status:SetText("Version: "..A.release.."\nScope: "..(A.scopeRuleset or "unavailable").." / region "..tostring(A.scopeRegion)
        .."\nReport channel: "..A.ReportChannelStatus().."\nWarband messaging: "..tostring(A.warbands.ready)
        .."\nAuto reports: "..(A.db.autoReports and "on" or "off"))
    f:Show()
end
