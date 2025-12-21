--- AutoCrafter Crafter Turtle
--- Turtle component that executes crafting jobs from the server.
--- All inventory operations are requested from the server to minimize peripheral calls.
---
---@version 2.1.0

local VERSION = "2.1.0"

-- Setup package path
local diskPrefix = fs.exists("disk/lib") and "disk/" or ""
if not package.path:find(diskPrefix .. "lib") then
    package.path = package.path .. ";" .. diskPrefix .. "?.lua;" .. diskPrefix .. "lib/?.lua"
end

local logger = require("lib.log")
local comms = require("lib.comms")
local config = require("config")

local running = true
local currentJob = nil
local status = "idle"

-- Cached peripherals (avoid repeated peripheral calls)
local cachedModem = nil
local cachedModemName = nil
local cachedTurtleName = nil  -- The turtle's name on the network (from getNameLocal)

-- Crafting slot mapping: 3x3 grid to turtle inventory
-- Turtle slots: 1-16
-- Crafting uses slots 1,2,3 for top row, 5,6,7 for middle, 9,10,11 for bottom
local CRAFT_SLOTS = {
    [1] = 1,  [2] = 2,  [3] = 3,
    [4] = 5,  [5] = 6,  [6] = 7,
    [7] = 9,  [8] = 10, [9] = 11,
}

-- Storage slots (not used for crafting)
local STORAGE_SLOTS = {4, 8, 12, 13, 14, 15, 16}

---Get the output slot
local OUTPUT_SLOT = 16

---Get cached modem peripheral
---@return table|nil modem The modem peripheral
---@return string|nil name The modem name
---@return string|nil turtleName The turtle's name on the network
local function getModem()
    if cachedModem then
        return cachedModem, cachedModemName, cachedTurtleName
    end
    
    cachedModem = peripheral.find("modem")
    if cachedModem then
        cachedModemName = peripheral.getName(cachedModem)
        -- Get the turtle's network name for item transfers
        if cachedModem.getNameLocal then
            cachedTurtleName = cachedModem.getNameLocal()
        end
    end
    
    return cachedModem, cachedModemName, cachedTurtleName
end

---Initialize the crafter
local function initialize()
    term.clear()
    term.setCursorPos(1, 1)
    
    print("================================")
    print("  AutoCrafter Crafter v" .. VERSION)
    print("================================")
    print("")
    
    -- Check for crafty turtle
    if not turtle.craft then
        term.setTextColor(colors.red)
        print("ERROR: This turtle needs a crafting table!")
        print("Use a Crafty Turtle or equip a crafting table.")
        term.setTextColor(colors.white)
        return false
    end
    print("Crafting table: OK")
    
    -- Initialize communications
    print("Initializing modem...")
    if comms.init(false) then -- Prefer wired for turtles
        comms.setChannel(config.modemChannel)
        local modemInfo = comms.getModemInfo()
        print("  Modem: " .. (modemInfo.isWireless and "Wireless" or "Wired"))
        print("  Channel: " .. modemInfo.channel)
    else
        term.setTextColor(colors.red)
        print("ERROR: No modem found!")
        term.setTextColor(colors.white)
        return false
    end
    print("")
    
    -- Cache modem and validate network name
    local modem, modemName, turtleName = getModem()
    if not turtleName then
        term.setTextColor(colors.yellow)
        print("WARNING: Cannot get turtle network name!")
        print("  This turtle may not be visible on the wired network.")
        print("  Ensure the modem is connected to a wired network.")
        print("  Wireless modems do not support item transfers.")
        term.setTextColor(colors.white)
        logger.warn("getNameLocal() returned nil - turtle may not be on wired network")
    else
        print("Network name: " .. turtleName)
    end
    
    -- Set label if not set
    if not os.getComputerLabel() then
        os.setComputerLabel("Crafter-" .. os.getComputerID())
    end
    
    print("ID: " .. os.getComputerID())
    print("Label: " .. os.getComputerLabel())
    print("")
    print("Waiting for crafting jobs...")
    print("")
    
    logger.info("AutoCrafter Crafter started")
    return true
