"""Strict post-combat attribution; source and compiled Release share these scenarios."""
SETUP = r'''
combat=false; lockdown=false; targetCombat=true; flagged=true; enemy=true; playerTarget=true
visible=true; attackable=true; instance=false; ffa=false; sanctuary=false; map=1
function UnitExists(u) return u=='player' or u=='target' end
function UnitAffectingCombat(u) return u=='player' and combat or u=='target' and targetCombat or false end
function InCombatLockdown() return combat or lockdown end
function UnitFactionGroup(u) return u=='target' and (enemy and 'Alliance' or 'Horde') or 'Horde' end
function UnitIsPlayer(u) return u=='player' or u=='target' and playerTarget end
function UnitIsPVP() return flagged end
function UnitIsVisible() return visible end
function UnitCanAttack() return attackable end
function UnitIsPVPFreeForAll() return ffa end
function UnitIsPVPSanctuary() return sanctuary end
function IsInInstance() return instance end
function UnitName(u) return u=='player' and PLAYER or 'Wide Guy' end
function UnitFullName(u) return UnitName(u),'' end
C_Map.GetBestMapForUnit=function() return map end
Enum.DamageMeterType={DamageTaken=7,DamageDone=0}
sessions={{sessionID=10}}; currentSession=10; rows={}; outgoing={}; available=true; reads=0; meterReads=0
function native() meterReads=meterReads+1; assert(not combat and not lockdown) end
C_DamageMeter={
 IsDamageMeterAvailable=function() native(); return available end,
 GetAvailableCombatSessions=function() native(); return sessions end,
 GetCombatSessionFromID=function(sid,kind)
  native(); assert((kind==7 or kind==0) and sid==currentSession); reads=reads+1
  return {combatSources={{isLocalPlayer=true,sourceGUID='Player-player'}}}
 end,
 GetCombatSessionSourceFromID=function(sid,kind,guid)
  native(); assert((kind==7 or kind==0) and guid=='Player-player')
  return {combatSpells=kind==7 and rows or outgoing}
 end,
}
function damage(unit,amount,mob,pet)
 return {totalAmount=9999,combatSpellDetails={unitName=unit,amount=amount,isMob=mob==true,isPet=pet==true}}
end
function reportCount()
 local n=0; for _,prefix in ipairs(sentPrefixes) do if prefix=='WBP_REPORT1' then n=n+1 end end; return n
end
function event(ev,...) A.autoReports.events.scripts.OnEvent(nil,ev,...) end
function step(seconds,ev) advanceTimers(seconds or 1); event(ev or 'PLAYER_TARGET_CHANGED') end
function fight()
 combat=true; event('PLAYER_REGEN_DISABLED')
 currentSession=currentSession+1; sessions[#sessions+1]={sessionID=currentSession}
 event('DAMAGE_METER_COMBAT_SESSION_UPDATED',7,currentSession)
end
function peace() combat=false; event('PLAYER_REGEN_ENABLED'); advanceTimers(4) end
A.UpdateAutoReports()
'''

