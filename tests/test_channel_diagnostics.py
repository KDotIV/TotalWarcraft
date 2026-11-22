"""Opt-in CHANNEL troubleshooting. Mocks never prove native server support."""
from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime
from wow_mock import client, BOOT

SETUP = r'''
inGuild=false; channel=0; joinCalls=0; leaveCalls=0; outbox={}; channelSends=0
local register=C_ChatInfo.RegisterAddonMessagePrefix
C_ChatInfo.RegisterAddonMessagePrefix=function(p)
 if p=='TW_CHTEST1' then return 0 end; return register(p)
end
function GetChannelName(name) if name==20 then return channel==20 and 20 or (occupied20 and 20 or 0) end; assert(name=='TotalWarcraftTest'); return channel,name end
function JoinTemporaryChannel(name) assert(name=='TotalWarcraftTest'); joinCalls=joinCalls+1; channel=LOCAL_CHANNEL; return channel end
function LeaveChannelByName(name) assert(name=='TotalWarcraftTest'); leaveCalls=leaveCalls+1; channel=0 end
function GetRealmName() return 'Hidden Realm '..LOCAL_CHANNEL end
function GetRealmID() return LOCAL_CHANNEL end
C_Map.GetBestMapForUnit=function() return CURRENT_MAP end
C_ChatInfo.AreOutgoingAddonChatMessagesRestricted=function() return true end
C_ChatInfo.InChatMessagingLockdown=function() return false end
C_ChatInfo.SendAddonMessage=function(prefix,payload,route,target)
 assert(prefix=='TW_CHTEST1' and route=='CHANNEL' and target==tostring(channel))
 assert(#payload<=255); channelSends=channelSends+1
 outbox[#outbox+1]={payload=payload,route=route,target=target}
 return SEND_RESULT or 0
end
function start(label) SlashCmdList.WARBANDPVP('channel start '..(label or 'unguilded')) end
function notice(code,index,base)
 A.OnChannelDiagnosticEvent('CHAT_MSG_CHANNEL_NOTICE',code,'','','',nil,nil,0,index or channel,base or 'TotalWarcraftTest')
end
'''

def configure(lua, channel_id=5, map_id=1454):
    lua.globals().LOCAL_CHANNEL = channel_id
    lua.globals().CURRENT_MAP = map_id
    lua.execute(SETUP)
    return lua

def make(name='Alice One', channel_id=5, map_id=1454):
    return configure(client(name), channel_id, map_id)

def deliver(lua, payload, sender, route='CHANNEL', channel_id=None):
    g = lua.globals()
    g.A.OnChannelDiagnosticEvent('CHAT_MSG_ADDON', 'TW_CHTEST1', payload, route,
                                sender, '', 0, channel_id or g.LOCAL_CHANNEL, 'TotalWarcraftTest')

def roundtrip(a, b):
    for lua in (a, b):
        lua.execute('assert(activeTimers()==0 and joinCalls==0); start(); assert(channelSends==0)')
    cursor = [0, 0]
    for _ in range(50):
        for lua in (a, b):
            lua.execute('advanceTimers(1)')
        for i, (source, dest) in enumerate(((a, b), (b, a))):
            box = source.globals().outbox
            while cursor[i] < len(box):
                cursor[i] += 1
                message = box[cursor[i]].payload
                deliver(dest, message, source.globals().PLAYER)
                deliver(source, message, source.globals().PLAYER)  # own echo is not proof
    for lua in (a, b):
        lua.execute('''
        assert(A.channelDiagnostics.rx>=3 and A.channelDiagnostics.acks>=3)
        assert(A.channelDiagnostics.echoes>0 and #A.List()==0 and sends==0)
        assert(A.ChannelDiagnosticText():find('REMOTE_ACK',1,true))
        SlashCmdList.WARBANDPVP('channel export'); assert(A.channelExport:IsShown())
        SlashCmdList.WARBANDPVP('channel stop')
        assert(activeTimers()==0 and leaveCalls==1 and channel==0)
        local n=channelSends; advanceTimers(300); assert(channelSends==n)
        ''')