end

---Request server to push items to us
---@param item string Item ID
---@param count number Amount needed
---@param destInv string Our inventory name (modem name)
---@param destSlot? number Optional destination slot
---@return number withdrawn Amount actually received
local function requestWithdraw(item, count, destInv, destSlot)
    local attempts = 0
    local maxAttempts = 5
    
    while attempts < maxAttempts do
        -- Send request each attempt
        comms.broadcast(config.messageTypes.REQUEST_WITHDRAW, {
            item = item,
            count = count,
            destInv = destInv,
            destSlot = destSlot,
        })
        
        -- Wait for response - use shorter timeout per attempt
        local attemptTimeout = os.clock() + 2
        while os.clock() < attemptTimeout do
            local message = comms.receive(0.5)
            if message then
                if message.type == config.messageTypes.RESPONSE_WITHDRAW then
                    return message.data.withdrawn or 0
                end
                -- Got a different message, keep waiting
            end
        end
        
        -- Timeout on this attempt, retry with new request
        attempts = attempts + 1
        if attempts < maxAttempts then
            logger.debug(string.format("requestWithdraw: no response, retrying (%d/%d)", attempts, maxAttempts))
        end
    end
    
    logger.warn("requestWithdraw: no response from server after timeout")
    return 0
end

---Request server to accept items from us
---@param sourceInv string Our inventory name (modem name)
---@param item? string Optional item filter
---@return number deposited Amount deposited
local function requestDeposit(sourceInv, item)
    logger.debug(string.format("requestDeposit: sourceInv=%s, item=%s", sourceInv, tostring(item)))
    
    local attempts = 0
    local maxAttempts = 5
    
    while attempts < maxAttempts do
        -- Send request each attempt
        comms.broadcast(config.messageTypes.REQUEST_DEPOSIT, {
            sourceInv = sourceInv,
            item = item,
        })
        
        -- Wait for response - use shorter timeout per attempt
        local attemptTimeout = os.clock() + 3
        while os.clock() < attemptTimeout do
            local message = comms.receive(1)
            if message then
                if message.type == config.messageTypes.RESPONSE_DEPOSIT then
                    logger.debug(string.format("requestDeposit: received response, deposited=%d", message.data.deposited or 0))
                    return message.data.deposited or 0
                else
                    -- Got a different message, keep waiting
                    logger.debug(string.format("requestDeposit: received unexpected message type: %s", message.type))
                end
            end
        end
        
        -- Timeout on this attempt, retry with new request
        attempts = attempts + 1
        if attempts < maxAttempts then
            logger.debug(string.format("requestDeposit: no response, retrying (%d/%d)", attempts, maxAttempts))
        end
    end
    
    logger.warn("requestDeposit: no response from server after timeout")
    return 0
end

---Request server to clear specific slots from turtle inventory
---@param sourceInv string Our inventory name (modem name)
---@param slots table Array of slot numbers to clear
---@return number cleared Amount of items cleared
local function requestClearSlots(sourceInv, slots)
    logger.debug(string.format("requestClearSlots: sourceInv=%s, slots=%s", sourceInv, textutils.serialize(slots)))
    
    local attempts = 0
    local maxAttempts = 3
    
    while attempts < maxAttempts do
        -- Send request each attempt
        comms.broadcast(config.messageTypes.REQUEST_CLEAR_SLOTS, {
            sourceInv = sourceInv,
            slots = slots,
        })
        
        -- Wait for response - use shorter timeout per attempt
        local attemptTimeout = os.clock() + 2
        while os.clock() < attemptTimeout do
            local message = comms.receive(0.5)
            if message then
                if message.type == config.messageTypes.RESPONSE_CLEAR_SLOTS then
                    logger.debug(string.format("requestClearSlots: received response, cleared=%d", message.data.cleared or 0))
                    return message.data.cleared or 0
                else
                    logger.debug(string.format("requestClearSlots: received unexpected message type: %s", message.type))
                end
            end
        end
        
        -- Timeout on this attempt, retry with new request
        attempts = attempts + 1
        if attempts < maxAttempts then
            logger.debug(string.format("requestClearSlots: no response, retrying (%d/%d)", attempts, maxAttempts))
        end
    end
    
    logger.warn("requestClearSlots: no response from server after timeout")
    return 0
