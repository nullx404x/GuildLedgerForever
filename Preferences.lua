local _,G=...
local U=G.UI
local W=G.UIWidgets
local function clamp(value,lo,hi,default)
    return type(value)=="number" and value==value and math.max(lo,math.min(hi,value)) or default
end
local function text(value,default)
    return type(value)=="string" and #value<=200 and value or default
end
function G.RestorePreferences()
    local prefs=type(G.db.ui)=="table" and G.db.ui or {}
    G.db.settings.uiScale=clamp(G.db.settings.uiScale,0.65,1.25,1)
    U.tab=({Roster=true,Crafting=true,["Guild Loot"]=true})[prefs.tab] and prefs.tab or "Guild Loot"
    U.section=({Spec=true,Gear=true,Professions=true,Loot=true})[prefs.section] and prefs.section or "Spec"
    U.query=text(prefs.query,""); U.role=text(prefs.role,"Any role"); U.class=text(prefs.class,"Any class"); U.spec=text(prefs.spec,"Any spec")
    U.craftSkill=type(prefs.craftSkill)=="number" and prefs.craftSkill or nil
    U.craftName=text(prefs.craftName,nil); U.craftQuality=text(prefs.craftQuality,nil)
    U.craftBinding=({["Hide BoP"]=true,["BoE only"]=true,["BoP only"]=true,["All bindings"]=true,["Unknown binding"]=true})[prefs.craftBinding] and prefs.craftBinding or "Hide BoP"
    -- Character shortcuts are temporary; preserve general browse preferences only.
    U.craftOwner=nil
    local online=type(prefs.online)=="table" and prefs.online or {}
    U.onlineByTab={Roster=online.Roster~=false,Crafting=online.Crafting==true}
    U.online=U.onlineByTab[U.tab] or false
end
function G.SavePreferences()
    if not G.db or not U.frame then return end
    U.onlineByTab=U.onlineByTab or {Roster=true,Crafting=false}
    if U.tab~="Guild Loot" then U.onlineByTab[U.tab]=U.online end
    G.db.ui={tab=U.tab,section=U.section,query=U.query,role=U.role,class=U.class,spec=U.spec,craftSkill=U.craftSkill,craftName=U.craftName,craftQuality=U.craftQuality,craftBinding=U.craftBinding,online={Roster=U.onlineByTab.Roster,Crafting=U.onlineByTab.Crafting}}
end
function G.ResetPosition()
    G.db.position=nil; G.db.settings.uiScale=1
    if U.frame then U.frame:ClearAllPoints(); U.frame:SetPoint("CENTER"); G.ScaleUI() end
end
function G.PeerSummary()
    local old,unknown,incompatible=0,0,0
    for name in pairs(G.peers) do
        local status=G.PeerStatus(name)
        if status=="Older version" then old=old+1 elseif status=="Update required (0.4.0+)" then incompatible=incompatible+1 elseif status=="Version unknown" then unknown=unknown+1 end
    end
    local s=G.Count(G.peers).." addon peers"
    if old>0 then s=s.." | "..old.." older" end
    if unknown>0 then s=s.." | "..unknown.." version unknown" end
    if incompatible>0 then s=s.." | "..incompatible.." need update" end
    return s
end
-- The footer describes observed local activity, not a guarantee that offline data is current.
function G.FriendlySyncStatus()
    if not G.scope then return "Join a guild to begin" end
    if not G.ready then return "Loading guild members…" end
    if next(G.manifestJobs or {}) or next(G.partials or {}) or next(G.outstanding or {}) then return "Receiving guild data…" end
    if next(G.peers or {})==nil then return "No addon users connected" end
    return "Up to date with connected members"
