--- AutoCrafter Export Manager
--- Manages automated item export to external inventories (e.g., ender storage).
--- Supports "stock" mode (keep items stocked) and "empty" mode (drain from storage).
---
---@version 1.0.1

local persist = require("lib.persist")
local logger = require("lib.log")
local inventory = require("lib.inventory")
local exportConfig = require("config.exports")

local manager = {}

-- Cache of wrapped export peripherals
local exportPeripherals = {}
local lastExportCheck = 0
local exportCheckInterval = 5  -- Seconds between export checks
local exportRunCount = 0  -- Track how many times exports have been processed

-- Default search type for export inventories
local DEFAULT_SEARCH_TYPE = "ender_storage"

---Initialize the export manager
function manager.init()
    exportPeripherals = {}
    logger.info("Export manager initialized")
end

---Set the export check interval
---@param seconds number Interval in seconds
function manager.setCheckInterval(seconds)
    exportCheckInterval = seconds
end

---Get a wrapped export peripheral (cached)
---@param name string The peripheral name
---@return table|nil peripheral The wrapped peripheral or nil
local function getExportPeripheral(name)
    if exportPeripherals[name] then
        return exportPeripherals[name]
    end
    
    local p = peripheral.wrap(name)
    if p then
        exportPeripherals[name] = p
        logger.debug(string.format("Wrapped export peripheral: %s", name))
    else
        logger.debug(string.format("Failed to wrap export peripheral: %s (not found)", name))
    end
    
    return p
end

---Find peripherals matching a search type
---@param searchType string The peripheral type to search for
---@return string[] names Array of peripheral names
local function findPeripheralsOfType(searchType)
    local results = {}
    for _, name in ipairs(peripheral.getNames()) do
        local types = {peripheral.getType(name)}
        for _, t in ipairs(types) do
            if t == searchType then
                table.insert(results, name)
                break
            end
        end
    end
    return results
end

---Check if an export check is needed based on interval
---@return boolean needsCheck Whether a check should be performed
function manager.needsCheck()
    return (os.clock() - lastExportCheck) >= exportCheckInterval
end

---Get current item count in an export inventory slot
---@param inv table The wrapped peripheral
---@param slot number The slot number
---@param item string The item ID to match
---@return number count The current count (0 if empty or different item)
local function getSlotCount(inv, slot, item)
    if not inv.getItemDetail then
        local list = inv.list()
        if list and list[slot] then
            local slotItem = list[slot]
            if slotItem.name == item then
                return slotItem.count
            end
        end
        return 0
    end
    
    local detail = inv.getItemDetail(slot)
    if detail and detail.name == item then
        return detail.count
    end
    return 0
end

---Get total item count in an export inventory
---@param inv table The wrapped peripheral
---@param item string The item ID to match
---@return number count The total count
---@return table slots Array of {slot, count} pairs containing the item
local function getInventoryItemCount(inv, item)
    local list = inv.list()
    if not list then return 0, {} end
    
    local total = 0
    local slots = {}
    
    for slot, slotItem in pairs(list) do
        if slotItem.name == item then
            total = total + slotItem.count
            table.insert(slots, {slot = slot, count = slotItem.count})
        end
    end
    
    return total, slots
end

