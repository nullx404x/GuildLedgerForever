local _,G=...
G.PROTOCOL=3
G.queue,G.partials,G.peers,G.outstanding={},{},{},{}
G.peerInfo={}; G.sources={}; G.manifestJobs={}; G.completedDigests={}
G.policyTimes={}
-- One lifecycle owner; these three public maps remain read-compatible views for
-- roster/settings callers. Introduction and inventory checks are independent.
G.peerStates={}; G.discoveryPending={}
local function peerState(name)
 local state=G.peerStates[name]
 if not state then state={name=name,detectedAt=G.clock()}; G.peerStates[name]=state end
 state.info=G.peerInfo[name]; state.lastSeen=G.peers[name]; state.checkedDigest=G.completedDigests[name]
 return state
end
local function observePeer(name,info)
 local state=peerState(name)
 if info then G.peerInfo[name]=info; state.info=info end
 G.peers[name]=G.now(); state.lastSeen=G.now()
 if state.info then G.discoveryPending[name]=nil
 elseif not state.checkedDigest then G.discoveryPending[name]=state end
 return state
end
local function checkedPeer(name,digest)
 if not digest then return end
 G.completedDigests[name]=digest; peerState(name).checkedDigest=digest
 G.discoveryPending[name]=nil
end
function G.PeerSyncState(name)
 if not G.peers[name] then return end
 local state=peerState(name); local info=state.info
 state.introduction=info and info.version and 'identified' or 'detected'
 state.advertisedDigest=info and info.digest
 -- Status rendering must not count/fingerprint every record once per peer.
 local digest=G.digestRevision==G.dataRevision and G.digest or nil
 local checked=state.checkedDigest and (not state.advertisedDigest or state.checkedDigest==state.advertisedDigest)
  or state.advertisedDigest and state.advertisedDigest==digest
 state.background=G.manifestJobs[name] and 'receiving' or checked and 'checked' or 'pending'
 state.phase=info and info.protocol~=G.PROTOCOL and 'incompatible'
  or state.background~='pending' and state.background or state.introduction
 return state
end
function G.ForgetPeer(name)
 G.peerStates[name]=nil; G.discoveryPending[name]=nil
 G.peers[name]=nil; G.peerInfo[name]=nil; G.completedDigests[name]=nil
 G.policyTimes[name]=nil; G.manifestJobs[name]=nil; G.sources[name]=nil
 if G.sourceBackoff then G.sourceBackoff[name]=nil end
 if G.offerTimes then G.offerTimes[name]=nil end
 if G.rates then G.rates[name]=nil end
 if G.bookPeers then G.bookPeers[name]=nil end
 for id,hint in pairs(G.priorityChanges or {}) do if hint.sender==name then G.priorityChanges[id]=nil end end
 for _,prefix in ipairs({'offer:','policy:','manifestReady:'}) do
  local key=prefix..name; if G.timers[key] then G.timers[key]:Cancel(); G.timers[key]=nil end
 end
end
function G.ResetPeers()
 for name in pairs(G.peerStates) do G.ForgetPeer(name) end
 for name in pairs(G.peers) do G.ForgetPeer(name) end
 G.peerStates={}; G.discoveryPending={}; G.discoveryNextAt=nil; G.discoveryReplyNextAt=nil
 G.peers={}; G.peerInfo={}; G.completedDigests={}
 G.priorityChanges={}
end
G.pendingRecords={}; G.definitionRequests={}
G.priorityChanges={}
-- Live announcements are never stored, relayed or included in catch-up.
G.announcementSeen={}
function G.AnnouncementText(text)
 if type(text)~='string' or #text>160 or text:find('|',1,true) then return nil end
 text=text:gsub('%c',' '):gsub('%s+',' '):match('^%s*(.-)%s*$')
 return text~='' and text or nil
end
function G.ShowAnnouncement(text,sender,preview,sound)
 local message=(preview and '[Preview] ' or '[Guild] ')..G.Plain(sender)..': '..text
 local color={r=0.88,g=0.73,b=0.43}
 local ok=false
 if RaidWarningUtil and type(RaidWarningUtil.AddMessage)=='function' then
  ok=pcall(RaidWarningUtil.AddMessage,message,color,4)
 elseif RaidWarningFrame and type(RaidWarningFrame.AddMessage)=='function' then
  ok=pcall(RaidWarningFrame.AddMessage,RaidWarningFrame,message,color,4)
 elseif type(RaidNotice_AddMessage)=='function' and RaidWarningFrame then
  ok=pcall(RaidNotice_AddMessage,RaidWarningFrame,message,color,4)
 end
 if ok and sound~=false and SOUNDKIT and SOUNDKIT.RAID_WARNING then G.Safe(PlaySound,SOUNDKIT.RAID_WARNING) end
 return ok
end
function G.PreviewAnnouncement(text)
 text=G.AnnouncementText(text)
 if not G.IsAnnouncer(G.self) then return false,'Announcement permission is required.' end
 if not text then return false,'Enter a short message using plain text only.' end
 if not G.ShowAnnouncement(text,G.self,true,G.db.settings.announcementSound~=false) then return false,'The built-in raid warning display is unavailable.' end
 return true,'Preview shown only to you.'
end
function G.SendAnnouncement(text)
 if not G.IsAnnouncer(G.self) then return false,'Announcement permission is required.' end
 if not G.AnnouncementsEnabled() then return false,'Guild announcements are turned off.' end
 text=G.AnnouncementText(text)
 if not text then return false,'Enter a short message using plain text only.' end
 local id=G.Hash(G.self..G.now()..G.clock()..(G.sequence or 0))
 local sound=G.db.settings.announcementSound~=false
 if not G.Send({type='announcement',scope=G.scope,id=id,stamp=G.now(),text=text,sound=sound},nil,'GUILD',true) then
  return false,'Could not send. Wait for guild sync and try again.'
 end
 G.ShowAnnouncement(text,G.self,false,sound)
 return true,'Sent to online members using this update.'
