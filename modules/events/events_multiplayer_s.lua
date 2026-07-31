---@class SKMultiplayerServerModule
SKMultiplayerServer = SKMultiplayerServer or {}

local MP_RACE_CHECKPOINT_RADIUS = 30.0
local MP_RACE_TIMEOUT_MS = 30 * 60 * 1000
local MP_RACE_RELEASE_DELAY_MS = 5000

---@return integer
local function nowUnix()
    return os.time()
end

---@return integer
local function nowMs()
    return GetGameTimer()
end

---@param src integer
---@return string
local function aliasFor(src)
    local savedAlias = SKSaves.read(src, 'profile.alias')
    if type(savedAlias) == 'string' and savedAlias ~= '' then
        return savedAlias
    end
    return GetPlayerName(src) or ('Player ' .. tostring(src))
end

---@param src integer
---@param coords vector3
---@return number
local function playerDistanceTo(src, coords)
    local ped = GetPlayerPed(src)
    if ped == 0 then return math.huge end
    local p = GetEntityCoords(ped)
    local dx, dy, dz = p.x - coords.x, p.y - coords.y, p.z - coords.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---@param src integer
local function cleanupMpVehicle(src)
    local mpNetId = SKEventsServer.mpVehicleNetIdBySource[src]
    if mpNetId then
        local veh = NetworkGetEntityFromNetworkId(mpNetId)
        if veh ~= 0 and DoesEntityExist(veh) then
            DeleteEntity(veh)
        end
    end
    SKEventsServer.mpVehicleNetIdBySource[src] = nil
end

--- Push the MP lobby vehicle back into the freeroam bucket and freeroam's
--- tracking so the player can return to freeroam without a respawn
---@param src integer
---@return boolean transferred, integer|nil netId
local function transferMpVehicleToFreeroam(src)
    local mpNetId = SKEventsServer.mpVehicleNetIdBySource[src]
    if not mpNetId then return false end
    SKEventsServer.mpVehicleNetIdBySource[src] = nil

    if not SKFreeroamServer.moveVehicleToBucket(mpNetId, 0) then
        return false
    end

    SKFreeroamServer.adoptAssignedVehicle(src, mpNetId)
    SetPlayerRoutingBucket(src, 0)
    return true
end

---@return integer
local function allocateBucket()
    local cfg = SKEventsConfig
    SKEventsServer.nextBucketOffset = SKEventsServer.nextBucketOffset + 1
    return cfg.MULTIPLAYER_BUCKET_BASE + SKEventsServer.nextBucketOffset
end

---@param src integer
---@return integer|nil
function SKMultiplayerServer.getBucketForSource(src)
    local lobbyId = SKEventsServer.lobbyIdBySource[src]
    if not lobbyId then return nil end
    local lobby = SKEventsServer.openRaceLobbies[lobbyId]
    if not lobby then return nil end
    return lobby.bucket
end

---@param src integer
---@return table|nil
function SKMultiplayerServer.getLobbyForSource(src)
    local lobbyId = SKEventsServer.lobbyIdBySource[src]
    if not lobbyId then return nil end
    return SKEventsServer.openRaceLobbies[lobbyId]
end

---@param def table
---@return string
local function eventTypeLabel(def)
    if def.type == EventType.DELIVERY then return 'Delivery' end
    if def.scheme == CheckpointScheme.CIRCUIT then return 'Circuit' end
    if def.scheme == CheckpointScheme.THEREANDBACK then return 'There & Back' end
    return 'Sprint'
end

