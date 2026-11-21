"""Independent-client tests of production warbands; no live WoW actions."""
from warband_network import Network, say, get
import uuid

net = Network()
alice = net.add('Alice One')
bob = net.add('Bob Two')
carol = net.add('Carol Three')
dave = net.add('Dave Four', 'B')
eve = net.add('Eve Five')
net.party('Alice One', ['Alice One', 'Helper One', 'Helper Two', 'Helper Three', 'Helper Four'])
net.party('Bob Two', ['Bob Two', 'Carol Three'])
say(alice, 'start Ashenvale Patrol')
wid = get(alice, 'A.warbands.host.id')
assert uuid.UUID(wid).version == 4
assert uuid.UUID(get(alice, 'A.warbands.session')).version == 4
assert wid != get(alice, 'A.warbands.session')
net.advance(2)
assert get(bob, '#A.WarbandList()') == 0  # explicit discovery opt-in
for lua in (bob, carol, eve):
    say(lua, 'on')
say(dave, 'watch Alice One')  # cross-guild, named subscription
net.advance(16)
for lua in (bob, carol, dave, eve):
    assert get(lua, '#A.WarbandList()') == 1
    assert get(lua, 'A.WarbandList()[1].id') == wid
say(bob, f'join {wid}')
net.advance(3)
assert get(bob, 'A.warbands.member.slot') == 2  # separate existing normal party
assert get(bob, 'A.warbands.member.id') == wid
say(carol, f'join {wid}')
net.advance(3)
assert get(carol, 'A.warbands.member.slot') == 2
say(dave, f'join {wid}')
net.advance(3)
assert get(dave, 'A.warbands.member.slot') == 2
assert get(dave, '#invited') == 0  # TotalWarcraft join never auto-accepts/auto-invites
assert get(bob, 'A.warbands.invites["dave-four"] ~= nil')
say(bob, 'invite Dave Four')
assert get(bob, 'invited[1]') == 'Dave Four'
net.party('Bob Two', ['Bob Two', 'Carol Three', 'Dave Four'])  # simulated USER acceptance
bob.execute('MAP=2; X=.4; Y=.3')
net.advance(45)
for lua in (bob, carol, dave):
    assert get(lua, 'A.warbands.member ~= nil')  # membership lease renewed
    assert get(lua, 'A.WarbandList()[1].groups[2].mapID') == 2
    assert get(lua, 'A.WarbandList()[1].groups[2].count') == 3
    assert get(lua, '#A.List()') == 0  # never generates reports/heat
assert 'unverified' in get(dave, 'A.WarbandArrival(A.WarbandList()[1])')

# A public observer sees one normal-sized banner; members also see group dots.
say(eve, 'show')
eve.execute('''
local r=A.WarbandList()[1]; A.ShowWarbandDetails(r)
assert(A.warbands.details.shown and not A.warbands.panel.shown)
local banner=0
for _,p in ipairs(WorldMapFrame.pool) do
 if p.active and p.template=='WarbandPvPWarbandPinTemplate' then
  banner=banner+1; assert(p.w==28 and p.h==28); p:OnMouseEnter(); p:OnMouseClickAction('LeftButton')
 end
 assert(not (p.active and p.template=='WarbandPvPWarbandGroupPinTemplate'))
end
assert(banner==1)
''')
dave.execute('WorldMapFrame:SetMapID(2)')
assert get(dave, "(function() for _,p in ipairs(WorldMapFrame.pool) do if p.active and p.group and p.group.slot==2 then return true end end end)()")

# Coordinator-only updates: another guild sender cannot overwrite the UUID.
latest = next(alice.globals().packets[i] for i in range(alice.globals().sends, 0, -1)
              if alice.globals().packets[i].startswith('1\tA\t'))
before = get(bob, 'A.WarbandList()[1].updatedAt')
fields = latest.split('\t')
fields[4] = str(int(fields[4]) + 100)
fields[-1] = 'Forged title'
bob.globals().A.OnWarbandMessage('WBP_WB1', '\t'.join(fields), 'GUILD', 'Intruder Name')
assert get(bob, 'A.WarbandList()[1].title') == 'Ashenvale Patrol'
for index, value in [(0,'2'),(2,'not-a-uuid'),(3,str(uuid.uuid4())),(4,'0'),(5,'0'),
                     (6,str(net.base+999999)),(7,'A'),(8,'rppvp'),(9,'99'),
                     (11,'nan'),(12,'10001'),(14,'fighting'),(15,'yes'),(17,'1000')]:
    bad = latest.split('\t'); bad[index] = value
    bob.globals().A.OnWarbandMessage('WBP_WB1', '\t'.join(bad), 'GUILD', 'Alice One')
    net.advance(.5)
