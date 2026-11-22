"""Two separate mocked Lua clients; no real network calls or game-state claims."""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1] / 'WarbandPvP'
template = ET.parse(ROOT/'MapPins.xml').getroot()[0]
assert template.attrib == {'name':'WarbandPvPMapPinTemplate','virtual':'true','enableMouse':'true','mixin':'WarbandPvPMapPinMixin'}
assert '## Dependencies: Blizzard_MapCanvas' in (ROOT/'WarbandPvP.toc').read_text()
from wow_mock import client

alice, bob = client('Alice'), client('Bob')
alice.execute('''
SlashCmdList.WARBANDPVP('test on')
assert(A.testMode)
WarbandPvP.Report() -- same entry point as binding
assert(sends==1 and #A.List()==1)
local r=A.List()[1]
assert(r.test and r.count==4 and r.observedCount==2 and r.syntheticCount==2)
assert(not r.countUnknown and A.lastSnapshot.players[1].pvpFlagged==false)
assert(A.lastSnapshot.players[1].simulatedCombat)
assert(not A.toast or not A.toast.shown) -- own report never alerts
WarbandPvP.Report(); assert(sends==1) -- cooldown
''')
packet = alice.globals().packets[1]

def deliver(lua, data=packet, sender='Alice-TestRealm', prefix='WBP_REPORT1', route='GUILD'):
    lua.globals().A.OnReportMessage(prefix, data, route, sender)

deliver(bob)  # explicit recipient opt-in required
bob.execute("assert(#A.List()==0); SlashCmdList.WARBANDPVP('test on')")
deliver(bob)
bob.execute('''
assert(#A.List()==1 and sends==0) -- receive never rebroadcasts
local r=A.List()[1]
assert(r.reporter=='Alice-TestRealm' and r.mapID==1 and r.x==.25 and r.y==.75)
assert(r.count==4 and r.syntheticCount==2 and A.toast.shown)
assert(A.toast.title.text:find('[TEST]',1,true))
A.toast.scripts.OnClick(A.toast,'LeftButton')
assert(A.details.shown and not A.toast.shown)
assert(not A.details.body.text:find('Layer: unknown',1,true))
assert(A.details.body.text:find('2 synthetic',1,true))
local pins=0
for _,f in ipairs(frames) do
 if f.parent==canvas and f.shown then
  pins=pins+1; assert(f.record.id==r.id and #f.strokes==6)
  for _,line in ipairs(f.strokes) do
   assert(line.kind=='Line' and line.color[1]==A.testColor[1] and line.color[4]==1)
   assert(line.thickness>=2 and line.startPoint and line.endPoint and not line.shown)
  end
  assert(f.combatIcon:IsShown() and f.combatIcon.texture:find('DualWield',1,true))
  assert(f.point[4]==250 and f.point[5]==-450)
  assert(f.normalizedX==.25 and f.normalizedY==.75 and f.frameLevelType=='PIN_FRAME_LEVEL_AREA_POI')
  assert(f.scaling[2]==1 and f.scaling[3]==1 and f.alphaLimits[2]==1)
  A.details:Hide(); f:OnMouseClickAction('LeftButton'); assert(A.details.shown)
 end
end
assert(pins==1)
SlashCmdList.WARBANDPVP('pincheck'); assert(A.pinCheck.shown)
SlashCmdList.WARBANDPVP('pincheck'); assert(not A.pinCheck.shown)
local poolSize=#WorldMapFrame.pool
WorldMapFrame:SetMapID(2)
for _,p in ipairs(WorldMapFrame.pool) do assert(not p.active and not p.record) end
WorldMapFrame:SetMapID(1)
assert(#WorldMapFrame.pool==poolSize and WorldMapFrame.pool[1].active)
A.RefreshMap(); assert(#WorldMapFrame.pool==poolSize) -- pooled, not growing each tick
''')
deliver(bob); deliver(alice)  # replay and self echo do not duplicate
alice.execute('assert(#A.List()==1)')
bob.execute('assert(#A.List()==1 and sends==0)')

