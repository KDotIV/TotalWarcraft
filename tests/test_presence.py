"""Cooperative location transport and map integration, using separate Lua clients."""
from wow_mock import client
from forever_compat import check_hidden_realms

check_hidden_realms(client)

GROUP = '''
grouped=true; raid=false; instance=false; members={'Alice','Bob','Carol','Dave','Eve'}
function IsInInstance() return instance end
function IsInGroup() return grouped end
function IsInRaid() return raid end
function memberName(u)
 if u=='player' then return PLAYER end
 local i=tonumber(u:match('%d+$'))
 if not grouped or not i then return end
 if raid then return members[i] end
 local n=0
 for _,name in ipairs(members) do
  if name~=PLAYER then n=n+1; if n==i then return name end end
 end
end
function UnitFullName(u) return memberName(u),'TestRealm' end
function UnitGUID(u) local n=memberName(u); return n and ('Player-'..n) end
function UnitIsPlayer(u) return memberName(u)~=nil end
function UnitDistanceSquared(u) return 10000,true end
function UnitAffectingCombat() return true end
function UnitIsPVP() return true end
'''


def grouped(name):
    lua = client(name)
    lua.execute(GROUP)
    return lua


def deliver(lua, packet, sender='Alice-TestRealm', route='PARTY', prefix='WBP_PRES1'):
    lua.globals().A.OnPresenceMessage(prefix, packet, route, sender)


alice, bob = grouped('Alice'), grouped('Bob')
alice.execute('''
assert(not A.presenceEnabled and A.presenceReady and sends==0 and not A.presenceTimer)
SlashCmdList.WARBANDPVP('presence on')
assert(A.presenceEnabled and A.presenceTimer and sends==1)
assert(sentRoutes[1]=='PARTY' and sentPrefixes[1]=='WBP_PRES1')
assert(#A.List()==0 and not A.toast) -- presence never creates a report/toast
A.PresenceTick(); assert(sends==1)
''')
packet = alice.globals().packets[1]
assert len(packet.split('\t')) == 10 and len(packet) <= 255
assert 'Alice' not in packet and 'Player-' not in packet
deliver(bob, packet)
bob.execute("assert(#A.PresenceList()==0); SlashCmdList.WARBANDPVP('presence on')")
deliver(bob, packet)
bob.execute('''
assert(#A.PresenceList()==1 and sends==1 and #A.List()==0 and not A.toast)
local p=A.PresenceList()[1]
assert(p.name=='Alice-TestRealm' and p.flagged=='1' and p.combat=='1')
assert(p.x==.25 and p.y==.75 and p.expiresAt==NOW+30)
local fresh,nearby,unknown=A.PresenceSummary()
assert(fresh==1 and nearby==1 and unknown==0)
UnitDistanceSquared=function() return 10001,true end
fresh,nearby,unknown=A.PresenceSummary(); assert(nearby==0 and unknown==0)
UnitDistanceSquared=function() return 0,false end
fresh,nearby,unknown=A.PresenceSummary(); assert(nearby==0 and unknown==1)
local pin=WorldMapFrame.pool[1]
assert(pin.active and pin.presence==p and pin.marker.text=='+')
assert(pin.normalizedX==.25 and pin.normalizedY==.75)
assert(pin.frameLevelType=='PIN_FRAME_LEVEL_AREA_POI')
pin:OnMouseEnter() -- tooltip only, no report action
WorldMapFrame:SetMapID(2); assert(not pin.active)
WorldMapFrame:SetMapID(1); assert(pin.active)
''')
deliver(alice, packet)  # self echo cannot become a peer
alice.execute('assert(#A.PresenceList()==0)')
deliver(bob, packet)
bob.execute('assert(#A.PresenceList()==1)')

# A real new heartbeat updates one identity, without accumulating records.
alice.execute('NOW=NOW+10; CLOCK=CLOCK+10; A.PresenceTick(); assert(sends==2)')
bob.execute('NOW=NOW+10; CLOCK=CLOCK+10')
deliver(bob, alice.globals().packets[2])
bob.execute('assert(#A.PresenceList()==1 and A.PresenceList()[1].updatedAt==NOW)')

