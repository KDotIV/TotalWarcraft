from wow_mock import client
from runtime_scenarios import check_runtime

check_runtime(client)
print('PASS: no idle timers, one-second discovery maintenance, bounded queue draining, Finder cleanup after disable, scouting timeout/sleep, report timer/provenance and live presence UI refresh.')
