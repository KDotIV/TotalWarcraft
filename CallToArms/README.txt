CALL TO ARMS 0.5.2-alpha

Remote testing: the tester runs /cta control allow YourFirst YourSurname once
each session. You can then /cta remote TesterFirst TesterSurname status,
test-on, report, test-off, presence-on/off, capture-start/stop or snapshot.
Use one verb per command and wait five seconds. Reports require test mode ON
and are simulated guild reports; recipients must also enable test mode.
/cta control off revokes access and stops test/presence/capture; reload revokes
access too. See repository docs/REMOTE_TEST_CLI_0.5.2.txt for the full guide.

Install this folder as Interface/AddOns/CallToArms. Restart after first install;
enable Call to Arms. Interface target: 16001. No bundled libraries are required.

Bind Call to Arms -> Report PvP at my location in Key Bindings, or use an
action-bar macro containing /cta report. Both send the same one-action report.

Both players run /cta status first. Guild membership, available messaging and
detected ruleset/region are required. Unknown scope disables network reports.
For simulation, BOTH run /cta test on, then press the report binding. Click the
TEST toast to see details, then Show on map outside combat for the purple pin.
Wait ten seconds between test reports. /cta test off clears test records.

Normal reports have unknown fight size and a 120-second cooldown. Only the
partial flagged-player snapshot summary is sent, not player names/GUIDs.
Test reports simulate observable players and fill to four using synthetic
participant counts. They never become real heat or city-raid authorization.

Guild messages can cross layers. Details show Layer: unknown; coordinate a
group invite with the reporter and use Blizzard's world-refresh UI as needed.
The addon cannot guarantee co-location or force a layer change.

See repository docs/GUILD_REPORT_TEST.txt for the complete test and protocol.

Optional group locations: /cta presence on (or the switch in /cta) shares your
own location and readable PvP flag/generic combat status with your outdoor
party/raid. Both ends opt in. /cta presence off stops sharing; /cta presence
shows status. This resets OFF at login/reload. Green plus markers are fresh
sharing peers, not confirmed PvP fighters. Ten-second updates expire after 30s.
No presence history, automatic heat, invites or layer synchronization is added.

OpenMap is optional. With its compatible public Lua API, CTA converts its own
native report/presence pins to the stitched map in mouse mode. Gamepad and
unavailable/unsupported APIs use matching-zone pins. No OpenMap code or art is
bundled. New functionality is offline-tested; see docs/PRESENCE_TEST.txt for
remaining live acceptance. No companion app or backend is required.

Built-in test capture: /cta layer start <label>, /cta layer snap <label>,
/cta layer mark <what-you-see>, /cta layer stop, /cta layer export. All testers
capture/export independently. Record before joining, after joining and after
refresh. The log includes phase/shard/visibility/distance, transfer events and
report/presence traces. /cta evidence explains why confirmed fighter counts
remain unknown. Diagnostics perform no invites, refresh clicks or broadcasts.
Captures stop after 15 minutes/reload/logout; retained rows are bounded to 1200.
WoW saves CallToArmsDiagnosticsDB in the main CallToArms.lua SavedVariables file
on normal logout/reload. See docs/DIAGNOSTIC_TEST_0.5.1.txt for the full test.
