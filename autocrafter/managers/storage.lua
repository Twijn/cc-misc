--- AutoCrafter Storage Manager
--- Manages storage operations and inventory tracking.
--- Uses cached inventory system to minimize peripheral calls.
---
---@version 2.0.0

local persist = require("lib.persist")
local logger = require("lib.log")
local inventory = require("lib.inventory")

local manager = {}

local storageConfig = persist("storage-config.json")
local lastScanTime = 0
local scanInterval = 30

---Initialize the storage manager
---@param storageType? string Optional storage peripheral type
function manager.init(storageType)
    storageConfig.setDefault("ignoredInventories", {})
    storageConfig.setDefault("priorityInventories", {})
    
    -- Set storage peripheral type if provided
    if storageType then
        inventory.setStorageType(storageType)
    end
    
    -- Initialize inventory library from cache
    inventory.init()
    
    -- Check if we have valid cached data, only scan if needed
    local stock = inventory.getAllStock()
    local hasCache = stock and next(stock) ~= nil
    
    if hasCache then
        logger.info("Storage manager initialized from cache")
    else
        -- No cache, perform initial scan
        manager.scan()
        logger.info("Storage manager initialized with full scan")
    end
end

---Set scan interval
---@param seconds number Interval in seconds
function manager.setScanInterval(seconds)
    scanInterval = seconds
end

---Perform inventory scan
---@param forceRefresh? boolean Force rediscovery of peripherals
---@return table stockLevels Current stock levels
function manager.scan(forceRefresh)
    local stock = inventory.scan(forceRefresh)
    lastScanTime = os.clock()
    return stock
end

---Check if a scan is needed based on interval
---@return boolean needsScan Whether a scan should be performed
function manager.needsScan()
    return (os.clock() - lastScanTime) >= scanInterval
end

---Get stock level for an item (from cache)
---@param item string Item ID
---@return number count Stock count
function manager.getStock(item)
    return inventory.getStock(item)
end

---Get all stock levels (from cache)
---@return table stock All stock levels
function manager.getAllStock()
    return inventory.getAllStock()
end

---Withdraw items from storage
---@param item string Item ID
---@param count number Amount to withdraw
---@param destInv string Destination inventory
---@param destSlot? number Optional destination slot
---@return number withdrawn Amount actually withdrawn
function manager.withdraw(item, count, destInv, destSlot)
    local withdrawn = inventory.withdraw(item, count, destInv, destSlot)
    
    if withdrawn > 0 then
        logger.info(string.format("Withdrew %d %s to %s", withdrawn, item, destInv))
        -- Note: inventory.withdraw() already updates affected caches
    end
    
    return withdrawn
end

---Deposit items into storage
---@param sourceInv string Source inventory
---@param item? string Optional item filter
---@return number deposited Amount deposited
function manager.deposit(sourceInv, item)
    local deposited = inventory.deposit(sourceInv, item)
    
    if deposited > 0 then
        if item then
            logger.info(string.format("Deposited %d %s from %s", deposited, item, sourceInv))
        else
            logger.info(string.format("Deposited %d items from %s", deposited, sourceInv))
        end
        -- Note: inventory.deposit() already updates affected caches
    end
    
    return deposited
end

