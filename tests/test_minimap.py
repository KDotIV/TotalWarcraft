from wow_mock import client
from minimap_scenarios import check_minimap, SETUP

check_minimap(client)
lua=client('Minimap Developer'); lua.execute(SETUP)
lua.execute('''
point('normal',0,0); A.SetTestMode(true); assert(A.Report())
assert(A.minimapReports.count==2)
A.SetTestMode(false); assert(A.minimapReports.count==1)
''')
print('PASS: native minimap projection, rotation/zoom/shape, zone/world isolation, clipping before clustering, pooled lifecycle, bounded active/idle work, secret guards, expiry, deferred clicks and local/peer delivery.')
