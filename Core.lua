local ADDON_NAME = ...

ComfyData = ComfyData or {}
local D = ComfyData

D.name = ADDON_NAME or "ComfyData"
D.version = "0.7"
D.schemaVersion = 3

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
        quests = {completed = {}, characters = {}},
        loot = {items = {}, characters = {}, sessions = {}},
        wallet = {characters = {}, lastChanges = {}, currencies = {}},
        sessions = {},
        accountTotals = {},
    }
end

function D:ValidateDB(db)
    if type(db) ~= "table" then return false, "database is not a table" end
    local required = {"characters", "kills", "gathering", "quests", "loot", "wallet", "sessions", "accountTotals"}
    for _, key in ipairs(required) do
        if db[key] ~= nil and type(db[key]) ~= "table" then return false, key .. " is invalid" end
    end
    if db.meta ~= nil and type(db.meta) ~= "table" then return false, "meta is invalid" end
    -- Never silently replace a corrupted *nested* SavedVariables table.
    -- Missing tables are normal for older addon versions and can be created.
    local nested = {
        kills = {"account", "characters", "sessions", "deaths"},
        gathering = {"nodes", "items", "zones", "characters", "sessions"},
        quests = {"completed", "characters"},
        loot = {"items", "characters", "sessions"},
        wallet = {"characters", "lastChanges", "currencies"},
    }
    for section, keys in pairs(nested) do
        local parent = db[section]
        if type(parent) == "table" then
            for _, key in ipairs(keys) do
                if parent[key] ~= nil and type(parent[key]) ~= "table" then
                    return false, section .. "." .. key .. " is invalid"
                end
            end
        end
    end
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
    local quests = EnsureTable(db, "quests")
    EnsureTable(quests, "completed")
    EnsureTable(quests, "characters")
    local loot = EnsureTable(db, "loot")
    EnsureTable(loot, "items")
    EnsureTable(loot, "characters")
    EnsureTable(loot, "sessions")
    local wallet = EnsureTable(db, "wallet")
    EnsureTable(wallet, "characters")
    EnsureTable(wallet, "lastChanges")
    EnsureTable(wallet, "currencies")
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
    local meta = type(db.meta) == "table" and db.meta or {}
    local oldSchema = tonumber(meta.schemaVersion) or tonumber(db.schema) or 1
    if oldSchema < self.schemaVersion then
        -- Never migrate a populated DB without first preserving its original state.
        -- A failed Vault write must not silently erase the only recoverable copy.
        local ok, why = self:CreateVaultSnapshot(
            "pre-migration-" .. tostring(oldSchema) .. "-to-" .. tostring(self.schemaVersion))
        local hasCharacters = type(db.characters) == "table" and next(db.characters) ~= nil
        if not ok and hasCharacters then
            return nil, "pre-migration backup failed: " .. tostring(why)
        end
    end

    self:EnsureStructure(db)
    if oldSchema >= self.schemaVersion then
        db.meta.schemaVersion = oldSchema -- Never downgrade newer schema data.
        db.schema = nil
        return db
    end

    if oldSchema < 2 then
        db.meta.migrationHistory[#db.meta.migrationHistory + 1] = {
            from = oldSchema, to = 2, at = Epoch(), version = self.version,
        }
    end
    if oldSchema < 3 then
        db.meta.migrationHistory[#db.meta.migrationHistory + 1] = {
            from = math.max(2, oldSchema), to = 3, at = Epoch(), version = self.version,
        }
    end
    db.meta.schemaVersion = self.schemaVersion
    db.schema = nil
    self:EnsureStructure(db)
    return db
end

