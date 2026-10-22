local _,G=...
-- Session-only review queue. Rank mutations happen only in the button click path.
function G.CanBatchPromote()
    return G.ready and G.scope~=nil and G.members[G.self]~=nil
        and G.Safe(CanGuildPromote)==true
        and C_GuildInfo and type(C_GuildInfo.SetGuildRankOrder)=="function"
        and type(C_GuildInfo.GetGuildRankOrder)=="function"
        and type(C_GuildInfo.IsGuildRankAssignmentAllowed)=="function"
end
local function ranks()
    local result={}
    local count=G.Safe(GuildControlGetNumRanks)
    if type(count)~="number" or count<2 or count>20 then return result end
    for i=1,count do
        local name=G.Safe(GuildControlGetRankName,i)
        if type(name)~="string" or name=="" then return {} end
        result[i]=name
    end
    return result
end
function G.PromotionTargets()
    local result={}
    local own=G.members[G.self]
    if not G.CanBatchPromote() or type(own.rankOrder)~="number" then return result end
    for order,name in ipairs(ranks()) do
        if order>own.rankOrder and order>1 then result[#result+1]={order=order,name=name} end
    end
    return result
end
local function eligible(name,target,guid)
    local own,m=G.members[G.self],G.members[name]
    if not G.CanBatchPromote() or not own or type(own.rankOrder)~="number" or target<=own.rankOrder or target<=1 then return false end
    if name==G.self or not m or not m.guid or (guid and m.guid~=guid) or type(m.rankOrder)~="number" or m.rankOrder<=target then return false end
    local seen=G.peers[name]
    if not m.online or type(seen)~="number" or G.now()-seen>600 or seen>G.now() then return false end
    return G.Safe(C_GuildInfo.IsGuildRankAssignmentAllowed,m.guid,target)==true
end
function G.PreviewPromotions(target)
    if G.promotionBatch and G.promotionBatch.pending then return nil,"Wait for the current request, or cancel." end
    local rankNames=ranks()
    if type(target)~="number" or target%1~=0 or not rankNames[target] or not G.CanBatchPromote() then return nil,"Promotion permission or rank information unavailable." end
    local own=G.members[G.self]
    if type(own.rankOrder)~="number" or target<=own.rankOrder or target<=1 then return nil,"Choose a rank below your own." end
    local batch={scope=G.scope,target=target,targetName=rankNames[target],rankNames=rankNames,rows={},index=1,confirmed=0,skipped=0,failed=0}
    for name,m in pairs(G.members) do
        if eligible(name,target) then batch.rows[#batch.rows+1]={name=name,guid=m.guid,rank=m.rank or rankNames[m.rankOrder],status="Ready"} end
    end
    table.sort(batch.rows,function(a,b) return a.name<b.name end)
    G.promotionBatch=batch
    return batch
end
function G.CancelPromotions()
    G.promotionBatch=nil
    if G.timers["promotion-confirm"] then G.timers["promotion-confirm"]:Cancel(); G.timers["promotion-confirm"]=nil end
end
local function finish(batch,row,status)
    row.status=status; batch.pending=nil; batch.index=batch.index+1
    if status=="Confirmed" then batch.confirmed=batch.confirmed+1
    elseif status=="Skipped" then batch.skipped=batch.skipped+1 else batch.failed=batch.failed+1 end
end
local function poll()
    local batch=G.promotionBatch
    if not batch or not batch.pending then return end
    local row=batch.rows[batch.index]
    local m=G.members[row.name]
    if G.scope~=batch.scope then G.CancelPromotions(); G.Refresh(); return end
    if G.ready and m and m.guid==row.guid and m.rankOrder==batch.target then
        finish(batch,row,"Confirmed")
    elseif G.clock()-batch.pending>=15 then
        finish(batch,row,"Not confirmed")
    else G.After("promotion-confirm",0.5,poll) end
    G.Refresh()
end
function G.PromoteNextReviewed()
    local batch=G.promotionBatch
    if not batch or batch.pending then return false,"Preview first, or wait for confirmation." end
    if not G.ready then return false,"Waiting for the guild roster. Try again shortly." end
    if G.scope~=batch.scope or not G.CanBatchPromote() or not G.Equal(ranks(),batch.rankNames) then
        G.CancelPromotions(); return false,"Guild, ranks or permissions changed. Preview again."
    end
    if G.Safe(InCombatLockdown) then return false,"Finish combat before promoting." end
    local row=batch.rows[batch.index]
    if not row then return false,"Review complete." end
    local current=G.Safe(C_GuildInfo.GetGuildRankOrder,row.guid)
    local own=G.members[G.self]
    local ownRank=own.guid and G.Safe(C_GuildInfo.GetGuildRankOrder,own.guid)
    if type(ownRank)~="number" or batch.target<=ownRank then
        G.CancelPromotions(); return false,"Your rank changed or is unavailable. Preview again."
    end
    if type(current)~="number" or current<=batch.target or not eligible(row.name,batch.target,row.guid) then
        finish(batch,row,"Skipped"); return false,"Skipped: member is no longer eligible."
    end
    batch.pending=G.clock(); row.status="Waiting"
    local ok,result=pcall(C_GuildInfo.SetGuildRankOrder,row.guid,batch.target)
    if not ok or result==false then finish(batch,row,"Not confirmed"); return false,"WoW refused the request. No automatic retry." end
    G.Safe(C_GuildInfo.GuildRoster)
    G.After("promotion-confirm",0.5,poll)
    return true,"Request sent. Waiting for the roster to confirm."
end

function G.CreatePromotionControls(parent)
    local W=G.UIWidgets
    local f=CreateFrame("Frame",nil,parent); f:SetAllPoints()
    f.page=0
    W.label(f,"Promote connected addon users",14,20,-120,470)
    W.label(f,"Already at the target rank or higher? They are skipped.",11,20,-145,470)
    local function clear() G.CancelPromotions(); f.page=0; f.status:SetText("") end
    f.target=W.button(f,"Choose target rank",470,20,-172,function()
        local choices=G.PromotionTargets()
        if #choices==0 then return end
        local nextIndex=1
        for i,v in ipairs(choices) do if v.order==f.targetRank then nextIndex=i%#choices+1 end end
        clear(); f.targetRank=choices[nextIndex].order; f.refresh()
    end)
    f.preview=W.button(f,"Preview",120,20,-210,function()
        local batch,err=G.PreviewPromotions(f.targetRank)
        f.page=0; f.status:SetText(err or (#batch.rows==0 and "No eligible connected addon users." or "Review the list, then promote one member per click.")); f.refresh()
    end)
    W.label(f,"Click the target rank to cycle through available ranks.",11,150,-218,340)
    f.rows={}
    for i=1,5 do
        local y=-252-(i-1)*31
        local row={name=W.label(f,"",12,20,y,290),rank=W.label(f,"",10,20,y-15,290),status=W.label(f,"",11,325,y,165)}
        row.status:SetJustifyH("RIGHT"); f.rows[i]=row
    end
    f.pageText=W.label(f,"Preview to list eligible members.",11,20,-407,350)
    f.prev=W.button(f,"<",32,414,-399,function() f.page=math.max(0,f.page-1); f.refresh() end)
    f.next=W.button(f,">",32,458,-399,function() f.page=f.page+1; f.refresh() end)
    f.promote=W.button(f,"Promote next",230,20,-441,function()
        local ok,message=G.PromoteNextReviewed(); f.status:SetText(message); f.refresh()
    end)
    f.cancel=W.button(f,"Cancel",110,380,-441,function() clear(); f.status:SetText("Queue cleared. Already sent requests cannot be undone."); f.refresh() end)
    f.status=W.label(f,"",11,20,-479,470); f.status:SetWordWrap(true); f.status:SetHeight(30)
    f.refresh=function()
        local batch=G.promotionBatch
        local names=ranks()
        f.target.text:SetText(f.targetRank and names[f.targetRank] and ("Target rank: "..names[f.targetRank]) or "Choose target rank")
        local allowed=G.CanBatchPromote()
        f.target:SetEnabled(allowed and not (batch and batch.pending),not allowed and "WoW guild permissions do not allow this action." or batch and batch.pending and "Waiting for the roster to confirm the last request." or "Choose a target rank first.")
        f.preview:SetEnabled(allowed and f.targetRank~=nil and not (batch and batch.pending),not allowed and "WoW guild permissions do not allow this action." or batch and batch.pending and "Waiting for the roster to confirm the last request." or "Choose a target rank first.")
        local rows=batch and batch.rows or {}
        local pages=math.max(1,math.ceil(#rows/5)); f.page=math.min(f.page,pages-1)
        for i,labels in ipairs(f.rows) do
            local row=rows[f.page*5+i]
            labels.name:SetText(row and G.Plain(row.name) or "")
            labels.rank:SetText(row and (G.Plain(row.rank).." → "..G.Plain(batch.targetName)) or "")
            labels.status:SetText(row and (i+f.page*5==batch.index and row.status=="Ready" and "Next" or row.status) or "")
        end
        f.pageText:SetText(batch and (#rows.." members · "..batch.confirmed.." confirmed · "..batch.skipped.." skipped · "..batch.failed.." failed") or "Preview to list eligible members.")
        f.prev:SetEnabled(f.page>0,"You are on the first page."); f.next:SetEnabled(f.page<pages-1,"You are on the last page.")
        f.promote:SetEnabled(allowed and batch~=nil and not batch.pending and batch.index<=#rows and not G.Safe(InCombatLockdown),G.Safe(InCombatLockdown) and "Wait until combat ends." or not allowed and "WoW guild permissions do not allow this action." or batch and batch.pending and "Waiting for the roster to confirm the last request." or "Preview eligible members first; the reviewed queue must contain a remaining member.")
        f.promote.text:SetText(batch and batch.pending and "Waiting for roster…" or "Promote next")
    end
    return f
end
