--- AutoCrafter Export Manager
--- Manages automated item export to external inventories (e.g., ender storage).
--- Supports "stock" mode (keep items stocked) and "empty" mode (drain from storage).
--- Supports NBT matching modes: "any" (all variants), "none" (no NBT), "with" (has NBT), "exact" (specific NBT)
---
---@version 1.1.0

local persist = require("lib.persist")
local logger = require("lib.log")
local inventory = require("lib.inventory")
local exportConfig = require("config.exports")

local manager = {}

-- NBT matching mode constants (mirrors config)
local NBT_MODE = exportConfig.NBT_MODES

-- Cache of wrapped export peripherals
local exportPeripherals = {}
local lastExportCheck = 0
local exportCheckInterval = 5  -- Seconds between export checks
local exportRunCount = 0  -- Track how many times exports have been processed

-- Default search type for export inventories
local DEFAULT_SEARCH_TYPE = "ender_storage"

---Check if an item key has NBT data
---@param itemKey string The item key (may include :nbtHash)
---@return boolean hasNbt True if item has NBT
---@return string baseName The base item name
---@return string|nil nbtHash The NBT hash if present
local function parseItemKey(itemKey)
    local colonPos = itemKey:find(":", 11)  -- Skip "minecraft:" prefix
    if colonPos then
        local baseName = itemKey:sub(1, colonPos - 1)
        local nbtHash = itemKey:sub(colonPos + 1)
        return true, baseName, nbtHash
    end
    return false, itemKey, nil
end

---Check if a slot item matches the export slot config based on NBT mode
---@param slotItemName string The item name from slot
---@param slotItemNbt? string The NBT hash from slot (if any)
---@param configItem string The configured item name (base name)
---@param nbtMode? string The NBT matching mode (default: "any")
---@param nbtHash? string The specific NBT hash to match (for "exact" mode)
---@return boolean matches True if item matches config
local function itemMatchesConfig(slotItemName, slotItemNbt, configItem, nbtMode, nbtHash)
    -- First check base name matches
    if slotItemName ~= configItem then
        return false
    end
    
    nbtMode = nbtMode or NBT_MODE.ANY
    
    if nbtMode == NBT_MODE.ANY then
        -- Match any variant (with or without NBT)
        return true
    elseif nbtMode == NBT_MODE.NONE then
        -- Only match items WITHOUT NBT
        return slotItemNbt == nil or slotItemNbt == ""
    elseif nbtMode == NBT_MODE.WITH then
        -- Only match items WITH any NBT
        return slotItemNbt ~= nil and slotItemNbt ~= ""
    elseif nbtMode == NBT_MODE.EXACT then
        -- Match specific NBT hash
        return slotItemNbt == nbtHash
    end
    
    return false
end

---Check if an item key matches the export slot config based on NBT mode
---@param itemKey string The full item key (name or name:nbt)
---@param configItem string The configured item name (base name)
---@param nbtMode? string The NBT matching mode (default: "any")
---@param nbtHash? string The specific NBT hash to match (for "exact" mode)
---@return boolean matches True if item matches config
local function itemKeyMatchesConfig(itemKey, configItem, nbtMode, nbtHash)
    local hasNbt, baseName, keyNbtHash = parseItemKey(itemKey)
    return itemMatchesConfig(baseName, keyNbtHash, configItem, nbtMode, nbtHash)
end

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

