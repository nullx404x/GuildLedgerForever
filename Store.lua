local _, G = ...
local function str(v,n) return type(v)=="string" and #v<=n and not v:find("|",1,true) and not v:find("[%z\1-\8\11\12\14-\31]") end
local function num(v,max) return type(v)=="number" and v>=0 and v<=max and v==math.floor(v) end
local function array(v,max,check)
    if type(v)~="table" or #v>max then return false end
    local n=0
    for k,x in pairs(v) do n=n+1; if not num(k,max) or k<1 or k>#v or not check(x) then return false end end
    return n==#v
end
local function fields(v, allowed)
    if type(v)~="table" then return false end
    for k in pairs(v) do if not allowed[k] then return false end end
    return true
end
local function link(v) return str(v,600) and (v:match("^item:%d+[%d:%-]*$") or v:match("^spell:%d+$")) end
G.ValidLink=link
function G.Validate(r)
    if not fields(r,{id=1,owner=1,kind=1,rev=1,stamp=1,data=1,deleted=1}) or not str(r.id,180) or not str(r.owner,100)
        or not num(r.rev,1e14) or not num(r.stamp,G.now()+300) or type(r.deleted)~="boolean" then return false end
    if r.kind~="profile" and r.kind~="gear" and r.kind~="profession" and r.kind~="loot" then return false end
    if r.kind=="profession" then
        if not r.id:match("^profession:"..r.owner:gsub("([^%w])","%%%1")..":%d+$") then return false end
    elseif r.kind=="loot" then
        if r.id:sub(1,#r.kind+#r.owner+2)~=r.kind..":"..r.owner..":" then return false end
    elseif r.id~=r.kind..":"..r.owner then return false end
    if r.deleted then return r.kind=="profession" and type(r.data)=="table" and next(r.data)==nil end
    local d=r.data
    if r.kind=="profile" then
        return fields(d,{roles=1,trees=1,talents=1,professions=1,talentStamp=1,skillStamp=1})
            and array(d.roles,3,function(x) return x=="Tank" or x=="Healer" or x=="DPS" end)
            and num(d.talentStamp, G.now()+300) and num(d.skillStamp,G.now()+300)
            and array(d.trees,6,function(x) return fields(x,{name=1,points=1}) and str(x.name,100) and num(x.points,200) end)
            and array(d.talents,300,function(x) return fields(x,{spell=1,rank=1}) and num(x.spell,1e8) and num(x.rank,100) end)
            and array(d.professions,8,function(x) return fields(x,{id=1,name=1,rank=1,max=1}) and num(x.id,1e7) and str(x.name,100) and num(x.rank,10000) and num(x.max,10000) end)
    elseif r.kind=="gear" then
        return array(d,19,function(x) return fields(x,{slot=1,state=1,link=1,id=1}) and num(x.slot,19) and x.slot>=1
            and (x.state=="empty" or x.state=="loading" or x.state=="ready") and (not x.link or link(x.link)) and (not x.id or num(x.id,1e8))
            and (x.state~="ready" or x.link~=nil) end) and #d==19 and (function() local seen={}; for _,v in ipairs(d) do if seen[v.slot] then return false end; seen[v.slot]=true end; return true end)()
    elseif r.kind=="profession" then
        return fields(d,{id=1,name=1,rank=1,max=1,recipes=1}) and num(d.id,1e7) and r.id=="profession:"..r.owner..":"..d.id
            and str(d.name,100) and num(d.rank,10000) and num(d.max,10000)
            and array(d.recipes,600,function(x) if type(x)=="string" then return G.recipePool[x]~=nil end; return fields(x,{id=1,name=1,link=1,materials=1}) and num(x.id,1e8) and str(x.name,180) and link(x.link)
                and array(x.materials,20,function(m) return fields(m,{id=1,quantity=1}) and num(m.id,1e8) and num(m.quantity,10000) end) end)
    end
    return fields(d,{link=1,quantity=1,source=1,quality=1}) and link(d.link) and d.link:match("^item:") and num(d.quantity,10000) and d.quantity>0 and str(d.source,100) and num(d.quality,5) and d.quality>=2
end
function G.InitStore()
    GuildLedgerDB = type(GuildLedgerDB)=="table" and GuildLedgerDB or {}
    G.db=GuildLedgerDB
    -- Discard pre-release caches once, retaining only user/guild configuration.
    if G.db.schema~=3 then
        local old=type(G.db.guild)=='table' and G.db.guild or {}
        local clean={records={},definitions={},blocked={},lootFloor=0}
        for _,key in ipairs({'discordInvite','inviteRevision','officerRanks','captureGreens','policyRevision'}) do clean[key]=old[key] end
        G.db.guild=clean; G.db.schema=3; G.scope=nil; G.store=nil
    end
    G.db.settings=type(G.db.settings)=='table' and G.db.settings or {roles={}}
    if G.db.settings.showGuildLocations==nil then G.db.settings.showGuildLocations=true end
    if G.db.settings.shareLocation==nil then G.db.settings.shareLocation=true end
    G.db.settings.rarity=nil; G.db.settings.watch=nil; G.db.rareLootDefault=nil
    G.db.serial=G.db.serial or 0
    G.self=G.UnitName("player")
end
-- Only Discord invite URLs are accepted; never accept arbitrary links or UI escapes.
function G.NormalizeInvite(value)
    if type(value)~="string" or #value>120 then return nil end
    value=value:match("^%s*(.-)%s*$")
    if value=="" then return "" end
    local code=value:match("^https://discord%.gg/([%w%-_]+)$")
        or value:match("^https://discord%.com/invite/([%w%-_]+)$")
    if not code or #code>64 then return nil end
    return "https://discord.gg/"..code
end
function G.DiscordInvite()
    return G.store and G.NormalizeInvite(G.store.discordInvite) or ""
end
function G.SendGuildInvite(target)
    if not G.IsGuildLeader(G.self) or not G.store.inviteRevision then return end
    G.Send({type="guildInvite",scope=G.scope,invite=G.DiscordInvite(),revision=G.store.inviteRevision},target)
end
function G.SetGuildInvite(value)
    if not G.IsGuildLeader(G.self) then return false,"Only the guild master can change the invite." end
    local invite=G.NormalizeInvite(value)
    if not invite then return false,"Use https://discord.gg/code or leave blank to remove it." end
    G.store.discordInvite=invite
    G.store.inviteRevision=math.max(G.now()*1000,(G.store.inviteRevision or 0)+1)
    for name,info in pairs(G.peerInfo) do if G.PeerCompatible(name) then G.SendGuildInvite(name) end end
    G.Refresh()
    return true
end
function G.ResetSync()
    G.Changed("membership"); G.Changed("roster"); G.scannedScope=nil
    if G.ResetTransport then G.ResetTransport() end
    G.recipePool={}; G.history={}; G.historyBytes=0
    G.bookTemplates={}; G.bookTemplateBytes=0; G.bookPeers={}; G.gearDemand=nil
    G.pendingRecords={}; G.definitionRequests={}; G.sources={}; G.completedDigests={}
    G.changedRecords={}; G.changeBase=nil; G.changeOverflow=nil
    G.tokenCache=setmetatable({},{__mode="k"})
    if G.ClearLocations then G.ClearLocations() end
    G.queue,G.partials,G.peers,G.outstanding={}, {}, {}, {}; G.peerInfo={}
    G.members={}; G.ready=false; G.candidate=nil; G.candidateAt=nil; G.manifestJobs={}; G.crafterIndex=nil; G.dataRevision=(G.dataRevision or 0)+1; G.skillCandidate=nil; G.recipeGeneration=(G.recipeGeneration or 0)+1; G.lastContact=nil; G.offerTimes={}; G.rates={}
end
function G.Scope(scope)
    if G.scope==scope and G.db.scope==scope and (scope==nil or G.store) then return end
    G.ResetSync(); G.scope=scope
    if G.db.scope~=scope then G.db.guild=nil; G.db.scope=scope end
    if scope then
        G.db.guild=G.db.guild or {records={},blocked={},lootFloor=0}
        G.store=G.db.guild
        G.store.records=type(G.store.records)=="table" and G.store.records or {}
        G.store.blocked=type(G.store.blocked)=="table" and G.store.blocked or {}
        G.RestoreCatalog()
        G.Prune()
    else G.store=nil end
end
function G.Prune()
    if not G.store then return end
    -- One history cap and cutoff for all qualifying loot.
    local floor=math.max(G.store.lootFloor or 0,G.now()-7*86400)
    local loot={}; local removed=false
    for id,r in pairs(G.store.records) do if r.kind=="loot" then
        if r.stamp<=floor then G.store.records[id]=nil; removed=true else loot[#loot+1]=r end
    end end
    table.sort(loot,function(a,b) if a.stamp==b.stamp then return a.id<b.id end return a.stamp>b.stamp end)
    if #loot>500 then floor=math.max(floor,loot[501].stamp) end
    G.store.lootFloor=floor
    for id,r in pairs(G.store.records) do
        if (r.kind=="loot") and r.stamp<=floor then G.store.records[id]=nil; removed=true end
    end
    if removed then G.Changed("loot") end
end
-- Accepted records are immutable snapshots. Weak keys release replaced records.
G.tokenCache=setmetatable({},{__mode="k"})
function G.Token(r)
    local cached=G.tokenCache[r]
    if cached and cached.rev==r.rev then return cached.token end
    local token=tostring(r.rev).."/"..G.Hash(G.Encode(G.PackRecord(r)))
    G.tokenCache[r]={rev=r.rev,token=token}
    return token
end
function G.Accept(r, localWrite)
    if not G.store or not G.Validate(r) then return false end
    if r.kind~="loot" then
        if not G.ready or not G.members[r.owner] then return false end
        if r.stamp<=math.max(G.store.blocked[r.owner] or 0,G.store.memberFloor or 0) then return false end
    elseif r.stamp<=math.max(G.store.lootFloor or 0,G.now()-7*86400) then return false end
    local old=G.store.records[r.id]
    if old and (old.rev>r.rev or (old.rev==r.rev and G.Encode(G.PackRecord(old))>=G.Encode(G.PackRecord(r)))) then return false end
    if not old and G.Count(G.store.records)>=12000 then G.errors.storage="Record capacity reached; new records deferred"; return false end
    if not G.InternRecord(r) then return false end
    G.RememberBase(old)
    if localWrite and G.TrackChange then G.TrackChange(r) end
    G.store.records[r.id]=r
    G.Changed(r.kind)
    if r.kind=="loot" then G.Prune() end
    G.Refresh()
    return true
end
function G.Publish(kind, data, suffix, deleted)
    if not G.ready or not G.store then return end
    local id=kind..":"..G.self..(suffix and ":"..suffix or "")
    local old=G.store.records[id]
    local ignore=kind=="profile" and {talentStamp=true,skillStamp=true} or nil
    if old and old.deleted==(deleted or false) and G.now()-old.stamp<900 and G.SameSnapshotData(kind,old.data,data,ignore) then return end
    local rev=math.max(G.now()*1000,(old and old.rev or 0)+1)
    local r={id=id,kind=kind,owner=G.self,rev=rev,stamp=G.now(),data=data,deleted=deleted or false}
    if G.Accept(r,true) then G.AnnounceSoon() end
end
function G.Get(kind,owner,suffix)
    local r=G.store and G.store.records[kind..":"..owner..(suffix and ":"..suffix or "")]
    return r and not r.deleted and r or nil
end
function G.RequestRoster()
    if G.clock()-(G.lastRosterRequest or -30)<30 then return end
    G.lastRosterRequest=G.clock()
    G.Safe(C_GuildInfo and C_GuildInfo.GuildRoster)
end
function G.RosterWait(reason)
    G.ready=false; G.candidate=nil; G.candidateAt=nil
    G.errors.roster=reason
    G.Refresh()
    if not G.timers["roster-retry"] then
        G.After("roster-retry",5,function() G.RequestRoster(); G.UpdateRoster() end)
    end
end
function G.UpdateRoster()
    if G.worldLoading then G.ready=false; return end
    if not IsInGuild() then
        -- Guild membership can be unavailable briefly during a loading screen.
        -- Pause communication immediately, but require stable absence before
        -- discarding this guild's records and officer settings.
        G.ready=false
        G.guildAbsentSince=G.guildAbsentSince or G.clock()
        if G.clock()-G.guildAbsentSince<10 then
            G.After("guild-absence",2,G.UpdateRoster); G.Refresh(); return
        end
        G.Scope(nil); G.errors.roster=nil; G.Refresh(); return
    end
    G.guildAbsentSince=nil

    local club=G.Safe(C_Club and C_Club.GetGuildClubId)
    local info=club and G.Safe(C_Club.GetClubInfo,club)
    if not info then G.RosterWait("Waiting for guild club information"); return end
    local scope=G.GuildScope(club)
    if not scope then G.RosterWait("Waiting for client region"); return end
    G.Scope(scope)
    G.guildName=info.name; G.club=club
    local ids=G.Safe(C_Club.GetClubMembers,club)
    -- ClubInfo.memberCount is optional in the client documentation.
    local total=info.memberCount or G.Safe(GetNumGuildMembers)
    if not ids or not total or #ids~=total or #ids==0 then
        G.RosterWait("Guild roster received "..tostring(ids and #ids or 0).." / "..tostring(total or "unknown").." members"); return
    end
    local roster,signature={},{}
    for _,id in ipairs(ids) do
        local m=G.Safe(C_Club.GetMemberInfo,club,id)
        if not m or not m.name or m.name=="" then G.RosterWait("Waiting for a guild member's name"); return end
        local name=G.Name(m.name)
        if not name or roster[name] then G.RosterWait("Guild roster has unresolved or duplicate names"); return end
        local p=Enum.ClubMemberPresence
        roster[name]={name=name,guid=m.guid,class=m.classID,level=m.level or 0,rank=m.guildRank or "",rankOrder=m.guildRankOrder,online=m.presence==p.Online or m.presence==p.Away or m.presence==p.Busy}
        signature[#signature+1]=name..":"..(m.guid or tostring(id))..":"..tostring(m.guildRankOrder)
    end
    if not roster[G.self] then G.RosterWait("Your character is not in the received roster: "..tostring(G.self)); return end
    table.sort(signature); signature=table.concat(signature,";")
    if G.candidate~=signature then
        G.candidate=signature; G.candidateAt=G.clock(); G.ready=false
        G.After("confirm-roster",2,G.UpdateRoster); return
    end
    if G.clock()-(G.candidateAt or 0)<2 then
        G.ready=false; G.After("confirm-roster",2-(G.clock()-(G.candidateAt or 0)),G.UpdateRoster); return
    end
    local membershipChanged=not G.Equal(G.Keys(G.members),G.Keys(roster))
    local rosterChanged=not G.Equal(G.members,roster)
    G.members=roster; G.ready=true; G.errors.roster=nil
    if G.timers["roster-retry"] then G.timers["roster-retry"]:Cancel(); G.timers["roster-retry"]=nil end
    for id,r in pairs(G.store.records) do
        if r.kind~="loot" and not roster[r.owner] then
            G.store.blocked[r.owner]=math.max(G.store.blocked[r.owner] or 0,G.now())
            G.store.records[id]=nil
        end
    end
    -- Compact exceptionally large removal sets into a conservative global snapshot floor.
    if G.Count(G.store.blocked)>10000 then G.store.memberFloor=G.now(); G.store.blocked={} end
    if membershipChanged then G.Changed("membership") end
    if rosterChanged then G.Changed("roster") end
    G.motd=G.Safe(C_GuildInfo.GetMOTD) or info.broadcast or ""
    G.guildInfo=G.Safe(C_GuildInfo.GetInfoText) or info.description or ""
    if G.scannedScope~=G.scope then G.After("scan",1,function()
        if G.ready then G.ScanAll(); G.scannedScope=G.scope end
    end) end
    G.Refresh(); G.AnnounceSoon()
end

-- Policy messages are accepted only from current authorized guild members.
function G.IsGuildLeader(name)
    return G.ready and G.members[name] and G.members[name].rankOrder==1
end
function G.IsOfficer(name)
    local m=G.members[name]
    return G.ready and m and (m.rankOrder==1 or (G.store.officerRanks or {})[m.rankOrder]==true) or false
end
function G.GreenCaptureEnabled() return G.store and G.store.captureGreens==true end
function G.SendLootPolicy(target)
    if G.IsGuildLeader(G.self) then G.Send({type="officerAccess",scope=G.scope,ranks=G.store.officerRanks or {}},target) end
    if G.IsOfficer(G.self) then G.Send({type="lootPolicy",scope=G.scope,greens=G.GreenCaptureEnabled(),revision=G.store.policyRevision or 0},target) end
end
function G.SetGreenCapture(value)
    if not G.IsOfficer(G.self) then return false end
    G.store.captureGreens=value==true; G.store.policyRevision=math.max(G.now()*1000,(G.store.policyRevision or 0)+1)
    for name,info in pairs(G.peerInfo) do if G.PeerCompatible(name) then G.SendLootPolicy(name) end end
    G.Refresh(); return true
end
