"""Finder API fixture and end-to-end scenarios, also run against the stripped ZIP."""
from warband_network import Network, get, say

MOCK = r'''
ACTIVE=nil; DESIRED=nil; RESULTS={}; creates=0; updates=0; removes=0; searches=0
function finderEvent(event,arg) A.finder.events.scripts.OnEvent(nil,event,arg) end
local function entry(data)
 assert(data.isAutoAccept==false and data.isCrossFactionListing==false and data.isPrivateGroup==false)
 return {activityIDs=data.activityIDs,name='Outdoor PvP',comment='',voiceChat='',voiceMode=0,
  autoAccept=false,privateGroup=false,isCrossFactionListing=false,newPlayerFriendly=false}
end
function finishListing()
 local created=ACTIVE==nil
 ACTIVE=DESIRED; finderEvent('LFG_LIST_ACTIVE_ENTRY_UPDATE',created)
end
C_LFGList={
 IsPremadeGroupFinderEnabled=function() return true end,
 GetAvailableCategories=function() return {2,118,120} end,
 GetAvailableActivities=function(c) return c==118 and {1001,1002} or {1003} end,
 GetLfgCategoryInfo=function(c) return {autoChooseActivity=c==120} end,
 GetActivityInfoTable=function(id) return {categoryID=id==1003 and 120 or 118,fullName='Zone '..(id-1000)} end,
 HasActiveEntryInfo=function() return ACTIVE~=nil end,
 GetActiveEntryInfo=function() return ACTIVE end,
 ClearCreationTextFields=function() end,
 CreateListing=function(data) creates=creates+1; DESIRED=entry(data); return true end,
 UpdateListing=function(data) updates=updates+1; DESIRED=entry(data); return true end,
 RemoveListing=function() removes=removes+1; DESIRED=nil end,
 Search=function(...) searches=searches+1; searchArgs={...} end,
 GetSearchResults=function() local ids={}; for i=1,#RESULTS do ids[i]=i end; return #ids,ids end,
 GetSearchResultInfo=function(id) return RESULTS[id] end,
}
A.finder.choicesAt=nil
assert(A.SelectFinderActivity(1001))
'''


def install(lua):
    lua.execute(MOCK)


def discover(peer, leader, activity=1001):
    peer.globals().finderLeader = leader
    peer.globals().finderActivity = activity
    peer.execute('''
RESULTS={{leaderName=finderLeader,activityIDs={finderActivity},numMembers=1,isDelisted=false,hasSelf=false}}
assert(A.FinderSearch())
finderEvent('LFG_LIST_SEARCH_RESULTS_RECEIVED')
''')