function D:EnsureDB()
    if self.blockedReason then return nil, self.blockedReason end
    -- nil is a normal first launch. Any other non-table value indicates
    -- damage: preserve it via verified recovery/quarantine instead of losing it.
    if ComfyDataDB == nil then ComfyDataDB = self:NewDatabase() end

    local valid, why = self:ValidateDB(ComfyDataDB)
    if not valid then
        local recovered
        if type(ComfyDataVault) == "table" and type(ComfyDataVault.GetLatestSnapshotData) == "function" then
            local data = ComfyDataVault:GetLatestSnapshotData()
            if type(data) == "table" and self:ValidateDB(data) then
                -- Keep the broken but potentially newer data for inspection.
                -- An older verified snapshot can omit recently earned items.
                local saved, err = false, "quarantine unavailable"
                if type(ComfyDataVault.QuarantineData) == "function" then
                    saved, err = ComfyDataVault:QuarantineData(ComfyDataDB, why)
                end
                if not saved then
                    self.blockedReason = "recovery blocked: cannot preserve original: " .. tostring(err)
                    self:Print(self.blockedReason)
                    return nil, self.blockedReason
                end
                ComfyDataDB = data
                recovered = true
                self:Print("Verified snapshot loaded; original preserved in Vault quarantine.")
            end
        end
        if not recovered then
            local broken = ComfyDataDB
            local quarantined = false
            if type(ComfyDataVault) == "table" and type(ComfyDataVault.QuarantineData) == "function" then
                quarantined = ComfyDataVault:QuarantineData(broken, why)
            end
            if not quarantined then
                self.blockedReason = "invalid DB and no safe quarantine: " .. tostring(why)
                self:Print(self.blockedReason .. " - no automatic reset; restore with /cdvault.")
                return nil, self.blockedReason
            end
            ComfyDataDB = self:NewDatabase()
            ComfyDataDB.meta.recoveredBrokenDB = {
                at = Epoch(), oldType = type(broken), reason = why,
            }
            self:Print("Corrupt DB preserved in the Vault quarantine before reset.")
        end
    end

    local migrated, err = self:MigrateDB(ComfyDataDB)
    if not migrated then
        self.blockedReason = err
        self:Print("Database startup stopped: " .. tostring(err))
        return nil, err
    end
    ComfyDataDB = migrated
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
            if self.lastMoney ~= nil and money ~= self.lastMoney then
                -- Currency in integer copper: retain both positive and negative
                -- changes, rather than only tracking gross inflows.
                local delta = money - self.lastMoney
                local wallet = EnsureTable(self.db, "wallet")
                local char = EnsureTable(EnsureTable(wallet, "characters"), self:GetCurrentKey())
                char.totalEarned = (tonumber(char.totalEarned) or 0) + math.max(0, delta)
                char.totalSpent = (tonumber(char.totalSpent) or 0) + math.max(0, -delta)
                char.changeCount = (tonumber(char.changeCount) or 0) + 1
                char.lastBalance, char.lastChangeAt = money, Epoch()
                local changes = EnsureTable(wallet, "lastChanges")
                changes[#changes+1] = {at=Epoch(), characterKey=self:GetCurrentKey(),
                    before=self.lastMoney, after=money, delta=delta}
                if #changes > 300 then table.remove(changes, 1) end
                if delta > 0 then
                    record.moneyGainedTracked = (tonumber(record.moneyGainedTracked) or 0) + delta
                    self.sessionMoneyGained = (self.sessionMoneyGained or 0) + delta
                else
                    record.moneySpentTracked = (tonumber(record.moneySpentTracked) or 0) - delta
                end
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

function D:CaptureCurrency(currencyID)
    currencyID = tonumber(currencyID)
    if not currencyID or currencyID < 1 or currencyID ~= math.floor(currencyID)
        or type(C_CurrencyInfo) ~= "table"
        or type(C_CurrencyInfo.GetCurrencyInfo) ~= "function" then return false end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if not ok or type(info) ~= "table" then return false end
    local safe, quantity, name = pcall(function()
        return tonumber(info.quantity), type(info.name) == "string" and info.name or nil
    end)
    -- Currency API balances are nonnegative whole-token counts.
    -- NaN and infinity must never reach persisted SavedVariables.
    if not safe or not quantity or quantity < 0 or quantity > 1000000000000
        or quantity % 1 ~= 0 then return false end
    local key = tostring(math.floor(currencyID))
    local wallet = EnsureTable(self:GetDB(), "wallet")
    local byChar = EnsureTable(EnsureTable(wallet, "currencies"), self:GetCurrentKey())
    local existing = type(byChar[key]) == "table" and byChar[key] or {}
    existing.quantity = quantity
    existing.name = name or existing.name
    existing.lastSeen = Epoch()
    byChar[key] = existing
    return true
end

