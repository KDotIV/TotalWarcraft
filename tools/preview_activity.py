"""Offline SVG projection of actual Lua pin geometry and tooltip strings."""
from pathlib import Path
import html
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
from build_addon import build
import wow_mock
wow_mock.ROOT=build('release')[0]
lua=wow_mock.client('Preview Commander')
lua.execute('''
tooltipLines={}
GameTooltip.AddLine=function(_,text) tooltipLines[#tooltipLines+1]=text end
function previewActivity(n)
 A.records={}
 for i=1,n do
  A.records[tostring(i)]={id=tostring(i),kind='report',title='PvP activity reported',reporter='Scout '..i,
   opposition='',note='',mapID=1,x=.5,y=.5,faction='Horde',ruleset='pvp',updatedAt=NOW,expiresAt=NOW+300,
   count=0,countUnknown=true,observedCount=0}
 end
 A.RefreshMap()
 for _,pin in ipairs(WorldMapFrame.pool) do if pin.active then
  tooltipLines={}; pin:OnMouseEnter()
  local geometry={}
  for _,f in ipairs(frames) do
   if f.parent==pin or (pin.glow and f.parent==pin.glow and pin.glow:IsShown()) then
    if f.kind=='Line' and f.startPoint and f.shown~=false then
     geometry[#geometry+1]={kind='line',a=f.startPoint,b=f.endPoint,color=f.color,width=f.thickness,
      glow=f.parent==pin.glow}
    end
   end
  end
  return pin.w,geometry,tooltipLines,pin.combatIcon.texture,pin.battleEmblem and pin.battleEmblem:IsShown()
 end end
end
''')
cards=[]
for n,title in [(1,'Isolated report'),(2,'Growing conflict'),(4,'Heavy activity')]:
    size,geometry,lines,texture,heavy=lua.globals().previewActivity(n)
    def point(p):
        # Native line anchors: origin at pin's center in this SVG.
        return (p[3]-(size/2 if p[1]=='TOPLEFT' else 0),-p[4]-(size/2 if p[1]=='TOPLEFT' else 0))
    elements=[]
    for f in geometry.values():
        color=f.color; rgb=','.join(str(round(color[i]*255)) for i in range(1,4))
        if f.kind=='line':
            (x1,y1),(x2,y2)=point(f.a),point(f.b)
            elem=f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="rgb({rgb})" stroke-opacity="{color[4]}" stroke-width="{f.width}"/>'
        else:
            elem=f'<rect x="{-f.w/2}" y="{-17-f.h/2}" width="{f.w}" height="{f.h}" fill="rgb({rgb})"/>'
        elements.append((bool(f.glow),elem))
    svg='<g class="pulse">'+''.join(e for glow,e in elements if glow)+'</g>'+''.join(e for glow,e in elements if not glow)
    icon=texture.rsplit('\\',1)[-1].lower()
    svg+=f'<image href="https://wow.zamimg.com/images/wow/icons/large/{icon}.jpg" x="{-size/2}" y="{-size/2}" width="{size}" height="{size}"/>'
    if heavy:
        # Layout stand-in for the client's built-in raid-target skull texture.
        svg+=f'<text x="0" y="{-size/2+2}" text-anchor="middle" font-size="17" fill="white">&#9760;</text>'
    tooltip='<br>'.join(html.escape(line) for line in lines.values())
    cards.append(f'<article><h2>{title}</h2><p>{n} unique recent reporter'+('s' if n!=1 else '')+f'</p><div class="map"><svg viewBox="-48 -48 96 96" width="96" height="96">{svg}</svg></div><div class="tip">{tooltip}</div></article>')
out=ROOT/'docs/assets/activity-preview.html'
out.write_text('''<!doctype html><meta charset="utf-8"><title>TotalWarcraft conflict pins</title>
<style>body{background:#171512;color:#e5d5ba;font:14px Arial;margin:28px}h1{font:24px Georgia;color:#e2bc72}h2{font:18px Georgia;color:#e2bc72}main{display:flex;gap:24px;flex-wrap:wrap}article{width:290px;padding:20px;border:1px solid #654a27;background:#231a12}.map{height:150px;display:grid;place-items:center;background:repeating-linear-gradient(20deg,#51462733 0 2px,transparent 2px 26px),radial-gradient(ellipse,#71623e,#393620);border:1px solid #806239}.tip{margin-top:18px;padding:12px;border:2px solid #8b6d3e;background:#17130feb;font:13px/1.35 Arial}.tip:first-line{color:#e2bc72}.pulse{animation:beat 2s infinite ease-in-out}@keyframes beat{0%,100%{opacity:.3}50%{opacity:.7}}p{color:#baa98b;font-size:12px}footer{max-width:920px;line-height:1.5;margin-top:24px}</style>
<h1>Conflict grows through reports</h1><p>Lua geometry and tooltip text with WoW icon references. Offline preview; tint/crop and the raid-skull badge are approximated.</p><main>'''+''.join(cards)+'''</main><footer>Pins grow from 22 to 32 pixels. Recent nearby reports from different players add heat; duplicate reporters never amplify it. Heavy activity uses the Berserker Stance icon and a small raid-target skull. Tooltips omit unknown counts and missing scouting information. The addon references artwork already in WoW; no downloaded icons are bundled.</footer>''',encoding='utf-8')
print(out)
