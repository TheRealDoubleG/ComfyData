-- Bad XP signals must not poison kill averages in persisted SavedVariables.
local root=arg[1] or "."
time=function() return 600 end
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
D.db=D:NewDatabase();ComfyDataDB=D.db
D.GetCurrentKey=function() return "Forever:Hero" end
local key,record=D:RecordKill({npcID=111,name="Test Mob"})
local checks=0
local function ck(v,what)checks=checks+1;assert(v,"Check "..checks..": "..what)end
ck(key=="npc:111" and record.total==1,"known mob recorded")
local function invalid(amount,reason)
 local beforeSamples=tonumber(record.xpSamples) or 0
 local beforeTotal=tonumber(record.xpTotal) or 0
 ck(not D:RecordKillXP(key,amount),reason)
 ck((tonumber(record.xpSamples) or 0)==beforeSamples,"samples remain unchanged after "..reason)
 ck((tonumber(record.xpTotal) or 0)==beforeTotal,"XP remains unchanged after "..reason)
end
invalid(-10,"negative XP")
invalid(0,"zero XP")
invalid(math.huge,"infinite XP")
invalid(0/0,"NaN XP")
invalid(12.5,"fractional XP")
invalid(1000000001,"absurd XP")
ck(D:RecordKillXP(key,10),"valid ten XP")
ck(record.averageXP==10 and record.xpSamples==1,"first sample average")
ck(D:RecordKillXP(key,30),"valid thirty XP")
ck(record.averageXP==20 and record.xpSamples==2,"second sample average")
ck(not D:RecordKillXP("npc:missing",10),"missing NPC rejected")
print("PASS: "..checks.." kill XP validation regression checks")
