local root = arg[1] or "."
local vaultRoot = arg[2] or "../ComfyDataVault"
local epoch=1000
time=function() return epoch end
CreateFrame=function()
    local frame={}
    function frame:RegisterEvent() end
    function frame:SetScript() end
    return frame
end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
ComfyDataDB,ComfyDataVaultDB,ComfyData,ComfyDataVault=nil,nil,nil,nil
assert(loadfile(vaultRoot.."/Core.lua"))("ComfyDataVault")
assert(loadfile(root.."/Core.lua"))("ComfyData")
local V,D=ComfyDataVault,ComfyData
local tests=0
local function expect(v,why)
    tests=tests+1
    assert(v,"Check "..tests..": "..why)
end
local function base()
    local db=D:NewDatabase()
    db.characters["Forever:Hero"]={money=100,level=10}
    db.kills.account["npc:1234"]={name="Goblin",total=7}
    db.loot.items["111"]={itemID=111,total=5,events=2}
    db.wallet.characters["Forever:Hero"]={totalEarned=30,totalSpent=4}
    db.wallet.lastChanges={{at=1000,delta=30}}
    return db
end
local valid=base()
expect(D:ValidateDB(valid),"valid SaveVariables accepted")
expect(V:ValidateData(valid),"valid Vault data accepted")
expect(V:CreateSnapshot(valid,"baseline"),"baseline backup created")
local broken=base()
broken.loot.items="DAMAGED-LOOT-ITEMS"
broken.kills.account["npc:1234"].total=99
broken.wallet.characters["Forever:Hero"].totalEarned=1000
ComfyDataDB=broken
local ok,why=D:ValidateDB(broken)
expect(not ok and why=="loot.items is invalid","malformed loot.items detected explicitly")
local recovered=D:EnsureDB()
expect(type(recovered)=="table","restored verified snapshot")
expect(recovered.kills.account["npc:1234"].total==7,"backup kill count recovered")
expect(recovered.loot.items["111"].total==5,"backup loot count recovered")
expect(recovered.wallet.characters["Forever:Hero"].totalEarned==30,"backup copper recovered")
local quarantined=V:EnsureDB().quarantinedData
expect(quarantined.loot.items=="DAMAGED-LOOT-ITEMS","malformed original preserved")
expect(quarantined.kills.account["npc:1234"].total==99,"newer kills preserved in quarantine")
expect(quarantined.wallet.characters["Forever:Hero"].totalEarned==1000,"newer copper preserved in quarantine")
expect(quarantined~=broken,"quarantine uses independent deep-copy")
expect(V:VerifySnapshot(V:GetSnapshots()[1]),"original snapshot checksum remains valid")

-- Do not replace a newer broken record if the one available quarantine slot
-- is already occupied. This is a deliberate fail-closed policy.
local newer=base()
newer.wallet.lastChanges="BROKEN-HISTORY"
ComfyDataDB=newer
D.blockedReason=nil
local before=ComfyDataDB
local halted,why=D:EnsureDB()
expect(halted==nil and type(why)=="string","second corrupt record blocked")
expect(ComfyDataDB==before and newer.wallet.lastChanges=="BROKEN-HISTORY","no silent overwrite")
expect(V:EnsureDB().quarantinedData.loot.items=="DAMAGED-LOOT-ITEMS","original quarantine not overwritten")

-- Without a Vault, validation must never erase malformed nested records.
ComfyDataVault=nil
D.blockedReason=nil
local damaged=base()
damaged.wallet.characters="DAMAGED-CHARACTER-WALLET"
ComfyDataDB=damaged
local blocked,reason=D:EnsureDB()
expect(blocked==nil and reason,"no-Vault corruption blocks startup")
expect(ComfyDataDB==damaged,"original left intact without Vault")

-- Older valid schema may omit optional sections; missing tables are created.
D.blockedReason=nil
local legacy=base()
legacy.wallet=nil
legacy.quests=nil
legacy.meta.schemaVersion=D.schemaVersion
ComfyDataDB=legacy
local upgraded=D:EnsureDB()
expect(upgraded and type(upgraded.wallet.lastChanges)=="table","missing wallet created compatibly")
expect(type(upgraded.quests.completed)=="table","missing quests created compatibly")
expect(upgraded.loot.items["111"].total==5,"other historical items unchanged")

-- A well-formed checksum must not legalize a damaged structure.
ComfyDataVault=V
for _,section in ipairs({"quests","loot","wallet"}) do
    local malformed=base()
    malformed[section]="MALFORMED-"..section
    expect(not V:ValidateData(malformed),"Vault rejects invalid "..section)
    expect(not V:CreateSnapshot(malformed,"bad-"..section),"bad "..section.." not backed up")
end
for _,pair in ipairs({{"kills","deaths"},{"loot","sessions"},{"quests","completed"},{"wallet","currencies"},{"gathering","nodes"}}) do
    local malformed=base()
    malformed[pair[1]][pair[2]]="MALFORMED"
    expect(not V:ValidateData(malformed),"Vault rejects invalid "..pair[1].."."..pair[2])
    expect(not V:CreateSnapshot(malformed,"bad-nested"),"invalid section cannot enter snapshots")
end
expect(V:CreateSnapshot(base(),"well-formed"),"new valid snapshot accepted")
print("PASS: "..tests.." nested SavedVariables integrity checks")
