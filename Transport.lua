local _,G=...
local deflate=LibStub('GuildLedgerDeflate')
G.sequence=0
G.performance={started=G.clock(),sentBytes=0,receivedBytes=0,sentPackets=0,receivedPackets=0,failures=0,peakTick=0,peakReceive=0,totalTick=0,totalReceive=0,ticks=0,receives=0,peakMemory=0}
function G.ResetTransport()
 G.sent={}; G.completed={}; G.controls={}; G.digestRevision=nil; G.digestWork=nil; G.sendBudget=nil
end
G.ResetTransport()
local function queuedBytes()
 local n=0; for _,q in ipairs(G.queue) do n=n+#q.data end
 for _,q in pairs(G.sent) do n=n+#q.data end
 return n
end
function G.WireEncode(v)
 local s=G.Encode(v)
 local compressed=deflate:EncodeForPrint(deflate:CompressDeflate(s,{level=1}))
 return #compressed<#s and 'Z'..compressed or 'R'..s
end
function G.WireDecode(s)
 if #s>G.MAX_WIRE+1 then return end
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
 if not G.ready or target and not G.PeerCompatible(target) then return false end
 value.protocol=G.PROTOCOL
 local ok,s=pcall(G.WireEncode,value)
 if not ok or #s>G.MAX_WIRE then G.errors.sync='Record exceeds transfer limits'; return false end
 if #G.queue>=160 or queuedBytes()+#s>524288 then return false end
 G.sequence=G.sequence+1
 local q={data=s,target=target,channel=channel or 'WHISPER',part=1,total=math.ceil(#s/180),
  id=G.Hash(G.self..G.now()..G.sequence),hash=G.Hash(s),prefix=G.PREFIX}
 if urgent then table.insert(G.queue,G.queue[1] and G.queue[1].part>1 and 2 or 1,q) else G.queue[#G.queue+1]=q end
 return true
end
local function control(msg,target)
 if msg:sub(1,2)=='A|' then
  for _,c in ipairs(G.controls) do
   if c.target==target and c.msg:sub(1,2)=='A|' then
    local pair=msg:sub(3)
    if c.msg:find(pair,1,true) then return end
    if #c.msg+#pair+1<=240 then c.msg=c.msg..','..pair; return end
   end
  end
 end
 if #G.controls<128 then G.controls[#G.controls+1]={msg=msg,target=target,ready=G.clock()+(msg:sub(1,2)=='A|' and 0.4 or 0)} end
end
local function frame(q,part)
 return 'D|'..q.id..'|'..part..'|'..q.total..'|'..q.hash..'|'..q.data:sub((part-1)*180+1,part*180)
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
local function sendOne(now,budget)
 local c=G.controls[1]; local q,part,kind
 if c and (c.ready or 0)<=now then
  if not G.members[c.target] then table.remove(G.controls,1); return false end
  kind='control'
 else
  c=nil
  for _,candidate in pairs(G.sent) do
   if candidate.retryParts and #candidate.retryParts>0 then q=candidate; part=q.retryParts[1]; kind='retry'; break end
  end
  if not q then
   q=G.queue[1]; if not q then return false end
   if q.target and (not G.members[q.target] or not G.PeerCompatible(q.target)) then table.remove(G.queue,1); return false end
   if q.target and q.part==1 and G.Count(G.sent)>=16 then return false end
   part=q.part; kind='data'
  end
 end
 local msg=c and c.msg or frame(q,part); local cost=#msg+#G.PREFIX+16
 if budget.bytes<cost or budget.packets<1 then return false end
 budget.bytes=budget.bytes-cost; budget.packets=budget.packets-1
 local result=G.Safe(C_ChatInfo.SendAddonMessage,c and G.PREFIX or q.prefix,msg,c and 'WHISPER' or q.channel,c and c.target or q.target)
 if Enum.SendAddonMessageResult and result~=Enum.SendAddonMessageResult.Success then
  G.performance.failures=G.performance.failures+1
  budget.failures=math.min(5,(budget.failures or 0)+1); budget.blocked=now+math.min(8,0.5*2^(budget.failures-1)); budget.rate=math.max(2,budget.rate/2)
  -- Keep control and data cursors intact when the client refuses a send.
  local item=c or q; item.failures=(item.failures or 0)+1
  if item.failures>10 then
   if kind=='control' then table.remove(G.controls,1)
   elseif kind=='retry' then G.sent[q.id]=nil
   else table.remove(G.queue,1) end
   G.AnnounceSoon() -- Request timers / duplicate probes recover abandoned work.
  end
  return false
 end
 (c or q).failures=0
 G.performance.sentBytes=G.performance.sentBytes+#msg+#G.PREFIX; G.performance.sentPackets=G.performance.sentPackets+1
 budget.failures=0; budget.rate=math.min(10,budget.rate+0.1)
 if kind=='control' then table.remove(G.controls,1)
 elseif kind=='retry' then table.remove(q.retryParts,1); if #q.retryParts==0 then q.retryParts=nil end
 else
  q.part=q.part+1
  if q.part>q.total then table.remove(G.queue,1); if q.target then q.sentAt=now; G.sent[q.id]=q end end
 end
 return true
end
function G.SyncTick()
 local now=G.clock()
 for k,c in pairs(G.completed) do if now-c.at>120 then G.completed[k]=nil end end
 for k,t in pairs(G.partials) do
  if now-(t.last or t.start)>45 or now-t.start>300 or not G.members[t.sender] then G.partials[k]=nil
  elseif t.channel=='WHISPER' and now-t.last>2 and now-(t.nackAt or -10)>3 then
   local missing={}; for i=1,t.total do if not t.parts[i] and #missing<32 then missing[#missing+1]=i end end
   control('N|'..t.id..'|'..t.hash..'|'..table.concat(missing,','),t.sender); t.nackAt=now
  end
 end
 for id,q in pairs(G.sent) do
  if not G.members[q.target] or not G.PeerCompatible(q.target) or now-q.sentAt>120 then G.sent[id]=nil
  elseif now-(q.retryAt or q.sentAt)>8 and not q.retryParts then
   q.retryParts={q.total}; q.retryAt=now
  end
 end
 G.SyncWork()
 if not G.ready then return end
 local budget=G.sendBudget or {at=now,bytes=512,packets=2,rate=5}; G.sendBudget=budget
 local elapsed=math.max(0,now-budget.at); budget.at=now
 local combat=InCombatLockdown and InCombatLockdown()
 budget.bytes=math.min(512,budget.bytes+elapsed*(combat and 700 or 2000))
 budget.packets=math.min(2,budget.packets+elapsed*(combat and math.min(3,budget.rate) or budget.rate))
 if now<(budget.blocked or 0) then return end
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