# Current group members only; wrong channel/audience/shape/state/timestamp rejected.
guard = grouped('Bob')
guard.execute('A.SetPresenceEnabled(true)')
fields = packet.split('\t')
bad_packets = ['x' * 256, packet + '\textra', 'SECRET']
for index, value in [(0, '2'), (1, '0'), (1, str(int(fields[1]) + 6)),
                     (2, 'nan'), (3, '10001'), (4, '-1'), (5, 'A'),
                     (6, 'rppvp'), (7, '2'), (8, 'true'), (9, 'combat')]:
    bad = fields.copy(); bad[index] = value; bad_packets.append('\t'.join(bad))
for bad in bad_packets:
    deliver(guard, bad)
for channel in ['GUILD', 'WHISPER', 'INSTANCE_CHAT', 'RAID']:
    deliver(guard, packet, route=channel)
deliver(guard, packet, sender='Outsider-TestRealm')
deliver(guard, packet, sender='SECRET')
deliver(guard, packet, prefix='WBP_REPORT1')
guard.execute('assert(#A.PresenceList()==0 and #A.List()==0)')
deliver(guard, packet, sender='Alice')  # same-realm event names normalize
guard.execute('assert(#A.PresenceList()==1)')

# Scope changes, departure, instances, opt-out and reload cannot retain active peers.
guard.execute('''
C_GameRules.IsGameRuleActive=function(rule) return rule==2 end
A.RefreshScope(); assert(#A.PresenceList()==0)
''')
deliver(guard, packet)
guard.execute('assert(#A.PresenceList()==0)')
bob.execute('''
members={'Bob','Carol'}; A.RefreshPresenceRoster(); A.RefreshMap()
assert(#A.PresenceList()==0 and not WorldMapFrame.pool[1].active)
''')
guard.execute('''
instance=true; local before=sends; CLOCK=CLOCK+10; A.PresenceTick()
assert(sends==before and #A.PresenceList()==0)
instance=false; grouped=false; A.PresenceTick(); assert(sends==before)
A.SetPresenceEnabled(false); assert(not A.presenceTimer)
''')
deliver(guard, packet)
guard.execute('assert(#A.PresenceList()==0)')
client('Reloaded').execute('assert(not A.presenceEnabled and sends==0)')

# Expiry must not be extended by duplicate packets, and sweeps release pins.
expiry = grouped('Bob')
expiry.execute('A.SetPresenceEnabled(true)')
deliver(expiry, packet)
expiry.execute('NOW=NOW+29; CLOCK=CLOCK+29')
deliver(expiry, packet)
expiry.execute('''
NOW=NOW+1; CLOCK=CLOCK+1; A.PresenceTick()
assert(#A.PresenceList()==0 and not WorldMapFrame.pool[1].active)
assert(#A.List()==0)
''')

# Missing/secret APIs fail closed; unknown flags are not advertised as false.
restricted = grouped('Alice')
restricted.execute('''
UnitIsPVP=function() return 'SECRET' end
UnitAffectingCombat=function() error('restricted') end
A.SetPresenceEnabled(true); assert(packets[1]:sub(-3)=='?\t?')
local before=sends
A.CurrentLocation=function() error('position restricted') end
CLOCK=CLOCK+10; A.PresenceTick(); assert(sends==before)
A.CurrentLocation=function() return {mapID=1,x='SECRET',y=.5} end
CLOCK=CLOCK+10; A.PresenceTick(); assert(sends==before)
''')
failure = grouped('Alice')
failure.execute('''
sendFailure=true; A.SetPresenceEnabled(true); assert(sends==0 and attempts==1)
sendFailure=false; A.PresenceTick(); assert(sends==0 and attempts==1)
CLOCK=CLOCK+10; A.PresenceTick(); assert(sends==1)
A.SetPresenceEnabled(false); A.SetPresenceEnabled(true); assert(sends==1)
''')

# Raid snapshots are bounded to actual roster GUIDs (including duplicate tokens).
raid = grouped('Bob')
raid.execute('''
raid=true; members={'Bob'}
for i=1,39 do members[#members+1]='Member'..i end
A.SetPresenceEnabled(true); assert(sentRoutes[1]=='RAID')
''')
for i in range(1, 45):
    deliver(raid, packet, sender=f'Member{i}-TestRealm', route='RAID')
raid.execute('assert(#A.PresenceList()==39 and #A.List()==0 and not A.toast)')

