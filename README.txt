TOTALWARCRAFT 0.7.8
World of Warcraft: Forever only (Interface 16001)

Quickly form parties to seek out world PvP or rally your faction to retaliate
against enemy attacks in WoW Forever.

WarbandPvP/ is the addon source. Open /tw for the command board and /tw show
for warbands. One managed dialog is visible at a time, with Back navigation and
a draggable military frame. No external backend or third-party library is needed.

FEATURES
- Automatic reports require attributable incoming opposing-player damage after
  combat, with fresh-session, identity, duel/NPC/pet/FFA/instance safeguards.
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
Fight size and exact layers remain unconfirmed. Automatic local reports now use
attributable incoming player damage; manual and received reports remain claims.
GUID components
are not cross-client layer keys. A UUID, map position, listing, native group join
or transfer event does not establish arrival at the original fight. Parties-only
is a product choice, not proof that outdoor raids cannot share a layer.

Nineteen offline suites cover isolated Lua clients and the physically
stripped release ZIP. The two-client 0.6.1 live simulation established messaging,
member updates and teardown; it did not validate native grouping or layer arrival.
Finder calls and the revised 0.7 UI/invitations still require live acceptance.
Enemy scouting is implemented and mock-tested, including ordinary members, reply
loss, sender/nonce validation, bounded hostile traffic and expiration. Cross-faction
addon delivery still needs live verification; no reply means unknown, never an
inferred absence of a warband. See docs/ENEMY_SCOUTING_0.7.1.txt.
Public packages use the production build flavor and CurseForge Release stage.
Version 0.7.7 passed all 19 suites locally and in GitHub CI and was uploaded to
CurseForge as Release file 9754372. Public approval/indexing is not yet verified.
All 30 uploaded files matched the tested 0.7.7 production build at installation.
Receipt: docs/CURSEFORGE_SUBMISSION_0.7.7.txt.
https://www.curseforge.com/wow/addons/total-warcraft/files/9754372
The 0.7.8 patch adds notification safeguards and expanded diagnostics; all 20
offline suites passed locally. See docs/UI_SESSION_AUDIT_0.7.8.txt for live checks.
Release publication is in progress; the upload receipt will be recorded separately.
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
