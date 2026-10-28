-- Lua 5.1 and 5.4: unique ComfyData sessions even on same-second reload.
local root=arg[1] or "."
local clock=200000
time=function() return clock end
GetTime=function() return 12 end
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
local checks=0
local function expect(ok,msg) checks=checks+1;assert(ok,"Check "..checks..": "..msg) end
ComfyDataDB=D:NewDatabase()
D.db=ComfyDataDB
D.GetCurrentKey=function() return "Forever:Hero" end
local first,err=D:AllocateSessionID(clock)
expect(first=="200000:Forever:Hero" and not err,"preserve legacy format if unique")
D.db.sessions[first]={startedAt=clock,characterKey="Forever:Hero",sentinel="old session"}
local second=D:AllocateSessionID(clock)
expect(second~=first and type(second)=="string","new ID after collision")
expect(D.db.sessions[first].sentinel=="old session","old session remains untouched")
D.db.sessions[second]={startedAt=clock,characterKey="Forever:Hero",sentinel="second session"}
local third=D:AllocateSessionID(clock)
expect(third~=second and third~=first,"multiple reloads same second have unique IDs")
D.db.sessions[third]={startedAt=clock,characterKey="Forever:Hero"}
clock=200001
local later=D:AllocateSessionID(clock)
expect(later=="200001:Forever:Hero","future second receives native ID")
D.db.sessions[later]={startedAt=clock}
D.sessionID=first
D:RecordLoot({itemID=1000,quantity=2,characterKey="Forever:Hero"})
local oldLoot=D.db.loot.sessions[first]["1000"]
expect(oldLoot==2,"first session loot")
D.sessionID=second
D:RecordLoot({itemID=1000,quantity=3,characterKey="Forever:Hero"})
expect(D.db.loot.sessions[second]["1000"]==3,"second session loot separate")
expect(D.db.loot.sessions[first]["1000"]==2,"old session loot not overwritten")
D:RecordKill({npcID=1111,characterKey="Forever:Hero"})
expect(D.db.kills.sessions[second].total==1,"second session kills separate")
D.sessionID=first
D:RecordKill({npcID=2222,characterKey="Forever:Hero"})
expect(D.db.kills.sessions[first].total==1,"first session kills separate")
expect(D.db.kills.sessions[second].total==1,"second session kills unchanged")
D.sessionID=second
D:RecordGather({itemID=2770,itemName="Kupfererz",quantity=2,characterKey="Forever:Hero",mapID=1,nodeKey="node:1"})
expect(D.db.gathering.sessions[second].total==2,"second session gathering separate")
D.sessionID=first
D:RecordGather({itemID=2770,itemName="Kupfererz",quantity=1,characterKey="Forever:Hero",mapID=1,nodeKey="node:1"})
expect(D.db.gathering.sessions[first].total==1,"first session gathering separate")
expect(D.db.gathering.sessions[second].total==2,"second session gathering untouched")
-- Recreating the Lua addon globals after a reload must not reuse IDs in
-- the persistent SavedVariables table loaded from a previous session.
ComfyData=nil
assert(loadfile(root.."/Core.lua"))("ComfyData")
local D2=ComfyData
D2.GetCurrentKey=function() return "Forever:Hero" end
D2:EnsureDB()
local after=D2:AllocateSessionID(clock-1)
expect(after~=first and after~=second and after~=third,"reload reads persistent session IDs")
expect(D2.db.sessions[first].sentinel=="old session","preserved legacy session after reload")
print("PASS: "..checks.." unique-session and preserved-history checks")