end
function G.ReceiveAnnouncement(v,sender)
 if not G.AnnouncementsEnabled() or not G.IsAnnouncer(sender) or v.sound~=nil and type(v.sound)~='boolean' or type(v.id)~='string' or not v.id:match('^%x%x%x%x%x%x%x%x$') or type(v.stamp)~='number' or v.stamp%1~=0 or v.stamp>G.now()+5 or G.now()-v.stamp>15 then return end
 local text=G.AnnouncementText(v.text); if not text then return end
 local now=G.clock()
 for key,at in pairs(G.announcementSeen) do if now-at>30 then G.announcementSeen[key]=nil end end
 local key=sender..':'..v.id
 if G.announcementSeen[key] then return end
 G.announcementSeen[key]=now
 G.ShowAnnouncement(text,sender,false,v.sound)
end
function G.PeerCompatible(name)
 local p=G.peerInfo[name]; return not p or p.protocol==3
end
function G.VersionCompare(a,b)
 local function parts(v)
  if type(v)~='string' then return end
  local x,y,z=v:match('^(%d+)%.(%d+)%.(%d+)$')
  if x then return {tonumber(x),tonumber(y),tonumber(z)} end
 end
 local x,y=parts(a),parts(b); if not x or not y then return end
 for i=1,3 do if x[i]~=y[i] then return x[i]<y[i] and -1 or 1 end end
 return 0
end
function G.PeerStatus(name)
 local p=G.peerInfo[name]
 if not p then return 'Version unknown' end
 if not p.protocol then return 'Update required (0.4.0+)' end
 local c=G.VersionCompare(p.version,G.VERSION)
 return not c and 'Version unknown' or c<0 and 'Older version' or c>0 and 'Newer version' or 'Current version'
