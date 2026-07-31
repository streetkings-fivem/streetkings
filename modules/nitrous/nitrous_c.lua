SKNitrous = {}

local INPUT_KEYBOARD_LEFT_ALT = 19
local INPUT_CONTROLLER_FACE_X = 179

local LEVELS = {
    street = {
        capacity = 3.0,
        torque = 1.25,
    },
    sport = {
        capacity = 4.0,
        torque = 1.35,
    },
    race = {
        capacity = 5.0,
        torque = 1.45,
    },
}

local ALLOWED_STATES = {
    [GameState.FREEROAM] = true,
    [GameState.EVENT] = true,
    [GameState.MULTIPLAYER_LOBBY] = true,
    [GameState.MULTIPLAYER_EVENT] = true,
}

local CHECKPOINT_REFILL = 0.75
local NEAR_MISS_REFILL = 0.45
local DRIFT_REFILL_PER_SEC = 0.35
local ONCOMING_REFILL_PER_SEC = 0.22
local NEAR_MISS_COOLDOWN_MS = 2200
local NEAR_MISS_DISTANCE = 4.2
local RECHARGE_SCAN_INTERVAL_MS = 120
local RECHARGE_SCAN_RADIUS = 25.0
local BACKFIRE_INTERVAL_MS = 85
local BACKFIRE_SCALE = 1.25
local BACKFIRE_ASSET = 'core'
local BACKFIRE_EFFECT = 'veh_backfire'

local EXHAUST_BONES = {
    'exhaust',
    'exhaust_2',
    'exhaust_3',
    'exhaust_4',
    'exhaust_5',
    'exhaust_6',
    'exhaust_7',
    'exhaust_8',
    'exhaust_9',
    'exhaust_10',
    'exhaust_11',
    'exhaust_12',
    'exhaust_13',
    'exhaust_14',
    'exhaust_15',
    'exhaust_16',
}

local activeType = nil
local vehicle = 0
local inVeh = false
local active = false
local boosting = false
local multiplayerRaceDisabled = false
local fuel = 0.0
local capacity = 0.0
local torque = 1.0
local runToken = 0
local nearMissCooldowns = {}
local lastScanAt = 0
local oncomingActiveUntil = 0
local backfireAssetRequested = false

---@param veh integer
---@return boolean
local function isAllowedClass(veh)
    local c = GetVehicleClass(veh)
    return c ~= 13 and c ~= 14 and c ~= 15 and c ~= 16 and c ~= 21
end

---@return boolean
local function isAllowedState()
    if multiplayerRaceDisabled then
        return false
    end

    return ALLOWED_STATES[SKC.GetGameState()] == true
end

---@param amount number
local function addFuel(amount)
    if not active then return end
    fuel = math.min(capacity, fuel + amount)
end

---@return nil
local function sendHudUpdate()
    SendNUIMessage({
        type = 'nitrous:update',
        active = active,
        pct = capacity > 0 and fuel / capacity or 0,
        boosting = boosting,
    })
end

---@param enabled boolean
local function setBoosting(enabled)
    if boosting == enabled then return end
    boosting = enabled

    if vehicle ~= 0 then
        SetVehicleBoostActive(vehicle, enabled)
        if not enabled then
            SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
        end
    end

    if enabled then
        StopScreenEffect('RaceTurbo')
        StartScreenEffect('RaceTurbo', 0, false)
        ShakeGameplayCam('SKY_DIVING_SHAKE', 0.12)
    else
        StopGameplayCamShaking(true)
        StopScreenEffect('RaceTurbo')
    end
end

---@return boolean
local function hasBackfireAsset()
    if HasNamedPtfxAssetLoaded(BACKFIRE_ASSET) then
        return true
    end

    if not backfireAssetRequested then
        backfireAssetRequested = true
        RequestNamedPtfxAsset(BACKFIRE_ASSET)
    end

    return false
end

---@param veh integer
---@return nil
local function emitExhaustBackfire(veh)
    if not hasBackfireAsset() then return end

    for i = 1, #EXHAUST_BONES do
        local boneIndex = GetEntityBoneIndexByName(veh, EXHAUST_BONES[i])
        if boneIndex ~= -1 then
            local bonePos = GetWorldPositionOfEntityBone(veh, boneIndex)
            local offset = GetOffsetFromEntityGivenWorldCoords(veh, bonePos.x, bonePos.y, bonePos.z)
            UseParticleFxAssetNextCall(BACKFIRE_ASSET)
            StartParticleFxNonLoopedOnEntity(BACKFIRE_EFFECT, veh, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, BACKFIRE_SCALE, false, false, false)
        end
    end
