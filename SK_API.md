# StreetKings Developer API

StreetKings is a standalone FiveM framework that manages its own game states, vehicles, progression, police, economy, and more. Third-party add-on resources can interact with StreetKings through the exports documented here.

All exports live on the `streetkings` resource. Call them the standard FiveM way:

```lua
-- client or server
local state = exports['streetkings']:GetGameState()
```

---

## SKConfig (data/sk_config.lua)

Global configuration flags that can be toggled before the resource starts. Edit `data/sk_config.lua` to customize.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `SKConfig.DisableSpeedometer` | `boolean` | `false` | Completely disables the built-in speedometer, allowing a third-party speedometer resource to be used instead. |
| `SKConfig.DisablePauseMenu` | `boolean` | `false` | Completely disables the built-in pause menu, allowing a custom pause menu resource to be used instead. |

```lua
-- data/sk_config.lua
SKConfig = {
    DisableSpeedometer = true,  -- use my own speedometer
    DisablePauseMenu   = true,  -- use my own pause menu
}
```

---

## SK.* Helpers (Client)

A set of global helper functions available to any client script inside the `streetkings` resource. They are also exported, so add-on resources can call them via `exports['streetkings']:LoadModel(...)` etc.

### SK.LoadModel(model, timeout?)

Requests a model and blocks until it finishes loading.

| Param | Type | Description |
|-------|------|-------------|
| model | `string` or `number` | Model name or hash |
| timeout | `integer?` | Max wait in ms (default 5000) |

**Returns:** `integer` hash on success, `nil` on failure.

```lua
local hash = SK.LoadModel('adder')
if not hash then return end
local veh = CreateVehicle(hash, x, y, z, heading, true, false)
SK.UnloadModel('adder')
```

### SK.UnloadModel(model)

Marks a model as no longer needed so the engine can free it.

| Param | Type | Description |
|-------|------|-------------|
| model | `string` or `number` | Model name or hash |

### SK.LoadAnimDict(dict, timeout?)

Requests an animation dictionary and blocks until loaded.

| Param | Type | Description |
|-------|------|-------------|
| dict | `string` | Animation dictionary name |
| timeout | `integer?` | Max wait in ms (default 3000) |

**Returns:** `true` on success, `false` on failure or timeout.

```lua
if SK.LoadAnimDict('mp_facial') then
    PlayFacialAnim(ped, 'mic_chatter', 'mp_facial')
end
```

### SK.LoadAnimSet(set, timeout?)

Requests an animation set and blocks until loaded. Returns `true`/`false`.

### SK.LoadPtfxAsset(asset, timeout?)

Requests a named particle effect asset and blocks until loaded. Returns `true`/`false`.

---

## Client Exports

### Game State

| Export | Returns | Description |
|--------|---------|-------------|
| `GetGameState()` | `string?` | Current game state id (see Game States below) |
| `SetGameState(id)` | `boolean` | Transition to a new game state |
| `RegisterGameState(id, def)` | | Register a custom game state with `onEnter`, `onExit`, `onTick` callbacks |

```lua
-- Register a custom game state from an add-on
exports['streetkings']:RegisterGameState('my_minigame', {
    onEnter = function(prev) print('entered minigame from', prev) end,
    onExit  = function(next) print('leaving minigame for', next) end,
})
```

### Freeroam

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `GetPlayerVehicle()` | | `integer?` | The entity handle of the player's current SK-assigned vehicle |
| `IsInFreeroam()` | | `boolean` | Whether the player is currently in the freeroam state |
| `IsPlayerWasted()` | | `boolean` | Whether the player is in the wasted/death state |
| `AllowLeaveVehicle(on)` | `boolean` | `boolean` | Allow the player to exit and re-enter their vehicle. By default StreetKings locks the player in their vehicle. Set back to `false` when done to restore the lock. |

