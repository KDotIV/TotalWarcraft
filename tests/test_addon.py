from pathlib import Path
# Install the development-only runtime with: python -m pip install lupa
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1] / 'CallToArms'
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
NOW = 10000
function GetServerTime() return NOW end
function GetTime() return NOW end
function UnitFactionGroup() return 'Horde' end
function UnitName() return 'Tester' end
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end
C_Timer = {NewTicker=function() return {Cancel=function() end} end}
A = {db={ruleset='pvp'}}
''')
for path in root.glob('*.lua'):
    lua.execute('assert(loadstring(...))', path.read_text())
lua.execute('assert(loadstring(...))("CallToArms", A)', (root/'Model.lua').read_text())
lua.execute('''
function record(id)
 return {version=1,id=id or 'a',kind='heat',faction='Horde',ruleset='pvp',
 mapID=1,x=.5,y=.5,count=4,updatedAt=NOW,expiresAt=NOW+300,cityAllowed=true,
 title='fight',reporter='tester'}
end
assert(A.Receive(record()))
assert(not A.Receive(record())) -- duplicate
local r=record(); r.updatedAt=NOW+1; r.count=5; assert(A.Receive(r))
assert(#A.List()==1 and A.List()[1].count==5)
for key,value in pairs({faction='Alliance',ruleset='normal',kind='bad',x=2,
 count=3,mapID=1.5,expiresAt=NOW,updatedAt=NOW+31,id='bad|id',cityAllowed=false}) do
 local bad=record('bad'); bad[key]=value; assert(not A.Receive(bad),key)
end
local bad=record('nan'); bad.x=0/0; assert(not A.Receive(bad))
local clean=record('clean'); clean.title='|Tfoo|t\\nhello'; assert(A.Receive(clean))
assert(not A.records.clean.title:find('|',1,true))
for i=1,100 do assert(A.Receive(record('id'..i))) end
assert(#A.List()==64)
NOW=NOW+400; assert(A.Prune(NOW)); assert(#A.List()==0)
''')
print('PASS: Lua 5.1 syntax for all modules; validation, audience isolation, duplicates, capacity, expiry and text sanitization.')
