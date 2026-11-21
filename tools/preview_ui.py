"""Render an offline layout reference from the real Lua frames, not a WoW screenshot."""
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
function preview(root)
 local result={}
 local function walk(parent,ox,oy)
  for _,f in ipairs(frames) do if f.parent==parent and f.shown~=false then
   local p=f.point or {}; local anchor=p[1]; local x,y=p[2],p[3]
   if type(x)~='number' then x,y=p[4],p[5] end
   x,y=x or 0,y or 0
   if anchor=='BOTTOMLEFT' then y=-root.h+y+(f.h or 22)
   elseif anchor=='BOTTOMRIGHT' then x=root.w+x-(f.w or 130); y=-root.h+y+(f.h or 22) end
   if f.text and f.text~='' then result[#result+1]={text=f.text,kind=f.kind,font=f.font or '',x=ox+x,y=oy-y,w=f.w or 400,h=f.h or 0} end
   walk(f,ox+x,oy-y)
  end end
 end
 walk(root,0,0); return result
end
''')
views=[('Command board','A.ShowHome()','A.home'),('Warbands','A.ShowWarbands()','A.warbands.panel'),
       ('Recruitment','A.ShowFinder()','A.finder.panel'),
       ('Field reports','A.BuildUI(); A.panel:Show()','A.panel'),('Group locations','A.ShowPresence()','A.presencePanel'),
       ('Help: reports','A.ShowHelp(2)','A.helpPanel'),('Help: support','A.ShowHelp(9)','A.helpPanel'),
       ('Bindings','A.ShowBindings()','A.bindingPanel')]
lua.execute('''
A.Report(); previewReport=A.List()[1]
previewReport.observedCount=6
previewReport.scout={state='known',enemy='Observed Enemy',title='Roaming patrol',
 members=12,parties=3,activity='roaming',updatedAt=GetServerTime(),expiresAt=GetServerTime()+90,
 warbandID='12345678-1234-4123-8123-123456789abc'}
''')
views += [('Field report','A.ShowDetails(previewReport)','A.details'),
          ('Enemy scouting','A.ShowEnemyScout(previewReport)','A.scouting.panel')]
sections=[]
for name,command,expr in views:
    lua.execute(command)
    frame=lua.eval(expr)
    elements=[]
    for item in lua.globals().preview(frame).values():
        cls='control' if item.kind=='Button' else 'label'
        size=18 if 'Large' in item.font else 13 if item.font=='GameFontNormal' else 12
        color='#e2bc72' if 'Normal' in item.font else '#e5d5ba'
        style=f'left:{item.x}px;top:{item.y}px;width:{item.w}px;font-size:{size}px;color:{color};'
        if cls=='control': style+=f'height:{item.h}px;'
        elements.append(f'<div class="{cls}" style="{style}">{html.escape(item.text)}</div>')
    sections.append(f'<section><h2>{name}</h2><div class="panel" style="width:{frame.w}px;height:{frame.h}px">'+''.join(elements)+'</div></section>')
document='''<!doctype html><meta charset="utf-8"><title>TotalWarcraft layout reference</title>
<style>body{background:#171512;color:#ddcba8;font:14px Arial;margin:22px}h1{font-size:20px}h2{font-size:16px}main{display:flex;gap:30px;flex-wrap:wrap}.panel{position:relative;background:url(campaign-frame-source-v1.png) center/100% 100% no-repeat}.label,.control{position:absolute;box-sizing:border-box;white-space:pre-wrap;line-height:1.35}.label{padding:0}.control{background:linear-gradient(#651c15,#330f0d);border:1px solid #ab7a3d;box-shadow:inset 0 0 0 2px #20140d;text-align:center;line-height:24px;border-radius:3px;font:13px/24px Georgia}.label:has(+.nothing){display:none}</style>
<h1>TotalWarcraft — offline layout reference</h1><p>Generated from Lua frame positions. Browser font approximation; this is not an in-game screenshot.</p><main>'''+''.join(sections)+'''</main><script>
const view=new URLSearchParams(location.search).get('view');
if(view) document.querySelectorAll('section').forEach(s=>{if(s.querySelector('h2').textContent!==view)s.remove()});
</script>'''
out=ROOT/'docs/assets/ui-layout-preview.html'
out.write_text(document,encoding='utf-8')
print(out)
