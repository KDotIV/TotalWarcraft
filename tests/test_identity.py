from pathlib import Path
import xml.etree.ElementTree as ET
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1] / 'WarbandPvP'
toc = (root/'WarbandPvP.toc').read_text()
assert '## SavedVariables: WarbandPvPDB' in toc
for line in toc.splitlines():
    if line and not line.startswith('#'):
        assert (root/line).is_file(), line
binding = ET.parse(root/'Bindings.xml').getroot().find('Binding')
assert binding.attrib == {'name':'WARBANDPVP_REPORT','header':'WARBANDPVP'}
for path in root.glob('*.lua'):
    assert 'ForeverPVP' not in path.read_text()

from wow_mock import BOOT
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(BOOT)
lua.execute("PLAYER='Identity Tester'; WarbandPvPDB={ruleset='rp',muted=true,lastSubmit=NOW-100}; C_GameRules.IsGameRuleActive=function(rule) return rule==2 end")
for line in toc.splitlines():
    if line.endswith('.lua'):
        lua.execute('assert(loadstring(...))("WarbandPvP",A)',(root/line).read_text())
lua.execute("for _,f in ipairs(frames) do if f.events.ADDON_LOADED then handler=f.scripts.OnEvent end end")
lua.execute('''
handler(nil,'ADDON_LOADED','Unrelated')
assert(WarbandPvP==nil)
handler(nil,'ADDON_LOADED','WarbandPvP')
A.Demo=function() demos=(demos or 0)+1 end; A.RunReport=function() reports=(reports or 0)+1 end; WarbandPvP.Report=A.RunReport
assert(WarbandPvP.Version==1 and A.db==WarbandPvPDB)
assert(A.db.ruleset=='rp' and A.db.muted and A.db.lastSubmit==NOW-100)
assert(SLASH_WARBANDPVP1=='/tw' and BINDING_HEADER_WARBANDPVP=='TotalWarcraft')
assert(SLASH_WARBANDPVP2=='/totalwarcraft' and SLASH_WARBANDPVP3=='/wb')
assert(TotalWarcraft==WarbandPvP and TotalWarcraft.Version==1)
assert(type(WarbandPvP.Report)=='function' and type(WarbandPvP.Receive)=='function')
assert(WarbandPvP.SetTransport(function() return true end))
SlashCmdList.WARBANDPVP(' report '); assert(reports==1)
SlashCmdList.WARBANDPVP('demo'); assert(demos==1)
assert(ForeverPVP==nil and SlashCmdList.FOREVERPVP==nil)
''')
lua.execute(binding.text)
lua.execute('assert(reports==2)')
print('PASS: manifest, renamed initialization/API, saved settings, command dispatch and XML binding.')