def check_finder():
    net = Network()
    host = net.add('Host One', 'A')
    peer = net.add('Peer Two', 'B')
    for lua in (host, peer):
        install(lua)
    say(host, 'start Public patrol')
    host.execute("assert(creates==1 and A.finder.operation and not A.finder.owned); finishListing(); assert(A.finder.owned)")
    # Independent guilds discover only via a native result plus scoped nonce exchange.
    peer.execute('A.warbands.enabled=true')
    discover(peer, 'Host One')
    net.advance(17)
    peer.execute("assert(#A.WarbandList()==1 and A.warbands.watches['host-one'].expectedID); assert(not A.warbands.join and not A.warbands.member and #invited==0); assert(A.JoinWarband(A.WarbandList()[1].id))")
    net.advance(4)
    host.execute("assert(#invited==1 and invited[1]=='Peer Two'); assert(A.warbands.invites['peer-two'])")
    peer.execute("assert(A.warbands.member and not IsInGroup()); assert(A.WarbandArrival(A.WarbandList()[1]):find('waiting for native party',1,true))")
    net.advance(8)
    host.execute('assert(#invited==1)')  # no invitation loop while the user decides
    net.party('Host One', ['Host One', 'Peer Two'])  # deliberate native acceptance
    net.advance(2)
    host.execute("assert(not A.warbands.invites['peer-two'])")
    peer.execute("assert(A.WarbandArrival(A.WarbandList()[1]):find('unverified',1,true))")
    # Search selection cannot redirect the listing. Follow-mode rally moves can.
    host.execute('assert(A.SelectFinderActivity(1002)); assert(updates==0); MAP=2; A.FinderSync(); assert(updates==1); finishListing(); assert(A.finder.owned.activity==1002)')
    net.party('Host One', ['Host One', 'Peer Two', 'Helper Three', 'Helper Four', 'Helper Five'])
    net.advance(2)
    host.execute('assert(removes==1); finishListing(); assert(not A.finder.owned)')
    net.advance(20)
    host.execute('assert(creates==1 and removes==1)')
    # Refuse to adopt an unrelated native listing, even for our selected activity.
    outsider = net.add('Other Three')
    install(outsider)
    outsider.execute("ACTIVE={activityIDs={1001},name='My own listing',comment='Keep this'}; assert(A.StartWarband('Private contact patrol')); assert(creates==0 and updates==0 and removes==0)")
    outsider.execute('A.LeaveWarband(); assert(removes==0 and ACTIVE.comment=="Keep this")')
    # Outside edits / replacements relinquish ownership and must survive teardown.
    editor = net.add('Editor Four')
    install(editor)
    editor.execute("assert(A.StartWarband('Patrol')); finishListing(); ACTIVE.comment='Edited by player'; finderEvent('LFG_LIST_ACTIVE_ENTRY_UPDATE',false); assert(not A.finder.owned); A.LeaveWarband(); assert(removes==0)")
    # Fresh listing records cannot grant membership, choose a layer, or auto-accept.
    assert get(peer, '#A.List()') == 0
    return net


def check_finder_edges(client):
    lua = client('Edge Five')
    from warband_network import WORLD
    lua.execute(WORLD)
    install(lua)
    lua.execute(r'''
assert(A.StartWarband('Edge patrol')); finishListing()
-- Hidden fields are not used as identity, compared, or sent out.
ACTIVE.comment='SECRET'; A.LeaveWarband(); assert(removes==0)
ACTIVE=nil; CLOCK=CLOCK+16
assert(A.StartWarband('Retry patrol')); assert(creates==2)
-- Success return alone is not confirmation; do not remove an unknown late listing.
CLOCK=CLOCK+11; A.FinderTick(); assert(not A.finder.owned and not A.finder.operation)
assert(creates==2); A.FinderSync(); assert(creates==2)
-- A user can explicitly retry; exceptions produce bounded failure, not retry spam.
C_LFGList.CreateListing=function() creates=creates+1; error('protected') end
A.FinderSync(true); assert(creates==3 and not A.finder.operation)
for i=1,60 do CLOCK=CLOCK+1; A.FinderTick() end
assert(creates==3)
-- Categories requiring a protected manual comment never attempt a background post.
assert(A.SelectFinderActivity(1003)); assert(creates==3)
C_LFGList.GetLfgCategoryInfo=function() return {autoChooseActivity=true} end
A.finder.choicesAt=nil; A.FinderSync(); assert(creates==3)
assert(A.finder.status:find('manual',1,true))
-- UI stays within the shared non-overlapping navigator.
A.ShowWarbands(); A.ShowFinder(); assert(A.finder.panel:IsShown() and not A.warbands.panel:IsShown())
A.BackWindow(); assert(A.warbands.panel:IsShown() and not A.finder.panel:IsShown())
''')
    # Malicious/expired replies and non-TotalWarcraft leaders do not populate the board.
    loner = client('Loner Six'); loner.execute(WORLD); install(loner)
    loner.execute(r'''
A.warbands.enabled=true
RESULTS={}
for i=1,100 do RESULTS[i]={leaderName='Candidate '..i,activityIDs={1001},numMembers=1,isDelisted=false,hasSelf=false} end
RESULTS[1].leaderName='SECRET'; RESULTS[2].numMembers=5; RESULTS[3].activityIDs={9999}
assert(A.FinderSearch()); finderEvent('LFG_LIST_SEARCH_RESULTS_RECEIVED')
local n=0; for _ in pairs(A.finder.pending) do n=n+1 end; assert(n==8)
assert(not A.FinderSearch() and searches==1)
local key,request=next(A.finder.pending)
local sender=key:gsub('-',' ')
local id,session=A.WB.UUID(),A.WB.UUID()
local wrong=A.WB.Request('F',id,session,A.WB.UUID(),{'Imposter Leader',1})
A.OnWarbandMessage('WBP_WB1',wrong,'WHISPER',sender); assert(not next(A.warbands.watches))
local valid=A.WB.Request('F',id,session,request.nonce,{'Imposter Leader',1})
A.OnWarbandMessage('WBP_WB1',valid,'GUILD',sender); assert(not next(A.warbands.watches))
CLOCK=CLOCK+26
A.OnWarbandMessage('WBP_WB1',valid,'WHISPER',sender); assert(not next(A.warbands.watches))
A.FinderTick(); assert(not next(A.finder.pending))
assert(#A.WarbandList()==0 and not A.warbands.member)
''')


