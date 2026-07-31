SKProgression = SKProgression or {}

SKProgression.COSMETIC_CURRENCY_PER_LEVEL = SKProgressionConfig.COSMETIC_CURRENCY_PER_LEVEL

local EXCLUDED_MOD_TYPES = {
    [14] = true,
    [16] = true,
}

local DEALERSHIP_CLASS_UNLOCK_LEVELS = {
    [10] = 'B',
    [20] = 'A',
    [30] = 'S',
}

---@param source integer
---@param levelUps integer[]
local function sendDealershipUnlockMessages(source, levelUps)
    for _, level in ipairs(levelUps) do
        local class = DEALERSHIP_CLASS_UNLOCK_LEVELS[level]
        if class then
            SKMessages.enqueueUnlockMessage(source, ('You hit Lv. %d. Class %s cars are now available at every dealership.'):format(level, class))
        end
    end
end

---@param vehicleData table
---@return table
function SKProgression.ensureVehicleData(vehicleData)
    if type(vehicleData.xp) ~= 'number' or vehicleData.xp < 0 or vehicleData.xp % 1 ~= 0 then
        vehicleData.xp = 0
    end
    if type(vehicleData.level) ~= 'number' or vehicleData.level < 1 or vehicleData.level % 1 ~= 0 then
        vehicleData.level = 1
    end
    if type(vehicleData.availableMods) ~= 'table' then
        vehicleData.availableMods = {}
    end
    if type(vehicleData.unlockSchedule) ~= 'table' then
        vehicleData.unlockSchedule = {}
    end
    if type(vehicleData.unlocks) ~= 'table' then
        vehicleData.unlocks = {}
    end
    if type(vehicleData.bestActivityScores) ~= 'table' then
        vehicleData.bestActivityScores = {}
    end
    if type(vehicleData.mods) ~= 'table' then
        vehicleData.mods = {}
    end
    if type(vehicleData.colors) ~= 'table' then
        vehicleData.colors = {}
    end

    vehicleData.level = math.max(1, math.min(vehicleData.level, SKProgression.VEHICLE_MAX_LEVEL))
    return vehicleData
end

---@param vehicleType string
---@return table
function SKProgression.newVehicleData(vehicleType)
    return SKProgression.ensureVehicleData({
        vehicleType = vehicleType,
        xp = 0,
        level = 1,
        availableMods = {},
        unlockSchedule = {},
        unlocks = {},
        bestActivityScores = {},
        mods = {},
        colors = {},
    })
end

---@param document SKSaveDocument
---@return SKSaveProgressionDocument
local function getProgression(document)
    local progression = document.progression
    if type(progression.bestActivityScores) ~= 'table' then
        progression.bestActivityScores = {}
    end
    return progression
end

---@param availableMods table[]
---@return table[]
local function normalizeAvailableMods(availableMods)
    local normalized = {}

    for _, mod in ipairs(availableMods or {}) do
        if type(mod) == 'table' and type(mod.modType) == 'number' and type(mod.options) == 'table' and not EXCLUDED_MOD_TYPES[mod.modType] then
            local options = {}

            for _, option in ipairs(mod.options) do
                if type(option) == 'table' and type(option.index) == 'number' and option.index >= 0 and type(option.name) == 'string' then
                    options[#options + 1] = {
                        index = option.index,
                        name = option.name,
                        key = SKProgression.getModOptionKey(mod.modType, option.index),
                    }
                end
            end

            table.sort(options, function(a, b)
                return a.index < b.index
            end)

            if #options > 0 then
                normalized[#normalized + 1] = {
                    modType = mod.modType,
                    name = mod.name or (SKProgression.MOD_TYPE_NAMES[mod.modType] or ('Mod ' .. mod.modType)),
                    options = options,
                }
            end
        end
    end

    table.sort(normalized, function(a, b)
        return a.modType < b.modType
    end)

    return normalized
end

---@param modType integer
---@param modIndex integer
---@return integer|nil
local function getFixedUnlockLevel(modType, modIndex)
    if modType ~= SKShopShared.NITROUS_UNLOCK_MOD_TYPE then
        return nil
    end

    for _, unlock in pairs(SKShopShared.NITROUS_UNLOCKS) do
        if unlock.index == modIndex then
            return unlock.level
        end
    end
end

