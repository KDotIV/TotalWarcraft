from wow_mock import client
from auto_report_scenarios import check_auto_reports, SETUP
check_auto_reports(client)
lua=client('Developer Tester'); lua.execute(SETUP)
lua.execute('''
A.SetTestMode(true); combat=true; step(); assert(reportCount()==0)
A.SetTestMode(false); A.warbands.simulationCount=5; step(); assert(reportCount()==0)
''')
print('PASS: eligible outdoor target combat, NPC/faction/flag/visibility/restricted checks, duel lifecycle/outgoing/reload suppression, shared cooldown, manual and dev isolation, toggles, failed-send bounds and peer delivery.')
