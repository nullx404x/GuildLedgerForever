local _,G=...
local U,W=G.UI,G.UIWidgets
local function note(parent,text,y)
    local t=W.label(parent,text,11,20,y,470); t:SetTextColor(0.75,0.79,0.84); t:SetWordWrap(true); t:SetHeight(38); return t
end
-- Settings use quiet rows; only the check itself carries the selected state.
local function quietButton(b,navigation)
    b.SetSelected=function(self,value)
        self.selected=value==true
        self:SetBackdropBorderColor(0,0,0,0)
        self:SetBackdropColor(0.16,0.17,0.18,navigation and self.selected and 1 or 0)
        self.text:SetTextColor(unpack(navigation and self.selected and {0.88,0.73,0.43} or {0.85,0.88,0.91}))
    end
    b:SetScript("OnEnter",function() if not b:ShowDisabledReason() then b:SetBackdropColor(0.16,0.17,0.18,0.6) end end)
    b:SetSelected(false)
end
G.SettingsQuietButton=quietButton
local function divider(parent,y)
    local line=parent:CreateTexture(nil,"ARTWORK")
    line:SetColorTexture(0.18,0.21,0.25,0.7); line:SetSize(470,1); line:SetPoint("TOPLEFT",20,y)
end
local function checkbox(parent,text,y,fn)
    local b=W.button(parent,text,470,20,y,fn)
    quietButton(b,false)
    b:SetHeight(28); b.text:ClearAllPoints(); b.text:SetPoint("LEFT",28,0); b.text:SetWidth(436); b.text:SetJustifyH("LEFT")
    local box=W.panel(b,18,18,0,-5)
    local mark=box:CreateTexture(nil,"OVERLAY"); mark:SetAllPoints(); mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local selected=b.SetSelected
    b.SetSelected=function(self,value) selected(self,value); mark:SetShown(value==true) end
    return b
end
G.SettingsCheckbox=checkbox
local function pageFrame(parent,title,scope,description)
    local f=CreateFrame("Frame",nil,parent); f:SetSize(510,510); f:SetPoint("TOPLEFT",250,-80)
    W.label(f,title,20,20,-18,470):SetTextColor(0.94,0.94,0.92)
    note(f,scope, -50); note(f,description,-83)
    return f