```lua
-- only run logic while the player is in freeroam and alive
CreateThread(function()
    while true do
        if exports['streetkings']:IsInFreeroam() and not exports['streetkings']:IsPlayerWasted() then
            local veh = exports['streetkings']:GetPlayerVehicle()
            if veh and veh ~= 0 then
                -- do something with the player's vehicle
            end
        end
        Wait(1000)
    end
end)
```

```lua
-- let the player get out of their car for an on-foot activity
exports['streetkings']:AllowLeaveVehicle(true)

-- re-lock the player into their vehicle when done
exports['streetkings']:AllowLeaveVehicle(false)
```

### Notifications

| Export | Params | Description |
|--------|--------|-------------|
| `ShowNotification(options)` | `{ title, type, duration, inCinematic? }` | Display a toast notification. Type can be `'info'`, `'success'`, `'error'`. |

Each notification runs in its own thread. By default, notifications **wait** until cinematic mode ends before displaying. Pass `inCinematic = true` to show the notification immediately even during cinematics.

```lua
exports['streetkings']:ShowNotification({ title = 'Package Delivered', type = 'success', duration = 3000 })

-- force show during a cinematic
exports['streetkings']:ShowNotification({ title = 'Objective Updated', type = 'info', inCinematic = true })
```

### Phone

| Export | Returns | Description |
|--------|---------|-------------|
| `IsPhoneOpen()` | `boolean` | Whether the phone UI is currently open |
| `OpenPhone(payload?)` | | Open the phone (optional payload table) |
| `ClosePhone()` | | Close the phone |

```lua
-- close the phone before starting a cutscene
if exports['streetkings']:IsPhoneOpen() then
    exports['streetkings']:ClosePhone()
end
```

### Police

| Export | Returns | Description |
|--------|---------|-------------|
| `IsPoliceChasing()` | `boolean` | Whether police are actively chasing the player |
| `GetWantedLevel()` | `integer` | Current GTA wanted level (0-5) |
| `IsNearPolice(distance)` | `entity?, boolean` | Returns nearest police entity and `true` if any police is within the given distance |

```lua
-- check if the player is being chased before allowing an action
if exports['streetkings']:IsPoliceChasing() then
    exports['streetkings']:ShowNotification({ title = 'Lose the cops first!', type = 'error' })
    return
end

-- check proximity to police
local cop, isNear = exports['streetkings']:IsNearPolice(25.0)
if isNear then
    -- cop entity is nearby
end
```

### Vehicle Data

| Export | Returns | Description |
|--------|---------|-------------|
| `GetAllVehicleData()` | `table` | The full `SKVehicles` catalog (model -> { name, brand, price, category, type, hash }) |
| `GetVehicleData(model)` | `table?` | Single entry from the catalog for the given model name, or nil |

```lua
local data = exports['streetkings']:GetVehicleData('adder')
if data then
    print(data.brand, data.name, data.price)
end
```

### Waypoints

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `CreateWaypoint(data)` | `{ coords, text, color, icon, ... }` | `integer` id | Create a 3D waypoint in the world |
| `RemoveWaypoint(id)` | waypoint id | | Remove a specific waypoint |
| `RemoveAllWaypoints()` | | | Remove all active waypoints |

```lua
-- create a waypoint for a delivery location
local wpId = exports['streetkings']:CreateWaypoint({
    coords = vector3(200.0, -800.0, 30.0),
    text   = 'Drop-off',
    color  = { r = 0, g = 200, b = 100 },
})

-- clean up when done
exports['streetkings']:RemoveWaypoint(wpId)
```

### Progression

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `GetVehicleAvailability(vehicle)` | entity handle | `table[]` | Collects available vehicle mod types and options for the given vehicle |

