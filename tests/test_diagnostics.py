"""Three independent observers; logs do not assert a layer or confirmed PvP."""
from wow_mock import client

SETUP = '''
members={'Alice','Bob','Carol'}; group=false; moved=false; raid=false
function GetBuildInfo() return '1.60.1','70938','test',16001 end
function UnitName(u)
 if u=='player' then return PLAYER end
 if not group then return end
 local n=0
 for _,name in ipairs(members) do
  if name~=PLAYER then n=n+1; if u=='party'..n then return name end end
 end
end
function UnitFullName(u) return UnitName(u),'TestRealm' end
function UnitExists(u) return UnitName(u)~=nil end
function UnitIsPlayer(u) return UnitExists(u) end
function UnitGUID(u) local n=UnitName(u); return n and ('Player-'..n) end
function UnitIsConnected(u) return UnitExists(u) end
function IsInGroup() return group end
function IsInRaid() return raid end
function IsInInstance() return false end
function UnitIsGroupLeader(u) return UnitName(u)=='Alice' end
function UnitInPartyShard(u) return UnitName(u)~='Bob' or moved end
function UnitPhaseReason(u) if UnitName(u)=='Bob' and not moved then return 1 end end
function UnitIsVisible(u) return UnitName(u)~='Bob' or moved end
function UnitDistanceSquared() return 25,true end
function UnitAffectingCombat() return true end
function UnitCanAttack() return false end
function GetEvictionTimeRemaining() return 30 end
Enum.PhaseReason={Sharding=1}
'''

observers = [client(name) for name in ('Alice', 'Bob', 'Carol')]
for lua in observers:
    lua.execute(SETUP)
    lua.execute('''
    assert(not A.DiagnosticActive() and #WarbandPvPDiagnosticsDB.entries==0)
    assert(A.EvidenceStatus():find('confirmedParticipants=unknown',1,true))
    SlashCmdList.WARBANDPVP('layer start trip-1')
    assert(A.DiagnosticActive() and sends==0)
    group=true
    A.OnDiagnosticEvent('GROUP_ROSTER_UPDATE')
    CLOCK=CLOCK+1; A.diagnosticTicker.fn()
    SlashCmdList.WARBANDPVP('layer mark i see alice but not bob')
    local log=A.DiagnosticText()
    assert(log:find('GROUP_ROSTER_UPDATE',1,true) and log:find('phase=Sharding(1)',1,true))
    assert(log:find('visible=false',1,true) and log:find('checked=true',1,true))
    assert(log:find('MANUAL i see alice but not bob',1,true))
    CLOCK=CLOCK+1; A.OnDiagnosticEvent('SHARD_TRANSFER_IMMINENT')
    moved=true; CLOCK=CLOCK+1; A.OnDiagnosticEvent('SHARD_TRANSFER')
    CLOCK=CLOCK+1; A.OnDiagnosticEvent('SHARD_TRANSFER_CANCELLED')
    local n=#WarbandPvPDiagnosticsDB.entries
    A.OnDiagnosticEvent('SHARD_TRANSFER_CANCELLED') -- event burst coalesced
    assert(#WarbandPvPDiagnosticsDB.entries==n)
    assert(A.DiagnosticText():find('SHARD_TRANSFER_CANCELLED',1,true))
    assert(A.DiagnosticText():find('phase=nil visible=true',1,true))
    assert(sends==0 and #A.List()==0) -- capture itself never transmits or creates heat
    ''')

# Restricted values never get stringified/compared as game data or saved verbatim.
guard = observers[0]
guard.execute('''
UnitPhaseReason=function() return 'SECRET' end
UnitGUID=function() return 'SECRET' end
UnitIsVisible=function() error('blocked') end
UnitInPartyShard=nil
SlashCmdList.WARBANDPVP('layer snap restricted')
local log=A.DiagnosticText()
assert(log:find('phase=<secret>',1,true) and log:find('visible=<error>',1,true))
assert(log:find('partyShard=<unavailable>',1,true) and not log:find('SECRET',1,true))
''')