end

---Check if the turtle inventory is empty
---@return boolean isEmpty Whether all slots are empty
local function isInventoryEmpty()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            return false
        end
    end
    return true
end

---Log detailed inventory state for debugging
---@return table slotDetails Array of {slot, count, name} for non-empty slots
local function logInventoryState()
    local slotDetails = {}
    for slot = 1, 16 do
        local count = turtle.getItemCount(slot)
        if count > 0 then
            local detail = turtle.getItemDetail(slot)
            local itemName = detail and detail.name or "unknown"
            table.insert(slotDetails, {
                slot = slot,
                count = count,
                name = itemName,
            })
            logger.debug(string.format("  Slot %d: %dx %s", slot, count, itemName))
        end
    end
    return slotDetails
end

---Clear the turtle inventory to storage (via server request)
---Ensures inventory is completely empty before returning (required for turtle.craft())
---@param maxRetries? number Maximum retry attempts (default 5)
---@return boolean success Whether inventory was fully cleared
local function clearInventory(maxRetries)
    maxRetries = maxRetries or 5
    local _, _, turtleName = getModem()
    if not turtleName then 
        logger.error("No modem found for clearInventory - cannot communicate with server")
        logger.error("Check that modem is attached and wired network is connected")
        return isInventoryEmpty()
    end
    
    logger.debug("clearInventory called, turtle name: " .. turtleName)
    
    -- Check if turtle has any items
    if isInventoryEmpty() then 
        turtle.select(1)
        return true 
    end
    
    -- Log what we're trying to clear
    logger.info("Attempting to clear inventory:")
    local initialItems = logInventoryState()
    
    -- Try to deposit all items with retries
    for attempt = 1, maxRetries do
        logger.debug(string.format("Clear attempt %d/%d", attempt, maxRetries))
        
        -- Request server to deposit all items from the turtle
        local deposited = requestDeposit(turtleName, nil)
        logger.debug(string.format("requestDeposit returned: %d items deposited", deposited))
        
        -- Small delay to allow items to transfer
        sleep(0.1)
        
        -- Verify inventory is actually empty
        if isInventoryEmpty() then
            logger.info("Inventory successfully cleared")
            turtle.select(1)
            return true
        end
        
        -- Still have items - log what remains
        logger.warn(string.format("Inventory not empty after deposit (attempt %d/%d)", attempt, maxRetries))
        local remainingItems = logInventoryState()
        
        -- Try clearing specific slots
        local slotsWithItems = {}
        for _, item in ipairs(remainingItems) do
            table.insert(slotsWithItems, item.slot)
        end
        
        if #slotsWithItems > 0 then
            logger.debug(string.format("Requesting server to clear slots: %s", textutils.serialize(slotsWithItems)))
            local cleared = requestClearSlots(turtleName, slotsWithItems)
            logger.debug(string.format("requestClearSlots returned: %d items cleared", cleared))
            sleep(0.1)
        end
        
        -- Check again
        if isInventoryEmpty() then
            logger.info("Inventory successfully cleared after slot-specific request")
            turtle.select(1)
            return true
        end
        
        -- Still have items, wait and retry
        if attempt < maxRetries then
            logger.debug("Items still remain, waiting before retry...")
            sleep(0.2)
        end
    end
    
    -- Failed to clear inventory - log detailed diagnostic info
    logger.error("=== INVENTORY CLEAR FAILED - DIAGNOSTIC INFO ===")
    logger.error(string.format("Turtle name on network: %s", turtleName))
    logger.error(string.format("Attempted %d times to clear inventory", maxRetries))
    logger.error("Remaining items in inventory:")
    local finalItems = logInventoryState()
    
    for _, item in ipairs(finalItems) do
        logger.error(string.format("  STUCK: Slot %d has %dx %s", item.slot, item.count, item.name))
    end
    
    logger.error("Possible causes:")
    logger.error("  1. Server not responding to deposit/clear requests")
    logger.error("  2. Storage system is full")
    logger.error("  3. No valid storage destination for these items")
    logger.error("  4. Network communication issues")
    logger.error("  5. Server doesn't have peripheral access to this turtle")
    logger.error("=================================================")
    
    turtle.select(1)
    return false
