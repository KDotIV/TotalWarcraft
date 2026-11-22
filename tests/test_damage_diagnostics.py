"""Dev-only, non-broadcasting meter capture; mocks do not establish native semantics."""
from wow_mock import client
from wow_mock import BOOT
from lupa.lua51 import LuaRuntime
from pathlib import Path
import sys

SETUP = r'''
combat=false; available=true; calls=0; currentMap=1; duel=false; targetNPC=false
enemyGUID='Player-Enemy'; enemyName='Enemy Person'
function UnitAffectingCombat(u) return combat end
function InCombatLockdown() return combat end
function UnitExists(u) return u=='player' or u=='target' or u=='focus' and secondEnemy end
function UnitIsVisible(u) return UnitExists(u) end
function UnitIsPlayer(u) return u=='player' or not targetNPC and UnitExists(u) end
function UnitIsPVP() return true end
function UnitCanAttack() return true end
function UnitIsPVPFreeForAll() return false end
function UnitIsPVPSanctuary() return false end
function UnitFactionGroup(u) return u=='player' and 'Horde' or 'Alliance' end
function UnitName(u) return u=='player' and PLAYER or enemyName end
function UnitFullName(u) return UnitName(u),'' end
function UnitGUID(u) return u=='player' and 'Player-Self' or (u=='focus' and 'Player-Other' or enemyGUID) end
C_Map.GetBestMapForUnit=function() return currentMap end
A.ReportBlockedByDuel=function() return duel end
Enum.DamageMeterType={DamageDone=0,DamageTaken=7,EnemyDamageTaken=10}
sessionList={{sessionID=10}}
incoming={}; outgoing={}; enemyTaken={}
function native() assert(not combat,'native meter read during combat'); calls=calls+1 end
C_DamageMeter={
 IsDamageMeterAvailable=function() native(); return available end,
 GetAvailableCombatSessions=function() native(); return sessionList end,
 GetCombatSessionFromID=function(sid,kind)
  native(); assert(sid~=10,'old session selected')
  if kind==10 then return {combatSources={{sourceGUID=enemyGUID,isLocalPlayer=false}}} end
  return {combatSources={{sourceGUID='Player-Self',isLocalPlayer=true,name=PLAYER}}}
 end,
 GetCombatSessionSourceFromID=function(sid,kind,guid)
  native(); return {combatSpells=kind==7 and incoming or kind==0 and outgoing or enemyTaken}
 end,
 ResetAllCombatSessions=function() error('must not reset native meter') end,
}
function damage(unit,amount,mob,pet)
 return {spellID=1,totalAmount=amount,combatSpellDetails={unitName=unit,amount=amount,isMob=mob==true,isPet=pet==true,unitClassFilename='WARRIOR'}}
end
function start(label) SlashCmdList.WARBANDPVP('damage start '..(label or 'case')) end
function fight()
 combat=true; A.OnDamageDiagnosticEvent('PLAYER_REGEN_DISABLED')
 A.UpdateAutoReports(); A.AutoReportTick()
end
function done(sid)
 sid=sid or 11
 sessionList={{sessionID=10},{sessionID=sid}}
 A.OnDamageDiagnosticEvent('DAMAGE_METER_COMBAT_SESSION_UPDATED',7,sid)
 combat=false; A.OnDamageDiagnosticEvent('PLAYER_REGEN_ENABLED'); A.UpdateAutoReports()
 advanceTimers(4)
end
function result(s) assert(A.damageDiagnostics.result:find(s,1,true), A.damageDiagnostics.result) end
'''

def capture():
    lua = client('Tester Person')
    lua.execute(SETUP)
    return lua

