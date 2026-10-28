-- Test quest-complete duplicate suppression across same-second /reload.
local root=arg[1] or "."
local clock=77777
time=function() return clock end
SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function() end}
CreateFrame=function()
 local frame={}
 function frame:RegisterEvent() end
 function frame:SetScript() end
 return frame
end
ComfyData=nil;ComfyDataDB=nil;ComfyDataVault=nil
local function reload()
 ComfyData=nil
 assert(loadfile(root.."/Core.lua"))("ComfyData")
 ComfyData:EnsureDB()
 return ComfyData
end
local current="Forever:Hero"
local function choose(D) D.GetCurrentKey=function() return current end end
local checks=0
local function check(ok,why)checks=checks+1;assert(ok,"Check "..checks..": "..why)end
local D=reload();choose(D)
check(D:RecordQuestCompletion(678,60,200),"first quest completion")
check(D.db.quests.completed["678"].total==1,"account count 1")
check(not D:RecordQuestCompletion(678,60,200),"same-instance duplicate blocked")
D=reload();choose(D)
check(not D:RecordQuestCompletion(678,60,200),"same-second reload duplicate blocked")
check(D.db.quests.completed["678"].total==1,"account quest total unchanged")
clock=clock+2
D=reload();choose(D)
check(not D:RecordQuestCompletion(678,60,200),"two seconds after reload suppressed")
check(D.db.quests.completed["678"].total==1,"no double count after two seconds")
clock=clock+2
D=reload();choose(D)
check(D:RecordQuestCompletion(678,70,300),"repeatable quest later allowed")
check(D.db.quests.completed["678"].total==2,"repeat completion counted")
check(D.db.quests.characters["Forever:Hero"]["678"].count==2,"character counts preserved")
check(D.db.quests.completed["678"].lastXPReward==70,"new reward recorded")
current="Forever:Second";D=reload();choose(D)
check(D:RecordQuestCompletion(678,50,100),"same quest for another character accepted")
check(D.db.quests.completed["678"].total==3,"account aggregates both characters")
check(D.db.quests.characters["Forever:Second"]["678"].count==1,"second character tracked")
check(not D:RecordQuestCompletion(0),"questID zero rejected")
check(not D:RecordQuestCompletion(-1),"negative questID rejected")
for _,bad in ipairs({math.huge,0/0,678.5,2147483648}) do
 local before=D.db.quests.completed["678"].total
 check(not D:RecordQuestCompletion(bad,70,100),"malformed/fractional quest ID rejected")
 check(D.db.quests.completed["678"].total==before,"malformed ID cannot mutate existing quest")
end
print("PASS: "..checks.." quest reload dedupe regression checks")
