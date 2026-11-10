local _,G=...
local deflate=LibStub('GuildLedgerDeflate')
G.sequence=0
G.performance={started=G.clock(),sentBytes=0,receivedBytes=0,sentPackets=0,receivedPackets=0,failures=0,peakTick=0,peakReceive=0,totalTick=0,totalReceive=0,ticks=0,receives=0,peakMemory=0}
function G.ResetTransport()
 G.ResetPeers()
 G.policyTimes={}
 G.sourceBackoff={}; G.retrySourceAt=nil
 G.sent={}; G.completed={}; G.controls={}; G.recentWhispers={}; G.digestRevision=nil; G.digestWork=nil
 if G.InventoryInvalidate then G.InventoryInvalidate() end
 G.nativeBlocks={}; G.nativePrefixFailures={}; G.lastServed={}; G.serviceCursor=0; G.locationPending=nil
end
G.ResetTransport()
-- Fixed fields avoid generic table/compression overhead on the guild heartbeat.
-- The optional bounded catalog count brings the maximum to 175 bytes, still
-- below one 180-byte fragment. Older seven-field beacons remain readable.
local function beaconFields(scope,version,inventory,policy,gear,busy,records)
 if type(scope)~='string' or #scope<1 or #scope>64 or scope:find('[|%c]')
  or type(version)~='string' or #version>32 or not version:match('^%d+%.%d+%.%d+$')
  or type(inventory)~='string' or #inventory~=8 or not inventory:match('^%x+$')
  or type(policy)~='string' or #policy>32 or type(gear)~='string' or #gear>24
  or busy~='0' and busy~='1' then return end
 if records~=nil and (type(records)~='number' or records%1~=0 or records<0 or records>12000) then return end
 local hash,revision=policy:match('^(%x+)/(%d+)$')
 if not hash or #hash~=16 or #revision>15 then return end
 if gear~='' then
  local rev,token=gear:match('^(%d+)/(%x+)$')
  if not rev or #rev>15 or #token~=8 then return end
 end
 return true
end
local function queuedBytes()
 local n=0; for _,q in ipairs(G.queue) do n=n+#q.data end
 for _,q in pairs(G.sent) do n=n+#q.data end
 return n
end
function G.CanQueue(size,slots)
 return #G.queue+(slots or 1)<=160 and queuedBytes()+(size or 2048)<=524288
end
function G.TransportPressure() return #G.queue,queuedBytes(),G.Count(G.sent) end
local function budgetAt(now)
 local b=G.sendBudget
 if not b then b={at=now,bytes=512,packets=2}; G.sendBudget=b end
 local elapsed=math.max(0,now-b.at); b.at=now
 local rate=InCombatLockdown and InCombatLockdown() and 400 or 800
 if now<(G.trafficWarmUntil or 0) then rate=80 end
 b.bytes=math.min(512,b.bytes+elapsed*rate); b.packets=math.min(2,b.packets+elapsed*10)
 return b
end
function G.TransportEnteringWorld()
 G.trafficWarmUntil=G.clock()+5
 local b=budgetAt(G.clock()); b.bytes=math.min(0,b.bytes)