-- Some client builds emit CURRENCY_DISPLAY_UPDATE without a currency ID.
-- Safely refresh only currencies already learned for this character.
-- Newly introduced IDs still require an explicit event or separate discovery.
function D:RefreshTrackedCurrencies()
    if type(C_CurrencyInfo) ~= "table"
        or type(C_CurrencyInfo.GetCurrencyInfo) ~= "function" then
        return false, "currency API unavailable"
    end
    local db = self:GetDB()
    local wallet = type(db.wallet) == "table" and db.wallet or nil
    local byChar = wallet and type(wallet.currencies) == "table"
        and wallet.currencies[self:GetCurrentKey()] or nil
    if type(byChar) ~= "table" then return false, "no known currencies" end
    local refreshed, examined = 0, 0
    for key, record in pairs(byChar) do
        local id = tonumber(key)
        if type(record) == "table" and id and id >= 1 and id == math.floor(id) then
            examined = examined + 1
            if examined > 256 then break end
            if self:CaptureCurrency(id) then refreshed = refreshed + 1 end
        end
    end
    return refreshed > 0, refreshed
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

function D:RecordQuestCompletion(questID, xpReward, moneyReward)
    questID = tonumber(questID)
    if not questID or questID <= 0 or questID > 2147483647
        or questID % 1 ~= 0 then return false, "invalid quest ID" end
    local charKey = self:GetCurrentKey()
    local key = tostring(math.floor(questID))
    local now = Epoch()
    local quests = EnsureTable(self:GetDB(), "quests")
    local previousChar = type(quests.characters[charKey]) == "table"
        and quests.characters[charKey] or nil
    local previousQuest = previousChar and previousChar[key] or nil
    local previousAt = type(previousQuest) == "table"
        and tonumber(previousQuest.lastAt) or nil
    -- Unlike the in-memory event cache, the character's SavedVariables
    -- survives /reload. Reject repeated events from the same few seconds
    -- without suppressing a later, genuinely repeatable quest.
    if previousAt and now >= previousAt and now - previousAt < 3 then
        return false, "duplicate event"
    end
    self.recentQuestEvents = self.recentQuestEvents or {}
    local recentKey = charKey .. ":" .. key
    if self.recentQuestEvents[recentKey] and now - self.recentQuestEvents[recentKey] < 3 then
        return false, "duplicate event"
    end
    self.recentQuestEvents[recentKey] = now
    local completed = EnsureTable(quests, "completed")
    local record = completed[key] or {questID = questID, firstAt = now, total = 0, characters = {}}
    completed[key] = record
    record.total = (record.total or 0) + 1
    record.lastAt = now
    record.characters[charKey] = (record.characters[charKey] or 0) + 1
    local ok, rewardXP = pcall(tonumber, xpReward)
    if ok and rewardXP then record.lastXPReward = rewardXP end
    ok, rewardXP = pcall(tonumber, moneyReward)
    if ok and rewardXP then record.lastMoneyReward = rewardXP end
    if C_QuestLog and type(C_QuestLog.GetTitleForQuestID) == "function" then
        local valid, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if valid and type(title) == "string" then record.title = title end
    end
    local byCharacter = EnsureTable(EnsureTable(quests, "characters"), charKey)
    local entry = byCharacter[key] or {count = 0}
    entry.count = entry.count + 1
    entry.lastAt = now
    byCharacter[key] = entry
    self.db.meta.lastSavedAt = now
    return true
end

function D:RecordLoot(data)
    if type(data) ~= "table" then return false, "invalid loot" end
    local itemID = tonumber(data.itemID)
    if not itemID or itemID < 1 or itemID > 2147483647
        or itemID % 1 ~= 0 then return false, "invalid itemID" end
    local quantity = data.quantity == nil and 1 or tonumber(data.quantity)
    if not quantity or quantity < 1 or quantity > 100000
        or quantity % 1 ~= 0 then return false, "invalid quantity" end
    local now = tonumber(data.time) or Epoch()
    local charKey = data.characterKey or self:GetCurrentKey()
    local loot = EnsureTable(self:GetDB(), "loot")
    local items = EnsureTable(loot, "items")
    local key = tostring(math.floor(itemID))
    local record = items[key] or {itemID = itemID, firstAt = now, total = 0, events = 0}
    items[key] = record
    record.total = record.total + quantity
    record.events = record.events + 1
    record.lastAt = now
    if type(data.name) == "string" then record.name = data.name end
    local byCharacter = EnsureTable(EnsureTable(loot, "characters"), charKey)
    byCharacter[key] = (byCharacter[key] or 0) + quantity
    local bySession = EnsureTable(EnsureTable(loot, "sessions"), self.sessionID or "current")
    bySession[key] = (bySession[key] or 0) + quantity
    self.db.meta.lastSavedAt = now
    return true
end

-- Match the actual Blizzard-localized self-loot format, not only its prefix.
-- LOOT_ITEM_SELF_MULTIPLE may be "%sx%d" or "%d x %s" across locales.
-- Never interpret an unrelated player's loot message as our own.
local SELF_LOOT_TEMPLATES = {
    "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF",
    "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_PUSHED_SELF",
}

