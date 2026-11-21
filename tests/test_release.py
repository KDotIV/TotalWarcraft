"""Exercise the actual stripped package, including hostile/dev messages and UI."""
import sys
import zipfile
from pathlib import Path
from lupa.lua51 import LuaRuntime
from wow_mock import BOOT
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from build_addon import build, compile_lua

root, manifest = build('release')
dev, dev_manifest = build('dev')
for flavor, directory in [('release', root), ('dev', dev)]:
    for path in directory.glob('*.lua'):
        lua = LuaRuntime(unpack_returned_tuples=True)
        assert lua.eval('function(s) return loadstring(s) end')(path.read_text()), path
with zipfile.ZipFile(manifest['zip']) as z:
    assert all(n.startswith('WarbandPvP/') for n in z.namelist())
    names = {Path(n).name for n in z.namelist()}
    assert not names.intersection({'Control.lua','Diagnostics.lua','WarbandSimulation.lua','Development.lua','WARBAND_TESTING.txt','CrossedSwords.tga'})
    code = '\n'.join(z.read(n).decode() for n in z.namelist() if n.endswith(('.lua','.txt','.toc')))
    for forbidden in ['WBP_CTL1','WBP_WBT1','testMode','SetTestMode','simulate','synthetic','/tw demo','/tw remote','/tw layer','/tw test','SetTransport','SetWarbandSimulation']:
        assert forbidden not in code, forbidden

def release_client(name):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(BOOT)
    lua.globals().PLAYER = name
    for line in (root/'WarbandPvP.toc').read_text().splitlines():
        if line.endswith('.lua'):
            lua.execute('assert(loadstring(...))("WarbandPvP",A)', (root/line).read_text())
    lua.execute("for _,f in ipairs(frames) do if f.events.ADDON_LOADED then core=f end end; core.scripts.OnEvent(nil,'ADDON_LOADED','WarbandPvP')")
    return lua

alice, bob = release_client('Alice One'), release_client('Bob Two')
from auto_report_scenarios import check_auto_reports
from activity_scenarios import check_activity
check_auto_reports(release_client)
check_activity(release_client)
from runtime_scenarios import check_runtime
check_runtime(release_client)
from forever_compat import check_hidden_realms
check_hidden_realms(release_client)
assert alice.globals().SLASH_WARBANDPVP1 == '/tw'
alice.execute("assert(TotalWarcraft==WarbandPvP and SLASH_WARBANDPVP3=='/wb'); assert(BINDING_HEADER_WARBANDPVP=='TotalWarcraft')")
alice.execute("SlashCmdList.WARBANDPVP('show'); assert(A.warbands.panel:IsShown()); A.CloseWindows()")
alice.execute('''
assert(A.buildFlavor=='release' and not A.SetTestMode and not A.ControlCommand and not A.SetWarbandSimulation)
assert(not WarbandPvP.Receive and not WarbandPvP.SetTransport)
for _,cmd in ipairs({'test on','remote Bob Two report','control allow Bob Two','simulate 5','demo','pincheck','layer start'}) do SlashCmdList.WARBANDPVP(cmd) end
assert(sends==0 and not A.testMode and not A.warbands.host)
A.CloseWindows(); A.ShowHome(); assert(A.home:IsShown())
A.BuildUI(); A.panel:Show(); assert(not A.home:IsShown())
A.BackWindow(); assert(A.home:IsShown() and not A.panel:IsShown())
assert(A.Report()); assert(sends==1 and #A.List()==1)
assert(A.List()[1].countUnknown and A.List()[1].count==0)
''')
packet=alice.globals().packets[1]
bob.globals().A.OnGuildMessage('WBP_REPORT1',packet,'GUILD','Alice One')
bob.execute("assert(#A.List()==1); A.ShowDetails(A.List()[1]); assert(A.details:IsShown()); A.ShowExport(); assert(not A.details:IsShown() and A.exportPanel:IsShown())")
fields=packet.split('\t'); fields[1]='T'
bob.globals().A.OnGuildMessage('WBP_REPORT1','\t'.join(fields),'GUILD','Developer One')
bob.execute(r'''
assert(#A.List()==1)
assert(A.SessionLogText():find('REPORT_RECEIVE',1,true))
assert(A.SessionLogText():find('Names and in-game locations',1,true))
-- Ring buffer keeps the newest records and bounds floods/restricted values.
for i=1,1600 do CLOCK=CLOCK+1; A.Trace('ROW','row-'..i) end
local text=A.SessionLogText()
assert(text:find('row%-1600') and not text:find('row%-1\n'))
local lines=0; for _ in text:gmatch('\n') do lines=lines+1 end; assert(lines<=1502)
A.Trace('RESTRICTED','SECRET'); assert(A.SessionLogText():find('<restricted>',1,true))
for i=1,1000 do A.Trace('FLOOD','ignored') end
assert(#A.SessionLogText()<1000000)
-- Never steal another binding; explicit clear/save uses the current set.
bindings={F1='OTHER'}; saved=0
function GetBindingAction(k) return bindings[k] or '' end
function GetBindingKey(action) for key,value in pairs(bindings) do if value==action then return key end end end
function SetBinding(k,a) if k=='INVALID' then return false end; bindings[k]=a; return true end
function SaveBindings(n) assert(n==2); saved=saved+1 end
function GetCurrentBindingSet() return 2 end
assert(not A.AssignBinding('WARBANDPVP_OPEN','F1')); assert(bindings.F1=='OTHER')
assert(A.AssignBinding('WARBANDPVP_OPEN','CTRL-SHIFT-C')); assert(saved==1)
assert(not A.AssignBinding('WARBANDPVP_OPEN','INVALID')); assert(bindings['CTRL-SHIFT-C']=='WARBANDPVP_OPEN')
assert(A.AssignBinding('WARBANDPVP_OPEN','')); assert(not bindings['CTRL-SHIFT-C'])
''')
# Developer package still contains separately authorized tools and fixtures.
assert (dev/'Control.lua').exists() and 'WBP_WBT1' in (dev/'WarbandProtocol.lua').read_text()
for malformed in ['--@enddev','--@dev\nlocal x=1','--@dev\n--@release return\n--@enddev']:
    try: compile_lua(malformed,'release')
    except ValueError: pass
    else: raise AssertionError('Malformed build directive accepted')
