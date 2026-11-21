"""Three real Lua clients stand in for three parties; dummies never become senders."""
from warband_network import Network, say, get


def count(lua, expression):
    return get(lua, '(function() local n=0; for _ in pairs('+expression+') do n=n+1 end; return n end)()')


net=Network()
owner=net.add('Alice One')
bob=net.add('Bob Two', 'B')
carol=net.add('Carol Three', 'C')
observer=net.add('Normal Observer')
report_tester=net.add('Report Tester')
# Can test from one real party, or solo: only the TotalWarcraft feature's roster input changes.
net.party('Alice One',['Alice One','Bob Two','Carol Three'])
for lua in (observer,report_tester):
    say(lua,'on')
say(report_tester,'test on')
assert not owner.globals().A.SetWarbandSimulation('5')[0]
assert not get(owner,'A.warbands.simulationCount')
assert not get(owner,'A.warbands.enabled')
assert get(owner,'sends') == 0


def remote(target,verb):
    say(owner,f'remote {target} {verb}')
    net.advance(6)  # normal five-second control throttle remains in force


remote('Bob Two','warband-five')  # installation alone grants no controller access
assert not get(bob,'A.warbands.simulationCount')
for lua in (bob,carol):
    say(lua,'control allow Alice One')
remote('Bob Two','warband-five')  # authorized but test mode must also be ON
assert not get(bob,'A.warbands.simulationCount')
assert any('Test mode must be ON' in s for s in owner.globals().messages.values())
for target in ('Bob Two','Carol Three'):
    remote(target,'test-on')
    remote(target,'warband-five')
    assert get(net.clients[target],'A.warbands.simulationCount') == 5
say(owner,'test on')
say(owner,'simulate 5')
say(owner,'layer start three-client-test')
say(owner,'start Three Client Patrol')
wid=get(owner,'A.warbands.host.id')
net.advance(2)
for lua in (observer,report_tester):
    assert get(lua,'#A.WarbandList()') == 0  # both explicit opt-ins required
for target in ('Bob Two','Carol Three'):
    remote(target,'warband-watch')  # subscription is to authorized controller only
net.advance(31)
for lua in (bob,carol):
    assert get(lua,'A.WarbandList()[1].simulated')
    assert get(lua,'A.WarbandList()[1].id') == wid
for target in ('Bob Two','Carol Three'):
    remote(target,'warband-join')
    assert get(net.clients[target],'A.warbands.member.id') == wid
net.advance(35)
for lua in (owner,bob,carol):
    assert get(lua,'#PARTY') == 3
    assert get(lua,'nativeLeader') == 'Alice One'
    assert get(lua,'#invited') == 0
    assert not get(lua,'RAID')
    assert get(lua,'A.WarbandList()[1].count') == 3  # never 15 invented clients
    assert count(lua,'A.WarbandList()[1].groups') == 3
    for slot in range(1,4):
        assert get(lua,f'A.WarbandList()[1].groups[{slot}].count') == 5
    summary=get(lua,'A.WarbandCountText(A.WarbandList()[1])')
    assert '3' in summary and '15 slots (12 dummy)' in summary,summary
    lua.execute('A.ShowWarbandDetails(A.WarbandList()[1]); A.ShowWarbands()')
    assert '[TEST]' in get(lua,'A.warbands.details.title.text')
    assert 'dummy' in get(lua,'A.warbands.details.body.text')
assert count(owner,'A.warbands.host.members') == 3
assert get(bob,'A.warbands.member.slot') == 2
assert get(carol,'A.warbands.member.slot') == 3
assert not bob.globals().A.InviteWarbandMember('Carol Three')[0]
assert 'Dummy party' in get(bob,'A.WarbandArrival(A.WarbandList()[1])')
assert not get(owner,'A.warbands.invites["bob-two"]')

