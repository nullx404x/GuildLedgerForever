local _,G=...
local U={tab="Guild Loot",section="Spec",offset=0,detailOffset=0,query="",online=false,role="Any role",class="Any class",spec="Any spec",rows={},details={}}
G.UI=U
local gold={0.88,0.73,0.43}
-- Use Blizzard's shared tooltip so tooltip addons can hook and style it.
local GameTooltip=_G.GameTooltip

local slots={"Head","Neck","Shoulder","Shirt","Chest","Waist","Legs","Feet","Wrist","Hands","Finger 1","Finger 2","Trinket 1","Trinket 2","Back","Main hand","Off hand","Ranged","Tabard"}
local function label(parent,text,size,x,y,width)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f:SetPoint("TOPLEFT",x,y); f:SetWidth(width or 300); f:SetJustifyH("LEFT"); f:SetWordWrap(false)
    f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",math.max(12,(size or 12)+1),""); f:SetTextColor(0.85,0.88,0.91); f:SetText(text); return f
end
-- Solid inset edges stay continuous at fractional UI scales. A sliced WHITE8X8
-- backdrop edge is not a border atlas and can leave missing sides/corners.
local function solidBorder(frame)
    local edges={}
    for i=1,4 do
        local edge=frame:CreateTexture(nil,"OVERLAY",nil,7); edges[i]=edge
        if edge.SetSnapToPixelGrid then edge:SetSnapToPixelGrid(false); edge:SetTexelSnappingBias(0) end
        if i==1 or i==2 then
            local side=i==1 and "TOP" or "BOTTOM"
            edge:SetPoint(side.."LEFT",0,0); edge:SetPoint(side.."RIGHT",0,0); edge:SetHeight(2)
        else
            local side=i==3 and "LEFT" or "RIGHT"
            edge:SetPoint("TOP"..side,0,-2); edge:SetPoint("BOTTOM"..side,0,2); edge:SetWidth(2)
        end
    end
    frame.SetBackdropBorderColor=function(_,r,g,b,a) for _,edge in ipairs(edges) do edge:SetColorTexture(r,g,b,a or 1) end end
end
local function panel(parent,w,h,x,y,name)
    local f=CreateFrame("Frame",name,parent,"BackdropTemplate")
    f:SetSize(w,h); f:SetPoint("TOPLEFT",x,y)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",insets={left=2,right=2,top=2,bottom=2}})
    solidBorder(f)
    f:SetBackdropColor(0.035,0.045,0.060,0.98); f:SetBackdropBorderColor(0.16,0.19,0.23,1)
    return f
end
local function button(parent,text,w,x,y,fn)
    local b=CreateFrame("Button",nil,parent,"BackdropTemplate")
    b:SetSize(w,28); b:SetPoint("TOPLEFT",x,y)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",insets={left=2,right=2,top=2,bottom=2}})
    solidBorder(b)
    b:SetBackdropColor(0.10,0.12,0.14,1); b:SetBackdropBorderColor(0.21,0.24,0.28,1)
    b.text=label(b,text,12,6,0,w-12); b.text:ClearAllPoints(); b.text:SetPoint("CENTER",0,0); b.text:SetJustifyH("CENTER")
    b.SetSelected=function(self,selected)
        self.selected=selected==true
        self:SetBackdropBorderColor(unpack(self.selected and {0.43,0.41,0.34,1} or {0.21,0.24,0.28,1}))
        self:SetBackdropColor(unpack(self.selected and {0.15,0.16,0.17,1} or {0.10,0.12,0.14,1}))
    end
    b:SetScript("OnEnter",function() b:SetBackdropColor(0.18,0.19,0.20,1) end)
    b:SetScript("OnLeave",function() b:SetSelected(b.selected); GameTooltip:Hide() end)
    b:SetScript("OnClick",fn); return b
end
-- Small native icons leave the text readable at every supported UI scale.
local function buttonIcon(b,texture)
    b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetSize(18,18); b.icon:SetPoint("LEFT",8,0)
    b.icon:SetTexture(texture); b.icon:SetTexCoord(0.07,0.93,0.07,0.93)
    b.text:ClearAllPoints(); b.text:SetPoint("LEFT",30,0); b.text:SetWidth(b:GetWidth()-38)
end
local classIcons={
    [1]="Ability_Warrior_SavageBlow",[2]="Spell_Holy_SealOfMight",[3]="INV_Weapon_Bow_07",
    [4]="Ability_BackStab",[5]="Spell_Holy_WordFortitude",[7]="Spell_Nature_Lightning",
    [8]="INV_Staff_13",[9]="Spell_Shadow_CurseOfTounges",[11]="Ability_Druid_Maul",
}
local function classIcon(member)
    local name=member and classIcons[member.class]
    return name and ("Interface\\Icons\\"..name) or nil
end
local function edit(parent,w,x,y,fn)
    local e=CreateFrame("EditBox",nil,parent,"BackdropTemplate")
    e:SetSize(w,28); e:SetPoint("TOPLEFT",x,y); e:SetAutoFocus(false); e:SetMaxLetters(200)
    e:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",13,""); e:SetTextInsets(10,10,0,0)
    e:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); solidBorder(e)
    e:SetBackdropColor(0.035,0.045,0.060,1); e:SetBackdropBorderColor(0.30,0.33,0.38,1)
    e:SetScript("OnEditFocusGained",function(self) self:SetBackdropBorderColor(unpack(gold)) end)
    e:SetScript("OnEditFocusLost",function(self) self:SetBackdropBorderColor(0.30,0.33,0.38,1) end)
    e:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
    e:SetScript("OnTextChanged",function(self,user) if user then fn(self:GetText()) end end)
    return e
end
local function nameColor(name)
    local m=G.members[name]
    if m and m.class then
        local info=G.Safe(C_CreatureInfo and C_CreatureInfo.GetClassInfo,m.class)
        local c=info and RAID_CLASS_COLORS[info.classFile]
        if c then return c.r,c.g,c.b end
    end
    return 0.85,0.85,0.85
end
local function className(m)
    local info=m and G.Safe(C_CreatureInfo and C_CreatureInfo.GetClassInfo,m.class)
    return info and info.className or "Unknown class"
