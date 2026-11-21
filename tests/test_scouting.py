from scouting_scenarios import check_all_scouting, setup
check_all_scouting()
net,scout,friend,enemy=setup()
scout.execute('A.SetTestMode(true); assert(A.Report()); assert(A.List()[1].test)')
assert not any(scout.globals().sentPrefixes[i]=='WBP_SCOUT1' for i in range(1,scout.globals().sends+1))
print('PASS: opposing-player scouting, scoped nonce/sender checks, same-faction report relay, unknown/blocked paths, expiration, bounded hostile inputs, dev isolation and non-overlapping UI.')