---Get current item count in an export inventory slot (NBT-aware)
---@param inv table The wrapped peripheral
---@param slot number The slot number
---@param item string The item ID (base name) to match
---@param nbtMode? string NBT matching mode (default: "any")
---@param nbtHash? string Specific NBT hash for "exact" mode
---@return number count The current count (0 if empty or doesn't match)
local function getSlotCount(inv, slot, item, nbtMode, nbtHash)
    local detail
    if inv.getItemDetail then
        detail = inv.getItemDetail(slot)
    else
        local list = inv.list()
        if list then
            detail = list[slot]
        end
    end
    
    if not detail then return 0 end
    
    -- Use NBT-aware matching
    local slotNbt = detail.nbt  -- May be nil
    if itemMatchesConfig(detail.name, slotNbt, item, nbtMode, nbtHash) then
        return detail.count
    end
    return 0
end

---Get total item count in an export inventory (NBT-aware)
---@param inv table The wrapped peripheral
---@param item string The item ID (base name) to match
---@param nbtMode? string NBT matching mode (default: "any")
---@param nbtHash? string Specific NBT hash for "exact" mode
---@return number count The total count
---@return table slots Array of {slot, count, nbt} pairs containing matching items
local function getInventoryItemCount(inv, item, nbtMode, nbtHash)
    local list = inv.list()
    if not list then return 0, {} end
    
    local total = 0
    local slots = {}
    
    for slot, slotItem in pairs(list) do
        local slotNbt = slotItem.nbt  -- May be nil
        if itemMatchesConfig(slotItem.name, slotNbt, item, nbtMode, nbtHash) then
            total = total + slotItem.count
            table.insert(slots, {slot = slot, count = slotItem.count, nbt = slotNbt})
        end
    end
    
    return total, slots
end

---Push items to an export inventory (only for explicitly configured exports)
---Items are ONLY taken from storage inventories, never from other exports or random chests.
---Uses parallel transfers for speed. NBT-aware based on nbtMode.
---@param item string The item ID (base name) - must be explicitly configured for this export
---@param count number Amount to push
---@param destInv string Destination inventory name - must be a configured export
---@param destSlot? number Optional destination slot
---@param nbtMode? string NBT matching mode (default: "any")
---@param nbtHash? string Specific NBT hash for "exact" mode
---@return number pushed Amount actually pushed
---@return table sources Array of {inventory, count} pairs indicating where items came from
local function pushToExport(item, count, destInv, destSlot, nbtMode, nbtHash)
    nbtMode = nbtMode or NBT_MODE.ANY
    
    -- CRITICAL: Verify this destination is actually a configured export inventory
    -- This prevents accidentally pushing items to random ender storages
    local exportCfg = exportConfig.get(destInv)
    if not exportCfg then
        logger.error(string.format("pushToExport: BLOCKED - %s is not a configured export inventory", destInv))
        return 0, {}
    end
    
    -- Find items in storage based on NBT mode
    local locations
    if nbtMode == NBT_MODE.EXACT then
        -- Exact NBT match - use full key
        local fullKey = nbtHash and (item .. ":" .. nbtHash) or item
        locations = inventory.findItem(fullKey, true)
    elseif nbtMode == NBT_MODE.NONE then
        -- No NBT - use base name only (no NBT suffix)
        locations = inventory.findItem(item, true)
    elseif nbtMode == NBT_MODE.WITH then
        -- Any NBT - find all variants with NBT, filter out non-NBT
        local allVariants = inventory.findItemByBaseName(item, true)
        locations = {}
        for _, loc in ipairs(allVariants) do
            local hasNbt, _, _ = parseItemKey(loc.key)
            if hasNbt then
                locations[#locations + 1] = loc
            end
        end
    else
        -- ANY mode - find all variants (base name match)
        locations = inventory.findItemByBaseName(item, true)
    end
    
    if #locations == 0 then 
        logger.debug(string.format("pushToExport: No %s found in storage for export to %s (nbtMode=%s)", 
            item, destInv, nbtMode))
        return 0, {} 
    end
    
    logger.debug(string.format("pushToExport: Found %d location(s) for %s (nbtMode=%s), need %d", 
        #locations, item, nbtMode, count))
    
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
                    -- Update cache incrementally - use full key from location if available
                    local itemKey = loc.key or item
                    inventory.updateCacheRemove(loc.inv, loc.slot, itemKey, transferred)
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
            local capturedKey = loc.key or item  -- Capture full key for cache update
            
            meta[#meta + 1] = {inv = capturedInv, slot = capturedSlot, key = capturedKey}
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
            -- Update cache incrementally - use full key from metadata
            inventory.updateCacheRemove(meta[i].inv, meta[i].slot, meta[i].key, transferred)
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
    
    -- Get storage inventories with empty slots (from cache) - similar to pullSlotsBatch
    local storageWithSpace = inventory.getStorageWithSpace()
    if #storageWithSpace == 0 then
        logger.debug("pullAllFromExport: No storage with empty slots according to cache, trying all storage")
        -- Fall back to all storage
        for _, invName in ipairs(storageInvs) do
            storageWithSpace[#storageWithSpace + 1] = {name = invName, emptySlots = 0}
        end
    else
        logger.debug(string.format("pullAllFromExport: Found %d storage inventories with space", #storageWithSpace))
    end
    
    -- Get all items in the export inventory
    local list = source.list()
    if not list then 
        logger.debug(string.format("pullAllFromExport: Failed to list items in %s (list returned nil)", sourceInv))
        return 0 
    end
    
    if next(list) == nil then
        logger.debug(string.format("pullAllFromExport: Empty table returned from %s (peripheral sees no items)", sourceInv))
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
    
    -- Log what we found
    local itemSummary = {}
    for _, slotInfo in ipairs(slotList) do
        local shortName = slotInfo.name:gsub("minecraft:", "")
        itemSummary[shortName] = (itemSummary[shortName] or 0) + slotInfo.count
    end
    local summaryParts = {}
    for itemName, count in pairs(itemSummary) do
        table.insert(summaryParts, string.format("%s:%d", itemName, count))
    end
    
    logger.debug(string.format("pullAllFromExport: Found %d slots with items in %s, have %d storage with space. Items: %s", 
        #slotList, sourceInv, #storageWithSpace, table.concat(summaryParts, ", ")))
    
    -- Build parallel tasks
    local tasks = {}
    local results = {}
    local meta = {}  -- Track item name for each task
    
    for i, slotInfo in ipairs(slotList) do
        local capturedSlot = slotInfo.slot
        local capturedCount = slotInfo.count
        local capturedName = slotInfo.name
        local capturedSourceInv = sourceInv  -- Capture in closure
        -- Distribute across storage inventories with space
        local storageIdx = ((i - 1) % #storageWithSpace) + 1
        local capturedStorageList = storageWithSpace  -- Capture for closure
        
        meta[#meta + 1] = {name = capturedName}
        tasks[#tasks + 1] = function()
            -- Try ALL storage inventories with space (not limited to 6)
            for attempt = 0, #capturedStorageList - 1 do
                local tryIdx = ((storageIdx - 1 + attempt) % #capturedStorageList) + 1
                local storageName = capturedStorageList[tryIdx].name
                local tryDest = inventory.getPeripheral(storageName)
                if tryDest and tryDest.pullItems then
                    local ok, transferred = pcall(tryDest.pullItems, capturedSourceInv, capturedSlot, capturedCount)
                    if ok and transferred and transferred > 0 then
                        logger.debug(string.format("pullAllFromExport: Pulled %d of %s from slot %d via %s", 
                            transferred, capturedName, capturedSlot, storageName))
                        return transferred
                    elseif not ok then
                        logger.debug(string.format("pullAllFromExport: pullItems error for slot %d (%s) via %s: %s", 
                            capturedSlot, capturedName, storageName, tostring(transferred)))
                    end
                    -- Don't log every "returned 0" - too spammy when trying many barrels
                else
                    logger.debug(string.format("pullAllFromExport: Cannot get peripheral or no pullItems for %s", storageName))
                end
            end
            logger.debug(string.format("pullAllFromExport: Failed to pull slot %d (%s) after trying %d barrels", 
                capturedSlot, capturedName, #capturedStorageList))
            return 0
        end
    end
    
    if #tasks == 0 then
        logger.debug(string.format("pullAllFromExport: No tasks created (slotList=%d, storage=%d)", 
            #slotList, #storageWithSpace))
        return 0
    end
    
    logger.debug(string.format("pullAllFromExport: Created %d tasks for %d slots", #tasks, #slotList))
    
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
---Uses parallel transfers for speed. NBT-aware matching.
---@param name string The peripheral name
---@param inv table The wrapped peripheral
---@param slotConfig table The slot configuration
---@return number pulled Amount of non-matching items pulled to storage
local function processVacuumSlots(name, inv, slotConfig)
    local expectedItem = slotConfig.item
    local nbtMode = slotConfig.nbtMode or NBT_MODE.ANY
    local nbtHash = slotConfig.nbtHash
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
            else
                -- Check if item matches using NBT-aware matching
                local slotNbt = slotItem.nbt
                local matches = itemMatchesConfig(slotItem.name, slotNbt, expectedItem, nbtMode, nbtHash)
                if not matches then
                    -- Doesn't match expected item - should vacuum
                    shouldPull = true
                end
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
        local nbtMode = slotConfig.nbtMode or NBT_MODE.ANY
        local nbtHash = slotConfig.nbtHash
        
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
                    local currentCount = getSlotCount(inv, slot, item, nbtMode, nbtHash)
                    if currentCount < targetQty then
                        local needed = targetQty - currentCount
                        local pushed, sources = pushToExport(item, needed, name, slot, nbtMode, nbtHash)
                        result.pushed = result.pushed + pushed
                        
                        if pushed > 0 then
                            logger.debug(string.format("Stocked %d %s to %s slot %d (nbtMode=%s)", pushed, item, name, slot, nbtMode))
                        end
                    end
                elseif config.mode == "empty" then
                    local currentCount = getSlotCount(inv, slot, item, nbtMode, nbtHash)
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
                currentCount = getSlotCount(inv, specificSlot, item, nbtMode, nbtHash)
            else
                currentCount = getInventoryItemCount(inv, item, nbtMode, nbtHash)
            end
            
            if currentCount < targetQty then
                local needed = targetQty - currentCount
                logger.debug(string.format("Need to push %d %s to %s (nbtMode=%s)", needed, item, name, nbtMode))
                local pushed, sources = pushToExport(item, needed, name, specificSlot, nbtMode, nbtHash)
                result.pushed = result.pushed + pushed
                
                if pushed > 0 then
                    -- Build source description
                    local sourceStrs = {}
                    for _, src in ipairs(sources) do
                        table.insert(sourceStrs, string.format("%s(%d)", src.inventory, src.count))
                    end
                    local sourceDesc = #sourceStrs > 0 and table.concat(sourceStrs, ", ") or "unknown"
                    logger.debug(string.format("Stocked %d %s to %s from %s (nbtMode=%s)", pushed, item, name, sourceDesc, nbtMode))
                elseif needed > 0 then
                    logger.debug(string.format("Failed to stock %s to %s: 0 pushed of %d needed (nbtMode=%s)", item, name, needed, nbtMode))
                end
            end
            
        elseif config.mode == "empty" then
            -- Empty mode: pull items FROM the export inventory INTO storage
            local currentCount, itemSlots
            if specificSlot then
                currentCount = getSlotCount(inv, specificSlot, item, nbtMode, nbtHash)
            else
                currentCount, itemSlots = getInventoryItemCount(inv, item, nbtMode, nbtHash)
            end
            
            if currentCount > 0 then
                local toPull = currentCount
                if targetQty > 0 then
                    -- If target quantity set, only pull excess (keep targetQty)
                    toPull = math.max(0, currentCount - targetQty)
                end
                
                if toPull > 0 then
                    local pulled = pullFromExport(item, toPull, name, specificSlot)
                    result.pulled = result.pulled + pulled
                    
                    if pulled > 0 then
                        logger.debug(string.format("Emptied %d %s from %s", pulled, item, name))
                    end
                end
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
    
    for name, config in pairs(inventories) do
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
