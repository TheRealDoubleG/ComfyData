-- Localized Blizzard loot template regression tests. Lua 5.1 / Lua 5.4.
local root=arg[1] or "."
time=function() return 1000 end
SlashCmdList={}
DEFAULT_CHAT_FRAME={AddMessage=function() end}
CreateFrame=function()
  local f={}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
ComfyData=nil
ComfyDataDB=nil
ComfyDataVault=nil
assert(loadfile(root.."/Core.lua"))("ComfyData")
local D=ComfyData
ComfyDataDB=D:NewDatabase()
D.db=ComfyDataDB
D.GetCurrentKey=function() return "Forever:Tester" end
ComfyDataDB.characters["Forever:Tester"]={money=0,level=1}
local checks=0
local function check(cond,reason) checks=checks+1;assert(cond,"Test "..checks.." failed: "..reason) end
local function item(id,name)
  return "|cff1eff00|Hitem:"..id..":0|h["..name.."]|h|r"
end
local function total(id)
  local r=D:GetDB().loot.items[tostring(id)]
  return r and r.total or 0
end
local function reset_templates()
  for _,s in ipairs({
    "LOOT_ITEM_SELF","LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_CREATED_SELF","LOOT_ITEM_CREATED_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF","LOOT_ITEM_PUSHED_SELF_MULTIPLE",
  }) do _G[s]=nil end
end
reset_templates()
LOOT_ITEM_SELF="You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE="You receive loot: %sx%d."
check(D:HandleLootMessage("You receive loot: "..item(1234,"Copper Ore").."."),"English singular")
check(total(1234)==1,"English singular quantity")
check(D:HandleLootMessage("You receive loot: "..item(1234,"Copper Ore").."x3."),"English multiple")
check(total(1234)==4,"English multiple quantity exact")
check(D:GetDB().loot.items["1234"].name=="Copper Ore","item name stored for item-based bronze diagnosis")
check(not D:HandleLootMessage("Other receives loot: "..item(1234,"Copper Ore").."x5."),"foreign loot rejected")
check(total(1234)==4,"foreign loot not counted")
check(not D:HandleLootMessage("You receive loot: nothing."),"no item link rejected")
reset_templates()
LOOT_ITEM_SELF="Ihr erhaltet Beute: %s."
LOOT_ITEM_SELF_MULTIPLE="Ihr erhaltet Beute: %sx%d."
LOOT_ITEM_CREATED_SELF_MULTIPLE="Ihr stellt %d x %s her."
LOOT_ITEM_PUSHED_SELF="Ihr erhaltet: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE="Ihr erhaltet %d Stück %s."
check(D:HandleLootMessage("Ihr erhaltet Beute: "..item(2222,"Kupfererz").."x2."),"German multiple")
check(total(2222)==2,"German x2 exact")
check(D:HandleLootMessage("Ihr stellt 7 x "..item(3333,"Bandage").." her."),"German count before item")
check(total(3333)==7,"German count before item exact")
check(D:HandleLootMessage("Ihr erhaltet 12 Stück "..item(4444,"Bronze").."."),"German push count before item")
check(total(4444)==12,"German push exact")
check(D:GetDB().loot.items["4444"].name=="Bronze","Bronze item identifiable by name")
check(D:HandleLootMessage("Ihr erhaltet: "..item(5555,"Spezialtoken").."."),"German pushed singular")
check(total(5555)==1,"German singular count")
check(not D:HandleLootMessage("Spieler erhält: "..item(3333,"Bandage").."."),"localized foreign loot rejected")
check(not D:HandleLootMessage("Ihr erhaltet Beute: "..item(4444,"Bronze").."x9999999."),"invalid huge stack not mistaken as one")
check(total(4444)==12,"invalid quantity leaves record unchanged")
check(not D:HandleLootMessage("Ihr erhaltet Beute: "..item(4444,"Bronze").."x0."),"zero stack rejected")
check(total(4444)==12,"zero quantity leaves record unchanged")
reset_templates()
LOOT_ITEM_SELF="You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE="You receive loot: %sx%d."
check(not D:HandleLootMessage("You receive loot: "..item(1234,"Copper Ore").."x4 [not an actual message]"),"template suffix anchored")
check(total(1234)==4,"invalid formatting does not change count")
-- Positional translated format strings, escaped-percent literal and older clients.
reset_templates()
LOOT_ITEM_SELF_MULTIPLE="Beute: %2$d mal %1$s."
check(D:HandleLootMessage("Beute: 6 mal "..item(6666,"Bronzetaler").."."),"positional locale placeholders")
check(total(6666)==6,"positional six exact")
reset_templates()
LOOT_ITEM_PUSHED_SELF="Boni 100%%: %s."
check(D:HandleLootMessage("Boni 100%: "..item(7777,"Extra").."."),"literal percent escaped")
check(total(7777)==1,"literal percent item stored")
reset_templates()
LOOT_ITEM_SELF="You receive loot: %s."
check(D:HandleLootMessage("You receive loot: "..item(8888,"Old Client Ore").." x4."),"older client only singular string")
check(total(8888)==4,"fallback old client x4 quantity")

print("PASS: "..checks.." localized loot parser checks")
