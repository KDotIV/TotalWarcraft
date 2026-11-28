"""Native minimap positioning and lifecycle; reused against the compiled release."""

SETUP = r'''
Minimap=CreateFrame('Minimap',nil,UIParent); Minimap:SetSize(200,200); Minimap:Show()
Minimap.IsVisible=Minimap.IsShown
nativeHidden=0; Minimap:SetScript('OnHide',function() nativeHidden=nativeHidden+1 end)
viewRadius=100; heading=0; rotating=false; ignoreRotation=false; shape='ROUND'
worldID=0; playerNorth=0; playerWest=0; playerMap=1; positionReads=0; conversions=0
Enum.UIMapType={Continent=2,Zone=3,Dungeon=4,Micro=5}
mapTypes={}; mapWorlds={[9]=1}; mapOffsets={[2]=100}
function CreateVector2D(x,y) return {GetXY=function() return x,y end} end
C_Map.GetBestMapForUnit=function() return playerMap end
C_Map.GetMapInfo=function(id) return {name='Zone '..id,mapType=mapTypes[id] or 3} end
C_Map.GetWorldPosFromMapPos=function(id,pos)
 conversions=conversions+1
 local x,y=pos:GetXY()
 return mapWorlds[id] or 0,CreateVector2D(500-y*1000,500-x*1000+(mapOffsets[id] or 0))
end
C_Map.GetPlayerMapPosition=function()
 return CreateVector2D((500-playerWest+(mapOffsets[playerMap] or 0))/1000,(500-playerNorth)/1000)
end
function UnitPosition() positionReads=positionReads+1; return playerNorth,playerWest,0,worldID end
function GetPlayerFacing() return heading end
function GetMinimapShape() return shape end
C_CVar={GetCVarBool=function() return rotating end}
C_Minimap={GetViewRadius=function() return viewRadius end,IsRotateMinimapIgnored=function() return ignoreRotation end}
function point(id,east,north,map,reporter,age,ttl)
 map=map or 1
 local r={version=1,id=id,kind='report',faction='Horde',ruleset='pvp',mapID=map,
 x=(500+east+(mapOffsets[map] or 0))/1000,y=(500-north)/1000,
 title='PvP activity reported',reporter=reporter or ('Reporter '..id),updatedAt=NOW-(age or 0),expiresAt=NOW+(ttl or 300),
 count=0,countUnknown=true}
 assert(A.Receive(r)); return A.records[id]
end
function pins()
 local result={}
 for _,p in ipairs(A.minimapReports.pins) do if p.record and p:IsShown() then result[p.record.id]=p end end
 return result
end
function close(actual,expected) assert(math.abs(actual-expected)<.0001,tostring(actual)..' ~= '..expected) end
function checkPin(id,x,y)
 local p=pins()[id]; assert(p,'missing pin '..id)
 assert(p.parent==Minimap and p.point[2]==Minimap)
 close(p.point[4],x); close(p.point[5],y); return p
end
WorldMapFrame:Hide(); emitEvent('PLAYER_ENTERING_WORLD')
'''