end
function G.OpenSettingsPage(page)
    U:Create(); U.frame:Show()
    local f=U.settings
    if not f then
        f=W.panel(U.frame,800,620,140,-40,"GuildLedgerSettings"); U.settings=f
        f:SetFrameLevel(U.frame:GetFrameLevel()+40); f:EnableMouse(true); f:SetClampedToScreen(true)
        f:SetBackdropColor(0.035,0.045,0.060,1)
        W.label(f,"Guild Ledger",22,24,-18,480):SetTextColor(0.88,0.73,0.43)
        note(f,"Settings",-52)
        W.button(f,"Close",70,706,-22,function() f:Hide() end)
        local sidebar=W.panel(f,214,494,16,-88); sidebar:SetBackdropColor(0.055,0.065,0.08,1); sidebar:SetBackdropBorderColor(0,0,0,0)
        f.nav={}; f.pages={}; f.page="general"
        local personalLabel=W.label(sidebar,"YOUR SETTINGS",10,12,-12,190); personalLabel:SetTextColor(0.55,0.61,0.68)
        f.guildLabel=W.label(sidebar,"GUILD CONTROLS",10,12,-155,190); f.guildLabel:SetTextColor(0.55,0.61,0.68)
        f.supportLabel=W.label(sidebar,"SUPPORT",10,12,-275,190); f.supportLabel:SetTextColor(0.55,0.61,0.68)
        local entries={{"general","General","Interface\\Icons\\Trade_Engineering"},{"character","Your character","Interface\\Icons\\INV_Misc_Book_09"},{"map","Guild map","Interface\\Icons\\INV_Misc_Map_01"},{"officer","Officer tools","Interface\\Icons\\INV_Shield_06"},{"management","Guild management","Interface\\Icons\\INV_Crown_01"},{"help","Help & diagnostics","Interface\\Icons\\INV_Misc_QuestionMark"}}
        for _,entry in ipairs(entries) do
            local key=entry[1]
            local b=W.button(sidebar,entry[2],198,8,-8,function() G.OpenSettingsPage(key) end)
            quietButton(b,true); W.buttonIcon(b,entry[3]); b.text:SetJustifyH("LEFT"); f.nav[key]=b
        end
        f.footer=W.label(f,"",11,24,-597,750)
        local general=pageFrame(f,"General","Only affects you","Make Guild Ledger comfortable to use."); f.pages.general=general
        W.label(general,"Window scale",14,20,-119,300)
        general.scaleValue=W.label(general,"",12,406,-119,84)
        local slider=CreateFrame("Slider",nil,general,"BackdropTemplate"); general.scale=slider
        slider:SetOrientation("HORIZONTAL"); slider:SetSize(340,20); slider:SetPoint("TOPLEFT",20,-151)
        slider:SetMinMaxValues(0.65,1.25); slider:SetValueStep(0.05); slider:SetObeyStepOnDrag(true)
        local track=slider:CreateTexture(nil,"BACKGROUND"); track:SetColorTexture(0.19,0.22,0.27,1); track:SetHeight(4); track:SetPoint("LEFT"); track:SetPoint("RIGHT")
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        slider:SetScript("OnValueChanged",function(_,value)
            if f.refreshing then return end
            G.db.settings.uiScale=math.max(0.65,math.min(1.25,math.floor(value*20+0.5)/20))
            if G.ScaleUI then G.ScaleUI() end; f.refresh()
        end)
        general.resetScale=W.button(general,"Reset",100,390,-146,function() G.db.settings.uiScale=1; if G.ScaleUI then G.ScaleUI() end; f.refresh() end)
        W.label(general,"65%",11,20,-178,60); W.label(general,"125%",11,320,-178,60)
        general.minimap=checkbox(general,"Show minimap button",-216,function()
            G.db.minimap=G.db.minimap or {}; G.db.minimap.hide=not G.db.minimap.hide
            local icons=LibStub("LibDBIcon-1.0"); if G.db.minimap.hide then icons:Hide("GuildLedger") else icons:Show("GuildLedger") end
            f.refresh()
        end)
        note(general,"Drag the button around the edge of your minimap.",-247)
        general.resetMinimap=W.button(general,"Reset minimap position",220,20,-279,function()
            G.db.minimap=G.db.minimap or {}; G.db.minimap.minimapPos=135; G.db.minimap.hide=false; G.db.minimap.lock=false
            LibStub("LibDBIcon-1.0"):Refresh("GuildLedger",G.db.minimap); f.refresh()
        end)
        general.resetWindow=W.button(general,"Reset window position",220,20,-348,function() G.ResetPosition(); f.refresh() end)
        note(general,"Centers the window and restores its default scale.",-384)
        note(general,"Set an open / close key in WoW's Key Bindings.",-458)
        divider(general,-204); divider(general,-326)
        local character=pageFrame(f,"Your character","Your role is shared with the guild","Automatic uses your specialization. Choose roles to override it."); f.pages.character=character
        character.name=W.label(character,"",16,20,-125,470)
        U.roleChoices={}
        local function publish()
            local r=G.Get("profile",G.self)
            if r then local d=G.Copy(r.data); d.roles=G.Copy(G.db.settings.roles); G.Publish("profile",d) end
            f.refresh(); U:Render()
        end
        U.roleChoices.Automatic=checkbox(character,"Automatic role",-167,function() G.db.settings.roles={}; publish() end)
        for i,role in ipairs({"Tank","Healer","DPS"}) do
            U.roleChoices[role]=checkbox(character,role,-213-(i-1)*44,function()
                local list,had={},false
                for _,v in ipairs(G.db.settings.roles) do if v==role then had=true else list[#list+1]=v end end
                if not had then list[#list+1]=role end
                G.db.settings.roles=list; publish()
            end)
        end
        note(character,"You may choose more than one role. Feral defaults to Tank / DPS.",-363)
        local map=pageFrame(f,"Guild map","Only affects you","Find guild members while you're out in the world."); f.pages.map=map
        map.show=checkbox(map,"Show guild members on the map",-123,function() G.SetShowLocations(not G.db.settings.showGuildLocations); f.refresh() end)
        note(map,"Display markers for members sharing their location.",-157)
        map.share=checkbox(map,"Share my location",-228,function() G.SetLocationSharing(not G.db.settings.shareLocation); f.refresh() end)
        note(map,"Let guild members using Guild Ledger see your location. No location history is saved.",-262)
        divider(map,-207)
        local management=pageFrame(f,"Guild management","Guild master only · Applies to the guild",""); f.pages.management=management
        management.inviteTab=W.button(management,"Discord invite",150,20,-80,function() end); management.inviteTab:SetSelected(true)
        management.accessTab=W.button(management,"Permissions",150,180,-80,function() G.OpenSettingsPage("permissions") end)
        W.label(management,"Guild Discord invite",14,20,-142,470)
        note(management,"The Discord button opens this invite for your guild.",-177)
        management.invite=W.edit(management,470,20,-229,function() management.dirty=true; management.status:SetText("Unsaved changes · Save invite to apply.") end)
        management.invite:SetMaxLetters(120)
        management.save=W.button(management,"Save invite",150,340,-278,function()
            local ok,err=G.SetGuildInvite(management.invite:GetText())
            if ok then management.dirty=false; management.invite:ClearFocus(); f.refresh() end
            management.status:SetText(ok and "Guild invite saved." or err)
        end)
        note(management,"Leave the field blank and save to remove the invite.",-328)
        management.status=note(management,"",-384)
        local help=pageFrame(f,"Help & diagnostics","Only affects you","Useful information when something isn't working."); f.pages.help=help
        W.label(help,"Guild Ledger "..G.VERSION,16,20,-123,470)
        note(help,"Standalone · All required libraries are included.",-179)
        W.label(help,"Sync status",14,20,-224,470)
        help.sync=note(help,"",-258)
        W.button(help,"Copy diagnostics",190,20,-316,G.ShowDiagnostics)
        W.button(help,"Quick introduction",190,20,-416,function() G.ShowWelcome(true) end)
        note(help,"Opens a copy window. Diagnostics include guild character names.",-355)
        f:SetScript("OnHide",function()
            G.CancelPromotions()
            if U.officerPanel then U.officerPanel:Hide() end
            management.invite:ClearFocus()
            if U.picker then U.picker:Hide() end
        end)
        f.refresh=function()
            if f.refreshing then return end
            f.refreshing=true
            local officer,leader=G.HasOfficerTools(G.self),G.IsGuildLeader(G.self)
            if G.ready and ((f.page=="officer" and not officer) or ((f.page=="management" or f.page=="permissions") and not leader)) then
                f.page="general"; G.CancelPromotions(); management.dirty=false; management.invite:SetText("")
            end
            local y=32
            for _,entry in ipairs(entries) do
                local key=entry[1]; local b=f.nav[key]
                local visible=(key~="officer" or officer) and (key~="management" or leader)
                b:SetShown(visible)
                if key=="officer" then
                    f.guildLabel:SetShown(officer or leader)
                    if officer or leader then y=y+32; f.guildLabel:ClearAllPoints(); f.guildLabel:SetPoint("TOPLEFT",12,-y+20) end
                elseif key=="help" then
                    y=y+32; f.supportLabel:ClearAllPoints(); f.supportLabel:SetPoint("TOPLEFT",12,-y+20)
                end
                if visible then b:ClearAllPoints(); b:SetPoint("TOPLEFT",8,-y); y=y+36 end
                b:SetSelected(f.page==key or key=="management" and f.page=="permissions")
            end
            for key,p in pairs(f.pages) do p:SetShown(key==f.page) end
            if U.officerPanel then
                local show=f.page=="officer" or f.page=="permissions"
                U.officerPanel:SetShown(show)
                if show then U.officerPanel.refresh() end
            end
            general.scale:SetValue(G.db.settings.uiScale or 1)
            general.scaleValue:SetText(math.floor((G.db.settings.uiScale or 1)*100+0.5).."%")
            general.minimap:SetSelected(not (G.db.minimap and G.db.minimap.hide))
            character.name:SetText(G.Plain(G.self))
            local selected={}; for _,role in ipairs(G.db.settings.roles) do selected[role]=true end
            for role,b in pairs(U.roleChoices) do b:SetSelected(role=="Automatic" and #G.db.settings.roles==0 or selected[role]==true) end
            map.show:SetSelected(G.db.settings.showGuildLocations==true); map.share:SetSelected(G.db.settings.shareLocation==true)
            management.save:SetEnabled(leader,"Only the guild master can save the guild invite.")
            if not management.dirty then management.invite:SetText(G.DiscordInvite()) end
            help.sync:SetText(not G.ready and "Waiting for the guild roster…" or G.SyncProgress and G.SyncProgress() or G.PeerSummary())
            f.footer:SetText(f.savedUntil and G.clock()<f.savedUntil and "Guild settings saved." or (G.guildName or "Guild Ledger").." · Personal preferences save automatically")
            f.refreshing=false
        end
        UISpecialFrames[#UISpecialFrames+1]="GuildLedgerSettings"
    end
    page=page or f.page or "general"
    if page=="officer" and not G.HasOfficerTools(G.self) then page="general" end
    if (page=="management" or page=="permissions") and not G.IsGuildLeader(G.self) then page="general" end
    if not f.pages[page] and page~="officer" and page~="permissions" then page="general" end
    if (page=="officer" or page=="permissions") and not U.officerPanel then G.BuildOfficerSettings(f) end
    if page=="permissions" then U.officerPanel.section="access"
    elseif page=="officer" and U.officerPanel.section=="access" then U.officerPanel.section="loot" end
    f.page=page; f:Show(); f.refresh()
end

function G.SettingsSaved()
    if not U.settings then return end
    U.settings.savedUntil=G.clock()+3
    U.settings.footer:SetText("Guild settings saved.")
    G.After("settings-saved",3,function() if U.settings and U.settings:IsShown() then U.settings.refresh() end end)
end
function G.ShowWelcome(force)
    if G.db.welcomeSeen and not force then return end
    local f=U.welcome
    if not f then
        f=W.panel(U.frame,510,320,285,-170,"GuildLedgerWelcome"); U.welcome=f
        f:SetFrameLevel(U.frame:GetFrameLevel()+100); f:EnableMouse(true)
        W.label(f,"Welcome to Guild Ledger",20,24,-22,462):SetTextColor(0.88,0.73,0.43)
        local body=W.label(f,"Find guild crafters, browse shared gear and talents, and follow guild loot. Members need Guild Ledger to share their data.",13,24,-64,462)
        body:SetWordWrap(true); body:SetHeight(64)
        local sharing=W.label(f,"Your character, known recipes and eligible loot are shared with the guild. Location sharing can be turned off in Guild map settings. Open your professions to share recipes.",13,24,-138,462)
        sharing:SetWordWrap(true); sharing:SetHeight(78)
        W.button(f,"Your role",140,24,-235,function() f:Hide(); G.OpenSettingsPage("character") end)
        W.button(f,"Guild map",140,184,-235,function() f:Hide(); G.OpenSettingsPage("map") end)
        W.button(f,"Got it",140,344,-235,function() f:Hide() end)
        W.label(f,"You can reopen this introduction in Help & diagnostics.",11,24,-286,462)
        UISpecialFrames[#UISpecialFrames+1]="GuildLedgerWelcome"
    end
    G.db.welcomeSeen=true; f:Show()
end
