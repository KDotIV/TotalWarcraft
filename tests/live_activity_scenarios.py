"""Observed flagged-unit damage, with no claimed attacker attribution."""
from auto_report_scenarios import SETUP


def check_live_activity(factory):
    def fresh():
        lua = factory('Activity Observer')
        lua.execute(SETUP)
        lua.execute('''
function UnitPlayerControlled(u) return UnitIsPlayer(u) end
function wound(u) event('UNIT_COMBAT',u or 'target','WOUND','', 'SECRET', 'SECRET') end
''')
        return lua

    # A readable WOUND occurrence is sufficient; its secret amount is not read.
    lua=fresh()
    lua.execute('''
local send=A.adapter
A.adapter=function(r) assert(r.manual==false); return send(r) end
local before=meterReads; fight(); advanceTimers(4); wound()
C_Map.GetPlayerMapPosition=function() return {GetXY=function() return .75,.75 end} end
UnitDistanceSquared=function() error('unavailable enemy range') end
assert(reportCount()==0); advanceTimers(1)
assert(combat and reportCount()==1 and not A.autoReports.timer)
assert(meterReads==before and reads==0)
assert(A.List()[1].x==.75)
assert(A.SessionLogText():find('evidence=observed-flagged-damage',1,true))
peace(); assert(reportCount()==1)
''')

    # The activity path must not depend on a damage-meter baseline or availability.
    lua=fresh()
    lua.execute('''
C_DamageMeter=nil; A.InitAutoReports(); fight(); advanceTimers(4); wound(); advanceTimers(1)
assert(reportCount()==1 and reads==0)
''')

    # PvP-flagged faction NPCs qualify even if UnitFactionGroup says Neutral.
    lua=fresh()
    lua.execute('''
playerTarget=false
function UnitFactionGroup(u) return u=='player' and 'Horde' or 'Neutral' end
fight(); advanceTimers(4); wound(); advanceTimers(1)
assert(reportCount()==1)
assert(A.SessionLogText():find('recipient=pvp-npc',1,true))
assert(A.List()[1].countUnknown and A.List()[1].observedCount==0)
''')

    # No report from selected targets, damage to self, healing/misses or unseen,
    # friendly, unflagged, controlled/pet, restricted or stale unit identities.
    for mutation, unit, action in [
        ('', 'player', 'WOUND'), ('', 'target', 'HEAL'), ('', 'target', 'MISS'),
        ('', 'target', 'SECRET'), ('', 'SECRET', 'WOUND'),
        ('flagged=false', 'target', 'WOUND'),
        ('playerTarget=false; flagged=false', 'target', 'WOUND'),
        ('enemy=false', 'target', 'WOUND'), ('attackable=false', 'target', 'WOUND'),
        ('visible=false', 'target', 'WOUND'), ('flagged="SECRET"', 'target', 'WOUND'),
        ('UnitGUID=function() return "SECRET" end', 'target', 'WOUND'),
        ('UnitIsPlayer=function() return "SECRET" end', 'target', 'WOUND'),
        ('playerTarget=false; UnitPlayerControlled=function() return true end', 'target', 'WOUND'),
        ('playerTarget=false; UnitPlayerControlled=nil', 'target', 'WOUND'),
        ('instance=true', 'target', 'WOUND'), ('ffa=true', 'target', 'WOUND'),
        ('sanctuary=true', 'target', 'WOUND'),
    ]:
        lua=fresh()
        lua.execute(mutation + "\nfight(); advanceTimers(4); event('UNIT_COMBAT','" + unit + "','" + action + "'); advanceTimers(1); assert(reportCount()==0)")

    lua=fresh(); lua.execute('fight(); advanceTimers(20); assert(reportCount()==0 and reads==0)')
    lua=fresh(); lua.execute("fight(); event('UNIT_COMBAT','player','WOUND'); advanceTimers(5); assert(reportCount()==0); assert(A.SessionLogText():find('evidence=none woundEvents=1 selfWounds=1',1,true))")
    lua=fresh(); lua.execute('wound(); advanceTimers(10); assert(reportCount()==0 and activeTimers()==0)')
    for mutation in ['flagged=false', 'visible=false', 'attackable=false', 'targetCombat=false',
                     'UnitGUID=function(u) return "Player-replacement" end', 'map=2']:
        lua=fresh(); lua.execute('fight(); advanceTimers(4); wound(); '+mutation+'; advanceTimers(1); assert(reportCount()==0)')

    # Evidence ages out and a different target cannot inherit it. Fresh later
    # wounds can qualify; no failed-send retry or duplicate post-combat send.
    lua=fresh()
    lua.execute('''
fight(); wound(); targetCombat=false; advanceTimers(5)
targetCombat=true; advanceTimers(5); assert(reportCount()==0)
advanceTimers(4); wound(); advanceTimers(1); assert(reportCount()==1)
peace(); assert(reportCount()==1)
''')
    lua=fresh(); lua.execute('fight(); advanceTimers(4); wound(); sendFailure=true; advanceTimers(1); local n=attempts; advanceTimers(20); wound(); advanceTimers(5); assert(reportCount()==0 and attempts==n and not A.autoReports.timer)')

    # Short combat cancels the live pulse; the existing verified fallback stays.
    lua=fresh(); lua.execute('playerTarget=false; fight(); wound(); advanceTimers(1); peace(); assert(reportCount()==0 and not A.autoReports.timer)')
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); wound(); advanceTimers(1); peace(); assert(reportCount()==1)")
    for ev in ['DUEL_REQUESTED','DUEL_INBOUNDS','ZONE_CHANGED_NEW_AREA','SHARD_TRANSFER','DAMAGE_METER_RESET']:
        lua=fresh(); lua.execute("fight(); advanceTimers(4); wound(); event('"+ev+"'); advanceTimers(1); assert(reportCount()==0)")
    lua=fresh(); lua.execute('fight(); advanceTimers(4); wound(); A.SetAutoReportsEnabled(false); advanceTimers(2); assert(reportCount()==0 and not A.autoReports.timer)')
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); local old=A.autoReports.timer; advanceTimers(4); wound(); combat=false; event('PLAYER_REGEN_ENABLED'); local reader=A.autoReports.timer; old.fn(); assert(reportCount()==0 and A.autoReports.timer==reader); advanceTimers(.5); assert(reportCount()==1)")
    lua=fresh(); lua.execute('combat=true; A.InitAutoReports(); wound(); advanceTimers(10); assert(reportCount()==0); peace(); fight(); advanceTimers(4); wound(); advanceTimers(1); assert(reportCount()==1)')

    # A manual report and the live path share the same cooldown and attempt.
    lua=fresh(); lua.execute('fight(); advanceTimers(4); wound(); assert(A.Report()); advanceTimers(1); peace(); assert(reportCount()==1); fight(); wound(); advanceTimers(5); assert(reportCount()==1)')

    # Only recent event recipients are revisited; token reuse/removal is rejected.
    lua=fresh()
    lua.execute('''
local exists=UnitExists; local faction=UnitFactionGroup; local inCombat=UnitAffectingCombat
function UnitExists(u) return u=='nameplate1' or exists(u) end
function UnitIsPlayer(u) return true end
function UnitFactionGroup(u) return u=='nameplate1' and 'Alliance' or faction(u) end
function UnitAffectingCombat(u) return u=='nameplate1' or inCombat(u) end
fight(); advanceTimers(4); wound('nameplate1'); event('NAME_PLATE_UNIT_REMOVED','nameplate1')
advanceTimers(1); assert(reportCount()==0)
advanceTimers(4); wound('nameplate1'); advanceTimers(1); assert(reportCount()==1)
''')

    # Keep event processing bounded without a UNIT_COMBAT flood cancelling the
    # whole capture or delaying combat-end cleanup.
    lua=fresh()
    lua.execute('''
fight(); advanceTimers(4)
for i=1,500 do wound() end
advanceTimers(1); assert(reportCount()==1)
peace(); assert(not A.autoReports.timer)
''')

    lua=fresh()
    lua.execute('''
local exists=UnitExists; local faction=UnitFactionGroup; local inCombat=UnitAffectingCombat
function UnitExists(u) return u:match('^nameplate%d+$')~=nil or exists(u) end
function UnitIsPlayer() return true end
function UnitFactionGroup(u) return u:match('^nameplate%d+$') and 'Alliance' or faction(u) end
function UnitAffectingCombat(u) return u:match('^nameplate%d+$')~=nil or inCombat(u) end
fight(); advanceTimers(4)
for i=1,64 do wound('nameplate'..i) end
local n=0; for _ in pairs(A.autoReports.capture.wounds) do n=n+1 end
assert(n==32)
advanceTimers(1); assert(reportCount()==1)
''')

    # A client that cannot register UNIT_COMBAT still retains strict verification.
    for failure in ['return false', 'error("unavailable event")']:
        lua=fresh()
        lua.execute('''
local create=CreateFrame
CreateFrame=function(...)
 local f=create(...); local register=f.RegisterEvent
 f.RegisterEvent=function(self,e)
  if e=='UNIT_COMBAT' then '''+failure+''' end
  return register(self,e)
 end
 return f
end
A.InitAutoReports(); assert(not A.autoReports.activityEvents)
rows={damage('Wide Guy',10)}; fight(); advanceTimers(4); wound(); advanceTimers(1)
assert(reportCount()==0); peace(); assert(reportCount()==1)
''')
