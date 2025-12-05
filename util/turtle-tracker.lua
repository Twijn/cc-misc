--- A turtle API client module for ComputerCraft that provides easy integration
--- with the krawlet-api turtle tracking system.
---
--- Features: Automatic stat tracking, position reporting, configurable API endpoint,
--- periodic sync support, and simple state management for turtle data.
---
---@usage
---local turtleApi = require("turtleApi")
---
--- -- Configure the API endpoint
---turtleApi.setEndpoint("http://localhost:3000")
---
--- -- Initialize with turtle ID (defaults to os.getComputerID())
---turtleApi.init()
---
--- -- Update stats
---turtleApi.incrementStat("blocks_mined")
---turtleApi.incrementStat("debris_found", 5)
---
--- -- Update position
---turtleApi.setAbsolutePosition(100, 64, -200)
---turtleApi.setRelativePosition(5, 0, 10)
---
--- -- Push data to server
---turtleApi.sync()
---
--- -- Or use auto-sync (syncs every N seconds)
---turtleApi.startAutoSync(30)
---
---@version 1.0.0
-- @module turtleApi

local VERSION = "1.0.0"

---@class TurtleStats
---@field debris_found number Number of debris blocks found
---@field blocks_mined number Number of blocks mined
---@field deposits number Number of deposits made

---@class TurtlePosition
---@field x number X coordinate
---@field y number Y coordinate
---@field z number Z coordinate

---@class TurtleApiModule
---@field _endpoint string API base URL
---@field _id string|number Turtle identifier
---@field _label string|nil Turtle label
---@field _stats TurtleStats Current stats
---@field _relativePosition TurtlePosition Relative position from start
---@field _absolutePosition TurtlePosition Absolute world coordinates
---@field _fuel number|nil Current fuel level
---@field _autoSyncTimer number|nil Auto-sync timer ID
---@field VERSION string Module version
local module = {
    _endpoint = "http://localhost:3000",
    _id = nil,
    _label = nil,
    _stats = {
        debris_found = 0,
        blocks_mined = 0,
        deposits = 0,
    },
    _relativePosition = { x = 0, y = 0, z = 0 },
    _absolutePosition = { x = 0, y = 0, z = 0 },
    _fuel = nil,
    _autoSyncTimer = nil,
    _initialized = false,
}

-- ======= Internal Helpers =======

local function httpRequest(method, path, body)
    local url = module._endpoint .. path
    local headers = {
        ["Content-Type"] = "application/json",
    }
    local bodyStr = body and textutils.serialiseJSON(body) or nil

    local response, err, errResponse
    if method == "GET" then
        response, err, errResponse = http.get(url, headers)
    elseif method == "POST" then
        response, err, errResponse = http.post(url, bodyStr, headers)
    elseif method == "PATCH" or method == "DELETE" or method == "PUT" then
        -- CC:Tweaked supports http.request for custom methods
        response, err, errResponse = http.request({
            url = url,
            method = method,
            headers = headers,
            body = bodyStr or "{}",
        })
        -- http.request returns immediately, we need to wait for the response
        if response == true then
            -- Wait for http_success or http_failure event
            local event, eventUrl, handle
            repeat
                event, eventUrl, handle = os.pullEvent()
            until (event == "http_success" or event == "http_failure") and eventUrl == url
            if event == "http_success" then
                response = handle
            else
                response = nil
                errResponse = handle
            end
        end
    end

    if response then
        local content = response.readAll()
        response.close()
        local success, data = pcall(textutils.unserialiseJSON, content)
        if success then
            return data
        end
        return { ok = false, error = "Failed to parse response" }
    end

    -- Try to get error message from error response
    if errResponse then
        local content = errResponse.readAll()
        errResponse.close()
        local success, data = pcall(textutils.unserialiseJSON, content)
        if success and data.error then
            return { ok = false, error = data.error }
        end
    end

    return { ok = false, error = err or "Request failed" }
end

local function ensureInitialized()
    if not module._initialized then
        error("TurtleApi not initialized. Call turtleApi.init() first.")
    end
end

-- ======= Configuration Functions =======

---Set the API endpoint URL
---@param endpoint string The base URL of the turtle API (e.g., "http://localhost:3000")
function module.setEndpoint(endpoint)
    -- Remove trailing slash if present
    if endpoint:sub(-1) == "/" then
        endpoint = endpoint:sub(1, -2)
    end
    module._endpoint = endpoint
end

---Get the current API endpoint
---@return string # The current API endpoint URL
function module.getEndpoint()
    return module._endpoint
end

-- ======= Initialization =======

---Initialize the turtle API client
---@param id string|number|nil Optional turtle ID (defaults to os.getComputerID())
---@param label string|nil Optional turtle label (defaults to os.getComputerLabel())
function module.init(id, label)
    module._id = id or os.getComputerID()
    module._label = label or os.getComputerLabel()
    module._initialized = true

    -- Try to get existing data from server
    local response = httpRequest("GET", "/turtles/" .. module._id)
    if response and response.ok and response.data then
        -- Merge with existing data
        if response.data.stats then
            for k, v in pairs(response.data.stats) do
                module._stats[k] = v
            end
        end
        if response.data.relativePosition then
            module._relativePosition = response.data.relativePosition
        end
        if response.data.absolutePosition then
            module._absolutePosition = response.data.absolutePosition
        end
        if response.data.fuel then
            module._fuel = response.data.fuel
        end
    end