end
function G.DiagnosticsText()
    local version,build,_,interface=GetBuildInfo()
    local lines={"Guild Ledger "..G.VERSION,"Client: "..tostring(version).." / "..tostring(build).." / interface "..tostring(interface),"Protocol: "..G.PROTOCOL,"Roster ready: "..tostring(G.ready),"Records: "..G.Count(G.store and G.store.records),"Queued transfers: "..#G.queue,"Partial transfers: "..G.Count(G.partials),"Awaiting acknowledgment: "..G.Count(G.sent),"Catch-up sources: "..G.Count(G.manifestJobs),"Shared recipe definitions: "..G.Count(G.recipePool),G.PeerSummary(),"", "Peers (includes character names):"}
    for _,name in ipairs(G.Keys(G.peers)) do
        local info=G.peerInfo[name]
        lines[#lines+1]=G.Plain(name)..": "..(info and info.version or "unknown").." - "..G.PeerStatus(name)
    end
    lines[#lines+1]=""; lines[#lines+1]="Diagnostics:"
    for _,key in ipairs(G.Keys(G.errors)) do lines[#lines+1]=G.Plain(key)..": "..G.Plain(G.errors[key]):sub(1,500) end
    local p=G.performance
    if p then
        lines[#lines+1]=""; lines[#lines+1]="Performance since reload (local only):"
        lines[#lines+1]=string.format("Sync traffic: %.1f KiB sent / %.1f KiB received; %d / %d packets",p.sentBytes/1024,p.receivedBytes/1024,p.sentPackets,p.receivedPackets)
        lines[#lines+1]=string.format("Send refusals: %d; average outgoing: %.1f bytes/sec",p.failures,p.sentBytes/math.max(1,G.clock()-p.started))
        lines[#lines+1]=p.ticks>0 and string.format("Sync tick: %.2f ms mean / %.2f ms peak; receive: %.2f ms mean / %.2f ms peak",p.totalTick/p.ticks,p.peakTick,p.totalReceive/math.max(1,p.receives),p.peakReceive) or "CPU timing: unavailable on this client"
        -- Refresh memory counters only on explicit diagnostics, not during gameplay ticks.
        G.Safe(C_AddOns and C_AddOns.UpdateAddOnMemoryUsage or UpdateAddOnMemoryUsage)
        local memory=G.Safe(C_AddOns and C_AddOns.GetAddOnMemoryUsage or GetAddOnMemoryUsage,"GuildLedger")
        if type(memory)=='number' then
            p.peakMemory=math.max(p.peakMemory,memory)
            lines[#lines+1]=string.format("Addon memory: %.2f MiB current / %.2f MiB peak",memory/1024,p.peakMemory/1024)
            lines[#lines+1]="Memory sampled when opening diagnostics, before garbage collection."
        end
        lines[#lines+1]="Recipe templates: "..G.Count(G.bookTemplates).."; estimated cache budget: "..G.bookTemplateBytes.." / 262144 bytes"
        lines[#lines+1]="Gear is fetched on demand; cached snapshots are retained."
    end
    return table.concat(lines,"\n")
end
-- A local copy dialog: no browser launching, chat sending or sync payload changes.
function G.ShowDiscord(edit)
    if not U.discord then
        local f=W.panel(UIParent,530,216,0,0,"GuildLedgerDiscord"); U.discord=f
        f:ClearAllPoints(); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetClampedToScreen(true); f:EnableMouse(true)
        W.label(f,"Guild Discord",20,20,-18,350):SetTextColor(0.68,0.72,1)
        W.button(f,"Close",70,440,-18,function() f:Hide() end)
        f.description=W.label(f,"",11,20,-58,490)
        local box=CreateFrame("EditBox",nil,f,"InputBoxTemplate"); f.box=box
        box:SetSize(478,28); box:SetPoint("TOPLEFT",26,-88); box:SetAutoFocus(false); box:SetMaxLetters(120)
        box:SetScript("OnEscapePressed",function() f:Hide() end)
        box:SetScript("OnEnterPressed",function(self) self:HighlightText(); self:SetFocus() end)
        box:SetScript("OnTextChanged",function(self,user) if user and not f.editing then self:SetText(G.DiscordInvite()); self:HighlightText() end end)
        f.note=W.label(f,"",11,20,-136,490)
        f.manage=W.button(f,"Edit invite",110,400,-170,function() G.ShowDiscord(true) end)
        f.save=W.button(f,"Save invite",110,400,-170,function()
            local ok,err=G.SetGuildInvite(box:GetText())
            if ok then G.ShowDiscord(false) else f.note:SetText(err) end
        end)
        f:SetScript("OnHide",function() box:ClearFocus() end)
        UISpecialFrames=UISpecialFrames or {}; table.insert(UISpecialFrames,"GuildLedgerDiscord")
    end
    local f=U.discord; local leader=G.IsGuildLeader(G.self); local invite=G.DiscordInvite()
    f.editing=edit==true and leader
    f.manage:SetShown(leader and not f.editing); f.save:SetShown(f.editing)
    f.description:SetText(f.editing and "Paste your guild's Discord invite. Leave blank to remove it." or "Copy the invite, then paste it into Discord or your browser.")
    f.note:SetText(f.editing and "Shared with guild members using Guild Ledger." or invite~="" and "Ctrl+C to copy" or "No invite shared yet. Ask your guild master to set one.")
    f:Show(); f.box:SetText(invite); f.box:SetFocus(); f.box:HighlightText()
end
function G.ShowDiagnostics()
    if not U.diagnostics then
        local f=W.panel(UIParent,580,430,0,0,"GuildLedgerDiagnostics"); U.diagnostics=f
        f:ClearAllPoints(); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:EnableMouse(true)
        W.label(f,"Copy diagnostics",20,16,-16,400)
        W.label(f,"Ctrl+C to copy. Includes peer character names.",11,16,-48,540)
        W.button(f,"Close",70,494,-16,function() f:Hide() end)
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",16,-78); scroll:SetSize(520,330)
        local box=CreateFrame("EditBox",nil,scroll); box:SetMultiLine(true); box:SetAutoFocus(false); G.ApplyTextFont(box,13); box:SetWidth(510)
        box:SetScript("OnEscapePressed",function() f:Hide() end); scroll:SetScrollChild(box); f.box=box
        UISpecialFrames=UISpecialFrames or {}; table.insert(UISpecialFrames,"GuildLedgerDiagnostics")
    end
    local f=U.diagnostics; local report=G.DiagnosticsText()
    local _,lines=report:gsub("\n",""); f.box:SetHeight(math.max(330,(lines+1)*18)); f.box:SetText(report)
    f:Show(); f.box:SetFocus(); f.box:HighlightText()
end
function G.PreferenceControls(parent,x,y)
    G.db.settings.uiScale=clamp(G.db.settings.uiScale,0.65,1.25,1)
    local mini,scale,map,share
    local function refresh()
        local hidden=G.db.minimap and G.db.minimap.hide
        mini.text:SetText(hidden and "Minimap: hidden" or "Minimap: shown")
        scale:SetText("Window scale: "..math.floor((G.db.settings.uiScale or 1)*100+0.5).."%")
        if map then map.text:SetText(G.db.settings.showGuildLocations and "Guild map: shown" or "Guild map: hidden") end
        if share then share.text:SetText(G.db.settings.shareLocation and "Share location: on" or "Share location: off") end
    end
    mini=W.button(parent,"",190,x,y,function()
        G.db.minimap=G.db.minimap or {}; G.db.minimap.hide=not G.db.minimap.hide
        local icons=LibStub("LibDBIcon-1.0"); if G.db.minimap.hide then icons:Hide("GuildLedger") else icons:Show("GuildLedger") end
        refresh()
    end)
    W.button(parent,"Reset minimap",190,x+210,y,function()
        G.db.minimap=G.db.minimap or {}; G.db.minimap.minimapPos=135; G.db.minimap.hide=false; G.db.minimap.lock=false
        LibStub("LibDBIcon-1.0"):Refresh("GuildLedger",G.db.minimap); refresh()
    end)
    scale=W.label(parent,"",12,x,y-48,230)
    local function resize(delta)
        G.db.settings.uiScale=clamp((G.db.settings.uiScale or 1)+delta,0.65,1.25,1)
        if G.ScaleUI then G.ScaleUI() end; refresh()
    end
    W.button(parent,"-",36,x+260,y-42,function() resize(-0.05) end)
    W.button(parent,"+",36,x+306,y-42,function() resize(0.05) end)
    W.button(parent,"Reset window",190,x,y-88,function() G.ResetPosition(); refresh() end)
    W.button(parent,"Copy diagnostics",190,x+210,y-88,G.ShowDiagnostics)
    map=W.button(parent,"",190,x,y-132,function()
        G.SetShowLocations(not G.db.settings.showGuildLocations); refresh()
    end)
    share=W.button(parent,"",190,x+210,y-132,function()
        G.SetLocationSharing(not G.db.settings.shareLocation); refresh()
    end)
    W.label(parent,"Map and sharing default on. Turn either off above. No history saved.",11,x,y-170,465)
    W.label(parent,"Assign an open/close key in WoW's Key Bindings.",11,x,y-204,465)
    parent:HookScript("OnShow",refresh); refresh()
end
function G.RegisterSettings()
    if U.nativeSettings then return end
    local f=CreateFrame("Frame"); f:Hide(); f.name="Guild Ledger"; U.nativeSettings=f
    W.label(f,"Guild Ledger",22,20,-20,450)
    W.label(f,"Changes save immediately. All libraries are included.",12,20,-60,500)
    W.button(f,"Open Guild Ledger settings",300,20,-100,function() if SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end; G.OpenSettingsPage() end)
    W.label(f,"Appearance, roles, guild map and authorized guild controls.",12,20,-150,500)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category=Settings.RegisterCanvasLayoutCategory(f,"Guild Ledger")
        Settings.RegisterAddOnCategory(category); U.settingsCategory=category
    elseif InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(f) end
end
function G.OpenSettings()
    if U.settingsCategory and Settings and Settings.OpenToCategory then Settings.OpenToCategory(U.settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory and U.nativeSettings then InterfaceOptionsFrame_OpenToCategory(U.nativeSettings)
    else U:Create(); U.frame:Show(); U:Settings() end
end
BINDING_HEADER_GUILDLEDGER="Guild Ledger"
BINDING_NAME_GUILDLEDGER_TOGGLE="Open / close Guild Ledger"
function GuildLedger_ToggleBinding() G.Toggle() end

function G.BuildOfficerSettings(host)
    if not G.HasOfficerTools(G.self) then return end
    if GameTooltip then GameTooltip:Hide() end
    local f=U.officerPanel
    if not f then
        f=W.panel(host or U.frame,510,310,285,-110,"GuildLedgerOfficerSettings"); U.officerPanel=f
        f.embedded=host~=nil
        f:SetFrameLevel(U.frame:GetFrameLevel()+60); f:EnableMouse(true)
        f:SetBackdropColor(0.035,0.045,0.060,1)
        f.title=W.label(f,"Officer tools",20,20,-18,360)
        local done=W.button(f,"Done",65,425,-18,function() f:Hide() end)
        done:SetShown(not f.embedded)
        f.subtitle=W.label(f,"Changes save automatically for the guild.",11,20,-51,470)
        f.section="loot"
        f.lootTab=W.button(f,"Loot feed",86,20,-80,function() f.section="loot"; f.refresh() end)
        f.announcementTab=W.button(f,"Announcements",130,112,-80,function() f.section="announcements"; f.refresh() end)
        f.accessTab=W.button(f,"Officer access",120,248,-80,function() f.section="access"; f.refresh() end)
        f.inviteTab=W.button(f,"Discord invite",150,20,-80,function() G.OpenSettingsPage("management") end); f.inviteTab:Hide()
        f.promotionTab=W.button(f,"Promotions",116,374,-80,function() f.section="promotions"; f.refresh() end)
        f.promotions=G.CreatePromotionControls(f)
        f:HookScript("OnHide",function() G.CancelPromotions() end)
        f.announcements=CreateFrame("Frame",nil,f); f.announcements:SetAllPoints()
        f.announcementEnabled=G.SettingsCheckbox(f.announcements,"Enable guild announcements",-120,function()
            if G.SetAnnouncementPolicy(not G.AnnouncementsEnabled(),G.AnnouncementRanks()) then G.SettingsSaved(); f.refresh() end
        end)
        W.label(f.announcements,"Only the guild master can turn announcements on or off.",11,20,-155,470)
        W.label(f.announcements,"Message · shown for 4 seconds",14,20,-189,470)
        f.announcementInput=W.edit(f.announcements,470,20,-216,function()
            f.announcementStatus:SetText("")
        end)
        f.announcementInput:SetMaxLetters(160)
        f.announcementSound=G.SettingsCheckbox(f.announcements,"Play a warning sound",-260,function()
            G.db.settings.announcementSound=not (G.db.settings.announcementSound~=false); f.refresh()
        end)
        f.previewAnnouncement=W.button(f.announcements,"Preview",120,20,-306,function()
            local ok,message=G.PreviewAnnouncement(f.announcementInput:GetText())
            f.announcementInput:ClearFocus(); f.announcementStatus:SetText(message)
        end)
        f.sendAnnouncement=W.button(f.announcements,"Send to guild",160,330,-306,function()
            local ok,message=G.SendAnnouncement(f.announcementInput:GetText())
            f.announcementInput:ClearFocus()
            if ok then f.announcementInput:SetText("") end
            f.announcementStatus:SetText(message)
        end)
        f.announcementStatus=W.label(f.announcements,"",11,20,-348,470)
        f.announcementStatus:SetWordWrap(true); f.announcementStatus:SetHeight(36)
        W.label(f.announcements,"Live only · No login replay",11,20,-392,470)
        f.loot=CreateFrame("Frame",nil,f); f.loot:SetAllPoints()
        f.enabled=G.SettingsCheckbox(f.loot,"Enable guild loot feed",-120,function()
            if G.SetGuildLootEnabled(not G.GuildLootEnabled()) then G.SettingsSaved(); f.refresh() end
        end)
        f.enabledNote=W.label(f.loot,"",11,20,-155,470)
        W.label(f.loot,"Show loot starting at",14,20,-191,470)
        f.choices={}
        for i,option in ipairs({{false,"Rare and above",0.35,0.65,1},{true,"Uncommon and above",0.35,0.85,0.45}}) do
            local enabled=option[1]
            local b=W.button(f.loot,option[2],231,20+(i-1)*239,-222,function()
                if G.SetGreenCapture(enabled) then G.SettingsSaved(); f.refresh() end
            end)
            b:SetHeight(42); b.text:SetTextColor(option[3],option[4],option[5]); f.choices[i]=b
        end
        f.explanation=W.label(f.loot,"",12,20,-280,470)
        W.label(f.loot,"Up to 7 days of history. Members need the update for this switch.",11,20,-322,470)
        f.access=CreateFrame("Frame",nil,f); f.access:SetAllPoints()
        f.accessKind="loot"
        f.lootAccess=W.button(f.access,"Manage loot",231,20,-120,function() f.accessKind="loot"; f.refresh() end)
        f.announcementAccess=W.button(f.access,"Send announcements",231,259,-120,function() f.accessKind="announcements"; f.refresh() end)
        W.label(f.access,"Checked ranks have access. The guild master always does.",11,20,-158,470)
        f.ranks={}
        for i=2,10 do
            local rank=i
            local b=W.button(f.access,"",231,20+((i-2)%2)*239,-187-math.floor((i-2)/2)*40,function()
                if not G.IsGuildLeader(G.self) then return end
                if f.accessKind=="announcements" then
                    local ranks=G.Copy(G.AnnouncementRanks()); ranks[rank]=not ranks[rank] or nil
                    if G.SetAnnouncementPolicy(G.AnnouncementsEnabled(),ranks) then G.SettingsSaved() end; f.refresh(); return
                end
                -- Freeze the initial announcement grants before editing loot access.
                if not G.store.announcementRanks then G.SetAnnouncementPolicy(G.AnnouncementsEnabled(),G.AnnouncementRanks()) end
                G.store.officerRanks=G.store.officerRanks or {}
                G.store.officerRanks[rank]=not G.store.officerRanks[rank] or nil
                G.SettingsSaved()
                for name,info in pairs(G.peerInfo) do if G.PeerCompatible(name) then G.SendLootPolicy(name) end end
                f.refresh()
            end)
            f.ranks[i]=b; G.SettingsQuietButton(b,false); b:SetHeight(34)
            b.text:ClearAllPoints(); b.text:SetPoint("LEFT",36,0); b.text:SetWidth(183); b.text:SetJustifyH("LEFT")
            local box=W.panel(b,18,18,10,-8)
            b.check=box:CreateTexture(nil,"OVERLAY"); b.check:SetAllPoints(); b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        end
        f.accessNote=W.label(f.access,"Only the guild master can change rank access.",11,20,-400,470)
        f.refresh=function()
            if not G.ready then f.promotions.refresh(); return end
            if not G.HasOfficerTools(G.self) then f:Hide(); return end
            local leader=G.IsGuildLeader(G.self)
            if not leader and f.section=="access" then f.section="loot" end
            if not G.IsOfficer(G.self) and f.section=="loot" then f.section=G.IsAnnouncer(G.self) and "announcements" or "promotions" end
            if f.section=="promotions" and not G.CanBatchPromote() then G.CancelPromotions(); f.section="announcements" end
            local access=f.section=="access"
            local announcements=f.section=="announcements"
            local promotions=f.section=="promotions"
            f:ClearAllPoints(); f:SetPoint("TOPLEFT",f.embedded and 250 or 285,f.embedded and -80 or promotions and -80 or -110)
            f:SetHeight(promotions and 510 or access and 442 or announcements and 430 or 360)
            f.promotions:SetShown(promotions); f.promotionTab:SetShown(G.CanBatchPromote()); f.promotionTab:SetSelected(promotions)
            f.promotions.refresh()
            f.lootTab:SetShown(G.IsOfficer(G.self))
            f.accessTab:SetShown(leader); f.loot:SetShown(not access and not announcements and not promotions); f.access:SetShown(access)
            f.announcements:SetShown(announcements)
            f.lootTab:SetSelected(not access and not announcements and not promotions); f.accessTab:SetSelected(access); f.announcementTab:SetSelected(announcements)
            f.subtitle:SetText(promotions and "Preview first. One member per click. No automatic promotions." or announcements and "Guild leader and authorized officers only." or "Changes save automatically for the guild.")
            local announcementEnabled=G.AnnouncementsEnabled()
            f.announcementEnabled.text:SetText("Enable guild announcements")
            f.announcementEnabled:SetSelected(announcementEnabled); f.announcementEnabled:SetEnabled(leader,"Only the guild master can change this switch.")
            f.sendAnnouncement:SetEnabled(announcementEnabled and G.IsAnnouncer(G.self),not announcementEnabled and "Guild announcements are turned off." or "Your rank cannot send announcements.")
            f.previewAnnouncement:SetEnabled(G.IsAnnouncer(G.self),"Your rank cannot send announcements.")
            f.announcementSound.text:SetText("Play a warning sound")
            f.announcementSound:SetSelected(G.db.settings.announcementSound~=false)
            f.lootAccess:SetSelected(f.accessKind=="loot"); f.announcementAccess:SetSelected(f.accessKind=="announcements")
            local greens=G.GreenCaptureEnabled()
            local enabled=G.GuildLootEnabled()
            f.enabled.text:SetText("Enable guild loot feed")
            f.enabled:SetEnabled(leader,"Only the guild master can change this switch."); f.enabled:SetSelected(enabled)
            f.enabledNote:SetText("Only the guild master can turn this on or off for everyone.")
            for _,b in ipairs(f.choices) do b:SetEnabled(enabled,"Enable the guild loot feed first.") end
            f.choices[1]:SetSelected(not greens); f.choices[2]:SetSelected(greens)
            f.explanation:SetText(not enabled and "Hidden for everyone. Loot capture and sharing are stopped." or greens and "Includes green, blue, purple and higher-quality items." or "Includes blue, purple and higher-quality items.")
            local names={}; for _,m in pairs(G.members) do if m.rankOrder then names[m.rankOrder]=m.rank end end
            local position=0
            for rank=2,10 do
                local b=f.ranks[rank]
                local name=G.Safe(GuildControlGetRankName,rank) or names[rank]
                local present=type(name)=="string" and name~=""
                b:SetShown(leader and present)
                if present then
                    b:ClearAllPoints(); b:SetPoint("TOPLEFT",20+(position%2)*239,-187-math.floor(position/2)*40); position=position+1
                    local grants=f.accessKind=="announcements" and G.AnnouncementRanks() or (G.store.officerRanks or {})
                    b.text:SetText(name); b.check:SetShown(grants[rank]==true)
                end
            end
            local noteY=187+math.ceil(position/2)*40+14
            f.accessNote:ClearAllPoints(); f.accessNote:SetPoint("TOPLEFT",20,-noteY)
            if access then f:SetHeight(noteY+40) end
            if f.embedded then
                f:SetBackdropColor(0.035,0.045,0.060,0); f:SetBackdropBorderColor(0,0,0,0)
                f.title:SetText(access and "Guild management" or "Officer tools"); f.title:SetTextColor(0.88,0.73,0.43)
                f.inviteTab:SetShown(access)
                f.accessTab:SetShown(access and leader)
                f.lootTab:SetShown(not access and G.IsOfficer(G.self))
                f.announcementTab:SetShown(not access and G.IsAnnouncer(G.self))
                f.promotionTab:SetShown(not access and G.CanBatchPromote())
                if access then
                    f.accessTab:ClearAllPoints(); f.accessTab:SetPoint("TOPLEFT",180,-80); f.accessTab:SetWidth(150); f.accessTab.text:SetText("Permissions")
                else
                    local x=20
                    for _,tab in ipairs({f.lootTab,f.announcementTab,f.promotionTab}) do
                        if tab:IsShown() then tab:ClearAllPoints(); tab:SetPoint("TOPLEFT",x,-80); tab:SetWidth(150); tab.text:SetWidth(138); x=x+160 end
                    end
                end
            end
        end
        UISpecialFrames[#UISpecialFrames+1]="GuildLedgerOfficerSettings"
    end
    if U.settings and not host then U.settings:Hide() end
    f.section="loot"; f:Show(); f.refresh()
    return f
end
function G.ShowOfficerSettings()
    if not G.HasOfficerTools(G.self) then return end
    if G.OpenSettingsPage then G.OpenSettingsPage("officer") else G.BuildOfficerSettings() end
end
