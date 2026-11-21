"""User-flow regressions: exclusive panels, backtracking, expiry and input retention."""
from wow_mock import client
lua=client('Window Tester')
lua.execute('''
function only(expected)
 local n=0
 for _,f in ipairs(frames) do if f.ctaWindow and f:IsShown() then n=n+1; assert(f==expected) end end
 assert(n==1 and A.ActiveWindow()==expected)
end
A.SetTestMode(true); assert(A.SetWarbandSimulation('5')); assert(A.StartWarband('Window test'))
for _,size in ipairs({{1920,1080},{1000,744},{696,744},{640,480}}) do
 UIParent:SetSize(size[1],size[2]); A.CloseWindows()
 A.ShowHome(); only(A.home)
 A.ShowWarbands(); local board=A.warbands.panel; only(board)
 board.name:SetText('Keep this input')
 A.ShowWarbandDetails(A.WarbandList()[1]); local detail=A.warbands.details; only(detail)
 A.RefreshWarbandUI(); only(detail)
 detail.dragHandle.scripts.OnDragStart(); detail.dragHandle.scripts.OnDragStop(); only(detail)
 A.BackWindow(); only(board); assert(board.name:GetText()=='Keep this input' and A.warbands.host)
 A.BackWindow(); only(A.home)
 A.ShowExport(); only(A.exportPanel); A.BackWindow(); only(A.home)
 A.ShowPresence(); only(A.presencePanel); A.ShowBindings(); only(A.bindingPanel)
 A.ShowHome(); only(A.home); A.BackWindow(); only(A.home)
end
-- History skips expired details instead of showing stale actionable controls.
A.ShowWarbands(); A.ShowWarbandDetails(A.WarbandList()[1]); A.ShowExport()
A.warbands.records={}; A.BackWindow(); only(A.warbands.panel)
-- Closing via Escape/close does not reopen previous dialogs unexpectedly.
A.warbands.panel:Hide(); assert(A.ActiveWindow()==nil)
A.ShowHelp(); only(A.helpPanel); A.BackWindow(); only(A.home)
-- Opening a map releases the TotalWarcraft panel; no toast covers an active TotalWarcraft window.
A.OpenMap({mapID=1}); assert(A.ActiveWindow()==nil and WorldMapFrame:IsShown())
A.ShowHome(); A.ShowToast({}); assert(not A.toast or not A.toast:IsShown()); only(A.home)
''')
print('PASS: one active TotalWarcraft dialog at all sizes, Back history, expired details, retained inputs, drag, close, map navigation and toast suppression.')