def check_minimap(factory):
    def fresh():
        lua = factory('Minimap Observer')
        lua.execute(SETUP)
        return lua

    lua = fresh()
    lua.execute('''
assert(A.db.minimapReports and not A.minimapReports.timer and activeTimers()==0)
point('east',40,0); point('north',0,40); point('west',-40,0); point('south',0,-40)
checkPin('east',40,0); checkPin('north',0,40); checkPin('west',-40,0); checkPin('south',0,-40)
assert(A.minimapReports.count==4 and A.minimapReports.interval==.1 and sends==0 and not WorldMapFrame:IsShown())
local before=conversions; local reads=positionReads; local count=#frames
advanceTimers(1.01)
assert(conversions==before and #frames==count and positionReads-reads<=11)
playerWest=-10; advanceTimers(.11); checkPin('east',30,0); checkPin('west',-50,0)
rotating=true; heading=math.pi/2; emitEvent('CVAR_UPDATE','rotateMinimap')
checkPin('east',0,-30); checkPin('north',40,10)
ignoreRotation=true; emitEvent('CVAR_UPDATE','rotateMinimap'); checkPin('east',30,0)
ignoreRotation=false; rotating=false; emitEvent('CVAR_UPDATE','rotateMinimap')
viewRadius=200; emitEvent('MINIMAP_UPDATE_ZOOM'); checkPin('east',15,0)
Minimap:SetSize(400,200); advanceTimers(.11); checkPin('east',30,0)
Minimap:SetFrameLevel(20); advanceTimers(.11); assert(pins().east:GetFrameLevel()==25)
-- Unchanged geometry never rewrites native icon placement between data refreshes.
local p=pins().east; local place=p.SetPoint; local writes=0
p.SetPoint=function(self,...) writes=writes+1; place(self,...) end
advanceTimers(1.01); assert(writes==0)
''')

    # Clip before clustering; the newest off-screen point cannot hide its neighbor.
    lua = fresh()
    lua.execute('''
point('outside',105,0,1,'Newest'); point('inside',80,0,1,'Older',1)
assert(A.minimapReports.count==1); checkPin('inside',80,0)
A.ClearReports(); point('one',0,0,1,'Same Name'); point('two',5,0,1,'SAME-NAME-TestRealm',1)
assert(A.minimapReports.count==1 and A.minimapReports.groups[1].count==1)
point('three',10,0,1,'Other Name',2)
assert(A.minimapReports.count==1 and A.minimapReports.groups[1].count==2)
local first=pins().one; assert(first and first.activity.label=='2 nearby reporters')
A.ClearReports(); point('corner',75,75); assert(A.minimapReports.count==0 and A.minimapReports.interval==1)
shape='SQUARE'; emitEvent('MINIMAP_UPDATE_ZOOM'); checkPin('corner',75,75)
shape='UNKNOWN'; emitEvent('MINIMAP_UPDATE_ZOOM'); assert(A.minimapReports.count==0)
shape='ROUND'; A.ClearReports(); point('far',250,0)
assert(A.minimapReports.count==0 and A.minimapReports.interval==1)
viewRadius=400; emitEvent('MINIMAP_UPDATE_ZOOM'); checkPin('far',62.5,0)
viewRadius=100; emitEvent('MINIMAP_UPDATE_ZOOM'); assert(A.minimapReports.count==0)
playerWest=-220; advanceTimers(1.01); checkPin('far',30,0); assert(A.minimapReports.interval==.1)
A.ClearReports(); playerWest=0
point('chain1',0,0); point('chain2',15,0); point('chain3',30,0)
assert(A.minimapReports.count==2 and #A.ReportClusters()==1)
''')

    # World coordinates handle adjacent outdoor zones; floors/worlds are isolated.
    lua = fresh()
    lua.execute('''
point('adjacent',40,0,2); checkPin('adjacent',40,0)
point('otherworld',0,0,9); assert(not pins().otherworld)
mapTypes[3]=5; point('basement',0,0,3); assert(not pins().basement)
playerMap=3; emitEvent('ZONE_CHANGED_INDOORS')
assert(A.minimapReports.count==1); checkPin('basement',0,0)
worldID=2; emitEvent('PLAYER_ENTERING_WORLD'); assert(A.minimapReports.count==0 and not A.minimapReports.timer)
worldID=0; playerMap=1; emitEvent('PLAYER_ENTERING_WORLD'); checkPin('adjacent',40,0)
local coords=UnitPosition; UnitPosition=nil; advanceTimers(.11); checkPin('adjacent',40,0)
UnitPosition=coords
-- World changes invalidate cached report transforms even with a hidden minimap.
Minimap:Hide(); mapWorlds[2]=2; worldID=2; emitEvent('PLAYER_ENTERING_WORLD')
Minimap:Show(); checkPin('adjacent',40,0)
''')

    # Visibility/configuration/loading control the single positioning timer.
    lua = fresh()
    lua.execute('''
point('live',30,0); local before=#frames; local controller=A.minimapReports; local original=pins().live
local cancelled=controller.timer
Minimap:Hide(); assert(not controller.timer and controller.count==0 and nativeHidden==1)
local reads=positionReads; advanceTimers(2); cancelled.fn(); assert(positionReads==reads and controller.count==0)
Minimap:Show(); checkPin('live',30,0); assert(#frames==before)
SlashCmdList.WARBANDPVP('minimap off'); assert(not A.db.minimapReports and not controller.timer)
reads=positionReads; local converts=conversions; advanceTimers(16)
assert(positionReads==reads and conversions==converts)
SlashCmdList.WARBANDPVP('minimap on'); checkPin('live',30,0)
A.ShowHome(); A.home.minimap.scripts.OnClick(); assert(not A.db.minimapReports)
A.home.minimap.scripts.OnClick(); assert(A.db.minimapReports); A.CloseWindows()
emitEvent('PLAYER_LEAVING_WORLD'); assert(not controller.timer and controller.count==0)
A.Changed(); assert(not controller.timer)
emitEvent('PLAYER_ENTERING_WORLD'); checkPin('live',30,0)
emitEvent('SHARD_TRANSFER_IMMINENT'); assert(controller.count==0 and not controller.timer)
emitEvent('SHARD_TRANSFER_CANCELLED'); checkPin('live',30,0)
A.ClearReports(); assert(controller.count==0 and not controller.timer and activeTimers()==0)
point('reused',0,30); assert(#controller.pins==1 and pins().reused==original); checkPin('reused',0,30)
emitEvent('PLAYER_LOGOUT'); assert(controller.count==0 and not controller.timer)
''')

    # Expiry is checked by the renderer, not delayed until the 15-second prune.
    lua = fresh()
    lua.execute('''
point('short',30,0,1,'Short Reporter',0,2)
local p=pins().short; p.scripts.OnEnter(p); assert(A.tooltipRecord and A.minimapReports.hover==p)
advanceTimers(2.1); assert(A.minimapReports.count==0 and not A.minimapReports.timer)
assert(not A.tooltipRecord and not A.minimapReports.hover)
A.ClearReports(); point('click',20,0); p=pins().click
combat=true; InCombatLockdown=function() return combat end
p.scripts.OnClick(p,'LeftButton'); assert(A.pendingDetails=='click' and not A.details)
combat=false; emitEvent('PLAYER_REGEN_ENABLED'); advanceTimers(.01)
assert(A.details:IsShown()); A.CloseWindows()
p.scripts.OnEnter(p); A.ClearReports(); assert(not A.minimapReports.hover and not A.tooltipRecord)
''')

    # Restricted/missing/bad native values cannot leak into coordinate arithmetic.
    for mutation in [
        "viewRadius='SECRET'", 'viewRadius=0', 'viewRadius=0/0', 'viewRadius=math.huge',
        "rotating=true; heading='SECRET'", 'rotating=true; GetPlayerFacing=function() end',
        "C_CVar.GetCVarBool=function() return 'SECRET' end",
        "Minimap.GetWidth=function() return 'SECRET' end",
        "C_Map.GetBestMapForUnit=function() return 'SECRET' end",
        "UnitPosition=function() return 0,0,0,'SECRET' end; C_Map.GetPlayerMapPosition=function() return 'SECRET' end",
        "UnitPosition=function() error('unavailable') end; C_Map.GetPlayerMapPosition=function() return nil end",
        'IsInInstance=function() return true end',
    ]:
        lua=fresh()
        lua.execute("point('bad',30,0); "+mutation+"; advanceTimers(.11); assert(A.minimapReports.count==0)")
    for mutation in [
        "C_Map.GetWorldPosFromMapPos=function() return 'SECRET',CreateVector2D(0,0) end",
        "C_Map.GetWorldPosFromMapPos=function() return 0,CreateVector2D('SECRET',0) end",
        "C_Map.GetWorldPosFromMapPos=function() error('unavailable') end",
        'C_Map.GetWorldPosFromMapPos=nil', 'C_Minimap=nil',
    ]:
        lua=fresh()
        lua.execute(mutation+"; point('bad',30,0); assert(A.minimapReports.count==0 and not A.minimapReports.timer)")

    lua=fresh()
    lua.execute('''
local convert=C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos=function() end
point('retry',30,0); assert(A.MinimapReportStatus()=='report coordinates unavailable')
C_Map.GetWorldPosFromMapPos=convert; emitEvent('PLAYER_REGEN_ENABLED'); checkPin('retry',30,0)
''')

    # Bounded work, cache reuse, reset, and icons for accepted local/peer reports.
    lua=fresh()
    lua.execute('''
for i=1,64 do point('r'..i,((i-1)%8-3.5)*20,(math.floor((i-1)/8)-3.5)*20) end
assert(#A.minimapReports.entries==64 and #A.minimapReports.pins<=64)
local before=conversions; local allocated=#frames; local reads=positionReads
advanceTimers(1.01); assert(conversions==before and #frames==allocated and positionReads-reads<=11 and sends==0)
for _,p in ipairs(A.minimapReports.pins) do assert(not p.scripts.OnUpdate) end
point('overflow',0,0); assert(#A.minimapReports.entries==64)
C_GameRules.IsGameRuleActive=function() return false end; emitEvent('GAME_RULES_CHANGED')
assert(A.minimapReports.count==0 and not A.minimapReports.timer)
''')

    alice,bob=fresh(),fresh()
    alice.execute("assert(A.Report()); assert(A.minimapReports.count==1 and not A.toast); advanceTimers(1); assert(sends==1)")
    packet=alice.globals().packets[1]
    bob.globals().A.OnReportMessage('WBP_REPORT1',packet,'CHANNEL','Other Reporter',None,None,7,'TotalWarcraftReportComms')
    bob.execute('assert(A.minimapReports.count==1 and sends==0)')

    lua=fresh()
    lua.execute('sendFailure=true; assert(not A.Report()); assert(A.minimapReports.count==0 and not A.minimapReports.timer)')
    from auto_report_scenarios import SETUP as COMBAT
    lua=fresh(); lua.execute(COMBAT)
    lua.execute('''
function UnitPlayerControlled(u) return UnitIsPlayer(u) end
fight(); advanceTimers(4); event('UNIT_COMBAT','target','WOUND'); advanceTimers(1)
assert(combat and A.minimapReports.count==1 and reportCount()==1 and not WorldMapFrame:IsShown())
advanceTimers(1); assert(reportCount()==1)
''')