---Clear specific slots from an inventory into storage
---@param sourceInv string Source inventory (e.g., turtle name)
---@param slots table Array of slot numbers to clear
---@return number cleared Amount of items cleared
function manager.clearSlots(sourceInv, slots)
    logger.debug(string.format("storageManager.clearSlots called: sourceInv=%s, slots=%s", 
        tostring(sourceInv), textutils.serialize(slots or {})))
    
    local cleared = inventory.clearSlots(sourceInv, slots)
    
    logger.debug(string.format("storageManager.clearSlots result: cleared=%d", cleared))
    
    if cleared > 0 then
        logger.info(string.format("Cleared %d items from %d slots in %s", cleared, #slots, sourceInv))
    end
    
    return cleared
end

---Pull a single slot from an inventory into storage
---This is a simplified, reliable method for turtle clearing.
---The caller provides the slot contents so we don't need to query the source.
---@param sourceInv string Source inventory name (e.g., turtle network name)
---@param slot number The slot number to pull from
---@param itemName string The item ID in the slot
---@param itemCount number The count of items in the slot
---@param itemNbt? string Optional NBT hash
---@return number pulled Amount of items actually pulled
---@return string|nil error Error message if failed
function manager.pullSlot(sourceInv, slot, itemName, itemCount, itemNbt)
    logger.debug(string.format("storageManager.pullSlot: %s slot %d (%dx %s)", 
        sourceInv, slot, itemCount, itemName))
    
    local pulled, err = inventory.pullSlot(sourceInv, slot, itemName, itemCount, itemNbt)
    
    return pulled, err
end

---Pull multiple slots from an inventory in a single batch operation
---This is much faster than calling pullSlot multiple times.
---@param sourceInv string Source inventory name (e.g., turtle network name)
---@param slotContents table Array of {slot, name, count, nbt?} for each slot to pull
---@return table results Array of {slot, pulled, error?} for each slot
---@return number totalPulled Total items pulled
function manager.pullSlotsBatch(sourceInv, slotContents)
    logger.debug(string.format("storageManager.pullSlotsBatch: %s, %d slots", 
        sourceInv, #slotContents))
    
    local results, totalPulled = inventory.pullSlotsBatch(sourceInv, slotContents)
    
    if totalPulled > 0 then
        logger.info(string.format("Batch pulled %d items from %d slots in %s", 
            totalPulled, #slotContents, sourceInv))
    end
    
    return results, totalPulled
end

---Withdraw items to a player's inventory via manipulator
---@param item string Item ID to withdraw
---@param count number Amount to withdraw
---@param playerName string Player name to send items to
---@return number withdrawn Amount actually withdrawn
---@return string|nil error Error message if failed
function manager.withdrawToPlayer(item, count, playerName)
    local withdrawn, err = inventory.withdrawToPlayer(item, count, playerName)
    
    if withdrawn > 0 then
        logger.info(string.format("Withdrew %d %s to player %s", withdrawn, item, playerName))
    end
    
    return withdrawn, err
end

---Deposit items from a player's inventory via manipulator
---@param playerName string Player name to get items from
---@param item? string Optional item filter
---@param maxCount? number Optional max items to deposit
---@return number deposited Amount deposited
---@return string|nil error Error message if failed
function manager.depositFromPlayer(playerName, item, maxCount)
    local deposited, err = inventory.depositFromPlayer(playerName, item, maxCount)
    
    if deposited > 0 then
        if item then
            logger.info(string.format("Deposited %d %s from player %s", deposited, item, playerName))
        else
            logger.info(string.format("Deposited %d items from player %s", deposited, playerName))
        end
    end
    
    return deposited, err
end

---Check if manipulator is available for player transfers
---@return boolean available Whether manipulator is available
function manager.hasManipulator()
    return inventory.hasManipulator()
end

---Get storage statistics
---@return table stats Storage statistics
function manager.getStats()
    local total, used, free = inventory.slotCounts()
    local stock = inventory.getAllStock()
    
    local uniqueItems = 0
    local totalItems = 0
    
    for _, count in pairs(stock) do
        uniqueItems = uniqueItems + 1
        totalItems = totalItems + count
    end
    
    return {
        totalSlots = total,
        usedSlots = used,
        freeSlots = free,
        uniqueItems = uniqueItems,
        totalItems = totalItems,
        inventoryCount = #inventory.getInventoryNames(),
        lastScan = lastScanTime,
        percentFull = total > 0 and math.floor((used / total) * 100) or 0,
    }
end

---Get list of inventories
---@return table inventories Array of inventory info
function manager.getInventories()
    local names = inventory.getInventoryNames()
    local result = {}
    
    for _, name in ipairs(names) do
        local details = inventory.getInventoryDetails(name)
        if details then
            local usedSlots = 0
            if details.slots then
                for _ in pairs(details.slots) do
                    usedSlots = usedSlots + 1
                end
            end
            
            local size = details.size or 0
            table.insert(result, {
                name = name,
                size = size,
                used = usedSlots,
                free = size - usedSlots,
            })
        end
    end
    
    return result
end

---Search for items by name
---@param query string Search query (partial match)
---@return table results Array of {item, count} pairs
function manager.searchItems(query)
    local stock = inventory.getAllStock()
    local results = {}
    query = query:lower()
    
    for item, count in pairs(stock) do
        if item:lower():find(query, 1, true) then
            table.insert(results, {
                item = item,
                count = count,
            })
        end
    end
    
    table.sort(results, function(a, b)
        return a.count > b.count
    end)
    
    return results
end

---Fuzzy match an item name to the best match in storage
---First tries exact match, then partial match
---@param query string Item name or partial name
---@return string|nil item The matched item ID or nil
---@return number count The stock count (0 if not found)
function manager.resolveItem(query)
    if not query or query == "" then
        return nil, 0
    end
    
    -- Add minecraft: prefix if missing
    if not query:find(":") then
        query = "minecraft:" .. query
    end
    
    local stock = inventory.getAllStock()
    
    -- Try exact match first
    if stock[query] then
        return query, stock[query]
    end
    
    -- Try partial/fuzzy match
    local queryLower = query:lower()
    local bestMatch = nil
    local bestCount = 0
    local bestScore = 0  -- Higher score = better match
    
    for item, count in pairs(stock) do
        local itemLower = item:lower()
        
        -- Check if query matches part of the item name
        if itemLower:find(queryLower, 1, true) then
            local score = 0
            
            -- Exact suffix match (e.g., "beef" matches "cooked_beef")
            if itemLower:sub(-#queryLower) == queryLower then
                score = 3
            -- Query appears after a separator (e.g., "beef" in "minecraft:beef")
            elseif itemLower:find("[_:]" .. queryLower:gsub("minecraft:", ""), 1, false) then
                score = 2
            -- Any partial match
            else
                score = 1
            end
            
            -- Prefer items with higher stock on tie
            if score > bestScore or (score == bestScore and count > bestCount) then
                bestMatch = item
                bestCount = count
                bestScore = score
            end
        end
    end
    
    return bestMatch, bestCount
end

---Get top items by count
---@param limit? number Max items to return (default 10)
---@return table items Array of {item, count} pairs
function manager.getTopItems(limit)
    limit = limit or 10
    local stock = inventory.getAllStock()
    local items = {}
    
    for item, count in pairs(stock) do
        table.insert(items, {item = item, count = count})
    end
    
    table.sort(items, function(a, b)
        return a.count > b.count
    end)
    
    local result = {}
    for i = 1, math.min(limit, #items) do
        table.insert(result, items[i])
    end
    
    return result
end

---Add inventory to ignore list
---@param name string Inventory name
function manager.ignoreInventory(name)
    local ignored = storageConfig.get("ignoredInventories") or {}
    ignored[name] = true
    storageConfig.set("ignoredInventories", ignored)
end

---Remove inventory from ignore list
---@param name string Inventory name
function manager.unignoreInventory(name)
    local ignored = storageConfig.get("ignoredInventories") or {}
    ignored[name] = nil
    storageConfig.set("ignoredInventories", ignored)
end

---Get cache statistics
---@return table stats Cache statistics
function manager.getCacheStats()
    return inventory.getCacheStats()
end

---Clear all caches and force rescan
function manager.clearCaches()
    inventory.clearCaches()
    manager.scan(true)
    logger.info("Caches cleared and rescanned")
end

---Invalidate cache to force next scan to happen immediately
---This is non-blocking and just marks that a scan is needed
function manager.invalidateCache()
    lastScanTime = 0  -- Reset scan time so needsScan() returns true
end

---Shutdown handler
function manager.beforeShutdown()
    logger.info("Storage manager shutting down")
end

return manager