end
local primarySkills={[164]=true,[165]=true,[171]=true,[182]=true,[186]=true,[197]=true,[202]=true,[333]=true,[393]=true}
function G.OrderedProfessions(d)
    local list={}; for _,p in ipairs(d and d.professions or {}) do list[#list+1]=p end
    table.sort(list,function(a,b)
        local ap,bp=primarySkills[a.id] and 0 or 1,primarySkills[b.id] and 0 or 1
        if ap~=bp then return ap<bp end
        return a.name<b.name
    end)
    return list
end
local function professionNames(d)
    local a={}; for _,p in ipairs(G.OrderedProfessions(d)) do a[#a+1]=p.name.." "..p.rank.."/"..p.max end
    return #a>0 and table.concat(a,", ") or "Professions not scanned"
end
local function talentNames(d)
    local a={}; for _,t in ipairs(d and d.trees or {}) do a[#a+1]=t.name.." "..t.points end
    return #a>0 and table.concat(a," / ") or "Talents not scanned"
end
-- Tree names are authoritative; a dominant tree is a summary, not an inferred role.
function G.SpecSummary(d)
    if not d or not d.trees or #d.trees==0 then return "Not shared", "" end
    local names,points,highest={},{},0
    for _,tree in ipairs(d.trees) do
        points[#points+1]=tostring(tree.points)
        if tree.points>highest then highest=tree.points; names={tree.name}
        elseif tree.points==highest and highest>0 then names[#names+1]=tree.name end
    end
    if highest==0 then return "Unspent",table.concat(points," / ") end
    return table.concat(names," / "),table.concat(points," / ")
end
local specIcons={
    [1]={Arms="Ability_Warrior_SavageBlow",Fury="Ability_Warrior_InnerRage",Protection="Ability_Warrior_DefensiveStance"},
    [2]={Holy="Spell_Holy_HolyBolt",Protection="Spell_Holy_DevotionAura",Retribution="Spell_Holy_AuraOfLight"},
    [3]={["Beast Mastery"]="Ability_Hunter_BeastTaming",Marksmanship="Ability_Marksmanship",Survival="Ability_Hunter_SwiftStrike"},
    [4]={Assassination="Ability_Rogue_Eviscerate",Combat="Ability_BackStab",Subtlety="Ability_Stealth"},
    [5]={Discipline="Spell_Holy_PowerWordShield",Holy="Spell_Holy_GuardianSpirit",Shadow="Spell_Shadow_ShadowWordPain"},
    [7]={Elemental="Spell_Nature_Lightning",Enhancement="Spell_Nature_LightningShield",Restoration="Spell_Nature_MagicImmunity"},
    [8]={Arcane="Spell_Holy_MagicalSentry",Fire="Spell_Fire_FireBolt02",Frost="Spell_Frost_FrostBolt02"},
    [9]={Affliction="Spell_Shadow_DeathCoil",Demonology="Spell_Shadow_Metamorphosis",Destruction="Spell_Shadow_RainOfFire"},
    [11]={Balance="Spell_Nature_StarFall",["Feral Combat"]="Ability_Racial_BearForm",Feral="Ability_Racial_BearForm",Restoration="Spell_Nature_HealingTouch"},
}
function G.RosterIcon(member,d)
    local spec=G.SpecSummary(d)
    local icon=member and specIcons[member.class] and specIcons[member.class][spec]
    return icon and ("Interface\\Icons\\"..icon) or classIcon(member)
end
-- Conservative defaults for Classic trees. Unknown/localized trees remain unassigned.
-- Feral and tied trees can have multiple roles; explicit player choices always win.
local roleTrees={
    [1]={Arms={"DPS"},Fury={"DPS"},Protection={"Tank"}},
    [2]={Holy={"Healer"},Protection={"Tank"},Retribution={"DPS"}},
    [3]={["Beast Mastery"]={"DPS"},Marksmanship={"DPS"},Survival={"DPS"}},
    [4]={Assassination={"DPS"},Combat={"DPS"},Subtlety={"DPS"}},
    [5]={Discipline={"Healer"},Holy={"Healer"},Shadow={"DPS"}},
    [7]={Elemental={"DPS"},Enhancement={"DPS"},Restoration={"Healer"}},
    [8]={Arcane={"DPS"},Fire={"DPS"},Frost={"DPS"}},
    [9]={Affliction={"DPS"},Demonology={"DPS"},Destruction={"DPS"}},
    [11]={Balance={"DPS"},["Feral Combat"]={"Tank","DPS"},Feral={"Tank","DPS"},Restoration={"Healer"}},
}
function G.EffectiveRoles(m,d)
    if d and d.roles and #d.roles>0 then return d.roles,"Chosen" end
    local map=m and roleTrees[m.class]
    local maximum,seen=0,{}
    for _,t in ipairs(d and d.trees or {}) do maximum=math.max(maximum,t.points) end
    if maximum>0 and map then
        for _,t in ipairs(d.trees) do
            if t.points==maximum then
                if not map[t.name] then return {},"Unknown" end
                for _,role in ipairs(map[t.name]) do seen[role]=true end
            end
        end
    end
    local roles={}; for _,role in ipairs({"Tank","Healer","DPS"}) do if seen[role] then roles[#roles+1]=role end end
    return roles,#roles>0 and "Auto" or "Unknown"
end
function G.SpecMatches(d,spec)
    if spec=="Any spec" then return true end
    local maximum=0; for _,t in ipairs(d and d.trees or {}) do maximum=math.max(maximum,t.points) end
    for _,t in ipairs(d and d.trees or {}) do if t.points==maximum and maximum>0 and t.name==spec then return true end end
    return false
end
function G.RecipeKey(r,professionID)
    return professionID..":"..tostring(r.id or r.name)..":"..tostring(r.link)
end
function G.EnsureCrafterIndex()
    local revision=G.Revision("profession")..":"..G.Revision("membership")
    if not G.crafterIndex or G.crafterRevision~=revision then
        local index,recipes={},{}
        for _,r in pairs(G.store and G.store.records or {}) do
            if r.kind=="profession" and not r.deleted and G.members[r.owner] then
                for _,recipe in G.Recipes(r) do
                    local id=G.ItemID(recipe.link)
                    if id then index[id]=index[id] or {}; index[id][r.owner]=true end
                    local key=G.RecipeKey(recipe,r.data.id)
                    recipes[key]=recipes[key] or {}; recipes[key][r.owner]=true
                end
            end
        end
        G.crafterIndex={}
        for id,names in pairs(index) do G.crafterIndex[id]=G.Keys(names) end
        G.recipeCrafterIndex={}
        for key,names in pairs(recipes) do G.recipeCrafterIndex[key]=G.Keys(names) end
        G.crafterRevision=revision
    end
end
function G.Crafters(itemID)
    G.EnsureCrafterIndex()
    return G.crafterIndex[itemID] or {}
end
local function itemText(link)
    if not link then return "Unavailable",nil end
    local name,full,_,_,_,_,_,_,_,icon=G.Safe(C_Item and C_Item.GetItemInfo,link)
    local spell=tonumber(link:match("^spell:(%d+)$"))
    if spell then
        local s=G.Safe(C_Spell and C_Spell.GetSpellInfo,spell)
        return s and s.name or "Spell "..spell,s and s.iconID
    end
    if not name then G.RequestItemData(G.ItemID(link)) end
    icon=icon or G.Safe(C_Item and C_Item.GetItemIconByID,G.ItemID(link))
    return full or name or ("Item "..tostring(G.ItemID(link)).." (loading)"),icon
end

local function linkClick(link)
    if link and IsShiftKeyDown() then
        local _,full=G.Safe(C_Item and C_Item.GetItemInfo,link)
        if not full then full="|cffffffff|H"..link.."|h["..itemText(link).."]|h|r" end
        ChatEdit_InsertLink(full); return true
    end
end
local function tooltip(row)
    if U.officerPanel and U.officerPanel:IsShown() then GameTooltip:Hide(); return end
    local d=row.data
    if not d or d.heading then GameTooltip:Hide(); return end
    GameTooltip:Hide()
    GameTooltip:SetOwner(row.tooltipOwner or row,"ANCHOR_CURSOR")
    if d.link then G.Safe(GameTooltip.SetHyperlink,GameTooltip,d.link) else GameTooltip:SetText(d.title or "Guild Ledger") end
    if d.lines then
        for _,line in ipairs(d.lines) do GameTooltip:AddLine(line,0.90,0.93,0.96,true) end
        if d.professionLines and #d.professionLines>0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Professions",0.88,0.73,0.43)
            for _,p in ipairs(d.professionLines) do GameTooltip:AddDoubleLine(p.name,p.rank.." / "..p.max,0.9,0.93,0.96,0.9,0.93,0.96) end
        end
    end
    if d.tip and d.tip~="" then GameTooltip:AddLine(d.tip,0.90,0.93,0.96,true) end
    if d.link then GameTooltip:AddLine("Shift-click to link in chat",0.88,0.73,0.43) end
    GameTooltip:Show()
end
local function row(parent,w,h,x,y)
    local r=CreateFrame("Button",nil,parent)
    r:SetSize(w,h); r:SetPoint("TOPLEFT",x,y)
    r.bg=r:CreateTexture(nil,"BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.07,0.085,0.10,0.8)
    r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8","ADD")
    r:GetHighlightTexture():SetVertexColor(0.10,0.12,0.15,0.25)
    r.selectedBar=r:CreateTexture(nil,"OVERLAY"); r.selectedBar:SetColorTexture(unpack(gold)); r.selectedBar:SetWidth(2); r.selectedBar:SetPoint("TOPLEFT"); r.selectedBar:SetPoint("BOTTOMLEFT"); r.selectedBar:Hide()
    r.icon=r:CreateTexture(nil,"ARTWORK"); r.icon:SetSize(h<30 and 20 or 30,h<30 and 20 or 30); r.icon:SetPoint("LEFT",5,0)
    r.title=label(r,"",12,9,-6,w-18)
    r.sub=label(r,"",10,9,-23,w-18); r.sub:SetTextColor(0.76,0.81,0.86)
    r.extra=label(r,"",10,9,-37,w-18); r.extra:SetTextColor(0.73,0.68,0.55)
    r:SetScript("OnEnter",tooltip); r:SetScript("OnLeave",function() GameTooltip:Hide() end)
    r:SetScript("OnClick",function(self)
        local d=self.data
        if d and not linkClick(d.link) and d.action then GameTooltip:Hide(); d.action() end
    end)
    return r
end
local function paint(r,d,detail)
    r.data=d
    if not d then r:Hide(); return end
    r:Show()
    local selected=d.character and U.selected==d.character or d.recipe and (U.recipe==d.recipe or d.recipeKey and U.recipeKey==d.recipeKey) or d.loot and U.loot==d.loot
    r.selectedBar:SetShown(selected and true or false)
    r.bg:SetColorTexture(selected and 0.16 or 0.055,selected and 0.14 or 0.068,selected and 0.10 or 0.082,1)
    r.title:SetText(d.title or ""); r.sub:SetText(d.sub or ""); r.extra:SetText(d.extra or "")
    r.title:SetTextColor(unpack(d.color or {0.86,0.88,0.90}))
    r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT",d.icon and 44 or 12,detail and -5 or -7)
    r.title:SetWidth(r:GetWidth()-(d.icon and 56 or 24))
    if r.quantity then r.quantity:Hide() end
    if d.heading then r.bg:SetColorTexture(0,0,0,0); r:GetHighlightTexture():SetVertexColor(0,0,0,0)
    else r:GetHighlightTexture():SetVertexColor(0.10,0.12,0.15,0.25) end
    if d.quantity then
        r.quantity=r.quantity or label(r,"",13,0,0,54)
        r.quantity:ClearAllPoints(); r.quantity:SetPoint("TOPRIGHT",-12,-10); r.quantity:SetJustifyH("RIGHT"); r.quantity:SetText(d.quantity); r.quantity:Show()
        r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT",d.icon and 44 or 12,-10); r.title:SetWidth(r:GetWidth()-116)
    elseif d.heading then r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT",0,-13) end
    r.icon:SetSize(d.character and 24 or (detail and 20 or 30),d.character and 24 or (detail and 20 or 30)); r.icon:SetTexture(d.icon); r.icon:SetShown(d.icon~=nil)
    r.sub:SetShown(not detail); r.extra:Hide()
    if r.columns then for _,f in ipairs(r.columns) do f:Hide() end; r.dot:Hide() end
    if r.lootColumns then for _,f in ipairs(r.lootColumns) do f:Hide() end end
    if r.recipeLabels then for _,f in ipairs(r.recipeLabels) do f:Hide() end end
    if d.loot and U.fullLoot then
        if not r.lootColumns then
            r.lootColumns={label(r,"",14,472,-15,265),label(r,"",14,748,-15,50),label(r,"",13,816,-15,190)}
        end
        r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT",48,-15); r.title:SetWidth(408)
        r.title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",15,"")
        r.sub:Hide(); r.extra:Hide()
        local values={d.loot.owner,d.loot.data.quantity>1 and ("x"..d.loot.data.quantity) or "",date("%H:%M",d.loot.stamp)}
        r.lootColumns[1]:SetTextColor(nameColor(d.loot.owner))
        for i,f in ipairs(r.lootColumns) do f:SetText(values[i]); f:Show() end
    elseif d.character then
        if not r.columns then
            r.columns={label(r,"",14,246,-7,172),label(r,"",12,430,-8,142),label(r,"",11,246,-27,172),label(r,"",11,430,-27,142)}
            r.dot=r:CreateTexture(nil,"ARTWORK"); r.dot:SetSize(4,4); r.dot:SetPoint("TOPLEFT",12,-30)
        end
        r.icon:SetSize(20,20)
        r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT",34,-1); r.title:SetWidth(202)
        r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT",42,-16); r.sub:SetWidth(194); r.sub:SetText(d.classText); r.sub:Show()
        r.dot:ClearAllPoints(); r.dot:SetPoint("TOPLEFT",34,-21); r.dot:Show()
        r.dot:SetColorTexture(d.online and 0.38 or 0.30,d.online and 0.78 or 0.34,d.online and 0.53 or 0.38,1)
        local values={d.specText,d.roleText,d.buildText,d.professionText}
        for i,f in ipairs(r.columns) do
            f:ClearAllPoints(); f:SetPoint("TOPLEFT",(i==1 or i==3) and 246 or 430,i<=2 and -1 or -16)
            f:SetText(values[i] or ""); f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",i<=2 and 13 or 12,"")
            f:SetTextColor(i<=2 and 0.85 or 0.70,i<=2 and 0.88 or 0.76,i<=2 and 0.91 or 0.81); f:Show()
        end
    elseif d.recipe then
        if not r.recipeLabels then
            r.recipeLabels={label(r,"",11,410,-7,162),label(r,"",11,410,-26,162)}
            for _,f in ipairs(r.recipeLabels) do f:SetJustifyH("RIGHT") end
        end
        r.title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",14,"")
        r.title:SetWidth(282)
        r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT",d.icon and 44 or 12,-26); r.sub:SetWidth(282)
        for i,f in ipairs(r.recipeLabels) do f:ClearAllPoints(); f:SetPoint("TOPRIGHT",-12,i==1 and -7 or -25); f:SetWidth(120) end
        r.title:SetWidth(r:GetWidth()-180); r.sub:SetWidth(r:GetWidth()-180)
        r.recipeLabels[1]:SetText(d.professionName); r.recipeLabels[2]:SetText(d.onlineText or (d.online and "Online" or "Offline"))
        r.recipeLabels[2]:SetTextColor(d.online and 0.38 or 0.65,d.online and 0.78 or 0.69,d.online and 0.53 or 0.73)
        for _,f in ipairs(r.recipeLabels) do f:Show() end
    else
        r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT",d.icon and 44 or 12,-24); r.sub:SetWidth(r:GetWidth()-(d.icon and 56 or 24))
        r.extra:ClearAllPoints(); r.extra:SetPoint("TOPLEFT",d.icon and 44 or 12,-37); r.extra:SetWidth(r:GetWidth()-(d.icon and 56 or 24))
    end
end
local function matches(text,query) return text:lower():find(query:lower(),1,true)~=nil end
local function searchable(m,d)
    local roles=G.EffectiveRoles(m,d)
    local spec=G.SpecSummary(d)
    return table.concat({m.name,className(m),table.concat(roles," "),professionNames(d),spec}," ")
end
local function allWords(text,query)
    for word in query:lower():gmatch("%S+") do if not matches(text,word) then return false end end
    return true
end
local qualityNames={[0]="Poor",[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Artifact",[7]="Heirloom"}
function U:MatchesQuality(link)
    if not self.craftQuality or self.craftQuality=="All rarities" then return true end
    if link and link:match("^spell:") then return self.craftQuality=="Enchants / spells" end
    local _,_,quality=G.Safe(C_Item and C_Item.GetItemInfo,link)
    if quality==nil then
        G.RequestItemData(G.ItemID(link))
        return self.craftQuality=="Unknown quality"
    end
    return qualityNames[quality]==self.craftQuality
end
function U:MatchesBinding(link)
    local mode=self.craftBinding or "Hide BoP"
    if mode=="All bindings" then return true end
    if link and link:match("^spell:") then return mode=="Hide BoP" end
    local bind=G.Safe(function() return select(14,(C_Item and C_Item.GetItemInfo or GetItemInfo)(link)) end)
    if bind==nil then
        G.RequestItemData(G.ItemID(link))
        return mode=="Hide BoP" or mode=="Unknown binding"
    end
    if mode=="BoE only" then return bind==2 end
    if mode=="BoP only" then return bind==1 end
    if mode=="Unknown binding" then return false end
    return bind~=1
end
function U:LootMatches(r)
    local quality=r.data.quality
    return quality~=nil and quality>=(G.GreenCaptureEnabled() and 2 or 3) and r.stamp>G.now()-7*86400
end
function U:BuildList()
    local revision=self.tab=="Roster" and G.Revision("profile") or self.tab=="Crafting" and G.Revision("profession") or G.Revision("loot")
    local cacheKey=table.concat({self.tab,self.query,tostring(self.online),self.role,self.class,self.spec,tostring(self.craftOwner),tostring(self.craftSkill),tostring(self.craftQuality),tostring(revision),tostring(G.Revision("roster")),tostring(G.Revision("membership")),self.tab=="Roster" and "" or tostring(G.itemRevision),tostring(G.GreenCaptureEnabled()),self.tab=="Guild Loot" and tostring(math.floor(G.now()/60)) or ""},";")
    cacheKey=cacheKey..";"..tostring(self.craftBinding)
    if self.listKey==cacheKey then return self.listCache end
    local result={}
    if self.tab=="Roster" then
        for name,m in pairs(G.members) do
            local rec=G.Get("profile",name); local d=rec and rec.data
            local assigned,roleSource=G.EffectiveRoles(m,d)
            local roles=table.concat(assigned,", ")
            if (not self.online or m.online) and (self.role=="Any role" or matches(roles,self.role)) and (self.class=="Any class" or className(m)==self.class) and G.SpecMatches(d,self.spec) and allWords(searchable(m,d),self.query) then
                local selected=name
                local spec,distribution=G.SpecSummary(d)
                local professions=G.OrderedProfessions(d)
                result[#result+1]={sort=name,character=name,title=name,icon=G.RosterIcon(m,d),color={nameColor(name)},rank=m.rank,online=m.online,classText=m.level.." "..className(m),roleText=roles~="" and roles or "Unassigned",specText=spec,buildText=distribution,professionText=professions[1] and (professions[1].name..(#professions>1 and " +"..(#professions-1) or "")) or "",prof1=professions[1] and professions[1].name or "—",prof2=professions[2] and (professions[2].name..(#professions>2 and " +"..(#professions-2) or "")) or "",lines={m.level.." "..className(m).." - "..(m.online and "Online" or "Offline"),"Spec: "..spec,"Role: "..(roles~="" and roles or "Unassigned"),"Rank: "..m.rank},professionLines=professions,action=function() U.selected=selected; U.showInfo=false; U.detailOffset=0; U:Render() end}
            end
        end
        table.sort(result,function(a,b) return a.sort<b.sort end)
    elseif self.tab=="Crafting" then
        local grouped={}
        local bindingMatches={}
        for _,recordID in ipairs(G.Keys(G.store and G.store.records or {})) do
            local rec=G.store.records[recordID]
            if rec.kind=="profession" and not rec.deleted and G.members[rec.owner] and (not self.craftOwner or rec.owner==self.craftOwner) and (not self.craftSkill or rec.data.id==self.craftSkill) then
                local m=G.members[rec.owner]
                for _,recipe in G.Recipes(rec) do
                    local text=recipe.name.." "..rec.owner.." "..rec.data.name.." "..itemText(recipe.link)
                    local bindingKey=recipe.link or ""
                    if bindingMatches[bindingKey]==nil then bindingMatches[bindingKey]=self:MatchesBinding(recipe.link) end
                    if (not self.online or m.online) and allWords(text,self.query) and self:MatchesQuality(recipe.link) and bindingMatches[bindingKey] then
                        local key=rec.data.id..":"..tostring(recipe.id or recipe.name)..":"..tostring(recipe.link)
                        if not grouped[key] then
                            local r,p=recipe,rec
                            local _,icon=itemText(r.link)
                            local names=self:RecipeCrafters(r,p); local online=0
                            for _,name in ipairs(names) do if G.members[name].online then online=online+1 end end
                            local entry={sort=r.name..key,recipe=r,recipeKey=key,title=r.name,icon=icon,sub=#names..(#names==1 and " crafter" or " crafters"),professionName=p.data.name,online=online>0,onlineText=online>0 and (online.." online") or "Offline",link=r.link,action=function() U.recipe=r; U.profession=p; U.recipeKey=key; U.detailOffset=0; U:Render() end}
                            grouped[key]=entry; result[#result+1]=entry
                        end
                    end
                end
            end
        end
        table.sort(result,function(a,b) return a.sort<b.sort end)
    else
        for _,r in pairs(G.store and G.store.records or {}) do
            if (r.kind=="loot") and self:LootMatches(r) then
                local title,icon=itemText(r.data.link)
                local former=not G.members[r.owner] and " (former member)" or ""
                do
                    local selected=r
                    result[#result+1]={sort=r.stamp,id=r.id,loot=r,title=title,icon=icon,sub=r.owner..former.."  ×"..r.data.quantity,extra=date("%Y-%m-%d %H:%M",r.stamp).."  ·  "..(r.data.source~="" and r.data.source or "Unknown source"),link=r.data.link,tip="Received by "..r.owner.."\n"..date("%b %d, %Y at %H:%M",r.stamp)..(r.data.quantity>1 and ("\nQuantity: "..r.data.quantity) or "")..(r.data.source~="" and ("\n"..r.data.source) or ""),action=function() U.loot=selected; U.detailOffset=0; U:Render() end}
                end
            end
        end
        table.sort(result,function(a,b) if a.sort==b.sort then return a.id<b.id end return a.sort>b.sort end)
    end
    self.listKey=cacheKey; self.listCache=result
    return result
end
function U:BuildDetails()
    local rows={}
    local function add(text,link,tip) local icon; if link then local ignored; ignored,icon=itemText(link) end; rows[#rows+1]={title=text,link=link,tip=tip,icon=icon} end
    if self.showInfo then
        self.detailTitle:SetText("Guild information")
        add("Message of the day")
        for line in (G.Plain(G.motd).."\n"):gmatch("([^\n]*)\n") do
            for i=1,math.max(1,#line),48 do add(line:sub(i,i+47)) end
        end
        add("Guild information")
        for line in (G.Plain(G.guildInfo).."\n"):gmatch("([^\n]*)\n") do for i=1,math.max(1,#line),48 do add(line:sub(i,i+47)) end end
    elseif self.tab=="Roster" then
        local name=self.selected
        if not name or not G.members[name] then self.detailTitle:SetText("Select a guild character"); add("Select a character to see their spec."); add("Tree names and points summarize each build."); return rows end
        self.detailTitle:SetText(name)
        local r=G.Get("profile",name); local d=r and r.data
        if self.section=="Spec" then
            local spec,distribution=G.SpecSummary(d)
            add(spec,nil,"Spec uses the dominant talent tree. Auto roles are suggestions; chosen roles take priority.")
            if d and #d.trees>0 then
                add(distribution.."  ·  Talent points")
                add("")
                for _,t in ipairs(d.trees) do add(t.name.."  ·  "..t.points.." points") end
                add("")
                add("Updated "..G.Age(d.talentStamp~=0 and d.talentStamp or nil))
            else add("Waiting for this character to share a build.") end
            local roles,source=G.EffectiveRoles(G.members[name],d)
            add((source=="Chosen" and "Chosen roles: " or "Auto roles: ")..(#roles>0 and table.concat(roles,", ") or "Unassigned"))
        elseif self.section=="Gear" then
            -- Equipment is drawn as fixed slots by RenderGear.
        elseif self.section=="Professions" then
            -- Profession cards are drawn by RenderProfessions.
        else
            local loot={}; for _,entry in pairs(G.store and G.store.records or {}) do if (entry.kind=="loot") and entry.owner==name and self:LootMatches(entry) then loot[#loot+1]=entry end end
            table.sort(loot,function(a,b) return a.stamp>b.stamp end)
            for _,entry in ipairs(loot) do add(date("%m/%d",entry.stamp).." ×"..entry.data.quantity.." "..itemText(entry.data.link),entry.data.link) end
            if #loot==0 then add("No observed notable loot in retained history.") end
        end
    elseif self.tab=="Crafting" then
        local r,p=self.recipe,self.profession
        if p and (not G.store or G.store.records[p.id]~=p or p.deleted) then r,p=nil,nil end
        self.detailTitle:SetText(r and r.name or "Find your guild's crafters")
        if not (r and p and G.members[p.owner]) then
            add("Choose a recipe to see its crafter.")
            add("Filter by profession or search by name.")
        end
    else
        self.detailTitle:SetText("Observed guild loot")
        add("Original recipients · last 7 days / 500 entries")
        add("History begins when members install the addon.")
        add("Unobserved loot cannot be recovered."); add("Later trades are not tracked.")
        if self.loot and G.store and G.store.records[self.loot.id] then local r=self.loot
            add(itemText(r.data.link),r.data.link); add(r.owner); add("Quantity: "..r.data.quantity)
            add(date("%Y-%m-%d %H:%M",r.stamp)); add("Source: "..(r.data.source~="" and r.data.source or "Unknown"))
        end
    end
    return rows
end
local professionSpells={[171]=2259,[164]=2018,[165]=2108,[197]=3908,[333]=7411,[202]=4036,[186]=2575,[182]=2366,[393]=8613,[185]=2550,[129]=3273,[356]=7620}
local gathering={[182]=true,[186]=true,[393]=true,[356]=true}
function U:CreateProfessions(parent)
    local f=CreateFrame("Frame",nil,parent); self.professionPanel=f; f:SetAllPoints(parent)
    self.professionAge=label(f,"",11,16,-104,384)
    self.professionEmpty=label(f,"No professions shared yet.",14,24,-158,360)
    self.professionCards={}
    for i=1,6 do
        local c=panel(f,384,48,16,-128-(i-1)*52); self.professionCards[i]=c
        c.icon=c:CreateTexture(nil,"ARTWORK"); c.icon:SetSize(32,32); c.icon:SetPoint("TOPLEFT",10,-8); c.icon:SetTexCoord(0.07,0.93,0.07,0.93)
        c.initial=label(c,"",16,10,-14,32); c.initial:SetTextColor(unpack(gold)); c.initial:SetJustifyH("CENTER")
        c.name=label(c,"",13,52,-6,200)
        c.rank=label(c,"",12,266,-6,106); c.rank:SetJustifyH("RIGHT"); c.rank:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",12,"")
        c.track=c:CreateTexture(nil,"BACKGROUND"); c.track:SetColorTexture(0.14,0.18,0.21,1)
        c.track:SetSize(210,6); c.track:SetPoint("TOPLEFT",52,-30)
        c.fill=c:CreateTexture(nil,"ARTWORK"); c.fill:SetColorTexture(0.38,0.70,0.56,1)
        c.fill:SetHeight(6); c.fill:SetPoint("TOPLEFT",52,-30)
        c.recipes=button(c,"",106,266,-24,function()
            if not c.owner or not c.professionID then return end
            U:SwitchTab("Crafting"); U.craftOwner=c.owner; U.craftSkill=c.professionID; U.craftName=c.skillName
            U.query=c.owner; U.search:SetText(U.query); U.online=false
            U.onlineButton.text:SetText("All members"); U.offset=0; U.detailOffset=0
            U.recipe=nil; U.profession=nil; U:Render()
        end)
        c.recipes:SetHeight(24); c.recipes.text:ClearAllPoints(); c.recipes.text:SetPoint("CENTER",0,0); c.recipes.text:SetWidth(90); c.recipes.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",12,"")
        c.status=label(c,"",10,266,-27,106); c.status:SetJustifyH("RIGHT")
        c:EnableMouse(true)
        c:SetScript("OnEnter",function()
            c.data={title=c.skillName or "Profession",tip=c.tip}; tooltip(c)
        end)
        c:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end
    f:Hide()
end
function U:RenderProfessions()
    local visible=self.tab=="Roster" and self.section=="Professions" and not self.showInfo and G.members[self.selected]~=nil
    self.professionPanel:SetShown(visible)
    if not visible then return false end
    local profile=G.Get("profile",self.selected); local d=profile and profile.data
    self.professionAge:SetText(d and d.skillStamp>0 and ("Skills updated "..G.Age(d.skillStamp)) or "Waiting for shared skills")
    local professions=G.OrderedProfessions(d)
    self.professionEmpty:SetShown(#professions==0)
    for i,c in ipairs(self.professionCards) do
        local p=professions[i]; c:SetShown(p~=nil)
        local roomy=#professions<=5
        c:SetHeight(roomy and 56 or 48); c:ClearAllPoints(); c:SetPoint("TOPLEFT",16,-128-(i-1)*(roomy and 62 or 52))
        c.icon:ClearAllPoints(); c.icon:SetPoint("TOPLEFT",10,roomy and -12 or -8)
        c.name:ClearAllPoints(); c.name:SetPoint("TOPLEFT",52,-8)
        c.rank:ClearAllPoints(); c.rank:SetPoint("TOPLEFT",266,roomy and -8 or -6)
        c.track:ClearAllPoints(); c.track:SetPoint("TOPLEFT",52,roomy and -38 or -32)
        c.fill:ClearAllPoints(); c.fill:SetPoint("TOPLEFT",52,roomy and -38 or -32)
        c.recipes:SetHeight(roomy and 24 or 22); c.recipes:ClearAllPoints(); c.recipes:SetPoint("TOPLEFT",266,roomy and -26 or -22)
        c.status:ClearAllPoints(); c.status:SetPoint("RIGHT",-12,roomy and -10 or -9)
        c.owner=nil; c.professionID=nil
        if p then
            c.owner=self.selected; c.professionID=p.id; c.skillName=p.name
            local spell=professionSpells[p.id] and G.Safe(C_Spell and C_Spell.GetSpellInfo,professionSpells[p.id])
            local icon=spell and spell.iconID
            c.icon:SetTexture(icon); c.icon:SetShown(icon~=nil)
            c.initial:SetText(p.name:sub(1,1)); c.initial:SetShown(icon==nil)
            c.name:SetText(p.name); c.rank:SetText(p.rank.." / "..p.max)
            local fraction=p.max>0 and math.min(1,math.max(0,p.rank/p.max)) or 0
            c.fill:SetWidth(math.max(1,210*fraction)); c.fill:SetShown(fraction>0)
            c.fill:SetColorTexture(unpack(fraction>=1 and gold or {0.38,0.70,0.56}))
            local book=not gathering[p.id] and G.Get("profession",self.selected,tostring(p.id))
            local count=book and #book.data.recipes or 0
            c.recipes:SetShown(count>0); c.status:SetShown(count==0)
            c.recipes.text:SetText(count..(count==1 and " recipe" or " recipes"))
            c.status:SetText(gathering[p.id] and "Gathering" or book and "No recipes" or "Not scanned")
            c.tip=p.rank.." / "..p.max..(book and ("\nRecipes updated "..G.Age(book.stamp)) or gathering[p.id] and "\nGathering skill" or "\nOpen this profession in-game to share recipes.")
        end
    end
    self.detailCount:SetText("")
    return true
end
function U:CraftingOptions()
    local names={}
    for _,p in pairs(G.store and G.store.records or {}) do
        if p.kind=="profession" and not p.deleted and G.members[p.owner] and (not self.craftOwner or p.owner==self.craftOwner) then names[p.data.name]=p.data.id end
    end
    local options=G.Keys(names); table.insert(options,1,"All professions")
    return options,names
end
function U:CreateRecipe(parent)
    local f=CreateFrame("Frame",nil,parent); f:SetAllPoints(parent); self.recipePanel=f
    self.recipePreview=CreateFrame("Button",nil,f); self.recipePreview:SetSize(40,40); self.recipePreview:SetPoint("TOPLEFT",16,-12)
    self.recipePreview:SetScript("OnEnter",tooltip); self.recipePreview:SetScript("OnLeave",function() GameTooltip:Hide() end)
    self.recipePreview:SetScript("OnClick",function(self) if self.data then linkClick(self.data.link) end end)
    self.recipeIcon=self.recipePreview:CreateTexture(nil,"ARTWORK"); self.recipeIcon:SetAllPoints()
    self.materialHeading=label(f,"INGREDIENTS",11,16,-78,440)
    local rule=f:CreateTexture(nil,"BACKGROUND"); rule:SetColorTexture(0.19,0.22,0.26,1); rule:SetSize(504,1); rule:SetPoint("TOPLEFT",16,-65)
    label(f,"QTY",10,466,-78,54):SetJustifyH("RIGHT")
    self.materialRows={}; self.crafterCards={}
    for i=1,8 do
        self.materialRows[i]=row(f,504,36,16,-102-(i-1)*40)
        local c=panel(f,504,36,16,-102-(i-1)*40); self.crafterCards[i]=c
        c.owner=label(c,"",14,12,-9,280)
        c.status=label(c,"",11,294,-11,100)
        c.contact=button(c,"Whisper",88,404,-4,function() if c.target and G.members[c.target] then ChatFrame_SendTell(c.target) end end)
    end
    f:Hide()
end
function U:RecipeCrafters(r,p)
    G.EnsureCrafterIndex()
    local names={}
    for _,name in ipairs(G.recipeCrafterIndex[G.RecipeKey(r,p.data.id)] or {}) do names[#names+1]=name end
    table.sort(names,function(a,b)
        local ao,bo=G.members[a].online,G.members[b].online
        if ao~=bo then return ao end
        return a<b
    end)
    return names
end
function U:RenderRecipe()
    local r,p=self.recipe,self.profession
    local visible=self.tab=="Crafting" and not self.showInfo and r and p and G.store and G.store.records[p.id]==p and not p.deleted and G.members[p.owner]~=nil
    self.recipePanel:SetShown(visible and true or false)
    for _,c in ipairs(self.crafterCards) do c.target=nil; c:Hide() end
    self.recipePreview.data=nil
    self.detailTitle:ClearAllPoints(); self.detailTitle:SetPoint("TOPLEFT",16,-16); self.detailTitle:SetWidth(384)
    self.detailSubtitle:ClearAllPoints(); self.detailSubtitle:SetPoint("TOPLEFT",16,-42); self.detailSubtitle:SetWidth(384)
    if not visible then return false end
    self.detailSubtitle:SetText(p.data.name)
    local _,icon=itemText(r.link); self.recipeIcon:SetTexture(icon)
    self.recipePreview.data={title=r.name,link=r.link}; self.recipePreview:SetShown(icon~=nil)
    local inset=icon and 64 or 16
    self.detailTitle:ClearAllPoints(); self.detailTitle:SetPoint("TOPLEFT",inset,-16); self.detailTitle:SetWidth(520-inset)
    self.detailSubtitle:ClearAllPoints(); self.detailSubtitle:SetPoint("TOPLEFT",inset,-42); self.detailSubtitle:SetWidth(520-inset)
    local entries={}
    for _,m in ipairs(r.materials or {}) do
        local link="item:"..m.id; local name,texture=itemText(link)
        entries[#entries+1]={title=name,quantity=m.quantity,icon=texture,link=link}
    end
    if #entries==0 then entries[1]={title="No ingredient list shared."} end
    local names=self:RecipeCrafters(r,p)
    entries[#entries+1]={title="GUILD CRAFTERS  ("..#names..")",color=gold,heading=true}
    for _,name in ipairs(names) do entries[#entries+1]={crafter=name} end
    self.recipeEntries=entries
    self.detailOffset=math.max(0,math.min(self.detailOffset,math.max(0,#entries-8)))
    for i,row in ipairs(self.materialRows) do
        local d=entries[self.detailOffset+i]; local c=self.crafterCards[i]
        if d and d.crafter then
            row:Hide(); c.target=d.crafter; c.owner:SetText(d.crafter); c.owner:SetTextColor(nameColor(d.crafter))
            c.status:SetText(G.members[d.crafter].online and "Online" or "Offline"); c:Show()
        else paint(row,d,true) end
    end
    self.detailCount:SetText(#entries>8 and ((self.detailOffset+1).."-"..math.min(self.detailOffset+8,#entries).." of "..#entries.." rows - Scroll for more") or "Hover items for details")
    return true
end
-- Only show active abilities actually present in the shared learned-talents snapshot.
-- Unknown spell metadata is omitted rather than guessing from class or level.
function G.SpecHighlights(d)
    local result,seen={},{}
    for _,talent in ipairs(d and d.talents or {}) do
        if talent.rank>0 and not seen[talent.spell] then
            local info=G.Safe(C_Spell and C_Spell.GetSpellInfo,talent.spell)
            local passive=G.Safe(C_Spell and C_Spell.IsSpellPassive,talent.spell)
            if info and info.name and passive==false then
                seen[talent.spell]=true
                result[#result+1]={title=info.name,icon=info.iconID,link="spell:"..talent.spell,spell=talent.spell}
            end
        end
    end
    table.sort(result,function(a,b) if a.title==b.title then return a.spell<b.spell end return a.title<b.title end)
    while #result>3 do table.remove(result) end
    return result
end
function U:CreateSpec(parent)
    local f=CreateFrame("Frame",nil,parent); f:SetAllPoints(parent); self.specPanel=f
    self.specIcon=f:CreateTexture(nil,"ARTWORK"); self.specIcon:SetSize(36,36); self.specIcon:SetPoint("TOPLEFT",16,-110); self.specIcon:SetTexCoord(0.07,0.93,0.07,0.93)
    self.specName=label(f,"",20,64,-108,336); self.specName:SetTextColor(unpack(gold))
    self.specBadge=panel(f,190,24,64,-139); self.specBadge:EnableMouse(true); self.specBadge:SetBackdropColor(0.07,0.13,0.12,1)
    self.specRole=label(self.specBadge,"",12,8,-4,174); self.specRole:SetTextColor(0.65,0.84,0.77)
    self.specBadge:SetScript("OnEnter",tooltip); self.specBadge:SetScript("OnLeave",function() GameTooltip:Hide() end)
    self.specTrees={}
    for i=1,3 do
        local c=panel(f,122,108,16+(i-1)*131,-180); self.specTrees[i]=c
        c.icon=c:CreateTexture(nil,"ARTWORK"); c.icon:SetSize(28,28); c.icon:SetPoint("TOPLEFT",12,-12); c.icon:SetTexCoord(0.07,0.93,0.07,0.93)
        c.points=label(c,"",25,50,-10,60); c.points:SetJustifyH("RIGHT")
        c.name=label(c,"",12,12,-53,98); c.name:SetWordWrap(true); c.name:SetHeight(40)
        c:EnableMouse(true); c:SetScript("OnEnter",tooltip); c:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end
    self.specSummary=label(f,"",11,16,-304,384); self.specSummary:SetTextColor(0.70,0.76,0.81)
    self.specEmpty=label(f,"",14,16,-190,384); self.specEmpty:SetWordWrap(true); self.specEmpty:SetHeight(86)
    self.specHighlightTitle=label(f,"TALENT ABILITIES",10,16,-336,384); self.specHighlightTitle:SetTextColor(unpack(gold))
    self.specAbilities={}
    for i=1,3 do self.specAbilities[i]=row(f,384,24,16,-356-(i-1)*27) end
    self.specAbilityEmpty=label(f,"No active talent abilities shared yet.",11,16,-358,384); self.specAbilityEmpty:SetTextColor(0.70,0.76,0.81)
    self.specUpdated=label(f,"",10,16,-446,384); self.specUpdated:SetTextColor(0.64,0.70,0.76)
    f:Hide()
end
function U:RenderSpec()
    local visible=self.tab=="Roster" and self.section=="Spec" and not self.showInfo and G.members[self.selected]~=nil
    self.specPanel:SetShown(visible)
    if not visible then return false end
    local member=G.members[self.selected]
    local rec=G.Get("profile",self.selected); local d=rec and rec.data
    local spec=G.SpecSummary(d); local shared=d and d.trees and #d.trees>0
    local total,highest,ties=0,0,0
    for _,t in ipairs(d and d.trees or {}) do
        total=total+t.points
        if t.points>highest then highest=t.points; ties=1 elseif t.points==highest and highest>0 then ties=ties+1 end
    end
    self.specName:SetText(not shared and "Build not shared yet" or ties>1 and "Hybrid build" or spec)
    local icon=G.RosterIcon(member,d); self.specIcon:SetTexture(icon); self.specIcon:SetShown(icon~=nil)
    self.specSummary:SetText(shared and (total.." talent points spent") or "")
    self.specEmpty:SetShown(not shared)
    self.specEmpty:SetText("This member has not shared a talent build. Their addon will share it when they are online and scan their talents.")
    for i,c in ipairs(self.specTrees) do
        local t=d and d.trees and d.trees[i]; c:SetShown(t~=nil)
        if t then
            local dominant=t.points>0 and t.points==highest
            c.name:SetText(t.name); c.points:SetText(tostring(t.points))
            c.points:SetTextColor(unpack(dominant and gold or {0.72,0.77,0.82}))
            c:SetBackdropBorderColor(unpack(dominant and gold or {0.16,0.19,0.23}))
            local treeIcon=G.RosterIcon(member,{trees={{name=t.name,points=1}}})
            c.icon:SetTexture(treeIcon); c.icon:SetShown(treeIcon~=nil)
            c.data={title=t.name,tip=t.points..(t.points==1 and " point spent" or " points spent")..(dominant and (ties>1 and " - Joint primary tree" or " - Primary tree") or "")}
        else c.data=nil end
    end
    local roles,source=G.EffectiveRoles(member,d)
    self.specRole:SetText(#roles>0 and table.concat(roles," / ") or "Role unassigned")
    self.specBadge:SetWidth(#roles>2 and 250 or 190); self.specRole:SetWidth(#roles>2 and 234 or 174)
    self.specBadge.data={title="Combat role",tip=source=="Chosen" and "Chosen by this player in Settings." or source=="Auto" and "Assigned automatically from their dominant talent tree. Players can override this in Settings." or "No shared spec or player-selected role is available."}
    local highlights=shared and G.SpecHighlights(d) or {}
    self.specHighlightTitle:SetShown(shared and total>0)
    self.specAbilityEmpty:SetShown(shared and total>0 and #highlights==0)
    for i,r in ipairs(self.specAbilities) do paint(r,highlights[i],true) end
    local roleSource=source=="Chosen" and "Player-selected role" or source=="Auto" and "Automatic role" or ""
    local age=d and d.talentStamp and d.talentStamp>0 and ("Updated "..G.Age(d.talentStamp)) or ""
    self.specUpdated:SetText(roleSource..(roleSource~="" and age~="" and "  |  " or "")..age)
    self.detailCount:SetText("")
    return true
end
function U:CreateGear(parent)
    self.gearPanel=CreateFrame("Frame",nil,parent)
    self.gearPanel:SetAllPoints(parent)
    self.gearAge=label(self.gearPanel,"",11,16,-104,384)
    self.gearSlots={}
    local groups={{1,2,3,15,5,4,19,9},{10,6,7,8,11,12,13,14},{16,17,18}}
    for column,group in ipairs(groups) do
        for index,slot in ipairs(group) do
            local weapon=column==3
            local x=weapon and (16+(index-1)*130) or (16+(column-1)*200)
            local y=weapon and -410 or (-130-(index-1)*34)
            local width=weapon and 124 or 184
            local r=row(self.gearPanel,width,32,x,y)
            r.icon:SetSize(28,28); r.icon:SetTexCoord(0.07,0.93,0.07,0.93); r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT",2,0)
            r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT",36,-2); r.title:SetWidth(width-40)
            r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT",36,-17); r.sub:SetWidth(width-40)
            r.extra:Hide(); r.selectedBar:Hide()
            self.gearSlots[slot]=r
        end
    end
    self.gearPanel:Hide()
end
function U:RenderGear()
    local visible=self.tab=="Roster" and self.section=="Gear" and not self.showInfo and G.members[self.selected]~=nil
    self.gearPanel:SetShown(visible)
    if not visible then return false end
    if G.WantGear then G.WantGear(self.selected) end
    local gear=G.Get("gear",self.selected)
    local demand=G.gearDemand
    self.gearAge:SetText(gear and ("Equipped snapshot · "..G.Age(gear.stamp)) or demand and demand.owner==self.selected and demand.failed and "No equipment snapshot available from connected peers" or "Requesting shared equipment…")
    local bySlot={}; for _,v in ipairs(gear and gear.data or {}) do bySlot[v.slot]=v end
    for slot,r in pairs(self.gearSlots) do
        local v=bySlot[slot]
        local text,icon
        -- An occupied slot may have an item ID before its instance link is available.
        -- Use base item data without claiming its enchantments or random modifiers.
        local itemLink=v and (v.link or (v.state~="empty" and v.id and ("item:"..v.id)))
        local basic=v and not v.link and itemLink~=nil
        if itemLink then text,icon=itemText(itemLink)
        else text=v and v.state=="empty" and "Empty" or v and v.state=="loading" and "Loading item..." or "Not available" end
        r.data={title=slots[slot]..": "..text,link=itemLink,tip=slots[slot]..(basic and " - Base item only; exact equipped details pending." or " - Equipped snapshot")}
        r.title:SetText(slots[slot]); r.title:SetTextColor(0.87,0.89,0.92)
        r.sub:SetText(text); r.sub:SetTextColor(0.72,0.77,0.82)
        r.icon:SetTexture(icon); r.icon:SetShown(icon~=nil)
        r.title:ClearAllPoints(); r.sub:ClearAllPoints()
        local inset=icon and 36 or 8
        r.title:SetPoint("TOPLEFT",inset,-2); r.sub:SetPoint("TOPLEFT",inset,-17)
        r.title:SetWidth(r:GetWidth()-inset-4); r.sub:SetWidth(r:GetWidth()-inset-4)
        r:Show()
    end
    self.detailCount:SetText("Hover slots for items · Shift-click to link")
    return true
end
function U:Render()
    if not self.frame or not self.frame:IsShown() then return end
    if self.officerButton then self.officerButton:SetShown(G.IsOfficer(G.self)) end
    if self.officerPanel and self.officerPanel:IsShown() then self.officerPanel.refresh() end
    self.fullLoot=self.tab=="Guild Loot" and not self.showInfo
    local crafting=self.tab=="Crafting"
    local leftWidth=self.fullLoot and 1032 or crafting and 480 or 600
    self.left:SetWidth(leftWidth); self.right:SetShown(not self.fullLoot)
    self.right:ClearAllPoints(); self.right:SetPoint("TOPLEFT",crafting and 520 or 640,-190); self.right:SetWidth(crafting and 536 or 416)
    self.pageSize=self.fullLoot and 6 or self.tab=="Roster" and 12 or 8
    for _,heading in ipairs(self.dayHeadings) do heading:Hide() end
    for i,r in ipairs(self.rows) do
        r:SetWidth(leftWidth-16); r:SetHeight(self.tab=="Roster" and 30 or crafting and 40 or 47)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT",8,-38-(i-1)*(self.tab=="Roster" and 32 or crafting and 44 or 48))
        r.title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",13,"")
    end
    self.previous:ClearAllPoints(); self.previous:SetPoint("TOPLEFT",leftWidth-108,-430)
    self.nextPage:ClearAllPoints(); self.nextPage:SetPoint("TOPLEFT",leftWidth-60,-430)
    self.empty:SetWidth(leftWidth-40)
    self.count:SetWidth(leftWidth-140)
    self.onlineButton:SetShown(self.tab~="Guild Loot")
    self.search:SetShown(self.tab~="Guild Loot"); self.searchHint:SetShown(self.tab~="Guild Loot" and self.search:GetText()=="" and not self.search:HasFocus())
    self.clearButton:SetShown(self.tab~="Guild Loot")
    self.left:ClearAllPoints(); self.left:SetPoint("TOPLEFT",24,self.tab=="Guild Loot" and -150 or -190)
    self.left:SetHeight(self.tab=="Guild Loot" and 506 or 466)
    local footer=self.tab=="Guild Loot" and -470 or -430
    self.previous:ClearAllPoints(); self.previous:SetPoint("TOPLEFT",leftWidth-108,footer)
    self.nextPage:ClearAllPoints(); self.nextPage:SetPoint("TOPLEFT",leftWidth-60,footer)
    self.count:ClearAllPoints(); self.count:SetPoint("TOPLEFT",16,footer-10)
    self.searchHint:SetText(self.tab=="Guild Loot" and "Search items or recipients" or self.tab=="Roster" and "Name, spec or role" or "Item or crafter")
    for _,h in ipairs(self.lootHeaders) do h:SetShown(self.fullLoot) end
    local online=0; for _,m in pairs(G.members) do if m.online then online=online+1 end end
    self.guild:SetText((G.guildName or "Join a guild to begin").."  ·  "..online.." online / "..G.Count(G.members).." members")
    self.motd:SetText(self.tab=="Roster" and "Find guild members by class, spec or role." or self.tab=="Crafting" and (self.craftOwner and ((self.craftName or "All").." recipes · "..self.craftOwner) or "Find a recipe and the guild members who know it.") or ((G.GreenCaptureEnabled() and "Uncommon and above" or "Rare and above").." · Last 7 days · Newest first"))
    self.professionButton:SetShown(self.tab=="Crafting"); self.professionButton.text:SetText(self.craftSkill and self.craftName or "All professions")
    self.qualityButton:SetShown(self.tab=="Crafting"); self.qualityButton.text:SetText(self.craftQuality or "All rarities")
    self.bindingButton:SetShown(self.tab=="Crafting"); self.bindingButton.text:SetText(self.craftBinding or "Hide BoP")
    self.crafterButton:SetShown(self.tab=="Crafting" and self.craftOwner~=nil); self.crafterButton.text:SetText(self.craftOwner and "This crafter" or "All crafters")
    self.roleButton:SetShown(self.tab=="Roster"); self.classButton:SetShown(self.tab=="Roster"); self.specButton:SetShown(self.tab=="Roster")
    local list=self:BuildList(); self.offset=math.max(0,math.min(self.offset,math.max(0,#list-self.pageSize)))
    local y,previousDay=38,nil
    for i,r in ipairs(self.rows) do
        local entry=i<=self.pageSize and list[self.offset+i] or nil
        paint(r,entry)
        if self.fullLoot and entry then
            local day=date("%Y-%m-%d",entry.loot.stamp)
            if day~=previousDay then
                local heading=self.dayHeadings[i]; heading:ClearAllPoints(); heading:SetPoint("TOPLEFT",16,-y)
                heading:SetText(day==date("%Y-%m-%d",G.now()) and "TODAY" or date("%A, %b %d",entry.loot.stamp)); heading:Show()
                y=y+20; previousDay=day
            end
            r:ClearAllPoints(); r:SetPoint("TOPLEFT",8,-y); r:SetHeight(42); y=y+44
        end
    end
    self.empty:SetText(not G.scope and "Join a guild to use Guild Ledger." or not G.ready and "Waiting for a complete guild roster…" or #list==0 and (self.tab=="Roster" and "No characters match your filters." or self.tab=="Guild Loot" and "No guild loot recorded in the last seven days." or "No recipes match. Try another profession or clear filters.") or "")
    self.count:SetText(#list==0 and "0 results" or ((self.offset+1).."–"..math.min(self.offset+self.pageSize,#list).." of "..#list.." results"))
    for _,b in ipairs(self.sectionButtons) do b:SetShown(self.tab=="Roster" and not self.showInfo) end
    local m=self.tab=="Roster" and G.members[self.selected]
    self.detailSubtitle:SetText(m and (m.level.." "..className(m).."  ·  "..m.rank.."  ·  "..(m.online and "Online" or "Offline")) or (self.tab=="Crafting" and "Recipes & guild crafters" or ""))
    self.detailTitle:SetTextColor(unpack(m and {nameColor(self.selected)} or gold))
    for i,h in ipairs(self.columnHeaders) do h:SetShown(self.tab=="Roster") end
    self.listHeading:SetText(self.tab=="Roster" and "CHARACTER" or self.tab=="Crafting" and "RECIPES" or "ITEM")
    local details=self:BuildDetails(); if self.tab~="Crafting" then self.detailOffset=math.max(0,math.min(self.detailOffset,math.max(0,#details-14))) end
    for i,r in ipairs(self.details) do paint(r,details[self.detailOffset+i],true) end
    self.detailCount:SetText(#details>14 and ((self.detailOffset+1).."–"..math.min(self.detailOffset+14,#details).." of "..#details.."  ·  Scroll for more") or (self.tab=="Crafting" and "Hover an item for details" or ""))
    local gearVisible=self:RenderGear(); local professionVisible=self:RenderProfessions(); local recipeVisible=self:RenderRecipe(); local specVisible=self:RenderSpec()
    if gearVisible or professionVisible or recipeVisible or specVisible then for _,r in ipairs(self.details) do r:Hide() end end
    self.status:SetText(not G.ready and "Loading guild roster…" or (G.SyncProgress and G.SyncProgress() or G.PeerSummary and G.PeerSummary() or (G.Count(G.peers).." connected addon peers")))
    local _,warning=next(G.errors)
    self.notice:SetText(warning and ("Status: "..tostring(warning)) or (self.tab=="Guild Loot" and "Observed drops only · Trades are not tracked" or ""))
    if G.SavePreferences then G.SavePreferences() end
    for tab,b in pairs(self.tabs) do b.text:SetTextColor(unpack(tab==self.tab and gold or {0.82,0.85,0.89})); b:SetSelected(tab==self.tab) end
    for i,b in ipairs(self.sectionButtons) do local active=({"Spec","Gear","Professions","Loot"})[i]==self.section; b:SetSelected(active); b.text:SetTextColor(unpack(active and gold or {0.82,0.85,0.89})) end
end
function G.UIRefresh()
    if not U.frame or not U.frame:IsShown() then return end
    if G.timers["ui-refresh"] then return end
    G.After("ui-refresh",0.15,function() U:Render() end)
end
function U:Choose(anchor,options,current,selectOption,multi)
    if self.rarityPicker then self.rarityPicker:Hide() end
    local f=self.picker
    if not f then
        f=panel(self.frame,240,280,0,0); self.picker=f; f.entries={}
        f:SetFrameLevel(self.frame:GetFrameLevel()+30); f:EnableMouse(true)
        f:SetBackdropColor(0.035,0.045,0.060,1)
        label(f,"Select filter",12,10,-10,180)
        button(f,"x",28,202,-4,function() f:Hide() end)
        for i=1,8 do f.entries[i]=button(f,"",220,10,-36-(i-1)*29,function(b)
            f.selectOption(b.value); if f.multi then f.draw() else f:Hide() end; U.offset=0; U:Render()
        end) end
    end
    f.selectOption=selectOption; f.multi=multi
    f:ClearAllPoints(); f:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",0,-4)
    f:SetSize(240,44+math.min(8,#options)*29)
    local offset=0
    local function draw()
        for i,b in ipairs(f.entries) do
            local value=options[offset+i]; b.value=value; b:SetShown(value~=nil)
            local active=value and (multi and current(value) or not multi and value==current)
            b.text:SetText(value and ((multi and (active and "[x] " or "[ ] ") or "")..value) or ""); b:SetSelected(active and true or false)
        end
    end
    f:EnableMouseWheel(true); f:SetScript("OnMouseWheel",function(_,delta)
        offset=math.max(0,math.min(math.max(0,#options-8),offset-delta)); draw()
    end)
    f.draw=draw; draw(); f:Show()
end
function U:Settings()
    if self.settings then self.settings:SetShown(not self.settings:IsShown()); return end
    local f=panel(self.frame,510,458,285,-100); f:SetFrameLevel(self.frame:GetFrameLevel()+40); self.settings=f; f:EnableMouse(true); f:SetBackdropColor(0.035,0.045,0.060,1)
    self.officerButton=button(f,"Officer settings",150,20,-412,function() G.ShowOfficerSettings() end)
    self.officerButton:SetShown(G.IsOfficer(G.self))
    label(f,"Your roles",20,20,-20,380)
    button(f,"Close",65,425,-16,function() f:Hide() end)
    label(f,"Automatic uses your spec. Choose roles to override it.",12,20,-62,470)
    local buttons={}; self.roleChoices=buttons
    local function refresh()
        local selected={}; for _,role in ipairs(G.db.settings.roles) do selected[role]=true end
        for role,b in pairs(buttons) do b:SetSelected(role=="Automatic" and #G.db.settings.roles==0 or selected[role]==true) end
    end
    local function publish()
        local r=G.Get("profile",G.self)
        if r then local d=G.Decode(G.Encode(r.data)); d.roles=G.db.settings.roles; G.Publish("profile",d) end
        refresh(); U:Render()
    end
    buttons.Automatic=button(f,"Automatic",110,20,-96,function() G.db.settings.roles={}; publish() end)
    for i,role in ipairs({"Tank","Healer","DPS"}) do
        buttons[role]=button(f,role,110,20+i*120,-96,function()
            local list,had={},false
            for _,v in ipairs(G.db.settings.roles) do if v==role then had=true else list[#list+1]=v end end
            if not had then list[#list+1]=role end
            G.db.settings.roles=list; publish()
        end)
    end
    label(f,"Feral defaults to Tank / DPS. Your choice is shared.",11,20,-137,470)
    if G.PreferenceControls then G.PreferenceControls(f,20,-180) end
    refresh()
end
function U:SwitchTab(tab)
    self.onlineByTab=self.onlineByTab or {Roster=true,Crafting=false}
    if self.tab~="Guild Loot" then self.onlineByTab[self.tab]=self.online end
    self.tab=tab
    self.online=self.onlineByTab[tab] or false
    self.onlineButton.text:SetText(self.online and "Online only" or "All members")
end
function U:Create()
    if self.frame then return end
    if G.RestorePreferences then G.RestorePreferences() end
    local f=panel(UIParent,1080,700,0,0,"GuildLedgerWindow"); self.frame=f; f:SetFrameStrata("DIALOG")
    f:ClearAllPoints(); f:SetPoint("CENTER"); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",function(self) self:StopMovingOrSizing(); local _,_,_,x,y=self:GetPoint(); G.db.position={x=x,y=y} end)
    local function scale() f:SetScale(math.min(G.db.settings.uiScale or 1,(UIParent:GetWidth()-24)/1080,(UIParent:GetHeight()-24)/700)) end
    scale(); G.ScaleUI=scale
    UISpecialFrames=UISpecialFrames or {}; table.insert(UISpecialFrames,"GuildLedgerWindow")
    if G.db.position then f:ClearAllPoints(); f:SetPoint("CENTER",UIParent,"CENTER",G.db.position.x,G.db.position.y) end
    label(f,"Guild Ledger",24,24,-18,600):SetTextColor(unpack(gold))
    self.guild=label(f,"",12,25,-49,700)
    local divider=f:CreateTexture(nil,"ARTWORK"); divider:SetColorTexture(0.25,0.22,0.15,1); divider:SetSize(1032,1); divider:SetPoint("TOPLEFT",24,-66)
    button(f,"×",32,1024,-20,function() f:Hide() end)
    button(f,"Settings",90,920,-20,function() U:Settings() end)
    self.discordButton=button(f,"Discord",130,778,-20,function() G.ShowDiscord() end)
    buttonIcon(self.discordButton,"Interface\\Icons\\INV_Misc_GroupNeedMore")
    self.discordButton:SetScript("OnEnter",function(b) b:SetBackdropColor(0.16,0.18,0.32,1); tooltip({tooltipOwner=b,data={title="Guild Discord",tip="Open the guild invite link to copy into your browser."}}) end)
    self.tabs={}
    for i,tab in ipairs({"Roster","Crafting","Guild Loot"}) do self.tabs[tab]=button(f,tab,125,24+(i-1)*133,-78,function() U:SwitchTab(tab); U.offset=0; U.detailOffset=0; U.showInfo=false; if U.picker then U.picker:Hide() end; if U.rarityPicker then U.rarityPicker:Hide() end; U:Render() end) end
    for tab,icon in pairs({Roster="INV_Misc_GroupNeedMore",Crafting="Trade_BlackSmithing",["Guild Loot"]="INV_Misc_Bag_10"}) do buttonIcon(self.tabs[tab],"Interface\\Icons\\"..icon) end
    button(f,"Guild info",100,956,-78,function() U.showInfo=not U.showInfo; U.detailOffset=0; U:Render() end)
    self.motd=label(f,"",11,24,-119,1032); self.motd:SetTextColor(0.70,0.68,0.58)
    self.search=edit(f,244,24,-150,function(text) G.After("search",0.2,function() U.query=text; U.offset=0; U:Render() end) end)
    self.searchHint=label(self.search,"Search characters, professions or items",12,10,0,224)
    self.searchHint:ClearAllPoints(); self.searchHint:SetPoint("LEFT",10,0)
    self.searchHint:SetTextColor(0.70,0.75,0.80)
    self.search:SetText(self.query)
    self.search:HookScript("OnTextChanged",function(e) self.searchHint:SetShown(self.tab~="Guild Loot" and e:GetText()=="" and not e:HasFocus()) end)
    self.search:HookScript("OnEditFocusGained",function() self.searchHint:Hide() end)
    self.search:HookScript("OnEditFocusLost",function(e) self.searchHint:SetShown(self.tab~="Guild Loot" and e:GetText()=="") end)
    local online=button(f,self.online and "Online only" or "All members",110,274,-150,function(b) U.online=not U.online; b.text:SetText(U.online and "Online only" or "All members"); U.offset=0; U:Render() end)
    self.clearButton=button(f,"Clear",68,988,-150,function() U.craftBinding=nil; U.craftQuality=nil; U.craftOwner=nil; U.craftSkill=nil; U.craftName=nil; U.search:SetText(""); U.query=""; U.role="Any role"; U.class="Any class"; U.spec="Any spec"; U.online=U.tab=="Roster"; online.text:SetText(U.online and "Online only" or "All members"); U.roleButton.text:SetText(U.role); U.classButton.text:SetText(U.class); U.specButton.text:SetText(U.spec); if U.picker then U.picker:Hide() end; if U.rarityPicker then U.rarityPicker:Hide() end; U.offset=0; U:Render() end)
    self.roleButton=button(f,"Any role",120,396,-150,function(b)
        U:Choose(b,{"Any role","Tank","Healer","DPS"},U.role,function(value) U.role=value; b.text:SetText(value) end)
    end)
    self.classButton=button(f,"Any class",170,528,-150,function(b)
        local seen={}; for _,m in pairs(G.members) do seen[className(m)]=true end
        local options=G.Keys(seen); table.insert(options,1,"Any class")
        U:Choose(b,options,U.class,function(value)
            U.class=value; b.text:SetText(value); U.spec="Any spec"; U.specButton.text:SetText(U.spec)
        end)
    end)
    self.specButton=button(f,"Any spec",266,710,-150,function(b)
        local seen={}
        for name,m in pairs(G.members) do
            if U.class=="Any class" or className(m)==U.class then
                local r=G.Get("profile",name)
                for _,t in ipairs(r and r.data.trees or {}) do if G.SpecMatches(r.data,t.name) then seen[t.name]=true end end
            end
        end
        local options=G.Keys(seen); table.insert(options,1,"Any spec")
        U:Choose(b,options,U.spec,function(value) U.spec=value; b.text:SetText(value) end)
    end)
    self.professionButton=button(f,"All professions",266,396,-150,function(b)
        local options,ids=U:CraftingOptions()
        U:Choose(b,options,U.craftName or "All professions",function(value)
            U.craftSkill=ids[value]; U.craftName=ids[value] and value or nil
            U.recipe=nil; U.profession=nil; U.detailOffset=0
        end)
    end)
    self.qualityButton=button(f,"All rarities",170,674,-150,function(b)
        U:Choose(b,{"All rarities","Poor","Common","Uncommon","Rare","Epic","Legendary","Artifact","Heirloom","Enchants / spells","Unknown quality"},U.craftQuality or "All rarities",function(value)
            U.craftQuality=value; U.recipe=nil; U.profession=nil; U.detailOffset=0
        end)
    end)
    self.bindingButton=button(f,"Hide BoP",120,856,-150,function(b)
        U:Choose(b,{"Hide BoP","BoE only","BoP only","All bindings","Unknown binding"},U.craftBinding or "Hide BoP",function(value)
            U.craftBinding=value; U.recipe=nil; U.profession=nil; U.detailOffset=0
        end)
    end)
    self.crafterButton=button(f,"All crafters",120,856,-112,function()
        U.craftOwner=nil; U.query=""; U.search:SetText(""); U.offset=0; U.recipe=nil; U.profession=nil; U:Render()
    end)
    self.roleButton.text:SetText(self.role); self.classButton.text:SetText(self.class); self.specButton.text:SetText(self.spec)
    self.onlineButton=online
    local left=panel(f,600,466,24,-190); local right=panel(f,416,466,640,-190)
    self.left,self.right=left,right
    self.dayHeadings={}; for i=1,8 do self.dayHeadings[i]=label(left,"",11,16,-38,950); self.dayHeadings[i]:SetTextColor(unpack(gold)); self.dayHeadings[i]:Hide() end
    self.lootHeaders={label(left,"RECIPIENT",11,480,-14,265),label(left,"QTY",11,756,-14,50),label(left,"RECEIVED",11,824,-14,190)}
    self.listHeading=label(left,"CHARACTER",10,20,-14,200)
    self.columnHeaders={label(left,"SPEC / POINTS",10,254,-14,172),label(left,"ROLE / SKILLS",10,438,-14,145)}
    for i=1,12 do self.rows[i]=row(left,584,47,8,-38-(i-1)*48) end
    self.empty=label(left,"",14,20,-120,510)
    self.count=label(left,"",11,16,-440,350)
    self.previous=button(left,"<",40,492,-430,function() U.offset=math.max(0,U.offset-(U.pageSize or 8)); U:Render() end)
    self.nextPage=button(left,">",40,540,-430,function() U.offset=U.offset+(U.pageSize or 8); U:Render() end)
    left:EnableMouseWheel(true); left:SetScript("OnMouseWheel",function(_,d) U.offset=math.max(0,U.offset-d*3); U:Render() end)
    self.detailTitle=label(right,"",18,16,-16,384)
    self.detailSubtitle=label(right,"",11,16,-42,384)
    self.sectionButtons={}
    for i,section in ipairs({"Spec","Gear","Professions","Loot"}) do self.sectionButtons[i]=button(right,section,92,16+(i-1)*97,-64,function() U.section=section; U.detailOffset=0; U:Render() end) end
    for i=1,14 do self.details[i]=row(right,384,23,16,-102-(i-1)*24) end
    self.detailCount=label(right,"",10,16,-446,384)
    self:CreateSpec(right)
    self:CreateGear(right)
    self:CreateProfessions(right)
    self:CreateRecipe(right)
    right:EnableMouseWheel(true); right:SetScript("OnMouseWheel",function(_,d) U.detailOffset=math.max(0,U.detailOffset-d*3); U:Render() end)
    self.status=label(f,"",11,24,-670,360)
    self.notice=label(f,"",10,400,-670,656); self.notice:SetJustifyH("RIGHT")
    f:SetScript("OnHide",function() if G.SavePreferences then G.SavePreferences() end; GameTooltip:Hide(); if U.picker then U.picker:Hide() end; if U.rarityPicker then U.rarityPicker:Hide() end; if U.settings then U.settings:Hide() end end)
    f:SetScript("OnShow",function() U:Render() end)
    f:Hide()
end
function G.Toggle() U:Create(); U.frame:SetShown(not U.frame:IsShown()) end
function G.Launcher()
    local broker=LibStub("LibDataBroker-1.1")
    local icons=LibStub("LibDBIcon-1.0")
    if type(G.db.minimap)~="table" then G.db.minimap={} end
    if type(G.db.minimap.minimapPos)~="number" then
        G.db.minimap.minimapPos=type(G.db.minimapAngle)=="number" and G.db.minimapAngle or 135
    end
    local object=broker:GetDataObjectByName("GuildLedger") or broker:NewDataObject("GuildLedger",{
        type="launcher",label="Guild Ledger",text="Guild Ledger",
        icon="Interface\\Icons\\INV_Misc_Book_09",
        OnClick=function(_,mouseButton) if mouseButton=="LeftButton" then G.Toggle() end end,
        OnEnter=function(frame)
            tooltip({data={title="Guild Ledger",tip="Click to open. Drag around the minimap to move. /gl also opens the window."},tooltipOwner=frame})
        end,
        OnLeave=function() GameTooltip:Hide() end,
    })
    G.broker=object
    if icons:IsRegistered("GuildLedger") then icons:Refresh("GuildLedger",G.db.minimap)
    else icons:Register("GuildLedger",object,G.db.minimap) end
    G.launcher=icons:GetMinimapButton("GuildLedger")
end

G.UIWidgets={label=label,button=button,panel=panel,buttonIcon=buttonIcon}