def check_delegated_recruitment():
    net=Network()
    root=net.add('Root One','A'); captain=net.add('Captain Two','B'); recruit=net.add('Recruit Three','C')
    for lua in (root,captain,recruit):
        install(lua)
    net.party('Root One',['Root One','A One','B Two','C Three','D Four'])
    net.party('Captain Two',['Captain Two','Helper Five'])
    captain.execute('MAP=2')  # captain travels elsewhere; listing must use root rally
    root.execute("assert(A.StartWarband('Multiple parties')); assert(creates==0)")
    say(captain,'watch Root One'); net.advance(17)
    captain.execute('assert(A.JoinWarband(A.WarbandList()[1].id))'); net.advance(4)
    captain.execute('assert(A.warbands.member.slot==2 and creates==1 and DESIRED.activityIDs[1]==1001); finishListing()')
    # A coordinator cannot trigger arbitrary automatic native invitations alone.
    forged=root.eval("A.WB.Request('I',A.warbands.host.id,A.warbands.session,A.WB.UUID(),{2,'Unconsenting Player'})")
    captain.globals().A.OnWarbandMessage('WBP_WB1',forged,'WHISPER','Root One')
    net.advance(4); captain.execute('assert(#invited==0)')
    # Secondary-party Finder entry resolves the shared UUID and actual coordinator.
    recruit.execute('A.warbands.enabled=true')
    discover(recruit,'Captain Two'); net.advance(17)
    recruit.execute("assert(#A.WarbandList()==1 and A.WarbandList()[1].owner=='Root One'); assert(A.JoinWarband(A.WarbandList()[1].id))")
    net.advance(4)
    captain.execute("assert(#invited==1 and invited[1]=='Recruit Three')")
    recruit.execute("assert(A.warbands.member.slot==2 and A.warbands.member.host=='Captain Two'); assert(not IsInGroup())")
    root.execute('A.LeaveWarband()'); net.advance(4)
    captain.execute('assert(removes==1); finishListing(); assert(not A.finder.owned)')


