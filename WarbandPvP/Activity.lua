local _,A=...
-- Visual proximity, not a world-yard radius or layer assertion. Anchor each
-- cluster to its newest report; never chain nearby reports across a whole zone.
local RADIUS_SQUARED=.035*.035
local WINDOW=120

function A.ReportClusters()
    local now,clusters=GetServerTime(),{}
    for _,r in ipairs(A.List()) do
        local recent=now-r.updatedAt<WINDOW
        local found
        for _,c in ipairs(clusters) do
            local anchor=c.record
            local compatible=anchor.mapID==r.mapID and anchor.faction==r.faction and anchor.ruleset==r.ruleset
--@dev
            compatible=compatible and (anchor.test==true)==(r.test==true) and (anchor.demo==true)==(r.demo==true)
--@enddev
            if compatible and (r.x-anchor.x)^2+(r.y-anchor.y)^2<=RADIUS_SQUARED then found=c; break end
        end
        if not found then
            found={record=r,reporters={},reports=0,weight=0}
            clusters[#clusters+1]=found
        end
        local key=A.WB.Key(r.reporter)
        if recent and key and not found.reporters[key] then
            found.reporters[key]=true; found.reports=found.reports+1
            found.weight=found.weight+math.max(0,1-math.max(0,now-r.updatedAt)/WINDOW)
        end
    end
    for _,c in ipairs(clusters) do
        c.heat=math.max(0,math.min(1,(c.weight-1)/3))
        c.pulse=c.reports>=2 and c.heat>0
        c.heavy=c.reports>=4 and c.weight>=2.5
        c.label=c.heavy and "Heavy activity" or c.pulse and "Growing conflict" or ""
        c.size=22+10*c.heat
    end
    return clusters
end
