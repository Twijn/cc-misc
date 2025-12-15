--- AutoCrafter Storage Manager
--- Manages storage operations and inventory tracking.
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")
local inventory = require("lib.inventory")

local manager = {}

local storageConfig = persist("storage-config.json")
local lastScanTime = 0
local scanInterval = 30

---Initialize the storage manager
function manager.init()
    storageConfig.setDefault("ignoredInventories", {})
    storageConfig.setDefault("priorityInventories", {})
    
    -- Initial scan
    manager.scan()
    logger.info("Storage manager initialized")
end

---Set scan interval
---@param seconds number Interval in seconds
function manager.setScanInterval(seconds)
    scanInterval = seconds
end

---Perform inventory scan
---@return table stockLevels Current stock levels
function manager.scan()
    local stock = inventory.scan()
    lastScanTime = os.clock()
    return stock
end

---Check if a scan is needed based on interval
---@return boolean needsScan Whether a scan should be performed
function manager.needsScan()
    return (os.clock() - lastScanTime) >= scanInterval
end

---Get stock level for an item
---@param item string Item ID
---@return number count Stock count
function manager.getStock(item)
    return inventory.getStock(item)
end

---Get all stock levels
---@return table stock All stock levels
function manager.getAllStock()
    return inventory.getAllStock()
end

---Withdraw items from storage
---@param item string Item ID
---@param count number Amount to withdraw
---@param destInv string Destination inventory
---@return number withdrawn Amount actually withdrawn
function manager.withdraw(item, count, destInv)
    local withdrawn = inventory.withdraw(item, count, destInv)
    
    if withdrawn > 0 then
        logger.info(string.format("Withdrew %d %s to %s", withdrawn, item, destInv))
        -- Rescan affected inventories
        manager.scan()
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
        manager.scan()
    end
    
    return deposited
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
        local usedSlots = 0
        for _ in pairs(details.slots) do
            usedSlots = usedSlots + 1
        end
        
        table.insert(result, {
            name = name,
            size = details.size,
            used = usedSlots,
            free = details.size - usedSlots,
        })
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

---Shutdown handler
function manager.beforeShutdown()
    logger.info("Storage manager shutting down")
end

return manager
