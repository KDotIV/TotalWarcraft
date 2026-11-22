local _,A=...
A.palette={gold={.86,.68,.36},red={.78,.22,.14},jade={.34,.72,.57},ink={.09,.065,.045}}
function A.StyleWindow(f)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=false,edgeSize=16,insets={left=5,right=5,top=5,bottom=5}})
    f:SetBackdropColor(.085,.059,.039,1); f:SetBackdropBorderColor(.63,.43,.22,1)
    local wash=f:CreateTexture(nil,"BACKGROUND",nil,1)
    wash:SetPoint("TOPLEFT",10,-10); wash:SetPoint("BOTTOMRIGHT",-10,10)
    wash:SetColorTexture(.17,.115,.065,.55)
    local art=f:CreateTexture(nil,"BORDER")
    art:SetAllPoints(f); art:SetTexture("Interface\\AddOns\\WarbandPvP\\Media\\CampaignFrame")
    f.campaignArt=art
end
function A.Label(parent,x,y,width,value,font)
    local t=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT",x,y); t:SetWidth(width); t:SetJustifyH("LEFT"); t:SetText(value or "")
    return t
end
function A.Button(parent,text,x,y,width,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT",x,y); b:SetSize(width,26); b:SetText(text); b:SetScript("OnClick",A.UIAction(text,fn))
    return b
end
function A.Surface(name,width,height,title)
    local f=CreateFrame("Frame",name,UIParent,"BackdropTemplate")
    f:SetSize(width,height); f:SetPoint("CENTER")
    local close=CreateFrame("Button",nil,f,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-5,-5)
    -- This is our own frame, not a Blizzard UIPanel. Avoid HideUIPanel in combat.
    close:SetScript("OnClick",A.UIAction("close "..name,function() f:Hide() end)); f.ctaClose=close
    f.ctaName=name
    f.heading=A.Label(f,30,-138,width-60,title,"GameFontNormalLarge")
    table.insert(UISpecialFrames,name); A.RegisterWindow(f); f:Hide()
    return f
end
