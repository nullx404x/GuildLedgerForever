local _, G = ...
G.VERSION = "0.4.1"
G.PREFIX = "GLDG3"
G.MAX_WIRE = 122880
G.now = function() return GetServerTime() end
G.clock = function() return GetTime() end
G.members, G.timers, G.errors = {}, {}, {}
function G.Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a,b,c,d,e,f,g,h,i,j,k = pcall(fn, ...)
    if ok then return a,b,c,d,e,f,g,h,i,j,k end
    return nil
end
function G.After(key, delay, fn)
    if G.timers[key] then G.timers[key]:Cancel() end
    G.timers[key] = C_Timer.NewTimer(delay, function()
        G.timers[key] = nil
        local ok, err = pcall(fn)
        if not ok then G.errors[key] = tostring(err); G.Refresh() end
    end)
end
function G.Refresh() if G.UIRefresh then G.UIRefresh() end end
function G.Changed(kind)
    G.dataRevision=(G.dataRevision or 0)+1
    G.revisions=G.revisions or {}
    G.revisions[kind]=(G.revisions[kind] or 0)+1
end
function G.Revision(kind) return G.revisions and G.revisions[kind] or 0 end
function G.Equal(a,b,ignore)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not (ignore and ignore[k]) and not G.Equal(v,b[k]) then return false end end
    for k in pairs(b) do if not (ignore and ignore[k]) and a[k]==nil then return false end end
    return true
end
function G.Copy(value)
    if type(value)~="table" then return value end
    local copy={}; for k,v in pairs(value) do copy[k]=G.Copy(v) end; return copy
end
-- Bound pending metadata requests and avoid render -> request -> event loops.
G.itemRequests={}
function G.RequestItemData(id)
    if not id then return end
    local now=G.clock()
    for key,t in pairs(G.itemRequests) do if now-t>=10 then G.itemRequests[key]=nil end end
    if G.itemRequests[id] or G.Count(G.itemRequests)>=512 then return end
    G.itemRequests[id]=now
    G.Safe(C_Item and C_Item.RequestLoadItemDataByID,id)
end
function G.ItemDataReceived(id,success)
    if not G.itemRequests[id] then return end
    -- Failed lookups retain the cooldown; do not immediately request again.
    if success==false then return end
    G.itemRequests[id]=nil
    G.itemRevision=(G.itemRevision or 0)+1
    G.Refresh()
end
function G.RegionalNames()
    return G.Safe(RegionalUniqueNamesEnabled)==true
end
function G.SurnameSeparator()
    local c=Constants and Constants.CharacterNameSeparatorConsts
    return c and c.CHARACTERNAME_SURNAME_SEPARATOR or " "
end
function G.Name(name)
    if type(name) ~= "string" or name == "" then return nil end
    if G.RegionalNames() then
        -- Camelot character identity includes the surname, not an internal realm.
        if G.SurnameSeparator()~="-" then name=name:match("^([^%-]+)") or name end
        return name
    end
    if not name:find("-",1,true) then name = name .. "-" .. (GetNormalizedRealmName() or GetRealmName()):gsub("%s", "") end
    return name
end
function G.UnitName(unit)
    local first,second=G.Safe(UnitName,unit)
    if not first then return nil end
    if second and second~="" then
        first=first..(G.RegionalNames() and G.SurnameSeparator() or "-")..second
    end
    return G.Name(first)
end
function G.GuildScope(club)
    if G.RegionalNames() then
        local region=G.Safe(GetCurrentRegion)
        if not region then return nil end
        return "region:"..region..":club:"..tostring(club)
    end
    return (GetNormalizedRealmName() or GetRealmName())..":"..tostring(club)
end
function G.Say(text) DEFAULT_CHAT_FRAME:AddMessage("|cffe1bc6cGuild Ledger:|r " .. text) end
function G.Age(t)
    if not t then return "not scanned" end
    local d = math.max(0, G.now()-t)
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d/60).."m ago" end
    if d < 86400 then return math.floor(d/3600).."h ago" end
    return math.floor(d/86400).."d ago (outdated)"
end
function G.Count(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
function G.Hash(s)
    local n=5381
    for i=1,#s do n=(n*33+s:byte(i))%2147483647 end
    return string.format("%08x",n)
end
function G.Keys(t) local a={}; for k in pairs(t) do a[#a+1]=k end; table.sort(a); return a end
function G.ItemID(link) return type(link)=="string" and tonumber(link:match("item:(%d+)")) or nil end
function G.Plain(s) return (tostring(s or ""):gsub("|", "")) end