end

---Calculate how many items are needed per slot in the crafting grid
---@param recipe table The recipe
---@return table grid Grid slot -> item mapping
---@return table counts Grid slot -> count per craft mapping
local function buildCraftingGrid(recipe)
    local grid = {}
    local counts = {}
    for i = 1, 9 do 
        grid[i] = nil 
        counts[i] = 0
    end
    
    if recipe.type == "shaped" then
        local pattern = recipe.pattern
        local key = recipe.key
        
        for row = 1, #pattern do
            local line = pattern[row]
            for col = 1, #line do
                local char = line:sub(col, col)
                local gridSlot = (row - 1) * 3 + col
                if char ~= " " and key[char] then
                    grid[gridSlot] = key[char]
                    counts[gridSlot] = 1
                end
            end
        end
    else -- shapeless
        local slot = 1
        for _, ingredient in ipairs(recipe.ingredients) do
            for _ = 1, ingredient.count do
                grid[slot] = ingredient.item
                counts[slot] = 1
                slot = slot + 1
            end
        end
    end
    
    return grid, counts
end

---Calculate maximum batch size based on stack limits
---@param craftsNeeded number Total crafts needed
---@return number batchSize Maximum crafts per batch (limited by stack size 64)
local function calculateBatchSize(craftsNeeded)
    -- Each slot can hold max 64 items, so max batch is 64 crafts
    -- But we also need room for output, so be conservative
    local maxPerSlot = 64
    return math.min(craftsNeeded, maxPerSlot)
end

---Pull items for a batch craft with retry logic
---@param item string Item ID
---@param count number Amount to pull
---@param turtleSlot number Destination slot
---@param maxRetries? number Max retry attempts (default 3)
---@return number pulled Amount actually pulled
local function pullItemWithRetry(item, count, turtleSlot, maxRetries)
    maxRetries = maxRetries or 3
    local _, _, turtleName = getModem()
    if not turtleName then
        logger.warn("No modem found for pullItemWithRetry")
        return 0
    end
    
    turtle.select(turtleSlot)
    local totalPulled = 0
    local attempts = 0
    
    while totalPulled < count and attempts < maxRetries do
        attempts = attempts + 1
        local remaining = count - totalPulled
        
        -- Request items from server directly to turtle slot
        local withdrawn = requestWithdraw(item, remaining, turtleName, turtleSlot)
        
        -- Verify the item actually arrived
        local actualCount = turtle.getItemCount(turtleSlot)
        
        if actualCount > totalPulled then
            totalPulled = actualCount
        elseif withdrawn > 0 and actualCount == totalPulled then
            -- Server says it sent items but we didn't receive them, wait and retry
            sleep(0.2)
        end
        
        if totalPulled >= count then
            break
        end
        
        -- Small delay before retry
        if attempts < maxRetries and totalPulled < count then
            sleep(0.1)
        end
    end
    
    if totalPulled < count then
        logger.warn(string.format("Wanted %d %s, only got %d after %d attempts", 
            count, item, totalPulled, attempts))
    end
    
    return totalPulled
end

