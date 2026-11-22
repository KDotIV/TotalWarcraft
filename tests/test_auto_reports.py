from wow_mock import client
from auto_report_scenarios import check_auto_reports, SETUP
check_auto_reports(client)
lua=client('Developer Tester'); lua.execute(SETUP)
lua.execute('''
A.SetTestMode(true); combat=true; step(); assert(reportCount()==0)
A.SetTestMode(false); A.warbands.simulationCount=5; step(); assert(reportCount()==0)
''')
print('PASS: native incoming player damage, live-shaped rows, NPC/pet rejection, fresh correlated sessions, exclusions, interrupted/restarted combat, captured location, bounded reads, manual cooldown and peer delivery.')
