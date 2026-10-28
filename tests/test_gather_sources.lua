-- ComfyData: gather source provenance persisted through SavedVariables.
local root=arg[1] or "."
time=function() return 333 end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
CreateFrame=function()
  local f={}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
ComfyData=nil
ComfyDataVault=nil
ComfyDataDB=nil
assert(loadfile(root.."/Core.lua"))("ComfyData")
local D=ComfyData
ComfyDataDB=D:NewDatabase()
D.db=ComfyDataDB
D.GetCurrentKey=function() return "Forever:Miner" end
ComfyDataDB.characters["Forever:Miner"]={money=123,level=12}
D.sessionID="test:miner"
local checks=0
local function expect(v,why)
 checks=checks+1;assert(v,"Check "..checks..": "..why)
end
local ore={
 itemID=2770,itemName="Kupfererz",quantity=3,
 sourceGUID="GameObject-1-22-33-44-1234-000000001",
 mapID=12,x=0.5,y=0.75,profession="Mining",visitID="ore:1",
}
local ok,nodekey,item=D:RecordGather(ore)
expect(ok,"ore gather recorded")
expect(item.total==3,"quantity 3 saved")
expect(item.lastSourceType=="GameObject","ore provenance GameObject")
expect(item.lastSourceGUID==ore.sourceGUID,"item GUID persisted")
local node=D:GetGatherStore().nodes[nodekey]
expect(node.lastSourceType=="GameObject","node provenance type")
expect(node.lastSourceGUID==ore.sourceGUID,"node GUID persisted")
expect(node.visits==1,"first visit")
ore.quantity=2
D:RecordGather(ore)
expect(node.visits==1,"repeat slot same visit not counted as new node visit")
expect(item.total==5,"two ore pieces added after separate item collection")
ore.visitID="loot:2"
ore.sourceGUID="Creature-1-22-33-44-5555-000000002"
D:RecordGather(ore)
expect(item.lastSourceType=="Creature","creature source distinguished from ore vein")
expect(node.lastSourceType=="Creature","node source updated")
expect(node.visits==2,"new visit tracked")
ore.visitID="loot:3"
ore.sourceGUID=nil
D:RecordGather(ore)
expect(node.visits==3,"missing source API does not lose gather")
expect(node.lastSourceType=="Creature","known provenance preserved on missing source")
expect(D:GetGatherStore().characters["Forever:Miner"].total==9,"full character gather quantity")
expect(D:GetGatherStore().items["2770"].total==9,"global ore amount")
print("PASS: "..checks.." ComfyData gathering provenance checks")