for mode, expected in [('incoming', 'incoming=1 outgoing=0 exchange=0'),
                       ('outgoing', 'incoming=0 outgoing=1 exchange=0'),
                       ('both', 'incoming=1 outgoing=1 exchange=1'),
                       ('none', 'incoming=0 outgoing=0 exchange=0')]:
    lua = capture()
    lua.execute('''
    assert(activeTimers()==0)
    start(); assert(A.DamageDiagnosticActive() and activeTimers()==1)
    local setting=A.db.autoReports
    assert(not A.Report()); assert(sends==0)
    local before=calls; fight(); assert(calls==before)
    assert(activeTimers()==1 and A.db.autoReports==setting)
    ''')
    if mode in ('incoming', 'both'):
        lua.execute("incoming={damage('Enemy Person',20)}")
    if mode in ('outgoing', 'both'):
        lua.execute("outgoing={damage('Enemy-Person',30)}")
    lua.execute('done()')
    lua.globals().result(expected)
    lua.execute('''
    assert(not A.DamageDiagnosticActive() and activeTimers()==0)
    assert(A.damageDiagnostics.reads==3 and sends==0 and #A.List()==0)
    A.ShowHome(); SlashCmdList.WARBANDPVP('damage export')
    assert(A.damageExport:IsShown() and not A.home:IsShown())
    assert(A.damageExport.edit.text:find('BUILD field1=1.60.1',1,true))
    local n=#WarbandPvPDiagnosticsDB.damage.entries
    A.InitDamageDiagnostics(); assert(#WarbandPvPDiagnosticsDB.damage.entries==n)
    assert(not A.DamageDiagnosticActive())
    ''')

# EnemyDamageTaken is an alternate outgoing candidate, never incoming.
lua = capture()
lua.execute("enemyTaken={damage('Tester Person',12)}; start(); fight(); done(); result('incoming=0 outgoing=1 exchange=0')")

# NPC/pet/zero/missing-amount/totals and same-faction/short-name data cannot qualify.
for mutation in ["targetNPC=true", "incoming[1].combatSpellDetails.isMob=true",
                 "incoming[1].combatSpellDetails.isPet=true", "incoming[1].combatSpellDetails.amount=0",
                 "incoming[1].combatSpellDetails.amount=nil", "incoming[1].combatSpellDetails.unitName='Enemy'",
                 "function UnitFactionGroup() return 'Horde' end", "secondEnemy=true"]:
    lua = capture()
    lua.execute("incoming={damage('Enemy Person',20)}; " + mutation + "; start(); fight(); done(); result('incoming=0 outgoing=0 exchange=0')")

# Strict secret stand-ins throw on indexing/stringifying/arithmetic; never leave the client.
for mutation in ["incoming[1].combatSpellDetails=RESTRICTED", "incoming[1].combatSpellDetails.unitName=RESTRICTED",
                 "incoming[1].combatSpellDetails.amount=RESTRICTED", "incoming[1].combatSpellDetails.isMob=RESTRICTED",
                 "incoming=RESTRICTED", "incoming={RESTRICTED}",
                 "C_DamageMeter.GetCombatSessionFromID=function() native(); return RESTRICTED end"]:
    lua = capture()
    lua.execute('''
    RESTRICTED=setmetatable({}, {__tostring=function() error('secret stringify') end,
      __index=function() error('secret indexing') end,__lt=function() error('secret compare') end,
      __add=function() error('secret arithmetic') end})
    function issecretvalue(v) return rawequal(v,RESTRICTED) or v=='SECRET' end
    incoming={damage('Enemy Person',20)}
    ''')
    lua.execute(mutation + "; start(); fight(); done()")
    lua.execute("assert(not A.damageDiagnostics.result:find('incoming=1',1,true)); assert(sends==0 and not A.DamageDiagnosticText():find('SECRET',1,true))")

# Refuse unavailable API, combat-time arm, simulated fixtures and stale session baselines.
for setup in ["C_DamageMeter=nil", "available=false", "available='SECRET'", "combat=true", "A.testMode=true",
              "sessionList={{sessionID='SECRET'}}", "sessionList='SECRET'", "duel=true"]:
    lua = capture()
    lua.execute(setup + "; start(); assert(not A.DamageDiagnosticActive() and activeTimers()==0 and sends==0)")
lua = capture()
lua.execute("incoming={damage('Enemy Person',10)}; start(); fight(); done(10); result('no readable attributable result')")
lua = capture()
lua.execute('''
start(); fight(); incoming={damage('Enemy Person',10)}
sessionList={{sessionID=11},{sessionID=12}}; combat=false
A.OnDamageDiagnosticEvent('PLAYER_REGEN_ENABLED'); advanceTimers(4)
result('excluded: multiple new sessions'); assert(sends==0)
''')

# Events must correlate the fresh session; no blind latest-session attribution.
lua = capture()
lua.execute('''
start(); fight(); incoming={damage('Enemy Person',10)}
combat=false; sessionList={{sessionID=11}}; A.OnDamageDiagnosticEvent('PLAYER_REGEN_ENABLED')
advanceTimers(4); result('incoming=0 outgoing=0 exchange=0')
''')

