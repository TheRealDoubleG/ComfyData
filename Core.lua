local ADDON_NAME = ...

ComfyData = ComfyData or {}
local D = ComfyData

D.name = ADDON_NAME or "ComfyData"
D.version = "0.2"
D.schemaVersion = 2

local function Epoch()
    return type(time) == "function" and time() or 0
end

local function Now()
    if type(GetTimePreciseSec) == "function" then
        local ok, v = pcall(GetTimePreciseSec)
        if ok and tonumber(v) then return tonumber(v) end
    end
    if type(GetTime) == "function" then
        local ok, v = pcall(GetTime)
        if ok and tonumber(v) then return tonumber(v) end
    end
    return 0
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return copy
end

local function EnsureTable(parent, key)
    if type(parent[key]) ~= "table" then parent[key] = {} end
    return parent[key]
end

local function CountKeys(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

local function CharacterIdentity()
    local name = type(UnitName) == "function" and UnitName("player") or "Unknown"
    local realm = type(GetRealmName) == "function" and GetRealmName() or ""
    name, realm = tostring(name or "Unknown"), tostring(realm or "")
    return realm .. ":" .. name, name, realm
end

local function BagTotals()
    local free, total = 0, 0
    for bag = 0, 4 do
        local slots, freeSlots
        if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
            local ok, v = pcall(C_Container.GetContainerNumSlots, bag)
            if ok then slots = tonumber(v) end
        elseif type(GetContainerNumSlots) == "function" then
            local ok, v = pcall(GetContainerNumSlots, bag)
            if ok then slots = tonumber(v) end
        end

        if C_Container and type(C_Container.GetContainerNumFreeSlots) == "function" then
            local ok, v = pcall(C_Container.GetContainerNumFreeSlots, bag)
            if ok then freeSlots = tonumber(v) end
        elseif type(GetContainerNumFreeSlots) == "function" then
            local ok, v = pcall(GetContainerNumFreeSlots, bag)
            if ok then freeSlots = tonumber(v) end
        end

        total = total + (slots or 0)
        free = free + (freeSlots or 0)
    end
    return free, total
end

local function DurabilityTotals()
    local current, maximum = 0, 0
    if type(GetInventoryItemDurability) ~= "function" then return current, maximum end
    for slot = 1, 19 do
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        if ok and tonumber(cur) and tonumber(max) and tonumber(max) > 0 then
            current = current + tonumber(cur)
            maximum = maximum + tonumber(max)
        end
    end
    return current, maximum
end

local function PvPKills()
    local session, lifetime = 0, 0
    if type(GetPVPSessionStats) == "function" then
        local ok, hk = pcall(GetPVPSessionStats)
        if ok then session = tonumber(hk) or 0 end
    end
    if type(GetPVPLifetimeStats) == "function" then
        local ok, hk = pcall(GetPVPLifetimeStats)
        if ok then lifetime = tonumber(hk) or 0 end
    end
    return session, lifetime
end

local function CurrentMapPosition()
    if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function" or type(C_Map.GetPlayerMapPosition) ~= "function" then
        return nil
    end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not mapID then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or not pos or type(pos.GetXY) ~= "function" then return mapID end
    local x, y = pos:GetXY()
    if not tonumber(x) or not tonumber(y) then return mapID end
    return mapID, x, y
end

local function NormalizeKey(text)
    return tostring(text or ""):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function KillKey(data)
    if data and data.npcID then return "npc:" .. tostring(data.npcID) end
    return "name:" .. NormalizeKey(data and data.name or "unknown")
end

local function GatherNodeKey(data)
    local mapID = tonumber(data and data.mapID) or 0
    local x = math.floor(((tonumber(data and data.x) or 0) * 1000) + 0.5)
    local y = math.floor(((tonumber(data and data.y) or 0) * 1000) + 0.5)
    local category = NormalizeKey(data and (data.profession or data.category) or "unknown")
    return tostring(mapID) .. ":" .. tostring(x) .. ":" .. tostring(y) .. ":" .. category
end

function D:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200ComfyData:|r " .. tostring(message))
    end
end

function D:NewDatabase()
    return {
        meta = {
            schemaVersion = self.schemaVersion,
            createdAt = Epoch(),
            lastSavedAt = Epoch(),
            migrationHistory = {},
        },
        characters = {},
        kills = {account = {}, characters = {}, sessions = {}, deaths = {}},
        gathering = {nodes = {}, items = {}, zones = {}, characters = {}, sessions = {}},
        sessions = {},
        accountTotals = {},
    }
end

function D:ValidateDB(db)
    if type(db) ~= "table" then return false, "database is not a table" end
    local required = {"characters", "kills", "gathering", "sessions", "accountTotals"}
    for _, key in ipairs(required) do
        if db[key] ~= nil and type(db[key]) ~= "table" then return false, key .. " is invalid" end
    end
    if db.meta ~= nil and type(db.meta) ~= "table" then return false, "meta is invalid" end
    return true
end

function D:EnsureStructure(db)
    db.meta = type(db.meta) == "table" and db.meta or {}
    db.meta.createdAt = db.meta.createdAt or Epoch()
    db.meta.migrationHistory = type(db.meta.migrationHistory) == "table" and db.meta.migrationHistory or {}
    EnsureTable(db, "characters")
    local kills = EnsureTable(db, "kills")
    EnsureTable(kills, "account")
    EnsureTable(kills, "characters")
    EnsureTable(kills, "sessions")
    EnsureTable(kills, "deaths")
    local gathering = EnsureTable(db, "gathering")
    EnsureTable(gathering, "nodes")
    EnsureTable(gathering, "items")
    EnsureTable(gathering, "zones")
    EnsureTable(gathering, "characters")
    EnsureTable(gathering, "sessions")
    EnsureTable(db, "sessions")
    EnsureTable(db, "accountTotals")
    return db
end

function D:CreateVaultSnapshot(reason)
    if type(ComfyDataVault) == "table" and type(ComfyDataVault.CreateSnapshot) == "function" and type(ComfyDataDB) == "table" then
        local ok, result = ComfyDataVault:CreateSnapshot(ComfyDataDB, reason)
        return ok, result
    end
    return false, "vault unavailable"
end

function D:MigrateDB(db)
    self:EnsureStructure(db)
    local oldSchema = tonumber(db.meta.schemaVersion) or tonumber(db.schema) or 1
    if oldSchema >= self.schemaVersion then
        db.meta.schemaVersion = self.schemaVersion
        db.schema = nil
        return db
    end

    self:CreateVaultSnapshot("pre-migration-" .. tostring(oldSchema) .. "-to-" .. tostring(self.schemaVersion))

    if oldSchema < 2 then
        db.meta.migrationHistory[#db.meta.migrationHistory + 1] = {
            from = oldSchema,
            to = 2,
            at = Epoch(),
            version = self.version,
        }
    end

    db.meta.schemaVersion = self.schemaVersion
    db.schema = nil
    self:EnsureStructure(db)
    return db
end

function D:EnsureDB()
    if type(ComfyDataDB) ~= "table" then ComfyDataDB = self:NewDatabase() end

    local valid = self:ValidateDB(ComfyDataDB)
    if not valid then
        local recovered
        if type(ComfyDataVault) == "table" and type(ComfyDataVault.GetLatestSnapshotData) == "function" then
            local data = ComfyDataVault:GetLatestSnapshotData()
            if type(data) == "table" and self:ValidateDB(data) then
                ComfyDataDB = data
                recovered = true
            end
        end
        if not recovered then
            local broken = ComfyDataDB
            ComfyDataDB = self:NewDatabase()
            ComfyDataDB.meta.recoveredBrokenDB = {
                at = Epoch(),
                oldType = type(broken),
            }
        end
    end

    ComfyDataDB = self:MigrateDB(ComfyDataDB)
    self.db = ComfyDataDB
    return self.db
end

function D:GetDB()
    return self:EnsureDB()
end

function D:GetCharacters()
    return self:GetDB().characters
end

function D:GetCurrentKey()
    if not self.currentKey then self.currentKey = CharacterIdentity() end
    return self.currentKey
end

function D:GetCurrentCharacter()
    self:EnsureDB()
    local key, name, realm = CharacterIdentity()
    self.currentKey = key
    local record = self.db.characters[key]
    if type(record) ~= "table" then
        record = {
            identity = {name = name, realm = realm},
            firstSeen = Epoch(),
        }
        self.db.characters[key] = record
    end
    record.identity = type(record.identity) == "table" and record.identity or {}
    record.identity.name, record.identity.realm = name, realm
    record.name, record.realm = name, realm
    return record
end

function D:GetCharacter(key)
    return self:GetCharacters()[key]
end

function D:GetSessionSeconds()
    return math.max(0, Now() - (self.sessionStart or Now()))
end

function D:GetCurrentTotalPlayed()
    local record = self:GetCurrentCharacter()
    local session = self:GetSessionSeconds()
    if self.playedBase ~= nil then
        return math.max(0, self.playedBase + session - (self.playedBaseSession or 0))
    end
    return math.max(0, (tonumber(self.sessionStartStoredTotal) or tonumber(record.totalPlayed) or 0) + session)
end

function D:GetAccountTotals()
    local totals = {money = 0, totalPlayed = 0, lifetimeKills = 0, bagFree = 0, bagTotal = 0, characters = 0}
    for key, record in pairs(self:GetCharacters()) do
        totals.characters = totals.characters + 1
        totals.money = totals.money + (tonumber(record.money) or 0)
        totals.totalPlayed = totals.totalPlayed + (key == self:GetCurrentKey() and self:GetCurrentTotalPlayed() or (tonumber(record.totalPlayed) or 0))
        totals.lifetimeKills = totals.lifetimeKills + (tonumber(record.lifetimeKills) or 0)
        totals.bagFree = totals.bagFree + (tonumber(record.bagFree) or 0)
        totals.bagTotal = totals.bagTotal + (tonumber(record.bagTotal) or 0)
    end
    self.db.accountTotals = totals
    return totals
end

function D:SnapshotReputation()
    local record = self:GetCurrentCharacter()
    record.reputation = record.reputation or {}
    if not C_Reputation or type(C_Reputation.GetNumFactions) ~= "function" or type(C_Reputation.GetFactionDataByIndex) ~= "function" then return end
    local ok, count = pcall(C_Reputation.GetNumFactions)
    count = ok and tonumber(count) or 0
    for i = 1, count do
        local good, data = pcall(C_Reputation.GetFactionDataByIndex, i)
        if good and type(data) == "table" and data.name and not data.isHeader then
            local key = tostring(data.factionID or data.name)
            record.reputation[key] = {
                id = data.factionID,
                name = data.name,
                reaction = data.reaction,
                standing = data.currentStanding,
                min = data.currentReactionThreshold,
                max = data.nextReactionThreshold,
                watched = data.isWatched and true or false,
            }
        end
    end
end

function D:RefreshCurrent(includeBags, includeReputation)
    local record = self:GetCurrentCharacter()
    record.level = type(UnitLevel) == "function" and (tonumber(UnitLevel("player")) or record.level or 0) or (record.level or 0)

    if type(UnitClass) == "function" then
        local className, classFile = UnitClass("player")
        record.class, record.classFile = className or record.class, classFile or record.classFile
    end
    if type(UnitFactionGroup) == "function" then
        local faction = UnitFactionGroup("player")
        record.faction = faction or record.faction
    end

    if type(GetMoney) == "function" then
        local ok, money = pcall(GetMoney)
        if ok then
            money = tonumber(money) or 0
            if self.lastMoney ~= nil and money > self.lastMoney then
                local gain = money - self.lastMoney
                record.moneyGainedTracked = (tonumber(record.moneyGainedTracked) or 0) + gain
                self.sessionMoneyGained = (self.sessionMoneyGained or 0) + gain
            end
            self.lastMoney = money
            record.money = money
            record.sessionMoneyDelta = money - (self.sessionStartMoney or money)
            record.sessionMoneyGained = self.sessionMoneyGained or 0
        end
    end

    if includeBags then record.bagFree, record.bagTotal = BagTotals() end

    local dur, durMax = DurabilityTotals()
    record.durability, record.durabilityMax = dur, durMax
    record.durabilityPercent = durMax > 0 and (dur / durMax) * 100 or nil

    if type(UnitXP) == "function" then record.xp = tonumber(UnitXP("player")) or record.xp or 0 end
    if type(UnitXPMax) == "function" then record.xpMax = tonumber(UnitXPMax("player")) or record.xpMax or 0 end
    if type(GetXPExhaustion) == "function" then record.restedXP = tonumber(GetXPExhaustion()) or 0 end
    record.sessionXPGained = self.sessionXPGained or 0

    local sessionKills, lifetimeKills = PvPKills()
    record.sessionKills, record.lifetimeKills = sessionKills, lifetimeKills
    record.totalPlayed = self:GetCurrentTotalPlayed()
    record.lastSeen = Epoch()

    record.lastFightDPS = self.lastFightDPS or record.lastFightDPS or 0
    record.sessionDamage = self.sessionDamage or 0
    record.sessionCombatSeconds = self.sessionCombatSeconds or 0
    record.sessionDPS = (self.sessionCombatSeconds or 0) > 0 and (self.sessionDamage or 0) / self.sessionCombatSeconds or 0
    record.trackedDamage = tonumber(record.trackedDamage) or 0
    record.trackedCombatSeconds = tonumber(record.trackedCombatSeconds) or 0
    record.trackedDPS = record.trackedCombatSeconds > 0 and record.trackedDamage / record.trackedCombatSeconds or 0

    if includeReputation then self:SnapshotReputation() end

    self.db.meta.lastSavedAt = Epoch()
    self:GetAccountTotals()
    return record
end

function D:GetKillStore()
    return self:GetDB().kills
end

function D:GetKillRecord(key)
    return self:GetKillStore().account[key]
end

function D:GetKillKey(data)
    return KillKey(data)
end

function D:RecordKill(data)
    data = type(data) == "table" and data or {}
    local store = self:GetKillStore()
    local key = KillKey(data)
    local charKey = data.characterKey or self:GetCurrentKey()
    local now = tonumber(data.time) or Epoch()

    local record = store.account[key]
    if type(record) ~= "table" then
        record = {
            key = key,
            npcID = data.npcID,
            name = data.name or "Unknown",
            firstKill = now,
            total = 0,
            zones = {},
            characters = {},
            xpTotal = 0,
            xpSamples = 0,
        }
        store.account[key] = record
    end

    record.name = data.name or record.name
    record.npcID = data.npcID or record.npcID
    record.creatureType = data.creatureType or record.creatureType
    record.classification = data.classification or record.classification
    if tonumber(data.level) then
        record.levelMin = record.levelMin and math.min(record.levelMin, data.level) or data.level
        record.levelMax = record.levelMax and math.max(record.levelMax, data.level) or data.level
    end
    record.total = (tonumber(record.total) or 0) + 1
    record.lastKill = now
    record.characters[charKey] = (tonumber(record.characters[charKey]) or 0) + 1

    local charStore = EnsureTable(store.characters, charKey)
    charStore[key] = (tonumber(charStore[key]) or 0) + 1

    local session = EnsureTable(store.sessions, self.sessionID or "current")
    session.total = (tonumber(session.total) or 0) + 1
    session.startedAt = session.startedAt or self.sessionStartedAt or Epoch()
    session.mobs = type(session.mobs) == "table" and session.mobs or {}
    session.mobs[key] = (tonumber(session.mobs[key]) or 0) + 1

    if data.mapID then
        local zoneKey = tostring(data.mapID)
        record.zones[zoneKey] = (tonumber(record.zones[zoneKey]) or 0) + 1
        record.lastMapID, record.lastX, record.lastY = data.mapID, data.x, data.y
    end

    self.db.meta.lastSavedAt = Epoch()
    return key, record
end

function D:RecordKillXP(key, amount)
    amount = tonumber(amount)
    local record = key and self:GetKillRecord(key)
    if not record or not amount or amount <= 0 then return false end
    record.xpTotal = (tonumber(record.xpTotal) or 0) + amount
    record.xpSamples = (tonumber(record.xpSamples) or 0) + 1
    record.averageXP = record.xpTotal / record.xpSamples
    return true
end

function D:RecordDeath(data)
    local store = self:GetKillStore()
    local charKey = data and data.characterKey or self:GetCurrentKey()
    local deaths = EnsureTable(store.deaths, charKey)
    deaths.total = (tonumber(deaths.total) or 0) + 1
    deaths.lastAt = data and data.time or Epoch()
    deaths.lastKiller = data and data.killer or deaths.lastKiller
    return deaths
end

function D:GetGatherStore()
    return self:GetDB().gathering
end

function D:RecordGather(data)
    data = type(data) == "table" and data or {}
    local itemID = tonumber(data.itemID)
    if not itemID then return false end

    local quantity = math.max(1, tonumber(data.quantity) or 1)
    local store = self:GetGatherStore()
    local charKey = data.characterKey or self:GetCurrentKey()
    local now = tonumber(data.time) or Epoch()
    local mapID = tonumber(data.mapID) or 0
    local nodeKey = data.nodeKey or GatherNodeKey(data)

    local itemKey = tostring(itemID)
    local item = store.items[itemKey]
    if type(item) ~= "table" then
        item = {itemID = itemID, name = data.itemName, total = 0, zones = {}, characters = {}, firstSeen = now}
        store.items[itemKey] = item
    end
    item.name = data.itemName or item.name
    item.total = (tonumber(item.total) or 0) + quantity
    item.lastSeen = now
    item.characters[charKey] = (tonumber(item.characters[charKey]) or 0) + quantity
    if mapID > 0 then item.zones[tostring(mapID)] = (tonumber(item.zones[tostring(mapID)]) or 0) + quantity end

    local node = store.nodes[nodeKey]
    if type(node) ~= "table" then
        node = {
            key = nodeKey,
            mapID = mapID,
            x = data.x,
            y = data.y,
            profession = data.profession,
            category = data.category,
            firstSeen = now,
            visits = 0,
            items = {},
        }
        store.nodes[nodeKey] = node
    end
    node.lastSeen = now
    node.visits = (tonumber(node.visits) or 0) + 1
    node.items[itemKey] = (tonumber(node.items[itemKey]) or 0) + quantity

    local zone = EnsureTable(store.zones, tostring(mapID))
    zone.items = type(zone.items) == "table" and zone.items or {}
    zone.total = (tonumber(zone.total) or 0) + quantity
    zone.items[itemKey] = (tonumber(zone.items[itemKey]) or 0) + quantity

    local char = EnsureTable(store.characters, charKey)
    char.items = type(char.items) == "table" and char.items or {}
    char.total = (tonumber(char.total) or 0) + quantity
    char.items[itemKey] = (tonumber(char.items[itemKey]) or 0) + quantity

    local session = EnsureTable(store.sessions, self.sessionID or "current")
    session.startedAt = session.startedAt or self.sessionStartedAt or Epoch()
    session.total = (tonumber(session.total) or 0) + quantity
    session.items = type(session.items) == "table" and session.items or {}
    session.items[itemKey] = (tonumber(session.items[itemKey]) or 0) + quantity

    self.db.meta.lastSavedAt = Epoch()
    return true, nodeKey, item
end

function D:GetGatherNodesForMap(mapID)
    local out = {}
    mapID = tonumber(mapID)
    if not mapID then return out end
    for _, node in pairs(self:GetGatherStore().nodes) do
        if tonumber(node.mapID) == mapID then out[#out + 1] = node end
    end
    return out
end

function D:GetGatherItem(itemID)
    return self:GetGatherStore().items[tostring(itemID or "")]
end

function D:HandleTimePlayed(totalPlayed)
    totalPlayed = tonumber(totalPlayed)
    if not totalPlayed then return end
    self.playedBase = totalPlayed
    self.playedBaseSession = self:GetSessionSeconds()
    self.sessionStartStoredTotal = totalPlayed
    self:GetCurrentCharacter().totalPlayed = totalPlayed
    self:RefreshCurrent(false, false)
end

function D:StartCombat()
    if self.inCombat then return end
    self.inCombat = true
    self.fightStartedAt = Now()
    self.fightDamage = 0
end

function D:EndCombat()
    if not self.inCombat then return end
    self.inCombat = false
    local duration = math.max(0.01, Now() - (self.fightStartedAt or Now()))
    local damage = tonumber(self.fightDamage) or 0
    self.lastFightDPS = damage / duration
    self.sessionDamage = (self.sessionDamage or 0) + damage
    self.sessionCombatSeconds = (self.sessionCombatSeconds or 0) + duration

    local record = self:GetCurrentCharacter()
    record.trackedDamage = (tonumber(record.trackedDamage) or 0) + damage
    record.trackedCombatSeconds = (tonumber(record.trackedCombatSeconds) or 0) + duration
    record.lastFightDPS = self.lastFightDPS
    self:RefreshCurrent(false, false)
end

function D:HandleCombatLog()
    if type(CombatLogGetCurrentEventInfo) ~= "function" then return end
    local data = {CombatLogGetCurrentEventInfo()}
    local subevent, sourceGUID = data[2], data[4]
    if not sourceGUID or (sourceGUID ~= self.playerGUID and sourceGUID ~= self.petGUID) then return end
    local amount
    if subevent == "SWING_DAMAGE" then
        amount = tonumber(data[12])
    elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "RANGE_DAMAGE" or subevent == "DAMAGE_SHIELD" then
        amount = tonumber(data[15])
    end
    if amount and amount > 0 then
        if not self.inCombat then self:StartCombat() end
        self.fightDamage = (self.fightDamage or 0) + amount
    end
end

function D:GetStatus()
    local db = self:GetDB()
    return {
        version = self.version,
        schemaVersion = db.meta.schemaVersion,
        characters = CountKeys(db.characters),
        killMobs = CountKeys(db.kills.account),
        gatherNodes = CountKeys(db.gathering.nodes),
        gatherItems = CountKeys(db.gathering.items),
        vault = type(ComfyDataVault) == "table",
    }
end

function D:Initialize()
    self:EnsureDB()

    self.sessionStartedAt = Epoch()
    self.sessionID = tostring(self.sessionStartedAt) .. ":" .. self:GetCurrentKey()
    self.sessionStart = Now()
    self.sessionMoneyGained = 0
    self.sessionDamage = 0
    self.sessionCombatSeconds = 0
    self.sessionXPGained = 0
    self.playerGUID = type(UnitGUID) == "function" and UnitGUID("player") or nil
    self.petGUID = type(UnitGUID) == "function" and UnitGUID("pet") or nil

    local record = self:GetCurrentCharacter()
    self.sessionStartStoredTotal = tonumber(record.totalPlayed) or 0
    self.sessionStartMoney = type(GetMoney) == "function" and (tonumber(GetMoney()) or 0) or (tonumber(record.money) or 0)
    self.lastMoney = self.sessionStartMoney
    self.lastXP = type(UnitXP) == "function" and tonumber(UnitXP("player")) or 0
    self.lastXPMax = type(UnitXPMax) == "function" and tonumber(UnitXPMax("player")) or 0

    self.db.sessions[self.sessionID] = {
        startedAt = self.sessionStartedAt,
        characterKey = self:GetCurrentKey(),
    }

    self:RefreshCurrent(true, true)
    self:CreateVaultSnapshot("session-start")
    self.requestPlayedAt = Now() + 3

    local frame = CreateFrame("Frame")
    self.frame = frame
    local events = {
        "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP",
        "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_PVP_KILLS_CHANGED", "TIME_PLAYED_MSG",
        "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_FACTION",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "COMBAT_LOG_EVENT_UNFILTERED",
        "UNIT_PET", "PLAYER_LOGOUT",
    }
    for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "TIME_PLAYED_MSG" then
            D:HandleTimePlayed(...)
            return
        elseif event == "PLAYER_REGEN_DISABLED" then
            D:StartCombat()
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            D:EndCombat()
            return
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            D:HandleCombatLog()
            return
        elseif event == "UNIT_PET" then
            local unit = ...
            if unit == "player" and type(UnitGUID) == "function" then D.petGUID = UnitGUID("pet") end
            return
        elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
            local xp = type(UnitXP) == "function" and tonumber(UnitXP("player")) or 0
            local maxXP = type(UnitXPMax) == "function" and tonumber(UnitXPMax("player")) or 0
            if D.lastXP ~= nil then
                local delta = xp - D.lastXP
                if delta < 0 and D.lastXPMax and D.lastXPMax > 0 then delta = (D.lastXPMax - D.lastXP) + xp end
                if delta > 0 then
                    D.sessionXPGained = (D.sessionXPGained or 0) + delta
                    local current = D:GetCurrentCharacter()
                    current.xpGainedTracked = (tonumber(current.xpGainedTracked) or 0) + delta
                end
            end
            D.lastXP, D.lastXPMax = xp, maxXP
        elseif event == "PLAYER_LOGOUT" then
            local session = D.db.sessions[D.sessionID]
            if session then session.endedAt = Epoch(); session.duration = D:GetSessionSeconds() end
            D:RefreshCurrent(true, true)
            D:CreateVaultSnapshot("logout")
            return
        end

        D:RefreshCurrent(event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD",
            event == "UPDATE_FACTION" or event == "PLAYER_ENTERING_WORLD")
    end)

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + (tonumber(elapsed) or 0)
        if D.requestPlayedAt and Now() >= D.requestPlayedAt then
            D.requestPlayedAt = nil
            if type(RequestTimePlayed) == "function" then pcall(RequestTimePlayed) end
        end
        if self.elapsed >= 10 then
            self.elapsed = 0
            D:RefreshCurrent(false, false)
        end
    end)
