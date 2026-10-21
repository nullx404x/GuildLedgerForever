local _,G=...
function G.Link(raw)
    if type(raw)~="string" then return nil end
    local link=raw:match("|H(item:[^|]+)|h") or raw:match("|H(spell:%d+)|h") or raw
    if G.ValidLink(link) then return link end
end
local function profile()
    local old=G.Get("profile",G.self)
    local d=old and G.Copy(old.data) or {roles={},trees={},talents={},professions={},talentStamp=0,skillStamp=0}
    d.roles=G.db.settings.roles or {}
    return d
end
function G.ScanTalents()
    local api=C_Traits
    if not api or not C_SpecializationInfo then G.errors.talents="Trait APIs unavailable"; return end
    local group=G.Safe(C_SpecializationInfo.GetActiveSpecGroup)
    local config=group and G.Safe(C_SpecializationInfo.GetCombatConfigIDForSpecGroup,group)
    local info=config and G.Safe(api.GetConfigInfo,config)
    if not info or not info.treeIDs then G.errors.talents="Waiting for talent configuration"; return end
    if G.Safe(api.ConfigHasStagedChanges,config)~=false then G.errors.talents="Waiting for committed talents"; return end
    local trees,talents={},{}
    for _,treeID in ipairs(info.treeIDs) do
        local headers=G.Safe(api.GetGroupDisplayInfoByTreeID,treeID)
        local nodes=G.Safe(api.GetTreeNodes,treeID)
        if not nodes or not headers then return end
        local groupIDs={}; for _,header in ipairs(headers) do groupIDs[#groupIDs+1]=header.groupID end
        local currencies=G.Safe(api.GetGroupCurrencyInfo,config,groupIDs)
        if not currencies then return end
        local points={}
        for _,currency in ipairs(currencies) do
            local first=currency.currencyInfos and currency.currencyInfos[1]
            if first then points[currency.traitNodeGroupID]=first.spent end
        end
        for _,id in ipairs(nodes) do
            local node=G.Safe(api.GetNodeInfo,config,id)
            if not node then return end
            if node.activeEntry and (node.activeEntry.rank or 0)>0 then
                local entry=G.Safe(api.GetEntryInfo,config,node.activeEntry.entryID)
                local definition=entry and G.Safe(api.GetDefinitionInfo,entry.definitionID)
                if not definition then return end
                if definition.spellID then talents[#talents+1]={spell=definition.spellID,rank=node.activeEntry.rank} end
            end
        end
        table.sort(headers,function(a,b) return a.orderIndex<b.orderIndex end)
        for _,h in ipairs(headers) do trees[#trees+1]={name=h.displayName,points=points[h.groupID] or 0} end
    end
    local d=profile(); d.trees=trees; d.talents=talents; d.talentStamp=G.now()
    G.Publish("profile",d); G.errors.talents=nil
end
function G.ScanGear(attempt)
    if not GetInventoryItemID or not GetInventoryItemLink then G.errors.gear="Inventory API unavailable"; return end
    local slots,loading={},false
    for slot=1,19 do
        local okID,id=pcall(GetInventoryItemID,"player",slot)
        local okLink,raw=pcall(GetInventoryItemLink,"player",slot)
        if not okID or not okLink then G.errors.gear="Equipment scan failed; previous snapshot retained"; return end
        local link=G.Link(raw)
        local texture=G.Safe(GetInventoryItemTexture,"player",slot)
        local state=link and "ready" or ((id or texture) and "loading" or "empty")
        slots[#slots+1]={slot=slot,state=state,id=id,link=link}
        if state=="loading" then loading=true end
        if state=="loading" then G.RequestItemData(id) end
    end
    G.errors.gear=nil
    G.Publish("gear",slots)
    attempt=attempt or 0
    if loading and attempt<8 then G.After("gear",2,function() G.ScanGear(attempt+1) end) end
end
function G.ScanSkills()
    if not GetProfessions or not GetProfessionInfo then G.errors.professions="Profession list API unavailable"; return end
    local ids={GetProfessions()}; local list={}
    for i=1,6 do
        local index=ids[i]
        if index then
            local name,_,rank,max,_,_,id=G.Safe(GetProfessionInfo,index)
            if not name or not id or not rank or not max then return end
            list[#list+1]={id=id,name=name,rank=rank,max=max}
        end
    end
    table.sort(list,function(a,b) return a.id<b.id end)
    local signature=G.Encode(list)
    if G.skillCandidate~=signature then G.skillCandidate=signature; G.After("skills-confirm",2,G.ScanSkills); return end
    local d=profile(); d.professions=list; d.skillStamp=G.now()
    G.Publish("profile",d)
    local known={}; for _,p in ipairs(list) do known[p.id]=true end
    local obsolete={}
    for _,r in pairs(G.store and G.store.records or {}) do
        if r.owner==G.self and r.kind=="profession" and not r.deleted and not known[r.data.id] then obsolete[#obsolete+1]=r.data.id end
    end
    for _,id in ipairs(obsolete) do G.Publish("profession",{},tostring(id),true) end
end
function G.ScanRecipes()
    local api=C_TradeSkillUI
    if not api or not api.GetAllRecipeIDs then G.errors.recipes="Complete recipe API unavailable"; return end
    if G.Safe(api.IsTradeSkillReady)~=true then return end
    -- Do not scan linked guild/other characters' books or NPC crafting as the player's own.
    for _,fn in ipairs({"IsTradeSkillLinked","IsTradeSkillGuild","IsTradeSkillGuildMember","IsNPCCrafting"}) do
        if not api[fn] or G.Safe(api[fn])~=false then return end
    end
    local p=G.Safe(api.GetBaseProfessionInfo)
    local ids=G.Safe(api.GetAllRecipeIDs)
    if not p or not p.professionID or not ids or #ids==0 then return end
    local own=profile(); local found
    for _,v in ipairs(own.professions) do if v.id==p.professionID then found=v end end
    if not found then G.ScanSkills(); return end
    -- Scan incrementally to avoid a long UI stall; abort if the open profession changes.
    G.recipeGeneration=(G.recipeGeneration or 0)+1
    local generation=G.recipeGeneration
    local d={id=found.id,name=found.name,rank=found.rank,max=found.max,recipes={}}
    local index=1
    local function step()
        if generation~=G.recipeGeneration or not G.ready then return end
        for _,fn in ipairs({"IsTradeSkillLinked","IsTradeSkillGuild","IsTradeSkillGuildMember","IsNPCCrafting"}) do
            if G.Safe(api[fn])~=false then return end
        end
        local current=G.Safe(api.GetBaseProfessionInfo)
        if not current or current.professionID~=d.id or G.Safe(api.IsTradeSkillReady)~=true then return end
        for _=1,20 do
            local id=ids[index]; if not id then break end
            index=index+1
            local r=G.Safe(api.GetRecipeInfo,id)
            if not r or type(r.learned)~="boolean" then G.errors.recipes="Recipe data still loading; reopen profession to retry"; return end
            if r.learned then
                local s=G.Safe(api.GetRecipeSchematic,id,false)
                if not s then return end
                local materials={}
                for _,slot in ipairs(s.reagentSlotSchematics or {}) do
                    if slot.required then
                        -- Static recipe requirements only. Never query bag/bank counts or craftable quantities.
                        -- Alternatives are not claimed as all required.
                        if slot.reagents and #slot.reagents==1 and slot.reagents[1].itemID then
                            materials[#materials+1]={id=slot.reagents[1].itemID,quantity=slot.quantityRequired or 1}
                        end
                    end
                end
                local output=s.outputItemID and ("item:"..s.outputItemID) or ("spell:"..id)
                d.recipes[#d.recipes+1]={id=id,name=r.name or ("Recipe "..id),link=output,materials=materials}
                if #d.recipes>600 then G.errors.recipes="Recipe book exceeds 600-recipe safety limit; previous cache retained"; return end
            end
        end
        if index<=#ids then G.After("recipe-step",0.05,step)
        else
            table.sort(d.recipes,function(a,b) return a.id<b.id end)
            local ok=pcall(function() for _,recipe in ipairs(d.recipes) do assert(G.ValidDefinition(recipe)); G.Encode(recipe) end end)
            if ok then G.Publish("profession",d,tostring(d.id)); G.errors.recipes=nil
            else G.errors.recipes="Recipe snapshot exceeds size limit; previous cache retained" end
        end
    end
    step()
end
function G.ScanAll()
    if not G.ready then return end
    G.ScanTalents(); G.ScanGear(); G.ScanSkills()
end
-- Match Blizzard's localized self-loot messages; do not assume English or parse another recipient.
local function formatPattern(format)
    if not format then return nil end
    local out,i={},1
    while i<=#format do
        local c=format:sub(i,i)
        if c=="%" then
            local token=format:sub(i):match("^%%[12]%$[sd]") or format:sub(i):match("^%%[sd]")
            if token then out[#out+1]=token:sub(-1)=="d" and "(%d+)" or "(.+)"; i=i+#token
            else out[#out+1]="%%"; i=i+1 end
        else out[#out+1]=c:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1"); i=i+1 end
    end
    return "^"..table.concat(out).."$"
end
G.FormatPattern=formatPattern
G.lootSeen={}; G.pendingLoot={}
function G.CaptureLoot(message,lineID)
    if not G.ready then return end
    local raw,quantity
    for _,name in ipairs({"LOOT_ITEM_SELF_MULTIPLE","LOOT_ITEM_SELF","LOOT_ITEM_PUSHED_SELF_MULTIPLE","LOOT_ITEM_PUSHED_SELF"}) do
        local pat=formatPattern(_G[name])
        if pat then
            local a,b=message:match(pat)
            if a then raw=message:match("(|Hitem:[^|]+|h.-|h)"); quantity=tonumber(b) or tonumber(a) or 1; break end
        end
    end
    local link=G.Link(raw); if not link then return end
    local key=lineID and lineID~=0 and tostring(lineID) or message
    local seen=G.lootSeen[key]
    if seen and G.clock()-seen<(lineID and lineID~=0 and 300 or 2) then return end
    G.lootSeen[key]=G.clock()
    for k,t in pairs(G.lootSeen) do if G.clock()-t>300 then G.lootSeen[k]=nil end end
    if G.Count(G.lootSeen)>1000 then G.lootSeen={[key]=G.clock()} end
    if #G.pendingLoot>=50 then return end
    G.db.serial=G.db.serial+1
    G.pendingLoot[#G.pendingLoot+1]={link=link,quantity=quantity,stamp=G.now(),id=tostring(G.now()).."-"..tostring(G.db.serial),attempt=0,scope=G.scope}
    G.ResolveLoot()
end
function G.ResolveLoot()
    local pending={}
    for _,v in ipairs(G.pendingLoot) do
        if v.scope==G.scope then
            local _,_,quality=G.Safe(C_Item and C_Item.GetItemInfo,v.link)
            if quality then
                if quality==2 and G.GreenCaptureEnabled() or quality and quality>=3 then
                    local kind="loot"
                    local r={id=kind..":"..G.self..":"..v.id,kind=kind,owner=G.self,stamp=v.stamp,rev=v.stamp*1000,data={link=v.link,quantity=v.quantity,source="",quality=quality},deleted=false}
                    if G.Accept(r,true) then G.AnnounceSoon() end
                end
            elseif v.attempt<15 then
                v.attempt=v.attempt+1; pending[#pending+1]=v
                G.RequestItemData(G.ItemID(v.link))
            else G.errors.loot="An observed item could not be resolved; it was not recorded" end
        end
    end
    G.pendingLoot=pending
    if #pending>0 then G.After("loot-retry",2,G.ResolveLoot) end
end
