-- Cross-addon event smoke test: ComfyDataVault -> ComfyData -> ComfyKills.
-- No WoW client required. Not a substitute for real Forever launch testing.
local dataRoot=arg[1] or "."
local vaultRoot=arg[2] or "../ComfyDataVault"
local killsRoot=arg[3] or "../ComfyKills"
local now=1000
local balance=500
local currencyQty=7
time=function() return now end
GetTime=function() return now end
GetMoney=function() return balance end
UnitName=function() return "Hero" end
GetRealmName=function() return "Forever" end
UnitXP=function() return 5 end
UnitXPMax=function() return 100 end
UnitGUID=function(unit)
    if unit=="player" then return "Player-1-2" end
    if unit=="pet" then return "Pet-1-2" end
end
C_CurrencyInfo={GetCurrencyInfo=function(id)
    if id==42 then return {name="Bronze Test Token",quantity=currencyQty} end
end}
_G.LOOT_ITEM_SELF="You receive loot: %s."
_G.LOOT_ITEM_SELF_MULTIPLE="You receive loot: %sx%d."
local frames={}
CreateFrame=function()
    local frame={events={},handlers={}}
    function frame:RegisterEvent(e)
        if e=="COMBAT_LOG_EVENT_UNFILTERED" then error("Forbidden combat event") end
        self.events[e]=true
    end
    function frame:SetScript(e,fn) self.handlers[e]=fn end
    frames[#frames+1]=frame
    return frame
end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
Settings=nil
ComfyData=nil
ComfyDataDB=nil
ComfyDataVault=nil
ComfyDataVaultDB=nil
ComfyKills=nil
local checks=0
local function expect(v,label)
    checks=checks+1
    assert(v,"Integration check "..checks..": "..label)
end
local function emit(frame,event,...)
    expect(frame.events[event]==true,"registered "..event)
    expect(type(frame.handlers.OnEvent)=="function","OnEvent present")
    frame.handlers.OnEvent(frame,event,...)
end
assert(loadfile(vaultRoot.."/Core.lua"))("ComfyDataVault")
local V=ComfyDataVault
assert(loadfile(dataRoot.."/Core.lua"))("ComfyData")
local D=ComfyData
for _,frame in ipairs(frames) do
    if frame.events.ADDON_LOADED then
        frame.handlers.OnEvent(frame,"ADDON_LOADED","ComfyDataVault")
    end
end
for _,frame in ipairs(frames) do
    if frame.events.ADDON_LOADED then
        frame.handlers.OnEvent(frame,"ADDON_LOADED","ComfyData")
    end
end
expect(type(D.frame)=="table","ComfyData initialized")
expect(D.db and type(D.db.characters["Forever:Hero"])=="table","character persisted")
ComfyKills={db={enabled=true,kills={countPetKills=true,trackDeaths=true,milestoneNotifications=false}}}
assert(loadfile(killsRoot.."/Kills.lua"))()
local A=ComfyKills
A:InitializeFeature()
expect(type(A.eventFrame)=="table","ComfyKills registered events")
expect(not D.frame.events.COMBAT_LOG_EVENT_UNFILTERED,"Data does not use forbidden combat log")
expect(not A.eventFrame.events.COMBAT_LOG_EVENT_UNFILTERED,"Kills does not use forbidden combat log")
local mob="Creature-0-1-2-3-1234-00000001"
A.unitCache[mob]={name="Kobold",level=10}
emit(A.eventFrame,"PARTY_KILL","Player-1-2",mob)
expect(D.db.kills.account["npc:1234"].total==1,"kill reached ComfyData")
now=1001
emit(A.eventFrame,"PARTY_KILL","Player-1-2",mob)
expect(D.db.kills.account["npc:1234"].total==1,"kill GUID deduped")
now=1003
emit(D.frame,"PLAYER_DEAD")
emit(A.eventFrame,"PLAYER_DEAD")
expect(D.db.kills.deaths["Forever:Hero"].total==1,"one death, not two")
now=1007
balance=513
emit(D.frame,"PLAYER_MONEY")
expect(D.db.wallet.characters["Forever:Hero"].totalEarned==13,"13 copper captured")
balance=510
emit(D.frame,"PLAYER_MONEY")
expect(D.db.wallet.characters["Forever:Hero"].totalSpent==3,"3 copper spent")
emit(D.frame,"CHAT_MSG_LOOT","You receive loot: |Hitem:1001:0|h[Test Ore]|h|r x3.")
expect(D.db.loot.items["1001"].total==3,"own loot stored")
emit(D.frame,"CHAT_MSG_LOOT","Friend receives loot: |Hitem:1001:0|h[Test Ore]|h|r x5.")
expect(D.db.loot.items["1001"].total==3,"foreign loot excluded")
emit(D.frame,"CURRENCY_DISPLAY_UPDATE",42)
expect(D.db.wallet.currencies["Forever:Hero"]["42"].quantity==7,"currency stored")
expect(D:RefreshTrackedCurrencies()==true,"known currency rescan succeeds")
currencyQty=9
emit(D.frame,"CURRENCY_DISPLAY_UPDATE") -- some clients emit only a general update
expect(D.db.wallet.currencies["Forever:Hero"]["42"].quantity==9,"currency updated without ID")
C_CurrencyInfo.GetCurrencyInfo=function(id)
    if id==42 then return {name="Bronze Test Token",quantity=11} end
    if id==43 then return {name="Badge",quantity=5} end
    return nil
end
emit(D.frame,"CURRENCY_DISPLAY_UPDATE",43)
expect(D.db.wallet.currencies["Forever:Hero"]["43"].quantity==5,"new currency ID captured")
emit(D.frame,"CURRENCY_DISPLAY_UPDATE")
expect(D.db.wallet.currencies["Forever:Hero"]["42"].quantity==11,"existing currency rescanned")
expect(D.db.wallet.currencies["Forever:Hero"]["43"].quantity==5,"second known currency retained")
local savedAPI=C_CurrencyInfo
C_CurrencyInfo=nil
emit(D.frame,"CURRENCY_DISPLAY_UPDATE")
expect(D.db.wallet.currencies["Forever:Hero"]["42"].quantity==11,"missing API does not delete saved currency")
C_CurrencyInfo=savedAPI

emit(D.frame,"QUEST_TURNED_IN",555,10,2)
expect(D.db.quests.completed["555"].total==1,"quest completion stored")
expect(V:CreateSnapshot(D.db,"integration-test"),"full database snapshot accepted")
local saved=V:GetLatestSnapshotData()
expect(saved.loot.items["1001"].total==3,"loot in verified snapshot")
expect(saved.kills.account["npc:1234"].total==1,"kill in verified snapshot")
expect(saved.wallet.characters["Forever:Hero"].totalEarned==13,"copper in verified snapshot")
expect(saved.wallet.currencies["Forever:Hero"]["42"].quantity==11,"currency in verified snapshot")
expect(V:VerifySnapshot(V:GetLatestValidSnapshot()),"snapshot checksum valid")
print("PASS: "..checks.." ComfySuite integration checks")