end
-- Observe other senders without wrapping/replacing their APIs or changing their
-- traffic. The shared byte allowance follows ChatThrottleLib's conservative
-- 800 B/s model; this addon retains ownership of cancellation and reliability.
function G.ObserveExternalTraffic(kind,prefix,message,channel,target)
 if issecretvalue and (issecretvalue(prefix) or issecretvalue(message) or issecretvalue(channel) or issecretvalue(target)) then return end
 local own=G.nativeCall
 if own and kind=='addon' and own.prefix==prefix and own.message==message and own.channel==channel and own.target==target then return end
 local size=(type(prefix)=='string' and #prefix or 0)+(type(message)=='string' and #message or 0)
 size=size+(type(target)=='string' and #target or 0)+40
 local b=budgetAt(G.clock()); b.bytes=math.max(-1600,b.bytes-size)
 G.performance.externalBytes=(G.performance.externalBytes or 0)+size
end
function G.InstallTrafficAccounting()
 if G.trafficHooks or type(hooksecurefunc)~='function' then return end
 G.trafficHooks=true
 local function hook(owner,key,fn)
  if owner and type(owner[key])=='function' then pcall(hooksecurefunc,owner,key,fn) end
 end
 local function addon(...) G.ObserveExternalTraffic('addon',...) end
 hook(C_ChatInfo,'SendAddonMessage',addon)
 hook(C_ChatInfo,'SendAddonMessageLogged',addon)
 if not C_ChatInfo or type(C_ChatInfo.SendAddonMessage)~='function' then hook(_G,'SendAddonMessage',addon) end
 local function chat(message,channel,language,target) G.ObserveExternalTraffic('chat',nil,message,channel,target) end
 if C_ChatInfo and type(C_ChatInfo.SendChatMessage)=='function' then hook(C_ChatInfo,'SendChatMessage',chat)
 else hook(_G,'SendChatMessage',chat) end
 local function bnet(target,prefix,message) G.ObserveExternalTraffic('bnet',prefix,message,'WHISPER',target) end
 if C_BattleNet and type(C_BattleNet.SendGameData)=='function' then hook(C_BattleNet,'SendGameData',bnet)
 else hook(_G,'BNSendGameData',bnet) end
end
function G.WireEncode(v)
 if v.type=='beacon' then
  local busy=v.catchingUp and '1' or '0'
  if beaconFields(v.scope,v.version,v.inventory,v.policy,v.gear,busy,v.records) then
   return 'B3|'..table.concat({v.scope,v.version,v.inventory,v.policy,v.gear,busy},'|')..(v.records~=nil and '|'..v.records or '')
  end
  -- Unusual realms/versions still use the existing fully compatible transport.
  v=G.Copy(v); v.type='hello'
 end
 local s=G.Encode(v)
 local compressed=deflate:EncodeForPrint(deflate:CompressDeflate(s,{level=1}))
 return #compressed<#s and 'Z'..compressed or 'R'..s
end
function G.WireDecode(s)
 if #s>G.MAX_WIRE+1 then return end
 if s:sub(1,3)=='B3|' then
  if #s>175 then return end
  local scope,version,inventory,policy,gear,busy,count=s:match('^B3|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$')
  local records
  if scope then
   if #count>5 or not count:match('^%d+$') then return end
   records=tonumber(count)
   if tostring(records)~=count then return end
  else scope,version,inventory,policy,gear,busy=s:match('^B3|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$') end
  if not beaconFields(scope,version,inventory,policy,gear,busy,records) then return end
  return {type='beacon',scope=scope,version=version,protocol=3,beacon=true,inventory=inventory,digest=inventory,policy=policy,gear=gear,catchingUp=busy=='1',records=records}
 end
 local raw
 if s:sub(1,1)=='R' then raw=s:sub(2)
 elseif s:sub(1,1)=='Z' then
  local compressed=deflate:DecodeForPrint(s:sub(2)); if not compressed then return end
  local remaining; raw,remaining=deflate:DecompressDeflate(compressed)
  if remaining~=0 then return end
 end
 if not raw or #raw>G.MAX_WIRE then return end
 return G.Decode(raw)
end
function G.Send(value,target,channel,urgent)
 if not G.ready or G.registeredPrefixes and G.registeredPrefixes[G.PREFIX]==false or G.nativePrefixFailures[G.PREFIX]
  or target and not G.PeerReachable(target) then return false end
 value.protocol=G.PROTOCOL
 local ok,s=pcall(G.WireEncode,value)
 if not ok or #s>G.MAX_WIRE then G.errors.sync='Record exceeds transfer limits'; return false end
 -- Receivers retry missing recipe definitions while a busy source may still
 -- have their first answer queued. Reuse that exact pending reply, not an
 -- already-sent packet: after a receiver reset a fresh request needs a new ID.
 if value.type=='definitions' and target then
  for _,pending in ipairs(G.queue) do
   if pending.target==target and pending.channel==(channel or 'WHISPER') and pending.data==s then return true end
  end
 end
 if not G.CanQueue(#s) then return false end
 G.sequence=G.sequence+1
 local q={data=s,target=target,channel=channel or 'WHISPER',part=1,total=math.ceil(#s/180),
  id=G.Hash(G.self..G.now()..G.sequence),hash=G.Hash(s),prefix=G.PREFIX,created=G.clock(),urgent=urgent,
  expires=G.clock()+(value.type=='announcement' and 10 or 300)}
 if value.type=='changes' and type(value.rows)=='table' then
  -- IDs only: a loot-policy reset can replay unsent local non-loot snapshots
  -- without decoding queued payloads or retaining copies of record data.
  for i=1,math.min(32,#value.rows) do
   local row=value.rows[i]; local id=type(row)=='table' and row.id
   local r=type(id)=='string' and G.store and G.store.records[id]
   if r and r.owner==G.self and r.kind~='loot' then
    q.localChanges=q.localChanges or {}; q.localChanges[#q.localChanges+1]=id
   end
  end
 end
 if urgent then table.insert(G.queue,G.queue[1] and G.queue[1].part>1 and 2 or 1,q) else G.queue[#G.queue+1]=q end
 return true
end
function G.CancelPeerTransport(target)
 for i=#G.queue,1,-1 do if G.queue[i].target==target then table.remove(G.queue,i) end end
 for i=#G.controls,1,-1 do if G.controls[i].target==target then table.remove(G.controls,i) end end
 for id,q in pairs(G.sent) do if q.target==target then G.sent[id]=nil end end
 for id,partial in pairs(G.partials) do if partial.sender==target then G.partials[id]=nil end end
 G.recentWhispers[target]=nil
 G.lastServed[target]=nil; G.nativeBlocks['target:'..target]=nil
end
local function noteWhisper(target,now)
 for name,at in pairs(G.recentWhispers) do if now-at>15 then G.recentWhispers[name]=nil end end
 if not G.recentWhispers[target] and G.Count(G.recentWhispers)>=64 then
  local oldest,at
  for name,seen in pairs(G.recentWhispers) do if not at or seen<at then oldest,at=name,seen end end
  G.recentWhispers[oldest]=nil
 end
 G.recentWhispers[target]=now
end
function G.HandleTransportSystemMessage(message)
 if type(message)~='string' or type(ERR_CHAT_PLAYER_NOT_FOUND_S)~='string'
  or issecretvalue and issecretvalue(message) then return end
 for target,at in pairs(G.recentWhispers) do
  if G.clock()-at<=15 then
   local ok,expected=pcall(string.format,ERR_CHAT_PLAYER_NOT_FOUND_S,target)
   local matched=ok and message==expected
   if not matched and not G.RegionalNames() then
    local realm=G.Safe(GetNormalizedRealmName) or G.Safe(GetRealmName)
    local suffix=type(realm)=='string' and '-'..realm:gsub('%s','')
    if suffix and target:sub(-#suffix)==suffix then
     ok,expected=pcall(string.format,ERR_CHAT_PLAYER_NOT_FOUND_S,target:sub(1,-#suffix-1)); matched=ok and message==expected
    end
   end
   if matched then G.PeerUnavailable(target,'not-found'); return end
  end
 end
end
local function control(msg,target)
 if not G.PeerReachable(target) then return end
 if msg:sub(1,2)=='A|' then
  for _,c in ipairs(G.controls) do
   if c.target==target and c.msg:sub(1,2)=='A|' then
    local pair=msg:sub(3)
    if c.msg:find(pair,1,true) then return end
    if #c.msg+#pair+1<=240 then c.msg=c.msg..','..pair; return end
   end
  end
 end
 if #G.controls<128 then G.controls[#G.controls+1]={msg=msg,target=target,created=G.clock(),ready=G.clock()+(msg:sub(1,2)=='A|' and 0.4 or 0)} end
end
local function frame(q,part)
 return 'D|'..q.id..'|'..part..'|'..q.total..'|'..q.hash..'|'..q.data:sub((part-1)*180+1,part*180)
end
local function frameCost(q,part)
 -- Avoid allocating complete candidate packets during each scheduler scan.
 return 22+#tostring(part)+#tostring(q.total)+math.min(180,#q.data-(part-1)*180)
  +#q.prefix+#(q.target or '')+40
end
function G.Receive(prefix,msg,channel,sender)
 if prefix~=G.PREFIX or not G.ready or (channel~='GUILD' and channel~='WHISPER') or type(msg)~='string' or #msg>255 then return end
 sender=G.Name(sender); if sender==G.self or not G.members[sender] then return end
 G.performance.receivedBytes=G.performance.receivedBytes+#msg+#prefix; G.performance.receivedPackets=G.performance.receivedPackets+1
 G.rates=G.rates or {}; local rate=G.rates[sender]
 if not rate or G.clock()-rate.start>=1 then rate={start=G.clock(),count=0}; G.rates[sender]=rate end
 rate.count=rate.count+1; if rate.count>30 then return end
 if prefix==G.PREFIX then
  if msg:sub(1,2)=='A|' then
   local entries={}
   for pair in msg:sub(3):gmatch('[^,]+') do
    local id,hash=pair:match('^(%x%x%x%x%x%x%x%x)|(%x%x%x%x%x%x%x%x)$')
    if not id or #entries>=13 then return end
    entries[#entries+1]={id,hash}
   end
   for _,entry in ipairs(entries) do
    local q=G.sent[entry[1]]; if q and q.target==sender and q.hash==entry[2] then G.sent[entry[1]]=nil end
   end
   return
  end
  local nid,nhash,missing=msg:match('^N|(%x+)|(%x+)|([%d,]+)$')
  if nid then
   local q=G.sent[nid]
   if q and q.target==sender and q.hash==nhash and G.clock()-(q.nackAt or -10)>=1 then
    q.nackAt=G.clock(); q.retryParts={}; local seen={}
    for part in missing:gmatch('%d+') do
     part=tonumber(part)
     if part>=1 and part<=q.total and not seen[part] and #q.retryParts<32 then q.retryParts[#q.retryParts+1]=part; seen[part]=true end
    end
   end
   return
  end
 end
 local id,p,n,hash,chunk=msg:match('^D|(%x+)|(%d+)|(%d+)|(%x+)|(.*)$')
 p,n=tonumber(p),tonumber(n)
 if not id or #id~=8 or #hash~=8 or not p or not n or n<1 or n>683 or p<1 or p>n or #chunk>180 then return end
 local key=prefix..':'..sender..':'..id
 local complete=G.completed[key]
 if complete and complete.hash==hash then
  if channel=='WHISPER' then control('A|'..id..'|'..hash,sender) end
  return
 end
 local t=G.partials[key]
 if not t then
  local count=0; for _,x in pairs(G.partials) do if x.sender==sender then count=count+1 end end
  if count>=4 or G.Count(G.partials)>=24 then return end
  t={sender=sender,id=id,total=n,hash=hash,parts={},count=0,bytes=0,start=G.clock(),channel=channel}; G.partials[key]=t
 end
 if t.total~=n or t.hash~=hash or t.parts[p] and t.parts[p]~=chunk then G.partials[key]=nil; return end
 if not t.parts[p] then t.parts[p]=chunk; t.count=t.count+1; t.bytes=t.bytes+#chunk end
 t.last=G.clock()
 local bytes=0; for _,x in pairs(G.partials) do bytes=bytes+x.bytes end
 if t.bytes>G.MAX_WIRE or bytes>524288 then G.partials[key]=nil; return end
 if t.count==n then
  G.partials[key]=nil; local s=table.concat(t.parts)
  if G.Hash(s)~=hash then return end
  local ok,v=pcall(G.WireDecode,s)
  if not ok or not v then return end
  local valid=G.ValidSyncEnvelope(v)
  local incompatible=type(v)=='table' and v.scope==G.scope and (v.type=='hello' or v.type=='offer')
   and type(v.protocol)=='number' and v.protocol%1==0 and v.protocol>=1 and v.protocol<=255
  if not valid and not incompatible then return end
  if valid then G.PeerActivity(sender) end
  if G.Count(G.completed)>=256 then
   local oldest,at; for k,c in pairs(G.completed) do if not at or c.at<at then oldest,at=k,c.at end end; G.completed[oldest]=nil
  end
  G.completed[key]={hash=hash,at=G.clock()}
  if channel=='WHISPER' then control('A|'..id..'|'..hash,sender) end
  -- Network data is never allowed to raise into the game's event loop.
  local handled,err=pcall(G.Handle,v,sender)
  if not handled then G.errors.sync='Rejected malformed sync payload' end
 end
end
-- Each class gets a turn when it has eligible work. A busy target cannot hold
-- other recipients, guild announcements, ACKs or location withdrawals behind it.
local classes={'control','broadcast','control','data','retry','data','location'}
local function removeItem(list,item)
 for i=#list,1,-1 do if list[i]==item then table.remove(list,i); return end end
end
local function dropItem(item,kind)
 if kind=='control' then removeItem(G.controls,item)
 elseif kind=='location' then if G.locationPending==item then G.locationPending=nil end
 elseif kind=='retry' then if G.sent[item.id]==item then G.sent[item.id]=nil end
 else removeItem(G.queue,item) end
end
local function routeBlocked(prefix,channel,target,now)
 if G.nativePrefixFailures[prefix] or G.registeredPrefixes and G.registeredPrefixes[prefix]==false then return true end
 for _,key in ipairs({'prefix:'..prefix..':'..channel,'channel:'..channel,target and 'target:'..target or ''}) do
  local block=G.nativeBlocks[key]; if block and now<block.untilTime then return true end
 end
 local lock=G.nativeBlocks.lockdown
 if lock then
  if now<lock.untilTime then return true end
  if G.Safe(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)==true then lock.untilTime=now+1; return true end
 end
 return false
end
local function serviceKey(item,kind)
 return item.target or (kind=='location' and 'location' or item.prefix..':'..item.channel)
end
local function candidate(kind,now,budget)
 local best,bestPart,bestCost,bestAge
 local seen,targetSent={},{}; local sent=0
 for _,q in pairs(G.sent) do sent=sent+1; targetSent[q.target]=(targetSent[q.target] or 0)+1 end
 local activeBroadcast
 if kind=='broadcast' then
  for _,q in ipairs(G.queue) do if q.channel=='GUILD' and q.urgent and q.part>1 then activeBroadcast=q; break end end
 end
 local function consider(item,part,prefix,channel,cost)
  local target=item.target
  if (not G.ready and not (kind=='location' and item.hidden and item.scope==G.scope))
   or target and not G.PeerReachable(target) or routeBlocked(prefix,channel,target,now)
   or cost>budget.bytes or budget.packets<1 then return end
  local key=serviceKey(item,kind); local age=G.lastServed[key] or -100000
  if not best or age<bestAge or kind=='broadcast' and item.urgent and not best.urgent then
   best,bestPart,bestCost,bestAge=item,part,cost,age
  end
 end
 if kind=='control' then
  for _,item in ipairs(G.controls) do
   if (item.ready or 0)<=now then consider(item,nil,G.PREFIX,'WHISPER',#item.msg+#G.PREFIX+#item.target+40) end
  end
 elseif kind=='location' then
  local item=G.locationPending
  if item and item.scope==G.scope then consider(item,nil,G.LOCATION_PREFIX,'GUILD',#item.data+#G.LOCATION_PREFIX+40) end
 elseif kind=='retry' then
  for _,item in pairs(G.sent) do
   local part=item.retryParts and item.retryParts[1]
   if part then consider(item,part,item.prefix,item.channel,frameCost(item,part)) end
  end
 else
  for _,item in ipairs(G.queue) do
   local category=item.channel=='GUILD' and 'broadcast' or 'data'
   if category==kind then
    local key=serviceKey(item,kind)
    -- One normal stream per recipient. Guild warnings/policy changes can
    -- preempt a bulk guild message, but only one urgent stream starts at a time.
    local priority=kind=='broadcast' and item.urgent
    if (not seen[key] or priority) and (not priority or not activeBroadcast or item==activeBroadcast) then
     seen[key]=true
     if not item.target or item.part>1 or sent<16 and (targetSent[item.target] or 0)<4 then
      consider(item,item.part,item.prefix,item.channel,frameCost(item,item.part))
     end
    end
   end
  end
 end
 return best,bestPart,bestCost
end
local function nativeFailure(item,kind,prefix,channel,target,result,now)
 local codes=Enum.SendAddonMessageResult or {}
 local code=type(result)=='number' and result or -1
 G.performance.failures=G.performance.failures+1
 G.performance.nativeRefusals=G.performance.nativeRefusals or {}
 local key=code>=0 and code<=12 and code or -1
 G.performance.nativeRefusals[key]=(G.performance.nativeRefusals[key] or 0)+1
 if target and code==(codes.TargetOffline or 12) then G.PeerUnavailable(target,'offline-result'); return end
 if code==(codes.InvalidPrefix or 1) then
  G.nativePrefixFailures[prefix]=true
  G.errors[prefix==G.PREFIX and 'syncPrefix' or 'locationPrefix']='Native client rejected addon prefix '..prefix
  for i=#G.queue,1,-1 do if G.queue[i].prefix==prefix then table.remove(G.queue,i) end end
  for id,q in pairs(G.sent) do if q.prefix==prefix then G.sent[id]=nil end end
  if prefix==G.PREFIX then G.controls={} else G.locationPending=nil end
  return
 end
 if code==(codes.InvalidMessage or 2) or code==(codes.InvalidChatType or 4)
  or code==(codes.TargetRequired or 6) or code==(codes.InvalidChannel or 7) then
  dropItem(item,kind); G.errors.transport='Native client rejected a sync request (code '..code..')'; return
 end
 local blockKey=code==(codes.AddonMessageThrottle or 3) and 'prefix:'..prefix..':'..channel
  or code==(codes.AddOnMessageLockdown or 11) and 'lockdown'
  or (code==(codes.ChannelThrottle or 8) or code==(codes.NotInGroup or 5) or code==(codes.NotInGuild or 10)) and 'channel:'..channel
  or target and 'target:'..target or 'prefix:'..prefix..':'..channel
 local block=G.nativeBlocks[blockKey] or {failures=0}
 block.failures=math.min(5,block.failures+1); block.untilTime=now+math.min(8,0.5*2^(block.failures-1))
 G.nativeBlocks[blockKey]=block
end
local function sendOne(now,budget,onlyLocation)
 local item,part,cost,kind
 if onlyLocation then kind='location'; item,part,cost=candidate(kind,now,budget)
 else
  for offset=1,#classes do
   local index=((G.serviceCursor or 0)+offset-1)%#classes+1
   kind=classes[index]; item,part,cost=candidate(kind,now,budget)
   if item then G.serviceCursor=index; break end
  end
 end
 if not item then return false end
 local prefix=kind=='location' and G.LOCATION_PREFIX or kind=='control' and G.PREFIX or item.prefix
 local channel=kind=='location' and 'GUILD' or kind=='control' and 'WHISPER' or item.channel
 local target=item.target
 local msg
 if kind=='location' then
  item.value.stamp=G.now(); msg=G.Encode(item.value)
  cost=#msg+#prefix+40
  if cost>budget.bytes then return false end
 else msg=kind=='control' and item.msg or frame(item,part) end
 budget.bytes=budget.bytes-cost; budget.packets=budget.packets-1
 G.lastServed[serviceKey(item,kind)]=now
 if channel=='WHISPER' and target then noteWhisper(target,now) end
 local previous=G.nativeCall; G.nativeCall={prefix=prefix,message=msg,channel=channel,target=target}
 local result=G.Safe(C_ChatInfo and C_ChatInfo.SendAddonMessage,prefix,msg,channel,target)
 G.nativeCall=previous
 -- Preserve the queue identity even if a synchronous error canceled this item
 -- and fresh contact immediately revived the same recipient before returning.
 if target and not G.PeerReachable(target) then return true end
 if kind=='control' and not (function() for _,v in ipairs(G.controls) do if v==item then return true end end end)()
  or (kind=='data' or kind=='broadcast') and not (function() for _,v in ipairs(G.queue) do if v==item then return true end end end)()
  or kind=='retry' and (G.sent[item.id]~=item or not item.retryParts or item.retryParts[1]~=part) then return true end
 if result~=(Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0) then
  nativeFailure(item,kind,prefix,channel,target,result,now); return true
 end
 G.nativeBlocks['prefix:'..prefix..':'..channel]=nil; G.nativeBlocks['channel:'..channel]=nil
 if target then G.nativeBlocks['target:'..target]=nil end
 G.nativeBlocks.lockdown=nil
 G.performance.sentBytes=G.performance.sentBytes+#msg+#prefix; G.performance.sentPackets=G.performance.sentPackets+1
 if kind=='location' then
  G.performance.locationSentPackets=(G.performance.locationSentPackets or 0)+1
  G.locationSent=not item.hidden; G.locationLastSend=now
  if G.locationPending==item then G.locationPending=nil end
 elseif kind=='control' then removeItem(G.controls,item)
 elseif kind=='retry' then table.remove(item.retryParts,1); if #item.retryParts==0 then item.retryParts=nil end
 else
  item.part=item.part+1
  if item.part>item.total then removeItem(G.queue,item); if target then item.sentAt=now; G.sent[item.id]=item end end
 end
 return true
end
function G.QueueLocation(message,hidden)
 if not G.ready and not hidden or not G.scope or G.nativePrefixFailures[G.LOCATION_PREFIX]
  or G.registeredPrefixes and G.registeredPrefixes[G.LOCATION_PREFIX]==false then return false end
 local value=G.Decode(message)
 if type(value)~='table' or value.scope~=G.scope or #message>255 then return false end
 G.locationPending={data=message,value=value,hidden=hidden==true,scope=G.scope}
 G.FlushLocation(); return true
end
function G.FlushLocation()
 if G.locationPending then sendOne(G.clock(),budgetAt(G.clock()),true) end
end
function G.SyncTick()
 local now=G.clock()
 for name,at in pairs(G.recentWhispers) do if now-at>15 then G.recentWhispers[name]=nil end end
 for k,c in pairs(G.completed) do if now-c.at>120 then G.completed[k]=nil end end
 for k,t in pairs(G.partials) do
  if now-(t.last or t.start)>45 or now-t.start>300 or not G.members[t.sender] then G.partials[k]=nil
  elseif t.channel=='WHISPER' and now-t.last>2 and now-(t.nackAt or -10)>3 then
   local missing={}; for i=1,t.total do if not t.parts[i] and #missing<32 then missing[#missing+1]=i end end
   control('N|'..t.id..'|'..t.hash..'|'..table.concat(missing,','),t.sender); t.nackAt=now
  end
 end
 for id,q in pairs(G.sent) do
  if not G.PeerReachable(q.target) or now-q.sentAt>120 then G.sent[id]=nil
  elseif now-(q.retryAt or q.sentAt)>8 and not q.retryParts then
   q.retryParts={q.total}; q.retryAt=now
  end
 end
 for i=#G.queue,1,-1 do
  local q=G.queue[i]
  if q.expires and now>=q.expires or q.target and not G.PeerReachable(q.target) then table.remove(G.queue,i) end
 end
 for i=#G.controls,1,-1 do
  local c=G.controls[i]
  if now-(c.created or now)>30 or not G.PeerReachable(c.target) then table.remove(G.controls,i) end
 end
 G.SyncWork()
 local budget=budgetAt(now)
 -- Never accumulate a large burst after a loading screen or frame stall.
 for i=1,2 do if not sendOne(now,budget) then break end end
end
-- Constant-space diagnostics; no payload history or per-member telemetry.
local tick,receive=G.SyncTick,G.Receive
function G.SyncTick(...)
 local start=debugprofilestop and debugprofilestop()
 tick(...)
 if start then local ms=math.max(0,debugprofilestop()-start); local p=G.performance; p.peakTick=math.max(p.peakTick,ms); p.totalTick=p.totalTick+ms; p.ticks=p.ticks+1 end
end
function G.Receive(...)
 local start=debugprofilestop and debugprofilestop()
 receive(...)
 if start then local ms=math.max(0,debugprofilestop()-start); local p=G.performance; p.peakReceive=math.max(p.peakReceive,ms); p.totalReceive=p.totalReceive+ms; p.receives=p.receives+1 end
end
