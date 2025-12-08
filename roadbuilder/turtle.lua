--- RBC Turtle Program
--- Main turtle program for building roads with wireless control
---
---@version 1.2.0
---@usage
--- wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/roadbuilder/install.lua
--- Then run: turtle
---

local TURTLE_VERSION = "1.2.0"
local TURTLE_UPDATE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main/roadbuilder/turtle.lua"

-- Set up library path
if not package.path:find("lib") then
    package.path = package.path .. ";lib/?.lua;lib/?/init.lua"
end

-- Load libraries
local attach = require("attach")
local log = require("log")
local persist = require("persist")
local gpsLib = require("gps")
local comms = require("comms")
local inventory = require("inventory")

-- Optional updater
local updaterLoaded, updater = pcall(require, "updater")
if not updaterLoaded then
    updater = nil
end

-- Load configuration
local configLoaded, config = pcall(require, "config")
if not configLoaded then
    config = {
        NETWORK = { CHANNEL = 4521, REPLY_CHANNEL = 4522, GPS_TIMEOUT = 2, HEARTBEAT_INTERVAL = 5 },
        ROAD = { DEFAULT_WIDTH = 3, MINE_HEIGHT = 5, DEFAULT_BLOCK = nil },
        ENDER_STORAGE = { ENABLED = true, REFILL_THRESHOLD = 0.25, DEPOSIT_THRESHOLD = 0.75 },
        FUEL = { MINIMUM = 500, TARGET = 2000, ITEMS = {"minecraft:coal", "minecraft:charcoal"} },
        TOOLS = { PICKAXE = "minecraft:diamond_pickaxe" },
    }
end

-- ======= State Management =======
local state = persist("roadbuilder_turtle.json")
state.setDefault("position", {x = 0, y = 0, z = 0})
state.setDefault("facing", 0)
state.setDefault("home", nil)
state.setDefault("roadWidth", config.ROAD.DEFAULT_WIDTH)
state.setDefault("mineHeight", config.ROAD.MINE_HEIGHT)
state.setDefault("roadBlockType", nil)
state.setDefault("stats", {
    blocks_placed = 0,
    blocks_mined = 0,
    roads_built = 0,
})

-- Runtime state
local running = true
local currentTask = nil
local taskProgress = 0
local taskTotal = 0

-- Debug mode (enabled with --debug flag)
local DEBUG = false

local function debugLog(level, msg)
    if level == "info" then
        log.info(msg)
    elseif level == "warn" then
        log.warn(msg)
    elseif level == "error" then
        log.error(msg)
    elseif level == "debug" and DEBUG then
        log.info("[DEBUG] " .. msg)
    end
end

-- ======= Position Management =======
local function syncPositionFromGPS()
    gpsLib.setTimeout(config.NETWORK.GPS_TIMEOUT)
    local x, y, z = gpsLib.locate()
    if x then
        gpsLib.setPosition(x, y, z)
        state.set("position", {x = x, y = y, z = z})
        debugLog("info", string.format("GPS synced: %.0f, %.0f, %.0f", x, y, z))
        return true
    end
    -- Fall back to stored position
    local storedPos = state.get("position")
    gpsLib.setPosition(storedPos.x, storedPos.y, storedPos.z)
    return false
end

local function detectAndSaveFacing()
    local facing = gpsLib.detectFacing()
    if facing then
        state.set("facing", facing)
        debugLog("info", "Facing detected: " .. gpsLib.getFacingName())
        return true
    end
    -- Fall back to stored facing
    gpsLib.setFacing(state.get("facing"))
    return false
end

local function savePosition()
    local pos = gpsLib.getPosition()
    state.set("position", pos)
    state.set("facing", gpsLib.getFacing())
end

-- ======= Movement Functions =======
local function forward()
    if attach.dig() or not turtle.detect() then
        if turtle.forward() then
            gpsLib.updateForward()
            savePosition()
            return true
        end
    end
    return false
end

local function back()
    if turtle.back() then
        gpsLib.updateBack()
        savePosition()
        return true
    end
    return false
end

local function up()
    if attach.digUp() or not turtle.detectUp() then
        if turtle.up() then
            gpsLib.updateUp()
            savePosition()
            return true
        end
    end
    return false
end

local function down()
    if attach.digDown() or not turtle.detectDown() then
        if turtle.down() then
            gpsLib.updateDown()
            savePosition()
            return true
        end
    end
    return false
end

