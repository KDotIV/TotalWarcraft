"""Spatial/temporal density, pooled art cleanup, compact tooltips and Help flows."""
def check_activity(factory):
    lua=factory('Map Observer')
    lua.execute(r'''
function record(id,reporter,x,y,age,mapID)
 local r={id=id,kind='report',title='PvP activity reported',reporter=reporter,opposition='',note='',
 mapID=mapID or 1,x=x,y=y,faction='Horde',ruleset='pvp',updatedAt=NOW-(age or 0),expiresAt=NOW+300,
 count=0,countUnknown=true,observedCount=0}
 A.records[id]=r; return r
end
local r=record('a','Alice One',.5,.5)
local clusters=A.ReportClusters()
assert(#clusters==1 and clusters[1].size==22 and not clusters[1].pulse and clusters[1].label=='')
record('a2','ALICE-ONE-TestRealm',.51,.5) -- same sender, normalized spelling/realm
clusters=A.ReportClusters(); assert(#clusters==1 and clusters[1].reports==1 and not clusters[1].pulse)
record('b','Bob Two',.51,.51); clusters=A.ReportClusters()
assert(#clusters==1 and clusters[1].reports==2 and clusters[1].pulse and not clusters[1].heavy)
assert(clusters[1].size>22 and clusters[1].size<32)
record('c','Charlie Three',.49,.51); record('d','Delta Four',.50,.49)
clusters=A.ReportClusters(); assert(#clusters==1 and clusters[1].heavy and clusters[1].size==32)
record('far','Far Away',.8,.8); record('zone','Other Zone',.5,.5,0,2)
record('old','Old Report',.5,.5,121)
clusters=A.ReportClusters(); assert(#clusters==3) -- an old nearby pin cannot cover the fresh cluster
assert(clusters[1].reports==4) -- old reports never add heat
A.records.far=nil; A.records.zone=nil; A.records.old=nil
A.AttachMap(); A.RefreshMap()
local pin,n=nil,0
for _,p in ipairs(WorldMapFrame.pool) do if p.active then pin=p; n=n+1 end end
assert(n==1 and pin.activity.heavy and pin.glow:IsShown() and pin.battleEmblem:IsShown())
assert(pin.combatIcon:IsShown() and pin.combatIcon.texture:find('OffensiveStance',1,true))
assert(pin.w==32 and pin.scripts.OnUpdate)
pin.scripts.OnUpdate(pin,.1)
local lines={}
GameTooltip.AddLine=function(_,text) lines[#lines+1]=text end
pin:OnMouseEnter()
local text=table.concat(lines,'\n')
assert(#lines==5 and text:find('Heavy activity',1,true))
for _,bad in ipairs({'unknown','Snapshot','No scouting','100yd','0 combatants'}) do assert(not text:find(bad,1,true),bad) end
-- The marker uses a real report position, not an invented centroid.
assert(pin.normalizedX==pin.record.x and pin.normalizedY==pin.record.y)
local oldPin=pin
A.records={}; r=record('one','Solo One',.25,.75); r.observedCount=6
A.RefreshMap(); assert(oldPin==WorldMapFrame.pool[1])
assert(not oldPin.glow:IsShown() and not oldPin.battleEmblem:IsShown() and not oldPin.scripts.OnUpdate)
assert(oldPin.combatIcon.texture:find('DualWield',1,true))
for _,s in ipairs(oldPin.swordLines) do assert(not s.line:IsShown()) end
-- Missing client artwork still has a visible vector marker.
local texture=oldPin.combatIcon.SetTexture
oldPin.combatIcon.SetTexture=function() return false end
A.RefreshMap(); assert(not oldPin.combatIcon:IsShown())
for _,s in ipairs(oldPin.swordLines) do assert(s.line:IsShown()) end
oldPin.combatIcon.SetTexture=texture; A.RefreshMap()
assert(oldPin.w==22)
lines={}; oldPin:OnMouseEnter(); text=table.concat(lines,'\n')
assert(#lines==5 and text:find('6 combatants',1,true) and not text:find('activity\n',1,true))
A.ShowDetails(r); assert(not A.details.scout:IsShown())
r.scout={state='known',title='Enemy patrol',enemy='Enemy Five',members=5,parties=1,activity='roaming',
 updatedAt=NOW,expiresAt=NOW+90,warbandID='12345678-1234-4123-8123-123456789abc'}
A.ShowDetails(r); assert(A.details.scout:IsShown()); lines={}; oldPin:OnMouseEnter()
assert(#lines==6 and table.concat(lines,'\n'):find('Enemy warband: Enemy patrol',1,true))
NOW=NOW+91; A.RefreshReportSurfaces(); assert(not A.details.scout:IsShown())
-- Intensity decays before the report itself expires.
A.records={}; for i=1,4 do record('hot'..i,'Reporter '..i,.5,.5,90) end
clusters=A.ReportClusters(); assert(#clusters==1 and not clusters[1].heavy and not clusters[1].pulse)
-- Neighbor chains do not join distant reports into one huge hotspot.
A.records={}; record('chain1','One',.1,.1); record('chain2','Two',.13,.1); record('chain3','Three',.16,.1)
assert(#A.ReportClusters()==2)
-- Home and Help remain one-window flows, and ordinary command entry points are documented.
A.ShowHome(); local buttons={}
for _,f in ipairs(frames) do if f.parent==A.home and f.kind=='Button' and f.text then buttons[f.text]=f end end
assert(buttons['Create Warband'] and buttons.Help and not buttons['Report PvP here'] and not buttons.Warbands)
buttons.Help.scripts.OnClick(buttons.Help); assert(A.helpPanel:IsShown() and not A.home:IsShown())
local guide=''
for page=1,9 do
 A.ShowHelp(page); guide=guide..A.helpPanel.body.text
 local lines=0; for _ in (A.helpPanel.body.text..'\n'):gmatch('\n') do lines=lines+1 end
 assert(lines<=18,'Help page exceeds vertical budget: '..page)
end
assert(A.helpPanel.link:IsShown() and A.helpPanel.link.text=='https://github.com/KDotIV/TotalWarcraft/issues')
for _,cmd in ipairs({'/tw report','/tw auto','/tw show','/tw export','/tw finder','/tw invite','/tw watch','/tw state','/tw clear'}) do assert(guide:find(cmd,1,true),cmd) end
A.ShowHelp(2); assert(not A.helpPanel.link:IsShown()); A.BackWindow(); assert(A.home:IsShown())
''')

