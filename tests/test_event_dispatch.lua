local root = arg[1] or "."
local now = 100
time = function() return now end
GetTime = function() return now end
UnitName = function() return "Hero" end
GetRealmName = function() return "Forever" end
GetMoney = function() return 0 end
UnitXP = function() return 0 end
UnitXPMax = function() return 100 end

local frames = {}
CreateFrame = function()
  local f = { events = {}, scripts = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(e, handler) self.scripts[e] = handler end
  frames[#frames + 1] = f
  return f
end

SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
Settings = nil
ComfyDataVault = nil
ComfyDataDB = nil

assert(loadfile(root .. "/Core.lua"))("ComfyData")
local D = ComfyData

for _, f in ipairs(frames) do
  if f.events.ADDON_LOADED then f.scripts.OnEvent(f, "ADDON_LOADED", "ComfyData") end
end

local frame = assert(D.frame)
assert(frame.events.QUEST_TURNED_IN and frame.events.PLAYER_DEAD and frame.events.CHAT_MSG_LOOT)

-- Exercise actual ComfyData event dispatch, not a fake test handler.
local checked = 0
local function check(value, desc)
    checked = checked + 1
    assert(value, "check " .. checked .. ": " .. desc)
end
local function send(event, ...)
    assert(frame.events[event], "unregistered " .. event)
    assert(type(frame.scripts.OnEvent) == "function", "missing handler")
    frame.scripts.OnEvent(frame, event, ...)
end

now = 100
send("QUEST_TURNED_IN", 321, 50, 20)
check(D.db.quests.completed["321"].total == 1, "first quest counted")
check(D.db.quests.completed["321"].lastXPReward == 50, "quest XP reward")
now = 101
send("QUEST_TURNED_IN", 321, 50, 20)
check(D.db.quests.completed["321"].total == 1, "duplicate quest suppressed")

now = 103
send("PLAYER_DEAD")
check(D.db.kills.deaths["Forever:Hero"].total == 1, "death recorded")
now = 104
send("PLAYER_DEAD")
check(D.db.kills.deaths["Forever:Hero"].total == 1, "duplicate death suppressed")

_G.LOOT_ITEM_SELF = "You receive loot: %s."
now = 106
send("CHAT_MSG_LOOT", "You receive loot: |Hitem:1234:0|h[Ore]|h|r x2.")
check(D.db.loot.items["1234"].total == 2, "self loot quantity")
send("CHAT_MSG_LOOT", "Other receives loot: |Hitem:1234:0|h[Ore]|h|r x10.")
check(D.db.loot.items["1234"].total == 2, "foreign loot ignored")

now = 109
send("QUEST_TURNED_IN", 456, 100, 50)
check(D.db.quests.completed["456"].total == 1, "distinct quest counted")
now = 112
send("PLAYER_DEAD")
check(D.db.kills.deaths["Forever:Hero"].total == 2, "subsequent death counted")

print("PASS: " .. checked .. " event dispatch cases")