def check_auto_reports(factory):
    def fresh():
        lua=factory('Auto Observer'); lua.execute(SETUP); return lua

    for condition in ['playerTarget=false','enemy=false','flagged=false','visible=false','attackable=false',
                      'instance=true','ffa=true','sanctuary=true','flagged="SECRET"',
                      'UnitCanAttack=nil','UnitFactionGroup=function() error("restricted") end',
                      'UnitIsPVPSanctuary=function() return "SECRET" end','UnitExists=function() return false end']:
        lua=fresh()
        lua.execute(condition+"; rows={damage('Wide Guy',947)}; fight(); peace(); assert(reportCount()==0)")

    # Native shape from the live PvP capture; no outgoing row is required.
    lua=fresh()
    lua.execute('''
assert(activeTimers()==0)
rows={damage('Wide Guy',429),damage('Wide Guy',271),damage('Wide Guy',206),damage('Wide Guy',41)}
fight(); assert(reportCount()==0 and reads==0 and A.autoReports.timer)
combat=false; event('PLAYER_REGEN_ENABLED'); advanceTimers(.6)
assert(reportCount()==1 and #A.List()==1 and not A.autoReports.timer)
assert(A.List()[1].expiresAt-NOW==300 and A.List()[1].countUnknown)
assert(A.SessionLogText():find('incoming opposing-player damage confirmed',1,true))
assert(not A.toast or not A.toast:IsShown())
-- A new attacker after the first read cannot erase that accepted report.
fight(); peace(); assert(reportCount()==1)
advanceTimers(121); fight(); peace(); assert(reportCount()==2)
''')
    peer=factory('Peer Reader')
    packet=next(lua.globals().packets[i] for i in range(1,lua.globals().sends+1) if lua.globals().sentPrefixes[i]=='WBP_REPORT1')
    peer.globals().A.OnReportMessage('WBP_REPORT1',packet,'GUILD','Auto Observer')
    peer.execute('assert(#A.List()==1)')

    # Automatic reporting must work for unguilded users on the shared channel too.
    unguilded=fresh()
    unguilded.execute("inGuild=false; rows={damage('Wide Guy',947)}; fight(); peace(); assert(reportCount()==1)")
    unguilded.execute("assert(sentRoutes[1]=='CHANNEL' and sentTargets[1]=='7'); assert(not A.toast or not A.toast:IsShown())")

    # Combat/flag alone, NPC/pet amounts, empty targets, aggregate totals and secrets fail closed.
    for detail in ["damage('Wide Guy',0)", "damage('Wide Guy',10,true)", "damage('Wide Guy',10,false,true)",
                   "damage('Unseen Enemy',10)", "damage('',10)", "damage('Wide Guy','SECRET')",
                   "damage('Wide Guy',0/0)", "damage('Wide Guy',math.huge)"]:
        lua=fresh(); lua.execute("rows={"+detail+"}; fight(); peace(); assert(reportCount()==0 and not A.autoReports.timer)")
    lua=fresh(); lua.execute("fight(); peace(); assert(reportCount()==0)")  # no native damage

    # Delayed readable rows qualify, after target loss/death, at captured combat position.
    lua=fresh()
    lua.execute('''
fight(); combat=false; event('PLAYER_REGEN_ENABLED'); advanceTimers(.6); assert(reportCount()==0)
rows={damage('Wide Guy',10)}; UnitExists=function(u) return u=='player' end
C_Map.GetPlayerMapPosition=function() return {GetXY=function() return .9,.9 end} end
advanceTimers(2); assert(reportCount()==1 and A.List()[1].x==.25)
''')

    # Reused/uncorrelated/ambiguous/changed sessions and source identity are not proof.
    for mutation in [
        "sessions={{sessionID=10}}; currentSession=10",
        "A.autoReports.capture.updated={}",
        "sessions[#sessions+1]={sessionID=99}",
        "C_DamageMeter.GetCombatSessionFromID=function() return {combatSources={{isLocalPlayer=true,sourceGUID='Wrong'}}} end",
        "C_DamageMeter.GetCombatSessionFromID=function() return {combatSources={{isLocalPlayer=true,sourceGUID='Player-player'},{isLocalPlayer=true,sourceGUID='Player-player'}}} end",
        "C_DamageMeter.GetCombatSessionSourceFromID=function() return 'SECRET' end",
        "rows={}; for i=1,513 do rows[i]=damage('Wide Guy',1) end",
        "A.autoReports.capture.ambiguous['wide-guy']=true",
    ]:
        lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); "+mutation+"; peace(); assert(reportCount()==0)")
    for e in ['ZONE_CHANGED_NEW_AREA','SHARD_TRANSFER','SHARD_TRANSFER_IMMINENT','DAMAGE_METER_RESET','PLAYER_ENTERING_WORLD']:
        lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); event('"+e+"'); peace(); assert(reportCount()==0)")
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); map=2; peace(); assert(reportCount()==0)")
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); combat=false; event('PLAYER_REGEN_ENABLED'); advanceTimers(.1); fight(); peace(); assert(reportCount()==0)")

    # Successful manual reports share cooldown and cancel automatic work.
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); assert(A.Report()); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; sendFailure=true; fight(); peace(); local tried=attempts; advanceTimers(130); assert(attempts==tried and reportCount()==0); sendFailure=false; fight(); peace(); assert(reportCount()==1)")

    for e in ['DUEL_REQUESTED','DUEL_TO_THE_DEATH_REQUESTED','DUEL_INBOUNDS','DUEL_OUTOFBOUNDS']:
        lua=fresh()
        lua.execute("event('"+e+"'); rows={damage('Wide Guy',10)}; fight(); assert(not A.Report()); advanceTimers(180); peace(); assert(reportCount()==0)")
        lua.execute("event('DUEL_FINISHED'); advanceTimers(11); fight(); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute("event('DUEL_REQUESTED'); advanceTimers(61); rows={damage('Wide Guy',10)}; fight(); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute("StartDuel=function() end; hooks={}; hooksecurefunc=function(n,f) hooks[n]=f end; A.InitAutoReports(); hooks.StartDuel(); rows={damage('Wide Guy',10)}; fight(); peace(); assert(reportCount()==0)")
    lua=fresh(); lua.execute("combat=true; A.InitAutoReports(); rows={damage('Wide Guy',10)}; fight(); peace(); assert(reportCount()==0); fight(); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); combat='SECRET'; event('PLAYER_TARGET_CHANGED'); combat=true; peace(); assert(reportCount()==0)")
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); A.SetAutoReportsEnabled(false); peace(); assert(reportCount()==0); A.SetAutoReportsEnabled(true); fight(); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute("C_DamageMeter=nil; A.InitAutoReports(); fight(); peace(); assert(reportCount()==0); assert(A.Report())")
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; combat=true; currentSession=11; sessions[#sessions+1]={sessionID=11}; event('DAMAGE_METER_COMBAT_SESSION_UPDATED',7,11); peace(); assert(reportCount()==1)")

    # Regression from the 0.7.9 battle: opponent seen throughout 70 seconds,
    # death ends combat, and only then is native damage attribution readable.
    lua=fresh()
    lua.execute('''
function UnitName(u) return u=='player' and PLAYER or 'Galahad Oathkeeper' end
rows={damage('Galahad Oathkeeper',947)}
local before=meterReads; fight(); advanceTimers(70.482)
assert(combat and reportCount()==0 and meterReads==before and reads==0)
assert(A.autoReports.capture.count==1 and A.autoReports.events.events.PLAYER_DEAD)
combat=false; lockdown=true; event('PLAYER_DEAD')
assert(A.autoReports.capture.state=='reading' and A.autoReports.timer)
UnitExists=function(u) return u=='player' end
C_Map.GetPlayerMapPosition=function() return {GetXY=function() return .9,.9 end} end
advanceTimers(.5); assert(reportCount()==0 and meterReads==before)
lockdown=false; event('PLAYER_REGEN_ENABLED'); advanceTimers(1.5)
assert(reportCount()==1 and A.List()[1].x==.25 and not A.autoReports.timer)
local log=A.SessionLogText()
assert(log:find('player=galahad-oathkeeper',1,true))
assert(log:find('waiting=lockdown',1,true) and log:find('phase=post-combat',1,true))
assert(log:find('incoming opposing-player damage confirmed after combat',1,true))
advanceTimers(10); event('PLAYER_REGEN_ENABLED'); assert(reportCount()==1)
''')

    # A short fight now qualifies after combat; no minimum combat duration.
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); advanceTimers(1); peace(); assert(reportCount()==1)")
    # Outgoing attribution must be a positive per-unit record, never a spell total.
    lua=fresh(); lua.execute("outgoing={damage('Wide Guy',10)}; fight(); peace(); assert(reportCount()==1)")
    for detail in ["damage('Wide Guy',0)", "damage('Wide Guy',10,true)", "damage('Wide Guy',10,false,true)",
                   "damage('Wide Guy','SECRET')", "damage('Unseen Enemy',10)", "{totalAmount=9999}"]:
        lua=fresh(); lua.execute('outgoing={'+detail+'}; fight(); peace(); assert(reportCount()==0)')
    # An unreadable unrelated row must not hide a readable positive player row.
    lua=fresh(); lua.execute("rows={{combatSpellDetails='SECRET'},damage('Wide Guy',10)}; fight(); peace(); assert(reportCount()==1)")

    # No native reads during combat or lockdown, bounded deferred retries,
    # preserved correlation for an update arriving after combat ends.
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); lockdown=true; peace(); assert(reportCount()==0 and reads==0 and not A.autoReports.timer)")
    lua=fresh(); lua.execute("fight(); peace(); assert(reads==6 and reportCount()==0 and not A.autoReports.timer)")
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); A.autoReports.capture.updated={}; combat=false; event('PLAYER_REGEN_ENABLED'); advanceTimers(.6); assert(reportCount()==0); event('DAMAGE_METER_COMBAT_SESSION_UPDATED',7,currentSession); advanceTimers(1.5); assert(reportCount()==1)")
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); C_DamageMeter.GetCombatSessionSourceFromID=function() return 'SECRET' end; peace(); assert(reportCount()==0 and not A.autoReports.timer)")

    # Cancelled/stale timers cannot send or clear a newer timer, including the
    # capture deadline replaced by the reader at death/combat end.
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); local old=A.autoReports.timer; combat=false; event('PLAYER_REGEN_ENABLED'); local reader=A.autoReports.timer; old.fn(); assert(A.autoReports.timer==reader and reportCount()==0); A.SetAutoReportsEnabled(false); reader.fn(); assert(reportCount()==0 and not A.autoReports.timer)")
    lua=fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); combat=false; event('PLAYER_REGEN_ENABLED'); local old=A.autoReports.timer; fight(); old.fn(); peace(); assert(reportCount()==0); fight(); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute('fight(); local before=meterReads; advanceTimers(900); assert(meterReads==before and not A.autoReports.timer and not A.autoReports.capture); peace(); assert(reportCount()==0)')
