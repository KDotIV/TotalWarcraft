WARBAND-PVP — 0.7.1-alpha
World of Warcraft: Forever 1.60.1 (Interface 16001)

Quickly form parties to seek out world PvP or rally your faction to retaliate
against enemy attacks in WoW Forever.

Open /wb for the command board. All player features have UI controls.
One Warband-PvP dialog is visible at a time. Back restores the previous view. Drag the
header to move a window. Show on map closes Warband-PvP dialogs and opens the world map.

FIELD REPORTS
/wb report sends an observer report to Warband-PvP users in your guild, at your current
location. Reports expire after five minutes and have a two-minute cooldown.
Flagged players, group presence and warband size are not confirmed PvP fighters.
Fight size remains unknown. Crimson crossed swords mark reports on the map.

ENEMY SCOUTING (EXPERIMENTAL)
Target a visible opposing-faction player before reporting. A cooperating WBP
warband member may reply with their warband's name, ID, reported membership size,
party count and orders. Open Enemy scouting from the field report for details.
Your same-faction guild report recipients can see the same snapshot. It expires
within 90 seconds of the underlying update and does not track enemy movement.
Membership is self-reported, not a count of nearby enemies or confirmed fighters.
No usable reply means unknown. Cross-faction addon delivery has not yet been
verified live and may be blocked by WoW; scouting never bypasses that restriction.
Starting or joining a warband makes your affiliation and reported size scoutable
by visible enemy WBP scouts. This disclosure also appears beside Start / Join.

WARBANDS
/wb show opens the rally board. Enable discovery, then start or join a
warband. One UUID coordinates up to four normal parties. Raids cannot become
warband groups. This is a product constraint, not a claim that outdoor raids
cannot share a layer. The assigned party host attempts an invitation after
your accepted join request; accept WoW's native invitation to join the party.
Blocked invitations can be retried inside Warband-PvP. No auto-accept or raids.
Use Rally here, Follow me, recruiting and forming/roaming/rallying controls.
Gold axe/sword/banner pins mark rally locations; numbered dots show group hosts.
Counts and positions are organizer/member reports, not authoritative game state.
The game controls transfers. Warband-PvP cannot select or prove a common layer.
Discovery reaches guild/party users, named subscribers and eligible Finder
leaders where the native API permits it; it is not a complete faction directory.
Watch organizers lets you add/remove up to eight full-name subscriptions.
Discovery and subscriptions reset on login/reload. Listings expire after 90s.

RECRUITMENT
/wb finder opens recruitment controls inside the same window navigator.
Choose a suitable available PvP / Custom activity once, then Start / Join stays
on the warband board. Public recruitment can be turned off here. Native listings
are visible to ordinary Finder users, too; they are not private addon messages.
Each participating party leader manages only their own addon-created listing.
Existing or externally changed listings are left alone. No native Finder window
is opened; protected text is never filled or pasted. Activities requiring manual
listing text support discovery only. A rejected API call shows a retry path here.
/wb find searches on demand (30s minimum interval); opening the board also tries
a search when discovery is on. Replies must match fresh, scoped requests before
the organizer's actual warband snapshots are requested. No public UUID text tag.
Finder-origin subscriptions expire after two minutes unless you join; subscribe
by name to keep following an organizer. All results remain self-reported.
Rally to report starts your own warband at that report's last reported location.
It does not enlist the reporter or prove that they are still present.

GROUP LOCATIONS
Enable from /wb > Group locations, or /wb presence on. Sharing is session-only
and restricted to your outdoor native party/raid. /wb presence off stops it.
Fresh peers appear as jade map markers and in the group-locations panel.
Positions expire after 30s. Presence is not proof of combat or a shared layer.

SESSION JOURNAL
/wb export opens a copyable local log of this UI session, including Warband-PvP actions,
transport results and group/zone/transfer events. Ctrl+A, Ctrl+C to copy.
The log is bounded; omitted rows are counted. No chat contents, automatic uploads
or external backend. Names and in-game locations can appear. Review before sharing.
Export before /reload or logout: the release journal resets each session.

SHORTCUTS
/wb                     Command board
/wb report              Report PvP at your current location
/wb show                Warband controls and listings
/wb finder              Recruitment settings and retry controls
/wb find                Search available recruitment listings
/wb start NAME   Start a normal-party warband
/wb join UUID    Request logical membership
/wb watch NAME   Subscribe to a full character name
/wb unwatch NAME Remove that subscription
/wb leave        Leave/end a warband; native group unchanged
/wb presence on/off      Toggle native group location sharing
/wb export              Copy session journal
/wb clear               Clear only local field reports
/wb status              Field guide and transport status

Keybindings for the command board, report, warbands and export are available in
/wb > Keybindings and the game's Key Bindings menu. No keys are assigned by default.
Optional OpenMap integration is supported; OpenMap is not required or bundled.
Install the WarbandPvP folder directly inside Interface/AddOns. Restart the client
after replacing files. Only one build can be installed at a time.

All Rights Reserved. See LICENSE.txt. No reference artwork or third-party fonts
are bundled. The military frame is original generated artwork.
