"""Cooperative scouting only: mocks do not establish real cross-faction delivery."""
from warband_network import Network, get

VISIBLE = r'''
VISIBLE={}; SELF_FACTION='Horde'
local priorName,priorFull,priorExists,priorGuid=UnitName,UnitFullName,UnitExists,UnitGUID
function UnitName(u) if VISIBLE[u] then return VISIBLE[u].name end; return priorName(u) end
function UnitFullName(u) if VISIBLE[u] then return VISIBLE[u].name,'TestRealm' end; return priorFull(u) end
function UnitFactionGroup(u) return VISIBLE[u] and VISIBLE[u].faction or SELF_FACTION end
function UnitExists(u) return VISIBLE[u]~=nil or priorExists(u) end
function UnitIsPlayer(u) return UnitExists(u) end
function UnitIsVisible(u) return VISIBLE[u] and VISIBLE[u].visible~=false or u=='player' end
function UnitGUID(u) return VISIBLE[u] and ('Player-'..VISIBLE[u].name) or priorGuid(u) end
'''


def setup():
    net=Network()
    scout=net.add('Scout One','Friendly'); friend=net.add('Friend Two','Friendly')
    friend.execute('inGuild=false')  # shared report/scouting delivery must reach unguilded users
    enemy=net.add('Enemy Three','Opposing')
    for lua in (scout,friend,enemy):
        lua.execute(VISIBLE)
    enemy.execute("SELF_FACTION='Alliance'; VISIBLE.target={name='Scout One',faction='Horde'}")
    scout.execute("VISIBLE.target={name='Enemy Three',faction='Alliance'}")
    enemy.execute("assert(A.StartWarband('Enemy patrol'))")
    return net,scout,friend,enemy


def packet(lua, kind):
    g=lua.globals()
    return next(g.packets[i] for i in range(g.sends,0,-1)
                if g.sentPrefixes[i]=='WBP_SCOUT1' and g.packets[i].split('\t')[1]==kind)


def check_scouting():
    net,scout,friend,enemy=setup()
    scout.execute('assert(A.Report()); assert(A.List()[1].scout.state=="pending")')
    net.advance(2)
    for lua in (scout,friend):
        lua.execute('''
local r=A.List()[1]
assert(r.scout.state=='known' and r.scout.enemy=='Enemy Three')
assert(r.scout.title=='Enemy patrol' and r.scout.members==1 and r.scout.parties==1)
assert(r.count==0 and r.countUnknown and #A.WarbandList()==0)
assert(A.ScoutSummary(r):find('reported',1,true))
A.ShowDetails(r); A.ShowEnemyScout(r)
assert(A.scouting.panel:IsShown() and not A.details:IsShown())
assert(A.scouting.panel.body.text:find('not live enemy positions',1,true))
A.BackWindow(); assert(A.details:IsShown() and not A.scouting.panel:IsShown())
''')
    assert get(enemy,'#A.List()')==0  # opposite-faction reports never enter the store
    assert len(packet(scout,'S').encode())<=255
    # Repeated / forged relays cannot replace the first snapshot or refresh expiry.
    good=packet(scout,'S'); forged=good.split('\t'); forged[-1]='Forged replacement'
    friend.globals().A.OnScoutMessage('WBP_SCOUT1','\t'.join(forged),'GUILD','Scout One')
    assert get(friend,'A.List()[1].scout.title')=='Enemy patrol'
    before=get(friend,'A.List()[1].scout.expiresAt')
    net.advance(10)
    friend.globals().A.OnScoutMessage('WBP_SCOUT1',good,'GUILD','Scout One')
    assert get(friend,'A.List()[1].scout.expiresAt')==before
    friend.execute('A.ShowEnemyScout(A.List()[1]); A.Tooltip(UIParent,A.List()[1]); assert(A.tooltipRecord)')
    net.advance(80)
    friend.execute('assert(not A.tooltipRecord and not GameTooltip:IsShown())')
    for lua in (scout,friend):
        lua.execute("assert(#A.List()==1 and A.List()[1].scout.state=='expired'); assert(A.ScoutSummary(A.List()[1])=='')")
    # Native report pin still expires normally and closes its scouting details.
    friend.execute('assert(not A.scouting.panel:IsShown()); A.ShowEnemyScout(A.List()[1]); assert(not A.scouting.panel:IsShown())')
    net.advance(211)
    friend.execute('A.Prune(NOW); A.RefreshReportSurfaces(); assert(not A.scouting.panel:IsShown())')


