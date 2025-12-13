--- SignShop Aisle Manager ---
--- Handles communication with aisle turtles via modem.
--- Provides health monitoring for aisle turtles with status tracking.
---
---@version 1.5.0

local s = require("lib.s")
local logger = require("lib.log")
local persist = require("lib.persist")
local errors = require("lib.errors")

-- Check if this is first run or settings are missing
local needsSetup = not settings.get("modem.side")

local modem, broadcastChannel, receiveChannel, pingFrequency

if needsSetup then
    -- Use form-based setup for new installations
    local form = s.useForm("Aisle Manager Setup")
    
    local modemField = form.peripheral("modem.side", "modem", true)
    local broadcastField = form.number("modem.broadcast", 0, 65535, 8698)
    local receiveField = form.number("modem.receive", 0, 65535, 9698)
    local pingField = form.number("aisle.ping-frequency-sec", 1, 30, 3)
    
    if not form.submit() then
        error("Setup cancelled. Aisle manager requires configuration.")
    end
    
    modem = modemField()
    broadcastChannel = broadcastField()
    receiveChannel = receiveField()
    pingFrequency = pingField()
else
    -- Use existing settings
    modem = s.peripheral("modem.side", "modem", true)
    broadcastChannel = s.number("modem.broadcast", 0, 65535, 8698)
    receiveChannel = s.number("modem.receive", 0, 65535, 9698)
    pingFrequency = s.number("aisle.ping-frequency-sec", 1, 30, 3)
end

local manager = {}

local aisles = persist("aisles.json")

-- Health status thresholds (in milliseconds)
local ONLINE_THRESHOLD = 30000      -- 30 seconds
local DEGRADED_THRESHOLD = 120000   -- 2 minutes
local HEALTH_CHECK_INTERVAL = 15    -- 15 seconds

-- Track previous health states for change detection
local previousHealthStates = {}

--- Get the health status of an aisle
---@param name string The aisle name
---@return string status "online", "degraded", "offline", or "unknown"
manager.getAisleHealth = function(name)
    local aisle = aisles.get(name)
    if not aisle then
        return "unknown"
    end
    
    if not aisle.lastSeen then
        return "unknown"
    end
    
    local now = os.epoch("utc")
    local elapsed = now - aisle.lastSeen
    
    if elapsed < ONLINE_THRESHOLD then
        return "online"
    elseif elapsed < DEGRADED_THRESHOLD then
        return "degraded"
    else
        return "offline"
    end
end

--- Get health status for all aisles
---@return table<string, string> Map of aisle names to health status
manager.getAllAisleHealth = function()
    aisles.reload()
    local allAisles = aisles.getAll() or {}
    local health = {}
    
    for name, _ in pairs(allAisles) do
        health[name] = manager.getAisleHealth(name)
    end
    
    return health
end

--- Check all aisles for health changes and fire events
local function checkAisleHealthChanges()
    local allAisles = aisles.getAll() or {}
    
    for name, _ in pairs(allAisles) do
        local currentHealth = manager.getAisleHealth(name)
        local previousHealth = previousHealthStates[name]
        
        if previousHealth and previousHealth ~= currentHealth then
            logger.info(string.format("Aisle %s status changed: %s -> %s", name, previousHealth, currentHealth))
            os.queueEvent("aisle_status_change", name, currentHealth, previousHealth)
        end
        
        previousHealthStates[name] = currentHealth
    end
end

local function listenLoop()
    modem.open(receiveChannel)
    while true do
        local e, side, chnl, rChnl, msg = os.pullEvent("modem_message")
        if type(msg) == "table" and msg.type then
            if msg.type == "pong" and msg.aisle and msg.self then
                msg.lastSeen = os.epoch("utc")
                aisles.set(msg.aisle, msg)
            end
        end
    end
end

local function pingLoop()
    local redstone = true
    while true do
        modem.transmit(broadcastChannel, receiveChannel, {
            type = "ping",
            redstone = redstone,
        })
        redstone = not redstone
        sleep(pingFrequency)
    end
end

--- Health check loop that runs every 15 seconds to detect offline aisles
local function healthCheckLoop()
    -- Initialize previous states
    local allAisles = aisles.getAll() or {}
    for name, _ in pairs(allAisles) do
        previousHealthStates[name] = manager.getAisleHealth(name)
    end
    
    while true do
        sleep(HEALTH_CHECK_INTERVAL)
        checkAisleHealthChanges()
    end
end

manager.getAisles = function()
    aisles.reload()  -- Reload from disk in case server updated
    return aisles.getAll()
end

manager.getAisle = function(name)
    aisles.reload()  -- Reload from disk in case server updated
    local aisle = aisles.get(name)
    if not aisle then
        return nil, errors.create(errors.types.AISLE_NOT_FOUND, 
            string.format("Aisle '%s' not found", name),
            { aisleName = name })
    end
    return aisle
end

manager.updateAisles = function()
    logger.info("Broadcasting update command to all aisles...")
    modem.transmit(broadcastChannel, receiveChannel, {
        type = "update",
    })
end

manager.run = function()
    parallel.waitForAll(listenLoop, pingLoop, healthCheckLoop)
end

for _, turtle in ipairs(table.pack(peripheral.find("turtle"))) do
    if not turtle.isOn() then
        turtle.turnOn()
    end
end

return manager
