"""Shared minimal WoW UI/network mock; never contacts a game client."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1] / "CallToArms"
BOOT = '''
NOW=1794240000; CLOCK=100; frames={}; packets={}; messages={}; sends=0; inGuild=true
sentRoutes={}; sentPrefixes={}; sentTargets={}; attempts=0
function GetServerTime() return NOW end
function GetTime() return CLOCK end
function GetCurrentRegion() return 1 end
function GetNormalizedRealmName() return 'TestRealm' end
function UnitFactionGroup() return 'Horde' end
function UnitName(u) return u=='player' and PLAYER or u end
function UnitGUID(u) return 'Player-'..u end
function UnitIsPlayer(u) return u=='player' or u=='target' or u=='focus' end
function UnitIsPVP() return false end
function UnitDistanceSquared(u) return u=='target' and 10000 or 10001,true end
function InCombatLockdown() return false end
function IsInGuild() return inGuild end
function issecretvalue(v) return v=='SECRET' end
function print(s) table.insert(messages,s) end
Enum={GameRule={HardcoreRuleset=1,RPRuleset=2,PvPRuleset=3},
 SendAddonMessageResult={Success=0},RegisterAddonMessagePrefixResult={Success=0,DuplicatePrefix=1}}
C_GameRules={IsGameRuleActive=function(rule) return rule==3 end}
SlashCmdList={}; UISpecialFrames={}
local methods={}
function methods:RegisterEvent(e) self.events[e]=true end
function methods:UnregisterAllEvents() self.events={} end
function methods:SetScript(e,f) self.scripts[e]=f end
function methods:HookScript(e,f) self.scripts[e]=f end
function methods:CreateFontString() return frame('FontString') end
function methods:CreateTexture() return frame('Texture') end
function methods:CreateLine() return frame('Line') end
function methods:SetStartPoint(...) self.startPoint={...} end
function methods:SetEndPoint(...) self.endPoint={...} end
function methods:SetThickness(n) self.thickness=n end
function methods:SetText(s) self.text=s end
function methods:SetTexture(path)
 error('Report pins must not load file textures')
end
function methods:SetPoint(...) self.point={...} end
function methods:SetSize(w,h) self.w=w; self.h=h end
function methods:GetWidth() return self.w or 1000 end
function methods:GetHeight() return self.h or 600 end
function methods:GetFrameLevel() return 1 end
function methods:SetFrameLevel(level) self.level=level end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetVertexColor(...) self.color={...} end
function methods:SetColorTexture(...) self.color={...} end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetShown(v) self.shown=v end
function methods:IsShown() return self.shown==true end
function methods:GetText() return self.text end
function frame(kind,name,parent)
 local f=setmetatable({kind=kind,events={},scripts={},parent=parent},
 {__index=function(_,k) return methods[k] or (k:match('^[A-Z]') and function() end) or nil end})
 table.insert(frames,f); if name then _G[name]=f end; return f
end
function CreateFrame(kind,name,parent) return frame(kind,name,parent) end
function CreateFromMixins(...)
 local obj={}
 for i=1,select('#',...) do for k,v in pairs(select(i,...)) do obj[k]=v end end
 return obj
end
MapCanvasPinMixin={
 OnReleased=function() end,
 UseFrameLevelType=function(self,t) self.frameLevelType=t end,
 SetScalingLimits=function(self,...) self.scaling={...} end,
 SetAlphaLimits=function(self,...) self.alphaLimits={...} end,
 SetPosition=function(self,x,y)
  self.normalizedX=x; self.normalizedY=y
  self:SetPoint('CENTER',canvas,'TOPLEFT',x*canvas:GetWidth(),-y*canvas:GetHeight())
 end,
}
MapCanvasDataProviderMixin={
 OnAdded=function(self,map) self.owningMap=map end,
 GetMap=function(self) return self.owningMap end,
 OnMapChanged=function(self) self:RefreshAllData() end,
}
UIParent=frame('Root'); GameTooltip=frame('Tooltip')
canvas=frame('Canvas')
WorldMapFrame=frame('Map'); WorldMapFrame.shown=true; WorldMapFrame.map=1
WorldMapFrame.GetCanvas=function() return canvas end
WorldMapFrame.GetMapID=function(self) return self.map end
WorldMapFrame.SetMapID=function(self,id)
 self.map=id; if self.provider then self.provider:OnMapChanged() end
end
WorldMapFrame.OnMapChanged=function() end
WorldMapFrame.pool={}
-- Preserve the critical relative ordering from Blizzard_WorldMap.lua:
-- DEFAULT is BELOW exploration/fog, so it is not a visible report-pin layer.
local pinLevels={PIN_FRAME_LEVEL_DEFAULT=2000, PIN_FRAME_LEVEL_MAP_EXPLORATION=2002,
 PIN_FRAME_LEVEL_FOG_OF_WAR=2006, PIN_FRAME_LEVEL_AREA_POI=2023}
WorldMapFrame.AddDataProvider=function(self,p) self.provider=p; p:OnAdded(self) end
WorldMapFrame.RemoveAllPinsByTemplate=function(self,t)
 assert(t=='CallToArmsMapPinTemplate' or t=='CallToArmsPresencePinTemplate')
 for _,p in ipairs(self.pool) do
  if p.active and p.template==t then p:OnReleased(); p.active=false; p:Hide() end
 end
end
WorldMapFrame.AcquirePin=function(self,t,r,x,y)
 assert(t=='CallToArmsMapPinTemplate' or t=='CallToArmsPresencePinTemplate')
 local pin
 for _,p in ipairs(self.pool) do if not p.active and p.template==t then pin=p; break end end
 if not pin then
  pin=frame('Frame',nil,canvas); pin:SetSize(28,28)
  pin.template=t
  local mixin=t=='CallToArmsMapPinTemplate' and CallToArmsMapPinMixin or CallToArmsPresencePinMixin
  for k,v in pairs(mixin) do pin[k]=v end
  pin:OnLoad(); table.insert(self.pool,pin)
 end
 pin.active=true; pin:Show(); pin:OnAcquired(r,x,y)
 pin:SetFrameLevel(pinLevels[pin.frameLevelType] or pinLevels.PIN_FRAME_LEVEL_DEFAULT)
 assert(pin:GetFrameLevel()>pinLevels.PIN_FRAME_LEVEL_MAP_EXPLORATION)
 assert(pin:GetFrameLevel()>pinLevels.PIN_FRAME_LEVEL_FOG_OF_WAR)
 return pin
end
function hooksecurefunc() end
C_Timer={NewTicker=function(_,fn) return {Cancel=function() end,fn=fn} end,
 NewTimer=function(_,fn) return {Cancel=function() end,fn=fn} end}
C_Map={GetBestMapForUnit=function() return 1 end,
 GetPlayerMapPosition=function() return {GetXY=function() return .25,.75 end} end,
 GetMapInfo=function(id) return {name='Zone '..id} end}
C_ChatInfo={RegisterAddonMessagePrefix=function(p) assert(p=='CTA_REPORT1' or p=='CTA_PRES1' or p=='CTA_CTL1'); return 0 end,
 SendAddonMessage=function(prefix,payload,route,target)
  attempts=attempts+1
  assert(#payload<=255)
  assert((prefix=='CTA_REPORT1' and route=='GUILD') or (prefix=='CTA_PRES1' and (route=='PARTY' or route=='RAID'))
   or (prefix=='CTA_CTL1' and route=='WHISPER' and type(target)=='string'))
  if sendFailure then return 3 end
  packets[#packets+1]=payload; sentRoutes[#packets]=route; sentPrefixes[#packets]=prefix; sentTargets[#packets]=target; sends=sends+1; return 0
 end}
A={}
'''

def client(name):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(BOOT)
    lua.globals().PLAYER = name
    for line in (ROOT/'CallToArms.toc').read_text().splitlines():
        if line.endswith('.lua'):
            lua.execute('assert(loadstring(...))("CallToArms",A)', (ROOT/line).read_text())
    lua.execute('''
    for _,f in ipairs(frames) do if f.events.ADDON_LOADED then core=f end end
    core.scripts.OnEvent(nil,'ADDON_LOADED','CallToArms')
    core.scripts.OnEvent(nil,'PLAYER_LOGIN')
    assert(sends==0 and A.scopeRuleset=='pvp' and A.scopeRegion==1 and A.guildReady)
    ''')
    return lua

