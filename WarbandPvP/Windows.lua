local _,A=...
local windows,history={},{}
local active,transition
local function navigation(f) if f.ctaBack then f.ctaBack:SetEnabled(#history>0) end end
function A.ActiveWindow() return active and active:IsShown() and active or nil end
function A.RaiseWindow(f) f:SetFrameLevel(80) end
function A.CloseWindows()
    transition=true
    for _,f in ipairs(windows) do f:Hide() end
    active=nil; history={}; transition=false
end
function A.BackWindow()
    while #history>0 do
        local previous=table.remove(history)
        if not previous.ctaValid or previous.ctaValid() then
            transition=true
            if active then active:Hide() end
            active=previous; previous:Show(); transition=false
            navigation(previous); return
        end
    end
    A.CloseWindows()
    if A.ShowHome then A.ShowHome() end
end
function A.InvalidateWindow(f)
    for i=#history,1,-1 do if history[i]==f then table.remove(history,i) end end
    if active==f then A.BackWindow() else f:Hide() end
end
function A.RegisterWindow(f)
    if f.ctaWindow then return end
    f.ctaWindow=true; windows[#windows+1]=f
    f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:SetToplevel(true)
    f:SetFrameStrata("DIALOG"); A.RaiseWindow(f)
    if A.StyleWindow then A.StyleWindow(f) end
    local back=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    back:SetSize(70,22); back:SetPoint("BOTTOMLEFT",30,36); back:SetText("< Back")
    back:SetScript("OnClick",A.BackWindow); f.ctaBack=back
    local home=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    home:SetSize(130,22); home:SetPoint("BOTTOMRIGHT",-30,36); home:SetText("Command board")
    home:SetScript("OnClick",function() if A.ShowHome then A.ShowHome() end end)
    local handle=CreateFrame("Frame",nil,f)
    handle:SetPoint("TOPLEFT",4,-4); handle:SetSize(f:GetWidth()-44,32)
    handle:EnableMouse(true); handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart",function() f:StartMoving(); f.ctaDragging=true end)
    handle:SetScript("OnDragStop",function() f:StopMovingOrSizing(); f.ctaDragging=false end)
    f.dragHandle=handle
    f:HookScript("OnShow",function()
        if not transition then
            if active and active~=f and active:IsShown() then
                local found
                for i,v in ipairs(history) do if v==f then found=i; break end end
                if found then for i=#history,found,-1 do table.remove(history,i) end
                else history[#history+1]=active; if #history>12 then table.remove(history,1) end end
            elseif active~=f then history={} end
            transition=true
            for _,other in ipairs(windows) do if other~=f then other:Hide() end end
            transition=false; active=f
        end
        if A.toast then A.toast:Hide() end
        local scale=math.min(1,(UIParent:GetWidth()-16)/f:GetWidth(),(UIParent:GetHeight()-16)/f:GetHeight())
        f:SetScale(math.max(.35,scale)); navigation(f)
    end)
    f:HookScript("OnHide",function()
        if f.ctaDragging then f:StopMovingOrSizing(); f.ctaDragging=false end
        if not transition and active==f then active=nil; history={} end
    end)
end
