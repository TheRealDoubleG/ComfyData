local root = arg[1] or "."
time=function() return 1200 end
GetTime=function() return 12 end
UnitName=function() return "Hero" end
GetRealmName=function() return "Forever" end
local copper=100
GetMoney=function() return copper end
CreateFrame=function()
    local f={}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
ComfyData=nil; ComfyDataDB=nil
assert(loadfile(root.."/Core.lua"))("ComfyData")
local D=ComfyData
D:EnsureDB()
D.sessionStart=12
D.sessionStartMoney=100
D.sessionMoneyGained=0
D.lastMoney=100
local checks=0
local function verify(ok,msg)
    checks=checks+1
    assert(ok,"wallet test "..checks..": "..msg)
end
local function poll()
    D:RefreshCurrent(false,false)
end
poll()
verify(D.db.wallet.characters["Forever:Hero"]==nil,"no false entry at start")
copper=105
poll()
local wallet=D.db.wallet
verify(wallet.characters["Forever:Hero"].totalEarned==5,"earned five copper")
verify(#wallet.lastChanges==1 and wallet.lastChanges[1].delta==5,"positive entry")
poll()
verify(#wallet.lastChanges==1,"same balance not double-counted")
copper=99
poll()
verify(wallet.characters["Forever:Hero"].totalSpent==6,"spent six copper")
verify(wallet.lastChanges[2].before==105 and wallet.lastChanges[2].after==99,"delta and balances")
verify(D:GetCurrentCharacter().money==99,"last copper balance retained")
verify(D:GetCurrentCharacter().moneySpentTracked==6,"spent money reflected in character record")
C_CurrencyInfo={GetCurrencyInfo=function(id)
    return {name="Test Bronze",quantity=17}
end}
verify(D:CaptureCurrency(42),"API currency captured")
verify(wallet.currencies["Forever:Hero"]["42"].quantity==17,"currency quantity stored")
verify(not D:CaptureCurrency("invalid"),"invalid currency rejected")
for i=1,330 do
    copper=copper+1
    poll()
end
verify(#wallet.lastChanges==300,"wallet history bounded")
verify(wallet.characters["Forever:Hero"].changeCount==332,"whole-session counters preserved")
print("PASS: "..checks.." wallet/currency tracking checks")
