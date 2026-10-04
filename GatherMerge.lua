ComfyData = ComfyData or {}
local D = ComfyData

D.version = "0.7"
D.gatherMergeRadius = 0.0035

local function Normalize(text)
    return tostring(text or ""):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function SameGatherType(node, data)
    local a = Normalize(node and (node.profession or node.category))
    local b = Normalize(data and (data.profession or data.category))
    return a == b
end

function D:FindNearbyGatherNode(data, radius)
    data = type(data) == "table" and data or {}
    local mapID, x, y = tonumber(data.mapID), tonumber(data.x), tonumber(data.y)
    if not mapID or not x or not y then return nil end
    radius = tonumber(radius) or self.gatherMergeRadius or 0.0035
    local best, bestDist
    for _, node in pairs((self:GetGatherStore() or {}).nodes or {}) do
        if tonumber(node.mapID) == mapID and SameGatherType(node, data) then
            local nx, ny = tonumber(node.x), tonumber(node.y)
            if nx and ny then
                local dx, dy = nx - x, ny - y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= radius and (not bestDist or dist < bestDist) then best, bestDist = node, dist end
            end
        end
    end
    return best, bestDist
end

local originalRecordGather = D.RecordGather
function D:RecordGather(data)
    data = type(data) == "table" and data or {}
    if type(originalRecordGather) ~= "function" then return false end

    local nearby = self:FindNearbyGatherNode(data)
    local oldVisits, oldX, oldY
    if nearby and nearby.key then
        data.nodeKey = nearby.key
        oldVisits = math.max(1, tonumber(nearby.visits) or 1)
        oldX, oldY = tonumber(nearby.x), tonumber(nearby.y)
    end

    local ok, nodeKey, item = originalRecordGather(self, data)
    if not ok then return ok, nodeKey, item end

    local node = nodeKey and self:GetGatherStore().nodes[nodeKey]
    if node then
        node.lastCharacter = data.characterKey or self:GetCurrentKey()
        node.zoneName = data.zoneName or node.zoneName
        if nearby and oldX and oldY and tonumber(data.x) and tonumber(data.y) then
            local weight = oldVisits or 1
            node.x = ((oldX * weight) + tonumber(data.x)) / (weight + 1)
            node.y = ((oldY * weight) + tonumber(data.y)) / (weight + 1)
        end
    end
    return ok, nodeKey, item
end

function D:GetGatherNodesFiltered(mapID, filters)
    filters = type(filters) == "table" and filters or {}
    local out = {}
    local now = type(time) == "function" and time() or 0
    local cutoffDays = tonumber(filters.lastSeenDays)
    local cutoff = cutoffDays and cutoffDays > 0 and (now - cutoffDays * 86400) or nil
    for _, node in ipairs(self:GetGatherNodesForMap(mapID) or {}) do
        local profession = tostring(node.profession or "Other")
        local show = filters[profession]
        if show == nil then show = true end
        if show and (not cutoff or (tonumber(node.lastSeen) or 0) >= cutoff) then out[#out+1] = node end
    end
    table.sort(out, function(a,b)
        local av,bv = tonumber(a.lastSeen) or 0, tonumber(b.lastSeen) or 0
        if av ~= bv then return av > bv end
        return (tonumber(a.visits) or 0) > (tonumber(b.visits) or 0)
    end)
    return out
end
