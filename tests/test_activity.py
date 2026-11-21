from wow_mock import client
from activity_scenarios import check_activity
check_activity(client)
lua=client('Developer Tester')
lua.execute('''
A.records={}
for i=1,4 do A.records[tostring(i)]={id=tostring(i),kind='report',title='',reporter='Reporter '..i,
 opposition='',note='',mapID=1,x=.5,y=.5,faction='Horde',ruleset='pvp',updatedAt=NOW,expiresAt=NOW+300,
 test=i~=1,count=0,countUnknown=true,observedCount=0} end
local c=A.ReportClusters(); assert(#c==2)
for _,v in ipairs(c) do if not v.record.test then assert(v.reports==1 and not v.pulse) end end
''')
print('PASS: bounded nearby report clusters, unique reporters, fading, separate maps/dev data, no chaining, pooled halo/skull cleanup and native icon fallback, concise known-only tooltips and paginated Help/navigation.')
