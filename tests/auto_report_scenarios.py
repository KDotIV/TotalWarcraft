"""Five-second live activity checks, shared by source and compiled release tests.

Readable meter mocks test logic, not availability in live Forever combat.
"""
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
function UnitName(u) return u=='player' and PLAYER or 'Wide Guy' end
function UnitFullName(u) return UnitName(u),'' end
C_Map.GetBestMapForUnit=function() return map end
Enum.DamageMeterType={DamageTaken=7,DamageDone=0}
sessions={{sessionID=10}}; currentSession=10; rows={}; outgoing={}; available=true; reads=0
C_DamageMeter={
 IsDamageMeterAvailable=function() return available end,
 GetAvailableCombatSessions=function() return sessions end,
 GetCombatSessionFromID=function(sid,kind)
  assert((kind==7 or kind==0) and sid==currentSession); reads=reads+1
  return {combatSources={{isLocalPlayer=true,sourceGUID='Player-player'}}}
 end,
 GetCombatSessionSourceFromID=function(sid,kind,guid)
  assert((kind==7 or kind==0) and guid=='Player-player')
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
function update() event('DAMAGE_METER_COMBAT_SESSION_UPDATED',7,currentSession) end
function fight()
 combat=true; event('PLAYER_REGEN_DISABLED')
 currentSession=currentSession+1; sessions[#sessions+1]={sessionID=currentSession}; update()
end
function peace() combat=false; event('PLAYER_REGEN_ENABLED'); advanceTimers(4) end
function activeFight() fight(); advanceTimers(5) end
A.UpdateAutoReports()
'''


def check_auto_reports(factory):
    def fresh():
        lua = factory('Auto Observer'); lua.execute(SETUP); return lua

    # Log regression: Wide Guy's eleven-second encounter reports at five seconds.
    lua = fresh()
    lua.execute('''
assert(activeTimers()==0)
fight(); assert(reportCount()==0 and reads==0 and A.autoReports.timer)
assert(A.SessionLogText():find('player=wide-guy',1,true))
advanceTimers(4.9); assert(reportCount()==0 and reads==0)
rows={damage('Wide Guy',429),damage('Wide Guy',271)}; update(); advanceTimers(.1)
assert(combat and reportCount()==1 and #A.List()==1 and not A.autoReports.timer)
assert(A.List()[1].expiresAt-NOW==300 and A.List()[1].countUnknown)
assert(A.SessionLogText():find('incoming opposing-player damage confirmed during combat',1,true))
assert(not A.toast or not A.toast:IsShown())
advanceTimers(6); peace(); assert(reportCount()==1)
activeFight(); peace(); assert(reportCount()==1)
advanceTimers(121); activeFight(); peace(); assert(reportCount()==2)
''')
    peer = factory('Peer Reader')
    peer.globals().NOW = lua.globals().NOW
    packet = next(lua.globals().packets[i] for i in range(1, lua.globals().sends + 1)
                  if lua.globals().sentPrefixes[i] == 'WBP_REPORT1')
    peer.globals().A.OnReportMessage('WBP_REPORT1', packet, 'CHANNEL', 'Auto Observer', None, None, 7, 'TotalWarcraftReportComms')
    peer.execute('assert(#A.List()==1)')

    # Either damage direction qualifies; no retaliation or guild required.
    for direction in ('rows', 'outgoing'):
        lua = fresh()
        lua.execute(direction + "={damage('Wide Guy',947)}; inGuild=false; fight(); " + '''
C_Map.GetPlayerMapPosition=function() return {GetXY=function() return .9,.9 end} end
advanceTimers(5); assert(reportCount()==1 and A.List()[1].x==.9)
assert(sentRoutes[1]=='CHANNEL' and sentTargets[1]=='7')
assert(not A.toast or not A.toast:IsShown())
''')

    for condition in ['playerTarget=false', 'enemy=false', 'flagged=false', 'visible=false', 'attackable=false',
                      'instance=true', 'ffa=true', 'sanctuary=true', 'flagged="SECRET"',
                      'UnitCanAttack=nil', 'UnitFactionGroup=function() error("restricted") end',
                      'UnitIsPVPSanctuary=function() return "SECRET" end', 'UnitExists=function() return false end']:
        lua = fresh()
        lua.execute(condition + "; rows={damage('Wide Guy',947)}; activeFight(); peace(); assert(reportCount()==0)")

    # Selected flagged players, NPC/pet rows, totals and secrets are not PvP proof.
    for direction in ('rows', 'outgoing'):
        for detail in ["damage('Wide Guy',0)", "damage('Wide Guy',10,true)", "damage('Wide Guy',10,false,true)",
                       "damage('Unseen Enemy',10)", "damage('',10)", "damage('Wide Guy','SECRET')",
                       "damage('Wide Guy',0/0)", "damage('Wide Guy',math.huge)", "damage('Wide Guy',-1)",
                       "{totalAmount=9999,combatSpellDetails='SECRET'}", "{totalAmount=9999}"]:
            lua = fresh()
            lua.execute(direction + '={' + detail + '}; activeFight(); peace(); assert(reportCount()==0 and not A.autoReports.timer)')
    lua = fresh(); lua.execute('activeFight(); peace(); assert(reportCount()==0)')

    # No post-combat send, including a timer racing the combat-end event.
    lua = fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); advanceTimers(4.9); local old=A.autoReports.timer; peace(); old.fn(); assert(reportCount()==0 and not A.autoReports.timer)")
    lua = fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); combat=false; advanceTimers(10); assert(reportCount()==0 and not A.autoReports.timer)")
    # Rapid restarts receive a new five-second window (old reading state lost it).
    lua = fresh(); lua.execute("fight(); advanceTimers(4); peace(); rows={damage('Wide Guy',10)}; fight(); advanceTimers(4.9); assert(reportCount()==0); advanceTimers(.1); assert(reportCount()==1)")
    lua = fresh(); lua.execute('fight(); local old=A.autoReports.timer; peace(); fight(); local current=A.autoReports.timer; old.fn(); assert(A.autoReports.timer==current); A.SetAutoReportsEnabled(false); assert(current.cancelled and activeTimers()==0)')

    # Rechecks require new damage, not lingering PvP totals and ongoing NPC damage.
    lua = fresh(); lua.execute("activeFight(); assert(reportCount()==0); rows={damage('Wide Guy',10)}; update(); advanceTimers(5); assert(reportCount()==1)")
    lua = fresh(); lua.execute("fight(); A.autoReports.capture.updated={}; rows={damage('Wide Guy',10)}; advanceTimers(5); update(); advanceTimers(5); assert(reportCount()==0); rows={damage('Wide Guy',11)}; update(); advanceTimers(5); assert(reportCount()==1)")
    lua = fresh(); lua.execute("fight(); CLOCK=CLOCK+5.1; NOW=NOW+5; rows={damage('Wide Guy',10)}; A.autoReports.timer.fn(); assert(reportCount()==1)")
    lua = fresh(); lua.execute("playerTarget=false; rows={damage('Wide Guy',10)}; activeFight(); playerTarget=true; event('PLAYER_TARGET_CHANGED'); update(); advanceTimers(5); assert(reportCount()==0); rows={damage('Wide Guy',11)}; update(); advanceTimers(5); assert(reportCount()==1)")

    # Restricted snapshots fail closed. Becoming readable primes a new baseline.
    lua = fresh()
    lua.execute('''
local native=C_DamageMeter.GetCombatSessionSourceFromID
C_DamageMeter.GetCombatSessionSourceFromID=function() return 'SECRET' end
rows={damage('Wide Guy',10)}; activeFight(); assert(reportCount()==0)
assert(A.SessionLogText():find('live damage attribution unavailable/restricted',1,true))
C_DamageMeter.GetCombatSessionSourceFromID=native; update(); advanceTimers(5); assert(reportCount()==0)
update(); advanceTimers(5); assert(reportCount()==0)
rows={damage('Wide Guy',11)}; update(); advanceTimers(5); assert(reportCount()==1)
''')

    for mutation in [
        "sessions={{sessionID=10}}; currentSession=10",
        "A.autoReports.capture.updated={}",
        "sessions[#sessions+1]={sessionID=99}",
        "C_DamageMeter.GetCombatSessionFromID=function() return {combatSources={{isLocalPlayer=true,sourceGUID='Wrong'}}} end",
        "C_DamageMeter.GetCombatSessionFromID=function() return {combatSources={{isLocalPlayer=true,sourceGUID='Player-player'},{isLocalPlayer=true,sourceGUID='Player-player'}}} end",
        "C_DamageMeter.GetCombatSessionFromID=function() return 'SECRET' end",
        "C_DamageMeter.GetCombatSessionSourceFromID=function() return 'SECRET' end",
        "C_DamageMeter.GetCombatSessionSourceFromID=function() error('restricted') end",
        "rows={}; for i=1,513 do rows[i]=damage('Wide Guy',1) end",
        "A.autoReports.capture.ambiguous['wide-guy']=true", "available=false",
    ]:
        lua = fresh()
        lua.execute("rows={damage('Wide Guy',10)}; fight(); " + mutation + '; advanceTimers(5); peace(); assert(reportCount()==0)')
    for e in ['ZONE_CHANGED_NEW_AREA', 'SHARD_TRANSFER', 'SHARD_TRANSFER_IMMINENT', 'DAMAGE_METER_RESET', 'PLAYER_ENTERING_WORLD']:
        lua = fresh()
        lua.execute("rows={damage('Wide Guy',10)}; fight(); event('" + e + "'); advanceTimers(5); peace(); assert(reportCount()==0 and not A.autoReports.timer)")
    lua = fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); map=2; advanceTimers(5); peace(); assert(reportCount()==0)")
    lua = fresh(); lua.execute('activeFight(); sessions={{sessionID=10},{sessionID=99}}; currentSession=99; update(); advanceTimers(5); assert(not A.autoReports.timer and reportCount()==0)')

    # Manual reports share cooldown; unsuccessful automatic sends do not retry.
    lua = fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); assert(A.Report()); advanceTimers(5); peace(); assert(reportCount()==1 and not A.autoReports.timer)")
    lua = fresh(); lua.execute("rows={damage('Wide Guy',10)}; sendFailure=true; activeFight(); local tried=attempts; advanceTimers(130); assert(attempts==tried and reportCount()==0); peace(); sendFailure=false; activeFight(); assert(reportCount()==1)")
    lua = fresh(); lua.execute("rows={damage('Wide Guy',10)}; activeFight(); advanceTimers(121); update(); advanceTimers(5); assert(reportCount()==1 and not A.autoReports.timer)")

    for e in ['DUEL_REQUESTED', 'DUEL_TO_THE_DEATH_REQUESTED', 'DUEL_INBOUNDS', 'DUEL_OUTOFBOUNDS']:
        lua = fresh()
        lua.execute("event('" + e + "'); rows={damage('Wide Guy',10)}; fight(); assert(not A.Report()); advanceTimers(180); peace(); assert(reportCount()==0)")
        lua.execute("event('DUEL_FINISHED'); advanceTimers(11); activeFight(); assert(reportCount()==1)")
        lua = fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); event('" + e + "'); advanceTimers(5); peace(); assert(reportCount()==0)")
    lua = fresh(); lua.execute("event('DUEL_REQUESTED'); advanceTimers(61); rows={damage('Wide Guy',10)}; activeFight(); assert(reportCount()==1)")
    lua = fresh(); lua.execute("StartDuel=function() end; hooks={}; hooksecurefunc=function(n,f) hooks[n]=f end; A.InitAutoReports(); hooks.StartDuel(); rows={damage('Wide Guy',10)}; activeFight(); peace(); assert(reportCount()==0)")
    lua = fresh(); lua.execute("combat=true; A.InitAutoReports(); rows={damage('Wide Guy',10)}; activeFight(); peace(); assert(reportCount()==0); activeFight(); assert(reportCount()==1)")
    lua = fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); combat='SECRET'; event('PLAYER_TARGET_CHANGED'); combat=true; advanceTimers(5); peace(); assert(reportCount()==0)")
    lua = fresh(); lua.execute("rows={damage('Wide Guy',10)}; fight(); A.SetAutoReportsEnabled(false); advanceTimers(5); peace(); assert(reportCount()==0); A.SetAutoReportsEnabled(true); activeFight(); assert(reportCount()==1)")
    lua = fresh(); lua.execute("C_DamageMeter=nil; A.InitAutoReports(); activeFight(); peace(); assert(reportCount()==0); assert(A.Report())")
    lua = fresh(); lua.execute("rows={damage('Wide Guy',10)}; combat=true; currentSession=11; sessions[#sessions+1]={sessionID=11}; update(); advanceTimers(5); assert(reportCount()==1)")
    # One timer per capture, bounded to fifteen minutes, no idle polling.
    lua = fresh(); lua.execute('fight(); assert(activeTimers()==1); advanceTimers(900); assert(reportCount()==0 and not A.autoReports.timer); peace(); assert(activeTimers()==0)')
