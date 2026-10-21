local _,G=...
G.LOCATION_PREFIX="GLDGP3"
G.locations={}
local TTL=90
local function integer(n,max)
    return type(n)=="number" and n==n and n>=0 and n<=max and n%1==0
end
function G.ClearLocations()
    G.locations={}; G.locationSent=nil; G.locationLastSend=nil
    if G.RefreshMapPins then G.RefreshMapPins() end
end
function G.ReceiveLocation(prefix,message,channel,sender)
    if prefix~=G.LOCATION_PREFIX or channel~="GUILD" or not G.ready or type(message)~="string" or #message>255 then return end
    sender=G.Name(sender)
    if sender==G.self or not G.members[sender] then return end
    local v=G.Decode(message)
    if type(v)~="table" or v.scope~=G.scope or not integer(v.stamp,G.now()+5) or G.now()-v.stamp>=TTL then return end
    if type(v.hidden)~="boolean" then return end
    if not v.hidden and (not integer(v.map,1e7) or v.map==0 or not integer(v.x,10000) or not integer(v.y,10000)) then return end
    local old=G.locations[sender]
    -- A hide wins ties; a delayed packet must not resurrect a hidden location.
    if old and (v.stamp<old.stamp or v.stamp==old.stamp and (old.hidden or not v.hidden)) then return end
    local changed=not old or old.hidden~=v.hidden or old.map~=v.map or old.x~=v.x or old.y~=v.y
    local entry=old or {}
    if changed then entry.projection=nil end
    entry.stamp=v.stamp; entry.received=G.clock(); entry.hidden=v.hidden
    entry.map=v.map; entry.x=v.x; entry.y=v.y
    G.locations[sender]=entry
    if changed then G.RefreshMapPins(sender) end
end
function G.BroadcastLocation(forceHide)
    if not G.ready or not G.scope then return end
    local hidden=forceHide or G.db.settings.shareLocation~=true or G.worldLoading or G.Safe(IsInInstance)==true
    local map,x,y
    if not hidden then
        map=G.Safe(C_Map and C_Map.GetBestMapForUnit,"player")
        local pos=map and G.Safe(C_Map.GetPlayerMapPosition,map,"player")
        if pos then x,y=G.Safe(pos.GetXY,pos) end
        if not integer(map,1e7) or not x or not y or x~=x or y~=y or x<0 or x>1 or y<0 or y>1 then hidden=true end
    end
    if hidden and not G.locationSent then return end
    -- Single bounded packet, independent of the recipe-transfer queue.
    -- Never queue coordinates: disabling sharing cannot leave an outgoing backlog.
    local v={scope=G.scope,stamp=G.now(),hidden=hidden==true}
    if not hidden then v.map=map; v.x=math.floor(x*10000+0.5); v.y=math.floor(y*10000+0.5) end
    local message=G.Encode(v)
    if #message>255 then return end
    local result=G.Safe(C_ChatInfo and C_ChatInfo.SendAddonMessage,G.LOCATION_PREFIX,message,"GUILD")
    if result==true or result==0 then G.locationSent=not hidden end
    G.locationLastSend=G.clock()
end
function G.SetLocationSharing(enabled)
    G.db.settings.shareLocation=enabled==true
    G.BroadcastLocation(not enabled)
end
function G.SetShowLocations(enabled)
    G.db.settings.showGuildLocations=enabled==true
    G.InstallMapOverlay(); G.RefreshMapPins()
end
local function finite(n)
    return type(n)=="number" and n==n and n>-math.huge and n<math.huge
end
local function ancestor(child,parent)
    local seen={}
    for i=1,16 do
        if child==parent then return true end
        if not child or child==0 or seen[child] then return false end
        seen[child]=true
        local info=G.Safe(C_Map and C_Map.GetMapInfo,child)
        child=info and info.parentMapID
    end
    return false
end
function G.LocationOnMap(v,map)
    if not map then return end
    if v.map==map then return v.x/10000,v.y/10000 end
    local target=G.Safe(C_Map and C_Map.GetMapInfo,map)
    local types=Enum and Enum.UIMapType
    if not target or not types or (target.mapType~=types.Continent and target.mapType~=types.Zone and target.mapType~=types.Micro) then return end
    -- A received parent-map position can also be projected into its visible child.
    if ancestor(map,v.map) then
        local minX,maxX,minY,maxY=G.Safe(C_Map.GetMapRectOnMap,map,v.map)
        if not finite(minX) or not finite(maxX) or not finite(minY) or not finite(maxY) or maxX<=minX or maxY<=minY then return end
        local x=(v.x/10000-minX)/(maxX-minX)
        local y=(v.y/10000-minY)/(maxY-minY)
        if x>=0 and x<=1 and y>=0 and y<=1 then return x,y end
        return
    end
    -- Only project through related maps, never a different landmass.
    local id=v.map; local seen={}
    for i=1,16 do
        if id==map then
            local minX,maxX,minY,maxY=G.Safe(C_Map.GetMapRectOnMap,v.map,map)
            if not finite(minX) or not finite(maxX) or not finite(minY) or not finite(maxY) or maxX<=minX or maxY<=minY then return end
            local x=minX+(maxX-minX)*v.x/10000
            local y=minY+(maxY-minY)*v.y/10000
            if x>=0 and x<=1 and y>=0 and y<=1 then return x,y end
            return
        end
        if not id or id==0 or seen[id] then return end
        seen[id]=true
        local info=G.Safe(C_Map.GetMapInfo,id)
        id=info and info.parentMapID
    end