end

---@return boolean
local function isNitrousPressed()
    local padIndex = SKInput.getActivePadIndex()

    if SKInput.isUsingKeyboard(padIndex) then
        DisableControlAction(0, INPUT_KEYBOARD_LEFT_ALT, true)
        return IsDisabledControlPressed(0, INPUT_KEYBOARD_LEFT_ALT)
    end

    DisableControlAction(padIndex, INPUT_CONTROLLER_FACE_X, true)
    return IsDisabledControlPressed(padIndex, INPUT_CONTROLLER_FACE_X)
        or IsControlPressed(padIndex, INPUT_CONTROLLER_FACE_X)
end

---@param veh integer
---@param other integer
---@return boolean
local function isTrafficVehicle(veh, other)
    if other == veh or not DoesEntityExist(other) then return false end
    local driver = GetPedInVehicleSeat(other, -1)
    return driver ~= 0 and not IsPedAPlayer(driver)
end

---@param veh integer
---@param otherPos vector3
---@return boolean
local function isOtherVehicleAhead(veh, otherPos)
    local localPos = GetOffsetFromEntityGivenWorldCoords(veh, otherPos.x, otherPos.y, otherPos.z)
    return localPos.y > -2.0 and localPos.y < 22.0
end

---@param veh integer
---@param nearby { vehicle: integer, coords: vector3 }[]
---@param pos vector3
---@param now integer
---@param speed number
---@return number
local function getNearMissRecharge(veh, nearby, pos, now, speed)
    if speed < 18.0 then return 0.0 end

    for i = 1, #nearby do
        local entry = nearby[i]
        local other = entry.vehicle
        local otherPos = entry.coords
        if #(pos - otherPos) <= NEAR_MISS_DISTANCE and isOtherVehicleAhead(veh, otherPos) and isTrafficVehicle(veh, other) and math.abs(speed - GetEntitySpeed(other)) >= 8.0 then
            local cooldownUntil = nearMissCooldowns[other] or 0
            if now >= cooldownUntil then
                nearMissCooldowns[other] = now + NEAR_MISS_COOLDOWN_MS
                return NEAR_MISS_REFILL
            end
        end
    end

    return 0.0
end

---@param veh integer
---@param nearby { vehicle: integer, coords: vector3 }[]
---@param speed number
---@return boolean
local function isInOncomingTraffic(veh, nearby, speed)
    if speed < 16.0 then return false end

    local forward = GetEntityForwardVector(veh)
    for i = 1, #nearby do
        local entry = nearby[i]
        local other = entry.vehicle
        if isOtherVehicleAhead(veh, entry.coords) and isTrafficVehicle(veh, other) then
            local otherForward = GetEntityForwardVector(other)
            local dot = forward.x * otherForward.x + forward.y * otherForward.y + forward.z * otherForward.z
            if dot < -0.55 then
                return true
            end
        end
    end

    return false
end

---@param veh integer
---@param frameSeconds number
---@return number
local function getDriftRecharge(veh, frameSeconds)
    if IsEntityInAir(veh) then return 0.0 end
    if GetEntitySpeed(veh) < 12.0 then return 0.0 end

    local velocity = GetEntitySpeedVector(veh, true)
    local sideways = math.abs(velocity.x)
    local forward = math.abs(velocity.y)
    if sideways < 3.0 or sideways / math.max(forward, 0.1) < 0.32 then
        return 0.0
    end

    return DRIFT_REFILL_PER_SEC * frameSeconds
end

---@param frameSeconds number
local function updateRecharge(frameSeconds)
    if vehicle == 0 or fuel >= capacity or boosting then return end

    local amount = getDriftRecharge(vehicle, frameSeconds)

    local now = GetGameTimer()
    if now <= oncomingActiveUntil then
        amount = amount + ONCOMING_REFILL_PER_SEC * frameSeconds
    end

    if now - lastScanAt >= RECHARGE_SCAN_INTERVAL_MS then
        lastScanAt = now
        local pos = GetEntityCoords(vehicle)
        local speed = GetEntitySpeed(vehicle)
        local nearby = lib.getNearbyVehicles(pos, RECHARGE_SCAN_RADIUS, false)

        if isInOncomingTraffic(vehicle, nearby, speed) then
            oncomingActiveUntil = now + RECHARGE_SCAN_INTERVAL_MS + 50
        end
        amount = amount + getNearMissRecharge(vehicle, nearby, pos, now, speed)
    end

    if amount > 0 then
        addFuel(amount)
    end