assert get(bob, 'A.WarbandList()[1].title') == 'Ashenvale Patrol'
bob.globals().A.OnWarbandMessage('WBP_WB1', latest, 'RAID', 'Alice One')
bob.globals().A.OnWarbandMessage('WBP_WB1', 'x'*256, 'GUILD', 'Alice One')
bob.globals().A.OnWarbandMessage('WBP_WB1', 'SECRET', 'GUILD', 'Alice One')

# Member observations cannot be sent by another identity or an old session.
update = next(dave.globals().packets[i] for i in range(dave.globals().sends, 0, -1)
              if dave.globals().packets[i].startswith('1\tU\t'))
u = update.split('\t'); u[5] = str(int(u[5])+100); u[12] = 'Intruder Name'
alice.globals().A.OnWarbandMessage('WBP_WB1','\t'.join(u),'WHISPER','Eve Five')
assert get(alice, 'A.warbands.host.members["dave-four"].nativeHost') == 'Bob Two'

# A new membership has a new incarnation; old leave/update traffic cannot mutate it.
old_member_session = get(dave, 'A.warbands.member.memberSession')
say(dave, 'leave')
net.advance(6)
old_leave = next(dave.globals().packets[i] for i in range(dave.globals().sends, 0, -1)
                 if dave.globals().packets[i].startswith('1\tL\t'))
say(dave, f'join {wid}')
net.advance(3)
assert get(dave, 'A.warbands.member.memberSession') != old_member_session
new_member_session = get(alice, 'A.warbands.host.members["dave-four"].session')
alice.globals().A.OnWarbandMessage('WBP_WB1', old_leave, 'WHISPER', 'Dave Four')
alice.globals().A.OnWarbandMessage('WBP_WB1', '\t'.join(u), 'WHISPER', 'Dave Four')
assert get(alice, 'A.warbands.host.members["dave-four"].session') == new_member_session
assert get(alice, 'A.warbands.host.members["dave-four"].nativeHost') == 'Bob Two'
net.advance(6)
seq = get(dave, 'A.warbands.member.seq')
say(dave, f'join {wid}')  # invitation retry must preserve the update stream
net.advance(3)
assert get(dave, 'A.warbands.member.seq') >= seq

# Lost terminal packets still expire; no stale UI survives.
lonely = net.add('Late Observer', 'Z')
say(lonely, 'on')
lonely.globals().A.OnWarbandMessage('WBP_WB1',latest,'GUILD','Alice One')
assert get(lonely, '#A.WarbandList()') == 1
lonely.execute('A.ShowWarbandDetails(A.WarbandList()[1]); NOW=NOW+96; CLOCK=CLOCK+96; A.WarbandTick()')
assert get(lonely, '#A.WarbandList()') == 0
assert not get(lonely, 'A.warbands.details.shown')
del net.clients['Late Observer']

say(alice, 'stop')
net.advance(10)
for lua in (bob, carol, dave, eve):
    assert get(lua, '#A.WarbandList()') == 0
    assert not get(lua, 'A.warbands.member')
    lua.globals().A.OnWarbandMessage('WBP_WB1',latest,'GUILD','Alice One')
    assert get(lua, '#A.WarbandList()') == 0  # END tombstone prevents replay revival

# UUIDs remain distinct across many creations, reinitialization, and equal clocks.
ids = {alice.globals().A.WB.UUID() for _ in range(2000)}
assert len(ids) == 2000 and all(uuid.UUID(x).version == 4 for x in ids)
assert not ids.intersection(bob.globals().A.WB.UUID() for _ in range(2000))
session = get(alice,'A.warbands.session')
alice.execute('A.InitWarbands()')
assert get(alice,'A.warbands.session') != session

# Four existing full normal parties can share a UUID (including their 20 TotalWarcraft users).
big = Network()
parties = [[f'{family} {suffix}' for suffix in ('One','Two','Three','Four','Five')]
           for family in ('Alpha','Bravo','Charlie','Delta')]
for names in parties:
    for name in names:
        say(big.add(name), 'on')
    big.party(names[0], names)
root = big.clients['Alpha One']
say(root, 'start Twenty Member Test')
big.advance(2)
full_id = get(root,'A.warbands.host.id')
for slot, names in enumerate(parties, 1):
    for name in names:
        if name == 'Alpha One':
            continue
        lua = big.clients[name]
        say(lua, f'join {full_id}')
        big.advance(10)
        assert get(lua, 'A.warbands.member'), (name, get(lua, 'A.warbands.join'), get(root, 'A.warbands.host.members[A.WB.Key("'+name+'")]'))
        assert get(lua, 'A.warbands.member.slot') == slot
big.advance(35)
assert get(root, '(function() local n=0; for _ in pairs(A.warbands.host.members) do n=n+1 end; return n end)()') == 20
for name, lua in big.clients.items():
    if name != 'Alpha One':
        assert get(lua, 'A.warbands.member')
        assert get(lua, 'A.WarbandList()[1].count') == 20