end
function G.Digest()
 if G.digestRevision~=G.dataRevision then
  local rows,legacy={},{}
  for _,id in ipairs(G.SharedRecordKeys()) do
   local r=G.store.records[id]; local piece=id..'='..G.Token(r)
   legacy[#legacy+1]=piece; if r.kind~='gear' then rows[#rows+1]=piece end
  end
  G.digest=G.Hash(table.concat(rows,';')); G.legacyDigest=G.Hash(table.concat(legacy,';')); G.digestRevision=G.dataRevision
 end
 return G.digest
end
-- Network discovery must not fingerprint an entire cold cache in one frame.
function G.NetworkDigest()
 if G.digestRevision==G.dataRevision then return G.digest end
 if G.Count(G.store.records)<=32 then return G.Digest() end
end
function G.LegacyNetworkDigest()
 if G.NetworkDigest() then return G.legacyDigest end
end
local function digestWork()
 if G.digestRevision==G.dataRevision then G.digestWork=nil; return end
 local work=G.digestWork
 if not work then work={keys=G.SharedRecordKeys(),cursor=1,hash=5381,legacyHash=5381,backgroundCount=0,revision=G.dataRevision}; G.digestWork=work end
 for i=1,24 do
  local id=work.keys[work.cursor]
  if not id then
   if work.revision==G.dataRevision then
    G.digest=string.format('%08x',work.hash); G.legacyDigest=string.format('%08x',work.legacyHash); G.digestRevision=work.revision
   end
   G.digestWork=nil; return
  end
  local r=G.store.records[id]
  if r then
   local piece=id..'='..G.Token(r)
   local legacy=(work.cursor>1 and ';' or '')..piece
   for j=1,#legacy do work.legacyHash=(work.legacyHash*33+legacy:byte(j))%2147483647 end
   if r.kind~='gear' then
    piece=(work.backgroundCount>0 and ';' or '')..piece
    for j=1,#piece do work.hash=(work.hash*33+piece:byte(j))%2147483647 end
    work.backgroundCount=work.backgroundCount+1
   end
  end
  work.cursor=work.cursor+1
 end
end
-- Guild configuration is independent of the record inventory. A missed policy
-- message must still recover when both members already have matching records.
function G.PolicyDigest()
 local s=G.store or {}
 local guild={G.DiscordInvite(),s.inviteRevision or 0,s.officerRanks or {},G.GuildLootEnabled(),s.lootEnabledRevision or 0,
  G.AnnouncementsEnabled(),G.AnnouncementRanks(),s.announcementRevision or 0}
 return G.Hash(G.Encode(guild))..G.Hash(G.Encode({G.GreenCaptureEnabled(),s.policyRevision or 0}))
end
function G.Hello(kind,target)
 local catchingUp=false; for _,job in pairs(G.manifestJobs) do if not job.incremental and G.clock()-(job.progress or 0)<45 then catchingUp=true; break end end
 local gear=G.store and G.store.records['gear:'..G.self]
 return {type=kind or 'hello',scope=G.scope,target=target,version=G.VERSION,protocol=G.PROTOCOL,beacon=true,digest=G.LegacyNetworkDigest(),inventory=G.NetworkDigest(),gear=gear and G.Token(gear) or '',
  policy=G.PolicyDigest()..'/'..tostring(G.store and G.store.policyRevision or 0),catchingUp=catchingUp}
end
local function discoveryKind()
 -- A single compatible broadcast serves every older peer. Never send a copy to
 -- every member, and return to compact discovery when legacy peers leave.
 for name,seen in pairs(G.peers) do
  local info=G.peerInfo[name]
  if G.members[name] and G.members[name].online~=false and G.now()-seen<600
   and G.PeerCompatible(name) and (not info or not info.beacon) then return 'hello' end
 end
 return 'beacon'
end
local function recoverPolicy(target)
 if not G.IsOfficer(G.self) then return end
 local info=G.peerInfo[target]; local theirs=info and info.policy
 local ours=G.PolicyDigest(); local leader=G.IsGuildLeader(G.self)
 local guildChanged=leader and (not theirs or ours:sub(1,8)~=theirs:sub(1,8))
 local lootChanged=not theirs or ours:sub(9)~=theirs:sub(9)
 local revision=G.store.policyRevision or 0
 if theirs and (info.policyRevision>revision or info.policyRevision==revision and G.GreenCaptureEnabled()) then lootChanged=false end
 if not guildChanged and not lootChanged then return end
 -- One known authority with the same loot policy answers, rather than every
 -- officer replying to the same member. The guild master handles their settings.
 if not leader then
  for name,p in pairs(G.peerInfo) do
   if name~=target and G.IsOfficer(name) and G.members[name].online~=false and G.peers[name] and G.now()-G.peers[name]<300
    and G.PeerCompatible(name) and p.policy and p.policy:sub(9)==ours:sub(9)
    and (G.IsGuildLeader(name) or name<G.self) then return end
  end
 end
 local wait=theirs and 60 or 300
 if G.clock()-(G.policyTimes[target] or -300)<wait then return end
 G.policyTimes[target]=G.clock()
 local scope=G.scope
 G.After('policy:'..target,1+(tonumber(G.Hash(G.self..target),16)%40)/10,function()
  if G.ready and G.scope==scope and G.members[target] then G.SendGuildInvite(target); G.SendLootPolicy(target) end
 end)
end
function G.AnnounceSoon()
 if G.timers.announce then return end
 G.After('announce',math.max(3,60-(G.clock()-(G.lastHello or -60))),function()
  if G.ready then
   if not G.NetworkDigest() then G.AnnounceSoon(); return end
   G.lastHello=G.clock(); G.Send(G.Hello(discoveryKind()),nil,'GUILD')
  end
 end)
end
-- Prefer one source. A second is allowed only after the first stops progressing.
function G.Manifest(target)
 if not G.members[target] or not G.PeerCompatible(target) or G.manifestJobs[target] or G.Count(G.manifestJobs)>=4 then return end
 if G.sourceBackoff and (G.sourceBackoff[target] or 0)>G.clock() then return end
 -- A changed cache is fingerprinted over several ticks. Wait for that comparison
 -- instead of starting a full catch-up merely because the local digest is pending.
 if not G.NetworkDigest() then
  local key='manifestReady:'..target
  if not G.timers[key] then G.After(key,3,function() if G.ready then G.Manifest(target) end end) end
  return
 end
 local active=0
 for _,job in pairs(G.manifestJobs) do
  if not job.incremental then
   active=active+1
   if G.clock()-(job.progress or 0)<45 then return end
  end
 end
 if active>=2 then return end
 local info=G.peerInfo[target]
 if info and info.catchingUp then return end
 if info and info.digest and (G.completedDigests[target]==info.digest or G.NetworkDigest()==info.digest) then checkedPeer(target,info.digest); return end
 G.manifestJobs[target]={cursor=1,at=-100,digest=info and info.digest,scope=G.scope,progress=G.clock(),session=G.Hash(G.self..target..G.clock()),pages={},pageRequests={},finished=0,focus=G.SyncFocus(),focusAt=G.clock()}
end
local function retrySource(target)
 G.sourceBackoff=G.sourceBackoff or {}
 G.sourceBackoff[target]=G.clock()+60+(tonumber(G.Hash(G.self..target),16)%30)
 G.manifestJobs[target]=nil
 G.retrySourceAt=G.clock()+2+(tonumber(G.Hash(target..G.self),16)%50)/10
end
-- Roster refreshes can discard a guild heartbeat while reliable whispers still
-- work. Bootstrap only peers we have actually heard, without polling the roster.
local function discoveryWork()
 if not next(G.discoveryPending) then return end
 local now=G.clock()
 if now<(G.discoveryNextAt or 0) or #G.queue>=8 or G.Count(G.outstanding)>=24 or not G.NetworkDigest() then return end
 G.discoveryNextAt=now+5
 local candidate,oldest
 for target,state in pairs(G.discoveryPending) do
  if not G.members[target] or not G.peers[target] or G.peerInfo[target] or G.completedDigests[target] then G.discoveryPending[target]=nil
  elseif G.members[target].online~=false then
   local attempt=state.lastAttempt or -60
   if now-state.detectedAt>=3 and now-attempt>=60 and now>=(G.sourceBackoff[target] or 0)
    and (not candidate or attempt<oldest or attempt==oldest and target<candidate) then
    candidate,oldest=target,attempt
   end
  end
 end
 if candidate then
  local hello=G.Hello('hello',candidate); hello.requestHello=true
  if G.Send(hello,candidate) then
   peerState(candidate).lastAttempt=now
   -- Older clients understand this catch-up even without the optional reply.
   G.Manifest(candidate)
  end
 end
end
function G.SyncFocus()
 local ui=G.UI
 if ui and ui.frame and ui.frame:IsShown() then return ui.tab end
 return 'Roster'
end
function G.WantGear(owner)
 if not G.ready or not G.members[owner] or owner==G.self then return end
 local demand=G.gearDemand
 if not demand or demand.owner~=owner or G.clock()-demand.started>60 then
  G.gearDemand={owner=owner,started=G.clock(),nextAt=0,tried={},attempts=0}
 elseif demand.failed and demand.attempts<6 then
  for name in pairs(G.peers) do
   if G.members[name] and G.PeerCompatible(name) and not demand.tried[name] then demand.failed=nil; demand.nextAt=0; break end
  end
 end
end
local function gearWork()
 local d=G.gearDemand
 if not d or d.done or d.failed or G.clock()<d.nextAt or #G.queue>=8 or G.Count(G.outstanding)>=24 then return end
 if not G.members[d.owner] then G.gearDemand=nil; return end
 local peer
 if G.peers[d.owner] and G.PeerCompatible(d.owner) and not d.tried[d.owner] then peer=d.owner end
 if not peer then for name in pairs(G.peers) do if G.members[name] and G.PeerCompatible(name) and not d.tried[name] then peer=name; break end end end
 if not peer or d.attempts>=6 then d.failed=true; G.Refresh(); return end
 local id='gear:'..d.owner; local r=G.store.records[id]
 if G.Send({type='request',scope=G.scope,rows={{id=id,base=r and G.Token(r)}},urgent=true},peer,nil,true) then
  d.tried[peer]=true; d.attempts=d.attempts+1; d.nextAt=G.clock()+10
  G.outstanding[id]={at=G.clock(),sender=peer}
 end
end
local function deferredGear(id)
 if id:sub(1,5)=='loot:' and not G.GuildLootEnabled() then return true end
 return id:sub(1,5)=='gear:' and not G.store.records[id] and not (G.gearDemand and id=='gear:'..G.gearDemand.owner)
end
-- Sort once per source snapshot; useful online details arrive before bulk books.
local function priorityKeys(focus,includeGear)
 local keys={}; local ranks={}
 for _,id in ipairs(G.SharedRecordKeys()) do if includeGear or G.store.records[id].kind~='gear' then keys[#keys+1]=id end end
 local loot={}; for _,id in ipairs(keys) do if G.store.records[id].kind=='loot' then loot[#loot+1]=id end end
 table.sort(loot,function(a,b) local x,y=G.store.records[a],G.store.records[b]; if x.stamp~=y.stamp then return x.stamp>y.stamp end; return a<b end)
 local recent={}; for i=1,math.min(20,#loot) do recent[loot[i]]=true end
 for _,id in ipairs(keys) do
  local r=G.store.records[id]; local online=G.members[r.owner] and G.members[r.owner].online
  ranks[id]=r.kind=='profile' and (online and 1 or 3) or recent[id] and 2 or r.kind=='profession' and (online and 4 or 5) or r.kind=='loot' and 6 or 7
  if focus=='Crafting' then ranks[id]=r.kind=='profession' and (online and 1 or 2) or ranks[id]+3
  elseif focus=='Guild Loot' then ranks[id]=r.kind=='loot' and (recent[id] and 1 or 2) or ranks[id]+3 end
 end
 table.sort(keys,function(a,b)
  if ranks[a]~=ranks[b] then return ranks[a]<ranks[b] end
  if G.store.records[a].kind=='loot' and G.store.records[b].kind=='loot' and G.store.records[a].stamp~=G.store.records[b].stamp then return G.store.records[a].stamp>G.store.records[b].stamp end
  return a<b
 end)
 return keys
end
function G.SyncProgress()
 for _,job in pairs(G.manifestJobs) do
  if not job.incremental then
   local n=job.finished or 0
   for _,row in ipairs(job.rows or {}) do
    local r=G.store.records[row.id]
    if row.absent or deferredGear(row.id) or r and (r.rev>tonumber(row.token:match('^(%d+)/')) or G.Token(r)==row.token) or job.resolved and job.resolved[row.id]==row.token then n=n+1 end
   end
   return job.total and ('Checking guild records: '..n..' / '..job.total) or 'Checking guild cache…'
  end
 end
end
local function finish(id) G.outstanding[id]=nil; G.pendingRecords[id]=nil end
local function receiveRecord(p,sender)
 if type(p)~='table' or type(p.id)~='string' or #p.id>180 then return end
 local r,reason=G.UnpackRecord(p)
 if r then
  if G.Validate(r) then
   if G.Accept(r) then G.AnnounceSoon() end
   local hint=G.priorityChanges[r.id]; local current=G.store.records[r.id]
   if hint and current and (current.rev>hint.rev or G.Token(current)==hint.token
    or r.rev==hint.rev and G.Token(r)==hint.token) then G.priorityChanges[r.id]=nil end
   if r.kind=='gear' and G.gearDemand and G.gearDemand.owner==r.owner then G.gearDemand.done=true; G.Refresh() end
   local job=G.manifestJobs[sender]
   if job then job.progress=G.clock(); job.resolved=job.resolved or {}; job.resolved[p.id]=G.Token(r) end
   finish(p.id)
  end
 elseif reason=='missing' and G.Count(G.pendingRecords)<32 then
  G.pendingRecords[p.id]={record=p,sender=sender,at=G.clock()}
 end
end
local function sendBatches(kind,field,values,target,urgent)
 local batch={}; local size=0
 local function send()
  if #batch==0 then return end
  local v={type=kind,scope=G.scope}; v[field]=batch; G.Send(v,target,nil,urgent); batch={}; size=0
 end
 for _,value in ipairs(values) do
  local n=#G.Encode(value)
  if #batch>=8 or size+n>90000 then send() end
  batch[#batch+1]=value; size=size+n
 end
 send()
end
local function rememberChange(row,sender)
 local id=row.id; local profession='profession:'..sender..':'
 local current=G.store.records[id]
 local professionID=id:sub(1,#profession)==profession and tonumber(id:sub(#profession+1):match('^%d+$'))
 local own=id=='profile:'..sender or professionID and professionID<=1e7
  or id=='gear:'..sender and (current or G.gearDemand and G.gearDemand.owner==sender)
 if not own then return end
 local rev=tonumber(row.token:match('^(%d+)/'))
 if not rev or rev>1e14 then return end
 if current and (current.rev>rev or G.Token(current)==row.token) then return end
 local old=G.priorityChanges[id]
 if old and old.rev>=rev then return end
 if not old and G.Count(G.priorityChanges)>=64 then return end
 G.priorityChanges[id]={sender=sender,token=row.token,rev=rev,at=G.clock(),scope=G.scope}
end
local function priorityWork()
 if not next(G.priorityChanges) then return end
 local target; local rows={}; local now=G.clock()
 local space=math.min(8,24-G.Count(G.outstanding))
 for id,hint in pairs(G.priorityChanges) do
  local current=G.store.records[id]; local member=G.members[hint.sender]
  if hint.scope~=G.scope or not member or member.online==false or now-hint.at>180
   or current and (current.rev>hint.rev or G.Token(current)==hint.token) then G.priorityChanges[id]=nil
  elseif #G.queue<8 and space>0 and not G.outstanding[id] and G.PeerCompatible(hint.sender)
   and (not target or target==hint.sender) then
   target=hint.sender; rows[#rows+1]={id=id,base=current and G.Token(current)}; space=space-1
  end
 end
 if target and G.Send({type='request',scope=G.scope,rows=rows},target,nil,true) then
  for _,row in ipairs(rows) do G.outstanding[row.id]={at=now,sender=target} end
 end
end
function G.Handle(v,sender)
 if type(v)~='table' or v.scope~=G.scope or not G.members[sender] then return end
 if v.type=='beacon' then v.type='hello' end
 if v.type=='hello' or v.type=='offer' then
  if type(v.protocol)~='number' or v.protocol%1~=0 or v.protocol<1 or v.protocol>10000 then return end
  local version=type(v.version)=='string' and #v.version<=32 and v.version:match('^%d+%.%d+%.%d+$') and v.version or nil
  local policy,policyRevision
  if type(v.policy)=='string' and #v.policy<=32 then
   local hash,rev=v.policy:match('^(%x+)/(%d+)$'); rev=tonumber(rev)
   if hash and #hash==16 and rev and rev<=(G.now()+300)*1000 then policy,policyRevision=hash,rev end
  end
  local inventory=type(v.inventory)=='string' and #v.inventory==8 and v.inventory or nil
  local previous=G.peerInfo[sender]
  local info={version=version,protocol=v.protocol==G.PROTOCOL and G.PROTOCOL or nil,catchingUp=v.catchingUp==true,beacon=v.beacon==true,
   digest=inventory or type(v.digest)=='string' and #v.digest==8 and v.digest or nil,inventory=inventory,
   policy=policy,policyRevision=policyRevision}
  observePeer(sender,info)
  -- An older client cannot decode the compact beacon. Its first introduction
  -- schedules one compatible guild broadcast, even if inventories already match.
  if not info.beacon and info.protocol==G.PROTOCOL and (not previous or previous.beacon) then G.AnnounceSoon() end
  if not G.PeerCompatible(sender) then G.manifestJobs[sender]=nil; G.Refresh(); return end
 end
 if not G.PeerCompatible(sender) or v.protocol and v.protocol~=G.PROTOCOL then return end
 local state=observePeer(sender); G.lastContact=G.now()
 if v.type=='announcement' then G.ReceiveAnnouncement(v,sender); return end
    if v.type=="guildInvite" then
        if not G.IsGuildLeader(sender) or type(v.revision)~="number" or v.revision%1~=0 or v.revision<0 or v.revision>(G.now()+300)*1000 then return end
        local invite=G.NormalizeInvite(v.invite)
        if invite and v.revision>(G.store.inviteRevision or -1) then
            G.store.discordInvite=invite; G.store.inviteRevision=v.revision; G.Refresh()
        end
        return
    elseif v.type=="officerAccess" then
        if not G.IsGuildLeader(sender) or type(v.ranks)~="table" then return end
        local ranks={}; for k,value in pairs(v.ranks) do
            if type(k)~="number" or k<2 or k>10 or k%1~=0 or value~=true then return end
            ranks[k]=true
        end
        G.store.officerRanks=ranks; G.Refresh(); return
    elseif v.type=="announcementPolicy" then
        if not G.IsGuildLeader(sender) or type(v.enabled)~="boolean" or type(v.ranks)~="table" or type(v.revision)~="number" or v.revision%1~=0 or v.revision<0 or v.revision>(G.now()+300)*1000 then return end
        local ranks={}
        for k,value in pairs(v.ranks) do
            if type(k)~="number" or k%1~=0 or k<2 or k>10 or value~=true then return end
            ranks[k]=true
        end
        if v.revision>(G.store.announcementRevision or -1) then
            G.store.announcementsEnabled=v.enabled; G.store.announcementRanks=ranks; G.store.announcementRevision=v.revision; G.Refresh()
        end
        return
    elseif v.type=="lootEnabled" then
        if not G.IsGuildLeader(sender) or type(v.enabled)~="boolean" or type(v.revision)~="number" or v.revision%1~=0 or v.revision<0 or v.revision>(G.now()+300)*1000 then return end
        if v.revision>(G.store.lootEnabledRevision or -1) then G.ApplyLootEnabled(v.enabled,v.revision) end
        return
    elseif v.type=="lootPolicy" then
        if not G.IsOfficer(sender) or type(v.greens)~="boolean" or type(v.revision)~="number" or v.revision%1~=0 or v.revision<0 or v.revision>(G.now()+300)*1000 then return end
        if v.revision>(G.store.policyRevision or -1) or v.revision==G.store.policyRevision and not v.greens and G.store.captureGreens then
            G.store.captureGreens=v.greens; G.store.policyRevision=v.revision; G.Refresh()
        end
        return
    end

 if v.type=='hello' then
  G.Manifest(sender)
  recoverPolicy(sender)
  if v.requestHello==true and v.target==G.self and G.clock()>=(G.discoveryReplyNextAt or 0)
   and G.clock()-(state.lastReply or -60)>=60 and #G.queue<8 then
   if G.Send(G.Hello('offer',sender),sender) then
    state.lastReply=G.clock(); G.discoveryReplyNextAt=G.clock()+5
   end
  end
  -- Gear is fetched on demand, but an already viewed character stays fresh even
  -- if its change notice was missed. Other members' gear is never pulled here.
  local id='gear:'..sender; local old=G.store.records[id]
  local rev=type(v.gear)=='string' and #v.gear<=50 and v.gear:match('^(%d+)/%x%x%x%x%x%x%x%x$')
  if old and rev and old.rev<=tonumber(rev) and G.Token(old)~=v.gear and not G.outstanding[id] and #G.queue<8 and G.Count(G.outstanding)<24 then
   if G.Send({type='request',scope=G.scope,rows={{id=id,base=G.Token(old)}}},sender) then G.outstanding[id]={at=G.clock(),sender=sender} end
  end
  -- Receiving the heartbeat already records presence. Matching inventories need
  -- no reply, including first contact, so simultaneous logins cannot fan out.
  if G.peerInfo[sender].digest and G.peerInfo[sender].digest==G.NetworkDigest() then return end
  local key='offer:'..sender
  if G.clock()-(G.offerTimes and G.offerTimes[sender] or -90)<45 then return end
  G.offerTimes=G.offerTimes or {}; G.offerTimes[sender]=G.clock()
  G.After(key,1+(tonumber(G.Hash(sender..G.self..math.floor(G.now()/60)),16)%900)/100,function()
   if not G.ready or not G.members[sender] then return end
   G.Send(G.Hello('offer',sender),nil,'GUILD'); G.Manifest(sender)
   recoverPolicy(sender)
  end)
 elseif v.type=='offer' and type(v.target)=='string' then
  local key='offer:'..v.target
  if G.timers[key] then G.timers[key]:Cancel(); G.timers[key]=nil end
  if v.target==G.self then G.Manifest(sender); recoverPolicy(sender) end
 elseif v.type=='changes' and type(v.rows)=='table' and #v.rows<=32 then
  for _,row in ipairs(v.rows) do
   if type(row)~='table' or type(row.id)~='string' or #row.id>180 or type(row.token)~='string' or #row.token>50 or not row.token:match('^%d+/%x%x%x%x%x%x%x%x$') then return end
  end
  local inventory=type(v.inventory)=='string' and #v.inventory==8 and v.inventory or nil
  local base=inventory and v.baseInventory or v.baseDigest
  local digest=inventory or v.digest
  local matched=type(base)=='string' and G.completedDigests[sender]==base
  -- Small self-owned profile/loot records ride one existing guild notice. Apply
  -- them before source-slot checks, so an active catch-up cannot hide a change.
  -- Older clients ignore this optional field and use their normal request path.
  for _,row in ipairs(v.rows) do
   local r=row.record
   if type(r)=='table' and (r.kind=='loot' or r.kind=='profile') and r.owner==sender and r.id==row.id
    and G.Validate(r) and G.Token(r)==row.token then G.Accept(r) end
   rememberChange(row,sender)
  end
  if G.manifestJobs[sender] or G.Count(G.manifestJobs)>=4 then return end
  G.manifestJobs[sender]={rows=v.rows,done=true,scope=G.scope,progress=G.clock(),at=G.clock(),cursor=0,incremental=true,
   digest=matched and type(digest)=='string' and #digest==8 and digest or nil,resolved={}}
 elseif v.type=='manifestRequest' then
  if type(v.cursor)~='number' or v.cursor%1~=0 or v.cursor<1 or v.cursor>12001 then return end
  local source=G.sources[sender]
  if v.session~=nil and (type(v.session)~='string' or #v.session~=8) then return end
  if v.cursor==1 and (not source or source.session~=v.session) then
   if not source and G.Count(G.sources)>=4 then
    G.Send({type='busy',scope=G.scope,session=v.session},sender)
    return
   end
   local focus=({Roster=true,Crafting=true,['Guild Loot']=true})[v.focus] and v.focus or 'Roster'
   local legacy=not (G.peerInfo[sender] and G.peerInfo[sender].inventory)
   source={keys=priorityKeys(focus,legacy),digest=legacy and G.LegacyNetworkDigest() or G.NetworkDigest(),legacy=legacy,revision=G.dataRevision,at=G.clock(),session=v.session}; G.sources[sender]=source
  end
  if not source or source.session~=v.session then G.Send({type='restart',scope=G.scope,session=v.session},sender); return end
  source.at=G.clock(); local rows={}
  if source.revision==G.dataRevision then source.digest=source.digest or (source.legacy and G.LegacyNetworkDigest() or G.NetworkDigest()) end
  for i=v.cursor,math.min(v.cursor+31,#source.keys) do
   local r=G.store.records[source.keys[i]]; if r then rows[#rows+1]={id=r.id,token=G.Token(r)} end
  end
  G.Send({type='manifest',scope=G.scope,rows=rows,cursor=v.cursor,nextCursor=v.cursor+32,done=v.cursor+32>#source.keys,digest=source.digest,total=#source.keys,session=source.session},sender)
 elseif v.type=='busy' then
  local job=G.manifestJobs[sender]
  if job and not job.incremental and job.session==v.session then retrySource(sender) end
 elseif v.type=='restart' then
  local job=G.manifestJobs[sender]
  if job and not job.incremental and v.session==job.session then
   job.session=G.Hash(job.session..G.clock()..'restart'); job.cursor=1; job.rows=nil; job.resolved=nil
   job.at=-100; job.pages={}; job.pageRequests={}; job.finished=0; job.total=nil
  end
 elseif v.type=='manifest' then
  local job=G.manifestJobs[sender]
  if not job or job.incremental or v.session~=job.session or type(v.cursor)~='number' or v.cursor<job.cursor or v.cursor>job.cursor+64 or (v.cursor-job.cursor)%32~=0 or type(v.rows)~='table' or #v.rows>32 or v.nextCursor~=v.cursor+32 or type(v.done)~='boolean' or type(v.total)~='number' or v.total%1~=0 or v.total<0 or v.total>12000 or v.digest~=nil and (type(v.digest)~='string' or #v.digest~=8) then return end
  for _,row in ipairs(v.rows) do
   if type(row)~='table' or type(row.id)~='string' or #row.id>180 or type(row.token)~='string' or #row.token>50 or not row.token:match('^%d+/%x%x%x%x%x%x%x%x$') then return end
  end
  job.progress=G.clock(); job.pages[v.cursor]=v; job.total=v.total; job.pageRequests[v.cursor]=nil
 elseif v.type=='request' and type(v.rows)=='table' and #v.rows<=8 then
  local entries={}
  for _,row in ipairs(v.rows) do
   if type(row)=='table' and type(row.id)=='string' then
    local r=G.store.records[row.id]
    if G.ShareRecord(r) then
     local entry=G.MakeTransfer(r,row.base)
     if entry.record then entry=G.BookTransfer(entry.record,sender,row.full==true) end
     entries[#entries+1]=entry
    else G.Send({type='absent',scope=G.scope,id=row.id},sender) end
   end
  end
  sendBatches('records','entries',entries,sender,v.urgent==true)
 elseif v.type=='bookKnown' and type(v.key)=='string' then
  local peer=G.bookPeers[sender]
  if peer and G.bookTemplates[v.key] and G.Count(peer.known)<128 then peer.known[v.key]=true end
 elseif v.type=='absent' and type(v.id)=='string' then
  if G.outstanding[v.id] and G.outstanding[v.id].sender==sender then
   if G.priorityChanges[v.id] and G.priorityChanges[v.id].sender==sender then G.priorityChanges[v.id]=nil end
   local job=G.manifestJobs[sender]
   if job and job.rows then for _,row in ipairs(job.rows) do if row.id==v.id then row.absent=true end end end
   finish(v.id)
  end
 elseif v.type=='records' and type(v.entries)=='table' and #v.entries<=8 then
  for _,entry in ipairs(v.entries) do
   if type(entry)=='table' then
    if entry.record then receiveRecord(entry.record,sender)
    elseif entry.book then
     local p,reason=G.ApplyBook(entry.book)
     if p then
      receiveRecord(p,sender)
      if entry.book.keys then G.Send({type='bookKnown',scope=G.scope,key=entry.book.template},sender) end
     elseif reason=='missing' then G.Send({type='request',scope=G.scope,rows={{id=entry.book.record.id,full=true}}},sender) end
    elseif entry.delta then
     local p=G.ApplyDelta(entry.delta)
     if p then receiveRecord(p,sender)
     elseif type(entry.delta.id)=='string' then G.Send({type='request',scope=G.scope,rows={{id=entry.delta.id}}},sender) end
    end
   end
  end
 elseif v.type=='definitionsRequest' and type(v.keys)=='table' and #v.keys<=20 then
  local entries={}
  for _,key in ipairs(v.keys) do if type(key)=='string' and G.recipePool[key] then entries[#entries+1]={key=key,recipe=G.recipePool[key]} end end
  sendBatches('definitions','entries',entries,sender)
 elseif v.type=='definitions' and type(v.entries)=='table' and #v.entries<=8 then
  for _,entry in ipairs(v.entries) do
   if type(entry)=='table' and G.definitionRequests[entry.key] and G.AddDefinition(entry.key,entry.recipe) then G.definitionRequests[entry.key]=nil end
  end
 end
 G.Refresh()
end
function G.SyncWork()
 if G.sourceBackoff then
  for name,untilTime in pairs(G.sourceBackoff) do if untilTime<=G.clock() or not G.members[name] then G.sourceBackoff[name]=nil end end
 end
 -- Recover from old clients that silently ignore requests when their slots fill.
 for target,job in pairs(G.manifestJobs) do
  if not job.incremental and G.clock()-(job.progress or 0)>90 then retrySource(target) end
 end
 for name,t in pairs(G.peers) do if not G.members[name] or G.now()-t>600 then G.ForgetPeer(name) end end
 for name,s in pairs(G.sources) do if G.clock()-s.at>300 or not G.members[name] then G.sources[name]=nil end end
 for id,h in pairs(G.history) do if G.clock()-h.at>600 then G.historyBytes=G.historyBytes-h.size; G.history[id]=nil end end
 for id,t in pairs(G.outstanding) do if G.clock()-t.at>(G.pendingRecords[id] and 300 or 60) then finish(id) end end
 for key,t in pairs(G.definitionRequests) do if G.clock()-t>15 then G.definitionRequests[key]=nil end end
 if not G.ready then return end
 G.PruneBookTemplates(); gearWork()
 digestWork()
 discoveryWork()
 priorityWork()
 if G.retrySourceAt and G.clock()>=G.retrySourceAt then
  G.retrySourceAt=G.clock()+5
  local candidates=G.Keys(G.peerInfo)
  table.sort(candidates,function(a,b) return G.Hash(G.self..a)<G.Hash(G.self..b) end)
  for _,target in ipairs(candidates) do G.Manifest(target) end
  for _,job in pairs(G.manifestJobs) do if not job.incremental then G.retrySourceAt=nil; break end end
  if G.retrySourceAt then
   local pending=false
   for _,target in ipairs(candidates) do
    local info=G.peerInfo[target]
    if G.members[target] and G.PeerCompatible(target) and info.digest~=G.NetworkDigest() and G.completedDigests[target]~=info.digest then pending=true; break end
   end
   if not pending then G.retrySourceAt=nil end
  end
 end
 for id,pending in pairs(G.pendingRecords) do
  if G.clock()-pending.at>300 or not G.members[pending.sender] then finish(id)
  else
   local r=G.UnpackRecord(pending.record)
   if r then receiveRecord(pending.record,pending.sender)
   elseif #G.queue<12 then
    local keys={}; local seen={}
    for _,key in ipairs(pending.record.data.recipes) do
     if not G.recipePool[key] and not G.definitionRequests[key] and not seen[key] and #keys<20 then keys[#keys+1]=key; seen[key]=true end
    end
    if #keys>0 and G.Send({type='definitionsRequest',scope=G.scope,keys=keys},pending.sender) then
     for _,key in ipairs(keys) do G.definitionRequests[key]=G.clock() end
    end
   end
  end
 end
 for target,job in pairs(G.manifestJobs) do
  if not job.incremental and G.digestRevision==G.dataRevision then
   local info=G.peerInfo[target]
   local digest=info and not info.inventory and G.legacyDigest or G.digest
   local advertised=info and info.digest or job.digest
   local matched=advertised==digest and advertised
   if matched then checkedPeer(target,matched); G.manifestJobs[target]=nil; job=nil; G.Refresh() end
  end
  if job then
  if not G.members[target] or not G.PeerCompatible(target) or job.scope~=G.scope then G.manifestJobs[target]=nil
  elseif #G.queue<8 then
   if not job.incremental then
    local focus=G.SyncFocus()
    if job.focus~=focus and G.clock()-(job.focusAt or 0)>5 then
     job.focus=focus; job.focusAt=G.clock(); job.cursor=1; job.rows=nil; job.resolved=nil; job.pages={}; job.pageRequests={}; job.finished=0; job.total=nil
     job.session=G.Hash(job.session..focus..G.clock())
    end
    -- At most three manifest pages (96 descriptors), only 24 record requests.
    for cursor=job.cursor,job.cursor+64,32 do
     if (not job.total and cursor==1 or job.total and cursor<=math.max(1,job.total)) and not job.pages[cursor] and G.clock()-(job.pageRequests[cursor] or -100)>15 then
      if G.Send({type='manifestRequest',scope=G.scope,cursor=cursor,session=job.session,focus=job.focus},target) then job.pageRequests[cursor]=G.clock() end
     end
    end
    local page=job.pages[job.cursor]
    if not job.rows and page then job.rows=page.rows; job.nextCursor=page.nextCursor; job.done=page.done; job.digest=page.digest; job.resolved={} end
   end
   if not job.rows then
    -- The bounded prefetch window above retries missing pages.
   else
    local requests={}; local waiting=false
    for _,row in ipairs(job.rows) do
     local old=G.store.records[row.id]; local rev=tonumber(row.token:match('^(%d+)/'))
     if not deferredGear(row.id) and not row.absent and (not old or old.rev<=rev and G.Token(old)~=row.token) and (not job.resolved or job.resolved[row.id]~=row.token) then
      waiting=true
      if not G.outstanding[row.id] and #requests<8 and G.Count(G.outstanding)+#requests<24 then requests[#requests+1]={id=row.id,base=old and G.Token(old)} end
     end
    end
    if #requests>0 and G.Send({type='request',scope=G.scope,rows=requests},target) then
     for _,row in ipairs(requests) do G.outstanding[row.id]={at=G.clock(),sender=target} end
    end
    if not waiting then
     if job.done then checkedPeer(target,job.digest); G.manifestJobs[target]=nil; G.Refresh()
     else job.finished=(job.finished or 0)+#job.rows; job.pages[job.cursor]=nil; job.cursor=job.nextCursor; job.rows=nil; job.resolved=nil; job.at=-100 end
    end
   end
  end
  end
 end
end

-- Only locally changed snapshots are announced. Relays do not amplify broadcasts.
G.changedRecords={}
function G.PendingLocalChanges()
 local pending,count={},0
 local function keep(id)
  local r=G.store and G.store.records[id]
  if count<32 and not pending[id] and r and r.owner==G.self and r.kind~='loot' then pending[id]=true; count=count+1 end
 end
 local profile='profile:'..G.self
 if G.changedRecords[profile] then keep(profile) end
 for _,q in ipairs(G.queue) do for _,id in ipairs(q.localChanges or {}) do if id==profile then keep(id) end end end
 for id in pairs(G.changedRecords) do keep(id) end
 for _,q in ipairs(G.queue) do for _,id in ipairs(q.localChanges or {}) do keep(id) end end
 return pending
end
function G.TrackChange(r,replay)
 if replay then G.changeReplay=true end
 if not G.changeBase then G.changeBase=G.NetworkDigest(); G.changeLegacyBase=G.LegacyNetworkDigest(); G.changeComplete=true
 elseif G.changeRevision~=G.dataRevision then G.changeComplete=false end
 G.changeRevision=(G.dataRevision or 0)+1
 if not G.changeOverflow then
  G.changedRecords[r.id]=true
  if G.Count(G.changedRecords)>32 then G.changedRecords={}; G.changeOverflow=true end
 end
 if G.timers.changes then return end
 G.After('changes',3,function()
  if not G.ready then G.changeBase=nil; G.changedRecords={}; G.changeOverflow=nil; G.changeReplay=nil; G.AnnounceSoon(); return end
  local rows={}; local inlineBytes=0
  local ids=G.Keys(G.changedRecords)
  -- Reserve the shared inline budget for the profile before a burst of loot.
  local profile='profile:'..G.self
  for i,id in ipairs(ids) do if id==profile then table.remove(ids,i); table.insert(ids,1,id); break end end
  for _,id in ipairs(ids) do
   local current=G.store.records[id]
   if G.ShareRecord(current) then
    local row={id=id,token=G.Token(current)}
    if (current.kind=='loot' or current.kind=='profile') and current.owner==G.self then
     local size=#G.Encode(current)
     if inlineBytes+size<=2048 then row.record=current; inlineBytes=inlineBytes+size end
    end
    rows[#rows+1]=row
   end
  end
  if #rows>0 then
   local complete=not G.changeReplay and G.changeComplete and G.changeRevision==G.dataRevision
   G.Send({type='changes',scope=G.scope,baseDigest=complete and G.changeLegacyBase or nil,digest=G.LegacyNetworkDigest(),
    baseInventory=complete and G.changeBase or nil,inventory=G.NetworkDigest(),rows=rows},nil,'GUILD')
  end
  G.changeBase=nil; G.changeLegacyBase=nil; G.changedRecords={}; G.changeOverflow=nil; G.changeReplay=nil
  G.AnnounceSoon()
 end)
end
