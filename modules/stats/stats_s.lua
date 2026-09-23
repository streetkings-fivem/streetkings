SKStats = {}

local MAX_MILES_PER_SYNC  = 5.0
local MAX_TOP_SPEED_MPH   = 350.0
local SYNC_COOLDOWN_MS    = 25000
local REPAIR_COOLDOWN_MS  = 4000
local ESCAPE_COOLDOWN_MS  = 10000

local lastSync   = {}
local lastRepair = {}
local lastEscape = {}

local VALID_KEYS = {}
local dynamicDefinitions = {}
local dynamicDefinitionKeys = {}
local VALID_FORMATS = {
    integer = true,
    cash = true,
    miles = true,
    mph = true,
    xp = true,
}

for key in pairs(SKSaves.defaultStats()) do
    VALID_KEYS[key] = true
end

---@param value any
---@param maxLength integer
---@return boolean
local function isValidText(value, maxLength)
    return type(value) == 'string' and value ~= '' and #value <= maxLength
end

---@param value any
---@return boolean
local function isValidIcon(value)
    return value == nil or (type(value) == 'string' and value:match('^fa[%w%-]+$') ~= nil)
end

---@param definition table
---@return table|nil
local function normalizeDefinition(definition)
    local key = definition.id or definition.key
    if type(key) ~= 'string' or key == '' or #key > 64 or not key:match('^[%w_%-]+$') then return nil end
    if not isValidText(definition.category, 40) or not isValidText(definition.label, 64) then return nil end
    if not isValidIcon(definition.icon) or not isValidIcon(definition.categoryIcon) then return nil end

    local format = definition.format or 'integer'
    if not VALID_FORMATS[format] then return nil end

    return {
        key = key,
        category = definition.category,
        categoryIcon = definition.categoryIcon or 'fa-chart-column',
        label = definition.label,
        icon = definition.icon or 'fa-chart-simple',
        format = format,
    }
end

