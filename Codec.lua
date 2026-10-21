local _, G = ...
-- Length-prefixed grammar; no loadstring, executable text, metatables or delimiters in strings.
function G.Encode(value)
    local seen, nodes = {}, 0
    local function put(v, depth)
        nodes=nodes+1
        assert(depth<=12 and nodes<=24000,"payload complexity")
        local t=type(v)
        if t=="string" then assert(#v<=4096,"string too long"); return "s"..#v..":"..v end
        if t=="number" then assert(v==v and math.abs(v)<1e15,"invalid number"); local s=tostring(v); return "n"..#s..":"..s end
        if t=="boolean" then return v and "t" or "f" end
        assert(t=="table" and not seen[v],"invalid value")
        seen[v]=true
        local keys={}; for k in pairs(v) do assert(type(k)=="string" or type(k)=="number","key type"); keys[#keys+1]=k end
        table.sort(keys,function(a,b) if type(a)==type(b) then return a<b end return type(a)<type(b) end)
        local out={"a",tostring(#keys),":"}
        for _,k in ipairs(keys) do out[#out+1]=put(k,depth+1); out[#out+1]=put(v[k],depth+1) end
        seen[v]=nil
        return table.concat(out)
    end
    local s=put(value,0); assert(#s<=G.MAX_WIRE,"payload too large"); return s
end
function G.Decode(s)
    if type(s)~="string" or #s>G.MAX_WIRE then return nil,"size" end
    local pos,nodes=1,0
    local function get(depth)
        nodes=nodes+1; assert(depth<=12 and nodes<=24000,"complexity")
        local tag=s:sub(pos,pos); pos=pos+1
        if tag=="t" then return true elseif tag=="f" then return false end
        assert(tag=="s" or tag=="n" or tag=="a","tag")
        local stop=s:find(":",pos,true); assert(stop and stop-pos<=6,"length")
        local digits=s:sub(pos,stop-1); assert(digits:match("^%d+$"),"length")
        local len=tonumber(digits); pos=stop+1
        if tag=="a" then
            assert(len<=8000,"entries"); local t={}
            for _=1,len do local k=get(depth+1); assert(type(k)=="string" or type(k)=="number","key"); assert(t[k]==nil,"duplicate key"); t[k]=get(depth+1) end
            return t
        end
        assert(len<=4096 and pos+len-1<=#s,"truncated")
        local v=s:sub(pos,pos+len-1); pos=pos+len
        if tag=="n" then v=tonumber(v); assert(v and v==v and math.abs(v)<1e15,"number") end
        return v
    end
    local ok,v=pcall(get,0)
    if not ok or pos~=#s+1 then return nil,"malformed" end
    return v
end
