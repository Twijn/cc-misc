--- AutoCrafter Worker Turtle
--- Turtle component that performs miscellaneous resource generation tasks.
--- Supports cobblestone generation, concrete creation, and other block-breaking tasks.
---
---@version 1.0.0

local VERSION = "1.0.0"

-- Setup package path
local diskPrefix = fs.exists("disk/lib") and "disk/" or ""
if not package.path:find(diskPrefix .. "lib") then
    package.path = package.path .. ";/" .. diskPrefix .. "?.lua;/" .. diskPrefix .. "lib/?.lua"
end

local logger = require("lib.log")
local comms = require("lib.comms")
local config = require("config")

local running = true
local currentTask = nil
local status = "idle"
local lastStatusUpdate = 0
local STATUS_UPDATE_INTERVAL = 30

-- Statistics
local stats = {
    totalProduced = 0,
    sessionProduced = 0,
    lastProduced = 0,
}

-- Progress tracking for current work
local progress = {
    current = 0,
    target = 0,
    startTime = 0,
}

-- Cached peripherals
local cachedModem = nil
local cachedModemName = nil
local cachedTurtleName = nil

-- Task configuration (loaded from server or local)
local assignedTask = nil

-- Forward declaration
local sendStatus

---Direction mappings for turtle operations
local DIRECTIONS = {
    front = {
        dig = turtle.dig,
        detect = turtle.detect,
        inspect = turtle.inspect,
    },
    up = {
        dig = turtle.digUp,
        detect = turtle.detectUp,
        inspect = turtle.inspectUp,
    },
    down = {
        dig = turtle.digDown,
        detect = turtle.detectDown,
        inspect = turtle.inspectDown,
    },
}

---Get cached modem peripheral
---@return table|nil modem
---@return string|nil name
---@return string|nil turtleName
local function getModem()
    if cachedModem then
        return cachedModem, cachedModemName, cachedTurtleName
    end
    
    cachedModem = peripheral.find("modem")
    if cachedModem then
        cachedModemName = peripheral.getName(cachedModem)
        if cachedModem.getNameLocal then
            cachedTurtleName = cachedModem.getNameLocal()
        end
    end
    
    return cachedModem, cachedModemName, cachedTurtleName
end

---Initialize the worker
local function initialize()
    term.clear()
    term.setCursorPos(1, 1)
    
    if config.logLevel then
        logger.setLevel(config.logLevel)
    end
    
    print("AutoCrafter Worker v" .. VERSION)
    print("")
    
    -- Initialize communications
    if not comms.init(false) then
        term.setTextColor(colors.red)
        print("ERROR: No modem found!")
        term.setTextColor(colors.white)
        return false
    end
    comms.setChannel(config.modemChannel)
    
    local modem, modemName, turtleName = getModem()
    if not turtleName then
        term.setTextColor(colors.yellow)
        print("WARN: No network name (wired modem required for transfers)")
        term.setTextColor(colors.white)
    else
        print("Network name: " .. turtleName)
    end
    
    -- Load saved task assignment
    if fs.exists("worker-task.json") then
        local f = fs.open("worker-task.json", "r")
        if f then
            local content = f.readAll()
            f.close()
            local ok, data = pcall(textutils.unserializeJSON, content)
            if ok and data then
                assignedTask = data
                print("Loaded task: " .. (assignedTask.id or "unknown"))
            end
        end
    end
    
    print("")
    logger.info("Worker initialized")
    return true
end

---Save task assignment
local function saveTask()
    if assignedTask then
        local f = fs.open("worker-task.json", "w")
        if f then
            f.write(textutils.serializeJSON(assignedTask))
            f.close()
        end
    end
end

