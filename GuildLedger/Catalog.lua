local _,G=...
G.definitionKeys=setmetatable({},{__mode='k'})
G.recipePool={}
-- Transfer-only recipe templates. Saved records remain self-contained key lists.
G.bookTemplates={}; G.bookTemplateBytes=0; G.bookPeers={}
local function bookKey(keys)
    local s=table.concat(keys,','); return G.Hash(s)..G.Hash(s:reverse())
end
local function validKeys(keys)
    if type(keys)~='table' or #keys>600 then return false end
    local count=0; local last=''
    for i,key in pairs(keys) do
        if type(i)~='number' or i%1~=0 or i<1 or i>#keys or type(key)~='string' or not key:match('^%x+$') or #key~=16 then return false end
        count=count+1
    end
    for _,key in ipairs(keys) do if key<=last then return false end; last=key end
    return count==#keys
end
function G.AddBookTemplate(key,keys)
    if type(key)~='string' or #key~=16 or not validKeys(keys) or bookKey(keys)~=key then return end
    local old=G.bookTemplates[key]
    if old then if not G.Equal(old.keys,keys) then return end; old.at=G.clock(); return old end
    local size=#keys*24+64
    while G.Count(G.bookTemplates)>=128 or G.bookTemplateBytes+size>262144 do
        local oldest,at; for k,t in pairs(G.bookTemplates) do if not at or t.at<at then oldest,at=k,t.at end end
        if not oldest then return end
        G.bookTemplateBytes=G.bookTemplateBytes-G.bookTemplates[oldest].size; G.bookTemplates[oldest]=nil
    end
    local t={keys=G.Copy(keys),at=G.clock(),size=size}; G.bookTemplates[key]=t; G.bookTemplateBytes=G.bookTemplateBytes+size; return t
