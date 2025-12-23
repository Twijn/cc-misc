--- AutoCrafter Inventory Library
--- Manages inventory scanning and item storage with comprehensive caching.
--- All peripheral calls are cached to minimize network/peripheral overhead.
--- Uses internal cache updates after transfers instead of rescanning.
--- Supports parallel execution for faster inventory operations.
---
---@version 3.1.0

local VERSION = "3.1.0"

local persist = require("lib.persist")
local logger = require("lib.log")
local config = require("config")

local inventory = {}

-- Determine cache path from config (default to /disk/data/cache)
-- Use absolute path (starts with /) so persist.lua doesn't prepend data/
local cachePath = config.cachePath or "/disk/data/cache"

-- Ensure cache directory exists
fs.makeDir(cachePath)

-- Persistent caches
local inventoryCache = persist(cachePath .. "/inventories.json")
local itemDetailCache = persist(cachePath .. "/item-details.json")
local stockCache = persist(cachePath .. "/stock.json")

-- Parallelism configuration (from config, with defaults)
local parallelConfig = config.parallelism or {}
local transferThreads = parallelConfig.transferThreads or 4
local scanThreads = parallelConfig.scanThreads or 16
local batchSize = parallelConfig.batchSize or 8
local parallelEnabled = parallelConfig.enabled ~= false  -- Default true

-- Runtime state (not persisted)
local wrappedPeripherals = {}  -- Cached peripheral.wrap() results
local itemLocations = {}       -- Map of item -> locations
local lastScanTime = 0
local lastFullScan = 0
local inventoryNames = {}      -- Cached list of inventory names
local inventorySizes = {}      -- Cached inventory sizes
local inventoryTypes = {}      -- Cached peripheral types for each inventory
local storageInventories = {}  -- Cached list of storage-type inventory names
local storagePeripheralType = config.storagePeripheralType or "sc-goodies:diamond_barrel"  -- Storage type from config
local modemPeripheral = nil    -- Cached modem peripheral
local modemName = nil          -- Cached modem name
local scanInProgress = false
local manipulator = nil        -- Cached manipulator peripheral
local deferredRebuild = false  -- Flag to defer cache rebuilding for batch operations
local emptySlotCache = {}      -- Cache of empty slots per inventory: {invName = {slot1, slot2, ...}}
local stockLevelsDirty = false -- Flag to indicate stock levels need recalculation

-- Mutex-like state for thread-safe results collection
local parallelResults = {}
local parallelResultsLock = false