### Camera

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `IsChaseCamEnabled()` | | `boolean` | Whether the custom chase camera is currently active |
| `EnableChaseCam(vehicle)` | entity handle | | Enable the chase camera for a vehicle |
| `DisableChaseCam()` | | | Disable the chase camera |
| `SetCinematicMode(on)` | `boolean` | `boolean` | Enable or disable cinematic mode. While active, the SK driving camera pauses, the busted countdown is suppressed, and notifications are queued until cinematic mode ends. Set back to `false` when done to re-enable the driving camera. |

```lua
-- enter cinematic mode for a custom cutscene
exports['streetkings']:SetCinematicMode(true)

-- ... run your camera logic ...

-- re-enable the driving camera
exports['streetkings']:SetCinematicMode(false)
```

### Warp

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `WarpPlayer(coords, heading?)` | position, optional heading | | Cinematic warp to a location |
| `WarpToWaypoint()` | | `boolean, string` | Warp to the player's map waypoint. Returns success and error message. |

```lua
-- teleport the player to a specific location
exports['streetkings']:WarpPlayer(vector3(150.0, -1000.0, 29.0), 90.0)

-- teleport the player to their map waypoint
local ok, err = exports['streetkings']:WarpToWaypoint()
if not ok then
    exports['streetkings']:ShowNotification({ title = err, type = 'error' })
end
```

### Speedometer

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `SetSpeedometerEnabled(on)` | `boolean` | `boolean` | Show or hide the speedometer HUD. Returns `false` if `on` is not a boolean. |

```lua
-- hide the speedometer during a custom UI screen
exports['streetkings']:SetSpeedometerEnabled(false)

-- re-enable it afterwards
exports['streetkings']:SetSpeedometerEnabled(true)
```

### Soundtrack

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `GetCurrentTrack()` | | `table?` | Current playing track: `{ key, title, stationKey, durationMs }` or nil |
| `SetSoundtrackEnabled(on)` | `boolean` | `boolean` | Enable or disable the managed soundtrack system. Returns `false` if `on` is not a boolean. |

```lua
-- display the current track name
local track = exports['streetkings']:GetCurrentTrack()
if track then
    exports['streetkings']:ShowNotification({ title = 'Now playing: ' .. track.title, type = 'info' })
end

-- mute the soundtrack during custom audio
exports['streetkings']:SetSoundtrackEnabled(false)
```

### Environment

| Export | Returns | Description |
|--------|---------|-------------|
| `GetCurrentTime()` | `{ h, m, s }` | Current in-game time (hours, minutes, seconds) |
| `GetCurrentWeather()` | `string?` | Current weather type (e.g. `'CLEAR'`, `'RAIN'`, `'FOGGY'`) |

```lua
local time = exports['streetkings']:GetCurrentTime()
local weather = exports['streetkings']:GetCurrentWeather()
print(('Time: %02d:%02d  Weather: %s'):format(time.h, time.m, weather or 'unknown'))
```

---

## Server Exports

### Save System

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `HasActiveSave(source)` | player server id | `boolean` | Check if a player has an active save loaded |
| `ReadSaveData(source, path)` | server id, dot-path key | `any` | Read a value from the player's save document (e.g. `'economy.cash'`). Returns `nil` if no save or invalid path. |
| `WriteSaveData(source, path, value)` | server id, dot-path key, value | `boolean` | Write a value to the player's save document. Returns `false` if no save or invalid path. |
| `PersistSave(source)` | server id | `boolean` | Flush the player's save to the database. Returns `false` if no active save. |

```lua
-- guard any server action behind a save check
if not exports['streetkings']:HasActiveSave(source) then return end

-- read and write custom data for your add-on
local rep = exports['streetkings']:ReadSaveData(source, 'myAddon.reputation') or 0
exports['streetkings']:WriteSaveData(source, 'myAddon.reputation', rep + 10)

-- flush to database after important changes
exports['streetkings']:PersistSave(source)
```

