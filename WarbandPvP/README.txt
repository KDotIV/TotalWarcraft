TOTALWARCRAFT - 0.7.8
World of Warcraft: Forever 1.60.1 (Interface 16001)

Formerly Warband-PvP. /tw is primary; /totalwarcraft and /wb also work.
The internal WarbandPvP folder preserves existing settings and keybindings.
Do not install a second renamed copy. See CHANGELOG.txt for release notes.

Quickly form parties to seek out world PvP or rally your faction to retaliate
against enemy attacks in WoW Forever.

Open /tw for the command board, Create Warband and the paginated Help guide.
Manual reporting is available through a keybind or /tw report.
One TotalWarcraft dialog is visible at a time. Back restores the previous view. Drag the
header to move a window. Show on map closes TotalWarcraft dialogs and opens the world map.

FIELD REPORTS
Automatic reports are on by default; toggle on /tw or with /tw auto on/off.
After combat ends, readable incoming damage must match a visible, attackable,
PvP-flagged opposing player observed during that fight. Incoming damage is enough;
outgoing damage is not required. The report uses the captured fight location.
NPCs, same-faction targets, instances and sanctuary/FFA rules do not qualify.
Unreadable required checks skip reporting. A reload during combat waits for
combat to end before reporting automatically. Duel events and outgoing requests
suppress reports through the duel and a short settling period. Manual reporting
also respects local duel holds. No blanket city exclusion hides real city raids.
Missing/ambiguous meter data skips the automatic report. This local attribution
does not authenticate another client's claims, prove a kill or establish team size.

An automatic attempt happens at most once per combat. Successful submissions
share a two-minute cooldown with /tw report and the report keybind. Failed
automatic sends do not retry until a later combat. Matching users receive a
five-minute map report through TotalWarcraftReportComms. No guild or shared
party is required.
"Combatants" is the partial observed flagged-player count, not a confirmed fight
size. Unknown counts, range gaps and absent scouting fields are hidden.

CONFLICT PINS
Nearby reports share one crossed-swords pin at the newest report's position.
Each unique recent reporter contributes once. More reports gradually increase
its size from 22 to 32 pixels and deepen its red color; two fresh reporters can
add a slow red pulse; heavy activity uses red crossed weapons and a raid skull.
Heat fades over a two-minute observation window; the report itself lasts five.
Proximity is within 3.5% of the same map's normalized coordinates, not a fixed
yard radius. It does not establish a common layer. No player counts are summed.
The tooltip adds only Growing conflict or Heavy activity when warranted.
Older nearby reports cannot cover a fresh cluster with a separate cold pin.
Click opens the newest report; all reports remain in Read field reports.

ENEMY SCOUTING (EXPERIMENTAL)
Target a visible opposing-faction player before reporting. A cooperating TotalWarcraft
warband member may reply with their warband's name, ID, reported membership size,
party count and orders. Open Enemy scouting from the field report for details.
Your same-faction report recipients can see the same snapshot. It expires
within 90 seconds of the underlying update and does not track enemy movement.
Membership is self-reported, not a count of nearby enemies or confirmed fighters.
No usable reply means unknown. Cross-faction addon delivery has not yet been
verified live and may be blocked by WoW; scouting never bypasses that restriction.
Starting or joining a warband makes your affiliation and reported size scoutable
by visible enemy TotalWarcraft scouts. This disclosure also appears beside Start / Join.

WARBANDS
/tw show opens the rally board. Enable discovery, then start or join a
warband. One UUID coordinates up to four normal parties. Raids cannot become
warband groups. This is a product constraint, not a claim that outdoor raids
cannot share a layer. The assigned party host attempts an invitation after
your accepted join request; accept WoW's native invitation to join the party.
Blocked invitations can be retried inside TotalWarcraft. No auto-accept or raids.
Use Rally here, Follow me, recruiting and forming/roaming/rallying controls.
Gold axe/sword/banner pins mark rally locations; numbered dots show group hosts.
Counts and positions are organizer/member reports, not authoritative game state.
The game controls transfers. TotalWarcraft cannot select or prove a common layer.
Discovery reaches guild/party users, named subscribers and eligible Finder
leaders where the native API permits it; it is not a complete faction directory.
Watch organizers lets you add/remove up to eight full-name subscriptions.
Discovery and subscriptions reset on login/reload. Listings expire after 90s.