---Execute functions in parallel with configurable thread limit
---Batches work into groups of threadLimit and executes each batch in parallel
---@param tasks table Array of functions to execute
---@param threadLimit? number Maximum concurrent tasks (default: transferThreads config)
---@return table results Array of results from each task (in order)
local function executeParallel(tasks, threadLimit)
    if not parallelEnabled or #tasks == 0 then
        -- Sequential fallback
        local results = {}
        for i, task in ipairs(tasks) do
            results[i] = {task()}
        end
        return results
    end
    
    threadLimit = threadLimit or transferThreads
    local results = {}
    
    -- Process in batches to respect thread limit
    for batchStart = 1, #tasks, threadLimit do
        local batchEnd = math.min(batchStart + threadLimit - 1, #tasks)
        local batchTasks = {}
        local batchResults = {}
        
        for i = batchStart, batchEnd do
            local taskIndex = i
            table.insert(batchTasks, function()
                batchResults[taskIndex] = {tasks[taskIndex]()}
            end)
        end
        
        -- Execute batch in parallel
        if #batchTasks > 0 then
            parallel.waitForAll(table.unpack(batchTasks))
        end
        
        -- Collect results
        for i = batchStart, batchEnd do
            results[i] = batchResults[i]
        end
    end
    
    return results
end

---Update parallelism configuration at runtime
---@param newConfig table New parallelism settings
function inventory.setParallelConfig(newConfig)
    if newConfig.transferThreads then
        transferThreads = newConfig.transferThreads
    end
    if newConfig.scanThreads then
        scanThreads = newConfig.scanThreads
    end
    if newConfig.batchSize then
        batchSize = newConfig.batchSize
    end
    if newConfig.enabled ~= nil then
        parallelEnabled = newConfig.enabled
    end
    logger.debug(string.format("Parallelism config updated: threads=%d, batch=%d, enabled=%s",
        transferThreads, batchSize, tostring(parallelEnabled)))
end

---Get current parallelism configuration
---@return table config Current parallelism settings
function inventory.getParallelConfig()
    return {
        transferThreads = transferThreads,
        scanThreads = scanThreads,
        batchSize = batchSize,
        enabled = parallelEnabled,
    }
end

---Get item detail cache key
---@param item table The item with name and optional nbt
---@return string key The cache key
local function getDetailCacheKey(item)
    if item.nbt then
        return item.name .. ":" .. item.nbt
    end
    return item.name
end

---Generate a unique key for an item (for stock tracking)
---@param item table The item data
---@return string key The unique item key
local function getItemKey(item)
    if item.nbt then
        return item.name .. ":" .. item.nbt
    end
    return item.name
end

---Update the internal cache after removing items from a slot
---Does NOT call any peripheral functions - purely cache manipulation
---@param invName string The inventory name
---@param slot number The slot number
---@param itemKey string The item key (from getItemKey)
---@param count number Amount removed
local function updateCacheAfterRemoval(invName, slot, itemKey, count)
    local invData = inventoryCache.get(invName)
    if not invData or not invData.slots then return end
    
    local slotKey = tostring(slot)  -- JSON uses string keys
    local slotData = invData.slots[slot] or invData.slots[slotKey]
    
    if slotData then
        local newCount = slotData.count - count
        if newCount <= 0 then
            -- Slot is now empty
            invData.slots[slot] = nil
            invData.slots[slotKey] = nil
            -- Add to empty slot cache
            if not emptySlotCache[invName] then
                emptySlotCache[invName] = {}
            end
            table.insert(emptySlotCache[invName], slot)
        else
            -- Update count
            slotData.count = newCount
            invData.slots[slot] = slotData
            invData.slots[slotKey] = nil  -- Normalize to numeric key
        end
        inventoryCache.set(invName, invData)
        
        -- Update stock levels directly
        local levels = stockCache.get("levels") or {}
        levels[itemKey] = math.max(0, (levels[itemKey] or 0) - count)
        if levels[itemKey] == 0 then
            levels[itemKey] = nil
        end
        stockCache.set("levels", levels)
        
        -- Update item locations cache
        if itemLocations[itemKey] then
            for i, loc in ipairs(itemLocations[itemKey]) do
                if loc.inventory == invName and loc.slot == slot then
                    if newCount <= 0 then
                        table.remove(itemLocations[itemKey], i)
                    else
                        itemLocations[itemKey][i].count = newCount
                    end
                    break
                end
            end
        end
    end
end

---Update the internal cache after adding items to a slot
---Does NOT call any peripheral functions - purely cache manipulation
---@param invName string The inventory name
---@param slot number The slot number
---@param itemName string The item name (e.g., "minecraft:stone")
---@param count number Amount added
---@param nbt? string Optional NBT hash
local function updateCacheAfterAddition(invName, slot, itemName, count, nbt)
    local invData = inventoryCache.get(invName)
    if not invData then
        invData = { slots = {}, size = inventorySizes[invName] or 27 }
    end
    if not invData.slots then
        invData.slots = {}
    end
    
    local slotKey = tostring(slot)
    local existingData = invData.slots[slot] or invData.slots[slotKey]
    local itemKey = nbt and (itemName .. ":" .. nbt) or itemName
    
    if existingData then
        -- Slot already has items - add to count
        existingData.count = existingData.count + count
        invData.slots[slot] = existingData
        invData.slots[slotKey] = nil  -- Normalize to numeric key
    else
        -- Slot was empty - add new item data
        invData.slots[slot] = {
            name = itemName,
            count = count,
            nbt = nbt,
        }
        -- Remove from empty slot cache
        if emptySlotCache[invName] then
            for i, emptySlot in ipairs(emptySlotCache[invName]) do
                if emptySlot == slot then
                    table.remove(emptySlotCache[invName], i)
                    break
                end
            end
        end
    end
    
    inventoryCache.set(invName, invData)
    
    -- Update stock levels directly
    local levels = stockCache.get("levels") or {}
    levels[itemKey] = (levels[itemKey] or 0) + count
    stockCache.set("levels", levels)
    
    -- Update item locations cache
    if not itemLocations[itemKey] then
        itemLocations[itemKey] = {}
    end
    local found = false
    for i, loc in ipairs(itemLocations[itemKey]) do
        if loc.inventory == invName and loc.slot == slot then
            itemLocations[itemKey][i].count = itemLocations[itemKey][i].count + count
            found = true
            break
        end
    end
    if not found then
        table.insert(itemLocations[itemKey], {
            inventory = invName,
            slot = slot,
            count = count,
        })
    end
end

---Check if an inventory is a storage type using the cached types
---This is much faster than calling peripheral.getType() every time
---@param invName string The inventory name
---@return boolean isStorage Whether the inventory is a storage type
local function isStorageType(invName)
    local types = inventoryTypes[invName]
    if not types then return false end
    
    for _, t in ipairs(types) do
        if t == storagePeripheralType then
            return true
        end
    end
    return false
end

---Get the maximum stack size for an item
---Uses cached item details when available, defaults to 64
---@param itemName string The item name (e.g., "minecraft:stone")
---@param nbt? string Optional NBT hash
---@return number maxStackSize The maximum stack size for this item
local function getMaxStackSize(itemName, nbt)
    local cacheKey = nbt and (itemName .. ":" .. nbt) or itemName
    
    -- Check detail cache for maxCount
    local cached = itemDetailCache.get(cacheKey)
    if cached and cached.maxCount then
        return cached.maxCount
    end
    
    -- Default stack sizes for common items
    -- Most items stack to 64, but some have lower limits
    local knownStackSizes = {
        ["minecraft:ender_pearl"] = 16,
        ["minecraft:snowball"] = 16,
        ["minecraft:egg"] = 16,
        ["minecraft:bucket"] = 16,
        ["minecraft:sign"] = 16,
        ["minecraft:honey_bottle"] = 16,
        ["minecraft:banner"] = 16,
    }
    
    if knownStackSizes[itemName] then
        return knownStackSizes[itemName]
    end
    
    -- Default to 64 for most items
    return 64
end

---Get an empty slot from a storage inventory (from cache)
---@param invName string The inventory name
---@return number|nil slot An empty slot number or nil if full
local function getEmptySlot(invName)
    -- Check empty slot cache first
    if emptySlotCache[invName] and #emptySlotCache[invName] > 0 then
        return emptySlotCache[invName][1]  -- Return first empty slot (don't remove yet)
    end
    
    -- Rebuild empty slot cache for this inventory if needed
    local invData = inventoryCache.get(invName)
    if not invData or not invData.size then return nil end
    
    emptySlotCache[invName] = {}
    for slot = 1, invData.size do
        local slotKey = tostring(slot)
        if not invData.slots[slot] and not invData.slots[slotKey] then
            table.insert(emptySlotCache[invName], slot)
        end
    end
    
    if #emptySlotCache[invName] > 0 then
        return emptySlotCache[invName][1]
    end
    
    return nil
end

---Find slots with partial stacks of a specific item that can accept more items
---@param itemName string The item name (e.g., "minecraft:stone")
---@param nbt? string Optional NBT hash
---@param storageInvs? table Optional list of storage inventory names to search
---@return table partialSlots Array of {inventory, slot, count, space} sorted by space ascending (smallest gaps first)
local function findPartialStacks(itemName, nbt, storageInvs)
    local itemKey = nbt and (itemName .. ":" .. nbt) or itemName
    local maxStackSize = getMaxStackSize(itemName, nbt)
    local partialSlots = {}
    
    -- Get item locations from cache
    local locations = itemLocations[itemKey] or {}
    
    -- If no locations in runtime cache, check persistent cache
    if #locations == 0 then
        local invData = inventoryCache.getAll()
        for name, data in pairs(invData) do
            if data.slots then
                for slot, slotItem in pairs(data.slots) do
                    local key = getItemKey(slotItem)
                    if key == itemKey then
                        local slotNum = tonumber(slot) or slot
                        table.insert(locations, {
                            inventory = name,
                            slot = slotNum,
                            count = slotItem.count,
                        })
                    end
                end
            end
        end
    end
    
    -- Filter to storage inventories and find partial stacks
    local storageSet = {}
    if storageInvs then
        for _, name in ipairs(storageInvs) do
            storageSet[name] = true
        end
    end
    
    for _, loc in ipairs(locations) do
        -- Only include if it's a storage inventory (or if no filter provided)
        if not storageInvs or storageSet[loc.inventory] then
            local space = maxStackSize - loc.count
            if space > 0 then
                table.insert(partialSlots, {
                    inventory = loc.inventory,
                    slot = loc.slot,
                    count = loc.count,
                    space = space,
                })
            end
        end
    end
    
    -- Sort by space ascending - fill smallest gaps first for better compaction
    table.sort(partialSlots, function(a, b)
        return a.space < b.space
    end)
    
    return partialSlots
end

---Get the cached modem peripheral (finds once, caches forever)
---@return table|nil modem The modem peripheral or nil
---@return string|nil name The modem name or nil
function inventory.getModem()
    if modemPeripheral then
        return modemPeripheral, modemName
    end
    
    modemPeripheral = peripheral.find("modem")
    if modemPeripheral then
        modemName = peripheral.getName(modemPeripheral)
    end
    
    return modemPeripheral, modemName
end

---Get a wrapped peripheral (cached)
---@param name string The peripheral name
---@return table|nil peripheral The wrapped peripheral or nil
function inventory.getPeripheral(name)
    if wrappedPeripherals[name] then
        return wrappedPeripherals[name]
    end
    
    local p = peripheral.wrap(name)
    if p then
        wrappedPeripherals[name] = p
    end
    
    return p
end

---Discover all inventory peripherals (cached)
---@param forceRefresh? boolean Force rediscovery of peripherals
---@return table names Array of inventory peripheral names
function inventory.discoverInventories(forceRefresh)
    if not forceRefresh and #inventoryNames > 0 then
        return inventoryNames
    end
    
    inventoryNames = {}
    storageInventories = {}
    wrappedPeripherals = {}  -- Clear wrapped cache on rediscovery
    inventoryTypes = {}
    
    for _, name in ipairs(peripheral.getNames()) do
        local types = {peripheral.getType(name)}
        local isInventory = false
        local isStorage = false
        
        for _, t in ipairs(types) do
            if t == "inventory" then
                isInventory = true
            end
            if t == storagePeripheralType then
                isStorage = true
            end
        end
        
        if isInventory then
            table.insert(inventoryNames, name)
            inventoryTypes[name] = types
            
            -- Pre-wrap and cache
            local p = peripheral.wrap(name)
            if p then
                wrappedPeripherals[name] = p
                -- Cache size (doesn't change)
                inventorySizes[name] = p.size()
            end
            
            -- Track storage inventories separately
            if isStorage then
                table.insert(storageInventories, name)
                logger.debug(string.format("Discovered storage peripheral: %s", name))
            end
        end
    end
    
    -- Log storage discovery results
    logger.debug(string.format("Discovered %d inventories, %d are storage type (%s)", 
        #inventoryNames, #storageInventories, storagePeripheralType))
    
    if #storageInventories == 0 then
        logger.warn("WARNING: No storage peripherals found!")
        logger.warn("Configured storage type: " .. storagePeripheralType)
        logger.warn("Items will NOT be deposited until storage peripherals are available.")
    end
    
    -- Also find and cache modem
    inventory.getModem()
    
    return inventoryNames
end

---Set the storage peripheral type
---@param peripheralType string The peripheral type for storage (e.g., "sc-goodies:diamond_barrel")
function inventory.setStorageType(peripheralType)
    storagePeripheralType = peripheralType
end

---Get the list of storage inventories
---@return table names Array of storage inventory names
function inventory.getStorageInventories()
    if #storageInventories > 0 then
        return storageInventories
    end
    
    -- Rebuild from inventory names if needed
    inventory.discoverInventories(true)
    return storageInventories
end

---Get configured storage peripheral type
---@return string type The storage peripheral type
function inventory.getStorageType()
    return storagePeripheralType
end

---Debug function to list all peripherals and their types
---Useful for diagnosing storage configuration issues
---@return table diagnostics Table with storage diagnostics
function inventory.debugStoragePeripherals()
    local diagnostics = {
        configuredType = storagePeripheralType,
        storageInventories = {},
        allInventories = {},
        warnings = {},
    }
    
    -- List all peripherals with inventory capability
    for _, name in ipairs(peripheral.getNames()) do
        local types = {peripheral.getType(name)}
        local hasInventory = false
        local hasStorage = false
        
        for _, t in ipairs(types) do
            if t == "inventory" then hasInventory = true end
            if t == storagePeripheralType then hasStorage = true end
        end
        
        if hasInventory then
            local info = {
                name = name,
                types = types,
                isStorage = hasStorage,
            }
            table.insert(diagnostics.allInventories, info)
            
            if hasStorage then
                table.insert(diagnostics.storageInventories, name)
            end
        end
    end
    
    -- Generate warnings
    if #diagnostics.storageInventories == 0 then
        table.insert(diagnostics.warnings, "No storage peripherals found with type: " .. storagePeripheralType)
        table.insert(diagnostics.warnings, "Check your config.lua storagePeripheralType setting")
    end
    
    return diagnostics
end

---Check if an inventory is a storage inventory
---@param name string The inventory name
---@return boolean isStorage Whether it's a storage inventory
function inventory.isStorageInventory(name)
    local types = inventoryTypes[name]
    if not types then return false end
    
    for _, t in ipairs(types) do
        if t == storagePeripheralType then
            return true
        end
    end
    return false
end

---Get inventory size (cached)
---@param name string The inventory name
---@return number size The inventory size
function inventory.getSize(name)
    if inventorySizes[name] then
        return inventorySizes[name]
    end
    
    local p = inventory.getPeripheral(name)
    if p and p.size then
        inventorySizes[name] = p.size()
        return inventorySizes[name]
    end
    
    return 0
end

---Scan all inventories and update caches
---@param forceRefresh? boolean Force rediscovery of peripherals
---@return table stockLevels Table of item counts
function inventory.scan(forceRefresh)
    if scanInProgress then
        -- Return cached data if scan already in progress
        return stockCache.get("levels") or {}
    end
    
    scanInProgress = true
    
    -- Clear runtime caches
    itemLocations = {}
    local newStockLevels = {}
    local newInventoryData = {}
    
    -- Discover inventories if needed
    local invNames = inventory.discoverInventories(forceRefresh)
    
    -- Batch scan inventories using parallel operations for better performance
    -- Each inv.list() is a peripheral call that can run concurrently
    local scanResults = {}
    local scanFunctions = {}
    
    for _, name in ipairs(invNames) do
        local inv = inventory.getPeripheral(name)
        if inv then
            table.insert(scanFunctions, function()
                local list = inv.list()
                if list then
                    local size = inventory.getSize(name)
                    scanResults[name] = {
                        slots = list,
                        size = size,
                    }
                end
            end)
        end
    end
    
    -- Run all scans in parallel (CC:Tweaked supports this)
    if #scanFunctions > 0 then
        parallel.waitForAll(table.unpack(scanFunctions))
    end
    
    -- Process scan results (sequential, but just data processing)
    -- Also build empty slot cache
    emptySlotCache = {}
    
    -- Build storage set for filtering stock levels
    local storageSet = {}
    for _, name in ipairs(storageInventories) do
        storageSet[name] = true
    end
    
    for name, data in pairs(scanResults) do
        newInventoryData[name] = data
        emptySlotCache[name] = {}
        
        -- Only include items from storage inventories in stock levels
        local isStorage = storageSet[name]
        
        for slot, item in pairs(data.slots) do
            local key = getItemKey(item)
            
            -- Only update stock levels for storage inventories
            if isStorage then
                newStockLevels[key] = (newStockLevels[key] or 0) + item.count
            end
            
            -- Track item locations (runtime only) - still track all for now
            if not itemLocations[key] then
                itemLocations[key] = {}
            end
            table.insert(itemLocations[key], {
                inventory = name,
                slot = slot,
                count = item.count,
            })
        end
        
        -- Build empty slot cache for this inventory
        if data.size then
            for slot = 1, data.size do
                if not data.slots[slot] and not data.slots[tostring(slot)] then
                    table.insert(emptySlotCache[name], slot)
                end
            end
        end
    end
    
    -- Persist the caches
    inventoryCache.setAll(newInventoryData)
    stockCache.set("levels", newStockLevels)
    stockCache.set("lastScan", os.epoch("utc"))
    
    lastScanTime = os.clock()
    lastFullScan = os.epoch("utc")
    scanInProgress = false
    
    return newStockLevels
end

---Scan a single inventory and update caches
---@param name string The inventory name to scan
---@param skipRebuild? boolean Skip rebuilding cache (for batch operations)
---@return table slots The slots in that inventory
function inventory.scanSingle(name, skipRebuild)
    local inv = inventory.getPeripheral(name)
    if not inv then return {} end
    
    local list = inv.list()
    if not list then return {} end
    
    local size = inventory.getSize(name)
    
    -- Update inventory cache
    inventoryCache.set(name, {
        slots = list,
        size = size,
    })
    
    -- Update empty slot cache for this inventory
    emptySlotCache[name] = {}
    if size then
        for slot = 1, size do
            if not list[slot] and not list[tostring(slot)] then
                table.insert(emptySlotCache[name], slot)
            end
        end
    end
    
    -- Rebuild stock levels and locations from cached inventory data (unless deferred)
    if not skipRebuild and not deferredRebuild then
        inventory.rebuildFromCache()
    end
    
    return list
end

---Begin a batch operation (defers cache rebuilding)
function inventory.beginBatch()
    deferredRebuild = true
end

---End a batch operation and rebuild cache
function inventory.endBatch()
    deferredRebuild = false
    inventory.rebuildFromCache()
end

---Rebuild stock levels and item locations from cached inventory data
---Also rebuilds empty slot cache
---@return table stockLevels The rebuilt stock levels
function inventory.rebuildFromCache()
    local invData = inventoryCache.getAll()
    local newStockLevels = {}
    itemLocations = {}
    emptySlotCache = {}
    
    -- Build storage set for filtering stock levels
    -- Use getStorageInventories() to ensure storageInventories is populated
    local storageSet = {}
    local storageInvs = inventory.getStorageInventories()
    for _, name in ipairs(storageInvs) do
        storageSet[name] = true
    end
    
    for name, data in pairs(invData) do
        emptySlotCache[name] = {}
        
        -- Only include items from storage inventories in stock levels
        local isStorage = storageSet[name]
        
        if data.slots then
            for slot, item in pairs(data.slots) do
                local key = getItemKey(item)
                -- Convert slot to number (JSON deserializes numeric keys as strings)
                local slotNum = tonumber(slot) or slot
                
                -- Only update stock levels for storage inventories
                if isStorage then
                    newStockLevels[key] = (newStockLevels[key] or 0) + item.count
                end
                
                if not itemLocations[key] then
                    itemLocations[key] = {}
                end
                table.insert(itemLocations[key], {
                    inventory = name,
                    slot = slotNum,
                    count = item.count,
                })
            end
        end
        
        -- Rebuild empty slot cache
        if data.size then
            for slot = 1, data.size do
                if not data.slots[slot] and not data.slots[tostring(slot)] then
                    table.insert(emptySlotCache[name], slot)
                end
            end
        end
    end
    
    stockCache.set("levels", newStockLevels)
    stockCache.set("lastScan", os.epoch("utc"))
    
    return newStockLevels
end

---Get stock level for an item
---@param item string The item ID
---@return number count The total count across all inventories
function inventory.getStock(item)
    local levels = stockCache.get("levels") or {}
    return levels[item] or 0
end

---Get all stock levels
---@return table stockLevels Table of all item counts
function inventory.getAllStock()
    return stockCache.get("levels") or {}
end

---Find slots containing an item (from cache)
---@param item string The item ID
---@param storageOnly? boolean If true, only search in storage inventories (default: false)
---@return table locations Array of {inventory, slot, count}
function inventory.findItem(item, storageOnly)
    -- Build storage set if filtering
    local storageSet = nil
    if storageOnly then
        storageSet = {}
        local storageInvs = inventory.getStorageInventories()
        for _, name in ipairs(storageInvs) do
            storageSet[name] = true
        end
    end
    
    -- First check runtime cache
    if itemLocations[item] and #itemLocations[item] > 0 then
        if not storageOnly then
            return itemLocations[item]
        end
        -- Filter to storage inventories only
        local filtered = {}
        for _, loc in ipairs(itemLocations[item]) do
            if storageSet[loc.inventory] then
                table.insert(filtered, loc)
            end
        end
        return filtered
    end
    
    -- Rebuild from persistent cache if needed
    local invData = inventoryCache.getAll()
    local locations = {}
    
    for name, data in pairs(invData) do
        -- Skip non-storage inventories if storageOnly is true
        if storageOnly and not storageSet[name] then
            goto continue
        end
        
        if data.slots then
            for slot, slotItem in pairs(data.slots) do
                local key = getItemKey(slotItem)
                if key == item then
                    -- Convert slot to number (JSON deserializes numeric keys as strings)
                    local slotNum = tonumber(slot) or slot
                    table.insert(locations, {
                        inventory = name,
                        slot = slotNum,
                        count = slotItem.count,
                    })
                end
            end
        end
        
        ::continue::
    end
    
    -- Only cache if not filtered (full results)
    if not storageOnly then
        itemLocations[item] = locations
    end
    return locations
end

---Find empty slots in inventories (from cache)
---@return table slots Array of {inventory, slot}
function inventory.findEmptySlots()
    local invData = inventoryCache.getAll()
    local empty = {}
    
    for name, data in pairs(invData) do
        if data.size and data.slots then
            for slot = 1, data.size do
                -- Check both numeric and string keys (JSON deserializes numeric keys as strings)
                if not data.slots[slot] and not data.slots[tostring(slot)] then
                    table.insert(empty, {
                        inventory = name,
                        slot = slot,
                    })
                end
            end
        end
    end
    
    return empty
end

---Get detailed item information (cached)
---@param invName string The inventory name
---@param slot number The slot number
---@return table|nil details The item details or nil
function inventory.getItemDetail(invName, slot)
    -- First check the slot in cache
    local invData = inventoryCache.get(invName)
    if not invData or not invData.slots then
        return nil
    end
    
    -- Check both numeric and string keys (JSON deserializes numeric keys as strings)
    local item = invData.slots[slot] or invData.slots[tostring(slot)]
    if not item then
        return nil
    end
    local cacheKey = getDetailCacheKey(item)
    
    -- Check detail cache
    local cached = itemDetailCache.get(cacheKey)
    if cached then
        return cached
    end
    
    -- Fetch from peripheral and cache
    local inv = inventory.getPeripheral(invName)
    if not inv or not inv.getItemDetail then
        return nil
    end
    
    local details = inv.getItemDetail(slot)
    if details then
        -- Store in persistent cache
        itemDetailCache.set(cacheKey, details)
    end
    
    return details
end

---Push items from one inventory slot to another
---Updates cache after transfer (for storage inventories only)
---@param fromInv string Source inventory name
---@param fromSlot number Source slot
---@param toInv string Destination inventory name
---@param count? number Amount to transfer (nil for all)
---@param toSlot? number Destination slot (nil for any)
---@return number transferred Amount actually transferred
function inventory.pushItems(fromInv, fromSlot, toInv, count, toSlot)
    local source = inventory.getPeripheral(fromInv)
    if not source then return 0 end
    
    -- Get item info from cache before transfer
    local invData = inventoryCache.get(fromInv)
    local slotData = nil
    local itemKey = nil
    if invData and invData.slots then
        slotData = invData.slots[fromSlot] or invData.slots[tostring(fromSlot)]
        if slotData then
            itemKey = getItemKey(slotData)
        end
    end
    
    local transferred = source.pushItems(toInv, fromSlot, count, toSlot) or 0
    
    if transferred > 0 and itemKey then
        -- Update source cache (removal)
        updateCacheAfterRemoval(fromInv, fromSlot, itemKey, transferred)
        
        -- Update destination cache if it's a storage inventory we track
        -- Skip scanning/rebuilding during batch operations
        local isStorageDest = inventory.isStorageInventory(toInv)
        if isStorageDest and slotData and not deferredRebuild then
            -- For now, scan destination since we don't know exact slot it went to
            inventory.scanSingle(toInv, true)
            inventory.rebuildFromCache()
        end
    end
    
    return transferred
end

---Pull items from one inventory slot to another
---Updates cache after transfer (for storage inventories only)
---@param toInv string Destination inventory name
---@param fromInv string Source inventory name
---@param fromSlot number Source slot
---@param count? number Amount to transfer (nil for all)
---@param toSlot? number Destination slot (nil for any)
---@return number transferred Amount actually transferred
function inventory.pullItems(toInv, fromInv, fromSlot, count, toSlot)
    local dest = inventory.getPeripheral(toInv)
    if not dest then return 0 end
    
    -- Get item info from source cache before transfer
    local invData = inventoryCache.get(fromInv)
    local slotData = nil
    local itemKey = nil
    if invData and invData.slots then
        slotData = invData.slots[fromSlot] or invData.slots[tostring(fromSlot)]
        if slotData then
            itemKey = getItemKey(slotData)
        end
    end
    
    local transferred = dest.pullItems(fromInv, fromSlot, count, toSlot) or 0
    
    if transferred > 0 and itemKey then
        -- Update source cache if it's a storage inventory
        local isStorageSource = inventory.isStorageInventory(fromInv)
        if isStorageSource then
            updateCacheAfterRemoval(fromInv, fromSlot, itemKey, transferred)
        end
        
        -- Update destination cache if it's a storage inventory we track
        -- Skip scanning/rebuilding during batch operations
        local isStorageDest = inventory.isStorageInventory(toInv)
        if isStorageDest and slotData and not deferredRebuild then
            inventory.scanSingle(toInv, true)
            inventory.rebuildFromCache()
        end
    end
    
    return transferred
end

---Withdraw items to a specific inventory (batch update)
---Uses parallel execution for faster multi-source withdrawals
---Uses internal cache updates instead of rescanning
---@param item string The item ID to withdraw
---@param count number Amount to withdraw
---@param destInv string Destination inventory name
---@param destSlot? number Optional destination slot
---@return number withdrawn Amount actually withdrawn
function inventory.withdraw(item, count, destInv, destSlot)
    local locations = inventory.findItem(item, true)  -- Only from storage inventories
    if #locations == 0 then return 0 end
    
    -- Sort locations by count (largest first) for efficiency
    table.sort(locations, function(a, b) return a.count > b.count end)
    
    local withdrawn = 0
    local maxRetries = 2
    
    -- If we have a specific destSlot, we can't parallelize (items would conflict)
    -- Also don't parallelize if disabled or only 1-2 locations
    if destSlot or not parallelEnabled or #locations <= 2 then
        -- Sequential execution
        for _, loc in ipairs(locations) do
            if withdrawn >= count then break end
            
            local source = inventory.getPeripheral(loc.inventory)
            if source then
                local toWithdraw = math.min(count - withdrawn, loc.count)
                local transferred = 0
                
                for attempt = 1, maxRetries do
                    local result = source.pushItems(destInv, loc.slot, toWithdraw, destSlot)
                    if result and result > 0 then
                        transferred = result
                        break
                    end
                    if attempt < maxRetries then
                        os.queueEvent("yield")
                        os.pullEvent("yield")
                    end
                end
                
                if transferred > 0 then
                    withdrawn = withdrawn + transferred
                    updateCacheAfterRemoval(loc.inventory, loc.slot, item, transferred)
                    if destSlot and transferred < toWithdraw then
                        destSlot = nil
                    end
                end
            end
        end
    else
        -- Parallel execution: build tasks for all needed locations
        local tasks = {}
        local taskMeta = {}  -- Track which location each task corresponds to
        local remaining = count
        
        -- Build task list (limited to what we need)
        for i, loc in ipairs(locations) do
            if remaining <= 0 then break end
            
            local source = inventory.getPeripheral(loc.inventory)
            if source then
                local toWithdraw = math.min(remaining, loc.count)
                remaining = remaining - toWithdraw
                
                table.insert(taskMeta, {
                    loc = loc,
                    toWithdraw = toWithdraw,
                })
                
                table.insert(tasks, function()
                    local transferred = 0
                    for attempt = 1, maxRetries do
                        local result = source.pushItems(destInv, loc.slot, toWithdraw)
                        if result and result > 0 then
                            transferred = result
                            break
                        end
                        if attempt < maxRetries then
                            os.queueEvent("yield")
                            os.pullEvent("yield")
                        end
                    end
                    return transferred
                end)
            end
        end
        
        -- Execute in parallel
        local results = executeParallel(tasks, transferThreads)
        
        -- Process results and update caches
        for i, result in ipairs(results) do
            local transferred = result[1] or 0
            if transferred > 0 then
                withdrawn = withdrawn + transferred
                local meta = taskMeta[i]
                updateCacheAfterRemoval(meta.loc.inventory, meta.loc.slot, item, transferred)
            end
        end
    end
    
    return withdrawn
end

---Deposit items from an inventory into storage (batch update)
---Storage inventories pull from the source (works with turtles)
---Prioritizes filling existing partial stacks before using empty slots
---Uses parallel execution in Phase 2 for faster bulk deposits
---Uses internal cache to find partial stacks and empty slots, updates cache after transfers
---@param sourceInv string Source inventory name (can be a turtle)
---@param item? string Optional item filter (not used when pulling from turtle)
---@return number deposited Amount deposited
function inventory.deposit(sourceInv, item)
    local deposited = 0
    
    logger.debug(string.format("inventory.deposit called: sourceInv=%s, item=%s", sourceInv, tostring(item)))
    
    -- Get storage inventories only - STRICTLY use defined storage type
    local storageInvs = inventory.getStorageInventories()
    logger.debug(string.format("Found %d storage inventories", #storageInvs))
    
    if #storageInvs == 0 then
        -- NO FALLBACK - only use defined storage blocks
        logger.error("No storage inventories found! Configure storagePeripheralType in config.lua")
        logger.error(string.format("Current storage type: %s", storagePeripheralType))
        return 0
    end
    
    -- Pre-wrap all storage peripherals for efficiency (using cached types - no peripheral.getType calls)
    local storagePeripherals = {}
    local storageByName = {}
    for _, name in ipairs(storageInvs) do
        if name ~= sourceInv then
            -- storageInvs already contains only storage-type peripherals,
            -- so we just need to verify the peripheral is still accessible
            local dest = inventory.getPeripheral(name)
            if dest and dest.pullItems then
                local entry = {
                    name = name, 
                    peripheral = dest,
                }
                table.insert(storagePeripherals, entry)
                storageByName[name] = entry
            end
        end
    end
    
    if #storagePeripherals == 0 then
        logger.error("No valid storage peripherals available for deposit!")
        logger.error(string.format("Expected storage type: %s", storagePeripheralType))
        return 0
    end
    
    logger.debug(string.format("Using %d validated storage peripherals for deposit", #storagePeripherals))
    
    -- First, get list of source slots from source inventory (turtle or other inventory)
    -- For turtles, we just iterate 1-16
    local sourceSlots = {}
    local sourcePeripheral = inventory.getPeripheral(sourceInv)
    
    if sourcePeripheral and sourcePeripheral.list then
        -- It's an inventory we can query
        local sourceList = sourcePeripheral.list()
        if sourceList then
            for slot, slotItem in pairs(sourceList) do
                local slotNum = tonumber(slot) or slot
                sourceSlots[slotNum] = slotItem
            end
        end
    else
        -- Assume turtle slots 1-16, we'll discover contents by trying to pull
        for slot = 1, 16 do
            sourceSlots[slot] = true  -- Mark as needing check
        end
    end
    
    -- Track which inventories we've modified (for scanning later)
    local modifiedInventories = {}
    
    -- Phase 1: Try to fill partial stacks first for each item type (sequential - order matters)
    -- This saves storage space by consolidating items
    for slot, slotInfo in pairs(sourceSlots) do
        if slotInfo and type(slotInfo) == "table" and slotInfo.name then
            local itemName = slotInfo.name
            local itemNbt = slotInfo.nbt
            local remaining = slotInfo.count
            
            -- Find partial stacks of this item in storage
            local partialStacks = findPartialStacks(itemName, itemNbt, storageInvs)
            
            for _, partial in ipairs(partialStacks) do
                if remaining <= 0 then break end
                
                local storage = storageByName[partial.inventory]
                if storage then
                    -- Pull up to the available space in this stack
                    local toPull = math.min(remaining, partial.space)
                    local success, pulled = pcall(function()
                        return storage.peripheral.pullItems(sourceInv, slot, toPull, partial.slot)
                    end)
                    
                    if success and pulled and pulled > 0 then
                        logger.debug(string.format("Stack-fill: pulled %d %s from slot %d to %s slot %d", 
                            pulled, itemName, slot, partial.inventory, partial.slot))
                        deposited = deposited + pulled
                        remaining = remaining - pulled
                        modifiedInventories[partial.inventory] = true
                        
                        -- Update the slotInfo count for phase 2
                        slotInfo.count = remaining
                        
                        -- Update cache for this partial stack
                        updateCacheAfterAddition(partial.inventory, partial.slot, itemName, pulled, itemNbt)
                    end
                end
            end
        end
    end
    
    logger.debug(string.format("Phase 1 (stack-fill) complete: deposited %d items so far", deposited))
    
    -- Phase 2: Deposit remaining items to empty slots (can be parallelized)
    -- Build list of slots that still need clearing
    local slotsToDeposit = {}
    for slot = 1, 16 do
        local slotInfo = sourceSlots[slot]
        if slotInfo and (type(slotInfo) ~= "table" or (slotInfo.count and slotInfo.count > 0)) then
            table.insert(slotsToDeposit, slot)
        end
    end
    
    if #slotsToDeposit > 0 and parallelEnabled and #storagePeripherals >= 2 then
        -- Parallel deposit: assign each slot to a different storage peripheral
        local tasks = {}
        local taskMeta = {}
        
        for i, slot in ipairs(slotsToDeposit) do
            -- Round-robin assignment to storage peripherals
            local storageIdx = ((i - 1) % #storagePeripherals) + 1
            local storage = storagePeripherals[storageIdx]
            
            table.insert(taskMeta, {slot = slot, storage = storage})
            table.insert(tasks, function()
                local success, pulled = pcall(function()
                    return storage.peripheral.pullItems(sourceInv, slot)
                end)
                if success and pulled and pulled > 0 then
                    return pulled, storage.name
                end
                return 0, nil
            end)
        end
        
        -- Execute in parallel batches
        local results = executeParallel(tasks, transferThreads)
        
        -- Process results
        for i, result in ipairs(results) do
            local pulled = result[1] or 0
            local storageName = result[2]
            if pulled > 0 and storageName then
                deposited = deposited + pulled
                modifiedInventories[storageName] = true
            end
        end
    else
        -- Sequential fallback (original logic)
        local storageWithSpace = {}
        for _, storage in ipairs(storagePeripherals) do
            local emptySlot = getEmptySlot(storage.name)
            if emptySlot then
                table.insert(storageWithSpace, storage)
            end
        end
        
        local storageIndex = 1
        local emptySlotStreak = 0
        
        for slot = 1, 16 do
            local slotInfo = sourceSlots[slot]
            if slotInfo and (type(slotInfo) ~= "table" or (slotInfo.count and slotInfo.count > 0)) then
                local slotCleared = false
                local attempts = 0
                local maxAttempts = math.min(3, math.max(1, #storageWithSpace))
                
                while not slotCleared and attempts < maxAttempts and #storageWithSpace > 0 do
                    local storage = storageWithSpace[storageIndex]
                    if not storage then
                        storageIndex = 1
                        storage = storageWithSpace[1]
                    end
                    
                    if storage then
                        local success, pulled = pcall(function()
                            return storage.peripheral.pullItems(sourceInv, slot)
                        end)
                        
                        if not success then
                            logger.debug(string.format("Slot %d: pullItems error from %s: %s", slot, storage.name, tostring(pulled)))
                            attempts = attempts + 1
                            storageIndex = (storageIndex % #storageWithSpace) + 1
                        elseif pulled and pulled > 0 then
                            logger.debug(string.format("Slot %d: pulled %d items to %s (empty slot)", slot, pulled, storage.name))
                            deposited = deposited + pulled
                            slotCleared = true
                            emptySlotStreak = 0
                            modifiedInventories[storage.name] = true
                        else
                            local emptySlot = getEmptySlot(storage.name)
                            if not emptySlot then
                                table.remove(storageWithSpace, storageIndex)
                                if storageIndex > #storageWithSpace then
                                    storageIndex = 1
                                end
                            else
                                slotCleared = true
                                emptySlotStreak = emptySlotStreak + 1
                            end
                            attempts = attempts + 1
                        end
                    else
                        break
                    end
                end
                
                if not slotCleared and #storageWithSpace > 0 then
                    emptySlotStreak = emptySlotStreak + 1
                end
            else
                emptySlotStreak = emptySlotStreak + 1
            end
            
            if emptySlotStreak >= 4 and slot >= 12 then
                break
            end
            
            if #storageWithSpace > 0 and slot % 4 == 0 then
                storageIndex = (storageIndex % #storageWithSpace) + 1
            end
        end
    end
    
    logger.debug(string.format("inventory.deposit complete: deposited %d items total", deposited))
    
    -- Scan modified inventories and rebuild cache once at the end
    if deposited > 0 then
        for invName in pairs(modifiedInventories) do
            inventory.scanSingle(invName, true)
        end
        inventory.rebuildFromCache()
    end
    
    return deposited
end

---Clear specific slots from an inventory into storage (batch update)
---Storage inventories pull from the specified slots (works with turtles)
---Prioritizes filling existing partial stacks before using empty slots
---Uses parallel execution in Phase 2 for faster bulk clears
---Uses deferred scanning and batch cache rebuild for efficiency
---@param sourceInv string Source inventory name (can be a turtle)
---@param slots table Array of slot numbers to clear
---@return number cleared Amount of items cleared
function inventory.clearSlots(sourceInv, slots)
    local cleared = 0
    local affectedInventories = {}
    
    logger.debug(string.format("inventory.clearSlots called: sourceInv=%s, slots=%s", sourceInv, textutils.serialize(slots)))
    
    -- Get storage inventories only - STRICTLY use defined storage type
    local storageInvs = inventory.getStorageInventories()
    logger.debug(string.format("Found %d storage inventories for clearSlots", #storageInvs))
    
    if #storageInvs == 0 then
        -- NO FALLBACK - only use defined storage blocks
        logger.error("No storage inventories found for clearSlots! Configure storagePeripheralType in config.lua")
        logger.error(string.format("Current storage type: %s", storagePeripheralType))
        return 0
    end
    
    -- Pre-wrap all storage peripherals for efficiency (using cached types - no peripheral.getType calls)
    local storagePeripherals = {}
    local storageByName = {}
    for _, name in ipairs(storageInvs) do
        if name ~= sourceInv then
            -- storageInvs already contains only storage-type peripherals,
            -- so we just need to verify the peripheral is still accessible
            local dest = inventory.getPeripheral(name)
            if dest and dest.pullItems then
                local entry = {
                    name = name, 
                    peripheral = dest,
                }
                table.insert(storagePeripherals, entry)
                storageByName[name] = entry
            end
        end
    end
    
    if #storagePeripherals == 0 then
        logger.error("No storage peripherals available for clearSlots!")
        return 0
    end
    
    logger.debug(string.format("Using %d storage peripherals for clearSlots", #storagePeripherals))
    
    -- Get source inventory contents to know what items are in each slot
    local sourceSlots = {}
    local sourcePeripheral = inventory.getPeripheral(sourceInv)
    local couldListSource = false
    
    if sourcePeripheral and sourcePeripheral.list then
        local success, sourceList = pcall(function() return sourcePeripheral.list() end)
        if success and sourceList then
            couldListSource = true
            for slot, slotItem in pairs(sourceList) do
                local slotNum = tonumber(slot) or slot
                sourceSlots[slotNum] = slotItem
            end
            logger.debug(string.format("Listed source inventory %s, found items in %d slots", sourceInv, #sourceSlots))
        else
            logger.debug(string.format("Could not list source inventory %s (success=%s)", sourceInv, tostring(success)))
        end
    else
        logger.debug(string.format("Source peripheral %s not available or has no list method", sourceInv))
    end
    
    -- Phase 1: Try to fill partial stacks first for each slot (sequential - order matters)
    for _, slot in ipairs(slots) do
        local slotInfo = sourceSlots[slot]
        if slotInfo and slotInfo.name then
            local itemName = slotInfo.name
            local itemNbt = slotInfo.nbt
            local remaining = slotInfo.count
            
            -- Find partial stacks of this item in storage
            local partialStacks = findPartialStacks(itemName, itemNbt, storageInvs)
            
            for _, partial in ipairs(partialStacks) do
                if remaining <= 0 then break end
                
                local storage = storageByName[partial.inventory]
                if storage then
                    local toPull = math.min(remaining, partial.space)
                    local success, pulled = pcall(function()
                        return storage.peripheral.pullItems(sourceInv, slot, toPull, partial.slot)
                    end)
                    
                    if success and pulled and pulled > 0 then
                        logger.debug(string.format("clearSlots stack-fill: pulled %d %s from slot %d to %s slot %d", 
                            pulled, itemName, slot, partial.inventory, partial.slot))
                        cleared = cleared + pulled
                        remaining = remaining - pulled
                        affectedInventories[partial.inventory] = true
                        
                        -- Update slotInfo for phase 2
                        slotInfo.count = remaining
                        
                        -- Update cache
                        updateCacheAfterAddition(partial.inventory, partial.slot, itemName, pulled, itemNbt)
                    end
                end
            end
        end
    end
    
    logger.debug(string.format("clearSlots Phase 1 (stack-fill) complete: cleared %d items so far", cleared))
    
    -- Phase 2: Clear remaining items to empty slots (can be parallelized)
    -- Build list of slots that still need clearing
    local slotsToClear = {}
    for _, slot in ipairs(slots) do
        local slotInfo = sourceSlots[slot]
        local shouldSkip = false
        if couldListSource then
            if not slotInfo or (slotInfo.count and slotInfo.count <= 0) then
                shouldSkip = true
            end
        end
        if not shouldSkip then
            table.insert(slotsToClear, slot)
        end
    end
    
    if #slotsToClear > 0 and parallelEnabled and #storagePeripherals >= 2 then
        -- Parallel clear: assign each slot to a different storage peripheral
        local tasks = {}
        local taskMeta = {}
        
        for i, slot in ipairs(slotsToClear) do
            -- Round-robin assignment to storage peripherals
            local storageIdx = ((i - 1) % #storagePeripherals) + 1
            local storage = storagePeripherals[storageIdx]
            
            table.insert(taskMeta, {slot = slot, storage = storage})
            table.insert(tasks, function()
                local success, pulled = pcall(function()
                    return storage.peripheral.pullItems(sourceInv, slot)
                end)
                if success and pulled and pulled > 0 then
                    return pulled, storage.name
                end
                return 0, nil
            end)
        end
        
        -- Execute in parallel batches
        local results = executeParallel(tasks, transferThreads)
        
        -- Process results
        for i, result in ipairs(results) do
            local pulled = result[1] or 0
            local storageName = result[2]
            if pulled > 0 and storageName then
                cleared = cleared + pulled
                affectedInventories[storageName] = true
            end
        end
    else
        -- Sequential fallback (original logic)
        local storageWithSpace = {}
        for _, storage in ipairs(storagePeripherals) do
            local emptySlot = getEmptySlot(storage.name)
            if emptySlot then
                table.insert(storageWithSpace, storage)
            end
        end
        
        local storageIndex = 1
        
        for _, slot in ipairs(slotsToClear) do
            local slotCleared = false
            local attempts = 0
            local maxAttempts = math.min(5, math.max(1, #storageWithSpace))
            
            while not slotCleared and attempts < maxAttempts and #storageWithSpace > 0 do
                local storage = storageWithSpace[storageIndex]
                if not storage then
                    storageIndex = 1
                    storage = storageWithSpace[1]
                end
                
                if storage then
                    local success, pulled = pcall(function()
                        return storage.peripheral.pullItems(sourceInv, slot)
                    end)
                    
                    if not success then
                        logger.debug(string.format("clearSlots slot %d: pullItems error from %s: %s", slot, storage.name, tostring(pulled)))
                        storageIndex = (storageIndex % #storageWithSpace) + 1
                        attempts = attempts + 1
                    elseif pulled and pulled > 0 then
                        logger.debug(string.format("clearSlots slot %d: pulled %d items to %s (empty slot)", slot, pulled, storage.name))
                        cleared = cleared + pulled
                        affectedInventories[storage.name] = true
                        slotCleared = true
                    else
                        local emptySlot = getEmptySlot(storage.name)
                        if not emptySlot then
                            table.remove(storageWithSpace, storageIndex)
                            if storageIndex > #storageWithSpace then
                                storageIndex = 1
                            end
                        else
                            slotCleared = true
                        end
                        attempts = attempts + 1
                    end
                else
                    break
                end
            end
            
            if not slotCleared and #storageWithSpace > 0 then
                logger.warn(string.format("clearSlots: failed to clear slot %d after %d attempts", slot, attempts))
            end
        end
    end
    
    logger.debug(string.format("inventory.clearSlots complete: cleared %d items total", cleared))
    
    -- Scan affected inventories with deferred rebuild
    for invName in pairs(affectedInventories) do
        inventory.scanSingle(invName, true)  -- Skip rebuild
    end
    
    -- Rebuild cache once at the end
    if cleared > 0 then
        inventory.rebuildFromCache()
    end
    
    return cleared
end

---Pull a single slot from an inventory into storage
---This is a simplified, more reliable version for turtle clearing.
---The caller provides the slot contents, so we don't need to query the source.
---@param sourceInv string Source inventory name (e.g., turtle network name)
---@param slot number The slot number to pull from
---@param itemName string The item ID in the slot (for stack-filling optimization)
---@param itemCount number The count of items in the slot
---@param itemNbt? string Optional NBT hash for items with NBT
---@return number pulled Amount of items actually pulled
---@return string|nil error Error message if failed
function inventory.pullSlot(sourceInv, slot, itemName, itemCount, itemNbt)
    logger.debug(string.format("inventory.pullSlot: sourceInv=%s, slot=%d, item=%s, count=%d", 
        sourceInv, slot, itemName, itemCount))
    
    if itemCount <= 0 then
        return 0, nil  -- Nothing to pull
    end
    
    -- Get storage inventories - STRICTLY use defined storage type
    local storageInvs = inventory.getStorageInventories()
    if #storageInvs == 0 then
        logger.error("pullSlot: No storage inventories available! Configure storagePeripheralType in config.lua")
        logger.error(string.format("pullSlot: Current storage type: %s", storagePeripheralType))
        return 0, "no_storage"
    end
    
    -- Build a validated list of storage peripherals (using cached types - no peripheral.getType calls)
    local validatedStorage = {}
    for _, name in ipairs(storageInvs) do
        if name ~= sourceInv then
            -- storageInvs already contains only storage-type peripherals,
            -- so we just need to verify the peripheral is still accessible
            local dest = inventory.getPeripheral(name)
            if dest and dest.pullItems then
                table.insert(validatedStorage, name)
            end
        end
    end
    
    if #validatedStorage == 0 then
        logger.error("pullSlot: No valid storage peripherals after validation!")
        return 0, "no_valid_storage"
    end
    
    local totalPulled = 0
    local remaining = itemCount
    
    -- Phase 1: Try to fill partial stacks of the same item first
    -- Filter partial stacks to only include validated storage
    local partialStacks = findPartialStacks(itemName, itemNbt, validatedStorage)
    
    for _, partial in ipairs(partialStacks) do
        if remaining <= 0 then break end
        
        local storage = inventory.getPeripheral(partial.inventory)
        if storage and storage.pullItems then
            local toPull = math.min(remaining, partial.space)
            local success, pulled = pcall(function()
                return storage.pullItems(sourceInv, slot, toPull, partial.slot)
            end)
            
            if success and pulled and pulled > 0 then
                logger.debug(string.format("pullSlot: stack-fill %d to %s slot %d", 
                    pulled, partial.inventory, partial.slot))
                totalPulled = totalPulled + pulled
                remaining = remaining - pulled
                
                -- Update cache
                updateCacheAfterAddition(partial.inventory, partial.slot, itemName, pulled, itemNbt)
            end
        end
    end
    
    -- Phase 2: Pull remaining to validated storage peripherals only
    if remaining > 0 then
        for _, storageName in ipairs(validatedStorage) do
            local storage = inventory.getPeripheral(storageName)
            if storage and storage.pullItems then
                -- Try to pull remaining items
                local success, pulled = pcall(function()
                    return storage.pullItems(sourceInv, slot, remaining)
                end)
                
                if success and pulled and pulled > 0 then
                    logger.debug(string.format("pullSlot: pulled %d to %s (new slot)", 
                        pulled, storageName))
                    totalPulled = totalPulled + pulled
                    remaining = remaining - pulled
                    
                    if remaining <= 0 then
                        break
                    end
                end
            end
        end
    end
    
    if totalPulled > 0 then
        logger.debug(string.format("pullSlot: pulled %d/%d %s from %s slot %d", 
            totalPulled, itemCount, itemName, sourceInv, slot))
    end
    
    if remaining > 0 then
        logger.warn(string.format("pullSlot: could not pull all items (%d/%d remaining)", remaining, itemCount))
        return totalPulled, "partial"
    end
    
    return totalPulled, nil
end

---Pull multiple slots from an inventory into storage in a single batch operation
---This is much faster than calling pullSlot multiple times due to parallel execution.
---@param sourceInv string Source inventory name (e.g., turtle network name)
---@param slotContents table Array of {slot, name, count, nbt?} for each slot to pull
---@return table results Array of {slot, pulled, error?} for each slot
---@return number totalPulled Total items pulled across all slots
function inventory.pullSlotsBatch(sourceInv, slotContents)
    logger.debug(string.format("pullSlotsBatch: sourceInv=%s, %d slots", sourceInv, #slotContents))
    
    if #slotContents == 0 then
        return {}, 0
    end
    
    -- Get storage inventories - STRICTLY use defined storage type
    local storageInvs = inventory.getStorageInventories()
    if #storageInvs == 0 then
        logger.error("pullSlotsBatch: No storage inventories available!")
        local results = {}
        for _, slotInfo in ipairs(slotContents) do
            table.insert(results, {slot = slotInfo.slot, pulled = 0, error = "no_storage"})
        end
        return results, 0
    end
    
    -- Build validated storage peripheral list (using cached types - no peripheral.getType calls)
    local validatedStorage = {}
    for _, name in ipairs(storageInvs) do
        if name ~= sourceInv then
            -- storageInvs already contains only storage-type peripherals,
            -- so we just need to verify the peripheral is still accessible
            local p = inventory.getPeripheral(name)
            if p and p.pullItems then
                table.insert(validatedStorage, {name = name, peripheral = p})
            end
        end
    end
    
    if #validatedStorage == 0 then
        logger.error("pullSlotsBatch: No valid storage peripherals!")
        local results = {}
        for _, slotInfo in ipairs(slotContents) do
            table.insert(results, {slot = slotInfo.slot, pulled = 0, error = "no_valid_storage"})
        end
        return results, 0
    end
    
    -- Use batch mode to defer cache rebuilding
    inventory.beginBatch()
    
    local results = {}
    local totalPulled = 0
    local affectedInventories = {}
    
    -- Phase 1: Fill partial stacks first (sequential to avoid conflicts)
    for _, slotInfo in ipairs(slotContents) do
        local slot = slotInfo.slot
        local itemName = slotInfo.name
        local remaining = slotInfo.count
        local itemNbt = slotInfo.nbt
        local slotPulled = 0
        
        if remaining > 0 then
            -- Find partial stacks of this item in storage
            local partialStacks = findPartialStacks(itemName, itemNbt, storageInvs)
            
            for _, partial in ipairs(partialStacks) do
                if remaining <= 0 then break end
                
                local storage = nil
                for _, s in ipairs(validatedStorage) do
                    if s.name == partial.inventory then
                        storage = s
                        break
                    end
                end
                
                if storage then
                    local toPull = math.min(remaining, partial.space)
                    local success, pulled = pcall(function()
                        return storage.peripheral.pullItems(sourceInv, slot, toPull, partial.slot)
                    end)
                    
                    if success and pulled and pulled > 0 then
                        slotPulled = slotPulled + pulled
                        remaining = remaining - pulled
                        affectedInventories[partial.inventory] = true
                        updateCacheAfterAddition(partial.inventory, partial.slot, itemName, pulled, itemNbt)
                    end
                end
            end
        end
        
        -- Update slotInfo.count for phase 2
        slotInfo._remaining = remaining
        slotInfo._pulled = slotPulled
    end
    
    -- Phase 2: Pull remaining items to empty slots in parallel
    local slotsNeedingEmptySpace = {}
    for i, slotInfo in ipairs(slotContents) do
        if slotInfo._remaining and slotInfo._remaining > 0 then
            table.insert(slotsNeedingEmptySpace, {index = i, slotInfo = slotInfo})
        end
    end
    
    if #slotsNeedingEmptySpace > 0 and parallelEnabled and #validatedStorage >= 1 then
        -- Build parallel tasks - round-robin assignment to storage
        local tasks = {}
        local taskMeta = {}
        
        for i, entry in ipairs(slotsNeedingEmptySpace) do
            local slotInfo = entry.slotInfo
            local storageIdx = ((i - 1) % #validatedStorage) + 1
            local storage = validatedStorage[storageIdx]
            
            table.insert(taskMeta, {index = entry.index, slotInfo = slotInfo, storage = storage})
            table.insert(tasks, function()
                local success, pulled = pcall(function()
                    return storage.peripheral.pullItems(sourceInv, slotInfo.slot, slotInfo._remaining)
                end)
                if success and pulled and pulled > 0 then
                    return pulled, storage.name
                end
                return 0, nil
            end)
        end
        
        -- Execute in parallel
        local parallelResults = executeParallel(tasks, transferThreads)
        
        -- Process results
        for i, result in ipairs(parallelResults) do
            local pulled = result[1] or 0
            local storageName = result[2]
            local meta = taskMeta[i]
            
            if pulled > 0 and storageName then
                meta.slotInfo._pulled = (meta.slotInfo._pulled or 0) + pulled
                meta.slotInfo._remaining = (meta.slotInfo._remaining or 0) - pulled
                affectedInventories[storageName] = true
            end
        end
    else
        -- Sequential fallback
        for _, entry in ipairs(slotsNeedingEmptySpace) do
            local slotInfo = entry.slotInfo
            local remaining = slotInfo._remaining
            
            for _, storage in ipairs(validatedStorage) do
                if remaining <= 0 then break end
                
                local success, pulled = pcall(function()
                    return storage.peripheral.pullItems(sourceInv, slotInfo.slot, remaining)
                end)
                
                if success and pulled and pulled > 0 then
                    slotInfo._pulled = (slotInfo._pulled or 0) + pulled
                    remaining = remaining - pulled
                    slotInfo._remaining = remaining
                    affectedInventories[storage.name] = true
                end
            end
        end
    end
    
    -- Build final results
    for _, slotInfo in ipairs(slotContents) do
        local pulled = slotInfo._pulled or 0
        local remaining = slotInfo._remaining or 0
        totalPulled = totalPulled + pulled
        
        local err = nil
        if remaining > 0 then
            err = "partial"
        end
        
        table.insert(results, {
            slot = slotInfo.slot,
            pulled = pulled,
            error = err,
        })
    end
    
    -- Scan affected inventories with deferred rebuild
    for invName in pairs(affectedInventories) do
        inventory.scanSingle(invName, true)
    end
    
    -- End batch and rebuild cache once
    inventory.endBatch()
    
    logger.debug(string.format("pullSlotsBatch: pulled %d total items from %d slots", totalPulled, #slotContents))
    
    return results, totalPulled
end

---@return number seconds Time since last scan in seconds
function inventory.timeSinceLastScan()
    return os.clock() - lastScanTime
end

---Get last scan timestamp
---@return number timestamp UTC epoch of last scan
function inventory.getLastScanTime()
    return stockCache.get("lastScan") or 0
end

---Get list of connected inventories (cached)
---@return table names Array of inventory names
function inventory.getInventoryNames()
    if #inventoryNames > 0 then
        return inventoryNames
    end
    
    -- Try to rebuild from cache
    local invData = inventoryCache.getAll()
    local names = {}
    for name in pairs(invData) do
        table.insert(names, name)
    end
    table.sort(names)
    inventoryNames = names
    
    return inventoryNames
end

---Get inventory details from cache
---@param name string The inventory name
---@return table|nil details The inventory details or nil
function inventory.getInventoryDetails(name)
    return inventoryCache.get(name)
end

---Count total slots across all inventories (from cache)
---@return number total Total slots
---@return number used Used slots
---@return number free Free slots
function inventory.slotCounts()
    local invData = inventoryCache.getAll()
    local total = 0
    local used = 0
    
    for _, data in pairs(invData) do
        if data.size then
            total = total + data.size
        end
        if data.slots then
            for _ in pairs(data.slots) do
                used = used + 1
            end
        end
    end
    
    return total, used, total - used
end

---Clear all caches (for debugging/reset)
function inventory.clearCaches()
    inventoryCache.setAll({})
    itemDetailCache.setAll({})
    stockCache.setAll({})
    wrappedPeripherals = {}
    itemLocations = {}
    inventoryNames = {}
    inventorySizes = {}
    emptySlotCache = {}
    lastScanTime = 0
    lastFullScan = 0
    stockLevelsDirty = true
end

---Get cache statistics
---@return table stats Cache statistics
function inventory.getCacheStats()
    local invData = inventoryCache.getAll()
    local detailCount = 0
    for _ in pairs(itemDetailCache.getAll()) do
        detailCount = detailCount + 1
    end
    
    local invCount = 0
    for _ in pairs(invData) do
        invCount = invCount + 1
    end
    
    local wrappedCount = 0
    for _ in pairs(wrappedPeripherals) do
        wrappedCount = wrappedCount + 1
    end
    
    local emptySlotCount = 0
    local inventoriesWithEmpty = 0
    for invName, slots in pairs(emptySlotCache) do
        local slotCount = 0
        for _ in pairs(slots) do
            slotCount = slotCount + 1
        end
        emptySlotCount = emptySlotCount + slotCount
        if slotCount > 0 then
            inventoriesWithEmpty = inventoriesWithEmpty + 1
        end
    end
    
    return {
        inventories = invCount,
        itemDetails = detailCount,
        wrappedPeripherals = wrappedCount,
        emptySlots = emptySlotCount,
        inventoriesWithEmptySlots = inventoriesWithEmpty,
        stockLevelsDirty = stockLevelsDirty,
        lastScan = lastFullScan,
        timeSinceScan = os.clock() - lastScanTime,
    }
end

---Initialize from persistent cache if available
function inventory.init()
    -- Try to load from persistent cache
    local levels = stockCache.get("levels")
    if levels then
        -- Rebuild item locations from inventory cache
        inventory.rebuildFromCache()
    end
    
    -- Ensure we have modem cached
    inventory.getModem()
    
    -- Try to find manipulator peripheral
    inventory.getManipulator()
end

---Get the manipulator peripheral (for player inventory access)
---@return table|nil manipulator The manipulator peripheral or nil
function inventory.getManipulator()
    if manipulator then
        return manipulator
    end
    
    -- Look for a manipulator peripheral (plethora neural interface)
    manipulator = peripheral.find("manipulator")
    
    return manipulator
end

---Check if manipulator is available
---@return boolean available Whether manipulator is available
function inventory.hasManipulator()
    return inventory.getManipulator() ~= nil
end

---Get player inventory via manipulator introspection
---@param playerName string The player name to get inventory for
---@return table|nil playerInv The player's inventory wrapper or nil
function inventory.getPlayerInventory(playerName)
    local manip = inventory.getManipulator()
    if not manip then
        return nil
    end
    
    -- Use introspection module to get player inventory
    -- The manipulator must have the introspection module and target the player
    if manip.getInventory then
        local success, inv = pcall(manip.getInventory)
        if success and inv then
            return inv
        end
    end
    
    return nil
end

---Withdraw items to a player's inventory via manipulator
---@param item string The item ID to withdraw
---@param count number Amount to withdraw  
---@param playerName string The player name to send items to
---@return number withdrawn Amount actually withdrawn
---@return string|nil error Error message if failed
function inventory.withdrawToPlayer(item, count, playerName)
    local manip = inventory.getManipulator()
    if not manip then
        return 0, "No manipulator available"
    end
    
    -- Get player's inventory via introspection
    local playerInv = nil
    if manip.getInventory then
        local success, inv = pcall(manip.getInventory)
        if success and inv then
            playerInv = inv
        end
    end
    
    if not playerInv then
        return 0, "Cannot access player inventory"
    end
    
    -- Find items in storage only (not in export inventories)
    local locations = inventory.findItem(item, true)
    if #locations == 0 then
        return 0, "Item not found in storage"
    end
    
    local withdrawn = 0
    local invData = inventoryCache.getAll()
    
    for _, loc in ipairs(locations) do
        if withdrawn >= count then break end
        
        local source = inventory.getPeripheral(loc.inventory)
        if source then
            local toWithdraw = math.min(count - withdrawn, loc.count)
            
            -- Push items from storage to player inventory
            local transferred = 0
            if playerInv.pullItems then
                -- Player inventory can pull from storage
                local success, result = pcall(playerInv.pullItems, loc.inventory, loc.slot, toWithdraw)
                if success then
                    transferred = result or 0
                end
            end
            
            withdrawn = withdrawn + transferred
            
            -- Update cache directly instead of rescanning
            if transferred > 0 then
                updateCacheAfterRemoval(loc.inventory, loc.slot, item, transferred)
            end
        end
    end
    
    if withdrawn == 0 then
        return 0, "Failed to transfer items"
    end
    
    return withdrawn, nil
end

---Deposit items from a player's inventory via manipulator
---@param playerName string The player name to get items from
---@param item? string|table Optional item filter(s) (nil for all items, string for single, table for multiple)
---@param maxCount? number Optional max items to deposit (nil for all)
---@param excludes? table Optional array of item IDs to exclude from deposit
---@return number deposited Amount deposited
---@return string|nil error Error message if failed
function inventory.depositFromPlayer(playerName, item, maxCount, excludes)
    local manip = inventory.getManipulator()
    if not manip then
        return 0, "No manipulator available"
    end
    
    -- Get player's inventory via introspection
    local playerInv = nil
    if manip.getInventory then
        local success, inv = pcall(manip.getInventory)
        if success and inv then
            playerInv = inv
        end
    end
    
    if not playerInv then
        return 0, "Cannot access player inventory"
    end
    
    -- List items in player inventory
    local playerItems = nil
    if playerInv.list then
        local success, list = pcall(playerInv.list)
        if success then
            playerItems = list
        end
    end
    
    if not playerItems then
        return 0, "Cannot list player inventory"
    end
    
    -- Build filter set from item param (can be string or table of strings)
    local filterSet = nil
    if item then
        filterSet = {}
        if type(item) == "string" then
            filterSet[item] = true
        elseif type(item) == "table" then
            for _, i in ipairs(item) do
                filterSet[i] = true
            end
        end
    end
    
    -- Build exclude set
    local excludeSet = {}
    if excludes then
        for _, ex in ipairs(excludes) do
            excludeSet[ex] = true
        end
    end
    
    local deposited = 0
    local remaining = maxCount  -- nil means unlimited
    local affectedInventories = {}
    local invData = inventoryCache.getAll()
    
    for slot, slotItem in pairs(playerItems) do
        -- Check if we've reached the max count
        if remaining and remaining <= 0 then
            break
        end
        
        -- Check excludes first (before filters)
        local isExcluded = excludeSet[slotItem.name]
        if not isExcluded and excludes then
            -- Also check partial matches for pattern excludes
            for _, ex in ipairs(excludes) do
                if slotItem.name:find(ex, 1, true) then
                    isExcluded = true
                    break
                end
            end
        end
        if isExcluded then
            goto continue
        end
        
        -- Filter by item(s) if specified (support partial matching)
        local matches = not filterSet
        if filterSet then
            -- Check exact match first
            if filterSet[slotItem.name] then
                matches = true
            else
                -- Check partial matches
                for filterItem in pairs(filterSet) do
                    local searchPart = filterItem:gsub("minecraft:", ""):lower()
                    if slotItem.name:lower():find(searchPart, 1, true) then
                        matches = true
                        break
                    end
                end
            end
        end
        
        if matches then
            -- Calculate how many to transfer from this slot
            local toTransfer = slotItem.count
            if remaining then
                toTransfer = math.min(toTransfer, remaining)
            end
            
            -- Find a destination storage inventory (only use storage inventories)
            local storageInvs = inventory.getStorageInventories()
            for _, name in ipairs(storageInvs) do
                local dest = inventory.getPeripheral(name)
                if dest then
                    -- Push from player inventory to storage
                    local transferred = 0
                    if playerInv.pushItems then
                        local success, result = pcall(playerInv.pushItems, name, slot, toTransfer)
                        if success then
                            transferred = result or 0
                        end
                    end
                    
                    if transferred and transferred > 0 then
                        deposited = deposited + transferred
                        if remaining then
                            remaining = remaining - transferred
                        end
                        affectedInventories[name] = true
                        break
                    end
                end
            end
        end
        
        ::continue::
    end
    
    -- Batch update affected inventories
    for invName in pairs(affectedInventories) do
        inventory.scanSingle(invName)
    end
    
    if deposited == 0 and not filterSet then
        return 0, "No items to deposit or failed to transfer"
    elseif deposited == 0 then
        return 0, "Item not found in player inventory or failed to transfer"
    end
    
    return deposited, nil
end

inventory.VERSION = VERSION

return inventory