local function MatchSelfLootTemplate(message, template)
    if type(message) ~= "string" or type(template) ~= "string" then return nil end
    local pattern, placeholders = {"^"}, {}
    local i = 1
    local magic = "^$()%.[]*+-?"
    while i <= #template do
        local c = template:sub(i, i)
        if c ~= "%" then
            pattern[#pattern + 1] = magic:find(c, 1, true) and ("%" .. c) or c
            i = i + 1
        else
            local pos, kind = template:sub(i):match("^%%(%d+)%$([sd])")
            if pos then
                i = i + #pos + 3
            else
                kind = template:sub(i + 1, i + 1)
                i = i + 2
            end
            if kind == "s" then
                placeholders[#placeholders + 1] = "s"
                pattern[#pattern + 1] = "(.+)"
            elseif kind == "d" then
                placeholders[#placeholders + 1] = "d"
                pattern[#pattern + 1] = "(%d+)"
            elseif kind == "%" then
                pattern[#pattern + 1] = "%%"
            else
                return nil
            end
        end
    end
    if #placeholders == 0 then return nil end
    pattern[#pattern + 1] = "$"
    local captures = {message:match(table.concat(pattern))}
    if #captures ~= #placeholders then return nil end
    local text, amount, hasExplicitAmount = nil, 1, false
    for n, kind in ipairs(placeholders) do
        if kind == "s" and captures[n]:find("|Hitem:", 1, true) then
            text = captures[n]
        elseif kind == "d" then
            amount = tonumber(captures[n])
            hasExplicitAmount = true
        end
    end
    if not text then return nil end
    -- Some older clients or offline fixtures omit the MULTIPLE global.
    -- A visible xN *after* the final hyperlink is still safely recoverable.
    if not hasExplicitAmount then
        local suffixCount = text:match("|h|r%s*[xX](%d+)%s*$")
        if suffixCount then amount = tonumber(suffixCount) end
    end
    return text, amount
end

function D:HandleLootMessage(message)
    if type(message) ~= "string" then return false, "not a loot message" end
    for _, constant in ipairs(SELF_LOOT_TEMPLATES) do
        local itemText, amount = MatchSelfLootTemplate(message, _G[constant])
        if itemText then
            local id = itemText:match("|Hitem:(%d+):")
            if not id then return false, "no item link" end
            if not amount or amount < 1 or amount > 100000 or amount ~= math.floor(amount) then
                return false, "invalid loot quantity"
            end
            local name = itemText:match("|h%[([^%]]+)%]|h")
            return self:RecordLoot({itemID = tonumber(id), quantity = amount, name = name})
        end
    end
    return false, "not self loot"
end

function D:GetGatherStore()
    return self:GetDB().gathering
end

function D:RecordGather(data)
    data = type(data) == "table" and data or {}
    local itemID = tonumber(data.itemID)
    -- Do not persist invalid or non-integral values in SavedVariables.
    if not itemID or itemID <= 0 or itemID > 2147483647
        or itemID % 1 ~= 0 then return false end
    local quantity = data.quantity == nil and 1 or tonumber(data.quantity)
    if not quantity or quantity < 1 or quantity > 100000
        or quantity % 1 ~= 0 then return false end
    if data.nodeKey ~= nil and (type(data.nodeKey) ~= "string"
        or data.nodeKey == "" or #data.nodeKey > 256) then return false end
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
    -- Keep the latest loot-source type so a post-/reload check can distinguish
    -- a GameObject ore vein from ore looted from a Creature where available.
    if type(data.sourceGUID) == "string" and data.sourceGUID ~= "" then
        item.lastSourceGUID = data.sourceGUID
        item.lastSourceType = data.sourceGUID:match("^([^-]+)")
    end
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
    if type(data.sourceGUID) == "string" and data.sourceGUID ~= "" then
        node.lastSourceGUID = data.sourceGUID
        node.lastSourceType = data.sourceGUID:match("^([^-]+)")
    end
    if data.visitID == nil or node.lastVisitID ~= data.visitID then
        node.visits = (tonumber(node.visits) or 0) + 1
        node.lastVisitID = data.visitID
    end
    node.items[itemKey] = (tonumber(node.items[itemKey]) or 0) + quantity

    local zone = EnsureTable(store.zones, tostring(mapID))
    zone.name = data.zoneName or zone.name
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

function D:RegisterBlizzardSettingsCategory()
    if self.settingsCategory then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end

    local canvas = CreateFrame("Frame")
    local isDE = type(GetLocale) == "function" and GetLocale() == "deDE"

    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("ComfyData")

    local desc = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText(isDE
        and "Persistenter Hintergrund-Datendienst der Comfy Suite. Die Daten liegen in den WoW-SavedVariables und bleiben bei Addon-Updates erhalten."
        or "Persistent background data service for the Comfy Suite. Data is stored in WoW SavedVariables and survives addon-folder updates.")

    local status = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    status:SetWidth(560)
    status:SetJustifyH("LEFT")
    local info = self:GetStatus()
    status:SetText(string.format("v%s  ·  schema %s  ·  %d chars  ·  %d mobs  ·  %d nodes",
        tostring(info.version), tostring(info.schemaVersion), tonumber(info.characters) or 0,
        tonumber(info.killMobs) or 0, tonumber(info.gatherNodes) or 0))

    local commands = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    commands:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -18)
    commands:SetText("/cdata  ·  /cdata snapshot  ·  /cdvault restore confirm")

    local category = Settings.RegisterCanvasLayoutCategory(canvas, "ComfyData")
    Settings.RegisterAddOnCategory(category)
    self.settingsCategory = category
end

-- A second /reload may start in the very same second as the previous
-- session. Never replace an existing session entry: all Comfy modules
-- use this ID to separate loot, kills and gathered items per session.
function D:AllocateSessionID(at)
    local sessions = self:GetDB().sessions
    local epoch = tonumber(at) or Epoch()
    local base = tostring(math.floor(epoch)) .. ":" .. self:GetCurrentKey()
    if sessions[base] == nil then return base end
    for suffix = 2, 10000 do
        local candidate = base .. "#" .. tostring(suffix)
        if sessions[candidate] == nil then return candidate end
    end
    return nil, "session ID space exhausted: no records overwritten"
end

function D:Initialize()
    local ready = self:EnsureDB()
    if not ready then return end
    self:RegisterBlizzardSettingsCategory()

    self.sessionStartedAt = Epoch()
    local allocated, allocationError = self:AllocateSessionID(self.sessionStartedAt)
    if not allocated then
        self.blockedReason = allocationError
        self:Print("Session initialization stopped: " .. tostring(allocationError))
        return
    end
    self.sessionID = allocated
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
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "UNIT_PET", "PLAYER_LOGOUT", "PLAYER_DEAD", "QUEST_TURNED_IN", "CHAT_MSG_LOOT",
        "CURRENCY_DISPLAY_UPDATE",
    }
    for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "QUEST_TURNED_IN" then
            D:RecordQuestCompletion(...)
            return
        elseif event == "PLAYER_DEAD" then
            local now = Epoch()
            if not D.lastPlayerDeathAt or now - D.lastPlayerDeathAt >= 3 then
                D:RecordDeath({time = now})
                D.lastPlayerDeathAt = now
            end
            return
        elseif event == "CHAT_MSG_LOOT" then
            D:HandleLootMessage(...)
            return
        elseif event == "CURRENCY_DISPLAY_UPDATE" then
            local currencyID = ...
            if currencyID == nil then
                D:RefreshTrackedCurrencies()
            else
                D:CaptureCurrency(currencyID)
            end
            return
        elseif event == "TIME_PLAYED_MSG" then
            D:HandleTimePlayed(...)
            return
        elseif event == "PLAYER_REGEN_DISABLED" then
            D:StartCombat()
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            D:EndCombat()
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

        if event == "PLAYER_ENTERING_WORLD" then
            D:RefreshTrackedCurrencies()
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
        D:Print("Use /cdvault restore confirm for a checksum-verified restore. /cdata does not overwrite data.")

    else
        if D.blockedReason then
            D:Print("Database paused for safety: " .. D.blockedReason)
            D:Print("Inspect Vault, then use /cdvault restore confirm for manual recovery.")
            return
        end
        local s = D:GetStatus()
        D:Print("v" .. s.version .. " | schema " .. s.schemaVersion .. " | chars " .. s.characters
            .. " | mobs " .. s.killMobs .. " | nodes " .. s.gatherNodes .. " | gather items " .. s.gatherItems
            .. " | vault " .. (s.vault and "OK" or "missing"))
        D:Print("Commands: /cdata snapshot | /cdvault restore confirm")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name == D.name then D:Initialize() end
end)