local function turnLeft()
    turtle.turnLeft()
    gpsLib.updateTurnLeft()
    savePosition()
end

local function turnRight()
    turtle.turnRight()
    gpsLib.updateTurnRight()
    savePosition()
end

local function turnAround()
    turnRight()
    turnRight()
end

local function turnToFace(targetFacing)
    local action = gpsLib.getTurnAction(gpsLib.getFacing(), targetFacing)
    if action == "left" then
        turnLeft()
    elseif action == "right" then
        turnRight()
    elseif action == "around" then
        turnAround()
    end
end

-- ======= Road Building Functions =======

--- Check if there are blocks above using the plethora scanner
--- Returns the max height that has blocks, or 0 if no scanner or no blocks
---@param maxHeight number Maximum height to scan
---@return number maxBlockHeight The highest block found (0 if none)
local function scanBlocksAbove(maxHeight)
    local scanner = attach.getScanner()
    if not scanner then
        return maxHeight -- No scanner, assume we need to mine full height
    end
    
    local blocks = scanner.scan()
    if not blocks then
        return maxHeight
    end
    
    local maxBlockY = 0
    for _, block in ipairs(blocks) do
        -- Scanner returns relative coordinates; y > 0 is above the turtle
        if block.y > 0 and block.y <= maxHeight and block.name ~= "minecraft:air" then
            if block.y > maxBlockY then
                maxBlockY = block.y
            end
        end
    end
    
    return maxBlockY
end

--- Mine a column above the current position
---@param height number Height to mine
local function mineColumn(height)
    local startY = gpsLib.getPosition().y
    local mined = 0
    
    -- Use scanner to check if there are blocks above
    local actualHeight = scanBlocksAbove(height)
    if actualHeight == 0 then
        -- No blocks above, skip mining
        return 0
    end
    
    for i = 1, actualHeight do
        if up() then
            mined = mined + 1
        else
            break
        end
    end
    
    -- Return to starting height
    while gpsLib.getPosition().y > startY do
        down()
    end
    
    local stats = state.get("stats")
    stats.blocks_mined = stats.blocks_mined + mined
    state.set("stats", stats)
    
    return mined
end

--- Place road block below turtle
---@return boolean success True if block was placed
local function placeRoadBlock()
    -- Check if there's already a block below
    local hasBlock, blockData = turtle.inspectDown()
    if hasBlock then
        -- Don't replace if it's already the road block type
        local roadType = state.get("roadBlockType") or inventory.getRoadBlockType()
        if blockData.name == roadType then
            return true -- Already correct block
        end
        -- Dig it up
        attach.digDown()
    end
    
    -- Select and place road block
    if inventory.selectRoadBlock() then
        if turtle.placeDown() then
            local stats = state.get("stats")
            stats.blocks_placed = stats.blocks_placed + 1
            state.set("stats", stats)
            return true
        end
    end
    
    return false
end

--- Build one segment of road (place block below, mine above)
---@return boolean success True if segment was built
local function buildRoadSegment()
    -- Place road block below
    local placed = placeRoadBlock()
    
    -- Mine column above
    local mineHeight = state.get("mineHeight")
    mineColumn(mineHeight)
    
    return placed
end

--- Build road for a specified number of blocks
---@param distance number Number of blocks to build
---@param direction string "forward" or "backward"
---@return number built Number of blocks actually built
local function buildRoad(distance, direction)
    direction = direction or "forward"
    local built = 0
    
    currentTask = "Building road"
    taskTotal = distance
    taskProgress = 0
    
    -- Check fuel
    if turtle.getFuelLevel() < config.FUEL.MINIMUM then
        debugLog("warn", "Low fuel! Attempting to refuel...")
        inventory.scan(config.FUEL.ITEMS)
        inventory.refuel(config.FUEL.TARGET, config.FUEL.ITEMS)
    end
    
    for i = 1, distance do
        -- Build current segment
        buildRoadSegment()
        built = built + 1
        taskProgress = i
        
        -- Move to next position
        if i < distance then
            local moved = false
            if direction == "forward" then
                moved = forward()
            else
                moved = back()
            end
            
            if not moved then
                debugLog("warn", "Blocked at segment " .. i)
                break
            end
        end
        
        -- Check inventory
        local invStatus = inventory.getStatus()
        if invStatus.roadBlockCount < 10 then
            debugLog("warn", "Low on road blocks!")
            if config.ENDER_STORAGE.ENABLED and invStatus.hasEnderStorage then
                debugLog("info", "Refilling from ender storage...")
                if inventory.placeEnderStorageUp() then
                    inventory.refillRoadBlocksUp()
                    inventory.pickUpEnderStorageUp()
                    inventory.scan(config.FUEL.ITEMS)
                end
            else
                break
            end
        end
        
        -- Periodic status update
        if i % 10 == 0 then
            comms.sendStatus(getFullStatus())
        end
    end
    
    currentTask = nil
    taskProgress = 0
    taskTotal = 0
    
    local stats = state.get("stats")
    stats.roads_built = stats.roads_built + 1
    state.set("stats", stats)
    
    return built
