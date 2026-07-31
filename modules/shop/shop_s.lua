--- Record shop cash spend for stats + add-on hooks (cumulative quests, etc.).
---@param source integer
---@param amount number
---@param category 'performance'|'visual'|'other'|nil
local function recordShopCashSpent(source, amount, category)
    local price = math.floor(tonumber(amount) or 0)
    if price <= 0 then return end
    if category ~= 'performance' and category ~= 'visual' then
        category = 'other'
    end
    SKStats.increment(source, 'totalCashSpent', price)
    TriggerEvent('streetkings:shop:cashSpent', source, price, category)
end

lib.callback.register('streetkings:shop:getBalance', function(source)
    return SKSaves.read(source, 'economy.cash')
end)

lib.callback.register('streetkings:shop:loadDiscovered', function(source)
    local world = SKSaves.read(source, 'world.state')
    return world.discoveredShops or {}
end)

lib.callback.register('streetkings:shop:discover', function(source, shopId)
    local world    = SKSaves.read(source, 'world.state')
    local list     = world.discoveredShops or {}
    for _, id in ipairs(list) do
        if id == shopId then return { ok = true } end
    end
    list[#list + 1] = shopId
    world.discoveredShops = list
    SKSaves.write(source, 'world.state', world)
    return { ok = true }
end)

lib.callback.register('streetkings:shop:getVehicleColors', function(source)
    local document  = SKSaves.getDocument(source)
    local vehicleId = document.garage.activeVehicleId
    local entry     = document.garage.vehicles[vehicleId]
    return entry.data.colors or {}
end)

lib.callback.register('streetkings:shop:getVehicleMods', function(source)
    local document  = SKSaves.getDocument(source)
    local vehicleId = document.garage.activeVehicleId
    local entry     = document.garage.vehicles[vehicleId]
    return entry.data.mods or {}
end)

lib.callback.register('streetkings:shop:getVehicleProgression', function(source)
    local _, entry = SKProgression.getActiveVehicleEntry(source)
    if not entry then
        return nil
    end

    local unlockLevels = {}
    for _, unlock in ipairs(entry.data.unlockSchedule) do
        unlockLevels[unlock.key] = unlock.level
    end

    return {
        level = entry.data.level,
        xp = entry.data.xp,
        unlocks = entry.data.unlocks,
        unlockLevels = unlockLevels,
    }
end)

---@param source integer
---@return table, string, table
local function getActiveVehicleEntry(source)
    local document = assert(SKSaves.getDocument(source), 'Missing save document')
    local vehicleId = document.garage.activeVehicleId
    local entry = document.garage.vehicles[vehicleId]
    return document, vehicleId, entry
end

---@param entry table
---@param unlockKey string
---@return integer|nil
local function getUnlockLevel(entry, unlockKey)
    for _, unlock in ipairs(entry.data.unlockSchedule) do
        if unlock.key == unlockKey then
            return unlock.level
        end
    end
end

---@param entry table
---@param modType integer
---@param modIndex integer
---@return boolean
local function hasModOption(entry, modType, modIndex)
    if modIndex == -1 then
        return true
    end

    for _, mod in ipairs(entry.data.availableMods) do
        if mod.modType == modType then
            for _, option in ipairs(mod.options) do
                if option.index == modIndex then
                    return true
                end
            end
            return false
        end
    end

    return false
end

local VALID_COLOR_SLOTS = { primary = true, secondary = true }
local VALID_NEON_SIDES = { front = true, back = true, left = true, right = true }

---@param value number
---@return integer
local function clampColor(value)
    return math.min(255, math.max(0, math.floor(value)))
end

---@param value number
---@return integer
local function clampPaintType(value)
    return math.min(5, math.max(0, math.floor(value)))
end

---@param color table
---@return boolean
local function isValidColor(color)
    return type(color) == 'table'
        and type(color.r) == 'number'
        and type(color.g) == 'number'
        and type(color.b) == 'number'
end

---@param sides table
---@return boolean
local function isValidNeonSides(sides)
    if type(sides) ~= 'table' then
        return false
    end

    for side in pairs(VALID_NEON_SIDES) do
        if type(sides[side]) ~= 'boolean' then
            return false
        end
    end

    return true
end

---@param color table
---@param sides table
---@return table
local function buildNeonData(color, sides)
    return {
        enabled = true,
        color = {
            r = clampColor(color.r),
            g = clampColor(color.g),
            b = clampColor(color.b),
        },
        sides = {
            front = sides.front,
            back  = sides.back,
            left  = sides.left,
            right = sides.right,
        },
    }
end

lib.callback.register('streetkings:shop:purchaseColor', function(source, slot, r, g, b, paintType)
    if not VALID_COLOR_SLOTS[slot] then
        return { ok = false, reason = 'invalid_slot' }
    end

    if not isValidColor({ r = r, g = g, b = b }) then
        return { ok = false, reason = 'invalid_color' }
    end
    if type(paintType) ~= 'number' then
        return { ok = false, reason = 'invalid_paint_type' }
    end

    local document, vehicleId, entry = getActiveVehicleEntry(source)
    local cash = document.economy.cash
    if cash < SKShopShared.COLOR_PRICE then
        return { ok = false, reason = 'insufficient_funds' }
    end

    if not entry.data.colors then entry.data.colors = {} end

    document.economy.cash = cash - SKShopShared.COLOR_PRICE
    entry.data.colors[slot] = {
        r = clampColor(r),
        g = clampColor(g),
        b = clampColor(b),
        paintType = clampPaintType(paintType),
    }

    SKSaves.write(source, 'economy.cash', document.economy.cash)
    SKSaves.write(source, 'garage.vehicles.' .. vehicleId .. '.data', entry.data)
    recordShopCashSpent(source, SKShopShared.COLOR_PRICE, 'visual')

    return { ok = true, balance = document.economy.cash, color = entry.data.colors[slot] }
end)

lib.callback.register('streetkings:shop:getActiveVehicleNeons', function(source)
    local document, vehicleId = getActiveVehicleEntry(source)
    local entry = document.garage.vehicles[vehicleId]
    return entry.data.neons
end)

lib.callback.register('streetkings:shop:purchaseNeons', function(source, enabled)
    if type(enabled) ~= 'boolean' then
        return { ok = false, reason = 'invalid_state' }
    end

    local document, vehicleId, entry = getActiveVehicleEntry(source)
    local cash = document.economy.cash
    local alreadyInstalled = type(entry.data.neons) == 'table'
    local price = enabled and not alreadyInstalled and SKShopShared.NEON_PRICE or 0
    local unlockKey = SKProgression.getModOptionKey(SKShopShared.NEON_UNLOCK_MOD_TYPE, SKShopShared.NEON_UNLOCK_MOD_INDEX)

    if enabled and not entry.data.unlocks[unlockKey] then
        return { ok = false, reason = 'locked', unlockLevel = getUnlockLevel(entry, unlockKey) }
    end

    if price > 0 and cash < price then
        return { ok = false, reason = 'insufficient_funds' }
    end

    document.economy.cash = cash - price
    if enabled and not alreadyInstalled then
        entry.data.neons = buildNeonData(SKShopShared.DEFAULT_NEONS.color, SKShopShared.DEFAULT_NEONS.sides)
    elseif not enabled then
        entry.data.neons = nil
    end

    SKSaves.write(source, 'economy.cash', document.economy.cash)
    SKSaves.write(source, 'garage.vehicles.' .. vehicleId .. '.data', entry.data)
    if price > 0 then
        recordShopCashSpent(source, price, 'visual')
    end

    return { ok = true, balance = document.economy.cash, neons = entry.data.neons }
end)

lib.callback.register('streetkings:shop:updateNeons', function(source, color, sides)
    if not isValidColor(color) then
        return { ok = false, reason = 'invalid_color' }
    end
    if not isValidNeonSides(sides) then
        return { ok = false, reason = 'invalid_sides' }
    end

    local document, vehicleId, entry = getActiveVehicleEntry(source)
    if type(entry.data.neons) ~= 'table' then
        return { ok = false, reason = 'not_installed' }
    end

    entry.data.neons = buildNeonData(color, sides)
    SKSaves.write(source, 'garage.vehicles.' .. vehicleId .. '.data', entry.data)

    return { ok = true, neons = entry.data.neons }
end)

lib.callback.register('streetkings:shop:purchaseMod', function(source, shopTypeKey, modType, modIndex)
    if not SKShopShared.isShopModType(shopTypeKey, modType) then
        return { ok = false, reason = 'invalid_mod' }
    end

    local price = SKShopShared.getModPrice(shopTypeKey, modType, modIndex)
    if not price then
        return { ok = false, reason = 'invalid_mod' }
    end

    local document, vehicleId, entry = getActiveVehicleEntry(source)
    local cash = document.economy.cash
    if cash < price then
        return { ok = false, reason = 'insufficient_funds' }
    end

    if not hasModOption(entry, modType, modIndex) then
        return { ok = false, reason = 'invalid_mod' }
    end

    local unlockKey = SKProgression.getModOptionKey(modType, modIndex)
    if not entry.data.mods then entry.data.mods = {} end

    if modIndex >= 0 and not entry.data.unlocks[unlockKey] then
        return { ok = false, reason = 'locked', unlockLevel = getUnlockLevel(entry, unlockKey) }
    end

    document.economy.cash = cash - price
    entry.data.mods[tostring(modType)] = modIndex

    SKSaves.write(source, 'economy.cash', document.economy.cash)
    SKSaves.write(source, 'garage.vehicles.' .. vehicleId .. '.data', entry.data)
    local category = shopTypeKey == 'performance' and 'performance'
        or (shopTypeKey == 'visual' and 'visual' or 'other')
    recordShopCashSpent(source, price, category)

    return { ok = true, balance = document.economy.cash, price = price }
end)

-- ─── Gearbox callbacks ────────────────────────────────────────────────────────

lib.callback.register('streetkings:shop:getActiveVehicleGearbox', function(source)
    local document  = SKSaves.getDocument(source)
    local vehicleId = document.garage.activeVehicleId
    local entry     = document.garage.vehicles[vehicleId]
    return entry.data.gearbox or 'none'
end)

local VALID_GEARBOX_TYPES = { none = true, beginner = true, expert = true }

lib.callback.register('streetkings:shop:purchaseGearbox', function(source, gearboxType)
    if not VALID_GEARBOX_TYPES[gearboxType] then
        return { ok = false, reason = 'invalid_type' }
    end

    local document, vehicleId, entry = getActiveVehicleEntry(source)
    local cash  = document.economy.cash
    local price = 0

    if gearboxType ~= 'none' then
        -- Swapping to a different type still costs the full upgrade price
        price = SKShopShared.GEARBOX_PRICES[gearboxType] or 0
        if cash < price then
            return { ok = false, reason = 'insufficient_funds' }
        end
    end

    document.economy.cash = cash - price
    entry.data.gearbox    = gearboxType ~= 'none' and gearboxType or nil

    SKSaves.write(source, 'economy.cash', document.economy.cash)
    SKSaves.write(source, 'garage.vehicles.' .. vehicleId .. '.data', entry.data)
    if price > 0 then
        recordShopCashSpent(source, price, 'performance')
    end

    return { ok = true, balance = document.economy.cash }
end)

lib.callback.register('streetkings:shop:getActiveVehicleNitrous', function(source)
    local document  = SKSaves.getDocument(source)
    local vehicleId = document.garage.activeVehicleId
    local entry     = document.garage.vehicles[vehicleId]
    return entry.data.nitrous or 'none'
end)

local VALID_NITROUS_TYPES = { none = true, street = true, sport = true, race = true }

lib.callback.register('streetkings:shop:purchaseNitrous', function(source, nitrousType)
    if not VALID_NITROUS_TYPES[nitrousType] then
        return { ok = false, reason = 'invalid_type' }
    end

    local document, vehicleId, entry = getActiveVehicleEntry(source)
    local cash  = document.economy.cash
    local price = 0

    if nitrousType ~= 'none' then
        local unlock = SKShopShared.NITROUS_UNLOCKS[nitrousType]
        local unlockKey = SKProgression.getModOptionKey(SKShopShared.NITROUS_UNLOCK_MOD_TYPE, unlock.index)
        if not entry.data.unlocks[unlockKey] then
            return { ok = false, reason = 'locked', unlockLevel = getUnlockLevel(entry, unlockKey) }
        end

        price = SKShopShared.NITROUS_PRICES[nitrousType] or 0
        if cash < price then
            return { ok = false, reason = 'insufficient_funds' }
        end
    end

    document.economy.cash = cash - price
    entry.data.nitrous    = nitrousType ~= 'none' and nitrousType or nil

    SKSaves.write(source, 'economy.cash', document.economy.cash)
    SKSaves.write(source, 'garage.vehicles.' .. vehicleId .. '.data', entry.data)
    if price > 0 then
        recordShopCashSpent(source, price, 'performance')
    end

    return { ok = true, balance = document.economy.cash }
end)
