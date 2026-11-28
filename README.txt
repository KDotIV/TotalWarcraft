TOTALWARCRAFT 0.7.12
World of Warcraft: Forever only (Interface 16001)

Quickly form parties to seek out world PvP or rally your faction to retaliate
against enemy attacks in WoW Forever.

WarbandPvP/ is the addon source. Open /tw for the command board and /tw show
for warbands. One managed dialog is visible at a time, with Back navigation and
a draggable military frame. No external backend or third-party library is needed.

FEATURES
- During your combat, automatic reports check every five seconds for recent
  damage to a visible, hostile, PvP-flagged player or NPC still in combat.
  Flagged faction NPCs intentionally qualify; ordinary unflagged mobs, pets,
  target selection and damage to self alone do not. No native meter reads in combat.
  Strict post-combat player-damage verification remains a fallback, including
  death/short fights. Both paths share exclusions, cooldown and a single attempt.
  A live 0.7.11 log confirms the five-second activity check, but startup channel
  cleanup blocked delivery. The 0.7.12 connection fix still needs live acceptance.
  Manual reports remain available via /tw report or a keybind; shared cooldown.
- Compact known-only tooltips and fading nearby-report clusters: scaled swords,
  pulsing red halo and native red weapons/raid skull for heavy reported activity.
- Create Warband and nine-page Help on /tw, with commands and bug-report link.
- Enemy scouting: a visible opposing TotalWarcraft member may reply with a bounded snapshot
  of affiliation and reported warband size. Same-faction report recipients
  can open it from report details. Joining a warband discloses this behavior.
- /tw show: one UUID coordinates up to four normal five-player parties, never raids.
- /tw finder: optional public recruitment, available activities, search and retry
  inside TotalWarcraft. Protected/native restrictions are respected; existing user
  listings are left alone. Native Finder UI is not opened by the addon.
- /tw find: throttled recruitment search, followed by scoped, expiring addon
  handshakes. Public listings are not a private transport or a complete directory.
- Finder stays idle until you recruit or explicitly search. Search never joins.
  Listings follow an exact native Competitive match for the warband rally zone.
- Accepted Join requests trigger a bounded native invite attempt by the assigned
  captain. Recruits still accept WoW's invitation. No auto-accept or group removal.
- Rally to report starts a warband at the last reported location, without assuming
  that the reporter is still present or automatically including them.
- /tw presence on/off: opt-in location sharing within the outdoor native group.
- /tw export: bounded combat, report, UI, network and error journal with addon versions.
- Own reports stay on the map without a popup; combat clicks defer report details.
- UI controls, slash commands and optional keybindings cover player features.

EVIDENCE LIMITS
Fight size and exact layers remain unconfirmed. Live reports observe damage to
eligible flagged units without identifying the attacker. A flagged enemy fighting
an ordinary mob can qualify. The fallback verifies player-attributed damage after
combat. Manual and received reports remain claims. Detection is limited to units
exposed by the client; the report snapshot's 100-yard cutoff is not a scan radius.
GUID components
are not cross-client layer keys. A UUID, map position, listing, native group join
or transfer event does not establish arrival at the original fight. Parties-only
is a product choice, not proof that outdoor raids cannot share a layer.

Twenty offline suites cover isolated Lua clients and the physically
stripped release ZIP. The two-client 0.6.1 live simulation established messaging,
member updates and teardown; it did not validate native grouping or layer arrival.
Finder calls and the revised 0.7 UI/invitations still require live acceptance.
Enemy scouting is implemented and mock-tested, including ordinary members, reply
loss, sender/nonce validation, bounded hostile traffic and expiration. Cross-faction
addon delivery still needs live verification; no reply means unknown, never an
inferred absence of a warband. See docs/ENEMY_SCOUTING_0.7.1.txt.
Public packages use the production build flavor and CurseForge Release stage.
Local 0.7.12 fixes channel startup and filters routine spell feedback from the
journal. It is not published. See docs/REPORT_CHANNEL_FIX_0.7.12.txt for evidence
and live acceptance checks.
CurseForge accepted 0.7.11 as Release file 9811578 after all 20 suites passed in
GitHub CI. All 30 uploaded files match the tested local build. Approval/client
indexing remains unconfirmed. It adds five-second flagged-player/NPC activity
reports and fixes delayed sessions and binding headers.
Receipt: docs/CURSEFORGE_SUBMISSION_0.7.11.txt.
https://www.curseforge.com/wow/addons/total-warcraft/files/9811578
Research and live checks: docs/FLAGGED_ACTIVITY_AND_TRACKING_0.7.11.txt.
Earlier log review and session fix: docs/AUTO_REPORT_SESSION_FIX_0.7.11.txt.
Version 0.7.10 restores strict post-combat verification after the 0.7.9 live test
recorded 14 checks with no readable attribution during a 70-second PvP fight.
It retains captures through death and reports at the captured fight location.
CurseForge accepted 0.7.10 as Release file 9777566 after all 20 suites passed in
GitHub CI. All 30 uploaded files match the local build. Public approval/indexing
remains unconfirmed; the file page returned HTTP 403 during verification.
Receipt: docs/CURSEFORGE_SUBMISSION_0.7.10.txt.
https://www.curseforge.com/wow/addons/total-warcraft/files/9777566
Live-test details: docs/LIVE_ACTIVITY_REPORTING.txt.
Version 0.7.9 introduced five-second in-combat checks, which failed that live test.
All 20 suites passed locally and in GitHub CI. CurseForge accepted Release file
9775730; all 30 uploaded files match the tested local package. The public file
page returned HTTP 403 during verification, so moderation/indexing remains
unconfirmed. Receipt: docs/CURSEFORGE_SUBMISSION_0.7.9.txt.
https://www.curseforge.com/wow/addons/total-warcraft/files/9775730
Version 0.7.8 passed all 20 suites locally and in GitHub CI and was uploaded to
CurseForge as Release file 9756275. The public file page returned 404 during
verification; approval/indexing state is not yet confirmed.
All 30 uploaded files match the tested and installed 0.7.8 production build.
Receipt: docs/CURSEFORGE_SUBMISSION_0.7.8.txt.
https://www.curseforge.com/wow/addons/total-warcraft/files/9756275
See docs/UI_SESSION_AUDIT_0.7.8.txt for the notification and journal audit and
the remaining live compatibility checks with other addons.
See docs/REFINEMENTS_0.7.3.txt for current live acceptance steps and
docs/DAMAGE_VERIFICATION_DESIGN.txt for the incoming-damage checks and their evidence limits.