end
function G.VisibleLocations(map)
    local rows={}
    for name,v in pairs(G.locations) do
        if G.clock()-v.received>=TTL or G.now()-v.stamp>=TTL or not G.members[name] then
            G.locations[name]=nil
        -- Roster validation pauses sync while club membership refreshes. Keep
        -- already validated, unexpired positions visible during that pause.
        elseif map and G.db.settings.showGuildLocations==true and not v.hidden and G.members[name].online then
            local x,y=G.LocationOnMap(v,map)
            if x then rows[#rows+1]={name=name,location=v,x=x,y=y} end
        end
    end
    table.sort(rows,function(a,b) return a.name<b.name end)
    return rows
end

-- Custom artwork and hover text, positioned/scaled by Blizzard's map canvas.
GuildLedgerLocationPinMixin={}
function GuildLedgerLocationPinMixin:OnLoad()
    self:SetSize(14,14)
    self:SetScalingLimits(1,1,1)
    self:SetAlphaLimits(1,1,1)
    -- Receive hover above the map's full-size unit-position overlay, without
    -- intercepting map clicks. Explicit scripts also cover client template differences.
    self:UseFrameLevelType("PIN_FRAME_LEVEL_TOPMOST")
    self:SetMouseMotionEnabled(true)
    self:SetMouseClickEnabled(false)
    self:SetScript("OnEnter",self.OnMouseEnter)
    self:SetScript("OnLeave",self.OnMouseLeave)
    -- Small outlined diamonds distinguish guild members from round party dots.
    -- Keep a larger invisible hover target without enlarging the artwork.
    self.outline=self:CreateTexture(nil,"BACKGROUND")
    self.outline:SetSize(8,8); self.outline:SetPoint("CENTER")
    self.outline:SetColorTexture(0.06,0.07,0.09,1)
    self.outline:SetRotation(math.pi/4)
    self.dot=self:CreateTexture(nil,"ARTWORK")
    self.dot:SetSize(5,5); self.dot:SetPoint("CENTER")
    self.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    self.dot:SetRotation(math.pi/4)
end
function GuildLedgerLocationPinMixin:OnAcquired(name,v,x,y)
    self.memberName=name
    local m=G.members[name]
    local class=m and G.Safe(C_CreatureInfo and C_CreatureInfo.GetClassInfo,m.class)
    local color=class and RAID_CLASS_COLORS[class.classFile]
    self.dot:SetVertexColor(color and color.r or 0.9,color and color.g or 0.75,color and color.b or 0.45)
    self:SetPosition(x or v.x/10000,y or v.y/10000)
    self.ledgerX=x or v.x/10000; self.ledgerY=y or v.y/10000
    self.ledgerMap=self:GetMap() and self:GetMap():GetMapID()
end
function GuildLedgerLocationPinMixin:OnMouseEnter()
    local name=self.memberName; local m=G.members[name]; local v=G.locations[name]
    if not m or not v then return end
    GameTooltip:SetOwner(self,"ANCHOR_CURSOR"); GameTooltip:SetText(G.Plain(name))
    local class=G.Safe(C_CreatureInfo and C_CreatureInfo.GetClassInfo,m.class)
    local detail=m.level.." "..(class and class.className or "")
    local profile=G.Get("profile",name)
    local spec=G.SpecSummary(profile and profile.data)
    if spec~="Not shared" and spec~="Unspent" then detail=detail.." - "..G.Plain(spec) end
    GameTooltip:AddLine(detail,1,1,1)
    GameTooltip:Show()
end
function GuildLedgerLocationPinMixin:OnMouseLeave()
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end
function GuildLedgerLocationPinMixin:OnReleased()
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    if G.locationPins and G.locationPins[self.memberName]==self then G.locationPins[self.memberName]=nil end
    self.memberName=nil
    MapCanvasPinMixin.OnReleased(self)
end
-- Some client map overlays swallow pin motion events. Test the actual visible
-- pin bounds as a fallback, without allocating a timer or handler for every pin.
function G.UpdateLocationHover(map,elapsed)
    G.locationHoverElapsed=(G.locationHoverElapsed or 0)+elapsed
    if G.locationHoverElapsed<0.1 then return end
    G.locationHoverElapsed=0
    local hit
    if map:IsShown() and G.db.settings.showGuildLocations and MouseIsOver and MouseIsOver(map.ScrollContainer or map) then
        for name,pin in pairs(G.locationPins or {}) do
            if pin:IsShown() and MouseIsOver(pin) and (not hit or name<hit.memberName) then hit=pin end
        end
    end
    local old=G.locationHoverPin
    if old and old~=hit and GameTooltip:IsOwned(old) then GameTooltip:Hide() end
    G.locationHoverPin=hit
    if hit and (not GameTooltip:IsOwned(hit) or not GameTooltip:IsShown()) then hit:OnMouseEnter() end
end
-- Cache one successful projection per member; changing map/coordinates replaces it.
local function projectedPosition(v,map)
    local cached=v.projection
    if cached and cached.map==map then return cached.x,cached.y end
    local x,y=G.LocationOnMap(v,map)
    if x then v.projection={map=map,x=x,y=y} else v.projection=nil end
    return x,y
end
function G.RefreshMapPins(member)
    local map=G.locationMap
    if not map then return end
    if G.locationToggle then G.locationToggle:SetChecked(G.db.settings.showGuildLocations==true) end
    G.locationPins=G.locationPins or {}
    local mapID=map:IsShown() and G.db.settings.showGuildLocations and map:GetMapID()
    local function update(name)
        local v=G.locations[name]; local m=G.members[name]
        local pin=G.locationPins[name]
        local x,y
        if mapID and v and not v.hidden and m and m.online then x,y=projectedPosition(v,mapID) end
        if x then
            if pin then
                if pin.ledgerX~=x or pin.ledgerY~=y or pin.ledgerMap~=mapID then
                    pin:SetPosition(x,y)
                    pin.ledgerX=x; pin.ledgerY=y; pin.ledgerMap=mapID
                end
            else
                pin=map:AcquirePin("GuildLedgerLocationPinTemplate",name,v,x,y)
                G.locationPins[name]=pin
                pin.ledgerX=x; pin.ledgerY=y; pin.ledgerMap=mapID
            end
        elseif pin then
            G.locationPins[name]=nil; map:RemovePin(pin)
        end
    end
    if member then update(member) else
        for name in pairs(G.locations) do update(name) end
        for name in pairs(G.locationPins) do if not G.locations[name] then update(name) end end
    end
end
function G.InstallMapOverlay()
    if G.locationMap or not WorldMapFrame or not MapCanvasDataProviderMixin or not WorldMapFrame.AddDataProvider then return end
    G.locationMap=WorldMapFrame
    local provider=CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RefreshAllData() G.RefreshMapPins() end
    function provider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate("GuildLedgerLocationPinTemplate"); G.locationPins={} end
    function provider:OnShow() self:RefreshAllData() end
    function provider:OnHide() self:RemoveAllData() end
    WorldMapFrame:AddDataProvider(provider)
    WorldMapFrame:HookScript("OnUpdate",G.UpdateLocationHover)
    WorldMapFrame:HookScript("OnHide",function()
        local pin=G.locationHoverPin
        if pin and GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
        G.locationHoverPin=nil; G.locationHoverElapsed=0
    end)
    local toggle=CreateFrame("CheckButton",nil,WorldMapFrame,"UICheckButtonTemplate")
    G.locationToggle=toggle
    toggle:SetSize(24,24); toggle:SetPoint("TOPLEFT",WorldMapFrame,"TOPLEFT",16,0)
    local label=toggle:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    label:SetPoint("LEFT",toggle,"RIGHT",2,0); label:SetText("Guild members")
    toggle:SetScript("OnClick",function(self) G.SetShowLocations(self:GetChecked()==true) end)
    toggle:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_CURSOR"); GameTooltip:SetText("Guild members")
        GameTooltip:AddLine("Show shared positions on zone and continent maps.",1,1,1,true)
        GameTooltip:AddLine("Class-colored diamonds mark guild members.",0.9,0.75,0.45,true)
        GameTooltip:AddLine("Share your own location in Guild Ledger Settings.",0.8,0.8,0.8,true); GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave",function() GameTooltip:Hide() end)
    G.RefreshMapPins()
end
function G.LocationTick()
    -- Expiry uses no sorted row list and does not rebuild unaffected pins.
    local clock,now=G.clock(),G.now()
    for name,v in pairs(G.locations) do
        if clock-v.received>=TTL or now-v.stamp>=TTL or not G.members[name] then
            G.locations[name]=nil; G.RefreshMapPins(name)
        end
    end
    G.InstallMapOverlay()
    if not G.locationLastSend or G.clock()-G.locationLastSend>=30 then G.BroadcastLocation() end
    local roster=G.Revision("roster")
    if roster~=G.locationRosterRevision then
        G.locationRosterRevision=roster; G.RefreshMapPins()
    end
end