---Request items to deposit into storage
---@param item string Item ID
---@param count number Amount to deposit
---@param slot number Turtle slot
---@return number deposited Amount actually deposited
local function requestDeposit(item, count, slot)
    local _, _, turtleName = getModem()
    if not turtleName then
        return 0
    end
    
    comms.send(config.messageTypes.REQUEST_DEPOSIT, {
        item = item,
        count = count,
        sourceInv = turtleName,
        sourceSlot = slot,
    })
    
    -- Wait for response
    local response = comms.receive(5, config.messageTypes.RESPONSE_DEPOSIT)
    if response and response.data then
        return response.data.deposited or 0
    end
    
    return 0
end

---Deposit all items from inventory to storage
---@return number deposited Total items deposited
local function depositInventory()
    local _, _, turtleName = getModem()
    if not turtleName then
        return 0
    end
    
    local totalDeposited = 0
    
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            local deposited = requestDeposit(detail.name, detail.count, slot)
            totalDeposited = totalDeposited + deposited
            
            -- Check if slot is now empty
            local remaining = turtle.getItemCount(slot)
            if remaining > 0 then
                logger.warn(string.format("Failed to deposit all %s from slot %d (%d remaining)",
                    detail.name, slot, remaining))
            end
        end
    end
    
    return totalDeposited
end

---Check if inventory is full
---@return boolean isFull
local function isInventoryFull()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return false
        end
    end
    return true
end

---Get free inventory slots
---@return number freeSlots
local function getFreeSlots()
    local free = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            free = free + 1
        end
    end
    return free
end

---Execute cobblestone generation task
---@param task table The task configuration
---@param quantity number How many to generate
---@return boolean success
---@return number produced Amount produced
-- How often to deposit items (every N items produced)
local DEPOSIT_INTERVAL = 32

local function executeCobblestoneTask(task, quantity)
    local direction = task.config.breakDirection or "front"
    local dirOps = DIRECTIONS[direction]
    
    if not dirOps then
        return false, 0
    end
    
    local produced = 0
    local lastDeposit = 0
    local lastProgressUpdate = 0
    local PROGRESS_UPDATE_INTERVAL = 5  -- Send progress every 5 items
    
    while produced < quantity and running do
        -- Deposit periodically or when inventory is getting full
        if (produced - lastDeposit) >= DEPOSIT_INTERVAL or getFreeSlots() < 2 then
            local deposited = depositInventory()
            if deposited > 0 then
                lastDeposit = produced
            elseif isInventoryFull() then
                logger.warn("Inventory full and cannot deposit, pausing")
                return true, produced
            end
        end
        
        -- Wait for block to regenerate
        local attempts = 0
        while not dirOps.detect() and attempts < 50 do
            sleep(0.1)
            attempts = attempts + 1
        end
        
        if not dirOps.detect() then
            -- No block appeared, might be misconfigured
            logger.debug("No block detected after waiting, checking...")
            sleep(0.5)
            if not dirOps.detect() then
                logger.warn("Cobblestone generator not working, no block detected")
                return false, produced
            end
        end
        
        -- Dig the block
        local ok, reason = dirOps.dig()
        if ok then
            produced = produced + 1
            progress.current = produced
            
            -- Send progress update periodically
            if produced - lastProgressUpdate >= PROGRESS_UPDATE_INTERVAL then
                sendStatus()
                lastProgressUpdate = produced
            end
        else
            logger.debug("Failed to dig: " .. tostring(reason))
            sleep(0.1)
        end
    end
    
    -- Deposit any remaining items
    depositInventory()
    
    return true, produced
end