The separate dev build now includes /tw damage start <label>, status, stop and
export for local post-combat meter acceptance tests. Normal reports pause while
it captures one fight; it never broadcasts candidate evidence. See
WarbandPvP/DAMAGE_TESTING.txt. These tools are physically excluded from Release.

The Release automatically joins TotalWarcraftReportComms on login/reload after
leaving existing TotalWarcraft-prefixed channel memberships. Each client uses
its actual local channel index. New reports use CHANNEL once; legacy guild
reports remain readable and duplicate IDs are ignored across both routes.
The live 0.7.6 transport captures confirmed automatic two-way delivery involving
unguilded clients across Kalimdor and Eastern Kingdoms on Forever build 71037.
See docs/CHANNEL_LIVE_RESULTS_2026-11-22.txt. No external backend is required.
Temporary channel probes and commands have been retired.

BUILD / INSTALL
  python -m pip install -r requirements-dev.txt
  python tools/run_tests.py
  .venv\Scripts\python.exe tools/build_addon.py --flavor both
  powershell -File tools/Install-Addon.ps1 -Flavor dev
Release ZIP physically excludes developer simulation, remote control, diagnostics
and demo implementations. The dev ZIP retains authorized in-game testing tools.
Only one flavor is installed at once. The installer backs up and verifies files.
The internal WarbandPvP folder and saved variables remain unchanged by the
TotalWarcraft rename. /tw is primary; /totalwarcraft and /wb are aliases.
GitHub Actions tests main/PRs; version tags publish compiled Release ZIPs after
checks. CF_API_TOKEN is configured and v0.7.4 completed the first successful
automatic publication. See docs/RELEASE_AUTOMATION.txt for future releases.
For an old CallToArms installation, tools/Migrate-LegacyInstall.ps1 verifies it
against its original archive, backs it up, copies settings under the new variable
names and disables only the old TOC. Run it with WoW closed and the explicit
SavedVariables directory. Old code and settings remain available for rollback.

START HERE
WarbandPvP/README.txt - current player controls and restrictions
WarbandPvP/WARBAND_TESTING.txt - three real clients, optional dummy party slots
 docs/RECRUITMENT_TEST_0.7.0.txt - native recruitment/party acceptance and sources
 docs/BACKEND_HANDOFF.txt - current state and historical implementation evidence
 docs/AUDIT_0.7.5.txt - idle runtime fixes, cleanup and verification limits
 docs/WARBAND_RESULTS_2026-11-20.txt - two-client observed results and limits
 docs/GUID_SECURITY_REVIEW_2026-11-20.txt - GUID/hidden-realm compatibility audit
 docs/LAYER_COORDINATION_RESEARCH_2026-11-18.txt - source audit and arrival design
 docs/assets/ui-layout-preview.html - offline layout reference, not a game capture
Historical /cta commands in older research documents refer to older builds.
Current player commands use /tw; the board is /tw show, not /tw warband.

VALIDATION
Run .venv\Scripts\python.exe tests/test_*.py individually. Tests use Lua 5.1 mocks,
never a live WoW client. tests/test_release.py checks both packaged flavors,
production protocol isolation, native lifecycle paths and deterministic ZIPs.
All Rights Reserved; see WarbandPvP/LICENSE.txt.
