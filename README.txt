TOTALWARCRAFT 0.7.4
World of Warcraft: Forever only (Interface 16001)

Quickly form parties to seek out world PvP or rally your faction to retaliate
against enemy attacks in WoW Forever.

WarbandPvP/ is the addon source. Open /tw for the command board and /tw show
for warbands. One managed dialog is visible at a time, with Back navigation and
a draggable military frame. No external backend or third-party library is needed.

FEATURES
- Automatic eligible outdoor PvP reports, with duel/NPC/FFA/instance safeguards.
  Manual reports remain available via /tw report or a keybind; shared cooldown.
- Compact known-only tooltips and fading nearby-report clusters: scaled swords,
  pulsing red halo and native red weapons/raid skull for heavy reported activity.
- Create Warband and nine-page Help on /tw, with commands and bug-report link.
- Enemy scouting: a visible opposing TotalWarcraft member may reply with a bounded snapshot
  of affiliation and reported warband size. Same-faction guild report recipients
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
- /tw export: bounded local session journal, including group/zone/transfer events.
- UI controls, slash commands and optional keybindings cover player features.

EVIDENCE LIMITS
Fight size, PvP participation and exact layers remain unconfirmed. GUID components
are not cross-client layer keys. A UUID, map position, listing, native group join
or transfer event does not establish arrival at the original fight. Parties-only
is a product choice, not proof that outdoor raids cannot share a layer.

Fifteen offline suites cover isolated Lua clients and the physically
stripped release ZIP. The two-client 0.6.1 live simulation established messaging,
member updates and teardown; it did not validate native grouping or layer arrival.
Finder calls and the revised 0.7 UI/invitations still require live acceptance.
Enemy scouting is implemented and mock-tested, including ordinary members, reply
loss, sender/nonce validation, bounded hostile traffic and expiration. Cross-faction
addon delivery still needs live verification; no reply means unknown, never an
inferred absence of a warband. See docs/ENEMY_SCOUTING_0.7.1.txt.
Public packages use the production build flavor and CurseForge Release stage.
CurseForge project 1819796 / file 9723988 was submitted November 20, 2026;
the user confirmed project approval on November 21. The new 0.7.4 build has
not been uploaded. See docs/REFINEMENTS_0.7.3.txt for current acceptance steps.
See docs/CURSEFORGE_SUBMISSION_0.7.1.txt. Alpha downloads use direct project links.

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
checks. See docs/RELEASE_AUTOMATION.txt for the one-time CF_API_TOKEN setup.
For an old CallToArms installation, tools/Migrate-LegacyInstall.ps1 verifies it
against its original archive, backs it up, copies settings under the new variable
names and disables only the old TOC. Run it with WoW closed and the explicit
SavedVariables directory. Old code and settings remain available for rollback.

START HERE
WarbandPvP/README.txt - current player controls and restrictions
WarbandPvP/WARBAND_TESTING.txt - three real clients, optional dummy party slots
 docs/RECRUITMENT_TEST_0.7.0.txt - native recruitment/party acceptance and sources
 docs/BACKEND_HANDOFF.txt - current state and historical implementation evidence
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