---Execute concrete task (break hardened concrete from water source)
---@param task table The task configuration  
---@param quantity number How many to generate
---@return boolean success
---@return number produced Amount produced
local function executeConcreteTask(task, quantity)
    local direction = task.config.breakDirection or "front"
    local dirOps = DIRECTIONS[direction]
    local inputItem = task.config.inputItem
    local outputItem = task.item
    
    if not dirOps or not inputItem then
        return false, 0
    end
    
    local produced = 0
    local lastDeposit = 0
    
    -- For concrete, we need powder in inventory
    -- Request powder from storage
    local _, _, turtleName = getModem()
    if not turtleName then
        return false, 0
    end
    
    while produced < quantity and running do
        -- Deposit periodically to keep inventory clear
        if (produced - lastDeposit) >= DEPOSIT_INTERVAL or getFreeSlots() < 2 then
            depositInventory()
            lastDeposit = produced
        end
        -- Check if we have concrete powder
        local hasPowder = false
        local powderSlot = nil
        
        for slot = 1, 16 do
            local detail = turtle.getItemDetail(slot)
            if detail and detail.name == inputItem then
                hasPowder = true
                powderSlot = slot
                break
            end
        end
        
        if not hasPowder then
            -- Request powder from storage
            comms.send(config.messageTypes.REQUEST_WITHDRAW, {
                item = inputItem,
                count = math.min(quantity - produced, 64),
                destInv = turtleName,
                destSlot = 1,
            })
            
            local response = comms.receive(5, config.messageTypes.RESPONSE_WITHDRAW)
            if not response or not response.data or response.data.withdrawn == 0 then
                logger.info("No more " .. inputItem .. " available")
                depositInventory()
                return true, produced
            end
            
            powderSlot = 1
        end
        
        -- Select powder slot and place
        turtle.select(powderSlot)
        
        -- Place the powder (it will turn to concrete in water)
        local placeOp = direction == "front" and turtle.place or
                       (direction == "up" and turtle.placeUp or turtle.placeDown)
        
        if placeOp() then
            -- Wait briefly for water to harden it
            sleep(0.1)
            
            -- Dig the hardened concrete
            local ok = dirOps.dig()
            if ok then
                produced = produced + 1
            end
        else
            -- Might already have a block there, try to dig it
            local ok, data = dirOps.inspect()
            if ok and data.name == outputItem then
                dirOps.dig()
                produced = produced + 1
            else
                sleep(0.2)
            end
        end
        
    end
    
    depositInventory()
    return true, produced
end

---Execute a custom block breaking task
---@param task table The task configuration
---@param quantity number How many to break
---@return boolean success
---@return number produced Amount produced
local function executeCustomTask(task, quantity)
    -- Same as cobblestone but for any block
    return executeCobblestoneTask(task, quantity)
end

---Execute current task
---@param task table The task to execute
---@param quantity number Target quantity
---@return boolean success
---@return number produced Amount produced
local function executeTask(task, quantity)
    logger.debug(string.format("Executing task %s: %s (qty: %d)", 
        task.id, task.type, quantity))
    
    -- Initialize progress tracking
    progress.current = 0
    progress.target = quantity
    progress.startTime = os.epoch("utc")
    
    status = "working"
    sendStatus()  -- Send initial working status
    
    local success, produced
    
    if task.type == "cobblestone" then
        success, produced = executeCobblestoneTask(task, quantity)
    elseif task.type == "concrete" then
        success, produced = executeConcreteTask(task, quantity)
    elseif task.type == "custom" then
        success, produced = executeCustomTask(task, quantity)
    else
        logger.warn("Unknown task type: " .. task.type)
        return false, 0
    end
    
    stats.lastProduced = produced
    stats.sessionProduced = stats.sessionProduced + produced
    stats.totalProduced = stats.totalProduced + produced
    
    -- Clear progress tracking
    progress.current = 0
    progress.target = 0
    progress.startTime = 0
    
    status = "idle"
    return success, produced
end

---Send status update to server
sendStatus = function()
    comms.broadcast(config.messageTypes.WORKER_STATUS, {
        status = status,
        taskId = assignedTask and assignedTask.id or nil,
        stats = stats,
        progress = status == "working" and progress or nil,
        label = os.getComputerLabel(),
    })
end