assert build('release')[1]['sha256']==manifest['sha256']
# Repeat the join/lease/END path using compiled production clients, not source.
import warband_network
warband_network.client=release_client
from scouting_scenarios import check_all_scouting
check_all_scouting()
from finder_scenarios import check_finder, check_finder_edges, check_delegated_recruitment, check_idle_and_consent
check_finder()
check_finder_edges(release_client)
check_delegated_recruitment()
check_idle_and_consent(release_client)
from finder_scenarios import check_rally_zone
check_rally_zone(release_client)
net=warband_network.Network()
host=net.add('Host One'); peer=net.add('Peer Two')
for lua in (host, peer):
    lua.execute("GetRealmName=function() return '' end; GetRealmID=function() return 0 end; GetNormalizedRealmName=function() return '' end; UnitFullName=function(u) return memberName(u),'' end")
net.party('Host One',['Host One','Helper One'])
net.party('Peer Two',['Peer Two','Helper Two'])
host.execute("assert(A.StartWarband('Release patrol'))")
peer.execute('A.SetWarbandsEnabled(true)')
net.advance(18)
peer.execute('assert(A.JoinWarband(A.WarbandList()[1].id))')
net.advance(110)
peer.execute('assert(A.warbands.member and A.warbands.member.slot==2); assert(#A.WarbandList()==1)')
solo=net.add('Solo Three'); solo.execute('A.SetWarbandsEnabled(true)'); net.advance(31)
solo.execute('assert(A.JoinWarband(A.WarbandList()[1].id))'); net.advance(3)
host.execute("assert(A.warbands.invites['solo-three']); A.warbands.invites={}; A.WarbandCommand('recruit off')")
net.advance(16)
solo.execute('assert(not A.WarbandList()[1].recruiting); assert(A.JoinWarband(A.WarbandList()[1].id))')
net.advance(3)
host.execute("assert(A.warbands.invites['solo-three'])")
host.execute('A.LeaveWarband()'); net.advance(3)
peer.execute('assert(not A.warbands.member and #A.WarbandList()==0)')
# Restrict accidental installs on Retail/other Classic clients.
peer.execute("function GetBuildInfo() return '12.0','1','',120000 end; assert(not A.RefreshScope()); assert(not A.Report())")
print('PASS: actual release ZIP has no developer code/protocols/commands; report delivery, navigation, bounded session export, non-stealing keybindings, dev isolation, deterministic packaging.')
