local _,G=...
local events=CreateFrame("Frame")
local function register(name) local ok=pcall(events.RegisterEvent,events,name); if not ok then G.errors[name]="Event unavailable: "..name end end
register("ADDON_LOADED")
local function guard(key,fn,...)
    local ok,err=pcall(fn,...)
    if not ok then G.errors[key]=tostring(err); G.Refresh() end
end
function G.InstallTooltips()
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,function(tooltip,data)
            if not G.ready or not data or not data.id then return end
            local names=G.Crafters(data.id)
            if #names>0 then
                local shown={}; for i=1,math.min(5,#names) do shown[#shown+1]=names[i] end
                tooltip:AddLine("Guild crafters: "..table.concat(shown,", ")..(#names>5 and " (+"..(#names-5)..")" or ""),0.88,0.73,0.43,true)
            end
        end)
    end
end
function G.Diagnostics()
    G.Safe(C_AddOns and C_AddOns.UpdateAddOnMemoryUsage or UpdateAddOnMemoryUsage)
    local memory=G.Safe(C_AddOns and C_AddOns.GetAddOnMemoryUsage or GetAddOnMemoryUsage,"GuildLedger")
    if memory then G.Say(string.format("Memory: %.2f MB (includes data waiting for garbage collection).",memory/1024)) end
    local version,build,_,interface=GetBuildInfo()
    G.Say("Client "..tostring(version).." build "..tostring(build).." interface "..tostring(interface).."; target 1.60.1.70450 / 16001.")
    G.Say((G.ready and "Complete roster confirmed" or "Waiting for complete roster").."; records "..G.Count(G.store and G.store.records).."; peers "..G.Count(G.peers).."; queued "..#G.queue..".")
    for key,value in pairs(G.errors) do G.Say(key..": "..value) end
end
local function login()
    G.InitStore(); G.Launcher(); G.InstallTooltips(); G.RegisterSettings()
    G.Safe(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix,G.LOCATION_PREFIX)
    C_Timer.NewTicker(1,function() guard("locations",G.LocationTick) end)
    if not C_ChatInfo or not G.Safe(C_ChatInfo.RegisterAddonMessagePrefix,G.PREFIX) then G.errors.sync="Addon message prefix could not be registered" end
    for _,name in ipairs({"PLAYER_GUILD_UPDATE","GUILD_ROSTER_UPDATE","CLUB_MEMBERS_UPDATED","CLUB_MEMBER_ADDED","CLUB_MEMBER_REMOVED","CLUB_MEMBER_UPDATED","CLUB_MEMBER_PRESENCE_UPDATED","PLAYER_EQUIPMENT_CHANGED","PLAYER_LEAVING_WORLD","PLAYER_ENTERING_WORLD","TRAIT_CONFIG_UPDATED","ACTIVE_PLAYER_SPECIALIZATION_CHANGED","PLAYER_SPECIALIZATION_CHANGED","SKILL_LINES_CHANGED","TRADE_SKILL_SHOW","TRADE_SKILL_DATA_SOURCE_CHANGED","TRADE_SKILL_LIST_UPDATE","TRADE_SKILL_CLOSE","CHAT_MSG_ADDON","CHAT_MSG_LOOT","GET_ITEM_INFO_RECEIVED","UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED","PLAYER_LOGOUT"}) do register(name) end
    G.RequestRoster()
    G.After("roster",1,G.UpdateRoster)
    C_Timer.NewTicker(0.2,function() guard("sync",G.SyncTick) end)
    C_Timer.NewTicker(120,function() guard("roster",G.UpdateRoster); guard("scan",G.ScanAll); G.Prune(); G.PruneDefinitions(); G.AnnounceSoon() end)
    SLASH_GUILDLEDGER1="/gl"; SLASH_GUILDLEDGER2="/guildledger"
    SlashCmdList.GUILDLEDGER=function(msg)
        msg=(msg or ""):lower():match("^%s*(.-)%s*$")
        if msg=="scan" then guard("scan",G.ScanAll); guard("recipes",G.ScanRecipes); G.Say("Scanned available data. Open profession windows to share recipe books.")
        elseif msg=="sync" then G.RequestRoster(); guard("roster",G.UpdateRoster); G.AnnounceSoon(); G.Say("Roster refresh and peer discovery queued. This does not certify complete guild data.")
        elseif msg=="status" then G.Diagnostics()
        elseif msg=="settings" then G.OpenSettings()
        elseif msg=="diagnostics" then G.ShowDiagnostics()
        elseif msg=="resetpos" then G.ResetPosition()
        elseif msg=="help" then G.Say("/gl · /gl scan · /gl sync · /gl status · /gl settings · /gl diagnostics · /gl resetpos")
        else G.Toggle() end
    end
end
local function dispatch(_,event,...)
    if event=="ADDON_LOADED" then
        if ...=="GuildLedger" then register("PLAYER_LOGIN") end
    elseif event=="PLAYER_LOGIN" then login()
    elseif event=="CHAT_MSG_ADDON" then
        if ...==G.LOCATION_PREFIX then G.ReceiveLocation(...) else G.Receive(...) end
    elseif event=="CHAT_MSG_LOOT" then local message=...; local lineID=select(11,...); G.CaptureLoot(message,lineID)
    elseif event=="PLAYER_LOGOUT" then G.SavePreferences(); G.PrepareSave()
    elseif event=="PLAYER_GUILD_UPDATE" or event=="GUILD_ROSTER_UPDATE" or event:match("^CLUB_MEMBER") then
        -- Gate messages immediately until the membership snapshot is refreshed.
        G.ready=false; G.After("roster",0.5,G.UpdateRoster)
    elseif event=="PLAYER_EQUIPMENT_CHANGED" then G.After("gear",0.8,G.ScanGear)
    elseif event=="TRAIT_CONFIG_UPDATED" or event=="ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event=="PLAYER_SPECIALIZATION_CHANGED" then G.After("talents",1,G.ScanTalents)
    elseif event=="PLAYER_LEAVING_WORLD" then G.BroadcastLocation(true); G.worldLoading=true; G.ready=false; G.guildAbsentSince=nil
    elseif event=="PLAYER_ENTERING_WORLD" then G.worldLoading=false; G.guildAbsentSince=nil; G.After("roster",2,G.UpdateRoster)
    elseif event=="SKILL_LINES_CHANGED" then G.After("skills",1,G.ScanSkills)
    elseif event=="TRADE_SKILL_CLOSE" then G.recipeGeneration=(G.recipeGeneration or 0)+1
    elseif event:match("^TRADE_SKILL_") then G.After("recipes",0.8,G.ScanRecipes)
    elseif event=="GET_ITEM_INFO_RECEIVED" then G.ItemDataReceived(...)
    elseif event=="UI_SCALE_CHANGED" or event=="DISPLAY_SIZE_CHANGED" then if G.ScaleUI then G.ScaleUI() end end
end
events:SetScript("OnEvent",function(...) guard("event",dispatch,...) end)
