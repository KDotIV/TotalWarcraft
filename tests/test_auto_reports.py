from wow_mock import client
from auto_report_scenarios import check_auto_reports, SETUP
check_auto_reports(client)
lua=client('Developer Tester'); lua.execute(SETUP)
lua.execute('''
A.SetTestMode(true); combat=true; step(); assert(reportCount()==0)
A.SetTestMode(false); A.warbands.simulationCount=5; step(); assert(reportCount()==0)
''')
print('PASS: strict post-combat incoming/outgoing attribution, 70-second Galahad/death regression, no combat meter reads, NPC/pet/secret rejection, deferred retries, captured location, cooldown and peer delivery.')
