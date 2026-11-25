from wow_mock import client
from auto_report_scenarios import check_auto_reports, SETUP
check_auto_reports(client)
from live_activity_scenarios import check_live_activity
check_live_activity(client)
lua=client('Developer Tester'); lua.execute(SETUP)
lua.execute('''
A.SetTestMode(true); combat=true; step(); assert(reportCount()==0)
A.SetTestMode(false); A.warbands.simulationCount=5; step(); assert(reportCount()==0)
''')
print('PASS: five-second flagged-player/NPC activity, bounded events/recipients, secret amounts ignored, ordinary-NPC and self-damage exclusion, live current location, strict post-combat fallback, delayed prior sessions, reset, death, cooldown and peer delivery.')
