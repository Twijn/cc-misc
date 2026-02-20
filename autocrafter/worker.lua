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
local STATUS_UPDATE_INTERVAL = 10  -- Reduced from 30 for better monitoring

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

-- Rate limiting for "no more item" messages to prevent log spam
local noMoreItemLogged = {}  -- item -> timestamp of last log
local NO_MORE_ITEM_LOG_INTERVAL = 300  -- Only log once per 5 minutes per item

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
            
            -- Update stats incrementally so monitoring shows real-time progress
            stats.lastProduced = produced
            stats.sessionProduced = stats.sessionProduced + 1
            stats.totalProduced = stats.totalProduced + 1
            
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
                -- Rate-limit this log message to prevent spam
                local now = os.epoch("utc") / 1000
                local lastLogged = noMoreItemLogged[inputItem] or 0
                if now - lastLogged >= NO_MORE_ITEM_LOG_INTERVAL then
                    logger.info("No more " .. inputItem .. " available")
                    noMoreItemLogged[inputItem] = now
                end
                depositInventory()
                return true, produced
            else
                -- Item is available again, clear the rate limit
                noMoreItemLogged[inputItem] = nil
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
                progress.current = produced
                
                -- Update stats incrementally so monitoring shows real-time progress
                stats.lastProduced = produced
                stats.sessionProduced = stats.sessionProduced + 1
                stats.totalProduced = stats.totalProduced + 1
            end
        else
            -- Might already have a block there, try to dig it
            local ok, data = dirOps.inspect()
            if ok and data.name == outputItem then
                dirOps.dig()
                produced = produced + 1
                progress.current = produced
                
                -- Update stats incrementally
                stats.lastProduced = produced
                stats.sessionProduced = stats.sessionProduced + 1
                stats.totalProduced = stats.totalProduced + 1
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

---Crop definitions for farming tasks
---Contains all information needed to plant, grow, and harvest each crop type
local CROP_DEFINITIONS = {
    -- Standard overworld crops (max age 7)
    ["minecraft:wheat"] = {
        seed = "minecraft:wheat_seeds",
        block = "minecraft:wheat",
        drop = "minecraft:wheat",
        maxAge = 7,
        canBonemeal = true,
    },
    ["minecraft:carrot"] = {
        seed = "minecraft:carrot",
        block = "minecraft:carrots",
        drop = "minecraft:carrot",
        maxAge = 7,
        canBonemeal = true,
    },
    ["minecraft:potato"] = {
        seed = "minecraft:potato",
        block = "minecraft:potatoes",
        drop = "minecraft:potato",
        maxAge = 7,
        canBonemeal = true,
    },
    -- Beetroot has max age 3
    ["minecraft:beetroot"] = {
        seed = "minecraft:beetroot_seeds",
        block = "minecraft:beetroots",
        drop = "minecraft:beetroot",
        maxAge = 3,
        canBonemeal = true,
    },
    -- Nether wart (grows on soul sand, cannot be bonemealed)
    ["minecraft:nether_wart"] = {
        seed = "minecraft:nether_wart",
        block = "minecraft:nether_wart",
        drop = "minecraft:nether_wart",
        maxAge = 3,
        canBonemeal = false,
    },
}

---Get crop definition for an item
---@param cropItem string The crop item (drop) to look up
---@return table|nil cropDef The crop definition or nil if not found
local function getCropDefinition(cropItem)
    return CROP_DEFINITIONS[cropItem]
end

---Get crop definition by block name
---@param blockName string The block name to look up
---@return table|nil cropDef The crop definition or nil if not found
local function getCropDefinitionByBlock(blockName)
    for _, def in pairs(CROP_DEFINITIONS) do
        if def.block == blockName then
            return def
        end
    end
    return nil
end