extra = big.add('Overflow Recruit')
say(extra, 'on')
big.advance(31)
say(extra, f'join {full_id}')
big.advance(4)
assert not get(extra, 'A.warbands.member')
assert not get(extra, 'A.warbands.join')
assert get(root, '#invited') == 0

# Maximum members plus eight cross-guild listeners remain live while all hosts move.
listeners=[]
for i in range(8):
    listener=big.add(f'Listener Number{i}', 'B')
    say(listener, 'watch Alpha One')
    listeners.append(listener)
for t in range(180):
    for names in parties:
        big.clients[names[0]].globals().X=.2+(t%40)/100
    big.advance(1)
    assert get(root,'(function() local n=0; for _ in pairs(A.warbands.queue) do n=n+1 end; return n end)()') <= 96
for names in parties:
    for name in names:
        if name!='Alpha One':
            assert get(big.clients[name],'A.warbands.member'), name
for listener in listeners:
    assert get(listener,'A.WarbandList()[1].count') == 20
    assert get(listener,'A.WarbandList()[1].groups[4]')

# A disappearing group host retires that group. A coordinator raid ends the warband.
departing = big.clients['Bravo One']
say(departing, 'leave')
big.advance(35)
assert get(root,'A.warbands.host.groups[2].retired')
assert not get(big.clients['Bravo Two'], 'A.WarbandList()[1].groups[2]')
assert 'unavailable' in get(big.clients['Bravo Two'], 'A.WarbandArrival(A.WarbandList()[1])')
root.execute('RAID=true')
big.advance(16)
assert not get(root, 'A.warbands.host')
for lua in big.clients.values():
    assert get(lua, '#A.WarbandList()') == 0

# Cancellation before acknowledgement cannot be undone by the old join request.
cancel = Network()
host, recruit = cancel.add('Host One'), cancel.add('Recruit Two')
say(recruit, 'on')
say(host, 'start Cancel Test')
cancel.advance(2)
cid = get(host,'A.warbands.host.id')
say(recruit, f'join {cid}')
assert not recruit.globals().A.StartWarband('Conflicting listing')[0]
join_packet = next(recruit.globals().packets[i] for i in range(recruit.globals().sends, 0, -1)
                   if recruit.globals().packets[i].startswith('1\tJ\t'))
say(recruit, 'leave')
cancel.advance(6)
host.globals().A.OnWarbandMessage('WBP_WB1', join_packet, 'WHISPER', 'Recruit Two')
cancel.advance(2)
assert not get(recruit, 'A.warbands.member')
assert not get(host, 'A.warbands.host.members["recruit-two"]')

# Full supported names, counters and scope still fit one native addon message.
host.execute('''
local P=A.WB; local id=P.UUID(); local name=string.rep('a',31)..' '..string.rep('b',32)
local u={'1','U',id,id,id,'2147483647','1794240000','1794240090','H','hardcore','99','leader',name,'5','100000','10000','10000'}
assert(P.Pack(u) and #P.Pack(u)<=255)
local j={'1','J',id,id,id,'1794240000','H','hardcore','99','leader',name,'5',id}
assert(P.Pack(j) and #P.Pack(j)<=255)
''')

# Duplicate snapshots do not extend expiry; unobserved prior sessions cannot roll back.
old = next(host.globals().packets[i] for i in range(host.globals().sends, 0, -1)
           if host.globals().packets[i].startswith('1\tA\t'))
expires = get(recruit, 'A.WarbandList()[1].expiresAt')
recruit.globals().A.OnWarbandMessage('WBP_WB1', old, 'GUILD', 'Host One')
assert get(recruit, 'A.WarbandList()[1].expiresAt') == expires
bad = old.split('\t'); bad[2] = str(uuid.uuid4()); bad[3] = str(uuid.uuid4())
recruit.globals().A.OnWarbandMessage('WBP_WB1', '\t'.join(bad), 'GUILD', 'Host One')
assert get(recruit, 'A.WarbandList()[1].id') == cid

# Failed sends obey the same attempt budget as successful sends.
host.execute('''
local W=A.warbands
W.queue={}; attempts=0
C_ChatInfo.SendAddonMessage=function() attempts=attempts+1; return false end
for i=1,20 do W.queue[tostring(i)]={packet='1\\tE',prefix=A.WB.PREFIX,route='GUILD',at=GetTime(),order=GetTime(),priority=0,key=tostring(i)} end
for i=1,100 do A.WarbandTick() end
assert(attempts<=1)
for i=1,4 do CLOCK=CLOCK+.25; A.WarbandTick() end
assert(attempts<=5)
''')

print('PASS: multi-client warbands, 4 parties/20 members, opt-in routes, native invite separation, leases, map pins, authority/session/replay validation, cancel/retry/leave, malformed packets, packet budgets, failed-send throttling, expiry and raid cleanup.')