---@param definition table
---@return boolean
local function registerDynamicStat(definition)
    local normalized = normalizeDefinition(definition)
    if not normalized or VALID_KEYS[normalized.key] or dynamicDefinitionKeys[normalized.key] then
        return false
    end

    VALID_KEYS[normalized.key] = true
    dynamicDefinitionKeys[normalized.key] = true
    dynamicDefinitions[#dynamicDefinitions + 1] = normalized
    return true
end

---@param source integer
---@param key string
---@param amount number
function SKStats.increment(source, key, amount)
    if not VALID_KEYS[key] then return end
    if not SKSaves.hasActiveSave(source) then return end
    local stats = SKSaves.read(source, 'stats') or SKSaves.defaultStats()
    stats[key] = (stats[key] or 0) + (amount or 1)
    SKSaves.write(source, 'stats', stats)
end

---@param source integer
---@param key string
---@param value number
function SKStats.setMax(source, key, value)
    if not VALID_KEYS[key] then return end
    if not SKSaves.hasActiveSave(source) then return end
    local stats = SKSaves.read(source, 'stats') or SKSaves.defaultStats()
    if value > (stats[key] or 0) then
        stats[key] = value
        SKSaves.write(source, 'stats', stats)
    end
end

---@param source integer
---@param miles number
function SKStats.addMiles(source, miles)
    SKStats.increment(source, 'totalMilesDriven', miles)
end

---@param doc SKSaveDocument
---@return integer
function SKStats.countVehicles(doc)
    local count = 0
    if doc.garage and doc.garage.vehicles then
        for _ in pairs(doc.garage.vehicles) do count = count + 1 end
    end
    return count
end

---@param doc SKSaveDocument
---@return integer
function SKStats.countProperties(doc)
    local count = 0
    if doc.properties and doc.properties.owned then
        for _, owned in pairs(doc.properties.owned) do
            if owned then count = count + 1 end
        end
    end
    return count
end

-- Callbacks -----------------------------------------------------------------

lib.callback.register('streetkings:stats:getData', function(source)
    local doc = SKSaves.getDocument(source)
    if not doc then return nil end
    local progression = doc.progression or {}
    local level = progression.level or 1
    local xp = progression.playerXp or 0
    local nextLevelXp = SKProgression.getXpForNextLevel(level, SKProgression.PLAYER_LEVEL_THRESHOLDS, SKProgression.PLAYER_MAX_LEVEL)
    local currentLevelXp = level > 1 and SKProgression.PLAYER_LEVEL_THRESHOLDS[level - 1] or 0
    local xpInLevel = xp - currentLevelXp
    local xpNeeded = nextLevelXp and (nextLevelXp - currentLevelXp) or 1
    local nextLevel = level < SKProgression.PLAYER_MAX_LEVEL and level + 1 or nil
    local xpRemainingToNext = nextLevelXp and math.max(0, nextLevelXp - xp) or 0

    return {
        cash            = doc.economy.cash,
        level           = level,
        maxLevel        = SKProgression.PLAYER_MAX_LEVEL,
        nextLevel       = nextLevel,
        xpInLevel       = xpInLevel,
        xpNeeded        = xpNeeded,
        xpRemainingToNext = xpRemainingToNext,
        stats           = doc.stats or SKSaves.defaultStats(),
        vehiclesOwned   = SKStats.countVehicles(doc),
        propertiesOwned = SKStats.countProperties(doc),
        dynamicStats     = dynamicDefinitions,
    }
end)

RegisterNetEvent('streetkings:stats:syncDriving', function(miles, topSpeed)
    local src = source
    if not SKSaves.hasActiveSave(src) then return end

    local now = GetGameTimer()
    if lastSync[src] and (now - lastSync[src]) < SYNC_COOLDOWN_MS then return end
    lastSync[src] = now

    if type(miles) == 'number' and miles > 0 then
        SKStats.addMiles(src, math.min(miles, MAX_MILES_PER_SYNC))
    end
    if type(topSpeed) == 'number' and topSpeed > 0 then
        SKStats.setMax(src, 'topSpeedMph', math.min(topSpeed, MAX_TOP_SPEED_MPH))
    end
end)

RegisterNetEvent('streetkings:stats:repair', function()
    local src = source
    if not SKSaves.hasActiveSave(src) then return end

    local now = GetGameTimer()
    if lastRepair[src] and (now - lastRepair[src]) < REPAIR_COOLDOWN_MS then return end
    lastRepair[src] = now

    SKStats.increment(src, 'totalRepairs', 1)
end)

RegisterNetEvent('streetkings:stats:policeEscape', function()
    local src = source
    if not SKSaves.hasActiveSave(src) then return end

    local now = GetGameTimer()
    if lastEscape[src] and (now - lastEscape[src]) < ESCAPE_COOLDOWN_MS then return end
    lastEscape[src] = now

    SKStats.increment(src, 'policeEscapes', 1)
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastSync[src]   = nil
    lastRepair[src] = nil
    lastEscape[src] = nil
end)

exports('RegisterStat', function(definitionOrCategory, id, label, options)
    -- Original signature: RegisterStat(key)
    if type(definitionOrCategory) == 'string' and id == nil then
        if definitionOrCategory == '' or VALID_KEYS[definitionOrCategory] then return false end
        VALID_KEYS[definitionOrCategory] = true
        return true
    end

    -- Positional UI signature: RegisterStat(category, id, label, options?)
    if type(definitionOrCategory) == 'string' then
        options = type(options) == 'table' and options or {}
        return registerDynamicStat({
            category = definitionOrCategory,
            id = id,
            label = label,
            categoryIcon = options.categoryIcon,
            icon = options.icon,
            format = options.format,
        })
    end

    -- Table UI signature: RegisterStat({ category, id, label, ... })
    if type(definitionOrCategory) == 'table' then
        return registerDynamicStat(definitionOrCategory)
    end

    return false
end)
exports('IncrementStat', function(source, key, amount)
    if type(key) ~= 'string' then return false end
    if amount ~= nil and type(amount) ~= 'number' then return false end
    if not SKSaves.hasActiveSave(source) then return false end
    SKStats.increment(source, key, amount)
    return true
end)
exports('SetStatMax', function(source, key, value)
    if type(key) ~= 'string' or type(value) ~= 'number' then return false end
    if not SKSaves.hasActiveSave(source) then return false end
    SKStats.setMax(source, key, value)
    return true
end)