# Unguilded clients, different maps/realm identifiers/local channel numbers.
roundtrip(make(), make('Bob Two', 9, 1434))

# Local success and self echoes alone never become remote confirmations.
lua = make()
lua.execute('start(); advanceTimers(5)')
p = lua.globals().outbox[1].payload
deliver(lua, p, 'Alice One')
lua.execute('assert(A.channelDiagnostics.echoes==1 and A.channelDiagnostics.rx==0 and A.channelDiagnostics.acks==0)')

# Malformed, wrong-route, wrong-scope, stale, secret and duplicate traffic.
peer = make('Bob Two', 9)
peer.execute('start(); advanceTimers(5)')
remote = peer.globals().outbox[1].payload
fields = remote.split('\t')
for index, value in [(0, '2'), (1, 'X'), (3, '13'), (4, '1'), (5, '2'), (6, 'normal'),
                     (7, 'Alliance'), (8, '-1'), (9, 'a|b'), (10, 'bad')]:
    bad = fields.copy(); bad[index] = value
    deliver(lua, '\t'.join(bad), 'Bob Two')
for payload in ['x'*256, remote+'\textra', 'SECRET']:
    deliver(lua, payload, 'Bob Two')
deliver(lua, remote, 'Bob Two', route='GUILD')
deliver(lua, remote, 'Bob Two', channel_id=9)
deliver(lua, remote, 'SECRET')
lua.execute('assert(A.channelDiagnostics.rx==0 and A.channelDiagnostics.acks==0)')
deliver(lua, remote, 'Bob Two')
deliver(lua, remote, 'Bob Two')
lua.execute('assert(A.channelDiagnostics.rx==1); advanceTimers(1); assert(channelSends==2)')
# Matching ACK only after our exact run/sequence, within its deadline.
ack = fields.copy(); ack[1]='A'; ack[2]=lua.globals().A.channelDiagnostics.run
ack[3]='12'
deliver(lua, '\t'.join(ack), 'Bob Two')
lua.execute('assert(A.channelDiagnostics.acks==0)')
ack[3]='1'
deliver(lua, '\t'.join(ack), 'Bob Two')
deliver(lua, '\t'.join(ack), 'Bob Two')
lua.execute('assert(A.channelDiagnostics.acks==1)')
lua.execute('advanceTimers(65)')
deliver(lua, '\t'.join(ack), 'Other Three')
lua.execute('assert(A.channelDiagnostics.acks==1)')

# Native rejection notices may follow an accepted return; no whisper fallback.
lua = make()
lua.execute('''
start(); advanceTimers(5); notice('NOT_ALLOWED_IN_CHANNEL',99,'OtherChannel')
assert(not A.channelDiagnostics.blocked)
notice('NOT_ALLOWED_IN_CHANNEL'); advanceTimers(170)
assert(channelSends==1 and A.channelDiagnostics.sent==1 and A.channelDiagnostics.rx==0)
advanceTimers(6); assert(not A.channelDiagnostics.active and activeTimers()==0)
''')
lua = make()
lua.execute('SEND_RESULT=7; start(); advanceTimers(60); assert(channelSends==3 and A.channelDiagnostics.sent==0 and A.channelDiagnostics.blocked)')
lua.execute('advanceTimers(125); assert(activeTimers()==0 and leaveCalls==1)')

# Missing channel, async join, channel renumbering, preexisting ownership, logout.
lua = make()
lua.execute('JoinTemporaryChannel=function() joinCalls=joinCalls+1 end; start(); advanceTimers(31); assert(channelSends==0 and joinCalls==1 and activeTimers()==0)')
lua = make()
lua.execute('JoinTemporaryChannel=function() joinCalls=joinCalls+1 end; start(); advanceTimers(6); channel=5; advanceTimers(1); assert(channelSends==1); channel=8; advanceTimers(15); assert(channelSends==2)')
lua = make()
lua.execute('channel=5; start(); advanceTimers(5); A.OnChannelDiagnosticEvent("PLAYER_LOGOUT"); assert(activeTimers()==0 and leaveCalls==0 and channel==5)')
lua.execute('local n=channelSends; A.InitChannelDiagnostics(); advanceTimers(30); assert(channelSends==n and not A.channelDiagnostics.active)')