---@param vehicleData table
local function rebuildUnlockSchedule(vehicleData)
    local flattened = {}

    for _, mod in ipairs(vehicleData.availableMods) do
        if EXCLUDED_MOD_TYPES[mod.modType] then
            goto continue
        end

        local categoryUnlocks = {}

        for index, option in ipairs(mod.options) do
            local unlockLevel = SKProgression.getVehicleUnlockLevel(index, #mod.options)
            local unlockModName = mod.name
            local packIndex = nil
            local fixedUnlockLevel = getFixedUnlockLevel(mod.modType, option.index)
            if fixedUnlockLevel then unlockLevel = fixedUnlockLevel end

            if SKProgression.isWheelModType(mod.modType) then
                packIndex = SKProgression.getWheelPackIndex(index, #mod.options)
                unlockLevel = SKProgression.getWheelPackUnlockLevel(packIndex)
                unlockModName = SKProgression.getWheelPackName(packIndex)
            end

            categoryUnlocks[#categoryUnlocks + 1] = {
                key = option.key,
                level = unlockLevel,
                modType = mod.modType,
                modIndex = option.index,
                modName = unlockModName,
                optionName = option.name,
                packIndex = packIndex,
            }
        end

        for _, unlock in ipairs(categoryUnlocks) do
            flattened[#flattened + 1] = {
                key = unlock.key,
                level = unlock.level,
                modType = unlock.modType,
                modIndex = unlock.modIndex,
                modName = unlock.modName,
                optionName = unlock.optionName,
                packIndex = unlock.packIndex,
            }
        end

        ::continue::
    end

    table.sort(flattened, function(a, b)
        if a.level ~= b.level then
            return a.level < b.level
        end
        if a.modType ~= b.modType then
            return a.modType < b.modType
        end
        return a.modIndex < b.modIndex
    end)

    vehicleData.unlockSchedule = flattened
    vehicleData.unlocks = {}

    for _, unlock in ipairs(flattened) do
        if unlock.level <= vehicleData.level then
            vehicleData.unlocks[unlock.key] = true
        end
    end
end

---@param vehicleData table
---@return table
local function buildVehicleSnapshot(vehicleData)
    local unlockLevels = {}
    local unlockedCount = 0

    for _, unlock in ipairs(vehicleData.unlockSchedule) do
        unlockLevels[unlock.key] = unlock.level
        if vehicleData.unlocks[unlock.key] then
            unlockedCount = unlockedCount + 1
        end
    end

    local currentLevelXp = SKProgression.VEHICLE_LEVEL_THRESHOLDS[vehicleData.level] or 0
    local nextLevelXp = SKProgression.getXpForNextLevel(
        vehicleData.level,
        SKProgression.VEHICLE_LEVEL_THRESHOLDS,
        SKProgression.VEHICLE_MAX_LEVEL
    )

    return {
        xp = vehicleData.xp,
        level = vehicleData.level,
        currentLevelXp = currentLevelXp,
        nextLevelXp = nextLevelXp,
        maxLevel = SKProgression.VEHICLE_MAX_LEVEL,
        availableMods = vehicleData.availableMods,
        unlocks = vehicleData.unlocks,
        unlockLevels = unlockLevels,
        unlockedCount = unlockedCount,
        totalUnlocks = #vehicleData.unlockSchedule,
    }
end

---@param source integer
---@return string|nil, table|nil
function SKProgression.getActiveVehicleEntry(source)
    local document = SKSaves.getDocument(source)
    if not document then
        return nil, nil
    end

    local vehicleId = document.garage.activeVehicleId
    if vehicleId == '' then
        return nil, nil
    end

    local entry = document.garage.vehicles[vehicleId]
    if not entry then
        return nil, nil
    end

    SKProgression.ensureVehicleData(entry.data)
    return vehicleId, entry
end

---@param source integer
---@param availableMods table[]
---@return table
function SKProgression.syncActiveVehicleMods(source, availableMods)
    local vehicleId, entry = SKProgression.getActiveVehicleEntry(source)
    if not vehicleId or not entry then
        return { ok = false, reason = 'no_active_vehicle' }
    end

    entry.data.availableMods = normalizeAvailableMods(availableMods)
    rebuildUnlockSchedule(entry.data)
    SKSaves.write(source, 'garage.vehicles.' .. vehicleId .. '.data', entry.data)

    return {
        ok = true,
        vehicleId = vehicleId,
        vehicle = buildVehicleSnapshot(entry.data),
    }
end

---@param scoreTable table<string, integer>
---@param activityId string
---@param score integer
---@param scoreType 'time'|'speed'|'points'
---@return boolean, boolean, integer|nil
function SKProgression.recordActivityBest(scoreTable, activityId, score, scoreType)
    local previous = scoreTable[activityId]
    if previous == nil then
        scoreTable[activityId] = score
        return true, true, nil
    end

    local improved = false
    if scoreType == 'speed' or scoreType == 'points' then
        improved = score > previous
    else
        improved = score < previous
    end

    if improved then
        scoreTable[activityId] = score
    end

    return false, improved, previous
end

---@param source integer
---@param amount integer
---@return table
function SKProgression.awardPlayerXp(source, amount)
    if amount <= 0 then
        return { xpGained = 0, oldLevel = 1, newLevel = 1, levelUps = {}, cosmeticCurrencyAwarded = 0, cosmeticCurrencyBalance = 0 }
    end

    local document = SKSaves.getDocument(source)
    if not document then
        return { xpGained = 0, oldLevel = 1, newLevel = 1, levelUps = {}, cosmeticCurrencyAwarded = 0, cosmeticCurrencyBalance = 0 }
    end

    local progression = getProgression(document)
    local oldXp = progression.playerXp
    local oldLevel = progression.level
    local maxXp = SKProgression.PLAYER_LEVEL_THRESHOLDS[SKProgression.PLAYER_MAX_LEVEL]
    local newXp = math.min(oldXp + amount, maxXp)

    progression.playerXp = newXp
    progression.level = SKProgression.getPlayerLevelFromXp(newXp)

    local levelUps = {}
    for level = oldLevel + 1, progression.level do
        levelUps[#levelUps + 1] = level
    end

    if #levelUps > 0 then
        sendDealershipUnlockMessages(source, levelUps)
    end

    SKSaves.write(source, 'progression', progression)

    local cosmeticCurrencyAwarded = #levelUps * SKProgression.COSMETIC_CURRENCY_PER_LEVEL
    local awardedCoins = 0
    local cosmeticCurrencyBalance = 0
    if cosmeticCurrencyAwarded > 0 then
        awardedCoins, cosmeticCurrencyBalance = SKAvatar.addCosmeticCurrency(source, cosmeticCurrencyAwarded)
    end

    return {
        xpGained = newXp - oldXp,
        oldLevel = oldLevel,
        newLevel = progression.level,
        levelUps = levelUps,
        cosmeticCurrencyAwarded = awardedCoins,
        cosmeticCurrencyBalance = cosmeticCurrencyBalance,
    }
end

---@param source integer
---@param amount integer
---@return table
function SKProgression.awardVehicleXp(source, amount)
    local vehicleId, entry = SKProgression.getActiveVehicleEntry(source)
    if not vehicleId or not entry or amount <= 0 then
        return { xpGained = 0, oldLevel = 1, newLevel = 1, unlocks = {} }
    end

    local vehicleData = SKProgression.ensureVehicleData(entry.data)
    local oldXp = vehicleData.xp
    local oldLevel = vehicleData.level
    local maxXp = SKProgression.VEHICLE_LEVEL_THRESHOLDS[SKProgression.VEHICLE_MAX_LEVEL]
    local newXp = math.min(oldXp + amount, maxXp)

    vehicleData.xp = newXp
    vehicleData.level = SKProgression.getVehicleLevelFromXp(newXp)

    local unlocked = {}
    for _, unlock in ipairs(vehicleData.unlockSchedule) do
        if unlock.level > oldLevel and unlock.level <= vehicleData.level then
            vehicleData.unlocks[unlock.key] = true
            unlocked[#unlocked + 1] = unlock
        elseif unlock.level <= vehicleData.level then
            vehicleData.unlocks[unlock.key] = true
        end
    end

    SKSaves.write(source, 'garage.vehicles.' .. vehicleId .. '.data', vehicleData)

    return {
        xpGained = newXp - oldXp,
        oldLevel = oldLevel,
        newLevel = vehicleData.level,
        unlocks = unlocked,
        vehicleId = vehicleId,
    }
end

---@param source integer
---@param targetLevel integer
---@return boolean
function SKProgression.setPlayerLevel(source, targetLevel)
    local document = SKSaves.getDocument(source)
    if not document then return false end

    targetLevel = math.max(1, math.min(targetLevel, SKProgression.PLAYER_MAX_LEVEL))
    local progression = getProgression(document)
    progression.playerXp = SKProgression.PLAYER_LEVEL_THRESHOLDS[targetLevel]
    progression.level = targetLevel
    SKSaves.write(source, 'progression', progression)
    return true
end

---@param source integer
---@param targetLevel integer
---@return boolean
function SKProgression.setVehicleLevel(source, targetLevel)
    local vehicleId, entry = SKProgression.getActiveVehicleEntry(source)
    if not vehicleId or not entry then return false end

    targetLevel = math.max(1, math.min(targetLevel, SKProgression.VEHICLE_MAX_LEVEL))
    local vehicleData = SKProgression.ensureVehicleData(entry.data)
    vehicleData.xp = SKProgression.VEHICLE_LEVEL_THRESHOLDS[targetLevel]
    vehicleData.level = targetLevel
    vehicleData.unlocks = {}
    for _, unlock in ipairs(vehicleData.unlockSchedule) do
        if unlock.level <= targetLevel then
            vehicleData.unlocks[unlock.key] = true
        end
    end
    SKSaves.write(source, 'garage.vehicles.' .. vehicleId .. '.data', vehicleData)
    return true
end

---@param rewardData table
---@return string
function SKProgression.buildVehicleUnlockMessage(rewardData)
    local unlocks = rewardData and rewardData.unlocks or nil
    if type(unlocks) ~= 'table' or #unlocks == 0 then
        return ''
    end

    local unlockCount = #unlocks
    return ('Your ride hit Lv. %d. %d new part%s %s ready.'):format(
        rewardData.newLevel,
        unlockCount,
        unlockCount == 1 and '' or 's',
        unlockCount == 1 and 'is' or 'are'
    )
end

---@param rewardData table
---@return string
function SKProgression.buildRewardSummary(rewardData)
    local parts = {}

    if rewardData.player and rewardData.player.xpGained > 0 then
        parts[#parts + 1] = 'Player +' .. rewardData.player.xpGained .. ' XP'
    end
    if rewardData.vehicle and rewardData.vehicle.xpGained > 0 then
        parts[#parts + 1] = 'Vehicle +' .. rewardData.vehicle.xpGained .. ' XP'
    end
    if rewardData.player and rewardData.player.cosmeticCurrencyAwarded > 0 then
        parts[#parts + 1] = 'GearCoins +' .. rewardData.player.cosmeticCurrencyAwarded
    end

    return table.concat(parts, ' | ')
end

lib.callback.register('streetkings:progression:syncActiveVehicleMods', function(source, availableMods)
    return SKProgression.syncActiveVehicleMods(source, availableMods)
end)

exports('AwardPlayerXp', function(source, amount)
    if type(amount) ~= 'number' or amount <= 0 then return nil end
    if not SKSaves.hasActiveSave(source) then return nil end
    return SKProgression.awardPlayerXp(source, amount)
end)
exports('AwardVehicleXp', function(source, amount)
    if type(amount) ~= 'number' or amount <= 0 then return nil end
    if not SKSaves.hasActiveSave(source) then return nil end
    return SKProgression.awardVehicleXp(source, amount)
end)
exports('GetPlayerLevel', function(source)
    local doc = SKSaves.getDocument(source)
    if not doc then return 1 end
    local progression = doc.progression or {}
    return SKProgression.getPlayerLevelFromXp(progression.playerXp or 0)
end)
exports('RecordActivityBest', function(source, activityId, score, scoreType)
    if not SKSaves.hasActiveSave(source) then return false end
    if type(activityId) ~= 'string' or type(score) ~= 'number' then return false end
    local doc = SKSaves.getDocument(source)
    if not doc then return false end
    local progression = doc.progression or {}
    local bests = progression.bestActivityScores or {}
    local isFirst, improved, previous = SKProgression.recordActivityBest(bests, activityId, score, scoreType)
    progression.bestActivityScores = bests
    SKSaves.write(source, 'progression', progression)
    return isFirst, improved, previous
end)