---@param def table
---@param options table|nil
---@return { laps: integer, collision: boolean, nitrousEnabled: boolean, trafficDensityPct: integer, lobbyTimeoutSeconds: integer }
local function normalizeRaceOptions(def, options)
    local defaults = SKEventsConfig.MULTIPLAYER_SETUP_DEFAULTS or {}
    local timeoutOptions = SKEventsConfig.MULTIPLAYER_SETUP_TIMEOUT_OPTIONS or { 180, 300, 600 }

    local laps = type(options) == 'table' and tonumber(options.laps) or tonumber(defaults.laps) or 1
    laps = math.min(5, math.max(1, math.floor(laps)))
    if def.scheme ~= CheckpointScheme.CIRCUIT then
        laps = 1
    end

    local collision = defaults.collision ~= false
    if type(options) == 'table' and type(options.collision) == 'boolean' then
        collision = options.collision
    end

    local nitrousEnabled = defaults.nitrousEnabled ~= false
    if type(options) == 'table' and type(options.nitrousEnabled) == 'boolean' then
        nitrousEnabled = options.nitrousEnabled
    end

    local trafficDensityPct = type(options) == 'table' and tonumber(options.trafficDensityPct)
        or tonumber(defaults.trafficDensityPct)
        or 20
    trafficDensityPct = math.floor(trafficDensityPct / 10) * 10
    trafficDensityPct = math.max(0, math.min(trafficDensityPct, 100))

    local lobbyTimeoutSeconds = type(options) == 'table' and tonumber(options.lobbyTimeoutSeconds)
        or tonumber(defaults.lobbyTimeoutSeconds)
        or timeoutOptions[1]
    lobbyTimeoutSeconds = math.floor(lobbyTimeoutSeconds)

    local timeoutValid = false
    for _, value in ipairs(timeoutOptions) do
        if value == lobbyTimeoutSeconds then
            timeoutValid = true
            break
        end
    end
    if not timeoutValid then
        lobbyTimeoutSeconds = timeoutOptions[1]
    end

    return {
        laps = laps,
        collision = collision,
        nitrousEnabled = nitrousEnabled,
        trafficDensityPct = trafficDensityPct,
        lobbyTimeoutSeconds = lobbyTimeoutSeconds,
    }
end