def check_idle_and_consent(client):
    from warband_network import WORLD
    idle=client('Idle Observer'); idle.execute(WORLD); install(idle)
    idle.execute(r'''
local calls=0
for key,fn in pairs(C_LFGList) do C_LFGList[key]=function(...) calls=calls+1; return fn(...) end end
A.ShowHome(); A.ShowWarbands(); A.SetWarbandsEnabled(true)
for i=1,300 do
 CLOCK=CLOCK+1
 InCombatLockdown=function() return i%2==0 end
 finderEvent('LFG_LIST_ACTIVE_ENTRY_UPDATE',true)
 A.WarbandTick()
end
assert(calls==0 and creates==0 and updates==0 and removes==0 and searches==0 and #invited==0)
A.OnFinderDiscovery({'1','D'},'Unrelated Player','unrelated-player'); assert(calls==0)
A.warbands.invites['random-player']={name='Random Player',consented=true,slot=1,untilAt=CLOCK+30}
assert(not A.InviteWarbandMember('Random Player')); assert(#invited==0)
InCombatLockdown=function() return false end
assert(A.FinderSearch()); assert(searches==1 and not A.warbands.join and not A.warbands.member)
-- Passive attribution observes other workflows without blocking/redirecting them.
function hooksecurefunc(t,key,after)
 local original=t[key]; t[key]=function(...) local result=original(...); after(...); return result end
end
A.InitSessionLog(); C_PartyInfo.InviteUnit('LayerSwap Guest')
assert(invited[1]=='LayerSwap Guest' and A.SessionLogText():find('NATIVE_INVITE_CALL',1,true))
assert(A.SessionLogText():find('origin unverified',1,true))
''')
    net=Network(); host=net.add('Host One'); peer=net.add('Peer Two')
    for lua in (host,peer): install(lua)
    host.execute("assert(A.StartWarband('Consent patrol')); finishListing(); InCombatLockdown=function() return true end")
    peer.execute('A.SetWarbandsEnabled(true)'); net.advance(17)
    peer.execute('assert(A.JoinWarband(A.WarbandList()[1].id))'); net.advance(4)
    host.execute(r'''
local W=A.warbands; local key='peer-two'; local invite=W.invites[key]
assert(invite and W.inviteConsents[key] and #invited==0)
InCombatLockdown=function() return false end
local consent=W.inviteConsents[key]; W.inviteConsents[key]=nil
assert(not A.InviteWarbandMember('Peer Two') and #invited==0)
W.inviteConsents[key]=consent; local session=consent.memberSession; consent.memberSession='stale'
assert(not A.InviteWarbandMember('Peer Two') and #invited==0)
consent.memberSession=session; consent.untilAt=CLOCK-1
assert(not A.InviteWarbandMember('Peer Two') and #invited==0)
consent.untilAt=CLOCK+30; invite.session='stale'
assert(not A.InviteWarbandMember('Peer Two') and #invited==0)
invite.session=W.session; W.invites[key]=invite; W.inviteConsents[key]=consent
InCombatLockdown=function() return true end
A.LeaveWarband(); InCombatLockdown=function() return false end
CLOCK=CLOCK+1; A.WarbandTick(); assert(#invited==0 and not next(W.invites))
''')


def check_rally_zone(client):
    from warband_network import WORLD
    lua=client('Zone Leader'); lua.execute(WORLD); install(lua)
    lua.execute(r'''
A.db.finderActivity=nil
assert(A.StartWarband('Zone patrol')); assert(DESIRED.activityIDs[1]==1001); finishListing()
-- A fixed rally wins even when the host travels to another zone.
A.WarbandCommand('rally'); MAP=2; CLOCK=CLOCK+16; A.FinderSync()
assert(updates==0 and A.finder.owned.activity==1001)
A.WarbandCommand('rally'); A.FinderSync(); assert(updates==1); finishListing()
assert(A.finder.owned.activity==1002)
-- Unavailable zones remove only our old listing; never choose an unrelated activity.
MAP=999; A.WarbandCommand('rally'); CLOCK=CLOCK+16; A.FinderSync()
assert(removes==1); finishListing(); A.FinderSync()
assert(A.finder.status:find('No Competitive listing',1,true) and creates==1)
-- Ambiguous native names are not guessed. Localized exact names do work.
C_LFGList.GetActivityInfoTable=function(id) return {categoryID=118,fullName='Tal des Schlingendorntals'} end
C_Map.GetMapInfo=function() return {name='Tal des Schlingendorntals'} end
A.finder.choicesAt=nil; A.FinderSync(); assert(creates==1 and A.finder.status:find('Multiple',1,true))
C_LFGList.GetAvailableActivities=function(c) return c==118 and {1002} or {} end
A.finder.choicesAt=nil; CLOCK=CLOCK+6; A.FinderSync()
assert(creates==2 and DESIRED.activityIDs[1]==1002); finishListing()
-- Another addon/native UI taking over the party is respected.
PARTY={PLAYER,'Layer Host'}; nativeLeader='Layer Host'; CLOCK=CLOCK+6; A.FinderSync()
assert(removes==2); finishListing(); assert(not A.finder.owned)
''')