# Real host movement drives each fixture; no invented locations or client identities.
bob.execute('MAP=2; X=.6; Y=.4')
carol.execute('MAP=3; X=.7; Y=.2')
net.advance(35)
for lua in (owner,bob,carol):
    assert get(lua,'A.WarbandList()[1].groups[2].mapID') == 2
    assert get(lua,'A.WarbandList()[1].groups[3].mapID') == 3
    assert get(lua,'#A.List()') == 0
    assert get(lua,'#A.PresenceList()') == 0
    for i,prefix in lua.globals().sentPrefixes.items():
        assert prefix in ('WBP_WBT1','WBP_CTL1'),prefix
        target=lua.globals().sentTargets[i]
        assert not target or target in net.clients,target
owner.execute('WorldMapFrame:SetMapID(2)')
assert get(owner,"(function() for _,p in ipairs(WorldMapFrame.pool) do if p.active and p.group and p.group.slot==2 then return p.warband.simulated end end end)()")

# Changing dummy count preserves the UUID and real membership, then propagates.
say(bob,'simulate 3')
net.advance(35)
assert get(bob,'A.warbands.member.id') == wid
assert get(owner,'A.WarbandList()[1].groups[2].count') == 3
assert '13 slots (10 dummy)' in get(owner,'A.WarbandCountText(A.WarbandList()[1])')
for arg in ('0','6','-1','nan','3.5','5\textra'):
    assert not bob.globals().A.SetWarbandSimulation(arg)[0]
assert get(bob,'A.warbands.simulationCount') == 3

# The live and test transports cannot mutate each other's records or memberships.
live=net.add('Live Organizer')
say(live,'start Live Patrol')
net.advance(2)
assert get(observer,'A.WarbandList()[1].title') == 'Live Patrol'
assert get(owner,'#A.WarbandList()') == 1
assert get(owner,'A.WarbandList()[1].id') == wid
live_id=get(live,'A.warbands.host.id')
say(live,'test on')
assert not live.globals().A.SetWarbandSimulation('5')[0]
assert get(live,'A.warbands.host.id') == live_id  # no silent destruction of live state

# Normal OFF/revocation clears test state and only sends test-prefix withdrawals.
before=get(carol,'sends')
say(carol,'control off')
assert not get(carol,'A.testMode')
assert not get(carol,'A.warbands.simulationCount')
assert not get(carol,'A.warbands.member')
assert not get(carol,'A.warbands.enabled')
assert get(carol,'#A.WarbandList()') == 0
net.advance(35)
assert not get(owner,'A.warbands.host.members["carol-three"]')
assert not get(owner,'A.WarbandList()[1].groups[3]')
for i in range(before+1,get(carol,'sends')+1):
    assert carol.globals().sentPrefixes[i] == 'WBP_WBT1'
remote('Carol Three','warband-five')
assert not get(carol,'A.warbands.simulationCount')

# Test-off on the organizer withdraws the fixture, not a live listing.
old_ad=next(owner.globals().packets[i] for i in range(get(owner,'sends'),0,-1)
            if owner.globals().sentPrefixes[i]=='WBP_WBT1' and owner.globals().packets[i].startswith('1\tA\t'))
say(owner,'test off')
net.advance(8)
assert not get(owner,'A.warbands.host')
assert not get(owner,'A.warbands.simulationCount')
assert not get(bob,'A.warbands.member')
assert get(bob,'#A.WarbandList()') == 0
assert get(observer,'A.WarbandList()[1].id') == live_id
# END history survives switching modes, so replay cannot resurrect a test listing.
say(bob,'simulate off')
say(bob,'simulate 5')
net.advance(1)
bob.globals().A.OnWarbandMessage('WBP_WBT1',old_ad,'GUILD','Alice One')
assert get(bob,'#A.WarbandList()') == 0

# Reload/default initialization does not persist or restore fake-party settings.
fresh=net.add('Reloaded Tester')
assert not get(fresh,'A.testMode') and not get(fresh,'A.warbands.simulationCount')
assert not get(fresh,'A.db.simulationCount')
print('PASS: three real clients / 15 simulated slots, separate test transport, test opt-in, authorized remote setup/join, real positions, dummy labels, no native invites or fake senders, count updates, live isolation, revocation and terminal replay protection.')