---@param def table
---@param raceOptions { laps: integer, collision: boolean, nitrousEnabled: boolean, trafficDensityPct: integer, lobbyTimeoutSeconds: integer }
---@return vector3[] checkpoints, integer checkpointsPerLap, integer lapTotal
local function buildRaceCheckpoints(def, raceOptions)
    local baseCheckpoints = SKEventRoute.buildCheckpointList(def)
    if def.scheme ~= CheckpointScheme.CIRCUIT then
        return baseCheckpoints, #baseCheckpoints, 1
    end

    local checkpoints = {}
    for lap = 1, raceOptions.laps do
        for _, checkpoint in ipairs(baseCheckpoints) do
            checkpoints[#checkpoints + 1] = checkpoint
        end
    end

    return checkpoints, #baseCheckpoints, raceOptions.laps
end

---@param lobby table
---@return table
local function buildLobbyPayload(lobby)
    local cfg = SKEventsConfig
    local players = {}
    for _, src in ipairs(lobby.memberOrder) do
        local member = lobby.members[src]
        if member then
            players[#players + 1] = {
                source = src,
                alias = member.alias,
                isHost = src == lobby.hostSource,
            }
        end
    end

    local now = nowUnix()
    local payload = {
        id = lobby.id,
        eventId = lobby.eventId,
        eventName = lobby.eventName,
        eventTypeLabel = lobby.eventTypeLabel,
        vehicleClass = lobby.vehicleClass,
        hostAlias = lobby.hostAlias,
        hostSource = lobby.hostSource,
        phase = lobby.phase,
        players = players,
        playerCount = #lobby.memberOrder,
        minPlayers = cfg.MULTIPLAYER_MIN_PLAYERS_TO_START,
        maxPlayers = cfg.MULTIPLAYER_MAX_PLAYERS,
        raceOptions = lobby.raceOptions,
        expiresInSeconds = math.max(0, (lobby.expiresAt or 0) - now),
        startsInSeconds = lobby.startDeadlineAt and math.max(0, lobby.startDeadlineAt - now) or nil,
    }
    return payload
end

---@param lobby table
local function broadcastLobbyUpdate(lobby)
    local payload = buildLobbyPayload(lobby)
    for _, src in ipairs(lobby.memberOrder) do
        local memberPayload = {}
        for k, v in pairs(payload) do memberPayload[k] = v end
        memberPayload.selfServerId = src
        TriggerClientEvent('streetkings:mp:lobbyUpdate', src, memberPayload)
    end
end

---@param lobby table
---@return table
local function buildRaceSnapshots(lobby)
    local snapshots = {}
    for src, pstate in pairs(lobby.race.players) do
        local ped = GetPlayerPed(src)
        local coords = ped ~= 0 and GetEntityCoords(ped) or nil
        local distToNextCp = 999999
        local nextCp = lobby.race.checkpoints[pstate.nextCpIndex]
        if nextCp and coords then
            local dx = coords.x - nextCp.x
            local dy = coords.y - nextCp.y
            local dz = coords.z - nextCp.z
            distToNextCp = math.sqrt(dx * dx + dy * dy + dz * dz)
        end
        snapshots[#snapshots + 1] = {
            source = src,
            cpIndex = pstate.nextCpIndex - 1,
            distToNextCp = distToNextCp,
            finished = pstate.finished == true,
            forfeited = pstate.forfeited == true,
            vehicleNetId = pstate.vehicleNetId,
            elapsedMs = pstate.elapsedMs,
        }
    end
    return snapshots
end

---@param lobby table
local function broadcastRacePositions(lobby)
    if not lobby.race then
        return
    end

    local snapshots = buildRaceSnapshots(lobby)
    for src, _ in pairs(lobby.race.players) do
        TriggerClientEvent('streetkings:mp:positions', src, snapshots)
    end
end

---@param src integer
---@param reason string|nil
---@param seamless boolean|nil
local function notifyMemberRemoved(src, reason, seamless)
    TriggerClientEvent('streetkings:mp:lobbyClosed', src, {
        reason = reason or 'removed',
        seamless = seamless == true,
    })
end

---@param lobby table
local function announceLobbyOpenMessage(lobby)
    local timeoutMinutes = math.floor((lobby.raceOptions.lobbyTimeoutSeconds or SKEventsConfig.MULTIPLAYER_LOBBY_EXPIRY_SECONDS) / 60)
    local lapsLine = lobby.raceOptions.laps == 1 and '1 lap' or (tostring(lobby.raceOptions.laps) .. ' laps')
    local collisionLine = lobby.raceOptions.collision and 'On' or 'Off'
    local nitrousLine = lobby.raceOptions.nitrousEnabled and 'On' or 'Off'
    local trafficLine = tostring(lobby.raceOptions.trafficDensityPct) .. '%'
    local body = ([[%s is hosting a live race.

Event: %s
Type: %s
Class: %s
Laps: %s
Collision: %s
NOS: %s
Traffic: %s
Lobby closes in %d minutes.]]):format(
        lobby.hostAlias,
        lobby.eventName,
        lobby.eventTypeLabel,
        lobby.vehicleClass,
        lapsLine,
        collisionLine,
        nitrousLine,
        trafficLine,
        timeoutMinutes
    )

    SKMessages.broadcast(
        SKEventsConfig.MULTIPLAYER_MESSAGE_SENDER,
        SKEventsConfig.MULTIPLAYER_MESSAGE_AVATAR,
        body,
        {
            kind = 'joinLobby',
            lobbyId = lobby.id,
            label = 'Join Lobby',
        },
        { excludeSource = lobby.hostSource }
    )
end

---@param lobbyId string
---@param reason string
local function closeLobby(lobbyId, reason)
    local lobby = SKEventsServer.openRaceLobbies[lobbyId]
    if not lobby then return end

    local seamless = reason ~= 'finished'

    for _, src in ipairs(lobby.memberOrder) do
        SKEventsServer.lobbyIdBySource[src] = nil
        local transferred = false
        if seamless then
            transferred = transferMpVehicleToFreeroam(src)
        end
        if not transferred then
            cleanupMpVehicle(src)
        end
        notifyMemberRemoved(src, reason, transferred)
    end

    SKEventsServer.openRaceLobbies[lobbyId] = nil
end

---@param src integer
---@param lobby table
local function adoptFreeroamVehicleIntoLobby(src, lobby)
    local freeroamNetId = SKFreeroamServer.detachAssignedVehicle(src)
    if not freeroamNetId then return nil end
    SKFreeroamServer.moveVehicleToBucket(freeroamNetId, lobby.bucket)
    SKEventsServer.mpVehicleNetIdBySource[src] = freeroamNetId
    return freeroamNetId
end

---@param src integer
---@param lobby table
local function setupMember(src, lobby)
    lobby.members[src] = {
        alias = aliasFor(src),
        joinedAt = nowMs(),
    }
    lobby.memberOrder[#lobby.memberOrder + 1] = src
    SKEventsServer.lobbyIdBySource[src] = lobby.id
    adoptFreeroamVehicleIntoLobby(src, lobby)
    SKFreeroamServer.syncRoutingBucket(src)
end

---@param lobby table
---@param src integer
local function removeMember(lobby, src)
    lobby.members[src] = nil
    for i, memberSrc in ipairs(lobby.memberOrder) do
        if memberSrc == src then
            table.remove(lobby.memberOrder, i)
            break
        end
    end
    SKEventsServer.lobbyIdBySource[src] = nil

    if lobby.race and lobby.race.players[src] then
        lobby.race.players[src] = nil
    end

    cleanupMpVehicle(src)
end

---@param lobby table
local function transferHostIfNeeded(lobby, formerHost)
    if lobby.hostSource ~= formerHost then return end

    local nextHost = lobby.memberOrder[1]
    if not nextHost then
        return
    end

    lobby.hostSource = nextHost
    local member = lobby.members[nextHost]
    lobby.hostAlias = member and member.alias or aliasFor(nextHost)
end

---@param lobby table
local function maybeBeginCountdown(lobby)
    if lobby.phase ~= 'waiting' then return end
    local cfg = SKEventsConfig
    if #lobby.memberOrder < cfg.MULTIPLAYER_MAX_PLAYERS then return end

    lobby.phase = 'starting'
    lobby.startDeadlineAt = nowUnix() + cfg.MULTIPLAYER_START_COUNTDOWN_SECONDS
end

---@param lobby table
local function maybeRevertCountdown(lobby)
    if lobby.phase ~= 'starting' then return end
    local cfg = SKEventsConfig
    if #lobby.memberOrder >= cfg.MULTIPLAYER_MAX_PLAYERS then return end

    lobby.phase = 'waiting'
    lobby.startDeadlineAt = nil
end

local startRace, releaseRace

---@param src integer
---@return boolean ok, string? reason
function SKMultiplayerServer.startNow(src)
    local lobby = SKMultiplayerServer.getLobbyForSource(src)
    if not lobby then return false, 'lobby_missing' end
    if lobby.hostSource ~= src then return false, 'not_host' end
    if lobby.phase ~= 'waiting' and lobby.phase ~= 'starting' then
        return false, 'invalid_phase'
    end
    if #lobby.memberOrder < SKEventsConfig.MULTIPLAYER_MIN_PLAYERS_TO_START then
        return false, 'not_enough_players'
    end

    startRace(lobby)
    return true
end

---@param def table
---@return vector3[]
local function gridSlotsForDef(def, count)
    local cfg = SKEventsConfig
    local startPos = vector3(def.start.x, def.start.y, def.start.z)
    local headingRad = math.rad(def.start.w)
    local forwardX = -math.sin(headingRad)
    local forwardY = math.cos(headingRad)
    local rightX = math.cos(headingRad)
    local rightY = math.sin(headingRad)

    local slots = {}
    for i = 1, count do
        local row = math.floor((i - 1) / 2)
        local col = ((i - 1) % 2)
        local lateral = (col == 0 and -0.5 or 0.5) * cfg.MULTIPLAYER_GRID_LATERAL_SPACING
        local longitudinal = -row * cfg.MULTIPLAYER_GRID_LONGITUDINAL_SPACING
        local x = startPos.x + forwardX * longitudinal + rightX * lateral
        local y = startPos.y + forwardY * longitudinal + rightY * lateral
        local z = startPos.z
        slots[i] = vector3(x, y, z)
    end
    return slots
end

---@param lobby table
startRace = function(lobby)
    local def = SKEvents[lobby.eventId]
    if not def then
        closeLobby(lobby.id, 'invalid_event')
        return
    end

    local checkpoints, checkpointsPerLap, lapTotal = buildRaceCheckpoints(def, lobby.raceOptions)
    local slots = gridSlotsForDef(def, #lobby.memberOrder)
    local releaseAtMs = nowMs() + MP_RACE_RELEASE_DELAY_MS

    lobby.phase = 'racing'
    lobby.race = {
        startedAtMs = nil,
        releaseAtMs = releaseAtMs,
        checkpoints = checkpoints,
        checkpointsPerLap = checkpointsPerLap,
        lapTotal = lapTotal,
        collision = lobby.raceOptions.collision,
        players = {},
        finishOrder = {},
        firstFinishAtMs = nil,
    }

    local heading = def.start.w
    local roster = {}
    for i, src in ipairs(lobby.memberOrder) do
        local slot = slots[i]
        lobby.race.players[src] = {
            gridIndex = i,
            gridPos = slot,
            nextCpIndex = 1,
            validatedCount = 0,
            cpTimes = {},
            finished = false,
            finishedAtMs = nil,
            elapsedMs = nil,
            dnf = false,
            forfeited = false,
            vehicleNetId = nil,
            vehicleModel = nil,
        }
        roster[i] = {
            source = src,
            alias = lobby.members[src] and lobby.members[src].alias or aliasFor(src),
        }
    end

    for i, src in ipairs(lobby.memberOrder) do
        TriggerClientEvent('streetkings:mp:raceStarting', src, {
            lobbyId = lobby.id,
            eventId = lobby.eventId,
            eventName = lobby.eventName,
            vehicleClass = lobby.vehicleClass,
            gridPos = { x = slots[i].x, y = slots[i].y, z = slots[i].z, w = heading },
            roster = roster,
            checkpointCount = #checkpoints,
            checkpointsPerLap = checkpointsPerLap,
            lapTotal = lapTotal,
            collision = lobby.raceOptions.collision,
            nitrousEnabled = lobby.raceOptions.nitrousEnabled,
            trafficDensityPct = lobby.raceOptions.trafficDensityPct,
        })
    end

    CreateThread(function()
        Wait(MP_RACE_RELEASE_DELAY_MS)
        if SKEventsServer.openRaceLobbies[lobby.id] ~= lobby then
            return
        end
        if lobby.phase ~= 'racing' or not lobby.race or lobby.race.releaseAtMs ~= releaseAtMs then
            return
        end
        releaseRace(lobby)
    end)
end

---@param lobby table
releaseRace = function(lobby)
    if not lobby.race or lobby.race.startedAtMs then
        return
    end

    lobby.race.startedAtMs = nowMs()
    for _, src in ipairs(lobby.memberOrder) do
        TriggerClientEvent('streetkings:mp:raceGo', src)
    end
end

---@param lobby table
local function finalizeRaceResults(lobby)
    local cfg = SKEventsConfig
    local def = SKEvents[lobby.eventId]
    if not def or not lobby.race then return end

    local totalPlayers = 0
    for _ in pairs(lobby.race.players) do totalPlayers = totalPlayers + 1 end

    local finishOrder = {}
    local seen = {}
    for _, src in ipairs(lobby.race.finishOrder) do
        local pstate = lobby.race.players[src]
        if pstate and pstate.finished and not pstate.forfeited then
            finishOrder[#finishOrder + 1] = src
            seen[src] = true
        end
    end
    for src, pstate in pairs(lobby.race.players) do
        if not seen[src] then
            finishOrder[#finishOrder + 1] = src
            if not pstate.finished and not pstate.forfeited then
                pstate.dnf = true
            end
        end
    end

    local results = {}
    for position, src in ipairs(finishOrder) do
        local pstate = lobby.race.players[src]
        local member = lobby.members[src]
        local alias = member and member.alias or aliasFor(src)
        local didNotFinish = pstate.forfeited == true or pstate.dnf == true
        local reward = SKEventsRewards.awardMultiplayerRace(src, def, lobby.vehicleClass, position, totalPlayers, didNotFinish)

        if didNotFinish and cfg.MULTIPLAYER_FORFEIT_COST > 0 then
            local document = SKSaves.getDocument(src)
            if document then
                document.economy.cash = math.max(0, document.economy.cash - cfg.MULTIPLAYER_FORFEIT_COST)
                SKSaves.write(src, 'economy.cash', document.economy.cash)
            end
        end

        results[position] = {
            position = position,
            source = src,
            alias = alias,
            elapsedMs = pstate.elapsedMs,
            dnf = pstate.dnf == true,
            forfeited = pstate.forfeited == true,
            reward = reward,
            vehicleModel = pstate.vehicleModel or '',
        }
    end

    for src, _ in pairs(lobby.race.players) do
        local resultForMe = nil
        for _, entry in ipairs(results) do
            if entry.source == src then resultForMe = entry break end
        end
        TriggerClientEvent('streetkings:mp:raceResults', src, {
            eventId = lobby.eventId,
            eventName = lobby.eventName,
            vehicleClass = lobby.vehicleClass,
            totalPlayers = totalPlayers,
            results = results,
            myResult = resultForMe,
        })
        SKEventsServer.lobbyIdBySource[src] = nil
    end

    lobby.phase = 'finished'
    SKEventsServer.openRaceLobbies[lobby.id] = nil
end

---@param lobby table
---@return boolean
local function allPlayersDone(lobby)
    if not lobby.race then return false end
    for _, pstate in pairs(lobby.race.players) do
        if not pstate.finished and not pstate.forfeited then
            return false
        end
    end
    return true
end

---@param src integer
---@return boolean
function SKMultiplayerServer.requestForfeit(src)
    local lobby = SKMultiplayerServer.getLobbyForSource(src)
    if not lobby or lobby.phase ~= 'racing' then return false end
    local pstate = lobby.race.players[src]
    if not pstate or pstate.finished or pstate.forfeited then return false end

    pstate.forfeited = true
    broadcastRacePositions(lobby)

    if allPlayersDone(lobby) then
        finalizeRaceResults(lobby)
    end

    return true
end

---@param src integer
---@param cpIndex integer
---@return boolean
function SKMultiplayerServer.onCheckpointHit(src, cpIndex)
    local lobby = SKMultiplayerServer.getLobbyForSource(src)
    if not lobby or lobby.phase ~= 'racing' then return false end
    local pstate = lobby.race.players[src]
    if not pstate or pstate.finished or pstate.forfeited then return false end
    if not lobby.race.startedAtMs then return false end

    if type(cpIndex) ~= 'number' or cpIndex % 1 ~= 0 then return false end
    local cp = lobby.race.checkpoints[cpIndex]
    if not cp then return false end

    local dist = playerDistanceTo(src, cp)
    if dist > MP_RACE_CHECKPOINT_RADIUS then
        return false
    end

    if cpIndex ~= pstate.nextCpIndex then
        return false
    end

    pstate.nextCpIndex = pstate.nextCpIndex + 1
    pstate.validatedCount = pstate.validatedCount + 1
    pstate.cpTimes[cpIndex] = nowMs() - lobby.race.startedAtMs
    broadcastRacePositions(lobby)

    return true
end

---@param src integer
---@param elapsedMs integer
---@return boolean
function SKMultiplayerServer.onFinish(src, elapsedMs)
    local lobby = SKMultiplayerServer.getLobbyForSource(src)
    if not lobby or lobby.phase ~= 'racing' then return false end
    local pstate = lobby.race.players[src]
    if not pstate or pstate.finished or pstate.forfeited then return false end
    if not lobby.race.startedAtMs then return false end
    if pstate.validatedCount ~= #lobby.race.checkpoints then return false end

    local serverElapsed = nowMs() - lobby.race.startedAtMs
    if type(elapsedMs) ~= 'number' or elapsedMs < 0 or elapsedMs > serverElapsed + 3000 then
        elapsedMs = serverElapsed
    end

    pstate.finished = true
    pstate.finishedAtMs = nowMs()
    pstate.elapsedMs = elapsedMs
    lobby.race.finishOrder[#lobby.race.finishOrder + 1] = src
    broadcastRacePositions(lobby)

    if not lobby.race.firstFinishAtMs then
        lobby.race.firstFinishAtMs = pstate.finishedAtMs
    end

    if allPlayersDone(lobby) then
        finalizeRaceResults(lobby)
    end

    return true
end

---@param src integer
---@param eventId string
---@param options table|nil
---@return table
function SKMultiplayerServer.create(src, eventId, options)
    if not SKEventsServer.dbReady then return { ok = false, reason = 'db_not_ready' } end
    if not SKSaves.hasActiveSave(src) then return { ok = false, reason = 'no_active_save' } end
    if SKGameStateServer.get(src) ~= GameState.FREEROAM then return { ok = false, reason = 'invalid_state' } end
    if SKEventsServer.lobbyIdBySource[src] then return { ok = false, reason = 'already_in_lobby' } end
    if type(eventId) ~= 'string' or not SKEventsQuery.isTimeTrialEvent(eventId) then return { ok = false, reason = 'invalid_event' } end

    local def = SKEvents[eventId]
    if not def or def.type ~= EventType.RACE then return { ok = false, reason = 'not_a_race' } end

    local vehicleClass = SKEventsRewards.getActiveVehicleClass(src)
    if not vehicleClass then return { ok = false, reason = 'no_active_vehicle' } end

    local cfg = SKEventsConfig
    local lobbyId = lib.string.random('........')
    local bucket = allocateBucket()
    local hostAlias = aliasFor(src)
    local raceOptions = normalizeRaceOptions(def, options)

    local lobby = {
        id = lobbyId,
        eventId = eventId,
        eventName = def.name,
        eventTypeLabel = eventTypeLabel(def),
        hostSource = src,
        hostAlias = hostAlias,
        vehicleClass = vehicleClass,
        members = {},
        memberOrder = {},
        bucket = bucket,
        phase = 'waiting',
        raceOptions = raceOptions,
        createdAt = nowUnix(),
        expiresAt = nowUnix() + raceOptions.lobbyTimeoutSeconds,
        startDeadlineAt = nil,
        race = nil,
    }
    SKEventsServer.openRaceLobbies[lobbyId] = lobby

    setupMember(src, lobby)
    announceLobbyOpenMessage(lobby)

    return {
        ok = true,
        lobby = buildLobbyPayload(lobby),
    }
end

---@param src integer
---@param lobbyId string
---@return table
function SKMultiplayerServer.join(src, lobbyId)
    if not SKSaves.hasActiveSave(src) then return { ok = false, reason = 'no_active_save' } end
    if SKGameStateServer.get(src) ~= GameState.FREEROAM then return { ok = false, reason = 'invalid_state' } end
    if SKEventsServer.lobbyIdBySource[src] then return { ok = false, reason = 'already_in_lobby' } end

    local lobby = SKEventsServer.openRaceLobbies[lobbyId]
    if not lobby then return { ok = false, reason = 'lobby_missing' } end
    if lobby.phase ~= 'waiting' and lobby.phase ~= 'starting' then
        return { ok = false, reason = 'lobby_started' }
    end

    local cfg = SKEventsConfig
    if #lobby.memberOrder >= cfg.MULTIPLAYER_MAX_PLAYERS then
        return { ok = false, reason = 'lobby_full' }
    end

    local vehicleClass = SKEventsRewards.getActiveVehicleClass(src)
    if not vehicleClass then return { ok = false, reason = 'no_active_vehicle' } end
    if vehicleClass ~= lobby.vehicleClass then
        return { ok = false, reason = 'class_mismatch', hostClass = lobby.vehicleClass }
    end

    setupMember(src, lobby)
    maybeBeginCountdown(lobby)
    broadcastLobbyUpdate(lobby)

    return {
        ok = true,
        lobby = buildLobbyPayload(lobby),
    }
end

---@param src integer
function SKMultiplayerServer.leave(src)
    local lobby = SKMultiplayerServer.getLobbyForSource(src)
    if not lobby then return end
    if lobby.phase == 'racing' then
        return
    end

    local wasHost = lobby.hostSource == src
    local transferred = transferMpVehicleToFreeroam(src)
    removeMember(lobby, src)
    notifyMemberRemoved(src, 'left', transferred)

    if #lobby.memberOrder == 0 then
        SKEventsServer.openRaceLobbies[lobby.id] = nil
        return
    end

    if wasHost then
        transferHostIfNeeded(lobby, src)
    end

    maybeRevertCountdown(lobby)
    broadcastLobbyUpdate(lobby)
end

---@param src integer
function SKMultiplayerServer.onPlayerDropped(src)
    local lobby = SKMultiplayerServer.getLobbyForSource(src)
    if not lobby then return end

    local wasHost = lobby.hostSource == src
    removeMember(lobby, src)

    if #lobby.memberOrder == 0 then
        if lobby.phase == 'racing' then
            lobby.phase = 'finished'
        end
        SKEventsServer.openRaceLobbies[lobby.id] = nil
        return
    end

    if lobby.phase == 'racing' then
        if allPlayersDone(lobby) then
            finalizeRaceResults(lobby)
        end
        return
    end

    if wasHost then
        transferHostIfNeeded(lobby, src)
    end

    maybeRevertCountdown(lobby)
    broadcastLobbyUpdate(lobby)
end

---@param src integer
---@param vehicleModel string|nil
---@return table
function SKMultiplayerServer.prepareRaceVehicle(src, vehicleModel)
    local lobby = SKMultiplayerServer.getLobbyForSource(src)
    if not lobby or lobby.phase ~= 'racing' or not lobby.race then
        return { ok = false, reason = 'invalid_state' }
    end
    if SKGameStateServer.get(src) ~= GameState.MULTIPLAYER_EVENT then
        return { ok = false, reason = 'invalid_state' }
    end
    local pstate = lobby.race.players[src]
    if not pstate then
        return { ok = false, reason = 'not_racer' }
    end

    local mpNetId = SKEventsServer.mpVehicleNetIdBySource[src]
    if not mpNetId then
        return { ok = false, reason = 'no_vehicle' }
    end

    pstate.vehicleNetId = mpNetId
    pstate.vehicleModel = (type(vehicleModel) == 'string' and #vehicleModel <= 64) and vehicleModel or ''

    return {
        ok = true,
        netId = mpNetId,
        releaseInMs = math.max(0, lobby.race.releaseAtMs - nowMs()),
        checkpointCount = #lobby.race.checkpoints,
    }
end

-- Callbacks -------------------------------------------------------------

lib.callback.register('streetkings:events:createRaceLobby', function(source, eventId, options)
    return SKMultiplayerServer.create(source, eventId, options)
end)

lib.callback.register('streetkings:events:joinRaceLobby', function(source, lobbyId)
    return SKMultiplayerServer.join(source, lobbyId)
end)

lib.callback.register('streetkings:events:leaveRaceLobby', function(source)
    SKMultiplayerServer.leave(source)
    return { ok = true }
end)

lib.callback.register('streetkings:events:startRaceNow', function(source)
    local ok, reason = SKMultiplayerServer.startNow(source)
    return { ok = ok, reason = reason }
end)

lib.callback.register('streetkings:mp:prepareRaceVehicle', function(source, vehicleModel)
    return SKMultiplayerServer.prepareRaceVehicle(source, vehicleModel)
end)

lib.callback.register('streetkings:mp:claimRaceReturn', function(source)
    local lobby = SKMultiplayerServer.getLobbyForSource(source)
    if lobby and lobby.phase == 'racing' and lobby.race then
        local pstate = lobby.race.players[source]
        if pstate and pstate.forfeited then
            SKEventsServer.lobbyIdBySource[source] = nil
        end
    end
    local seamless, netId = transferMpVehicleToFreeroam(source)
    return { seamless = seamless, netId = netId }
end)

RegisterNetEvent('streetkings:mp:checkpointHit', function(cpIndex)
    SKMultiplayerServer.onCheckpointHit(source --[[@as integer]], cpIndex)
end)

lib.callback.register('streetkings:mp:checkpointHit', function(source, cpIndex)
    local ok = SKMultiplayerServer.onCheckpointHit(source, cpIndex)
    return { ok = ok }
end)

lib.callback.register('streetkings:mp:finish', function(source, elapsedMs)
    local ok = SKMultiplayerServer.onFinish(source, elapsedMs)
    return { ok = ok }
end)

lib.callback.register('streetkings:mp:forfeit', function(source)
    local ok = SKMultiplayerServer.requestForfeit(source)
    return { ok = ok }
end)

AddEventHandler('playerDropped', function()
    SKMultiplayerServer.onPlayerDropped(source --[[@as integer]])
end)

-- Lifecycle threads -----------------------------------------------------

CreateThread(function()
    while true do
        Wait(1000)

        local now = nowUnix()
        local lobbyIds = {}
        for lobbyId in pairs(SKEventsServer.openRaceLobbies) do
            lobbyIds[#lobbyIds + 1] = lobbyId
        end

        for _, lobbyId in ipairs(lobbyIds) do
            local lobby = SKEventsServer.openRaceLobbies[lobbyId]
            if lobby then
                if lobby.phase == 'waiting' and lobby.expiresAt <= now then
                    closeLobby(lobbyId, 'expired')
                elseif lobby.phase == 'waiting' then
                    maybeBeginCountdown(lobby)
                    broadcastLobbyUpdate(lobby)
                elseif lobby.phase == 'starting' then
                    if lobby.startDeadlineAt and lobby.startDeadlineAt <= now then
                        startRace(lobby)
                    else
                        broadcastLobbyUpdate(lobby)
                    end
                elseif lobby.phase == 'racing' and lobby.race then
                    local cfg = SKEventsConfig
                    if not lobby.race.startedAtMs then
                        if nowMs() >= lobby.race.releaseAtMs then
                            releaseRace(lobby)
                        end
                    elseif lobby.race.firstFinishAtMs and (nowMs() - lobby.race.firstFinishAtMs) >= cfg.MULTIPLAYER_RACE_FINISH_GRACE_SECONDS * 1000 then
                        finalizeRaceResults(lobby)
                    elseif (nowMs() - lobby.race.startedAtMs) >= MP_RACE_TIMEOUT_MS then
                        finalizeRaceResults(lobby)
                    end
                elseif lobby.phase == 'finished' then
                    closeLobby(lobbyId, 'finished')
                end
            end
        end
    end
end)

-- Position broadcast (once per second) ---------------------------------------------

CreateThread(function()
    while true do
        local cfg = SKEventsConfig
        Wait(cfg.MULTIPLAYER_POSITION_BROADCAST_INTERVAL_MS)

        for _, lobby in pairs(SKEventsServer.openRaceLobbies) do
            if lobby.phase == 'racing' and lobby.race then
                broadcastRacePositions(lobby)
            end
        end
    end
end)