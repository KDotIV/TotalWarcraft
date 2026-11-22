"""Independent Lua clients, routed guild/party/whisper traffic; no live WoW actions."""
from wow_mock import client

WORLD = '''
PARTY={}; nativeLeader=PLAYER; RAID=false; INSTANCE=false; MAP=1; X=.25; Y=.75
function memberName(u)
 if u=='player' then return PLAYER end
 local i=tonumber(u:match('^party(%d+)$')); if not i then return end
 local k=0; for _,n in ipairs(PARTY) do if n~=PLAYER then k=k+1; if k==i then return n end end end
end
function GetBuildInfo() return '1.60.1','70862','',16001 end
function UnitName(u)
 local n=memberName(u); if not n then return end
 if u=='player' then return n end
 return n:match('^(%S+) (.+)$')
end
function UnitFullName(u) return memberName(u),'TestRealm' end
function UnitGUID(u) local n=memberName(u); return n and ('Player-'..n) end
function UnitExists(u) return memberName(u)~=nil end
function UnitIsPlayer(u) return memberName(u)~=nil end
function UnitIsGroupLeader(u) return memberName(u)==nativeLeader end
function IsInGroup() return #PARTY>1 end
function IsInRaid() return RAID end
function IsInInstance() return INSTANCE end
function GetNumGroupMembers() return #PARTY end
C_Map.GetBestMapForUnit=function() return MAP end
C_Map.GetPlayerMapPosition=function() return {GetXY=function() return X,Y end} end
invited={}
C_PartyInfo={InviteUnit=function(n) invited[#invited+1]=n end}
'''


class Network:
    def __init__(self, scheduled=False, factory=None):
        self.scheduled = scheduled
        self.factory = factory or client
        self.clients = {}
        self.sent = {}
        self.clock = 100
        self.base = 1794240000

    def add(self, name, guild='A'):
        lua = self.factory(name)
        lua.execute(WORLD)
        lua.globals().CLOCK = self.clock
        lua.globals().NOW = self.base + int(self.clock - 100)
        lua.globals().GUILD = guild
        self.clients[name] = lua
        self.sent[name] = 0
        return lua

    def party(self, leader, names):
        for n in names:
            if n in self.clients:
                lua = self.clients[n]
                lua.globals().PARTY = lua.table_from(names)
                lua.globals().nativeLeader = leader

    def advance(self, seconds=1):
        for _ in range(int(seconds * 4)):
            self.clock += .25
            for lua in self.clients.values():
                if self.scheduled:
                    lua.globals().advanceTimers(.25)
                else:
                    lua.globals().CLOCK = self.clock
                    lua.globals().NOW = self.base + int(self.clock - 100)
                    lua.globals().A.WarbandTick()
                    if lua.globals().A.ScoutTick:
                        lua.globals().A.ScoutTick()
            self.deliver()

    def deliver(self):
        for name, lua in self.clients.items():
            g = lua.globals()
            while self.sent[name] < g.sends:
                self.sent[name] += 1
                i = self.sent[name]
                if g.sentPrefixes[i] not in ('WBP_WB1', 'WBP_WBT1', 'WBP_CTL1', 'WBP_REPORT1', 'WBP_SCOUT1'):
                    continue
                packet, route, target = g.packets[i], g.sentRoutes[i], g.sentTargets[i]
                assert len(packet.encode()) <= 255
                for other, peer in self.clients.items():
                    pg = peer.globals()
                    allowed = ((route == 'GUILD' and g.GUILD == pg.GUILD)
                               or (route == 'CHANNEL' and pg.A.ReportChannelID() and g.A.ReportChannelID())
                               or (route == 'WHISPER' and other == target)
                               or (route == 'PARTY' and other in list(g.PARTY.values())))
                    if allowed:
                        if g.sentPrefixes[i] == 'WBP_CTL1':
                            pg.A.OnControlMessage('WBP_CTL1', packet, route, name)
                        elif g.sentPrefixes[i] == 'WBP_REPORT1':
                            pg.A.OnReportMessage('WBP_REPORT1', packet, route, name, '', 0, pg.A.ReportChannelID() or 0, 'TotalWarcraftReportComms')
                        elif g.sentPrefixes[i] == 'WBP_SCOUT1':
                            pg.A.OnScoutMessage('WBP_SCOUT1', packet, route, name, '', 0, pg.A.ReportChannelID() or 0, 'TotalWarcraftReportComms')
                        else:
                            pg.A.OnWarbandMessage(g.sentPrefixes[i], packet, route, name)


def say(lua, cmd):
    lua.globals().SlashCmdList.WARBANDPVP(cmd)


def get(lua, expr):
    return lua.eval(expr)
