-- ComfyData loot API rejects malformed items without recording fake copper/ore.
local root=arg[1] or "."
time=function() return 1234 end
SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function()end}
CreateFrame=function()
 local f={}
 function f:RegisterEvent()end
 function f:SetScript()end
 return f
end
ComfyData=nil;ComfyDataDB=nil;ComfyDataVault=nil
assert(loadfile(root.."/Core.lua"))("ComfyData")
local D=ComfyData
D.GetCurrentKey=function()return "Forever:Looter"end
D.sessionID="safe-test"
D.db=D:NewDatabase();ComfyDataDB=D.db
local checks=0
local function ck(v,msg)checks=checks+1;assert(v,"Check "..checks..": "..msg)end
local function invalid(x,label)
 local before=D.db.loot.items["1234"] and D.db.loot.items["1234"].total or 0
 local ok=D:RecordLoot(x)
 ck(ok==false,label)
 local after=D.db.loot.items["1234"] and D.db.loot.items["1234"].total or 0
 ck(after==before,"no recorded fake loot after "..label)
end
invalid({itemID=-1,quantity=1},"negative loot item")
invalid({itemID=0,quantity=1},"zero loot item")
invalid({itemID=math.huge,quantity=1},"infinite loot item")
invalid({itemID=1234.5,quantity=1},"fractional loot item")
invalid({itemID=1234,quantity=-9},"negative loot amount")
invalid({itemID=1234,quantity=0},"zero loot amount")
invalid({itemID=1234,quantity=math.huge},"infinite loot amount")
invalid({itemID=1234,quantity=0/0},"nan loot amount")
invalid({itemID=1234,quantity=100001},"too much loot")
invalid({itemID=1234,quantity=1.5},"fractional loot amount")
local ok=D:RecordLoot({itemID=1234,quantity=2,name="Copper Ore"})
ck(ok,"valid two items")
ck(D.db.loot.items["1234"].total==2,"valid qty 2")
ck(D.db.loot.characters["Forever:Looter"]["1234"]==2,"per-character quantity")
ok=D:RecordLoot({itemID=1234})
ck(ok,"missing quantity defaults to 1")
ck(D.db.loot.items["1234"].total==3,"legacy quantity default")
ck(D.db.loot.sessions["safe-test"]["1234"]==3,"per-session amount")
print("PASS: "..checks.." loot validation checks")
