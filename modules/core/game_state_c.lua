---@class GameStateDefinition
---@field onEnter fun(prevState: string|nil)|nil
---@field onExit fun(nextState: string)|nil
---@field onTick fun()|nil
---@field tickWait integer|nil wait ms after each onTick; default 0

--- Client framework table (short global `SKC`)
SKC = SKC or {}

local definitions = {}
local currentState = nil
local tickGeneration = 0

---@param id string
---@param def GameStateDefinition
function SKC.RegisterGameState(id, def)
    definitions[id] = def
end

---@return string|nil
function SKC.GetGameState()
    return currentState
end

---@param id string
---@return boolean
function SKC.SetGameState(id)
    local def = definitions[id]
    if not def then
        print(('[SK:GameState] unknown game state "%s"'):format(tostring(id)))
        return false
    end

    local prev = currentState
    local transition = lib.callback.await('streetkings:core:requestStateTransition', false, prev, id)
    if not transition or transition.ok ~= true or type(transition.token) ~= 'string' then
        return false
    end

    TriggerServerEvent('streetkings:core:stateTransitionWill', transition.token)
    if prev and definitions[prev] and definitions[prev].onExit then
        definitions[prev].onExit(id)
    end

    currentState = id
    TriggerServerEvent('streetkings:core:stateTransitionDid', transition.token)
    tickGeneration = tickGeneration + 1
    local myGen = tickGeneration

    if def.onEnter then
        def.onEnter(prev)
    end

    if def.onTick then
        local tickWait = def.tickWait
        if tickWait == nil then
            tickWait = 0
        end
        CreateThread(function()
            while currentState == id and myGen == tickGeneration do
                def.onTick()
                Wait(tickWait)
            end
        end)
    end

    return true
end

exports('GetGameState', SKC.GetGameState)
exports('SetGameState', SKC.SetGameState)
exports('RegisterGameState', SKC.RegisterGameState)