### Economy

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `GetPlayerCash(source)` | server id | `number` | Get the player's current cash balance (returns 0 if no active save) |
| `AddPlayerCash(source, amount)` | server id, amount | `boolean` | Add cash. Returns `false` if no active save or invalid amount. |
| `RemovePlayerCash(source, amount)` | server id, amount | `boolean` | Remove cash. Returns `false` if no save, invalid amount, or insufficient funds. |

```lua
local cash = exports['streetkings']:GetPlayerCash(source)
if cash >= 5000 then
    exports['streetkings']:RemovePlayerCash(source, 5000)
end
```

### Progression

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `AwardPlayerXp(source, amount)` | server id, xp amount | `table?` | Award player XP. Returns `{ xpGained, oldLevel, newLevel, levelUps }` or `nil` if invalid amount or no save. |
| `AwardVehicleXp(source, amount)` | server id, xp amount | `table?` | Award vehicle XP for the active vehicle. Returns `nil` if invalid amount or no save. |
| `GetPlayerLevel(source)` | server id | `integer` | Get the player's current level (defaults to 1 if no save) |
| `RecordActivityBest(source, activityId, score, scoreType)` | server id, string id, number, `'time'`\|`'speed'` | `boolean, boolean, number?` | Record a personal best. Returns `isFirst`, `improved`, `previousScore`. Returns `false` if no save or invalid params. |

```lua
-- reward XP after completing a job
local result = exports['streetkings']:AwardPlayerXp(source, 250)
if result and result.newLevel > result.oldLevel then
    TriggerClientEvent('myAddon:levelUp', source, result.newLevel)
end

-- award vehicle XP alongside player XP
exports['streetkings']:AwardVehicleXp(source, 100)

-- gate content behind player level
local level = exports['streetkings']:GetPlayerLevel(source)
if level < 10 then
    TriggerClientEvent('myAddon:notify', source, 'You need level 10 to unlock this.')
    return
end

-- record a time trial result (lower is better for 'time', higher is better for 'speed')
local isFirst, improved, previous = exports['streetkings']:RecordActivityBest(source, 'my_time_trial_1', lapTimeMs, 'time')
if isFirst then
    TriggerClientEvent('myAddon:notify', source, 'First attempt recorded!')
elseif improved then
    TriggerClientEvent('myAddon:notify', source, ('New best! Previous: %dms'):format(previous))
end
```

### Stats

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `RegisterStat(key)` | stat key string | `boolean` | Register a persisted custom stat without adding it to the phone UI. Existing signature retained for compatibility. |
| `RegisterStat(definition)` | `{ category, id, label, categoryIcon?, icon?, format? }` | `boolean` | Register a persisted custom stat and dynamically add it to the phone Stats app. |
| `RegisterStat(category, id, label, options?)` | category, stat id, label, options | `boolean` | Positional form of dynamic phone stat registration. |
| `IncrementStat(source, key, amount?)` | server id, stat key, amount (default 1) | `boolean` | Increment a numeric stat. Returns `false` if invalid key, no save, or bad types. |
| `SetStatMax(source, key, value)` | server id, stat key, value | `boolean` | Set a stat only if the new value is higher. Returns `false` if invalid key, no save, or bad types. |

**Built-in stat keys:**

| Key | Type | Description |
|-----|------|-------------|
| `totalMilesDriven` | `float` | Total distance driven in miles |
| `topSpeedMph` | `float` | Highest recorded speed in mph |
| `totalCashEarned` | `integer` | Lifetime cash earned |
| `totalCashSpent` | `integer` | Lifetime cash spent |
| `racesCompleted` | `integer` | Total races finished |
| `racesWon` | `integer` | Total races won |
| `npcChallengesWon` | `integer` | NPC challenges beaten |
| `rampagesCompleted` | `integer` | Rampages completed |
| `stuntJumpsCompleted` | `integer` | Stunt jumps landed |
| `speedCameraFlashes` | `integer` | Speed camera flashes triggered |
| `policeBusts` | `integer` | Times busted by police |
| `policeEscapes` | `integer` | Successful police escapes |
| `totalRepairs` | `integer` | Vehicle repairs performed |
| `clothingPurchased` | `integer` | Clothing items bought |