# Context invalidation, stale positive results, deferred late data, duplicate events.
for event in ['DUEL_REQUESTED', 'SHARD_TRANSFER', 'ZONE_CHANGED_NEW_AREA', 'DAMAGE_METER_RESET']:
    lua = capture()
    lua.execute("start(); fight(); incoming={damage('Enemy Person',10)}")
    lua.globals().A.OnDamageDiagnosticEvent(event)
    lua.execute("done(); result('excluded:'); assert(not A.DamageDiagnosticActive() and sends==0)")
lua = capture()
lua.execute('''
start(); fight(); incoming={damage('Enemy Person',10)}; sessionList={{sessionID=11}}
A.OnDamageDiagnosticEvent('DAMAGE_METER_COMBAT_SESSION_UPDATED',7,11)
combat=false; A.OnDamageDiagnosticEvent('PLAYER_REGEN_ENABLED'); advanceTimers(.6)
result('incoming=1 outgoing=0 exchange=0')
outgoing={damage('Enemy Person',12)}
for i=1,20 do A.OnDamageDiagnosticEvent('PLAYER_REGEN_ENABLED') end
advanceTimers(3); result('incoming=1 outgoing=1 exchange=1'); assert(A.damageDiagnostics.reads==3)
start(); fight(); done(12); assert(sends==0)
''')
lua = capture()
lua.execute('''
start(); fight(); incoming={damage('Enemy Person',10)}; sessionList={{sessionID=11}}
A.OnDamageDiagnosticEvent('DAMAGE_METER_COMBAT_SESSION_UPDATED',7,11)
combat=false; A.OnDamageDiagnosticEvent('PLAYER_REGEN_ENABLED'); advanceTimers(.6)
result('incoming=1 outgoing=0 exchange=0')
combat=true; A.OnDamageDiagnosticEvent('PLAYER_REGEN_DISABLED')
result('excluded: new combat'); assert(activeTimers()==0 and sends==0)
''')

# Hard time, memory, event and row bounds; log persistence never rearms.
lua = capture()
lua.execute('''
start(); advanceTimers(901); assert(not A.DamageDiagnosticActive() and activeTimers()==0)
start(); fight()
for i=1,70 do A.OnDamageDiagnosticEvent('DAMAGE_METER_COMBAT_SESSION_UPDATED',7,i+100) end
result('excluded: session event capacity'); assert(not A.DamageDiagnosticActive())
combat=false; start(); fight()
incoming={}; for i=1,520 do incoming[i]=damage('Enemy Person',1) end
done(); result('excluded: spell capacity')
assert(#WarbandPvPDiagnosticsDB.damage.entries<=600)
combat=false; start(); A.OnDamageDiagnosticEvent('PLAYER_LOGOUT')
assert(not A.DamageDiagnosticActive() and activeTimers()==0)
SlashCmdList.WARBANDPVP('damage clear'); assert(#WarbandPvPDiagnosticsDB.damage.entries==0)
''')

# Incoming/outgoing damage involving different enemies is not a reciprocal pair.
lua = capture()
lua.execute('''
function UnitName(u) return u=='player' and PLAYER or (u=='focus' and 'Other Enemy' or enemyName) end
secondEnemy=true; start(); fight()
incoming={damage('Enemy Person',20)}; outgoing={damage('Other Enemy',30)}
done(); result('incoming=1 outgoing=1 exchange=0')
''')

# Test the installable dev package as well as source; production has no capture.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from build_addon import build
stage, manifest = build('dev')
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(BOOT)
lua.globals().PLAYER = 'Tester Person'
for line in (stage/'WarbandPvP.toc').read_text().splitlines():
    if line.endswith('.lua'):
        lua.execute('assert(loadstring(...))("WarbandPvP",A)', (stage/line).read_text())
lua.execute("for _,f in ipairs(frames) do if f.events.ADDON_LOADED then core=f end end; core.scripts.OnEvent(nil,'ADDON_LOADED','WarbandPvP')")
lua.execute(SETUP)
lua.execute("start('packaged-dev'); fight(); incoming={damage('Enemy Person',10)}; done(); result('incoming=1 outgoing=0 exchange=0'); assert(sends==0)")
assert 'DamageDiagnostics.lua' in manifest['files'] and 'DAMAGE_TESTING.txt' in manifest['files']
print('PASS: dev-only post-combat meter capture, directional candidates, NPC/pet/duel rejection, secret-safe reads, session identity, bounds, report pause, local export and timer cleanup. Native semantics still require live acceptance.')
