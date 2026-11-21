"""Run recruitment discovery/lifecycle/consent against independent source clients."""
from wow_mock import client
from finder_scenarios import check_finder, check_finder_edges, check_delegated_recruitment, check_idle_and_consent, install
from warband_network import WORLD

check_finder()
check_finder_edges(client)
check_delegated_recruitment()
check_idle_and_consent(client)
from finder_scenarios import check_rally_zone
check_rally_zone(client)
dev = client('Developer One'); dev.execute(WORLD); install(dev)
dev.execute('''
A.testMode=true
assert(A.StartWarband('Developer patrol'))
assert(creates==0 and searches==0)
assert(not A.FinderSearch())
A.warbands.invites['guest-two']={name='Guest Two',slot=1,consented=true,untilAt=CLOCK+30}
A.WarbandTick(); assert(#invited==0)
''')
print('PASS: Finder discovery across guilds, nonce/scope/expiry, party acceptance, listing ownership and teardown, bounded failures, protected fields, UI navigation, developer isolation.')
