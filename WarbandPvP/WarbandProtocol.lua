local _, A = ...
--@dev
local P = {PREFIX="WBP_WB1", TEST_PREFIX="WBP_WBT1", TTL=90, MAX_GROUPS=4, MAX_MEMBERS=20}
--@enddev
--@release local P = {PREFIX="WBP_WB1", TTL=90, MAX_GROUPS=4, MAX_MEMBERS=20}
A.WB = P
--@dev
function P.IsSimulation() return A.warbands and A.warbands.simulationCount~=nil end
function P.ActivePrefix() return P.IsSimulation() and P.TEST_PREFIX or P.PREFIX end
--@enddev
--@release function P.ActivePrefix() return P.PREFIX end
function P.Read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok,a,b = pcall(fn,...)
    if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then return end
    return a,b
end
function P.Integer(s,lo,hi)
    if type(s)~="string" or not s:match("^%d+$") then return end
    local n=tonumber(s); if n and n>=lo and n<=hi then return n end
end
function P.Name(s)
    if type(s)~="string" or #s==0 or #s>64 or s:find("[|%c]") then return end
    s=s:match("^%s*(.-)%s*$"); if s~="" then return s end
end
function P.Key(s)
    s=P.Name(s); if not s then return end
    s=s:lower():gsub("%s+","-")
    local realm=P.Read(GetNormalizedRealmName)
    if type(realm)=="string" and realm~="" then
        local suffix="-"..realm:lower():gsub("%s+","")
        if s:sub(-#suffix)==suffix then s=s:sub(1,-#suffix-1) end
    end
    return s
end
function P.UnitName(unit)
    local first,second=P.Read(UnitName,unit)
    local full,realm=P.Read(UnitFullName,unit)
    local interface=P.Read(function() return select(4,GetBuildInfo()) end)
    if type(interface)=="number" and interface>=16000 and interface<20000 then
        if type(first)=="string" and type(second)=="string" and second~="" then return P.Name(first.." "..second) end
        return P.Name(first) or P.Name(full)
    end
    if type(full)=="string" then return P.Name(full..(type(realm)=="string" and realm~="" and ("-"..realm) or "")) end
    return P.Name(first)
end
function P.UnitFor(name)
    local key=P.Key(name); if not key then return end
    local found
    for _,u in ipairs({"player","party1","party2","party3","party4"}) do
        if P.Key(P.UnitName(u))==key then if found then return end; found=u end
    end
    return found
end
function P.UUIDValid(s)
    return type(s)=="string" and #s==36 and s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") and s==s:lower()
end
-- Non-secret application identifiers. Mix local identity/time/persisted counter
-- into random bytes without reseeding WoW's shared random generator.
function P.UUID()
    local n=tonumber(A.db.warbandNonce) or 0
    if n~=n or n<0 or n>=1000000000 then n=0 end
    n=math.floor(n)+1; A.db.warbandNonce=n
    local seed=table.concat({P.Read(UnitGUID,"player") or "",P.UnitName("player") or "",
        tostring(GetServerTime()),string.format("%.6f",GetTime()),tostring(n)},":")
    local h=5381
    for i=1,#seed do h=(h*33+seed:byte(i))%4294967296 end
    local bytes={}
    for i=1,16 do h=(h*33+i+n)%4294967296; bytes[i]=(math.random(0,255)+math.floor(h/65536))%256 end
    bytes[7]=64+bytes[7]%16; bytes[9]=128+bytes[9]%64
    local hex={}; for i,b in ipairs(bytes) do hex[i]=string.format("%02x",b) end
    local s=table.concat(hex)
    return s:sub(1,8).."-"..s:sub(9,12).."-"..s:sub(13,16).."-"..s:sub(17,20).."-"..s:sub(21)
end
function P.Scope()
    if not A.RefreshScope() then return end
    local f=P.Read(UnitFactionGroup,"player")
    if f=="Horde" or f=="Alliance" then return f=="Horde" and "H" or "A",A.scopeRuleset,tostring(A.scopeRegion) end
end
function P.Pack(fields)
    local s=table.concat(fields,"\t"); if #s<=255 then return s end
end
function P.Fields(packet)
    if type(packet)~="string" or #packet>255 or packet:find("|",1,true) or packet:gsub("\t",""):find("%c") then return end
    local f={}; for s in (packet.."\t"):gmatch("(.-)\t") do f[#f+1]=s; if #f>20 then return end end
    if f[1]=="1" then return f end
end
function P.ScopeMatches(faction,ruleset,region)
    local f,r,g=P.Scope(); return f and f==faction and r==ruleset and g==region
end
function P.Header(kind,id,session,seq)
    local f,r,g=P.Scope(); if not f then return end
    local now=GetServerTime()
    return {"1",kind,id,session,tostring(seq),tostring(now),tostring(now+P.TTL),f,r,g}
end
function P.DecodeState(f)
    if not f or (f[2]~="A" and f[2]~="G" and f[2]~="E") or not P.UUIDValid(f[3]) or not P.UUIDValid(f[4]) then return end
    local now=GetServerTime()
    local seq=P.Integer(f[5],1,2147483647); local at=P.Integer(f[6],now-P.TTL+1,now+5)
    local expires=P.Integer(f[7],now+1,now+P.TTL+5)
    if not seq or not at or not expires or expires<=at or expires-at>P.TTL or not P.ScopeMatches(f[8],f[9],f[10]) then return end
--@dev
    local r={id=f[3],session=f[4],seq=seq,updatedAt=at,expiresAt=math.min(expires,now+P.TTL),faction=f[8],ruleset=f[9],region=f[10],simulated=P.IsSimulation()}
--@enddev
--@release     local r={id=f[3],session=f[4],seq=seq,updatedAt=at,expiresAt=math.min(expires,now+P.TTL),faction=f[8],ruleset=f[9],region=f[10]}
    if f[2]=="E" then return #f==10 and r or nil end
    if f[2]=="G" then return #f==11 and r or nil end
    if #f~=19 then return end
    r.revision=P.Integer(f[11],1,2147483647); r.mapID=P.Integer(f[12],1,100000)
    local x,y=P.Integer(f[13],0,10000),P.Integer(f[14],0,10000)
    r.count=P.Integer(f[18],1,P.MAX_MEMBERS)
    if not r.revision or not r.mapID or not x or not y or not r.count
        or not ({forming=true,roaming=true,rallying=true})[f[15]]
        or (f[16]~="0" and f[16]~="1") or (f[17]~="follow" and f[17]~="rally")
        or #f[19]==0 or #f[19]>40 then return end
    r.x,r.y=x/10000,y/10000; r.status=f[15]; r.recruiting=f[16]=="1"; r.mode=f[17]; r.title=f[19]
    return r
end
function P.Request(kind,id,session,nonce,extra)
    local f,r,g=P.Scope(); if not f then return end
    local fields={"1",kind,id or "-",session or "-",nonce,tostring(GetServerTime()),f,r,g}
    for _,v in ipairs(extra or {}) do fields[#fields+1]=tostring(v) end
    return P.Pack(fields)
end
function P.DecodeRequest(f)
    if not f or not P.UUIDValid(f[5]) or not P.Integer(f[6],GetServerTime()-30,GetServerTime()+5)
        or not P.ScopeMatches(f[7],f[8],f[9]) then return end
    if f[2]=="S" or f[2]=="X" or f[2]=="D" then return #f==9 and f[3]=="-" and f[4]=="-" end
    if not P.UUIDValid(f[3]) or not P.UUIDValid(f[4]) then return end
    if f[2]=="F" then return #f==11 and P.Name(f[10]) and P.Integer(f[11],1,P.MAX_GROUPS) end
    if f[2]=="J" then return #f==13 and ({solo=true,leader=true,member=true})[f[10]] and P.Name(f[11]) and P.Integer(f[12],1,5) and P.UUIDValid(f[13]) end
    if f[2]=="R" then return #f==12 and #f[10]<=32 and P.Integer(f[11],0,P.MAX_GROUPS) and P.Name(f[12]) end
    if f[2]=="I" then return #f==11 and P.Integer(f[10],1,P.MAX_GROUPS) and P.Name(f[11]) end
    if f[2]=="V" then return #f==11 and P.Integer(f[10],1,P.MAX_GROUPS) and P.Name(f[11]) end
    if f[2]=="L" then return #f==10 and P.UUIDValid(f[10]) end
    if f[2]=="K" then return #f==12 and P.Integer(f[10],1,2147483647) and P.Integer(f[11],1,P.MAX_GROUPS) and P.Name(f[12]) end
end
function P.Base36(n)
    local chars="0123456789abcdefghijklmnopqrstuvwxyz"; local s=""
    repeat local i=n%36; s=chars:sub(i+1,i+1)..s; n=math.floor(n/36) until n==0
    return s
end
function P.Unbase36(s,hi)
    if type(s)~="string" or not s:match("^[0-9a-z]+$") or #s>6 then return end
    local n=tonumber(s,36); if n and n<=hi then return n end
end
