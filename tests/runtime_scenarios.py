"""Exercise real timer registration/cancellation, rather than manually ticking modules."""
from auto_report_scenarios import SETUP
from warband_network import WORLD, Network


def check_runtime(factory):
    # Full network flow driven solely by registered timers. This catches missing
    # wakeups that manual calls to WarbandTick/ScoutTick would hide.
    net = Network(scheduled=True, factory=factory)
    host, peer = net.add('Timer Host'), net.add('Timer Peer')
    watcher = net.add('Timer Watcher', 'Other guild')
    net.party('Timer Host', ['Timer Host', 'Host Helper'])
    net.party('Timer Peer', ['Timer Peer', 'Peer Helper'])
    host.execute("assert(A.StartWarband('Scheduled patrol'))")
    peer.execute('A.SetWarbandsEnabled(true)')
    watcher.execute("assert(A.WatchWarband('Timer Host'))")
    net.advance(20)
    peer.execute('assert(A.JoinWarband(A.WarbandList()[1].id))')
    net.advance(150)
    peer.execute('assert(A.warbands.member and A.warbands.member.slot==2)')
    watcher.execute('assert(#A.WarbandList()==1 and A.WarbandList()[1].count==2)')
    host.execute('A.SetWarbandsEnabled(false)')
    net.advance(2)
    peer.execute('assert(not A.warbands.member and #A.WarbandList()==0); A.SetWarbandsEnabled(false)')
    watcher.execute('assert(#A.WarbandList()==0); A.SetWarbandsEnabled(false)')
    net.advance(2)
    for lua in (host, peer, watcher):
        lua.execute('assert(activeTimers()==0)')

    lua = factory('Runtime Tester')
    lua.execute('''
assert(activeTimers()==0 and not A.warbands.timer and not A.scouting.timer)
assert(advanceTimers(300)==0 and sends==0)
nativeChecks=0
local native=A.WarbandNativeInfo
A.WarbandNativeInfo=function(...) nativeChecks=nativeChecks+1; return native(...) end
A.SetWarbandsEnabled(true)
assert(advanceTimers(3)==3 and nativeChecks==0 and sends==0)
A.SetWarbandsEnabled(false)
assert(activeTimers()==0 and advanceTimers(10)==0)
-- Terminal messages still drain after discovery has stopped; failures obey the
-- same bounded rate and do not leave a retry timer behind.
for _,fail in ipairs({false,true}) do
 sendFailure=fail
 local before=attempts
 for i=1,3 do
  assert(A.QueueWarbandWhisper(A.WB.Request('X',nil,nil,A.WB.UUID()),'Peer Reader','END:'..i))
 end
 assert(advanceTimers(1)==3 and attempts-before==3)
 assert(not next(A.warbands.queue) and activeTimers()==0)
end
sendFailure=false
-- Pending native cleanup must time out even with discovery disabled.
A.finder.operation={kind='remove',at=CLOCK}
A.SetWarbandsEnabled(false)
assert(A.warbands.timer)
advanceTimers(12)
assert(not A.finder.operation and activeTimers()==0)
''')

    lua = factory('Runtime Host')
    lua.execute('''
A.db.finderEnabled=false
assert(A.StartWarband('Timer lifecycle'))
advanceTimers(35)
local snapshots=0
for _,p in ipairs(packets) do if p:sub(1,3)=='1\\tA' then snapshots=snapshots+1 end end
assert(snapshots==2 and A.warbands.host and not next(A.warbands.queue))
A.SetWarbandsEnabled(false); advanceTimers(1)
local ended=false
for _,p in ipairs(packets) do if p:sub(1,3)=='1\\tE' then ended=true end end
assert(ended and not A.warbands.host and activeTimers()==0)
''')

    # Genuine message-handler paths wake scouting, and timers expire pending
    # requests/rate entries without further input. Clearing reports stops expiry.
    lua = factory('Runtime Scout')
    lua.execute(SETUP)
    lua.execute('''
assert(A.Report()); local r=A.List()[1]
assert(r.scout.state=='pending' and A.scouting.timer)
advanceTimers(11); assert(r.scout.state=='unknown' and not next(A.scouting.pending))
advanceTimers(20); assert(not A.scouting.timer)
A.ClearReports(); assert(not A.timer and activeTimers()==0)
local request=A.WB.Pack({'1','Q',A.WB.UUID(),tostring(NOW),'A',A.scopeRuleset,tostring(A.scopeRegion)})
A.OnScoutMessage('WBP_SCOUT1',request,'WHISPER','Enemy Player')
assert(A.scouting.timer)
advanceTimers(121); assert(not next(A.scouting.rates) and not A.scouting.timer and activeTimers()==0)
''')

    for automatic in (False, True):
        lua = factory('Runtime Reporter')
        lua.execute(SETUP)
        lua.globals().automatic = automatic
        lua.execute('''
local send=A.adapter; local manual
A.adapter=function(r) manual=r.manual; return send(r) end
rows={damage('Enemy Person',10)}; fight()
if automatic then peace() else assert(A.Report()); peace() end
assert(manual==not automatic and not A.autoReports.timer and reportCount()==1)
advanceTimers(130); assert(reportCount()==1 and not A.autoReports.timer)
fight(); peace(); assert(reportCount()==2)
''')

    # Open UI must follow incoming locations, expiry and native roster removal.
    lua = factory('Runtime Receiver')
    lua.execute(WORLD)
    lua.execute('''
PARTY={PLAYER,'Runtime Sender'}; nativeLeader=PLAYER
A.SetPresenceEnabled(true); A.ShowPresence()
local function receive()
 local packet=table.concat({'1',NOW,'1','2500','7500','H',A.scopeRuleset,tostring(A.scopeRegion),'1','1'},'\\t')
 A.OnPresenceMessage('WBP_PRES1',packet,'PARTY','Runtime Sender-TestRealm')
end
receive(); assert(A.presencePanel.body.text:find('RuntimeSender-TestRealm',1,true))
advanceTimers(40)
assert(not A.presencePanel.body.text:find('RuntimeSender-TestRealm',1,true))
receive(); assert(A.presencePanel.body.text:find('RuntimeSender-TestRealm',1,true))
A.ShowHome(); assert(A.home.status.text:find('1 sharing peers',1,true))
advanceTimers(40); assert(A.home.status.text:find('0 sharing peers',1,true))
receive(); A.ShowPresence(); assert(A.presencePanel.body.text:find('RuntimeSender-TestRealm',1,true))
PARTY={}
for _,f in ipairs(frames) do
 if f.events.GROUP_ROSTER_UPDATE and f.scripts.OnEvent then f.scripts.OnEvent(f,'GROUP_ROSTER_UPDATE') end
end
assert(not A.presencePanel.body.text:find('RuntimeSender-TestRealm',1,true))
A.SetPresenceEnabled(false); assert(activeTimers()==0)
''')