---Handle incoming messages
local function messageHandler()
    while running do
        local message = comms.receive(1)
        
        if message then
            if message.type == config.messageTypes.WORKER_PING then
                -- Respond to ping
                comms.send(config.messageTypes.WORKER_PONG, {
                    status = status,
                    taskId = assignedTask and assignedTask.id or nil,
                    stats = stats,
                    progress = status == "working" and progress or nil,
                    label = os.getComputerLabel(),
                }, message.sender)
                
            elseif message.type == config.messageTypes.REBOOT then
                term.setTextColor(colors.yellow)
                print("Received reboot request from server...")
                term.setTextColor(colors.white)
                sleep(0.5)
                os.reboot()
                
            elseif message.type == config.messageTypes.WORK_REQUEST then
                if status == "idle" and message.data.task then
                    currentTask = message.data.task
                    assignedTask = currentTask
                    saveTask()
                    
                    local quantity = message.data.quantity or 64
                    
                    term.setTextColor(colors.lime)
                    print("Received work: " .. currentTask.id)
                    term.setTextColor(colors.white)
                    print("  Type: " .. currentTask.type)
                    print("  Quantity: " .. quantity)
                    
                    local success, produced = executeTask(currentTask, quantity)
                    
                    if success then
                        term.setTextColor(colors.lime)
                        print("  Completed! Produced: " .. produced)
                        term.setTextColor(colors.white)
                        
                        comms.broadcast(config.messageTypes.WORK_COMPLETE, {
                            taskId = currentTask.id,
                            produced = produced,
                            stats = stats,
                        })
                    else
                        term.setTextColor(colors.red)
                        print("  Failed!")
                        term.setTextColor(colors.white)
                        
                        comms.broadcast(config.messageTypes.WORK_FAILED, {
                            taskId = currentTask.id,
                            reason = "Task execution failed",
                            stats = stats,
                        })
                    end
                    
                    currentTask = nil
                    sendStatus()
                    lastStatusUpdate = os.clock()
                    print("")
                end
            end
        end
        
        -- Periodic status update
        local now = os.clock()
        if now - lastStatusUpdate >= STATUS_UPDATE_INTERVAL then
            sendStatus()
            lastStatusUpdate = now
        end
    end
end

---Display status on turtle screen
local function displayLoop()
    while running do
        local x, y = term.getCursorPos()
        local _, h = term.getSize()
        
        term.setCursorPos(1, h)
        term.clearLine()
        
        term.setTextColor(colors.lightGray)
        write("Status: ")
        
        if status == "idle" then
            term.setTextColor(colors.lime)
            write("Idle")
        elseif status == "working" then
            term.setTextColor(colors.orange)
            write("Working")
            if currentTask then
                term.setTextColor(colors.white)
                write(" (" .. currentTask.type .. ")")
            end
        end
        
        term.setTextColor(colors.gray)
        write(" | Produced: " .. stats.sessionProduced)
        
        term.setTextColor(colors.white)
        term.setCursorPos(x, y)
        
        sleep(1)
    end
end

---Handle termination
local function handleTerminate()
    os.pullEventRaw("terminate")
    running = false
    
    logger.info("Worker shutting down")
    
    -- Deposit any remaining items
    depositInventory()
    
    comms.close()
    logger.info("Shutdown complete")
    logger.flush()
end

---Main entry point
local function main()
    if not initialize() then
        return
    end
    
    parallel.waitForAny(
        handleTerminate,
        messageHandler,
        displayLoop
    )
end

-- Run with crash protection
local success, err = pcall(main)
if not success then
    local crashMsg = "Worker crashed: " .. tostring(err)
    logger.critical(crashMsg)
    logger.flush()
    
    term.setTextColor(colors.red)
    print("")
    print("=== WORKER CRASH ===")
    print(crashMsg)
    print("")
    print("Check log/crash.txt for details.")
    print("Press any key to exit...")
    term.setTextColor(colors.white)
    
    os.pullEvent("key")
    error(err)
end