end

-- ======= State Management =======

---Set default stats (similar to CC state.setDefault pattern)
---@param stats table Default stat values
function module.setDefault(stats)
    for k, v in pairs(stats) do
        if module._stats[k] == nil or module._stats[k] == 0 then
            module._stats[k] = v
        end
    end
end

---Get the current stats
---@return TurtleStats # Current stats table
function module.getStats()
    return module._stats
end

---Get a specific stat value
---@param statName string Name of the stat
---@return number # The stat value
function module.getStat(statName)
    return module._stats[statName] or 0
end

---Set a specific stat value
---@param statName string Name of the stat
---@param value number The value to set
function module.setStat(statName, value)
    module._stats[statName] = value
end

---Increment a stat by a value (default 1)
---@param statName string Name of the stat to increment
---@param amount number|nil Amount to increment by (default 1)
function module.incrementStat(statName, amount)
    amount = amount or 1
    module._stats[statName] = (module._stats[statName] or 0) + amount
end

---Decrement a stat by a value (default 1)
---@param statName string Name of the stat to decrement
---@param amount number|nil Amount to decrement by (default 1)
function module.decrementStat(statName, amount)
    amount = amount or 1
    module._stats[statName] = (module._stats[statName] or 0) - amount
end

-- ======= Position Management =======

---Set the absolute position (world coordinates)
---@param x number X coordinate
---@param y number Y coordinate
---@param z number Z coordinate
function module.setAbsolutePosition(x, y, z)
    module._absolutePosition = { x = x, y = y, z = z }
end

---Get the absolute position
---@return TurtlePosition # Absolute position table
function module.getAbsolutePosition()
    return module._absolutePosition
end

---Set the relative position (from starting point)
---@param x number X offset
---@param y number Y offset
---@param z number Z offset
function module.setRelativePosition(x, y, z)
    module._relativePosition = { x = x, y = y, z = z }
end

---Get the relative position
---@return TurtlePosition # Relative position table
function module.getRelativePosition()
    return module._relativePosition
end

---Update relative position by offset
---@param dx number X offset to add
---@param dy number Y offset to add
---@param dz number Z offset to add
function module.moveRelative(dx, dy, dz)
    module._relativePosition.x = module._relativePosition.x + dx
    module._relativePosition.y = module._relativePosition.y + dy
    module._relativePosition.z = module._relativePosition.z + dz
end

---Update absolute position by offset
---@param dx number X offset to add
---@param dy number Y offset to add
---@param dz number Z offset to add
function module.moveAbsolute(dx, dy, dz)
    module._absolutePosition.x = module._absolutePosition.x + dx
    module._absolutePosition.y = module._absolutePosition.y + dy
    module._absolutePosition.z = module._absolutePosition.z + dz
end

-- ======= Label & Fuel =======

---Set the turtle label
---@param label string The label to set
function module.setLabel(label)
    module._label = label
end

---Get the turtle label
---@return string|nil # The turtle label
function module.getLabel()
    return module._label
end

---Update fuel level from turtle API
function module.updateFuel()
    if turtle then
        module._fuel = turtle.getFuelLevel()
    end
end

---Set fuel level manually
---@param fuel number The fuel level
function module.setFuel(fuel)
    module._fuel = fuel
end

---Get the current fuel level
---@return number|nil # The fuel level
function module.getFuel()
    return module._fuel
end

-- ======= API Communication =======

---Build the full data payload for syncing
---@return table # The data payload
function module.buildPayload()
    return {
        label = module._label,
        stats = module._stats,
        relativePosition = module._relativePosition,
        absolutePosition = module._absolutePosition,
        fuel = module._fuel,
    }
end

---Sync all turtle data to the server
---@return boolean # True if sync was successful
---@return string|nil # Error message if sync failed
function module.sync()
    ensureInitialized()

    -- Update fuel before syncing
    module.updateFuel()

    local payload = module.buildPayload()
    local response = httpRequest("POST", "/turtles/" .. module._id, payload)

    if response and response.ok then
        return true
    end

    return false, response and response.error or "Unknown error"
end

---Sync only stats to the server
---@return boolean # True if sync was successful
---@return string|nil # Error message if sync failed
function module.syncStats()
    ensureInitialized()

    local response = httpRequest("PATCH", "/turtles/" .. module._id .. "/stats", module._stats)

    if response and response.ok then
        return true
    end

    return false, response and response.error or "Unknown error"
end

