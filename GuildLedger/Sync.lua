local _,G=...
G.PROTOCOL=3
G.queue,G.partials,G.peers,G.outstanding={},{},{},{}
G.peerInfo={}; G.sources={}; G.manifestJobs={}; G.completedDigests={}
G.pendingRecords={}; G.definitionRequests={}
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
 return not c and 'Version unknown' or c<0 and 'Older version' or c>0 and 'Newer version' or 'Up to date'
end
function G.Digest()
 if G.digestRevision~=G.dataRevision then
  local rows={}; for _,id in ipairs(G.Keys(G.store.records)) do rows[#rows+1]=id..'='..G.Token(G.store.records[id]) end
  G.digest=G.Hash(table.concat(rows,';')); G.digestRevision=G.dataRevision
 end
 return G.digest
end
-- Network discovery must not fingerprint an entire cold cache in one frame.
function G.NetworkDigest()
 if G.digestRevision==G.dataRevision then return G.digest end
 if G.Count(G.store.records)<=32 then return G.Digest() end
end
local function digestWork()
 if G.digestRevision==G.dataRevision then G.digestWork=nil; return end
 local work=G.digestWork
 if not work then work={keys=G.Keys(G.store.records),cursor=1,hash=5381,revision=G.dataRevision}; G.digestWork=work end
 for i=1,24 do
  local id=work.keys[work.cursor]
  if not id then
   if work.revision==G.dataRevision then G.digest=string.format('%08x',work.hash); G.digestRevision=work.revision end
   G.digestWork=nil; return
  end
  local r=G.store.records[id]
  if r then
   local piece=(work.cursor>1 and ';' or '')..id..'='..G.Token(r)
   for j=1,#piece do work.hash=(work.hash*33+piece:byte(j))%2147483647 end
  end
  work.cursor=work.cursor+1
 end
end
function G.Hello(kind,target)
 local catchingUp=false; for _,job in pairs(G.manifestJobs) do if not job.incremental and G.clock()-(job.progress or 0)<45 then catchingUp=true; break end end
 return {type=kind or 'hello',scope=G.scope,target=target,version=G.VERSION,protocol=G.PROTOCOL,digest=G.NetworkDigest(),catchingUp=catchingUp}
end
function G.AnnounceSoon()
 if G.timers.announce then return end
 G.After('announce',math.max(3,60-(G.clock()-(G.lastHello or -60))),function()
  if G.ready then
   if not G.NetworkDigest() then G.AnnounceSoon(); return end
   G.lastHello=G.clock(); G.Send(G.Hello(),nil,'GUILD')
  end
 end)
end
-- Prefer one source. A second is allowed only after the first stops progressing.
function G.Manifest(target)
 if not G.members[target] or not G.PeerCompatible(target) or G.manifestJobs[target] or G.Count(G.manifestJobs)>=4 then return end
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
 if info and info.digest and (G.completedDigests[target]==info.digest or G.NetworkDigest()==info.digest) then G.completedDigests[target]=info.digest; return end
 G.manifestJobs[target]={cursor=1,at=-100,digest=info and info.digest,scope=G.scope,progress=G.clock(),session=G.Hash(G.self..target..G.clock()),pages={},pageRequests={},finished=0,focus=G.SyncFocus(),focusAt=G.clock()}
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
 return id:sub(1,5)=='gear:' and not G.store.records[id] and not (G.gearDemand and id=='gear:'..G.gearDemand.owner)
end
-- Sort once per source snapshot; useful online details arrive before bulk books.
local function priorityKeys(focus)
 local keys=G.Keys(G.store.records); local ranks={}
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
function G.Handle(v,sender)
 if type(v)~='table' or v.scope~=G.scope or not G.members[sender] then return end
 if v.type=='hello' or v.type=='offer' then
  if type(v.protocol)~='number' or v.protocol%1~=0 or v.protocol<1 or v.protocol>10000 then return end
  local version=type(v.version)=='string' and #v.version<=32 and v.version:match('^%d+%.%d+%.%d+$') and v.version or nil
  G.peerInfo[sender]={version=version,protocol=v.protocol==G.PROTOCOL and G.PROTOCOL or nil,catchingUp=v.catchingUp==true,
   digest=type(v.digest)=='string' and #v.digest==8 and v.digest or nil}
  G.peers[sender]=G.now()
  if not G.PeerCompatible(sender) then G.manifestJobs[sender]=nil; G.Refresh(); return end
 end
 if not G.PeerCompatible(sender) or v.protocol and v.protocol~=G.PROTOCOL then return end
 G.peers[sender]=G.now(); G.lastContact=G.now()
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
    elseif v.type=="lootPolicy" then
        if not G.IsOfficer(sender) or type(v.greens)~="boolean" or type(v.revision)~="number" or v.revision%1~=0 or v.revision<0 or v.revision>(G.now()+300)*1000 then return end
        if v.revision>(G.store.policyRevision or -1) or v.revision==G.store.policyRevision and not v.greens and G.store.captureGreens then
            G.store.captureGreens=v.greens; G.store.policyRevision=v.revision; G.Refresh()
        end
        return
    end

 if v.type=='hello' then
  G.Manifest(sender)
  local key='offer:'..sender
  if G.clock()-(G.offerTimes and G.offerTimes[sender] or -90)<45 then return end
  G.offerTimes=G.offerTimes or {}; G.offerTimes[sender]=G.clock()
  G.After(key,1+(tonumber(G.Hash(sender..G.self..math.floor(G.now()/60)),16)%900)/100,function()
   if not G.ready or not G.members[sender] then return end
   G.Send(G.Hello('offer',sender),nil,'GUILD'); G.Manifest(sender)
   G.SendGuildInvite(sender); G.SendLootPolicy(sender)
  end)
 elseif v.type=='offer' and type(v.target)=='string' then
  local key='offer:'..v.target
  if G.timers[key] then G.timers[key]:Cancel(); G.timers[key]=nil end
  if v.target==G.self then G.Manifest(sender); G.SendGuildInvite(sender); G.SendLootPolicy(sender) end
 elseif v.type=='changes' and type(v.rows)=='table' and #v.rows<=32 then
  if G.manifestJobs[sender] or G.Count(G.manifestJobs)>=4 then return end
  for _,row in ipairs(v.rows) do
   if type(row)~='table' or type(row.id)~='string' or #row.id>180 or type(row.token)~='string' or #row.token>50 or not row.token:match('^%d+/%x%x%x%x%x%x%x%x$') then return end
  end
  local matched=type(v.baseDigest)=='string' and G.completedDigests[sender]==v.baseDigest
  G.manifestJobs[sender]={rows=v.rows,done=true,scope=G.scope,progress=G.clock(),at=G.clock(),cursor=0,incremental=true,
   digest=matched and type(v.digest)=='string' and #v.digest==8 and v.digest or nil,resolved={}}
 elseif v.type=='manifestRequest' then
  if type(v.cursor)~='number' or v.cursor%1~=0 or v.cursor<1 or v.cursor>12001 then return end
  local source=G.sources[sender]
  if v.session~=nil and (type(v.session)~='string' or #v.session~=8) then return end
  if v.cursor==1 and (not source or source.session~=v.session) then
   if not source and G.Count(G.sources)>=4 then return end
   local focus=({Roster=true,Crafting=true,['Guild Loot']=true})[v.focus] and v.focus or 'Roster'
   source={keys=priorityKeys(focus),digest=G.NetworkDigest(),revision=G.dataRevision,at=G.clock(),session=v.session}; G.sources[sender]=source
  end
  if not source or source.session~=v.session then G.Send({type='restart',scope=G.scope,session=v.session},sender); return end
  source.at=G.clock(); local rows={}
  if source.revision==G.dataRevision then source.digest=source.digest or G.NetworkDigest() end
  for i=v.cursor,math.min(v.cursor+31,#source.keys) do
   local r=G.store.records[source.keys[i]]; if r then rows[#rows+1]={id=r.id,token=G.Token(r)} end
  end
  G.Send({type='manifest',scope=G.scope,rows=rows,cursor=v.cursor,nextCursor=v.cursor+32,done=v.cursor+32>#source.keys,digest=source.digest,total=#source.keys,session=source.session},sender)
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
    if r then
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
 for name,t in pairs(G.peers) do if not G.members[name] or G.now()-t>600 then G.peers[name]=nil; G.peerInfo[name]=nil; G.completedDigests[name]=nil; if G.offerTimes then G.offerTimes[name]=nil end; if G.rates then G.rates[name]=nil end end end
 for name,s in pairs(G.sources) do if G.clock()-s.at>300 or not G.members[name] then G.sources[name]=nil end end
 for id,h in pairs(G.history) do if G.clock()-h.at>600 then G.historyBytes=G.historyBytes-h.size; G.history[id]=nil end end
 for id,t in pairs(G.outstanding) do if G.clock()-t.at>(G.pendingRecords[id] and 300 or 60) then finish(id) end end
 for key,t in pairs(G.definitionRequests) do if G.clock()-t>15 then G.definitionRequests[key]=nil end end
 if not G.ready then return end
 G.PruneBookTemplates(); gearWork()
 digestWork()
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
     if job.done then if job.digest then G.completedDigests[target]=job.digest end; G.manifestJobs[target]=nil; G.Refresh()
     else job.finished=(job.finished or 0)+#job.rows; job.pages[job.cursor]=nil; job.cursor=job.nextCursor; job.rows=nil; job.resolved=nil; job.at=-100 end
    end
   end
  end
 end
end

-- Only locally changed snapshots are announced. Relays do not amplify broadcasts.
G.changedRecords={}
function G.TrackChange(r)
 if not G.changeBase then G.changeBase=G.NetworkDigest(); G.changeComplete=true
 elseif G.changeRevision~=G.dataRevision then G.changeComplete=false end
 G.changeRevision=(G.dataRevision or 0)+1
 if not G.changeOverflow then
  G.changedRecords[r.id]=true
  if G.Count(G.changedRecords)>32 then G.changedRecords={}; G.changeOverflow=true end
 end
 if G.timers.changes then return end
 G.After('changes',3,function()
  if not G.ready then G.changeBase=nil; G.changedRecords={}; G.changeOverflow=nil; G.AnnounceSoon(); return end
  local rows={}
  for _,id in ipairs(G.Keys(G.changedRecords)) do local current=G.store.records[id]; if current then rows[#rows+1]={id=id,token=G.Token(current)} end end
  if #rows>0 then G.Send({type='changes',scope=G.scope,baseDigest=G.changeComplete and G.changeRevision==G.dataRevision and G.changeBase or nil,digest=G.NetworkDigest(),rows=rows},nil,'GUILD') end
  G.changeBase=nil; G.changedRecords={}; G.changeOverflow=nil
  G.AnnounceSoon()
 end)
end