end

--- Build a wide road (multiple lanes)
---@param distance number Length of road
---@param width number Width of road
---@return number built Total blocks built
local function buildWideRoad(distance, width)
    width = width or state.get("roadWidth")
    local totalBuilt = 0
    local startFacing = gpsLib.getFacing()
    
    currentTask = "Building wide road"
    taskTotal = distance * width
    taskProgress = 0
    
    for lane = 1, width do
        -- Build this lane
        local built = buildRoad(distance, "forward")
        totalBuilt = totalBuilt + built
        taskProgress = (lane - 1) * distance + built
        
        if lane < width then
            -- Move to next lane
            if lane % 2 == 1 then
                turnRight()
                forward()
                turnRight()
            else
                turnLeft()
                forward()
                turnLeft()
            end
        end
    end
    
    -- Return to starting side
    if width % 2 == 0 then
        turnAround()
        for i = 1, width - 1 do
            forward()
        end
        turnToFace(startFacing)
    end
    
    currentTask = nil
    return totalBuilt
end

-- ======= Ender Storage Operations =======

local function depositDebris()
    debugLog("info", "Depositing debris to ender storage...")
    inventory.scan(config.FUEL.ITEMS)
    
    if not inventory.getEnderStorageSlot() then
        debugLog("warn", "No ender storage found!")
        return 0
    end
    
    if inventory.placeEnderStorageUp() then
        local deposited = inventory.depositDebrisUp()
        inventory.pickUpEnderStorageUp()
        debugLog("info", "Deposited " .. deposited .. " items")
        return deposited
    end
    
    return 0
end

local function refillBlocks()
    debugLog("info", "Refilling road blocks from ender storage...")
    inventory.scan(config.FUEL.ITEMS)
    
    if not inventory.getEnderStorageSlot() then
        debugLog("warn", "No ender storage found!")
        return 0
    end
    
    if inventory.placeEnderStorageUp() then
        local refilled = inventory.refillRoadBlocksUp()
        inventory.pickUpEnderStorageUp()
        inventory.scan(config.FUEL.ITEMS)
        debugLog("info", "Refilled " .. refilled .. " blocks")
        return refilled
    end
    
    return 0
end

-- ======= Home Position =======

local function setHome()
    local pos = gpsLib.getPosition()
    local home = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        facing = gpsLib.getFacing(),
    }
    state.set("home", home)
    debugLog("info", "Home set at " .. pos.x .. ", " .. pos.y .. ", " .. pos.z)
    return home
end

local function goHome()
    local home = state.get("home")
    if not home then
        debugLog("warn", "No home position set!")
        return false
    end
    
    local pos = gpsLib.getPosition()
    currentTask = "Going home"
    
    -- Navigate to home Y first
    while pos.y < home.y do
        if not up() then break end
        pos = gpsLib.getPosition()
    end
    while pos.y > home.y do
        if not down() then break end
        pos = gpsLib.getPosition()
    end
    
    -- Navigate to home X
    if pos.x < home.x then
        turnToFace(gpsLib.DIRECTIONS.EAST)
        while pos.x < home.x do
            if not forward() then break end
            pos = gpsLib.getPosition()
        end
    elseif pos.x > home.x then
        turnToFace(gpsLib.DIRECTIONS.WEST)
        while pos.x > home.x do
            if not forward() then break end
            pos = gpsLib.getPosition()
        end
    end
    
    -- Navigate to home Z
    if pos.z < home.z then
        turnToFace(gpsLib.DIRECTIONS.SOUTH)
        while pos.z < home.z do
            if not forward() then break end
            pos = gpsLib.getPosition()
        end
    elseif pos.z > home.z then
        turnToFace(gpsLib.DIRECTIONS.NORTH)
        while pos.z > home.z do
            if not forward() then break end
            pos = gpsLib.getPosition()
        end
    end
    
    -- Face home direction
    turnToFace(home.facing)
    
    currentTask = nil
    debugLog("info", "Arrived at home")
    return true