end

---@return nil
local function shutdown()
    setBoosting(false)
    active = false
    vehicle = 0
    inVeh = false
    fuel = 0.0
    capacity = 0.0
    torque = 1.0
    nearMissCooldowns = {}
    oncomingActiveUntil = 0
    SendNUIMessage({ type = 'nitrous:update', active = false, pct = 0, boosting = false })
end

---@return nil
local function startLoop()
    runToken += 1
    local token = runToken

    CreateThread(function()
        local lastHudPct = -1.0
        local lastHudBoosting = false
        local nextBackfireAt = 0

        while token == runToken do
            if not active or vehicle == 0 then
                Wait(250)
                goto continue
            end

            if not isAllowedState() then
                setBoosting(false)
                Wait(250)
                goto continue
            end

            if GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() or not GetIsVehicleEngineRunning(vehicle) then
                setBoosting(false)
                lastHudPct = -1.0
                Wait(100)
                goto continue
            end

            Wait(0)

            local frameSeconds = math.max(GetFrameTime(), 0.001)
            local pressed = isNitrousPressed()

            if pressed and fuel > 0.0 and not IsVehicleStopped(vehicle) then
                setBoosting(true)
                fuel = math.max(0.0, fuel - frameSeconds)
                SetVehicleEngineTorqueMultiplier(vehicle, torque)
                local now = GetGameTimer()
                if now >= nextBackfireAt then
                    nextBackfireAt = now + BACKFIRE_INTERVAL_MS
                    emitExhaustBackfire(vehicle)
                end
            else
                setBoosting(false)
                updateRecharge(frameSeconds)
            end

            if fuel <= 0.0 then
                setBoosting(false)
            end

            local pct = capacity > 0 and fuel / capacity or 0
            if math.abs(pct - lastHudPct) >= 0.01 or boosting ~= lastHudBoosting then
                lastHudPct = pct
                lastHudBoosting = boosting
                sendHudUpdate()
            end

            ::continue::
        end
    end)
end

---@return nil
local function enableNitrous()
    if vehicle == 0 or not inVeh then return end
    if multiplayerRaceDisabled then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then return end
    if not isAllowedClass(vehicle) then return end
    if not LEVELS[activeType] then return end

    local level = LEVELS[activeType]
    capacity = level.capacity
    torque = level.torque
    fuel = capacity
    active = true
    sendHudUpdate()
    startLoop()
end

---@param veh integer|nil
lib.onCache('vehicle', function(veh)
    if veh and veh ~= 0 then
        setBoosting(false)
        vehicle = veh
        inVeh = true
        if activeType ~= nil and isAllowedState() then
            enableNitrous()
        end
    else
        setBoosting(false)
        inVeh = false
        vehicle = 0
    end
end)

---@return nil
AddEventHandler('streetkings:nitrous:freeroamEnter', function()
    local nitrousType = lib.callback.await('streetkings:shop:getActiveVehicleNitrous', false)
    activeType = LEVELS[nitrousType] and nitrousType or nil

    local cacheVeh = cache.vehicle
    if cacheVeh and cacheVeh ~= 0 and activeType ~= nil then
        vehicle = cacheVeh
        inVeh = true
        enableNitrous()
    else
        SendNUIMessage({ type = 'nitrous:update', active = false, pct = 0, boosting = false })
    end
end)

---@param nextState string
AddEventHandler('streetkings:nitrous:freeroamExit', function(nextState)
    if nextState == GameState.EVENT or nextState == GameState.MULTIPLAYER_LOBBY or nextState == GameState.MULTIPLAYER_EVENT then
        return
    end

    shutdown()
    activeType = nil
end)

---@return nil
AddEventHandler('streetkings:nitrous:checkpointCleared', function()
    addFuel(CHECKPOINT_REFILL)
    sendHudUpdate()
end)

---@param disabled boolean
AddEventHandler('streetkings:nitrous:setMultiplayerRaceDisabled', function(disabled)
    multiplayerRaceDisabled = disabled == true

    if multiplayerRaceDisabled then
        active = false
        setBoosting(false)
        SendNUIMessage({ type = 'nitrous:update', active = false, pct = 0, boosting = false })
        return
    end

    if activeType ~= nil and vehicle ~= 0 and inVeh and isAllowedState() then
        enableNitrous()
    end
end)

---@return string|nil
function SKNitrous.getType()
    return activeType
end