RECRUITMENT
/tw finder opens recruitment controls inside the same window navigator.
Recruiting party leaders post under the rally zone's native Competitive entry.
A missing or ambiguous zone match pauses public posting. Fixed rallies stay in
their zone; Follow me tracks the organizer's current zone. Each party uses that
same rally destination. Selecting a search activity never redirects a listing.
Start / Join stays on the warband board. Public recruitment can be turned off here. Native listings
are visible to ordinary Finder users, too; they are not private addon messages.
Each participating party leader manages only their own addon-created listing.
Existing or externally changed listings are left alone. No native Finder window
is opened; protected text is never filled or pasted. Activities requiring manual
listing text support discovery only. A rejected API call shows a retry path here.
/tw find or Search warbands searches on demand (30s minimum interval). Opening
the board or enabling discovery does not search. Results never join for you.
Replies must match fresh, scoped requests before
the organizer's actual warband snapshots are requested. No public UUID text tag.
Finder-origin subscriptions expire after two minutes unless you join; subscribe
by name to keep following an organizer. All results remain self-reported.
Rally to report starts your own warband at that report's last reported location.
It does not enlist the reporter or prove that they are still present.

TotalWarcraft sends party invitations only for an active, matching warband assignment
and a fresh confirmation from the recruit. Expired or previous-warband requests
cannot invite. Native acceptance stays with the player. TotalWarcraft never auto-accepts,
leaves, kicks or converts your native party, or changes another addon's settings.
LayerSwap may pause hosting while TotalWarcraft's native listing is active, by its own
policy. Turn public recruitment off to use known contacts without a listing.
/tw export distinguishes TotalWarcraft invitation attempts from observed native invite
calls outside TotalWarcraft; the latter cannot identify which addon or UI initiated them.

GROUP LOCATIONS
Enable from /tw > Group locations, or /tw presence on. Sharing is session-only
and restricted to your outdoor native party/raid. /tw presence off stops it.
Fresh peers appear as jade map markers and in the group-locations panel.
Positions expire after 30s. Presence is not proof of combat or a shared layer.

REPORT CHANNEL
Login/reload leaves old TotalWarcraft-prefixed channel memberships and joins
TotalWarcraftReportComms. Other channel memberships are retained. Channel numbers
are assigned by WoW and may differ between players. No ordinary chat is sent.
Reports reach matching faction, ruleset and region users through this channel,
including unguilded players. New reports are sent once; legacy guild reports
remain readable and duplicate report IDs never create extra markers or heat.
/tw status shows connectivity; /tw export includes connection and report events.
Automatic reconnect attempts are bounded and stop once connected or timed out.

SESSION JOURNAL
/tw export opens a copyable local log of this UI session, including TotalWarcraft actions,
combat/report decisions, transport results, window/button actions and group/zone/transfer
events. It includes blocked/forbidden action details and readable Lua errors delivered to
Blizzard's error frame, plus client and loaded-addon versions. Ctrl+A, Ctrl+C to copy.
The journal keeps 1500 recent activity entries and a separate 64-entry issue buffer;
omitted rows are counted. No chat event capture, automatic uploads or external backend.
Names, in-game locations and addon error text can appear. Review before sharing.
Other addons' error handlers remain in control; errors they intercept may be unavailable.
Your own reports stay on the map without a popup. Clicking another player's popup
in combat queues its details until combat ends; expired reports are not opened.
Export before /reload or logout: the release journal resets each session.

SHORTCUTS
/tw                     Command board
/tw report              Report PvP at your current location
/tw show                Warband controls and listings
/tw finder              Recruitment settings and retry controls
/tw find                Search available recruitment listings
/tw start NAME   Start a normal-party warband
/tw join UUID    Request logical membership
/tw watch NAME   Subscribe to a full character name
/tw unwatch NAME Remove that subscription
/tw leave        Leave/end a warband; native group unchanged
/tw presence on/off      Toggle native group location sharing
/tw export              Copy session journal
/tw clear               Clear only local field reports
/tw auto on/off         Toggle automatic reporting
/tw help                Guide, commands, map legend and support
/tw status              Support and transport status

Keybindings for the command board, report, warbands and export are available in
/tw > Keybindings and the game's Key Bindings menu. No keys are assigned by default.
Optional OpenMap integration is supported; OpenMap is not required or bundled.
Install the WarbandPvP folder directly inside Interface/AddOns. Restart the client
after replacing files. Only one build can be installed at a time.

BUG REPORTS
https://github.com/KDotIV/TotalWarcraft/issues
Include addon/client versions, reproduction steps and /tw export before reload.
The Help > Support page has a copyable link. CurseForge comments also work.

All Rights Reserved. See LICENSE.txt. No reference artwork or third-party fonts
are bundled. The military frame is original generated artwork.
