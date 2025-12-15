--- AutoCrafter Crafter Turtle
--- Turtle component that executes crafting jobs from the server.
---
---@version 1.0.0

local VERSION = "1.0.0"

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

---Find connected inventories
---@return table inventories Array of inventory peripheral names
local function getInventories()
    local inventories = {}
    for _, name in ipairs(peripheral.getNames()) do
        local types = {peripheral.getType(name)}
        for _, t in ipairs(types) do
            if t == "inventory" then
                table.insert(inventories, name)
                break
            end
        end
    end
    return inventories
end

---Find an item in connected inventories
---@param item string Item ID to find
---@param count number Amount needed
---@return table|nil locations Array of {inventory, slot, count} or nil
local function findItem(item, count)
    local inventories = getInventories()
    local found = {}
    local foundCount = 0
    
    for _, invName in ipairs(inventories) do
        local inv = peripheral.wrap(invName)
        if inv then
            local list = inv.list()
            if list then
                for slot, slotItem in pairs(list) do
                    if slotItem.name == item then
                        table.insert(found, {
                            inventory = invName,
                            slot = slot,
                            count = slotItem.count,
                        })
                        foundCount = foundCount + slotItem.count
                        
                        if foundCount >= count then
                            return found
                        end
                    end
                end
            end
        end
    end
    
    if foundCount > 0 then
        return found
    end
    return nil
end

---Clear the turtle inventory to storage
local function clearInventory()
    local inventories = getInventories()
    if #inventories == 0 then return end
    
    local targetInv = inventories[1]
    
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            -- Try to push to inventory
            for _, invName in ipairs(inventories) do
                local inv = peripheral.wrap(invName)
                if inv then
                    local pushed = inv.pullItems(peripheral.getName(peripheral.find("modem")), slot)
                    if pushed and pushed > 0 then
                        break
                    end
                end
            end
        end
    end
    
    turtle.select(1)
end

---Pull item from inventory to turtle slot
---@param item string Item ID
---@param count number Amount to pull
---@param turtleSlot number Destination slot
---@return number pulled Amount actually pulled
local function pullItem(item, count, turtleSlot)
    local locations = findItem(item, count)
    if not locations then
        return 0
    end
    
    local pulled = 0
    turtle.select(turtleSlot)
    
    for _, loc in ipairs(locations) do
        if pulled >= count then break end
        
        local inv = peripheral.wrap(loc.inventory)
        if inv then
            local toPull = math.min(count - pulled, loc.count)
            local modemName = peripheral.getName(peripheral.find("modem"))
            
            -- Use suck if modem not available, otherwise pushItems
            if modemName then
                local amount = inv.pushItems(modemName, loc.slot, toPull, turtleSlot)
                pulled = pulled + (amount or 0)
            end
        end
    end
    
    return pulled
end

---Execute a crafting job
---@param job table The crafting job
---@return boolean success Whether crafting succeeded
---@return number|string result Output count or error message
local function executeCraft(job)
    local recipe = job.recipe
    if not recipe then
        return false, "No recipe in job"
    end
    
    -- Clear inventory first
    clearInventory()
    
    -- Build crafting grid based on recipe type
    local grid = {}
    for i = 1, 9 do grid[i] = nil end
    
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
                end
            end
        end
    else -- shapeless
        local slot = 1
        for _, ingredient in ipairs(recipe.ingredients) do
            for _ = 1, ingredient.count do
                grid[slot] = ingredient.item
                slot = slot + 1
            end
        end
    end
    
    -- Gather materials for each craft
    local craftsCompleted = 0
    local craftsToDo = job.crafts or 1
    
    for craft = 1, craftsToDo do
        -- Clear crafting area
        for gridSlot = 1, 9 do
            local turtleSlot = CRAFT_SLOTS[gridSlot]
            if turtle.getItemCount(turtleSlot) > 0 then
                turtle.select(turtleSlot)
                turtle.drop()
            end
        end
        
        -- Gather materials for this craft
        local materialsOk = true
        for gridSlot = 1, 9 do
            local item = grid[gridSlot]
            if item then
                local turtleSlot = CRAFT_SLOTS[gridSlot]
                local pulled = pullItem(item, 1, turtleSlot)
                
                if pulled == 0 then
                    materialsOk = false
                    logger.warn("Failed to get " .. item .. " for slot " .. gridSlot)
                    break
                end
            end
        end
        
        if not materialsOk then
            -- Return items to storage
            clearInventory()
            if craftsCompleted > 0 then
                return true, craftsCompleted * (recipe.outputCount or 1)
            else
                return false, "Missing materials"
            end
        end
        
        -- Select output slot and craft
        turtle.select(OUTPUT_SLOT)
        local craftSuccess = turtle.craft()
        
        if craftSuccess then
            craftsCompleted = craftsCompleted + 1
            
            -- Move output to storage
            local outputCount = turtle.getItemCount(OUTPUT_SLOT)
            for _, invName in ipairs(getInventories()) do
                local inv = peripheral.wrap(invName)
                if inv then
                    local modemName = peripheral.getName(peripheral.find("modem"))
                    if modemName then
                        local pushed = inv.pullItems(modemName, OUTPUT_SLOT, outputCount)
                        if pushed and pushed > 0 then
                            break
                        end
                    end
                end
            end
        else
            clearInventory()
            if craftsCompleted > 0 then
                return true, craftsCompleted * (recipe.outputCount or 1)
            else
                return false, "Crafting failed"
            end
        end
    end
    
    -- Clear any remaining items
    clearInventory()
    
    return true, craftsCompleted * (recipe.outputCount or 1)
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
        local message = comms.receive(5)
        
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