end
function G.BookTransfer(r,target,force)
    if r.kind~='profession' or r.deleted or #r.data.recipes<8 or not validKeys(r.data.recipes) then return {record=r} end
    local peer=G.bookPeers[target]
    if not peer then
        if G.Count(G.bookPeers)>=8 then return {record=r} end
        peer={bases={},known={},at=G.clock()}; G.bookPeers[target]=peer
    end
    peer.at=G.clock()
    local key=peer.bases[r.data.id]; local template=key and G.bookTemplates[key]
    if not template then
        key=bookKey(r.data.recipes); template=G.AddBookTemplate(key,r.data.recipes)
        if not template then return {record=r} end
        if G.Count(peer.bases)<16 then peer.bases[r.data.id]=key end
    end
    template.at=G.clock()
    local a,b,add,remove={},{},{},{}
    for _,k in ipairs(template.keys) do a[k]=true end
    for _,k in ipairs(r.data.recipes) do b[k]=true; if not a[k] then add[#add+1]=k end end
    for _,k in ipairs(template.keys) do if not b[k] then remove[#remove+1]=k end end
    local p={id=r.id,owner=r.owner,kind=r.kind,rev=r.rev,stamp=r.stamp,deleted=false,
        data={id=r.data.id,name=r.data.name,rank=r.data.rank,max=r.data.max}}
    local entry={book={record=p,template=key,add=add,remove=remove,token=G.Token(r),keys=(force or not peer.known[key]) and template.keys or nil}}
    -- Very different books use a full record rather than a larger patch.
    if #add+#remove>#r.data.recipes then return {record=r} end
    return entry
end
function G.ApplyBook(book)
    if type(book)~='table' or type(book.record)~='table' or type(book.record.id)~='string' or #book.record.id>180 or book.record.kind~='profession' or book.record.deleted~=false or type(book.record.data)~='table' or book.record.data.recipes~=nil then return end
    if type(book.template)~='string' or #book.template~=16 or not validKeys(book.add) or not validKeys(book.remove) then return end
    if book.keys and not G.AddBookTemplate(book.template,book.keys) then return end
    local template=G.bookTemplates[book.template]
    if not template then return nil,'missing' end
    template.at=G.clock()
    local keys={}; for _,key in ipairs(template.keys) do keys[key]=true end
    for _,key in ipairs(book.remove) do if not keys[key] then return end; keys[key]=nil end
    for _,key in ipairs(book.add) do if keys[key] then return end; keys[key]=true end
    local p=G.Copy(book.record); p.data.recipes=G.Keys(keys)
    if #p.data.recipes>600 or tostring(p.rev)..'/'..G.Hash(G.Encode(p))~=book.token then return end
    return p
end
function G.PruneBookTemplates()
    for key,t in pairs(G.bookTemplates) do if G.clock()-t.at>600 then G.bookTemplateBytes=G.bookTemplateBytes-t.size; G.bookTemplates[key]=nil end end
    for name,p in pairs(G.bookPeers) do if not G.members[name] or G.clock()-p.at>600 then G.bookPeers[name]=nil end end
end
function G.DefinitionKey(recipe)
    if type(recipe)=='string' then return recipe end
    local cached=G.definitionKeys[recipe]; if cached then return cached end
    local s=G.Encode(recipe)
    local key=G.Hash(s)..G.Hash(s:reverse()); return key
end
function G.ValidDefinition(recipe)
    if type(recipe)~='table' then return false end
    local owner=G.self or 'Catalog'
    return G.Validate({id='profession:'..owner..':1',owner=owner,kind='profession',rev=0,stamp=0,deleted=false,
        data={id=1,name='',rank=0,max=0,recipes={recipe}}})
end
function G.AddDefinition(key,recipe)
    if type(key)~='string' or #key~=16 or not G.ValidDefinition(recipe) or G.DefinitionKey(recipe)~=key then return false end
    local old=G.recipePool[key]
    if old then return G.Equal(old,recipe) end
    if G.Count(G.recipePool)>=12000 then return false end
    G.recipePool[key]=recipe; G.definitionKeys[recipe]=key; return true
end
-- The scan boundary produces definitions; every stored/wire book holds only keys.
function G.PackRecord(r)
    if r.kind~='profession' or r.deleted or type(r.data.recipes[1])~='table' then return r end
    local d=r.data
    local p={id=r.id,owner=r.owner,kind=r.kind,rev=r.rev,stamp=r.stamp,deleted=false,
        data={id=d.id,name=d.name,rank=d.rank,max=d.max,recipes={}}}
    for i,recipe in ipairs(d.recipes) do p.data.recipes[i]=G.DefinitionKey(recipe) end
    table.sort(p.data.recipes); return p
end
function G.UnpackRecord(p)
    if type(p)~='table' or type(p.data)~='table' then return nil end
    if p.kind~='profession' or p.deleted then return p end
    if type(p.data.recipes)~='table' or #p.data.recipes>600 then return nil end
    local missing=false; local count=0
    for i,key in pairs(p.data.recipes) do
        if type(i)~='number' or i%1~=0 or i<1 or i>#p.data.recipes or type(key)~='string' or #key~=16 then return nil end
        count=count+1; if not G.recipePool[key] then missing=true end
    end
    if count~=#p.data.recipes then return nil end
    if missing then return nil,'missing' end
    return p
end
function G.InternRecord(r)
    if r.kind=='gear' then table.sort(r.data,function(a,b) return a.slot<b.slot end) end
    if r.kind~='profession' or r.deleted then return true end
    local additions,keys={},{}
    for i,recipe in ipairs(r.data.recipes) do
        local key=G.DefinitionKey(recipe); keys[i]=key; local old=G.recipePool[key]
        if type(recipe)=='table' then
            if old and not G.Equal(old,recipe) then return false end
            if not old then additions[key]=recipe end
        elseif not old then return false end
    end
    if G.Count(G.recipePool)+G.Count(additions)>12000 then G.errors.storage='Recipe catalog capacity reached'; return false end
    for key,recipe in pairs(additions) do G.recipePool[key]=recipe; G.definitionKeys[recipe]=key end
    r.data.recipes=keys
    table.sort(r.data.recipes)
    return true
end
function G.Recipes(record)
    local i=0
    return function()
        i=i+1; local key=record.data.recipes[i]
        if key then return i,G.recipePool[key] end
    end
end
function G.PruneDefinitions()
    local used={}
    for _,r in pairs(G.store and G.store.records or {}) do
        if r.kind=='profession' and not r.deleted then for _,key in ipairs(r.data.recipes) do used[key]=true end end
    end
    for _,pending in pairs(G.pendingRecords or {}) do
        local p=pending.record
        if p.kind=='profession' and not p.deleted then for _,key in ipairs(p.data.recipes or {}) do used[key]=true end end
    end
    for key in pairs(G.recipePool) do if not used[key] then G.recipePool[key]=nil end end
end
function G.PrepareSave()
    if not G.store then return end
    G.PruneDefinitions(); G.store.definitions=G.recipePool; G.db.guild=G.store
end
function G.RestoreCatalog()
    local definitions=type(G.store.definitions)=='table' and G.store.definitions or {}
    G.recipePool={}
    for key,recipe in pairs(definitions) do G.AddDefinition(key,recipe) end
    G.store.definitions=G.recipePool
    for id,p in pairs(G.store.records) do
        local r=G.UnpackRecord(p)
        if not r or not G.Validate(r) or not G.InternRecord(r) then G.store.records[id]=nil end
    end
end
-- One recent base per record, bounded by both count and encoded bytes.
G.history={}; G.historyBytes=0
function G.RememberBase(old)
    if not old or (old.kind~='gear' and old.kind~='profession') then return end
    local p=G.PackRecord(old); local size=#G.Encode(p)
    if size>65536 then return end
    local previous=G.history[old.id]
    if previous then G.historyBytes=G.historyBytes-previous.size end
    G.history[old.id]={record=p,token=G.Token(old),at=G.clock(),size=size}; G.historyBytes=G.historyBytes+size
    while G.Count(G.history)>128 or G.historyBytes>524288 do
        local key,at; for id,h in pairs(G.history) do if not at or h.at<at then key,at=id,h.at end end
        G.historyBytes=G.historyBytes-G.history[key].size; G.history[key]=nil
    end
end
function G.MakeTransfer(r,base)
    local p=G.PackRecord(r); local h=G.history[r.id]
    if not base or not h or h.token~=base or r.deleted or h.record.deleted then return {record=p} end
    local d={id=r.id,base=base,token=G.Token(r),rev=r.rev,stamp=r.stamp,kind=r.kind}
    if r.kind=='gear' then
        d.slots={}; for i,v in ipairs(p.data) do if not G.Equal(v,h.record.data[i]) then d.slots[#d.slots+1]=v end end
    elseif r.kind=='profession' then
        d.meta={id=p.data.id,name=p.data.name,rank=p.data.rank,max=p.data.max}; d.add={}; d.remove={}
        local a,b={},{}; for _,key in ipairs(h.record.data.recipes) do a[key]=true end
        for _,key in ipairs(p.data.recipes) do b[key]=true; if not a[key] then d.add[#d.add+1]=key end end
        for key in pairs(a) do if not b[key] then d.remove[#d.remove+1]=key end end
        -- Order is part of the fingerprint: canonicalize books before storing.
    else return {record=p} end
    if #G.Encode(d)>=#G.Encode(p) then return {record=p} end
    return {delta=d}
end
function G.ApplyDelta(d)
    if type(d)~='table' or type(d.id)~='string' then return nil end
    local old=G.store.records[d.id]
    if not old or G.Token(old)~=d.base then return nil,'base' end
    local p=G.Copy(G.PackRecord(old)); p.rev=d.rev; p.stamp=d.stamp
    if d.kind~=p.kind then return nil end
    if d.kind=='gear' and type(d.slots)=='table' and #d.slots<=19 then
        local seen={}; for _,v in ipairs(d.slots) do
            if type(v)~='table' or type(v.slot)~='number' or v.slot%1~=0 or v.slot<1 or v.slot>19 or seen[v.slot] then return nil end
            seen[v.slot]=true; p.data[v.slot]=v
        end
    elseif d.kind=='profession' and type(d.meta)=='table' and type(d.add)=='table' and type(d.remove)=='table' and #d.add<=600 and #d.remove<=600 then
        local keys={}; for _,key in ipairs(p.data.recipes) do keys[key]=true end
        for _,key in ipairs(d.remove) do if type(key)~='string' then return nil end; keys[key]=nil end
        for _,key in ipairs(d.add) do if type(key)~='string' or #key~=16 then return nil end; keys[key]=true end
        p.data=G.Copy(d.meta); p.data.recipes=G.Keys(keys)
    else return nil end
    if tostring(p.rev)..'/'..G.Hash(G.Encode(p))~=d.token then return nil,'base' end
    return p
end


-- Scan order does not change recipe membership.
function G.SameSnapshotData(kind,a,b,ignore)
    if kind~='profession' then return G.Equal(a,b,ignore) end
    if a.id~=b.id or a.name~=b.name or a.rank~=b.rank or a.max~=b.max then return false end
    if type(a.recipes)~='table' or type(b.recipes)~='table' then return G.Equal(a,b) end
    local x,y={},{}
    for i,r in ipairs(a.recipes) do x[i]=G.DefinitionKey(r) end
    for i,r in ipairs(b.recipes) do y[i]=G.DefinitionKey(r) end
    table.sort(x); table.sort(y); return G.Equal(x,y)
end
