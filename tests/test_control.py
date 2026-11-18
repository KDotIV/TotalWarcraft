"""Remote in-game test CLI: explicit session authorization, fixed commands, no real reports."""
from wow_mock import client

owner, peer = client('Owner One'), client('Tester Two')


def tick(lua, seconds=5):
    lua.execute(f'CLOCK=CLOCK+{seconds}; NOW=NOW+{seconds}')


def request(verb, target='Tester Two'):
    owner.globals().A.RemoteCommand(f'{target} {verb}')
    return owner.globals().packets[owner.globals().sends]


def deliver(packet, sender='Owner One', receiver=None, prefix='CTA_CTL1', route='WHISPER'):
    receiver = peer if receiver is None else receiver
    receiver.globals().A.OnControlMessage(prefix, packet, route, sender)


assert owner.globals().sends == peer.globals().sends == 0
packet = request('test-on')
assert owner.globals().sentTargets[1] == 'Tester Two'
deliver(packet)  # install alone does not authorize a remote controller
peer.execute('assert(not A.testMode and sends==0)')
peer.execute("SlashCmdList.CALLTOARMS('control allow Owner One')")
deliver(packet, sender='Intruder')
peer.execute('assert(not A.testMode and sends==0)')
deliver(packet)
peer.execute('assert(A.testMode and sends==1 and sentPrefixes[1]=="CTA_CTL1")')
ack = peer.globals().packets[1]
before = len(owner.globals().messages)
deliver(ack, sender='Tester Wrong', receiver=owner)
deliver(ack.replace('\tA\t', '\tA\tbad', 1), sender='Tester Two', receiver=owner)
assert len(owner.globals().messages) == before
deliver(ack, sender='Tester Two', receiver=owner)
owner.execute("assert(messages[#messages]:find('OK',1,true))")
before = len(owner.globals().messages)
deliver(ack, sender='Tester Two', receiver=owner)
assert len(owner.globals().messages) == before  # replayed ACK ignored

# A replayed mutation may not run again; sender/route/scope/shape checks are strict.
peer.execute('A.SetTestMode(false)')
tick(peer)
deliver(packet)
peer.execute('assert(not A.testMode and sends==1)')
tick(owner)
packet = request('test-on')
fields = packet.split('\t')
for index, value in [(0, '2'), (3, '0'), (4, 'A'), (5, 'rppvp'), (6, '2'), (7, 'run-lua')]:
    bad = fields.copy(); bad[index] = value
    deliver('\t'.join(bad))
for bad in (packet + '\textra', 'x' * 256, 'SECRET'):
    deliver(bad)
for route in ('GUILD', 'PARTY', 'RAID'):
    deliver(packet, route=route)
peer.execute('assert(not A.testMode and sends==1)')
deliver(packet, sender='Owner-One')  # known two-part separator variant
peer.execute('assert(A.testMode and sends==2)')

# Controlled reports always carry simulated mode; normal remote reports cannot run.
tick(owner); tick(peer)
packet = request('report')
deliver(packet)
peer.execute('''
assert(sends==4 and sentPrefixes[3]=='CTA_REPORT1' and sentRoutes[3]=='GUILD')
assert(packets[3]:sub(1,3)=='1\tT')
assert(A.List()[1].test and A.List()[1].kind=='report')
''')
tick(owner); tick(peer)
deliver(request('test-off'))
peer.execute('assert(not A.testMode and #A.List()==0)')
tick(owner); tick(peer)
count = peer.globals().sends
deliver(request('report'))
peer.execute(f'assert(sends=={count + 1} and #A.List()==0)')  # failure reply only
assert '\t0\t' in peer.globals().packets[peer.globals().sends]

# Capture actions are bounded local commands, not remote Lua execution/export.
for verb in ('capture-start', 'snapshot', 'capture-stop'):
    tick(owner); tick(peer); deliver(request(verb))
