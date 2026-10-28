-- Reject impossible gathering data before it reaches SavedVariables.
local root=arg[1] or "."
time=function() return 1234 end
SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function() end}
CreateFrame=function()
 local f={}
 function f:RegisterEvent() end
 function f:SetScript() end
 return f
end
ComfyData=nil;ComfyDataDB=nil;ComfyDataVault=nil
assert(loadfile(root.."/Core.lua"))("ComfyData")
local D=ComfyData
D.GetCurrentKey=function()return "Forever:Miner" end
D.sessionID="safe-test"
D.db=D:NewDatabase();ComfyDataDB=D.db
local checks=0
local function check(cond,what) checks=checks+1;assert(cond,"Check "..checks..": "..what)end
local function invalid(payload,why)
 local before=D.db.gathering.items["2770"] and D.db.gathering.items["2770"].total or 0
 local ok=D:RecordGather(payload)
 check(ok==false,why)
 local after=D.db.gathering.items["2770"] and D.db.gathering.items["2770"].total or 0
 check(before==after,"no saved item mutation after "..why)
end
invalid({itemID=-1,quantity=1},"negative item ID")
invalid({itemID=0,quantity=1},"zero item ID")
invalid({itemID=2770.5,quantity=1},"fractional item ID")
invalid({itemID=math.huge,quantity=1},"infinite item ID")
invalid({itemID=2770,quantity=-2},"negative quantity")
invalid({itemID=2770,quantity=math.huge},"infinite quantity")
invalid({itemID=2770,quantity=0/0},"nan quantity")
invalid({itemID=2770,quantity=100001},"unreasonably huge quantity")
invalid({itemID=2770,quantity=1.5},"fractional quantity")
invalid({itemID=2770,quantity=2,nodeKey={}},"unsafe table-key node identity")
local ok,nodeKey,item=D:RecordGather({itemID=2770,quantity=3,itemName="Copper Ore",mapID=1,profession="Mining",visitID="window-1"})
check(ok and item.total==3,"normal valid ore saved")
check(D.db.gathering.nodes[nodeKey].visits==1,"first node visit")
ok=D:RecordGather({itemID=2770,quantity=2,itemName="Copper Ore",mapID=1,profession="Mining",visitID="window-1"})
check(ok and item.total==5,"second slot same window adds quantity")
check(D.db.gathering.nodes[nodeKey].visits==1,"same visit counted once")
ok=D:RecordGather({itemID=2770,quantity=1,mapID=1,profession="Mining",visitID="window-2"})
check(ok and item.total==6,"second window increases quantity")
check(D.db.gathering.nodes[nodeKey].visits==2,"second visit increments")
check(D.db.gathering.characters["Forever:Miner"].total==6,"per-character sum sound")
print("PASS: "..checks.." gather input-safety regression checks")