end

-- ======= Status Reporting =======

function getFullStatus()
    inventory.scan(config.FUEL.ITEMS)
    local invStatus = inventory.getStatus()
    local pos = gpsLib.getPosition()
    
    return {
        id = os.getComputerID(),
        label = os.getComputerLabel() or ("Turtle-" .. os.getComputerID()),
        version = TURTLE_VERSION,
        position = pos,
        facing = gpsLib.getFacing(),
        facingName = gpsLib.getFacingName(),
        hasGPS = gpsLib.hasGPSSignal(),
        fuel = turtle.getFuelLevel(),
        fuelLimit = turtle.getFuelLimit(),
        inventory = invStatus,
        roadWidth = state.get("roadWidth"),
        mineHeight = state.get("mineHeight"),
        roadBlockType = state.get("roadBlockType") or invStatus.roadBlockType,
        home = state.get("home"),
        stats = state.get("stats"),
        currentTask = currentTask,
        taskProgress = taskProgress,
        taskTotal = taskTotal,
    }
end

-- ======= Command Handling =======

local function handleCommand(message, senderId, senderLabel)
    local cmd = message.data.command
    local params = message.data.params or {}
    
    debugLog("info", "Received command: " .. cmd .. " from " .. (senderLabel or senderId))
    comms.sendAck(comms.MSG_TYPE.COMMAND, senderId)
    
    local result = {}
    local success = true
    
    if cmd == comms.COMMANDS.BUILD_FORWARD then
        local distance = params.distance or 10
        local width = params.width or state.get("roadWidth")
        if width > 1 then
            result.built = buildWideRoad(distance, width)
        else
            result.built = buildRoad(distance, "forward")
        end
        
    elseif cmd == comms.COMMANDS.BUILD_BACKWARD then
        local distance = params.distance or 10
        result.built = buildRoad(distance, "backward")
        
    elseif cmd == comms.COMMANDS.MOVE_UP then
        local count = params.count or 1
        result.moved = 0
        for i = 1, count do
            if up() then
                result.moved = result.moved + 1
            else
                break
            end
        end
        
    elseif cmd == comms.COMMANDS.MOVE_DOWN then
        local count = params.count or 1
        result.moved = 0
        for i = 1, count do
            if down() then
                result.moved = result.moved + 1
            else
                break
            end
        end
        
    elseif cmd == comms.COMMANDS.TURN_LEFT then
        turnLeft()
        result.facing = gpsLib.getFacingName()
        
    elseif cmd == comms.COMMANDS.TURN_RIGHT then
        turnRight()
        result.facing = gpsLib.getFacingName()
        
    elseif cmd == comms.COMMANDS.SET_WIDTH then
        local width = params.width or 3
        state.set("roadWidth", width)
        result.width = width
        
    elseif cmd == comms.COMMANDS.SET_BLOCK then
        local blockType = params.blockType
        state.set("roadBlockType", blockType)
        inventory.setRoadBlockType(blockType)
        result.blockType = blockType
        
    elseif cmd == comms.COMMANDS.REFILL then
        result.refilled = refillBlocks()
        
    elseif cmd == comms.COMMANDS.DEPOSIT then
        result.deposited = depositDebris()
        
    elseif cmd == comms.COMMANDS.GO_HOME then
        success = goHome()
        
    elseif cmd == comms.COMMANDS.SET_HOME then
        result.home = setHome()
        
    elseif cmd == comms.COMMANDS.UPDATE then
        -- Update command - run update script headlessly and restart
        debugLog("info", "Update command received, downloading update...")
        comms.sendComplete(cmd, {status = "updating"}, senderId)
        comms.close()
        
        -- Run update script
        local updateUrl = "https://raw.githubusercontent.com/Twijn/cc-misc/main/roadbuilder/update.lua"
        shell.run("wget", "run", updateUrl)
        
        -- Restart the turtle
        os.reboot()
        return -- Won't reach here due to reboot
        
    else
        debugLog("warn", "Unknown command: " .. cmd)
        success = false
        result.error = "Unknown command"
    end
    
    -- Send completion
    comms.sendComplete(cmd, result, senderId)
    comms.sendStatus(getFullStatus())
end