---Execute a crafting job with batch crafting
---@param job table The crafting job
---@return boolean success Whether crafting succeeded
---@return number|string result Output count or error message
local function executeCraft(job)
    local recipe = job.recipe
    if not recipe then
        return false, "No recipe in job"
    end
    
    -- Clear inventory first - MUST succeed or crafting will fail
    if not clearInventory() then
        return false, "Failed to clear inventory before crafting"
    end
    
    -- Build crafting grid
    local grid, slotCounts = buildCraftingGrid(recipe)
    
    -- Calculate total crafts needed
    local totalCraftsNeeded = job.crafts or 1
    local totalCraftsCompleted = 0
    local outputCount = recipe.outputCount or 1
    
    logger.info(string.format("Starting job: %d crafts of %s (output: %dx per craft)", 
        totalCraftsNeeded, recipe.output, outputCount))
    
    -- Process in batches
    while totalCraftsCompleted < totalCraftsNeeded do
        local remainingCrafts = totalCraftsNeeded - totalCraftsCompleted
        local batchSize = calculateBatchSize(remainingCrafts)
        
        -- Clear inventory before each batch (first batch already cleared above)
        if totalCraftsCompleted > 0 then
            if not clearInventory() then
                -- Partial success - return what we completed
                local totalOutput = totalCraftsCompleted * outputCount
                logger.warn(string.format("Failed to clear inventory for next batch, returning partial: %d items", totalOutput))
                return true, totalOutput
            end
        end
        
        -- Gather materials for this batch
        local materialsOk = true
        local failedItem = nil
        local shortAmount = 0
        
        for gridSlot = 1, 9 do
            local item = grid[gridSlot]
            if item then
                local turtleSlot = CRAFT_SLOTS[gridSlot]
                local neededCount = slotCounts[gridSlot] * batchSize
                
                local pulled = pullItemWithRetry(item, neededCount, turtleSlot, 3)
                
                if pulled == 0 then
                    materialsOk = false
                    failedItem = item
                    shortAmount = neededCount
                    logger.warn(string.format("Failed to get any %s for grid slot %d (needed %d)", 
                        item, gridSlot, neededCount))
                    break
                elseif pulled < neededCount then
                    -- We got some but not all - adjust batch size
                    local possibleCrafts = math.floor(pulled / slotCounts[gridSlot])
                    if possibleCrafts > 0 and possibleCrafts < batchSize then
                        -- Reduce batch size to what we can actually craft
                        logger.info(string.format("Reducing batch from %d to %d (only got %d/%d %s)", 
                            batchSize, possibleCrafts, pulled, neededCount, item))
                        batchSize = possibleCrafts
                        -- Return excess items for this slot
                        local excess = pulled - (possibleCrafts * slotCounts[gridSlot])
                        if excess > 0 then
                            -- We can't easily return partial items, so we'll use what we have
                            -- The extra will be returned after crafting
                        end
                    elseif possibleCrafts == 0 then
                        materialsOk = false
                        failedItem = item
                        shortAmount = neededCount - pulled
                        logger.warn(string.format("Not enough %s: got %d, needed at least %d", 
                            item, pulled, slotCounts[gridSlot]))
                        break
                    end
                end
            end
        end
        
        if not materialsOk then
            -- Return items to storage
            clearInventory()
            if totalCraftsCompleted > 0 then
                local totalOutput = totalCraftsCompleted * outputCount
                logger.info(string.format("Partial completion: %d/%d crafts, %d items", 
                    totalCraftsCompleted, totalCraftsNeeded, totalOutput))
                return true, totalOutput
            else
                return false, string.format("Missing materials: %s (short %d)", failedItem or "unknown", shortAmount)
            end
        end
        
        -- Select output slot and craft
        turtle.select(OUTPUT_SLOT)
        local craftSuccess = turtle.craft(batchSize)
        
        if craftSuccess then
            totalCraftsCompleted = totalCraftsCompleted + batchSize
            local batchOutput = batchSize * outputCount
            
            logger.info(string.format("Batch complete: crafted %d (total: %d/%d crafts)", 
                batchOutput, totalCraftsCompleted, totalCraftsNeeded))
            
            -- Collect all slots that have items to clear (including output)
            local slotsToClean = {}
            for slot = 1, 16 do
                if turtle.getItemCount(slot) > 0 then
                    table.insert(slotsToClean, slot)
                end
            end
            
            -- Request server to pull items from these slots
            if #slotsToClean > 0 then
                local _, _, turtleName = getModem()
                if turtleName then
                    local cleared = requestClearSlots(turtleName, slotsToClean)
                    if cleared == 0 then
                        -- Retry once if clearing failed
                        sleep(0.2)
                        requestClearSlots(turtleName, slotsToClean)
                    end
                end
            end
        else
            -- Crafting failed - try to salvage what we can
            clearInventory()
            if totalCraftsCompleted > 0 then
                local totalOutput = totalCraftsCompleted * outputCount
                logger.warn(string.format("Crafting failed mid-batch, completed %d crafts", totalCraftsCompleted))
                return true, totalOutput
            else
                return false, "Crafting failed - recipe may require exact positioning"
            end
        end
    end
    
    -- Clear any remaining items
    clearInventory()
    
    local totalOutput = totalCraftsCompleted * outputCount
    logger.info(string.format("Job complete: %d crafts, %d items output", totalCraftsCompleted, totalOutput))
    
    return true, totalOutput
