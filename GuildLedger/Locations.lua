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
    G.locations[sender]={stamp=v.stamp,received=G.clock(),hidden=v.hidden,map=v.map,x=v.x,y=v.y}
    G.RefreshMapPins()
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
function G.VisibleLocations(map)
    local rows={}
    for name,v in pairs(G.locations) do
        if G.clock()-v.received>=TTL or G.now()-v.stamp>=TTL or not G.members[name] then
            G.locations[name]=nil
        elseif G.ready and G.db.settings.showGuildLocations==true and not v.hidden and v.map==map and G.members[name].online then
            rows[#rows+1]={name=name,location=v}
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
    self.dot=self:CreateTexture(nil,"ARTWORK"); self.dot:SetAllPoints()
    self.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    local mask=self:CreateMaskTexture()
    mask:SetAllPoints(); mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    self.dot:AddMaskTexture(mask); self.dotMask=mask
end
function GuildLedgerLocationPinMixin:OnAcquired(name,v)
    self.memberName=name
    local m=G.members[name]
    local class=m and G.Safe(C_CreatureInfo and C_CreatureInfo.GetClassInfo,m.class)
    local color=class and RAID_CLASS_COLORS[class.classFile]
    self.dot:SetVertexColor(color and color.r or 0.9,color and color.g or 0.75,color and color.b or 0.45)
    self:SetPosition(v.x/10000,v.y/10000)
end
function GuildLedgerLocationPinMixin:OnMouseEnter()
    local name=self.memberName; local m=G.members[name]; local v=G.locations[name]
    if not m or not v then return end
    GameTooltip:SetOwner(self,"ANCHOR_CURSOR"); GameTooltip:SetText(G.Plain(name))
    local class=G.Safe(C_CreatureInfo and C_CreatureInfo.GetClassInfo,m.class)
    GameTooltip:AddLine(m.level.." "..(class and class.className or ""),1,1,1)
    local profile=G.Get("profile",name)
    if profile then GameTooltip:AddLine(G.SpecSummary(profile.data),0.9,0.75,0.45) end
    local info=G.Safe(C_Map.GetMapInfo,v.map)
    GameTooltip:AddLine(info and info.name or "Guild member",0.8,0.8,0.8)
    GameTooltip:AddLine("Updated "..G.Age(v.stamp),0.8,0.8,0.8)
    GameTooltip:Show()
end
function GuildLedgerLocationPinMixin:OnMouseLeave() GameTooltip:Hide() end
function GuildLedgerLocationPinMixin:OnReleased()
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    MapCanvasPinMixin.OnReleased(self)
end
function G.RefreshMapPins()
    local map=G.locationMap
    if not map then return end
    if G.locationToggle then
        G.locationToggle:SetChecked(G.db.settings.showGuildLocations==true)
    end
    local rows=G.VisibleLocations(map:GetMapID())
    local signature=tostring(map:GetMapID())..":"..tostring(map:IsShown())..":"..tostring(G.db.settings.showGuildLocations)
    for _,row in ipairs(rows) do signature=signature..":"..row.name..":"..row.location.stamp end
    if signature==G.locationPinSignature then return end
    G.locationPinSignature=signature
    map:RemoveAllPinsByTemplate("GuildLedgerLocationPinTemplate")
    if not map:IsShown() then return end
    for _,row in ipairs(rows) do map:AcquirePin("GuildLedgerLocationPinTemplate",row.name,row.location) end
end
function G.InstallMapOverlay()
    if G.locationMap or not WorldMapFrame or not MapCanvasDataProviderMixin or not WorldMapFrame.AddDataProvider then return end
    G.locationMap=WorldMapFrame
    local provider=CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RefreshAllData() G.locationPinSignature=nil; G.RefreshMapPins() end
    function provider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate("GuildLedgerLocationPinTemplate"); G.locationPinSignature=nil end
    function provider:OnShow() self:RefreshAllData() end
    function provider:OnHide() self:RemoveAllData() end
    WorldMapFrame:AddDataProvider(provider)
    local toggle=CreateFrame("CheckButton",nil,WorldMapFrame,"UICheckButtonTemplate")
    G.locationToggle=toggle
    toggle:SetSize(24,24); toggle:SetPoint("TOPLEFT",WorldMapFrame,"TOPLEFT",16,0)
    local label=toggle:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    label:SetPoint("LEFT",toggle,"RIGHT",2,0); label:SetText("Guild members")
    toggle:SetScript("OnClick",function(self) G.SetShowLocations(self:GetChecked()==true) end)
    toggle:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_CURSOR"); GameTooltip:SetText("Guild members")
        GameTooltip:AddLine("Show shared positions on this zone map.",1,1,1,true)
        GameTooltip:AddLine("Share your own location in Guild Ledger Settings.",0.8,0.8,0.8,true); GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave",function() GameTooltip:Hide() end)
    G.RefreshMapPins()
end
function G.LocationTick()
    G.VisibleLocations(nil)
    G.InstallMapOverlay()
    if not G.locationLastSend or G.clock()-G.locationLastSend>=30 then G.BroadcastLocation() end
    G.RefreshMapPins()
end