local function handlePing(message, senderId, senderLabel)
    debugLog("info", "Received PING from controller #" .. senderId .. " (" .. (senderLabel or "unnamed") .. ")")
    debugLog("info", "Sending PONG and status...")
    comms.pong(senderId)
    comms.sendStatus(getFullStatus())
    debugLog("info", "Response sent!")
end

local function handleStop(message, senderId, senderLabel)
    debugLog("info", "Stop command received from " .. (senderLabel or senderId))
    running = false
    comms.sendAck(comms.MSG_TYPE.STOP, senderId)
end

local function handleConfig(message, senderId, senderLabel)
    local newConfig = message.data
    
    if newConfig.roadWidth then
        state.set("roadWidth", newConfig.roadWidth)
    end
    if newConfig.mineHeight then
        state.set("mineHeight", newConfig.mineHeight)
    end
    if newConfig.roadBlockType then
        state.set("roadBlockType", newConfig.roadBlockType)
        inventory.setRoadBlockType(newConfig.roadBlockType)
    end
    
    comms.sendAck(comms.MSG_TYPE.CONFIG, senderId)
    comms.sendStatus(getFullStatus())
end

-- ======= Main Loop =======

local function heartbeatLoop()
    while running do
        comms.sendStatus(getFullStatus())
        sleep(config.NETWORK.HEARTBEAT_INTERVAL)
    end
end

local function messageLoop()
    while running do
        local message = comms.receive(1)
        -- Messages are handled by registered handlers
    end
end

local function main(args)
    term.clear()
    term.setCursorPos(1, 1)
    
    print("================================")
    print("  RBC Turtle v" .. TURTLE_VERSION)
    print("================================")
    print("")
    
    -- Check for debug flag
    args = args or {}
    if args[1] == "--debug" or args[1] == "-d" then
        DEBUG = true
        comms.DEBUG = true
        print("Debug mode enabled")
    end
    
    -- Check for updates
    if updater and config.UPDATER and config.UPDATER.CHECK_ON_STARTUP then
        debugLog("info", "Checking for updates...")
        -- Update check would go here
    end
    
    -- Initialize communications
    debugLog("info", "Initializing wireless modem...")
    if not comms.init(config.NETWORK) then
        debugLog("error", "Failed to find wireless modem!")
        print("Please equip a wireless modem.")
        return
    end
    debugLog("info", "Wireless modem ready on channel " .. config.NETWORK.CHANNEL)
    debugLog("info", "Turtle ID: " .. os.getComputerID())
    
    -- Register message handlers
    comms.onMessage(comms.MSG_TYPE.PING, handlePing)
    comms.onMessage(comms.MSG_TYPE.COMMAND, handleCommand)
    comms.onMessage(comms.MSG_TYPE.STOP, handleStop)
    comms.onMessage(comms.MSG_TYPE.CONFIG, handleConfig)
    
    -- Set up tools
    attach.setDefaultEquipped(config.TOOLS.PICKAXE)
    
    -- Initialize GPS
    debugLog("info", "Acquiring GPS position...")
    if syncPositionFromGPS() then
        debugLog("info", "GPS acquired, detecting facing...")
        detectAndSaveFacing()
    else
        debugLog("warn", "No GPS signal, using stored position")
    end
    
    -- Scan inventory
    debugLog("info", "Scanning inventory...")
    local invSummary = inventory.scan(config.FUEL.ITEMS)
    if invSummary.roadBlockType then
        debugLog("info", "Road block type: " .. invSummary.roadBlockType)
        if not state.get("roadBlockType") then
            state.set("roadBlockType", invSummary.roadBlockType)
        end
    else
        debugLog("warn", "No road blocks found in inventory!")
    end
    
    debugLog("info", "Road blocks: " .. invSummary.roadBlockCount)
    debugLog("info", "Fuel level: " .. turtle.getFuelLevel())
    
    print("")
    print("Turtle ready! Waiting for commands...")
    print("Press Q to quit")
    print("")
    
    -- Send initial status
    comms.sendStatus(getFullStatus())
    
    -- Main loop with parallel tasks
    parallel.waitForAny(
        heartbeatLoop,
        messageLoop,
        function()
            while running do
                local event, key = os.pullEvent("key")
                if key == keys.q then
                    running = false
                    debugLog("info", "Shutting down...")
                end
            end
        end
    )
    
    comms.close()
    debugLog("info", "RBC turtle stopped")
end

main({...})
