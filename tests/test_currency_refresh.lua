-- Safe currency updates: known IDs only, no arbitrary API enumeration, Lua 5.1.
local root=arg[1] or "."
time=function() return 1010 end
CreateFrame=function()
  local f={}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
ComfyData=nil;ComfyDataDB=nil;ComfyDataVault=nil
assert(loadfile(root.."/Core.lua"))("ComfyData")
local D=ComfyData
ComfyDataDB=D:NewDatabase()
D.db=ComfyDataDB
local character="Forever:Hero"
D.GetCurrentKey=function() return character end
local calls={}
local values={[42]=3,[43]=7,[99]=99}
C_CurrencyInfo={GetCurrencyInfo=function(id)
  calls[#calls+1]=id
  if values[id]==nil then return nil end
  return {name="Token "..id,quantity=values[id]}
end}
local checks=0
local function expect(ok,what) checks=checks+1;assert(ok,"Check "..checks..": "..what) end
local ok,why=D:RefreshTrackedCurrencies()
expect(not ok and why=="no known currencies","unknown currencies do not scan")
expect(#calls==0,"no calls without known IDs")
expect(not D:CaptureCurrency(0),"ID 0 rejected")
expect(not D:CaptureCurrency(-42),"negative ID rejected")
expect(not D:CaptureCurrency(42.5),"fractional ID rejected")
expect(#calls==0,"invalid IDs not passed to API")
expect(D:CaptureCurrency(42),"learn ID 42")
expect(#calls==1 and calls[1]==42,"only ID 42 queried")
expect(D.db.wallet.currencies[character]["42"].quantity==3,"initial quantity")
values[42]=5
calls={}
ok=D:RefreshTrackedCurrencies()
expect(ok and #calls==1 and calls[1]==42,"known-ID only refreshed")
expect(D.db.wallet.currencies[character]["42"].quantity==5,"updated quantity retained")
expect(D.db.wallet.currencies[character]["99"]==nil,"unseen ID not fabricated")
expect(D:CaptureCurrency(43),"second ID learned")
values[42]=8
values[43]=10
calls={}
ok=D:RefreshTrackedCurrencies()
expect(ok and #calls==2,"both existing IDs queried")
expect(D.db.wallet.currencies[character]["42"].quantity==8,"first new quantity")
expect(D.db.wallet.currencies[character]["43"].quantity==10,"second new quantity")
C_CurrencyInfo.GetCurrencyInfo=function(id) error("temporary API failure") end
ok=D:RefreshTrackedCurrencies()
expect(not ok,"API exception not counted as success")
expect(D.db.wallet.currencies[character]["42"].quantity==8,"old value preserved after API error")
expect(D.db.wallet.currencies[character]["43"].quantity==10,"second old value preserved")
C_CurrencyInfo=nil
ok=D:RefreshTrackedCurrencies()
expect(not ok,"missing Currency API safely rejected")
expect(D.db.wallet.currencies[character]["42"].quantity==8,"missing API does not delete SavedVariables")
character="Forever:Second"
calls={}
C_CurrencyInfo={GetCurrencyInfo=function(id) calls[#calls+1]=id; return {quantity=5} end}
ok=D:RefreshTrackedCurrencies()
expect(not ok and #calls==0,"currencies cannot leak across characters")
expect(D.db.wallet.currencies[character]==nil,"new character not given phantom data")
print("PASS: "..checks.." tracked-currency refresh safety checks")
