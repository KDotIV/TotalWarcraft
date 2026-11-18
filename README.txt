CALL TO ARMS 0.5.2-alpha
Documentation reconciled November 18, 2026

CallToArms/ is the installable MAIN addon. /cta report sends one bounded guild
addon message. Matching recipients display the report; accepted submissions also
display locally. Only remote receipt proves delivery. No external service or
third-party library is required. Target interface: 16001.

Start here:
  docs/REMOTE_TEST_CLI_0.5.2.txt - control online testers through in-game commands
  docs/DIAGNOSTIC_TEST_0.5.1.txt - three-player layer test, evidence capture and export
  docs/MVP_REVIEW_2026-11-18.txt - current MVP gaps and installed OpenMap research
  docs/PRESENCE_TEST.txt - opt-in group locations, protocol and live acceptance
  docs/LAYER_COORDINATION_RESEARCH_2026-11-18.txt - LayerSwap and accept/arrival design
  docs/GUILD_REPORT_TEST.txt - install, bind and run the two-player report test
  docs/GUILD_REPORT_RESULTS_2026-11-09.txt - observed results and evidence limits
  docs/PRE_LAYER_TEST_CHECKLIST.txt - remaining checks before layer coordination
  docs/BACKEND_HANDOFF.txt - current architecture, wire contract and future scope
  docs/BACKEND_STACK.txt - C# recommendation and external-transport boundary

Verified so far: two-way cross-zone guild diagnostic delivery, including sends
during PvE combat; main report receipt/details; visible map pins after the 0.4.4
fix. The managed AREA_POI map layer places the native line swords above fog and
exploration overlays. See docs/MAP_PIN_FIX_0.4.4.txt for the cause and correction.
Final remote-origin pin/toast tests on BOTH updated clients, keybinding use and
main UI combat/lifecycle checks remain open. Probe combat success alone does not
prove the full report UI in combat. Actual PvP detection is not implemented.

/cta report       One-action report, also in Key Bindings or an action-bar macro
/cta control allow First Surname  Authorize one remote tester controller this session
/cta remote First Surname status  Request status; see the CLI guide for other verbs
/cta control off  Revoke control and stop test/presence/capture
/cta presence on  Share your location/status with outdoor party/raid this session
/cta presence off Stop group location sharing and clear local peer markers
/cta presence     Fresh peers, checked nearby peers, unknown range and send status
/cta layer start <label>  Capture local phase/visibility/transfer and validation data
/cta layer snap <label>   Record/print group readings; mark <text> adds a manual note
/cta layer stop   Stop capture; /cta layer export opens the copyable log
/cta evidence     Current reliable PvP-attribution capability (still unresolved)
/cta test on      Session-only simulated report; recipients must also opt in
/cta test off     End simulation and clear test reports
/cta status       Version, detected scope, guild transport and test state
/cta              Activity panel and notification toggle
/cta demo         Local-only interface preview
/cta clear        Clear local records; cooldowns remain
/cta mapdebug     Current map/pin diagnostics
/cta pincheck     Toggle independent crossed-swords rendering check

Normal reports retain unknown fight size. Simulation includes the reporter and
fills the participant count to four when needed, with explicit synthetic counts.
Only accessible players with verified distance are sampled; this is not a full
100-yard census. No actual combat/PvP flags are changed. Test mode resets off
on reload/login. Normal send cooldown: 120s; test send cooldown: 10s.

Audience uses detected game-rule flags, region and faction. Unknown scope disables
networking; manual ruleset overrides are not used. Guild broadcast is not a
faction-wide or cross-guild network, and client filtering is not confidentiality.
Group presence uses separate PARTY/RAID addon messages, including other guilds
within the group, and defaults OFF each session. Green plus markers expire after
30 seconds; sends are throttled to ten seconds. Presence, flags and generic combat
never count as confirmed PvP. OpenMap's optional public Lua coordinate API lets
CTA own its native pins on the stitched map in mouse mode; otherwise zone-only
fallback applies. No backend or OpenMap installation is required.

Layer IDs remain unknown in CTA. No automatic invites, layer transfer or world refresh
are implemented. Different-zone message receipt does not prove different layers.

Development checks (passed for 0.5.2; mocks do not replace live acceptance):
  python -m pip install lupa
  python tests/test_addon.py
  python tests/test_reporting.py
  python tests/test_identity.py
  python tests/test_guild_reports.py
  python tests/test_presence.py
  python tests/test_diagnostics.py
  python tests/test_control.py

probes/ contains separate in-game messaging diagnostics (current version 0.3.0)
and the closed snapshot experiment. probes/RESULTS.txt records live transport
evidence. Discord/relay tooling is not active. No backend connection is proven.
Current main release: releases/CallToArms-0.5.2-alpha.zip; install its inner
CallToArms folder. Historical releases are not the current installation package.
New presence, diagnostics and remote control have no live acceptance result yet. The diagnostic
captures observations without an automatic synced/confirmed-fighters verdict.
Use tools/Install-Addon.ps1 to back up, copy and hash-verify the testing build.