Add-on resources can register their own stat keys with `RegisterStat` and then use them with `IncrementStat`/`SetStatMax`. Custom stats are persisted alongside built-in stats in the player's save.

Dynamic phone rows support the formats `integer`, `cash`, `miles`, `mph`, and `xp`. Existing category names such as `Activities` append to that category; a new category name creates a new section. Icons use Font Awesome class names.

```lua
-- register custom stats once at resource start
exports['streetkings']:RegisterStat('longestDeliveryStreak')

-- register a persisted stat and show it in the phone Stats app
exports['streetkings']:RegisterStat({
    category = 'Activities',
    id = 'deliveriesCompleted',
    label = 'Deliveries Completed',
    icon = 'fa-box',
    format = 'integer',
})

-- positional form
exports['streetkings']:RegisterStat('Driving', 'bestDriftMph', 'Best Drift Speed', {
    icon = 'fa-gauge-high',
    format = 'mph',
})

-- increment after a delivery
exports['streetkings']:IncrementStat(source, 'deliveriesCompleted', 1)

-- track the longest streak (only saves if the new value is higher)
exports['streetkings']:SetStatMax(source, 'longestDeliveryStreak', currentStreak)

-- built-in keys work the same way
exports['streetkings']:IncrementStat(source, 'totalCashEarned', payment)
```

### Messages

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `SendPhoneMessage(source, sender, avatar, body, delay?, action?, banner?)` | server id + message fields | `boolean` | Enqueue a phone message to a specific player. Returns `false` if sender/body invalid or no save. |
| `BroadcastPhoneMessage(sender, avatar, body, action?, options?)` | message fields | `boolean` | Send a phone message to all players with active saves. Returns `false` if sender/body invalid. |

```lua
exports['streetkings']:SendPhoneMessage(source, 'The Boss', 'boss', 'Meet me at the docks.')
exports['streetkings']:BroadcastPhoneMessage('News', 'news', 'A new event is starting!')
```

### Game State (Server)

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `GetPlayerGameState(source)` | server id | `string?` | Get a player's current game state from the server side |

```lua
-- only allow an action while the player is in freeroam
local state = exports['streetkings']:GetPlayerGameState(source)
if state ~= 'freeroam' then
    TriggerClientEvent('myAddon:notify', source, 'You must be in freeroam.')
    return
end
```

### Environment (Server)

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `SetTime(hour)` | integer 0-23 | `boolean` | Set the in-game hour. Returns `false` if hour is not a number. |
| `SetWeather(weather)` | weather string | `boolean` | Set the weather (e.g. `'CLEAR'`, `'RAIN'`, `'THUNDER'`). Returns `false` if weather is empty or not a string. |

```lua
-- set up a night race atmosphere
exports['streetkings']:SetTime(22)
exports['streetkings']:SetWeather('CLEAR')
```

### Garage

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `GetActiveVehicle(source)` | server id | `table?` | Get the player's active vehicle data from the save |
| `GetOwnedVehicles(source)` | server id | `table` | Get all vehicles in the player's garage |

```lua
-- check the player's active vehicle
local vehicle = exports['streetkings']:GetActiveVehicle(source)
if vehicle then
    print(vehicle.model, vehicle.data)
end

-- count how many vehicles a player owns
local vehicles = exports['streetkings']:GetOwnedVehicles(source)
local count = 0
for _ in pairs(vehicles) do count = count + 1 end
```

### Hangout Zones

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `IsPlayerInHangoutZone(source)` | server id | `boolean` | Check if a player is currently inside any hangout zone |

```lua
-- give a bonus if the player is hanging out
if exports['streetkings']:IsPlayerInHangoutZone(source) then
    exports['streetkings']:AddPlayerCash(source, 500)
end
```