end

SLASH_COMFYDATA1 = "/comfydata"
SLASH_COMFYDATA2 = "/cdata"
SlashCmdList.COMFYDATA = function(msg)
    msg = tostring(msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "snapshot" then
        local ok, why = D:CreateVaultSnapshot("manual")
        D:Print(ok and "Vault snapshot created." or ("Snapshot unavailable: " .. tostring(why)))
    elseif msg == "restore" then
        if type(ComfyDataVault) == "table" and type(ComfyDataVault.GetLatestSnapshotData) == "function" then
            local data, snapshot = ComfyDataVault:GetLatestSnapshotData()
            if type(data) == "table" and D:ValidateDB(data) then
                ComfyDataDB = data
                D:Print("Restored snapshot '" .. tostring(snapshot and snapshot.reason or "?") .. "'. Use /reload now.")
            else
                D:Print("No valid Vault snapshot available.")
            end
        else
            D:Print("ComfyDataVault is not loaded.")
        end
    else
        local s = D:GetStatus()
        D:Print("v" .. s.version .. " | schema " .. s.schemaVersion .. " | chars " .. s.characters
            .. " | mobs " .. s.killMobs .. " | nodes " .. s.gatherNodes .. " | gather items " .. s.gatherItems
            .. " | vault " .. (s.vault and "OK" or "missing"))
        D:Print("Commands: /cdata snapshot | /cdata restore")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name == D.name then D:Initialize() end
end)
