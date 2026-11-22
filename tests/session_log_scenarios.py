"""Behavioral regressions reused against source and the compiled release."""


def check_session_ui(factory):
    def pair():
        sender, recipient = factory('Reporter One'), factory('Observer Two')
        sender.execute("assert(A.Report()); assert(#A.List()==1 and not A.toast and not A.lastNotice)")
        recipient.globals().packet = sender.globals().packets[1]
        recipient.execute("A.OnReportMessage('WBP_REPORT1',packet,'CHANNEL','Reporter One',nil,nil,7,'TotalWarcraftReportComms')")
        recipient.execute("assert(#A.List()==1 and A.toast:IsShown())")
        return sender, recipient

    sender, recipient = pair()
    sender.globals().packet = sender.globals().packets[1]
    sender.execute('''
A.OnReportMessage('WBP_REPORT1',packet,'CHANNEL','Reporter One',nil,nil,7,'TotalWarcraftReportComms')
A.OnReportMessage('WBP_REPORT1',packet,'GUILD','Reporter One')
assert(#A.List()==1 and not A.toast and not A.lastNotice)
-- Even if a record was removed, an authenticated self echo must not alert.
A.records={}; A.OnReportMessage('WBP_REPORT1',packet,'CHANNEL','Reporter One',nil,nil,7,'TotalWarcraftReportComms')
assert(#A.List()==1 and not A.toast)
''')
    recipient.execute('''
combat=true; function InCombatLockdown() return combat end
function UnitAffectingCombat() return combat end
function ShowUIPanel() error('unexpected native panel action') end
function HideUIPanel() error('unexpected native panel action') end
local before=#frames
A.toast.scripts.OnClick(A.toast,'LeftButton')
assert(#frames==before and not A.details and A.pendingDetails and not A.toast:IsShown())
local log=A.SessionLogText()
assert(log:find('ALERT_CLICK',1,true) and log:find('UI_DEFER',1,true) and log:find('lockdown=true',1,true))
combat=false; emitEvent('PLAYER_REGEN_ENABLED'); advanceTimers(.1)
assert(A.details:IsShown() and not A.pendingDetails)
-- Already-visible details are not repeatedly requeued by refreshes in combat.
combat=true; A.RefreshReportSurfaces(); assert(not A.pendingDetails)
A.details.ctaClose.scripts.OnClick(); assert(not A.details:IsShown())
-- Right-click only dismisses, including during combat.
assert(A.ShowToast(A.List()[1])); A.toast.scripts.OnClick(A.toast,'RightButton')
assert(not A.pendingDetails and not A.toast:IsShown())
''')
    for action in ["NOW=NOW+301", "A.records={}", "A.ShowHome()", "emitEvent('PLAYER_ENTERING_WORLD')"]:
        _, recipient = pair()
        recipient.execute('''
combat=true; function InCombatLockdown() return combat end
A.toast.scripts.OnClick(A.toast,'LeftButton'); assert(A.pendingDetails)
''' + action + '''
combat=false; emitEvent('PLAYER_REGEN_ENABLED'); advanceTimers(.1)
assert(not A.details or not A.details:IsShown()); assert(not A.pendingDetails)
''')

    # A hostile payload cannot declare itself a local submission to hide its alert.
    lua = factory('Local Person')
    lua.execute('''
local r={version=1,id='remote:metadata',kind='report',faction='Horde',ruleset='pvp',mapID=1,x=.2,y=.3,
 title='Report',reporter='Other Person',count=0,countUnknown=true,updatedAt=NOW,expiresAt=NOW+300,localSubmission=true}
assert(A.Receive(r)); assert(not A.List()[1].localSubmission and A.toast:IsShown())
''')

    # Preserve another error handler's normal processing and never inspect locals.
    lua = factory('Journal Reader')
    lua.execute(r'''
nativeErrors=0; hooks=0; loaded={'OpenMap','LayerSwap','Prat-3.0','DialogueUI','AtlasLootClassic'}
C_AddOns={GetNumAddOns=function() return #loaded end, GetAddOnInfo=function(i) return loaded[i] end,
 IsAddOnLoaded=function(n) return true end, GetAddOnMetadata=function(n,key) assert(key=='Version'); return '1.2.3' end}
ScriptErrorsFrame={DisplayMessageInternal=function(self,msg,kind,stack,locals)
 nativeErrors=nativeErrors+1; return 'original-result'
end}
local nativeHandler=function() end
geterrorhandler=function() return nativeHandler end
seterrorhandler=function() error('must not replace the error handler') end
hooksecurefunc=function(object,method,hook)
 hooks=hooks+1; local previous=object[method]
 object[method]=function(...) local result=previous(...); hook(...); return result end
end
emitEvent('ADDON_LOADED','Blizzard_ScriptErrorsFrame'); emitEvent('ADDON_LOADED','OpenMap'); emitEvent('PLAYER_LOGIN')
assert(hooks==1 and geterrorhandler()==nativeHandler)
assert(ScriptErrorsFrame:DisplayMessageInternal('other addon failed',0,'stack path','PRIVATE LOCALS')=='original-result')
ScriptErrorsFrame:DisplayMessageInternal('SECRET',0,'SECRET','PRIVATE LOCALS')
assert(nativeErrors==2)
local log=A.SessionLogText()
assert(log:find('LUA_ERROR',1,true) and log:find('other addon failed',1,true) and log:find('stack path',1,true))
assert(log:find('<restricted>',1,true) and not log:find('PRIVATE LOCALS',1,true))
assert(log:find('interface=16001',1,true) and log:find('LayerSwap=1.2.3',1,true) and log:find('Prat-3.0=1.2.3',1,true))
local wrapped=A.UIAction('failing button',function() error('owned UI error') end)
local ok,err=pcall(wrapped); assert(not ok and err:find('owned UI error',1,true))
local a,b,c=A.UIAction('result preservation',function(...) return ... end)(nil,42,false)
assert(a==nil and b==42 and c==false)
emitEvent('PLAYER_REGEN_DISABLED'); emitEvent('PLAYER_REGEN_ENABLED')
emitEvent('PLAYER_DEAD'); emitEvent('PLAYER_TARGET_CHANGED')
emitEvent('UI_ERROR_MESSAGE',123,'Cannot do that in combat')
for i=1,1000 do A.Trace('FLOOD','routine') end
emitEvent('ADDON_ACTION_BLOCKED','WarbandPvP','SomeProtectedFunction()')
emitEvent('ADDON_ACTION_FORBIDDEN','LayerSwap','AnotherProtectedFunction()')
for i=1,1600 do CLOCK=CLOCK+1; A.Trace('ROW','row-'..i) end
log=A.SessionLogText()
assert(log:find('ADDON_ACTION_BLOCKED',1,true) and log:find('SomeProtectedFunction()',1,true))
assert(log:find('namedAddon=LayerSwap',1,true) and log:find('UI_LUA_ERROR',1,true))
assert(log:find('row-1600',1,true) and not log:find('row-1\n',1,true))
for i=1,200 do CLOCK=CLOCK+1; emitEvent('ADDON_ACTION_BLOCKED','Other','operation-'..i) end
log=A.SessionLogText()
assert(log:find('operation-200',1,true) and not log:find('operation-1 |',1,true))
for i=1,1000 do emitEvent('ADDON_ACTION_FORBIDDEN','Other','flood') end
assert(#A.SessionLogText()<1100000)
assert(not A.SessionLogText():find('issuesOmitted=0',1,true))
assert(geterrorhandler()==nativeHandler and nativeErrors==2 and hooks==1)
''')