peer.execute("assert(not A.DiagnosticActive() and A.DiagnosticText():find('CONTROL_REQUEST',1,true))")
peer.execute("SlashCmdList.CALLTOARMS('control off'); assert(not A.testMode and not A.presenceEnabled)")
tick(owner); tick(peer); count = peer.globals().sends
deliver(request('test-on'))
peer.execute(f'assert(not A.testMode and sends=={count})')

# Authorization does not survive login initialization; exact surname matters.
peer.execute("A.ControlCommand('allow Owner One'); A.InitControl()")
tick(owner); tick(peer); deliver(request('test-on'))
peer.execute('assert(not A.testMode)')
peer.execute("A.ControlCommand('allow Owner Other')")
tick(owner); tick(peer); deliver(request('test-on'))
peer.execute('assert(not A.testMode)')

# Failed sends, cooldown and invalid commands produce no accidental traffic.
failed = client('Failure')
failed.execute('''
sendFailure=true; A.RemoteCommand('Tester Two status'); assert(sends==0 and attempts==1)
sendFailure=false; A.RemoteCommand('Tester Two status'); assert(sends==0 and attempts==1)
CLOCK=CLOCK+5; A.RemoteCommand('Tester Two status'); assert(sends==1)
A.RemoteCommand('Tester Two arbitrary-lua'); assert(sends==1)
''')

# A lost reply expires without retrying or executing on the wrong target.
timeout = client('Owner One')
timeout.execute('''
C_Timer.NewTimer=function(delay,fn) timeoutDelay=delay; timeoutCallback=fn end
SlashCmdList.CALLTOARMS('remote Tester Two status')
assert(timeoutDelay==30 and sentTargets[1]=='Tester Two')
CLOCK=CLOCK+30; NOW=NOW+30; timeoutCallback()
assert(sends==1 and messages[#messages]:find('No reply',1,true))
''')
late_ack = '\t'.join(['1', 'A', timeout.globals().packets[1].split('\t')[2],
                      str(timeout.globals().NOW), '1', 'late'])
before = len(timeout.globals().messages)
deliver(late_ack, sender='Tester Two', receiver=timeout)
assert len(timeout.globals().messages) == before

# Presence toggles only addon state; the real flag APIs are never invoked.
owner, peer = client('Owner One'), client('Tester Two')
peer.execute('''
A.ControlCommand('allow Owner One')
function TogglePVP() error('Remote CLI must not change game PvP flags') end
''')
deliver(request('presence-on'))
peer.execute('assert(A.presenceEnabled and sends==1 and sentPrefixes[1]=="CTA_CTL1")')
tick(owner); tick(peer); deliver(request('status'))
assert 'presence=true' in peer.globals().packets[2]
tick(owner); tick(peer); deliver(request('presence-off'))
peer.execute('assert(not A.presenceEnabled)')
tick(owner); tick(peer); deliver(request('test-on'))
peer.execute('A.adapter=function() error("Custom transport must not be called") end')
tick(owner); tick(peer); deliver(request('report'))
assert '\t0\tRemote reports require' in peer.globals().packets[peer.globals().sends]
peer.execute('A.adapter=A.GuildSend; inGuild=false')
tick(owner); tick(peer); deliver(request('report'))
peer.execute('assert(#A.List()==0 and sentPrefixes[sends]=="CTA_CTL1")')
assert '\t0\t' in peer.globals().packets[peer.globals().sends]

# Sender realm suffixes must be exact or the known local realm, never arbitrary.
owner, peer = client('Owner One'), client('Tester Two')
peer.execute("A.ControlCommand('allow Owner One')")
packet = request('test-on')
deliver(packet, sender='Owner One-OtherRealm')
peer.execute('assert(not A.testMode and sends==0)')
deliver(packet, sender='Owner One-TestRealm')
peer.execute('assert(A.testMode and sends==1)')
print('PASS: remote CLI authorization/revocation, sender/surname/scope/route checks, replay protection, fixed commands, simulated-only reports, captures, replies, timeouts, failed sends and throttling.')