end

---Send status update to server
local function sendStatus()
    comms.broadcast(config.messageTypes.STATUS, {
        status = status,
        currentJob = currentJob and currentJob.id or nil,
        label = os.getComputerLabel(),
    })
end

---Handle incoming messages
local function messageHandler()
    while running do
        local message = comms.receive(1)  -- Reduced timeout for faster response
        
        if message then
            if message.type == config.messageTypes.PING then
                -- Respond to ping
                comms.send(config.messageTypes.PONG, {
                    status = status,
                    currentJob = currentJob and currentJob.id or nil,
                    label = os.getComputerLabel(),
                }, message.sender)
                
            elseif message.type == config.messageTypes.CRAFT_REQUEST then
                -- Received craft request
                if status == "idle" and message.data.job then
                    currentJob = message.data.job
                    status = "crafting"
                    
                    term.setTextColor(colors.lime)
                    print("Received job #" .. currentJob.id)
                    term.setTextColor(colors.white)
                    print("  Crafting: " .. (currentJob.recipe.output or "unknown"))
                    print("  Quantity: " .. (currentJob.expectedOutput or 0))
                    
                    -- Execute the craft
                    local success, result = executeCraft(currentJob)
                    
                    if success then
                        term.setTextColor(colors.lime)
                        print("  Completed! Output: " .. result)
                        term.setTextColor(colors.white)
                        
                        comms.broadcast(config.messageTypes.CRAFT_COMPLETE, {
                            jobId = currentJob.id,
                            actualOutput = result,
                        })
                    else
                        term.setTextColor(colors.red)
                        print("  Failed: " .. tostring(result))
                        term.setTextColor(colors.white)
                        
                        comms.broadcast(config.messageTypes.CRAFT_FAILED, {
                            jobId = currentJob.id,
                            reason = tostring(result),
                        })
                    end
                    
                    currentJob = nil
                    status = "idle"
                    -- Immediately notify server we're idle and ready for next job
                    sendStatus()
                    print("")
                end
            end
        end
        
        -- Periodic status update
        sendStatus()
    end
end

---Display status on turtle screen
local function displayLoop()
    while running do
        local x, y = term.getCursorPos()
        
        -- Move to bottom of screen for status
        local _, h = term.getSize()
        term.setCursorPos(1, h)
        term.clearLine()
        
        term.setTextColor(colors.lightGray)
        write("Status: ")
        
        if status == "idle" then
            term.setTextColor(colors.lime)
            write("Idle")
        elseif status == "crafting" then
            term.setTextColor(colors.orange)
            write("Crafting")
            if currentJob then
                term.setTextColor(colors.white)
                write(" #" .. currentJob.id)
            end
        end
        
        term.setTextColor(colors.white)
        term.setCursorPos(x, y)
        
        sleep(1)
    end
end

---Handle termination
local function handleTerminate()
    os.pullEventRaw("terminate")
    running = false
    
    logger.info("Crafter shutting down")
    
    -- Clear inventory before shutdown
    clearInventory()
    
    comms.close()
    logger.info("Shutdown complete")
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

main()
