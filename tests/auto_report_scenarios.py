"""Incoming native player damage is required; reused against source and release."""
SETUP = r'''
combat=false; targetCombat=true; flagged=true; enemy=true; playerTarget=true
visible=true; attackable=true; instance=false; ffa=false; sanctuary=false; map=1
function UnitExists(u) return u=='player' or u=='target' end
function UnitAffectingCombat(u) return u=='player' and combat or u=='target' and targetCombat or false end
function InCombatLockdown() return combat end
function UnitFactionGroup(u) return u=='target' and (enemy and 'Alliance' or 'Horde') or 'Horde' end
function UnitIsPlayer(u) return u=='player' or u=='target' and playerTarget end
function UnitIsPVP() return flagged end
function UnitIsVisible() return visible end
function UnitCanAttack() return attackable end
function UnitIsPVPFreeForAll() return ffa end
function UnitIsPVPSanctuary() return sanctuary end
function IsInInstance() return instance end
function UnitName(u) return u=='player' and PLAYER or 'Enemy Person' end
function UnitFullName(u) return UnitName(u),'' end
C_Map.GetBestMapForUnit=function() return map end
Enum.DamageMeterType={DamageTaken=7}
sessions={{sessionID=10}}; currentSession=10; rows={}; available=true; reads=0
C_DamageMeter={
 IsDamageMeterAvailable=function() assert(not combat); return available end,
 GetAvailableCombatSessions=function() assert(not combat); return sessions end,
 GetCombatSessionFromID=function(sid,kind)
  assert(not combat and kind==7 and sid==currentSession); reads=reads+1
  return {combatSources={{isLocalPlayer=true,sourceGUID='Player-player'}}}
 end,
 GetCombatSessionSourceFromID=function(sid,kind,guid)
  assert(not combat and kind==7 and guid=='Player-player')
  return {combatSpells=rows}
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
        lua.execute(condition+"; rows={damage('Enemy Person',947)}; fight(); peace(); assert(reportCount()==0)")

    # Native shape from the live PvP capture; no outgoing row is required.
    lua=fresh()
    lua.execute('''
assert(activeTimers()==0)
rows={damage('Enemy Person',429),damage('Enemy Person',271),damage('Enemy Person',206),damage('Enemy Person',41)}
fight(); assert(reportCount()==0 and reads==0 and not A.autoReports.timer)
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
    unguilded.execute("inGuild=false; rows={damage('Enemy Person',947)}; fight(); peace(); assert(reportCount()==1)")
    unguilded.execute("assert(sentRoutes[1]=='CHANNEL' and sentTargets[1]=='7'); assert(not A.toast or not A.toast:IsShown())")

    # Combat/flag alone, NPC/pet amounts, empty targets, aggregate totals and secrets fail closed.
    for detail in ["damage('Enemy Person',0)", "damage('Enemy Person',10,true)", "damage('Enemy Person',10,false,true)",
                   "damage('Unseen Enemy',10)", "damage('',10)", "damage('Enemy Person','SECRET')",
                   "damage('Enemy Person',0/0)", "damage('Enemy Person',math.huge)"]:
        lua=fresh(); lua.execute("rows={"+detail+"}; fight(); peace(); assert(reportCount()==0 and not A.autoReports.timer)")
    lua=fresh(); lua.execute("fight(); peace(); assert(reportCount()==0)")  # no native damage

    # Delayed readable rows qualify, after target loss/death, at captured combat position.
    lua=fresh()
    lua.execute('''
fight(); combat=false; event('PLAYER_REGEN_ENABLED'); advanceTimers(.6); assert(reportCount()==0)
rows={damage('Enemy Person',10)}; UnitExists=function(u) return u=='player' end
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
        "rows={}; for i=1,513 do rows[i]=damage('Enemy Person',1) end",
        "A.autoReports.capture.ambiguous['enemy-person']=true",
    ]:
        lua=fresh(); lua.execute("rows={damage('Enemy Person',10)}; fight(); "+mutation+"; peace(); assert(reportCount()==0)")
    for e in ['ZONE_CHANGED_NEW_AREA','SHARD_TRANSFER','SHARD_TRANSFER_IMMINENT','DAMAGE_METER_RESET','PLAYER_ENTERING_WORLD']:
        lua=fresh(); lua.execute("rows={damage('Enemy Person',10)}; fight(); event('"+e+"'); peace(); assert(reportCount()==0)")
    lua=fresh(); lua.execute("rows={damage('Enemy Person',10)}; fight(); map=2; peace(); assert(reportCount()==0)")
    lua=fresh(); lua.execute("rows={damage('Enemy Person',10)}; fight(); combat=false; event('PLAYER_REGEN_ENABLED'); advanceTimers(.1); fight(); peace(); assert(reportCount()==0)")

    # Successful manual reports share cooldown and cancel automatic work.
    lua=fresh(); lua.execute("rows={damage('Enemy Person',10)}; fight(); assert(A.Report()); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute("rows={damage('Enemy Person',10)}; sendFailure=true; fight(); peace(); local tried=attempts; advanceTimers(130); assert(attempts==tried and reportCount()==0); sendFailure=false; fight(); peace(); assert(reportCount()==1)")

    for e in ['DUEL_REQUESTED','DUEL_TO_THE_DEATH_REQUESTED','DUEL_INBOUNDS','DUEL_OUTOFBOUNDS']:
        lua=fresh()
        lua.execute("event('"+e+"'); rows={damage('Enemy Person',10)}; fight(); assert(not A.Report()); advanceTimers(180); peace(); assert(reportCount()==0)")
        lua.execute("event('DUEL_FINISHED'); advanceTimers(11); fight(); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute("event('DUEL_REQUESTED'); advanceTimers(61); rows={damage('Enemy Person',10)}; fight(); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute("StartDuel=function() end; hooks={}; hooksecurefunc=function(n,f) hooks[n]=f end; A.InitAutoReports(); hooks.StartDuel(); rows={damage('Enemy Person',10)}; fight(); peace(); assert(reportCount()==0)")
    lua=fresh(); lua.execute("combat=true; A.InitAutoReports(); rows={damage('Enemy Person',10)}; fight(); peace(); assert(reportCount()==0); fight(); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute("rows={damage('Enemy Person',10)}; fight(); combat='SECRET'; event('PLAYER_TARGET_CHANGED'); combat=true; peace(); assert(reportCount()==0)")
    lua=fresh(); lua.execute("rows={damage('Enemy Person',10)}; fight(); A.SetAutoReportsEnabled(false); peace(); assert(reportCount()==0); A.SetAutoReportsEnabled(true); fight(); peace(); assert(reportCount()==1)")
    lua=fresh(); lua.execute("C_DamageMeter=nil; A.InitAutoReports(); fight(); peace(); assert(reportCount()==0); assert(A.Report())")
    lua=fresh(); lua.execute("rows={damage('Enemy Person',10)}; combat=true; currentSession=11; sessions[#sessions+1]={sessionID=11}; event('DAMAGE_METER_COMBAT_SESSION_UPDATED',7,11); peace(); assert(reportCount()==1)")