def check_scouting_failures():
    net,scout,friend,enemy=setup()
    scout.execute('assert(A.Report())')
    request=packet(scout,'Q').split('\t')
    nonce=request[2]
    # A well-formed reply from the wrong native sender, faction, route, or request
    # cannot turn a pending report into known affiliation.
    enemy.globals().rq=nonce
    reply=enemy.eval("A.WB.Pack({'1','R',rq,tostring(NOW),'A',A.scopeRuleset,tostring(A.scopeRegion),A.warbands.host.id,A.warbands.session,'1','1','1','forming','Enemy patrol'})")
    fields=reply.split('\t')
    for sender,route in [('Imposter Four','WHISPER'),('Enemy Three','GUILD')]:
        scout.globals().A.OnScoutMessage('WBP_SCOUT1',reply,route,sender)
    for index,value in [(0,'9'),(2,'bad-nonce'),(3,'0'),(4,'H'),(5,'normal'),(6,'99'),
                        (7,'invalid-uuid'),(8,'invalid-session'),(9,'0'),(10,'21'),(11,'5'),
                        (12,'fighting'),(13,'|Hinvalid')]:
        bad=fields.copy(); bad[index]=value
        scout.execute('A.scouting.rates={}; A.scouting.tokens=16; A.scouting.refill=CLOCK')
        scout.globals().A.OnScoutMessage('WBP_SCOUT1','\t'.join(bad),'WHISPER','Enemy Three')
        scout.execute("assert(A.List()[1].scout.state=='pending')")
    scout.execute("assert(A.List()[1].scout.state=='pending')")
    scout.execute('CLOCK=CLOCK+11; A.ScoutTick()')
    scout.execute("assert(A.List()[1].scout.state=='unknown')")
    # No visible requester => no reply, even to a syntactically valid probe.
    enemy.execute('VISIBLE={}')
    enemy.globals().A.OnScoutMessage('WBP_SCOUT1','\t'.join(request),'WHISPER','Scout One')
    assert not any(enemy.globals().sentPrefixes[i]=='WBP_SCOUT1' for i in range(1,enemy.globals().sends+1))
    # Missing/secret enemy identity or visibility sends no scouting query.
    for field,value in [('name',"'SECRET'"),('faction',"'SECRET'"),('visible','false')]:
        n,s,_,_=setup()
        s.execute(f"VISIBLE.target.{field}={value}; assert(A.Report())")
        assert not any(s.globals().sentPrefixes[i]=='WBP_SCOUT1' for i in range(1,s.globals().sends+1))
    # A send accepted by the API may still never arrive across factions.
    n,s,f,e=setup(); e.execute('A.scouting.ready=false'); s.execute('assert(A.Report())')
    n.advance(12)
    s.execute("assert(A.List()[1].scout.state=='unknown'); assert(not next(A.scouting.pending))")
    f.execute('assert(A.List()[1].scout==nil)')
    # The native API may explicitly reject a query, while the guild report succeeds.
    n,s,f,e=setup()
    s.execute('''
local old=C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage=function(prefix,...) if prefix=='WBP_SCOUT1' then return 99 end; return old(prefix,...) end
assert(A.Report()); assert(A.List()[1].scout.state=='unknown')
''')


def check_scouting_order_and_bounds():
    net,scout,friend,enemy=setup()
    scout.execute('assert(A.Report())'); net.advance(2)
    relay=packet(scout,'S')
    report=next(scout.globals().packets[i] for i in range(1,scout.globals().sends+1)
                if scout.globals().sentPrefixes[i]=='WBP_REPORT1')
    late=net.add('Late Four','Friendly'); late.execute(VISIBLE)
    late.globals().A.OnScoutMessage('WBP_SCOUT1',relay,'GUILD','Scout One')
    late.execute('assert(#A.List()==0 and next(A.scouting.orphans))')
    # The same nonce sent by a different reporter cannot attach to this report.
    late.globals().A.OnReportMessage('WBP_REPORT1',report,'GUILD','Wrong Observer')
    late.execute('assert(not A.List()[1].scout)')
    late.globals().A.OnReportMessage('WBP_REPORT1',report,'GUILD','Scout One')
    late.execute("assert(A.records[A.ReportID('Scout One',(...))].scout.state=='known')",relay.split('\t')[2])
    # Memory / per-sender / total budgets remain bounded under hostile orphan traffic.
    late.globals().relay=relay
    late.execute(r'''
for i=1,500 do
 local p=relay:gsub('S\t[^\t]+\t','S\t'..i..'-1-1\t',1)
 A.OnScoutMessage('WBP_SCOUT1',p,'GUILD','Untrusted '..i)
end
local n=0; for _ in pairs(A.scouting.orphans) do n=n+1 end; assert(n<=32)
n=0; for _ in pairs(A.scouting.rates) do n=n+1 end; assert(n<=64)
CLOCK=CLOCK+121; A.ScoutTick(); assert(not next(A.scouting.orphans) and not next(A.scouting.rates))
A.ClearReports(); assert(#A.List()==0)
''')


def check_scouting_member():
    # Any current member can answer; the coordinator need not be visible.
    for expired in (False, True):
        net,scout,friend,enemy=setup()
        member=net.add('Member Four','Opposing'); member.execute(VISIBLE)
        member.execute("SELF_FACTION='Alliance'; VISIBLE.target={name='Scout One',faction='Horde'}; A.SetWarbandsEnabled(true)")
        net.advance(16)
        wid=get(enemy,'A.warbands.host.id')
        assert member.globals().A.JoinWarband(wid)
        net.advance(20)
        member.execute('assert(A.warbands.member and not A.warbands.host)')
        scout.execute("VISIBLE.target={name='Member Four',faction='Alliance'}")
        if expired:
            member.execute('A.warbands.member.untilAt=CLOCK-1')
            # Hold unrelated heartbeat delivery while probing the expired lease.
            scout.execute('assert(A.Report())')
            member.globals().A.OnScoutMessage('WBP_SCOUT1',packet(scout,'Q'),'WHISPER','Scout One')
            assert not any(member.globals().sentPrefixes[i]=='WBP_SCOUT1'
                           for i in range(1,member.globals().sends+1))
        else:
            scout.execute('assert(A.Report())'); net.advance(2)
            scout.execute("assert(A.List()[1].scout.state=='known' and A.List()[1].scout.enemy=='Member Four')")
            friend.execute("assert(A.List()[1].scout.title=='Enemy patrol' and A.List()[1].scout.members==2)")


def check_all_scouting():
    check_scouting(); check_scouting_failures(); check_scouting_order_and_bounds(); check_scouting_member()
