"""Real report path over mocked CHANNEL; also run against the compiled Release."""
import sys
from pathlib import Path
from lupa.lua51 import LuaRuntime
from wow_mock import BOOT, ROOT
from auto_report_scenarios import SETUP

sys.path.insert(0, str(ROOT.parent / 'tools'))
from build_addon import build

NAME = 'TotalWarcraftReportComms'


def factory(root, name='Observer One', setup=''):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(BOOT)
    lua.globals().PLAYER = name
    for line in (root / 'WarbandPvP.toc').read_text().splitlines():
        if line.endswith('.lua'):
            lua.execute('assert(loadstring(...))("WarbandPvP",A)', (root / line).read_text())
    lua.execute("emitEvent('ADDON_LOADED','WarbandPvP')")
    lua.execute(setup)
    lua.execute("emitEvent('PLAYER_LOGIN')")
    return lua


def deliver(lua, payload, sender, route='CHANNEL', index=None, name=NAME, prefix='WBP_REPORT1'):
    if index is None:
        index = lua.globals().A.ReportChannelID() or 0
    lua.globals().emitEvent('CHAT_MSG_ADDON', prefix, payload, route, sender, '', 0, index, name)


def check(root):
    # Preserve the active report channel; legacy cleanup cannot block readiness.
    lua = factory(root, setup="""
channels={[1]='General',[2]='totalwarcraft-old',[3]='Trade',[7]='TotalWarcraftTest',
 [8]='TotalWarcraftReportComms',[9]='OtherTotalWarcraft',[10]='TotalWarcraftFans'}
A.db.channelDiagnostics={entries={'old dummy data'}}
""")
    lua.execute("""
assert(#channelLeaves==3 and channelJoins==0 and not A.db.channelDiagnostics)
assert(channels[1]=='General' and channels[3]=='Trade' and channels[9]=='OtherTotalWarcraft')
assert(A.ReportChannelID()==8)
advanceTimers(1)
assert(A.ReportChannelID()==8 and channelJoins==0 and activeTimers()==0)
emitEvent('PLAYER_LOGIN'); emitEvent('PLAYER_ENTERING_WORLD')
assert(channelJoins==0 and #channelLeaves==3 and advanceTimers(300)==0 and sends==0)
""")

    # 0.7.11 live failure: cleanup can retain listed memberships even after leave
    # attempts, preventing any join. A usable current channel must remain usable.
    stuck=factory(root,setup="channels[7]='TotalWarcraftReportComms'; channels[8]='TotalWarcraftLegacy'; LeaveChannelByName=function() end")
    stuck.execute("assert(A.ReportChannelID()==7 and channelJoins==0); assert(A.Report()); assert(sends==1)")
    for setup in ["channels[5]='TotalWarcraftOld'; LeaveChannelByName=function() end",
                  "channels[5]='TotalWarcraftOld'; LeaveChannelByName=function() error('unavailable') end",
                  "GetChannelList=nil", "GetChannelList=function() error('unavailable') end",
                  "GetChannelList=function() return 1,'SECRET',false end"]:
        recovered=factory(root,setup=setup)
        recovered.execute("assert(A.ReportChannelID()==7 and channelJoins==1 and activeTimers()==0); assert(A.Report())")

    # Real five-second automatic sends survive the stuck legacy cleanup from the
    # live log, for both players and flagged NPCs, with or without a prior channel.
    for existing in [False, True]:
        for player in ['true', 'false']:
            activity=factory(root,setup="channels[5]='TotalWarcraftOld'; LeaveChannelByName=function() end; "
                             + ("channels[7]='TotalWarcraftReportComms'" if existing else ""))
            activity.execute(SETUP + "\nplayerTarget=" + player + """
function UnitPlayerControlled(u) return UnitIsPlayer(u) end
fight(); advanceTimers(4); event('UNIT_COMBAT','target','WOUND'); advanceTimers(1)
assert(combat and reportCount()==1 and sentRoutes[1]=='CHANNEL' and #A.List()==1)
assert(A.SessionLogText():find('REPORT_AUTO accepted=true evidence=observed-flagged-damage',1,true))
peace(); assert(reportCount()==1 and not A.autoReports.timer and not A.reportChannel.timer)
""")

    # Two unguilded users on different continents and different LOCAL indexes.
    alice=factory(root,'Alice One',"inGuild=false; nextChannel=7; C_Map.GetBestMapForUnit=function() return 1434 end")
    bob=factory(root,'Bob Two',"inGuild=false; nextChannel=8; C_Map.GetBestMapForUnit=function() return 1445 end")
    alice.execute("C_ChatInfo.AreOutgoingAddonChatMessagesRestricted=function() return true end; assert(A.Report()); assert(sends==1 and sentRoutes[1]=='CHANNEL' and sentTargets[1]=='7')")
    packet=alice.globals().packets[1]
    deliver(bob,packet,'Alice One')
    bob.execute("""
assert(#A.List()==1 and A.List()[1].mapID==1434 and sends==0)
WorldMapFrame:SetMapID(1434)
local pins=0; for _,p in ipairs(WorldMapFrame.pool) do if p.active and p.record then pins=pins+1 end end
assert(pins==1)
""")
    # Self echo and channel/guild copies never increase pins, heat or expiration.
    deliver(alice,packet,'Alice One')
    bob.execute('inGuild=true; before=A.List()[1].expiresAt')
    deliver(bob,packet,'Alice One','GUILD')
    deliver(bob,packet,'Alice One')
    bob.execute('assert(#A.List()==1 and A.List()[1].expiresAt==before and sends==0); local c=A.ReportClusters(); assert(#c==1 and c[1].reports==1 and not c[1].pulse)')
    reverse=factory(root,'Legacy First')
    deliver(reverse,packet,'Alice One','GUILD')
    deliver(reverse,packet,'Alice One')
    reverse.execute('assert(#A.List()==1 and sends==0); local c=A.ReportClusters(); assert(#c==1 and c[1].reports==1 and not c[1].pulse)')
    # A live channel reindex is resolved at the next send, without a cached target.
    bob.execute("channels[8]=nil; channels[12]='TotalWarcraftReportComms'; channels[8]='Other'; assert(A.Report()); assert(sends==1 and sentTargets[1]=='12' and sentRoutes[1]=='CHANNEL')")
    deliver(alice,bob.globals().packets[1],'Bob Two')
    alice.execute('assert(#A.List()==2 and sends==1)')

    guard=factory(root,'Guard Three', 'inGuild=false; nextChannel=8')
    for route,index,name,prefix in [('CHANNEL',7,NAME,'WBP_REPORT1'),('CHANNEL',8,'Other','WBP_REPORT1'),
            ('CHANNEL',0,'','WBP_REPORT1'),('WHISPER',8,NAME,'WBP_REPORT1'),
            ('GUILD',8,NAME,'WBP_REPORT1'),('CHANNEL',8,NAME,'WRONG'),('CHANNEL',8,'SECRET','WBP_REPORT1')]:
        deliver(guard,packet,'Alice One',route,index,name,prefix)
    guard.execute('assert(#A.List()==0 and sends==0)')
    for field,value in [(1,'T'),(7,'A'),(8,'rppvp'),(12,'2'),(3,'1')]:
        fields=packet.split('\t'); fields[field]=value
        deliver(guard,'\t'.join(fields),'Alice One')
    deliver(guard,packet,'Bad|Sender')
    guard.execute('assert(#A.List()==0)')
    deliver(guard,packet,'Alice One')
    guard.execute('assert(#A.List()==1 and sends==0); advanceTimers(301); assert(#A.List()==0 and activeTimers()==0)')

    # Delayed membership is not mistaken for success from a join return value.
    delayed=factory(root,setup="""
JoinTemporaryChannel=function(name) channelJoins=channelJoins+1; return 0 end
""")
    delayed.execute("""
assert(not A.ReportChannelID() and not A.Report() and A.db.lastSubmit==0)
advanceTimers(2); channels[11]='TotalWarcraftReportComms'; advanceTimers(1)
assert(A.ReportChannelID()==11 and activeTimers()==0)
CLOCK=CLOCK+5; assert(A.Report() and sentTargets[1]=='11')
""")

    # Native rejection and missing/secret channel identity still fail boundedly.
    for setup in ["JoinTemporaryChannel=function() error('unavailable') end",
                  "JoinTemporaryChannel=function() channelJoins=channelJoins+1; return 0 end",
                  "GetChannelName=function() return 'SECRET' end"]:
        fail=factory(root,setup=setup)
        fail.execute("advanceTimers(31); assert(not A.ReportChannelID() and activeTimers()==0 and sends==0); assert(channelJoins<=3); assert(advanceTimers(300)==0)")

    # Recover on leaving combat, without an idle retry loop or resending a report.
    recovery=factory(root,setup="nativeJoin=JoinTemporaryChannel; JoinTemporaryChannel=function() return false end")
    recovery.execute("advanceTimers(31); assert(not A.ReportChannelID() and activeTimers()==0); JoinTemporaryChannel=nativeJoin; emitEvent('PLAYER_REGEN_ENABLED'); assert(A.ReportChannelID()==7 and channelJoins==1 and sends==0 and activeTimers()==0)")

    retry=factory(root)
    retry.execute("""
advanceTimers(31); channels[7]=nil
emitEvent('CHAT_MSG_CHANNEL_NOTICE','YOU_LEFT','','','',nil,nil,0,7,'TotalWarcraftReportComms')
assert(A.ReportChannelID()==7 and channelJoins==2 and activeTimers()==0)
emitEvent('CHAT_MSG_CHANNEL_NOTICE','BANNED','','','',nil,nil,0,7,'Other')
assert(A.ReportChannelID()==7)
emitEvent('CHAT_MSG_CHANNEL_NOTICE','MUTED','','','',nil,nil,0,7,'TotalWarcraftReportComms')
assert(not A.ReportChannelID() and not A.Report() and activeTimers()==0)
advanceTimers(31); emitEvent('PLAYER_REGEN_ENABLED'); assert(not A.ReportChannelID() and activeTimers()==0)
advanceTimers(31); emitEvent('PLAYER_ENTERING_WORLD'); assert(A.ReportChannelID()==7)
emitEvent('PLAYER_LOGOUT'); assert(not A.ReportChannelID() and activeTimers()==0)
""")
    # Failures do not create local records or consume the successful-report cooldown.
    failed=factory(root)
    failed.execute('sendFailure=true; assert(not A.Report()); assert(#A.List()==0 and A.db.lastSubmit==0); advanceTimers(5); sendFailure=false; assert(A.Report() and sends==1)')

    # Persisted valid membership is reused; only retired channels are cleaned.
    reload=factory(root,setup="channels[7]='TotalWarcraftReportComms'; channels[8]='TotalWarcraftLegacy'; nextChannel=9")
    reload.execute("advanceTimers(1); assert(#channelLeaves==1 and channelJoins==0 and A.ReportChannelID()==7)")


check(ROOT)
release,manifest=build('release')
check(release)
assert 'ChannelDiagnostics.lua' not in manifest['files'] and 'CHANNEL_TESTING.txt' not in manifest['files']
dev=factory(ROOT)
dev.execute("SlashCmdList.WARBANDPVP('test on'); assert(A.Report()); assert(sends==1 and sentRoutes[1]=='GUILD')")
print('PASS: automatic report channel, unguilded map delivery, distinct/reindexed local IDs, cross-route deduplication, cleanup/reload/recovery, bounded failures, sender/scope guards, source + compiled Release, dev isolation.')