# Optional OpenMap transforms preserve source coordinates and managed layering.
projection = grouped('Bob')
projection.execute('''
callbacks={}; stitched=true
OpenMapAPI={major=1,
 IsStitched=function() return stitched end,
 WorldFromMap=function(map,x,y) assert(map==2); return .4,.6 end,
 MapFromWorld=function(map,u,v) assert(map==1 and u==.4 and v==.6); return 1.25,-.2 end,
 RegisterCallback=function(owner,event,fn) callbacks[event]=fn end}
A.AttachMap(); A.AttachMap(); assert(callbacks.OpenMap_StitchedChanged)
assert(not callbacks.OpenMap_ViewChanged) -- pan/zoom uses native canvas positioning
local r={mapID=2,x=.25,y=.75}
local x,y=A.MapPosition(r,1); assert(x==1.25 and y==-.2 and r.x==.25 and r.y==.75)
''')
projection.execute('A.SetPresenceEnabled(true)')
foreign_zone = fields.copy(); foreign_zone[2] = '2'
deliver(projection, '\t'.join(foreign_zone))
projection.execute('''
local pin=WorldMapFrame.pool[1]
assert(pin.active and pin.normalizedX==1.25 and pin.normalizedY==-.2)
assert(pin.presence.mapID==2 and pin.presence.x==.25)
stitched=false; callbacks.OpenMap_StitchedChanged(); assert(not pin.active)
stitched=true; callbacks.OpenMap_StitchedChanged(); assert(pin.active)
local r={mapID=2,x=.25,y=.75}
InputUtil={IsGamepadUIEnabled=function() return true end}
assert(A.MapPosition(r,1)==nil)
InputUtil=nil; OpenMapAPI.MapFromWorld=function() return 0/0,math.huge end
assert(A.MapPosition(r,1)==nil)
OpenMapAPI.MapFromWorld=function() error('unavailable') end
assert(A.MapPosition(r,1)==nil)
OpenMapAPI=nil; assert(A.MapPosition(r,1)==nil)
x,y=A.MapPosition(r,2); assert(x==.25 and y==.75)
''')
print('PASS: opt-in group presence, roster identity, bounded raid, scope, packet rejection, expiry, throttling, API restrictions, native markers and optional OpenMap transforms.')
print('No live WoW delivery, rendering, same-layer or PvP participation claim is made by these mocks.')

# Forever first/surname aliases come from actual roster tokens, never guessed pools.
names = grouped('Bob')
names.execute('''
function GetBuildInfo() return '1.60.1','test','date',16001 end
function UnitFullName(u)
 if u=='party1' then return 'Alice-Smith','TestRealm' end
 return memberName(u),'TestRealm'
end
function UnitName(u)
 if u=='party1' then return 'Alice','Smith' end
 return memberName(u)
end
A.SetPresenceEnabled(true)
''')
deliver(names, packet, sender='Alice Smith')
names.execute("assert(#A.PresenceList()==1 and A.PresenceList()[1].guid=='Player-Alice')")
deliver(names, packet, sender='Alice-Smith')
deliver(names, packet, sender='Alice-Smith-TestRealm')
names.execute('assert(#A.PresenceList()==1)')
names.execute('''
-- Two readable roster identities yielding the same alias must not be guessed.
UnitName=function(u) if u=='party1' or u=='party2' then return 'Alice','Smith' end return memberName(u) end
A.ClearPresence(); A.RefreshPresenceRoster()
''')
deliver(names, packet, sender='Alice Smith')
names.execute('assert(#A.PresenceList()==0)')

# Unreadable/nonfinite map data cannot crash reporting or publish a position.
location = client('Alice')
location.execute('''
C_Map.GetBestMapForUnit=function() return 'SECRET' end
assert(A.CurrentLocation()==nil)
C_Map.GetBestMapForUnit=function() error('restricted map') end
assert(A.CurrentLocation()==nil)
C_Map.GetBestMapForUnit=function() return 1 end
C_Map.GetPlayerMapPosition=function() return {GetXY=function() return 0/0,.5 end} end
assert(A.CurrentLocation()==nil)
C_Map.GetPlayerMapPosition=function() return {GetXY=function() return .5,'SECRET' end} end
assert(A.CurrentLocation()==nil)
local ok=A.Report(); assert(not ok and sends==0)
''')
print('PASS: Forever roster aliases reject ambiguity; restricted map APIs fail closed.')
