local root = arg[1] or "."
local vaultRoot = arg[2] or "../ComfyDataVault"
time=function() return 12345 end
CreateFrame=function()
    local f={}
    function f:RegisterEvent() end
    function f:SetScript() end
    return f
end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
local tests=0
local function expect(cond,label) tests=tests+1; assert(cond,"Test "..tests..": "..label) end
ComfyDataVault=nil; ComfyDataVaultDB=nil; ComfyData=nil; ComfyDataDB=nil
assert(loadfile(vaultRoot.."/Core.lua"))("ComfyDataVault")
local V=ComfyDataVault
V:EnsureDB()
assert(loadfile(root.."/Core.lua"))("ComfyData")
local D=ComfyData
local function good()
    local d=D:NewDatabase()
    d.characters["Forever:Hero"]={money=123,level=10}
    return d
end

local live=good()
expect(V:CreateSnapshot(live,"original"),"vault backup")
ComfyDataDB={characters="broken"}
local recovered=D:EnsureDB()
expect(type(recovered)=="table","recovery succeeded")
expect(recovered.characters["Forever:Hero"].money==123,"restored previous valid contents")
expect(V:EnsureDB().quarantinedData.characters=="broken","corrupted current data preserved before verified recovery")

-- Fresh independent Vault fixture for the next corruption scenario.
ComfyDataVaultDB=nil
V:EnsureDB()
expect(V:CreateSnapshot(live,"original-2"),"fresh verified recovery fixture")
D.blockedReason=nil
ComfyDataDB={meta={},characters="broken",kills={account={example=4}}}
local restored,why=D:EnsureDB()
expect(type(restored)=="table","recovery valid when corrupt schema")
expect(restored.characters["Forever:Hero"]~=nil,"recover verified old snapshot")
local before=ComfyDataDB
SlashCmdList.COMFYDATA("restore")
expect(ComfyDataDB==before,"/cdata restore cannot bypass confirmation")

D.blockedReason=nil
ComfyDataVaultDB=nil
V:EnsureDB()
ComfyDataDB={meta="invalid",characters={["Forever:Hero"]={money=5}},skills={"legacy"}}
local result=D:EnsureDB()
expect(type(result)=="table","quarantined corrupted record")
expect(V:EnsureDB().quarantinedData.skills[1]=="legacy","full corrupt copy preserved")
expect(ComfyDataDB.meta.recoveredBrokenDB~=nil,"new DB records recovery reason")
expect(not V:QuarantineData({overwrite=true}),"quarantine cannot be replaced")

D.blockedReason=nil
ComfyDataVault=nil
ComfyDataDB={meta="bad",characters={["Forever:Hero"]={money=10}}}
local original=ComfyDataDB
local safe,err=D:EnsureDB()
expect(safe==nil and err~=nil,"start blocked without vault")
expect(ComfyDataDB==original,"original data untouched without safe backup")

D.blockedReason=nil
ComfyDataVault=V
ComfyDataVaultDB=nil
V:EnsureDB()
ComfyDataDB=good()
ComfyDataDB.meta.schemaVersion=1
local migrated=D:EnsureDB()
expect(migrated.meta.schemaVersion==3,"schema migrated")
local previous=V:GetMigrationSnapshotData()
expect(previous.meta.schemaVersion==1,"pre-migration saved before modification")
expect(V:VerifySnapshot(V:EnsureDB().migrationSnapshot),"migration archive checked")


D:GetDB()
D.GetCurrentKey = function() return "Forever:Hero" end
local questok=D:RecordQuestCompletion(100,50,200)
expect(questok,"quest recorded")
expect(D:GetDB().quests.completed["100"].total==1,"quest count")
expect(not D:RecordQuestCompletion(100,50,200),"duplicate quest suppressed")
expect(D:GetDB().quests.completed["100"].total==1,"duplicate did not inflate count")
expect(D:RecordLoot({itemID=1234,quantity=3}),"loot API")
expect(D:GetDB().loot.items["1234"].total==3,"loot quantity")
_G.LOOT_ITEM_SELF="You receive loot: %s."
expect(not D:HandleLootMessage("Other receives loot: |Hitem:1234:0|h[Ore]|h|r."),"other player skipped")
expect(D:HandleLootMessage("You receive loot: |Hitem:1234:0|h[Ore]|h|r x2."),"self loot recorded")
expect(D:GetDB().loot.items["1234"].total==5,"self loot quantity")
expect(not D:HandleLootMessage("You receive loot: no item link"),"no item link skipped")
D:RecordDeath({time=12345})
expect(D:GetDB().kills.deaths["Forever:Hero"].total==1,"death counted")

-- Regression: non-table top-level SavedVariables must never be lost.
D.blockedReason=nil
ComfyDataVault=nil
ComfyDataDB="recoverable corrupt original"
local untouched,problem=D:EnsureDB()
expect(untouched==nil and type(problem)=="string","non-table DB blocked without Vault")
expect(ComfyDataDB=="recoverable corrupt original","non-table DB preserved without Vault")

D.blockedReason=nil
ComfyDataVault=V
ComfyDataVaultDB=nil
V:EnsureDB()
ComfyDataDB="another corrupt original"
local saved=D:EnsureDB()
expect(type(saved)=="table","non-table DB safe quarantine followed by reset")
expect(V:EnsureDB().quarantinedData=="another corrupt original","non-table original quarantined")

D.blockedReason=nil
ComfyDataVault=nil
ComfyDataDB=nil
expect(type(D:EnsureDB())=="table","first run still creates fresh DB")
print("PASS: "..tests.." ComfyData recovery/migration checks")