# Reverse direction while the recipient is in mocked combat.
bob.execute('WarbandPvP.Report(); assert(sends==1)')
alice.execute('function InCombatLockdown() return true end; CLOCK=CLOCK+6')
deliver(alice, bob.globals().packets[1], 'Bob-TestRealm')
alice.execute('assert(#A.List()==2 and A.toast.record.reporter=="Bob-TestRealm")')

# Opt-out clears simulated data and ignores incoming tests, retaining real data.
bob.execute('''
SlashCmdList.WARBANDPVP('test off')
assert(#A.List()==0 and not A.details.shown and not A.toast.shown)
CLOCK=CLOCK+10; NOW=NOW+10
WarbandPvP.Report(); assert(sends==2)
assert(not A.List()[1].test and A.List()[1].countUnknown)
''')
real = bob.globals().packets[2]
alice.execute('CLOCK=CLOCK+10; NOW=NOW+10')
deliver(alice, real, 'Bob-TestRealm')
alice.execute('assert(#A.List()==3)')
deliver(bob)
bob.execute('assert(#A.List()==1)')

def altered(index, value):
    fields = packet.split('\t'); fields[index] = value
    return '\t'.join(fields)

# Fresh receiver for adversarial input. Wrong scope never enters store or toasts.
guard = client('Guard')
guard.execute("SlashCmdList.WARBANDPVP('test on')")
for bad in [altered(8, 'rppvp'), altered(12, '2'), altered(7, 'A'),
            altered(5, '10001'), altered(3, '1'), altered(4, 'nan'),
            altered(11, '0'), packet+'\textra', 'x'*256, 'SECRET']:
    deliver(guard, bad)
    guard.execute('CLOCK=CLOCK+2')
deliver(guard, prefix='OTHER'); deliver(guard, route='PARTY')
guard.execute('assert(#A.List()==0 and sends==0)')
guard.execute('''
Enum.GameRule.PvPRuleset=nil
WarbandPvP.Report(); assert(sends==0 and A.scopeRuleset==nil)
''')
deliver(guard)
guard.execute('assert(#A.List()==0)')

# API failure must not become a local success or consume network cooldown.
failed = client('Failed')
failed.execute('''
sendFailure=true
WarbandPvP.Report(); assert(sends==0 and #A.List()==0 and A.db.lastSubmit==0)
sendFailure=false; CLOCK=CLOCK+5; NOW=NOW+5
WarbandPvP.Report(); assert(sends==1 and A.db.lastSubmit==NOW)
''')

# Automatic rulesets cannot be changed by a slash override; RP-PvP differs from PvP.
failed.execute('''
C_GameRules.IsGameRuleActive=function(rule) return rule==2 or rule==3 end
A.RefreshScope(); assert(A.scopeRuleset=='rppvp' and #A.List()==0)
SlashCmdList.WARBANDPVP('ruleset pvp'); assert(A.db.ruleset=='rppvp')
C_GameRules.IsGameRuleActive=function(rule) return rule==1 end
A.RefreshScope(); assert(A.scopeRuleset=='hardcore')
C_GameRules.IsGameRuleActive=function(rule) return rule==2 end
A.RefreshScope(); assert(A.scopeRuleset=='rp')
C_GameRules.IsGameRuleActive=function() return false end
A.RefreshScope(); assert(A.scopeRuleset=='normal')
C_GameRules.IsGameRuleActive=function() return 'SECRET' end
assert(not A.RefreshScope() and A.scopeRuleset==nil)
''')
# A UI exception after a successful send must not report a network failure or
# invite an immediate duplicate retry.
display_failure = client('DisplayFailure')
display_failure.execute('''
A.Changed=function() error('mock UI failure') end
local ok,msg=A.Report()
assert(ok and sends==1 and A.db.lastSubmit==NOW)
assert(msg:find('accepted',1,true))
''')
print('PASS: separate-client reports, test isolation, native map provider/template, normalized placement, managed frame level, pooled refresh/zone changes, click details, packet bounds, duplicates, cooldowns and scope filtering.')
print('Mock combat validates code paths only; real client UI/security behavior still requires testing.')