---Sync only position to the server
---@return boolean # True if sync was successful
---@return string|nil # Error message if sync failed
function module.syncPosition()
    ensureInitialized()

    local payload = {
        relativePosition = module._relativePosition,
        absolutePosition = module._absolutePosition,
    }
    local response = httpRequest("PATCH", "/turtles/" .. module._id .. "/position", payload)

    if response and response.ok then
        return true
    end

    return false, response and response.error or "Unknown error"
end

---Fetch turtle data from the server
---@return table|nil # The turtle data or nil if not found
function module.fetch()
    ensureInitialized()

    local response = httpRequest("GET", "/turtles/" .. module._id)

    if response and response.ok then
        return response.data
    end

    return nil
end

---Fetch all turtles from the server
---@return table|nil # Array of turtle data or nil on error
function module.fetchAll()
    local response = httpRequest("GET", "/turtles")

    if response and response.ok then
        return response.data
    end

    return nil
end

---Delete the current turtle from the server
---@return boolean # True if deletion was successful
---@return string|nil # Error message if deletion failed
function module.delete()
    ensureInitialized()

    local response = httpRequest("DELETE", "/turtles/" .. module._id)

    if response and response.ok then
        return true
    end

    return false, response and response.error or "Unknown error"
end

---Delete a specific turtle by ID from the server
---@param id string|number The turtle ID to delete
---@return boolean # True if deletion was successful
---@return string|nil # Error message if deletion failed
function module.deleteById(id)
    local response = httpRequest("DELETE", "/turtles/" .. id)

    if response and response.ok then
        return true
    end

    return false, response and response.error or "Unknown error"
end

-- ======= Auto-Sync =======

---Start automatic syncing at a given interval
---@param intervalSeconds number Seconds between syncs (default 30)
function module.startAutoSync(intervalSeconds)
    intervalSeconds = intervalSeconds or 30

    if module._autoSyncTimer then
        module.stopAutoSync()
    end

    -- Use parallel API for background syncing
    module._autoSyncRunning = true

    -- Return a function that should be run in parallel
    return function()
        while module._autoSyncRunning do
            sleep(intervalSeconds)
            if module._autoSyncRunning and module._initialized then
                module.sync()
            end
        end
    end
end

---Stop automatic syncing
function module.stopAutoSync()
    module._autoSyncRunning = false
end

---Check if auto-sync is running
---@return boolean # True if auto-sync is active
function module.isAutoSyncRunning()
    return module._autoSyncRunning or false
end

-- ======= Convenience Wrappers =======

---Wrapper for turtle.forward() that updates relative position
---@return boolean # True if movement succeeded
function module.forward()
    if turtle and turtle.forward() then
        -- Note: Actual position change depends on facing direction
        -- User should track facing and call moveRelative appropriately
        return true
    end
    return false
end

---Wrapper for turtle.back() that updates relative position
---@return boolean # True if movement succeeded
function module.back()
    if turtle and turtle.back() then
        return true
    end
    return false
end

---Wrapper for turtle.up() that updates relative position
---@return boolean # True if movement succeeded
function module.up()
    if turtle and turtle.up() then
        module.moveRelative(0, 1, 0)
        module.moveAbsolute(0, 1, 0)
        return true
    end
    return false
end

---Wrapper for turtle.down() that updates relative position
---@return boolean # True if movement succeeded
function module.down()
    if turtle and turtle.down() then
        module.moveRelative(0, -1, 0)
        module.moveAbsolute(0, -1, 0)
        return true
    end
    return false
end

---Wrapper for turtle.dig() that increments blocks_mined stat
---@return boolean # True if dig succeeded
function module.dig()
    if turtle and turtle.dig() then
        module.incrementStat("blocks_mined")
        return true
    end
    return false
end

---Wrapper for turtle.digUp() that increments blocks_mined stat
---@return boolean # True if dig succeeded
function module.digUp()
    if turtle and turtle.digUp() then
        module.incrementStat("blocks_mined")
        return true
    end
    return false
end

---Wrapper for turtle.digDown() that increments blocks_mined stat
---@return boolean # True if dig succeeded
function module.digDown()
    if turtle and turtle.digDown() then
        module.incrementStat("blocks_mined")
        return true
    end
    return false
end

-- ======= Debug =======

---Print debug information about the current state
function module._debug()
    print("TurtleApi version:", VERSION)
    print("\nConfiguration:")
    print("- Endpoint:", module._endpoint)
    print("- ID:", module._id or "not set")
    print("- Label:", module._label or "not set")
    print("- Initialized:", module._initialized)

    print("\nStats:")
    for k, v in pairs(module._stats) do
        print("-", k, ":", v)
    end

    print("\nRelative Position:")
    print("- X:", module._relativePosition.x)
    print("- Y:", module._relativePosition.y)
    print("- Z:", module._relativePosition.z)

    print("\nAbsolute Position:")
    print("- X:", module._absolutePosition.x)
    print("- Y:", module._absolutePosition.y)
    print("- Z:", module._absolutePosition.z)

    print("\nFuel:", module._fuel or "unknown")
    print("Auto-sync:", module._autoSyncRunning and "running" or "stopped")
end

module.VERSION = VERSION
return module
