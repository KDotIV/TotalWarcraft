"""Shared source/package regression for Forever's hidden realm metadata."""

def check_hidden_realms(client):
    alice, bob = client('Alice Smith'), client('Bob Jones')
    setup = r'''
function GetRealmName() return '' end
function GetRealmID() return 0 end
function GetNormalizedRealmName() return '' end
function IsInGroup() return true end
function IsInRaid() return false end
function IsInInstance() return false end
function member(u)
 if u=='player' then return PLAYER end
 if u=='party1' then return PLAYER=='Alice Smith' and 'Bob Jones' or 'Alice Smith' end
 if u=='party2' and collision then return 'Other Member' end
end
function UnitName(u)
 local n=member(u); if not n then return end
 if u=='party2' then return 'Alice','Smith' end
 return n:match('^(%S+) (.+)$')
end
function UnitFullName(u)
 if u=='party2' and collision then return 'Alice-Smith','' end
 local n=member(u); return n and n:gsub(' ','-'),''
end
function UnitGUID(u) local n=member(u); return n and ('Player-'..n) end
function UnitIsPlayer(u) return member(u)~=nil end
function UnitDistanceSquared() return 100,true end
function UnitIsPVP() return true end
assert(A.RefreshScope())
A.SetPresenceEnabled(true)
assert(A.WB.Key(A.WB.UnitName('player'))==A.WB.Key(PLAYER:gsub(' ','-')))
assert(A.WB.UUIDValid(A.WB.UUID()))
'''
    for lua in (alice, bob):
        lua.execute(setup)
    packet = alice.globals().packets[1]
    assert alice.globals().sentPrefixes[1] == 'WBP_PRES1'
    bob.globals().A.OnPresenceMessage('WBP_PRES1', packet, 'PARTY', 'Alice Smith')
    bob.execute("assert(#A.PresenceList()==1 and A.PresenceList()[1].guid=='Player-Alice Smith')")
    bob.globals().A.OnPresenceMessage('WBP_PRES1', packet, 'PARTY', 'Outsider Person')
    bob.execute('assert(#A.PresenceList()==1); A.ClearPresence()')
    bob.globals().A.OnPresenceMessage('WBP_PRES1', packet, 'PARTY', 'Alice-Smith')
    bob.execute('assert(#A.PresenceList()==1)')
    bob.execute('collision=true; A.ClearPresence(); A.RefreshPresenceRoster()')
    bob.globals().A.OnPresenceMessage('WBP_PRES1', packet, 'PARTY', 'Alice Smith')
    bob.execute('assert(#A.PresenceList()==0)')
    # Different spellings of our own first/surname cannot create duplicate reports.
    alice.execute('assert(A.Report()); assert(#A.List()==1)')
    report = alice.globals().packets[2]
    assert alice.globals().sentPrefixes[2] == 'WBP_REPORT1'
    for sender in ('Alice Smith', 'Alice-Smith'):
        alice.globals().A.OnReportMessage('WBP_REPORT1', report, 'GUILD', sender)
        alice.execute('assert(#A.List()==1)')
    bob.globals().A.OnReportMessage('WBP_REPORT1', report, 'GUILD', 'Alice-Smith')
    bob.execute('assert(#A.List()==1)')
    # Realm APIs may be unavailable/restricted, rather than returning empty text.
    alice.execute("function GetNormalizedRealmName() return 'SECRET' end; NOW=NOW+121; CLOCK=CLOCK+121; assert(A.Report())")
    print('PASS: hidden realms preserve roster-authenticated presence, reject ambiguous/foreign senders, and deduplicate Forever report self echoes.')