### Waypoints (Server)

| Export | Params | Returns | Description |
|--------|--------|---------|-------------|
| `CreateServerWaypoint(target, data)` | player id or -1, waypoint data | `integer?` | Create a server-managed waypoint. Returns `nil` if target or data is invalid. |
| `RemoveServerWaypoint(sid)` | server waypoint id | `boolean` | Remove a server waypoint. Returns `false` if sid is not a number. |
| `GetServerWaypoints()` | | `table` | Get all active server waypoints |

```lua
-- create a waypoint visible to all players
local sid = exports['streetkings']:CreateServerWaypoint(-1, {
    coords = vector3(100.0, -500.0, 30.0),
    text   = 'Event Start',
    color  = { r = 255, g = 200, b = 0 },
})

-- remove it when the event ends
exports['streetkings']:RemoveServerWaypoint(sid)
```

---

## Game States

StreetKings uses a state machine to control the player's high-level flow. The built-in states are:

| Constant | Value | Description |
|----------|-------|-------------|
| `GameState.MAIN_MENU` | `'main_menu'` | Title screen / save selection |
| `GameState.AVATAR` | `'avatar'` | Character customization |
| `GameState.INITIATION` | `'initiation'` | New-game intro sequence |
| `GameState.FREEROAM` | `'freeroam'` | Open-world driving |
| `GameState.PROPERTY` | `'property'` | Inside a player property |
| `GameState.GARAGE` | `'garage'` | Vehicle selection garage |
| `GameState.VISUALSHOP` | `'visual_shop'` | Visual mod shop |
| `GameState.PERFORMANCESHOP` | `'performance_shop'` | Performance mod shop |
| `GameState.DEALERSHIP` | `'dealership'` | Vehicle dealership |
| `GameState.EVENT` | `'event'` | Solo event (race, time trial, etc.) |
| `GameState.MULTIPLAYER_LOBBY` | `'multiplayer_lobby'` | Waiting in a multiplayer lobby |
| `GameState.MULTIPLAYER_EVENT` | `'multiplayer_event'` | Active multiplayer race/event |
| `GameState.MISSION` | `'mission'` | Story mission in progress |
| `GameState.TUTORIAL` | `'tutorial'` | Tutorial sequence |

### Custom States

Add-on resources can register their own states using `RegisterGameState`:

```lua
exports['streetkings']:RegisterGameState('my_addon_state', {
    onEnter = function(prevState)
        -- called when transitioning into this state
    end,
    onExit = function(nextState)
        -- called when leaving this state
    end,
    onTick = function()
        -- called every frame while in this state
    end,
    tickWait = 0, -- ms to wait between onTick calls (default 0)
})

-- then transition into it
exports['streetkings']:SetGameState('my_addon_state')
```

---

## Events

Key events that third-party resources can listen to.

### Client Events

| Event | Payload | Description |
|-------|---------|-------------|
| `streetkings:phone:toggle` | none | Fired when the phone toggle is requested |
| `streetkings:shop:freeroamEnter` | none | Player entered freeroam (shop systems) |
| `streetkings:shop:freeroamExit` | none | Player left freeroam |
| `streetkings:garage:freeroamEnter` | none | Garage systems activated |
| `streetkings:event:freeroamEnter` | none | Event markers activated |
| `streetkings:property:freeroamEnter` | none | Property systems activated |
| `streetkings:hangoutzones:freeroamEnter` | none | Hangout zones activated |

### Server Events

| Event | Payload | Description |
|-------|---------|-------------|
| `streetkings:freeroam:enter` | none | Player entered freeroam |
| `streetkings:freeroam:exit` | none | Player left freeroam |
| `streetkings:environment:sync` | `{ h, m, s, weather, prevWeather, transitionPct }` | Time/weather sync broadcast |


## Special Thanks to CFX.re & Rockstar Games