---Execute crop farm task (farm wheat, carrots, potatoes, beetroot, nether wart)
---@param task table The task configuration
---@param quantity number How many crops to harvest
---@return boolean success
---@return number produced Amount produced
local function executeCropFarmTask(task, quantity)
    local direction = task.config.farmDirection or "down"
    local dirOps = DIRECTIONS[direction]
    local cropItem = task.item
    
    if not dirOps then
        logger.warn("Invalid farm direction: " .. direction)
        return false, 0
    end
    
    -- Get crop definition from our table, falling back to task config
    local cropDef = getCropDefinition(cropItem)
    if not cropDef then
        logger.warn("Unknown crop type: " .. cropItem)
        return false, 0
    end
    
    local seedItem = cropDef.seed
    local cropBlock = cropDef.block
    local maxAge = cropDef.maxAge
    local canBonemeal = cropDef.canBonemeal
    
    local _, _, turtleName = getModem()
    if not turtleName then
        logger.warn("No network name available for inventory transfers")
        return false, 0
    end
    
    local produced = 0
    local lastDeposit = 0
    local lastProgressUpdate = 0
    local PROGRESS_UPDATE_INTERVAL = 5
    
    -- Place operation based on direction
    local placeOp = direction == "front" and turtle.place or
                   (direction == "up" and turtle.placeUp or turtle.placeDown)
    
    -- Helper function to find an item in inventory
    local function findItemSlot(itemName)
        for slot = 1, 16 do
            local detail = turtle.getItemDetail(slot)
            if detail and detail.name == itemName then
                return slot
            end
        end
        return nil
    end
    
    -- Helper function to request items from storage
    local function requestItem(itemName, count)
        comms.send(config.messageTypes.REQUEST_WITHDRAW, {
            item = itemName,
            count = count,
            destInv = turtleName,
            destSlot = 1,
        })
        
        local response = comms.receive(5, config.messageTypes.RESPONSE_WITHDRAW)
        if response and response.data then
            return response.data.withdrawn or 0
        end
        return 0
    end
    
    -- Helper to check if a block is our crop and if it's mature
    local function checkCropState(blockData)
        if not blockData then return false, false end
        
        -- Check if this block matches our target crop
        if blockData.name ~= cropBlock then
            -- Check if it's any known crop block (might be wrong crop planted)
            local blockDef = getCropDefinitionByBlock(blockData.name)
            if blockDef then
                -- It's a crop, but not our target - still check maturity for harvesting
                local blockMaxAge = blockDef.maxAge
                local isMature = blockData.state and blockData.state.age == blockMaxAge
                return true, isMature
            end
            return false, false
        end
        
        -- It's our crop - check if mature
        local isMature = blockData.state and blockData.state.age == maxAge
        return true, isMature
    end
    
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
        
        -- Check if there's already a crop planted
        local ok, blockData = dirOps.inspect()
        
        if ok then
            local isCrop, isMature = checkCropState(blockData)
            
            if isCrop and not isMature and canBonemeal then
                -- It's our crop but not mature - apply bonemeal if possible
                local bonemealSlot = findItemSlot("minecraft:bone_meal")
                if not bonemealSlot then
                    -- Request bonemeal from storage
                    local withdrawn = requestItem("minecraft:bone_meal", 64)
                    if withdrawn == 0 then
                        local now = os.epoch("utc") / 1000
                        local lastLogged = noMoreItemLogged["minecraft:bone_meal"] or 0
                        if now - lastLogged >= NO_MORE_ITEM_LOG_INTERVAL then
                            logger.info("No bonemeal available")
                            noMoreItemLogged["minecraft:bone_meal"] = now
                        end
                        depositInventory()
                        return true, produced
                    else
                        noMoreItemLogged["minecraft:bone_meal"] = nil
                    end
                    bonemealSlot = findItemSlot("minecraft:bone_meal")
                end
                
                if bonemealSlot then
                    turtle.select(bonemealSlot)
                    -- Apply bonemeal until crop is mature (up to 10 attempts)
                    for _ = 1, 10 do
                        placeOp()  -- Apply bonemeal
                        sleep(0.05)
                        local checkOk, checkData = dirOps.inspect()
                        if checkOk then
                            _, isMature = checkCropState(checkData)
                            if isMature then
                                break
                            end
                        end
                        if turtle.getItemCount(bonemealSlot) == 0 then
                            bonemealSlot = findItemSlot("minecraft:bone_meal")
                            if bonemealSlot then
                                turtle.select(bonemealSlot)
                            else
                                break
                            end
                        end
                    end
                    -- Re-check maturity after bonemealing
                    local recheckOk, recheckData = dirOps.inspect()
                    if recheckOk then
                        _, isMature = checkCropState(recheckData)
                    end
                end
            elseif isCrop and not isMature and not canBonemeal then
                -- Crop can't be bonemealed (like nether wart) - wait for natural growth
                sleep(0.5)
            end
            
            -- Re-check current state for harvesting
            ok, blockData = dirOps.inspect()
            if ok then
                isCrop, isMature = checkCropState(blockData)
            end
            
            if isCrop and isMature then
                -- Harvest the mature crop
                local digOk = dirOps.dig()
                if digOk then
                    produced = produced + 1
                    progress.current = produced
                    stats.lastProduced = produced
                    stats.sessionProduced = stats.sessionProduced + 1
                    stats.totalProduced = stats.totalProduced + 1
                    
                    if produced - lastProgressUpdate >= PROGRESS_UPDATE_INTERVAL then
                        sendStatus()
                        lastProgressUpdate = produced
                    end
                end
            end
        end
        
        -- Plant a new seed if the block is empty
        ok, blockData = dirOps.inspect()
        if not ok then
            -- No block - plant a seed
            local seedSlot = findItemSlot(seedItem)
            if not seedSlot then
                -- Request seeds from storage
                local withdrawn = requestItem(seedItem, 64)
                if withdrawn == 0 then
                    local now = os.epoch("utc") / 1000
                    local lastLogged = noMoreItemLogged[seedItem] or 0
                    if now - lastLogged >= NO_MORE_ITEM_LOG_INTERVAL then
                        logger.info("No " .. seedItem .. " available")
                        noMoreItemLogged[seedItem] = now
                    end
                    depositInventory()
                    return true, produced
                else
                    noMoreItemLogged[seedItem] = nil
                end
                seedSlot = findItemSlot(seedItem)
            end
            
            if seedSlot then
                turtle.select(seedSlot)
                placeOp()  -- Plant seed
                sleep(0.05)
            end
        end
        
        -- Small delay to prevent tight loop
        sleep(0.05)
    end
    
    -- Deposit any remaining items
    depositInventory()
    
    return true, produced
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
    
    -- Support both old and new task type names
    local taskType = task.type
    local typeAliases = {
        cobblestone = "cobblegen",
        crop_farm = "farming",
        custom = "blockbreak",
    }
    taskType = typeAliases[taskType] or taskType
    
    if taskType == "cobblegen" then
        success, produced = executeCobblestoneTask(task, quantity)
    elseif taskType == "concrete" then
        success, produced = executeConcreteTask(task, quantity)
    elseif taskType == "farming" then
        success, produced = executeCropFarmTask(task, quantity)
    elseif taskType == "blockbreak" then
        success, produced = executeCustomTask(task, quantity)
    else
        logger.warn("Unknown task type: " .. task.type)
        return false, 0
    end
    
    -- Stats are now updated incrementally during task execution
    -- Just ensure lastProduced reflects the final batch count
    stats.lastProduced = produced
    
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
