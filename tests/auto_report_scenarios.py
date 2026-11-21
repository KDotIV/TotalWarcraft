"""Behavioral checks reused against source and physically stripped release."""
SETUP = r'''
combat=false; targetCombat=true; flagged=true; enemy=true; playerTarget=true
visible=true; attackable=true; dead=false; instance=false; ffa=false; sanctuary=false
function UnitExists(u) return u=='player' or u=='target' end
function UnitAffectingCombat(u) return u=='player' and combat or u=='target' and targetCombat or false end
function UnitFactionGroup(u) return u=='target' and (enemy and 'Alliance' or 'Horde') or 'Horde' end
function UnitIsPlayer(u) return u=='player' or u=='target' and playerTarget end
function UnitIsPVP(u) return flagged end
function UnitIsVisible(u) return visible end
function UnitCanAttack(a,b) return attackable end
function UnitIsDeadOrGhost(u) return dead end
function UnitIsPVPFreeForAll(u) return ffa end
function UnitIsPVPSanctuary(u) return sanctuary end
function IsInInstance() return instance end
function reportCount()
 local n=0; for _,prefix in ipairs(sentPrefixes) do if prefix=='WBP_REPORT1' then n=n+1 end end; return n
end
function step(seconds,event)
 CLOCK=CLOCK+(seconds or 1); NOW=NOW+(seconds or 1)
 A.autoReports.events.scripts.OnEvent(nil,event or 'PLAYER_TARGET_CHANGED')
end
A.UpdateAutoReports()
'''

def check_auto_reports(factory):
    def fresh():
        lua=factory('Auto Observer'); lua.execute(SETUP); return lua

    for condition in ['playerTarget=false','enemy=false','flagged=false','targetCombat=false',
                      'visible=false','attackable=false','dead=true','instance=true','inGuild=false',
                      'ffa=true','sanctuary=true','flagged="SECRET"','UnitCanAttack=nil',
                      'UnitFactionGroup=function() error("restricted") end',
                      'UnitIsPVPSanctuary=function() return "SECRET" end',
                      'UnitExists=function() return false end']:
        lua=fresh()
        lua.execute(condition+"; combat=true; step(); assert(reportCount()==0)")

    lua=fresh()
    lua.execute('''
assert(A.db.autoReports and reportCount()==0 and not A.autoReports.timer)
combat=true; playerTarget=false; step(); assert(reportCount()==0 and A.autoReports.timer)
playerTarget=true; step(); assert(reportCount()==1 and #A.List()==1)
assert(A.List()[1].observedCount==1 and A.List()[1].countUnknown)
assert(A.List()[1].expiresAt-NOW==300)
step(121); assert(reportCount()==1) -- same combat never repeats
combat=false; step(); assert(not A.autoReports.timer)
combat=true; step(); assert(reportCount()==2)
combat=false; step(); combat=true; step(); assert(reportCount()==2) -- shared cooldown
step(120); assert(reportCount()==3)
SlashCmdList.WARBANDPVP('auto off'); assert(not A.db.autoReports and not A.autoReports.timer)
combat=false; step(); combat=true; step(121); assert(reportCount()==3)
SlashCmdList.WARBANDPVP('auto on'); assert(A.db.autoReports and reportCount()==4)
''')
    peer=factory('Peer Reader')
    packet=next(lua.globals().packets[i] for i in range(1,lua.globals().sends+1)
                if lua.globals().sentPrefixes[i]=='WBP_REPORT1')
    peer.globals().A.OnGuildMessage('WBP_REPORT1',packet,'GUILD','Auto Observer')
    peer.execute('assert(#A.List()==1 and A.List()[1].observedCount==1)')

    lua=fresh()
    lua.execute('''
-- A manual accepted report already covers this combat.
combat=true; assert(A.Report()); step(); assert(reportCount()==1)
step(121); assert(reportCount()==1)
''')
    lua=fresh()
    lua.execute('''
sendFailure=true; combat=true; step(); local tried=attempts
step(121); assert(attempts==tried and reportCount()==0)
combat=false; step(); sendFailure=false; combat=true; step(); assert(reportCount()==1)
''')
    # All local duel signals suppress manual as well as automatic submissions.
    for event in ['DUEL_REQUESTED','DUEL_TO_THE_DEATH_REQUESTED','DUEL_INBOUNDS','DUEL_OUTOFBOUNDS']:
        lua=fresh()
        lua.execute(f"step(1,'{event}'); combat=true; step(); assert(not A.Report()); step(180); assert(reportCount()==0)")
        lua.execute('''
step(1,'DUEL_FINISHED'); step(11); assert(reportCount()==0) -- lingering combat
combat=false; step(); step(11); combat=true; step(); assert(reportCount()==1)
''')
    lua=fresh()
    lua.execute('''
-- An ignored/declined request cannot disable reporting indefinitely.
step(1,'DUEL_REQUESTED'); step(61); combat=true; step(); assert(reportCount()==1)
''')
    lua=fresh()
    lua.execute('''
-- Outgoing requests are observed without calling, replacing or accepting a duel.
StartDuel=function() end; duelHooks={}
hooksecurefunc=function(name,fn) duelHooks[name]=fn end
A.InitAutoReports(); assert(duelHooks.StartDuel)
duelHooks.StartDuel(); combat=true; step(); step(180); assert(reportCount()==0)
''')
    lua=fresh()
    lua.execute('''
-- Loading mid-combat never assumes that a missed duel event meant no duel.
combat=true; A.InitAutoReports(); step(121); assert(reportCount()==0)
combat=false; step(); combat=true; step(); assert(reportCount()==1)
''')
    lua=fresh()
    lua.execute('''
SlashCmdList.WARBANDPVP('auto off'); A.InitAutoReports()
combat=true; step(); assert(not A.db.autoReports and reportCount()==0)
''')
    lua=fresh()
    lua.execute('''
combat=true; step(); assert(reportCount()==1)
combat='SECRET'; step(); assert(A.autoReports.awaitPeace and not A.autoReports.timer)
combat=true; step(121); assert(reportCount()==1)
combat=false; step(); combat=true; step(); assert(reportCount()==2)
''')