---Push items to an export inventory (only for explicitly configured exports)
---Items are ONLY taken from storage inventories, never from other exports or random chests.
---Uses parallel transfers for speed
---@param item string The item ID - must be explicitly configured for this export
---@param count number Amount to push
---@param destInv string Destination inventory name - must be a configured export
---@param destSlot? number Optional destination slot
---@return number pushed Amount actually pushed
---@return table sources Array of {inventory, count} pairs indicating where items came from
local function pushToExport(item, count, destInv, destSlot)
    -- CRITICAL: Verify this destination is actually a configured export inventory
    -- This prevents accidentally pushing items to random ender storages
    local exportCfg = exportConfig.get(destInv)
    if not exportCfg then
        logger.error(string.format("pushToExport: BLOCKED - %s is not a configured export inventory", destInv))
        return 0, {}
    end
    
    -- Find item in storage only (not in other export inventories)
    local locations = inventory.findItem(item, true)
    if #locations == 0 then 
        logger.debug(string.format("pushToExport: No %s found in storage for export to %s", item, destInv))
        return 0, {} 
    end
    
    logger.debug(string.format("pushToExport: Found %d location(s) for %s, need %d", #locations, item, count))
    
    -- Sort by count (largest first) for efficiency
    table.sort(locations, function(a, b) return a.count > b.count end)
    
    -- If specific slot, must do sequential
    if destSlot then
        local pushed = 0
        local sources = {}
        
        for _, loc in ipairs(locations) do
            if pushed >= count then break end
            if loc.inv == destInv then goto continue end
            if not inventory.isStorageInventory(loc.inv) then goto continue end
            
            local source = inventory.getPeripheral(loc.inv)
            if source then
                local toPush = math.min(count - pushed, loc.count)
                local transferred = source.pushItems(destInv, loc.slot, toPush, destSlot) or 0
                pushed = pushed + transferred
                
                if transferred > 0 then
                    sources[loc.inv] = (sources[loc.inv] or 0) + transferred
                    -- Update cache incrementally - no need to rescan entire inventory
                    inventory.updateCacheRemove(loc.inv, loc.slot, item, transferred)
                end
            end
            ::continue::
        end
        
        local sourceList = {}
        for inv, cnt in pairs(sources) do
            table.insert(sourceList, {inventory = inv, count = cnt})
        end
        return pushed, sourceList
    end
    
    -- Build parallel tasks for each source location
    local tasks = {}
    local meta = {}
    local remaining = count
    
    for _, loc in ipairs(locations) do
        if remaining <= 0 then break end
        if loc.inv == destInv then goto continue end
        if not inventory.isStorageInventory(loc.inv) then 
            logger.debug(string.format("pushToExport: Skipping non-storage inventory %s", loc.inv))
            goto continue 
        end
        
        local source = inventory.getPeripheral(loc.inv)
        if source then
            local toPush = math.min(remaining, loc.count)
            remaining = remaining - toPush
            
            local capturedInv = loc.inv
            local capturedSlot = loc.slot
            local capturedAmount = toPush
            local capturedDestInv = destInv  -- Capture destInv in closure
            
            meta[#meta + 1] = {inv = capturedInv, slot = capturedSlot}
            tasks[#tasks + 1] = function()
                local ok, transferred = pcall(source.pushItems, capturedDestInv, capturedSlot, capturedAmount)
                if not ok then
                    logger.debug(string.format("pushToExport: pushItems failed from %s slot %d to %s: %s", 
                        capturedInv, capturedSlot, capturedDestInv, tostring(transferred)))
                    return 0
                end
                return transferred or 0
            end
        else
            logger.debug(string.format("pushToExport: Failed to get peripheral for %s", loc.inv))
        end
        ::continue::
    end
    
    if #tasks == 0 then 
        logger.debug(string.format("pushToExport: No valid tasks created for %s -> %s", item, destInv))
        return 0, {} 
    end
    
    logger.debug(string.format("pushToExport: Executing %d parallel tasks for %s -> %s", #tasks, item, destInv))
    
    -- Execute in parallel batches
    local results = {}
    local taskFns = {}
    for i, task in ipairs(tasks) do
        local idx = i
        taskFns[#taskFns + 1] = function()
            results[idx] = task()
        end
    end
    
    local batchSize = 8
    for batch = 1, #taskFns, batchSize do
        local batchEnd = math.min(batch + batchSize - 1, #taskFns)
        local batchFns = {}
        for i = batch, batchEnd do
            batchFns[#batchFns + 1] = taskFns[i]
        end
        parallel.waitForAll(table.unpack(batchFns))
    end
    
    -- Sum results and build sources
    local pushed = 0
    local sources = {}
    for i, result in ipairs(results) do
        local transferred = result or 0
        if transferred > 0 then
            pushed = pushed + transferred
            sources[meta[i].inv] = (sources[meta[i].inv] or 0) + transferred
            -- Update cache incrementally - no need to rescan entire inventory
            inventory.updateCacheRemove(meta[i].inv, meta[i].slot, item, transferred)
        end
    end
    
    logger.debug(string.format("pushToExport: Completed - pushed %d of %d requested for %s -> %s", 
        pushed, count, item, destInv))
    
    -- Convert sources to array format for return
    local sourceList = {}
    for inv, cnt in pairs(sources) do
        table.insert(sourceList, {inventory = inv, count = cnt})
    end
    
    return pushed, sourceList
end

---Pull items from an export inventory back to storage
---Uses parallel transfers for speed
---@param item string The item ID
---@param count number Amount to pull
---@param sourceInv string Source export inventory name
---@param sourceSlot? number Optional source slot
---@return number pulled Amount actually pulled
local function pullFromExport(item, count, sourceInv, sourceSlot)
    local source = getExportPeripheral(sourceInv)
    if not source then 
        logger.debug(string.format("pullFromExport: Source %s not available", sourceInv))
        return 0 
    end
    
    local storageInvs = inventory.getStorageInventories()
    if #storageInvs == 0 then 
        logger.debug("pullFromExport: No storage inventories available")
        return 0 
    end
    
    -- If specific slot, just pull from that
    if sourceSlot then
        logger.debug(string.format("pullFromExport: Pulling from specific slot %d of %s", sourceSlot, sourceInv))
        -- Try parallel pulls to multiple storage inventories
        local tasks = {}
        for i, destName in ipairs(storageInvs) do
            local dest = inventory.getPeripheral(destName)
            if dest and dest.pullItems then
                local capturedDestName = destName
                tasks[#tasks + 1] = function()
                    local ok, transferred = pcall(dest.pullItems, sourceInv, sourceSlot, count)
                    if not ok then
                        logger.warn(string.format("pullFromExport: pullItems failed from %s slot %d to %s: %s", 
                            sourceInv, sourceSlot, capturedDestName, tostring(transferred)))
                    end
                    return ok and transferred or 0
                end
            end
        end
        
        -- Run first batch - usually first one succeeds
        if #tasks > 0 then
            local result = tasks[1]()
            if result > 0 then
                logger.debug(string.format("pullFromExport: Pulled %d from slot %d of %s", result, sourceSlot, sourceInv))
                -- Update stock (we know the item from the function parameter)
                inventory.updateStockAdd(item, result)
                return result
            end
            -- If first failed, try rest sequentially
            local pulled = 0
            for i = 2, #tasks do
                result = tasks[i]()
                if result > 0 then
                    pulled = pulled + result
                    break
                end
            end
            if pulled > 0 then
                logger.debug(string.format("pullFromExport: Pulled %d from slot %d of %s (retry)", pulled, sourceSlot, sourceInv))
                -- Update stock
                inventory.updateStockAdd(item, pulled)
            else
                logger.warn(string.format("pullFromExport: Failed to pull from slot %d of %s", sourceSlot, sourceInv))
            end
            return pulled
        end
        logger.debug(string.format("pullFromExport: No storage tasks created for slot %d of %s", sourceSlot, sourceInv))
        return 0
    end
    
    -- Pull from any slot containing the item
    local _, slots = getInventoryItemCount(source, item)
    if #slots == 0 then 
        logger.debug(string.format("pullFromExport: Item %s not found in %s", item, sourceInv))
        return 0 
    end
    
    logger.debug(string.format("pullFromExport: Found %s in %d slots of %s, need %d", item, #slots, sourceInv, count))
    
    local pulled = 0
    
    -- Build parallel tasks for each slot
    local tasks = {}
    local meta = {}
    
    for _, slotInfo in ipairs(slots) do
        if pulled >= count then break end
        local capturedSlot = slotInfo.slot
        local capturedCount = math.min(count - pulled, slotInfo.count)
        pulled = pulled + capturedCount  -- Optimistic accounting
        
        -- Distribute across storage inventories
        local storageIdx = (#tasks % #storageInvs) + 1
        local destName = storageInvs[storageIdx]
        local dest = inventory.getPeripheral(destName)
        
        if dest and dest.pullItems then
            meta[#meta + 1] = {slot = capturedSlot, expected = capturedCount, destName = destName}
            tasks[#tasks + 1] = function()
                -- Try multiple storage inventories if first fails
                for attempt = 0, math.min(#storageInvs - 1, 3) do
                    local tryIdx = ((storageIdx - 1 + attempt) % #storageInvs) + 1
                    local tryDest = inventory.getPeripheral(storageInvs[tryIdx])
                    if tryDest and tryDest.pullItems then
                        local ok, transferred = pcall(tryDest.pullItems, sourceInv, capturedSlot, capturedCount)
                        if ok and transferred and transferred > 0 then
                            return transferred
                        end
                    end
                end
                return 0
            end
        end
    end
    
    -- Execute in parallel
    if #tasks > 0 then
        local results = {}
        local taskFns = {}
        for i, task in ipairs(tasks) do
            local idx = i
            taskFns[#taskFns + 1] = function()
                results[idx] = task()
            end
        end
        parallel.waitForAll(table.unpack(taskFns))
        
        -- Sum actual results and track which storage inventories were used
        pulled = 0
        for i, result in ipairs(results) do
            local transferred = result or 0
            if transferred > 0 then
                pulled = pulled + transferred
            end
        end
        
        -- Update stock total (lightweight - no need to scan for exact slot)
        -- Location cache will be corrected on next periodic scan
        if pulled > 0 then
            inventory.updateStockAdd(item, pulled)
        end
        
        logger.debug(string.format("pullFromExport: Pulled %d %s from %s", pulled, item, sourceInv))
    else
        logger.debug(string.format("pullFromExport: No tasks created for %s from %s", item, sourceInv))
    end
    
    return pulled
end

---Pull all items from an export inventory back to storage
---Uses parallel transfers for speed
---@param sourceInv string Source export inventory name
---@return number pulled Total amount of items pulled
local function pullAllFromExport(sourceInv)
    local source = getExportPeripheral(sourceInv)
    if not source then 
        logger.debug(string.format("pullAllFromExport: Source peripheral %s not available", sourceInv))
        return 0 
    end
    
    local storageInvs = inventory.getStorageInventories()
    if #storageInvs == 0 then 
        logger.debug("pullAllFromExport: No storage inventories available")
        return 0 
    end
    
    -- Get all items in the export inventory
    local list = source.list()
    if not list then 
        logger.debug(string.format("pullAllFromExport: Failed to list items in %s", sourceInv))
        return 0 
    end
    
    -- Build list of slots to pull
    local slotList = {}
    for slot, slotItem in pairs(list) do
        slotList[#slotList + 1] = {slot = slot, count = slotItem.count, name = slotItem.name}
    end
    
    if #slotList == 0 then 
        logger.debug(string.format("pullAllFromExport: No items found in %s", sourceInv))
        return 0 
    end
    
    logger.debug(string.format("pullAllFromExport: Found %d slots with items in %s", #slotList, sourceInv))
    
    -- Build parallel tasks
    local tasks = {}
    local results = {}
    local meta = {}  -- Track item name for each task
    
    for i, slotInfo in ipairs(slotList) do
        local capturedSlot = slotInfo.slot
        local capturedCount = slotInfo.count
        local capturedName = slotInfo.name
        local capturedSourceInv = sourceInv  -- Capture in closure
        -- Distribute across storage inventories
        local storageIdx = ((i - 1) % #storageInvs) + 1
        
        meta[#meta + 1] = {name = capturedName}
        tasks[#tasks + 1] = function()
            -- Try multiple storage inventories if first fails
            for attempt = 0, math.min(#storageInvs - 1, 5) do
                local tryIdx = ((storageIdx - 1 + attempt) % #storageInvs) + 1
                local tryDest = inventory.getPeripheral(storageInvs[tryIdx])
                if tryDest and tryDest.pullItems then
                    local ok, transferred = pcall(tryDest.pullItems, capturedSourceInv, capturedSlot, capturedCount)
                    if ok and transferred and transferred > 0 then
                        return transferred
                    elseif not ok then
                        logger.debug(string.format("pullAllFromExport: pullItems error for slot %d (%s): %s", 
                            capturedSlot, capturedName, tostring(transferred)))
                    end
                end
            end
            return 0
        end
    end
    
    -- Execute in parallel batches
    local taskFns = {}
    for i, task in ipairs(tasks) do
        local idx = i
        taskFns[#taskFns + 1] = function()
            results[idx] = task()
        end
    end
    
    -- Run in batches of 8
    local batchSize = 8
    for batch = 1, #taskFns, batchSize do
        local batchEnd = math.min(batch + batchSize - 1, #taskFns)
        local batchFns = {}
        for i = batch, batchEnd do
            batchFns[#batchFns + 1] = taskFns[i]
        end
        parallel.waitForAll(table.unpack(batchFns))
    end
    
    -- Sum results and update stock cache
    local pulled = 0
    for i, result in ipairs(results) do
        local transferred = result or 0
        if transferred > 0 then
            pulled = pulled + transferred
            -- Update stock total for this item (lightweight - no scan needed)
            if meta[i] and meta[i].name then
                inventory.updateStockAdd(meta[i].name, transferred)
            end
        end
    end
    
    logger.debug(string.format("pullAllFromExport: Completed - pulled %d items from %s", pulled, sourceInv))
    
    return pulled
end

---Process vacuum slots (remove items that don't match expected item in slot range)
---Uses parallel transfers for speed
---@param name string The peripheral name
---@param inv table The wrapped peripheral
---@param slotConfig table The slot configuration
---@return number pulled Amount of non-matching items pulled to storage
local function processVacuumSlots(name, inv, slotConfig)
    local expectedItem = slotConfig.item
    local storageInvs = inventory.getStorageInventories()
    
    if #storageInvs == 0 then return 0 end
    
    -- Get list of slots to check
    local slotsToCheck = exportConfig.getExpandedSlots(slotConfig)
    
    -- If no specific slots and it's a wildcard vacuum, vacuum ALL slots
    if #slotsToCheck == 0 and expectedItem == "*" then
        local list = inv.list()
        if list then
            for slot in pairs(list) do
                table.insert(slotsToCheck, slot)
            end
        end
    end
    
    local list = inv.list()
    if not list then return 0 end
    
    -- Build list of slots that need vacuuming
    local slotsToPull = {}
    for _, slot in ipairs(slotsToCheck) do
        local slotItem = list[slot]
        if slotItem then
            local shouldPull = false
            
            if expectedItem == "*" then
                -- Wildcard vacuum: pull everything from these slots
                shouldPull = true
            elseif slotItem.name ~= expectedItem then
                -- Specific item vacuum: pull non-matching items
                shouldPull = true
            end
            
            if shouldPull then
                slotsToPull[#slotsToPull + 1] = {slot = slot, count = slotItem.count, name = slotItem.name}
            end
        end
    end
    
    if #slotsToPull == 0 then return 0 end
    
    -- Build parallel tasks
    local tasks = {}
    local results = {}
    local meta = {}  -- Track item name for each task
    
    for i, slotInfo in ipairs(slotsToPull) do
        local capturedSlot = slotInfo.slot
        local capturedCount = slotInfo.count
        local storageIdx = ((i - 1) % #storageInvs) + 1
        
        meta[#meta + 1] = {name = slotInfo.name}
        tasks[#tasks + 1] = function()
            for attempt = 0, math.min(#storageInvs - 1, 5) do
                local tryIdx = ((storageIdx - 1 + attempt) % #storageInvs) + 1
                local tryDest = inventory.getPeripheral(storageInvs[tryIdx])
                if tryDest and tryDest.pullItems then
                    local ok, transferred = pcall(tryDest.pullItems, name, capturedSlot, capturedCount)
                    if ok and transferred and transferred > 0 then
                        return transferred
                    end
                end
            end
            return 0
        end
    end
    
    -- Execute in parallel batches
    local taskFns = {}
    for i, task in ipairs(tasks) do
        local idx = i
        taskFns[#taskFns + 1] = function()
            results[idx] = task()
        end
    end
    
    local batchSize = 8
    for batch = 1, #taskFns, batchSize do
        local batchEnd = math.min(batch + batchSize - 1, #taskFns)
        local batchFns = {}
        for i = batch, batchEnd do
            batchFns[#batchFns + 1] = taskFns[i]
        end
        parallel.waitForAll(table.unpack(batchFns))
    end
    
    -- Sum results and update stock cache
    local pulled = 0
    for i, result in ipairs(results) do
        local transferred = result or 0
        if transferred > 0 then
            pulled = pulled + transferred
            -- Update stock total for this item (lightweight - no scan needed)
            if meta[i] and meta[i].name then
                inventory.updateStockAdd(meta[i].name, transferred)
            end
        end
    end
    
    return pulled
end

local function processExportInventory(name, config)
    local result = {pushed = 0, pulled = 0}
    
    local inv = getExportPeripheral(name)
    if not inv then
        logger.warn("Export inventory not available: " .. name)
        return result
    end
    
    local slots = config.slots or {}
    
    -- Debug: show what's actually in the export inventory
    local list = inv.list()
    if list then
        local itemCount = 0
        local itemSummary = {}
        for slot, slotItem in pairs(list) do
            itemCount = itemCount + 1
            local shortName = slotItem.name:gsub("minecraft:", "")
            itemSummary[shortName] = (itemSummary[shortName] or 0) + slotItem.count
        end
        if itemCount > 0 then
            local summaryParts = {}
            for itemName, count in pairs(itemSummary) do
                table.insert(summaryParts, string.format("%s:%d", itemName, count))
            end
            logger.debug(string.format("processExportInventory: %s contains: %s", 
                name, table.concat(summaryParts, ", ")))
        else
            logger.debug(string.format("processExportInventory: %s is empty", name))
        end
    end
    
    -- Special case: empty mode with no items configured = pull ALL items
    if config.mode == "empty" and #slots == 0 then
        logger.debug(string.format("processExportInventory: %s is in empty mode with no slots, pulling ALL items", name))
        local pulled = pullAllFromExport(name)
        result.pulled = result.pulled + pulled
        if pulled > 0 then
            logger.debug(string.format("Emptied all: %d items from %s", pulled, name))
        else
            logger.debug(string.format("Empty mode: nothing to pull from %s (may already be empty)", name))
        end
        return result
    end
    
    for _, slotConfig in ipairs(slots) do
        local item = slotConfig.item
        local targetQty = slotConfig.quantity
        local specificSlot = slotConfig.slot
        local slotStart = slotConfig.slotStart
        local slotEnd = slotConfig.slotEnd
        local isVacuum = slotConfig.vacuum
        
        -- Process vacuum slots first (remove non-matching items)
        if isVacuum then
            local vacuumed = processVacuumSlots(name, inv, slotConfig)
            result.pulled = result.pulled + vacuumed
            if vacuumed > 0 then
                logger.debug(string.format("Vacuumed %d non-matching items from %s", vacuumed, name))
            end
        end
        
        -- Skip further processing for wildcard vacuum slots
        if item == "*" then
            goto continue
        end
        
        -- Handle slot ranges
        if slotStart and slotEnd then
            for slot = slotStart, slotEnd do
                if config.mode == "stock" then
                    local currentCount = getSlotCount(inv, slot, item)
                    if currentCount < targetQty then
                        local needed = targetQty - currentCount
                        local pushed, sources = pushToExport(item, needed, name, slot)
                        result.pushed = result.pushed + pushed
                        
                        if pushed > 0 then
                            logger.debug(string.format("Stocked %d %s to %s slot %d", pushed, item, name, slot))
                        end
                    end
                elseif config.mode == "empty" then
                    local currentCount = getSlotCount(inv, slot, item)
                    logger.debug(string.format("Empty slot range: slot %d of %s, item=%s, current=%d, targetQty=%d", 
                        slot, name, item, currentCount, targetQty))
                    if currentCount > 0 then
                        local toPull = currentCount
                        if targetQty > 0 then
                            toPull = math.max(0, currentCount - targetQty)
                        end
                        if toPull > 0 then
                            local pulled = pullFromExport(item, toPull, name, slot)
                            result.pulled = result.pulled + pulled
                            if pulled > 0 then
                                logger.debug(string.format("Empty slot range: pulled %d %s from slot %d of %s", 
                                    pulled, item, slot, name))
                            end
                        end
                    end
                end
            end
        elseif config.mode == "stock" then
            -- Stock mode: keep the export inventory stocked with items from storage
            local currentCount
            if specificSlot then
                currentCount = getSlotCount(inv, specificSlot, item)
            else
                currentCount = getInventoryItemCount(inv, item)
            end
            
            logger.debug(string.format("Stock check for %s in %s: current=%d, target=%d", 
                item, name, currentCount, targetQty))
            
            if currentCount < targetQty then
                local needed = targetQty - currentCount
                logger.debug(string.format("Need to push %d %s to %s", needed, item, name))
                local pushed, sources = pushToExport(item, needed, name, specificSlot)
                result.pushed = result.pushed + pushed
                
                if pushed > 0 then
                    -- Build source description
                    local sourceStrs = {}
                    for _, src in ipairs(sources) do
                        table.insert(sourceStrs, string.format("%s(%d)", src.inventory, src.count))
                    end
                    local sourceDesc = #sourceStrs > 0 and table.concat(sourceStrs, ", ") or "unknown"
                    logger.debug(string.format("Stocked %d %s to %s from %s", pushed, item, name, sourceDesc))
                elseif needed > 0 then
                    logger.debug(string.format("Failed to stock %s to %s: 0 pushed of %d needed", item, name, needed))
                end
            end
            
        elseif config.mode == "empty" then
            -- Empty mode: pull items FROM the export inventory INTO storage
            local currentCount, itemSlots
            if specificSlot then
                currentCount = getSlotCount(inv, specificSlot, item)
            else
                currentCount, itemSlots = getInventoryItemCount(inv, item)
            end
            
            logger.debug(string.format("Empty check for %s in %s: current=%d, targetQty=%d, slot=%s", 
                item, name, currentCount, targetQty, specificSlot and tostring(specificSlot) or "any"))
            
            if currentCount > 0 then
                local toPull = currentCount
                if targetQty > 0 then
                    -- If target quantity set, only pull excess (keep targetQty)
                    toPull = math.max(0, currentCount - targetQty)
                end
                
                logger.debug(string.format("Empty mode: will try to pull %d of %d %s from %s", 
                    toPull, currentCount, item, name))
                
                if toPull > 0 then
                    local pulled = pullFromExport(item, toPull, name, specificSlot)
                    result.pulled = result.pulled + pulled
                    
                    if pulled > 0 then
                        logger.debug(string.format("Emptied %d %s from %s", pulled, item, name))
                    else
                        logger.debug(string.format("Empty mode: pullFromExport returned 0 for %s from %s", item, name))
                    end
                end
            else
                logger.debug(string.format("Empty mode: item %s not found in %s", item, name))
            end
        end
        
        ::continue::
    end
    
    return result
end

---Process all export inventories
---@return table stats Processing statistics
function manager.processExports()
    lastExportCheck = os.clock()
    exportRunCount = exportRunCount + 1
    
    local inventories = exportConfig.getAll()
    local stats = {
        inventoriesProcessed = 0,
        totalPushed = 0,
        totalPulled = 0,
        errors = 0,
    }
    
    local invCount = 0
    for _ in pairs(inventories) do invCount = invCount + 1 end
    
    if invCount == 0 then
        return stats
    end
    
    logger.debug(string.format("processExports: Processing %d export inventories", invCount))
    
    for name, config in pairs(inventories) do
        logger.debug(string.format("processExports: Processing %s (mode=%s, slots=%d)", 
            name, config.mode or "?", #(config.slots or {})))
        
        local ok, result = pcall(processExportInventory, name, config)
        
        if ok then
            stats.inventoriesProcessed = stats.inventoriesProcessed + 1
            stats.totalPushed = stats.totalPushed + result.pushed
            stats.totalPulled = stats.totalPulled + result.pulled
            
            if result.pushed > 0 or result.pulled > 0 then
                logger.debug(string.format("processExports: %s - pushed=%d, pulled=%d", 
                    name, result.pushed, result.pulled))
            end
        else
            stats.errors = stats.errors + 1
            logger.warn(string.format("Error processing export %s: %s", name, tostring(result)))
        end
    end
    
    if stats.totalPushed > 0 or stats.totalPulled > 0 then
        logger.debug(string.format("Exports: pushed=%d, pulled=%d from %d inventories", 
            stats.totalPushed, stats.totalPulled, stats.inventoriesProcessed))
    end
    
    return stats
end

---Get export statistics
---@return table stats Export statistics
function manager.getStats()
    local inventories = exportConfig.getAll()
    local invCount = 0
    local itemCount = 0
    
    for _, config in pairs(inventories) do
        invCount = invCount + 1
        itemCount = itemCount + #(config.slots or {})
    end
    
    return {
        inventoryCount = invCount,
        itemCount = itemCount,
        lastCheck = lastExportCheck,
        checkInterval = exportCheckInterval,
    }
end

---Get default search type for export inventories
---@return string searchType The default peripheral search type
function manager.getDefaultSearchType()
    return DEFAULT_SEARCH_TYPE
end

---Set default search type for export inventories  
---@param searchType string The peripheral search type
function manager.setDefaultSearchType(searchType)
    DEFAULT_SEARCH_TYPE = searchType
end

---Find available export peripherals
---@param searchType? string The peripheral type to search for (default: ender_storage)
---@return string[] names Array of peripheral names
function manager.findExportPeripherals(searchType)
    return findPeripheralsOfType(searchType or DEFAULT_SEARCH_TYPE)
end

---Shutdown handler
function manager.beforeShutdown()
    logger.info("Export manager shutting down")
end

return manager