# Burst/peer/queue/log limits, stop prevents future replies; no changes to damage capture.
lua = make()
lua.execute('start(); advanceTimers(5)')
for i in range(200):
    deliver(lua, remote, f'Peer Number{i}')
lua.execute('assert(A.channelDiagnostics.peerCount==16 and #A.channelDiagnostics.queue<=16); advanceTimers(180); assert(channelSends<=72 and activeTimers()==0)')
for i in range(12):
    lua.execute("start('bounded'); advanceTimers(5); SlashCmdList.WARBANDPVP('channel stop')")
lua.execute('''
assert(#A.db.channelDiagnostics.entries<=500)
SlashCmdList.WARBANDPVP('channel clear'); assert(#A.db.channelDiagnostics.entries==0)
assert(A.damageDiagnostics.revision==1 and not A.damageDiagnostics.active)
''')
for mutation in ['JoinTemporaryChannel=nil; JoinChannelByName=nil', 'C_ChatInfo.RegisterAddonMessagePrefix=function() return 2 end', 'GetChannelName=nil']:
    lua = make(); lua.execute(mutation + '; start(); assert(not A.channelDiagnostics.active and activeTimers()==0)')

# Repeat actual delivery against the installable, compiled developer package.
lua=make()
lua.execute('''
swapCalls=0
C_ChatInfo.SwapChatChannelsByChannelIndex=function(a,b) assert(a==channel and b==20); channel=20; swapCalls=swapCalls+1 end
start(); advanceTimers(6); assert(channel==20 and outbox[1].target=='20' and swapCalls==1)
advanceTimers(20); assert(swapCalls==1)
SlashCmdList.WARBANDPVP('channel'); assert(A.channelPanel:IsShown())
SlashCmdList.WARBANDPVP('channel stop'); assert(channel==0 and leaveCalls==1)
''')
for scenario in ['occupied20=true', 'GetChannelName=function(n) if n==20 then return "SECRET" end; return channel end']:
    lua=make(); lua.execute(scenario+'''
    C_ChatInfo.SwapChatChannelsByChannelIndex=function() error('must not displace existing/unknown channel') end
    start(); advanceTimers(6); assert(channel==5 and outbox[1].target=='5')
    ''')
for implementation in ['function() error("unsupported index") end','function() end']:
    lua=make(); lua.execute('C_ChatInfo.SwapChatChannelsByChannelIndex='+implementation+'; start(); advanceTimers(6); assert(channel==5 and outbox[1].target=="5")')

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from build_addon import build
stage, manifest = build('dev')
def packaged(name, channel_id, map_id):
    lua = LuaRuntime(unpack_returned_tuples=True); lua.execute(BOOT); lua.globals().PLAYER=name
    for line in (stage/'WarbandPvP.toc').read_text().splitlines():
        if line.endswith('.lua'):
            lua.execute('assert(loadstring(...))("WarbandPvP",A)', (stage/line).read_text())
    lua.execute("for _,f in ipairs(frames) do if f.events.ADDON_LOADED then core=f end end; core.scripts.OnEvent(nil,'ADDON_LOADED','WarbandPvP')")
    return configure(lua, channel_id, map_id)
roundtrip(packaged('Alice One', 5, 1454), packaged('Bob Two', 9, 1434))
assert 'ChannelDiagnostics.lua' in manifest['files'] and 'CHANNEL_TESTING.txt' in manifest['files']
stage, manifest = build('release')
roundtrip(packaged('Alice One', 5, 1454), packaged('Bob Two', 9, 1434))
assert 'DamageDiagnostics.lua' not in manifest['files'] and 'Control.lua' not in manifest['files']
print('PASS: automatic unguilded CHANNEL probes/ACKs, local IDs, receipt vs self echo, rejection notices, hostile bounds, owned-channel cleanup, managed export and compiled-dev delivery. Native server delivery remains unverified.')