# PvE / PvP / bystander context all remain unattributed; no protected combat reads.
evidence = observers[1]
evidence.execute('''
C_CombatLogSecure={GetCurrentEventInfo=function() error('must never call') end}
C_CombatText={GetCurrentEventInfo=function() error('must never call') end}
C_DamageMeter={GetCombatSessionFromType=function() error('must never call') end}
for _,label in ipairs({'pve','pvp','bystander'}) do
 SlashCmdList.WARBANDPVP('layer mark '..label)
 A.OnDiagnosticEvent('UNIT_COMBAT','player','WOUND','', 'SECRET',1)
 A.OnDiagnosticEvent('UNIT_SPELLCAST_SENT','player','SECRET','SECRET','SECRET')
 A.OnDiagnosticEvent('UNIT_SPELLCAST_SUCCEEDED','player','SECRET','SECRET')
 CLOCK=CLOCK+5; A.diagnosticTicker.fn()
end
local log=A.DiagnosticText()
assert(log:find('attribution=unknown',1,true) and not log:find('SECRET',1,true))
assert(#A.List()==0 and sends==0)
for i=1,1000 do A.OnDiagnosticEvent('UNIT_COMBAT','player','WOUND') end
CLOCK=CLOCK+5; A.diagnosticTicker.fn()
assert(A.DiagnosticText():find('EVIDENCE_DROPPED',1,true))
for i=1,1300 do A.Trace('TEST','row '..i) end
assert(#WarbandPvPDiagnosticsDB.entries==1200 and WarbandPvPDiagnosticsDB.dropped>0)
SlashCmdList.WARBANDPVP('layer export')
assert(A.diagnosticExport.shown and A.diagnosticExport.edit.text:find('dropped=',1,true))
CLOCK=CLOCK+900; A.diagnosticTicker.fn(); assert(not A.DiagnosticActive())
local n=#WarbandPvPDiagnosticsDB.entries
A.OnDiagnosticEvent('SHARD_TRANSFER'); A.Trace('TEST','ignored')
assert(#WarbandPvPDiagnosticsDB.entries==n)
''')

# Capture does not resume after reinitialization; logout stops, existing log retained.
other = observers[2]
other.execute('''
A.OnDiagnosticEvent('PLAYER_LOGOUT'); assert(not A.DiagnosticActive())
local n=#WarbandPvPDiagnosticsDB.entries
A.InitDiagnostics(); assert(#WarbandPvPDiagnosticsDB.entries==n and not A.DiagnosticActive())
SlashCmdList.WARBANDPVP('layer clear'); assert(#WarbandPvPDiagnosticsDB.entries==0)
''')

# Report and presence receipt can be correlated by ID/time in the diagnostic log.
sender, receiver = client('Alice'), client('Bob')
for lua in (sender, receiver):
    lua.execute(SETUP)
    lua.execute("group=true; SlashCmdList.WARBANDPVP('layer start validation'); A.SetPresenceEnabled(true); A.SetTestMode(true)")
sender.execute('A.RunReport()')
receiver.globals().A.OnPresenceMessage('WBP_PRES1', sender.globals().packets[1], 'PARTY', 'Alice-TestRealm')
receiver.globals().A.OnReportMessage('WBP_REPORT1', sender.globals().packets[2], 'GUILD', 'Alice-TestRealm')
receiver.execute('''
local log=A.DiagnosticText()
assert(log:find('PRESENCE_RECEIVE',1,true) and log:find('REPORT_RECEIVE',1,true))
local r=A.List()[1]; A.ShowDetails(r); A.Tooltip(UIParent,r)
assert(A.details.shown)
NOW=NOW+301; CLOCK=CLOCK+301; A.timer.fn()
assert(not A.details.shown and not A.toast.shown and not A.tooltipRecord and #A.List()==0)
''')

print('PASS: three-client diagnostic capture, phase/visibility/transfer snapshots, manual notes, secret/error handling, bounded unattributed evidence, expiry, export, timeout, transport traces and stale report UI cleanup.')
