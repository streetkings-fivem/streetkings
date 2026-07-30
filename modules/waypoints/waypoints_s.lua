SKServerWaypoint = SKServerWaypoint or {}

local serverWaypoints = {}
local nextServerId    = 1

local function getTargetPlayers(target)
    if target == -1 then
        return GetPlayers()
    elseif type(target) == 'table' then
        return target
    else
        return { tostring(target) }
    end
end

function SKServerWaypoint.Create(target, data)
    local sid = nextServerId
    nextServerId = nextServerId + 1
    data._serverId = sid

    local entry = {
        target    = target,
        data      = data,
        clientMap = {},
    }
    serverWaypoints[sid] = entry

    local players = getTargetPlayers(target)
    for _, pid in ipairs(players) do
        TriggerClientEvent('streetkings:waypoints:client:create', tonumber(pid), data)
    end

    return sid
end

function SKServerWaypoint.Remove(sid)
    local entry = serverWaypoints[sid]
    if not entry then return end

    for pid, cid in pairs(entry.clientMap) do
        TriggerClientEvent('streetkings:waypoints:client:remove', tonumber(pid), cid)
    end

    serverWaypoints[sid] = nil
end

function SKServerWaypoint.Update(sid, data)
    local entry = serverWaypoints[sid]
    if not entry then return end

    for k, v in pairs(data) do
        entry.data[k] = v
    end

    for pid, cid in pairs(entry.clientMap) do
        TriggerClientEvent('streetkings:waypoints:client:update', tonumber(pid), cid, data)
    end
end

function SKServerWaypoint.RemoveAll(playerId)
    if playerId then
        for _, entry in pairs(serverWaypoints) do
            if entry.clientMap[playerId] then
                TriggerClientEvent('streetkings:waypoints:client:remove', playerId, entry.clientMap[playerId])
                entry.clientMap[playerId] = nil
            end
        end
    else
        for sid in pairs(serverWaypoints) do
            SKServerWaypoint.Remove(sid)
        end
    end
end

function SKServerWaypoint.Get(sid)
    return serverWaypoints[sid]
end

function SKServerWaypoint.GetAll()
    return serverWaypoints
end

RegisterNetEvent('streetkings:waypoints:server:ack', function(serverId, clientId)
    local src = source
    local entry = serverWaypoints[serverId]
    if entry then
        entry.clientMap[src] = clientId
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, entry in pairs(serverWaypoints) do
        entry.clientMap[src] = nil
    end
end)

RegisterNetEvent('streetkings:waypoints:server:requestSync', function()
    local src = source
    for _, entry in pairs(serverWaypoints) do
        if entry.target == -1 then
            TriggerClientEvent('streetkings:waypoints:client:create', src, entry.data)
        end
    end
end)

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(2000, function()
        TriggerClientEvent('streetkings:waypoints:client:requestSync', src)
    end)
end)

exports('CreateServerWaypoint', function(target, data)
    if not target or type(data) ~= 'table' then return nil end
    return SKServerWaypoint.Create(target, data)
end)
exports('RemoveServerWaypoint', function(sid)
    if type(sid) ~= 'number' then return false end
    SKServerWaypoint.Remove(sid)
    return true
end)
exports('GetServerWaypoints', SKServerWaypoint.GetAll)