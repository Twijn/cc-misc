--- AutoCrafter Inventory Library
--- Manages inventory scanning and item storage with comprehensive caching.
--- All peripheral calls are cached to minimize network/peripheral overhead.
--- Uses internal cache updates after transfers instead of rescanning.
---
---@version 3.0.0

local VERSION = "3.0.0"

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

-- Runtime state (not persisted)
local wrappedPeripherals = {}  -- Cached peripheral.wrap() results
local itemLocations = {}       -- Map of item -> locations
local lastScanTime = 0
local lastFullScan = 0
local inventoryNames = {}      -- Cached list of inventory names
local inventorySizes = {}      -- Cached inventory sizes
local inventoryTypes = {}      -- Cached peripheral types for each inventory
local storageInventories = {}  -- Cached list of storage-type inventory names
local storagePeripheralType = "sc-goodies:diamond_barrel"  -- Default storage type
local modemPeripheral = nil    -- Cached modem peripheral
local modemName = nil          -- Cached modem name
local scanInProgress = false
local manipulator = nil        -- Cached manipulator peripheral
local deferredRebuild = false  -- Flag to defer cache rebuilding for batch operations
local emptySlotCache = {}      -- Cache of empty slots per inventory: {invName = {slot1, slot2, ...}}
local stockLevelsDirty = false -- Flag to indicate stock levels need recalculation

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
            end
        end
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
    
    for name, data in pairs(scanResults) do
        newInventoryData[name] = data
        emptySlotCache[name] = {}
        
        for slot, item in pairs(data.slots) do
            local key = getItemKey(item)
            
            -- Update stock levels
            newStockLevels[key] = (newStockLevels[key] or 0) + item.count
            
            -- Track item locations (runtime only)
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
    
    for name, data in pairs(invData) do
        emptySlotCache[name] = {}
        
        if data.slots then
            for slot, item in pairs(data.slots) do
                local key = getItemKey(item)
                -- Convert slot to number (JSON deserializes numeric keys as strings)
                local slotNum = tonumber(slot) or slot
                
                newStockLevels[key] = (newStockLevels[key] or 0) + item.count
                
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
---@return table locations Array of {inventory, slot, count}
function inventory.findItem(item)
    -- First check runtime cache
    if itemLocations[item] and #itemLocations[item] > 0 then
        return itemLocations[item]
    end
    
    -- Rebuild from persistent cache if needed
    local invData = inventoryCache.getAll()
    local locations = {}
    
    for name, data in pairs(invData) do
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
    end
    
    itemLocations[item] = locations
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
        local isStorageDest = inventory.isStorageInventory(toInv)
        if isStorageDest and slotData then
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
        local isStorageDest = inventory.isStorageInventory(toInv)
        if isStorageDest and slotData then
            inventory.scanSingle(toInv, true)
            inventory.rebuildFromCache()
        end
    end
    
    return transferred
end

---Withdraw items to a specific inventory (batch update)
---Uses internal cache updates instead of rescanning
---@param item string The item ID to withdraw
---@param count number Amount to withdraw
---@param destInv string Destination inventory name
---@param destSlot? number Optional destination slot
---@return number withdrawn Amount actually withdrawn
function inventory.withdraw(item, count, destInv, destSlot)
    local locations = inventory.findItem(item)
    if #locations == 0 then return 0 end
    
    -- Sort locations by count (largest first) for efficiency
    table.sort(locations, function(a, b) return a.count > b.count end)
    
    local withdrawn = 0
    local maxRetries = 2
    
    for _, loc in ipairs(locations) do
        if withdrawn >= count then break end
        
        local source = inventory.getPeripheral(loc.inventory)
        if source then
            local toWithdraw = math.min(count - withdrawn, loc.count)
            local transferred = 0
            
            -- Try with retries for reliability
            for attempt = 1, maxRetries do
                local result = source.pushItems(destInv, loc.slot, toWithdraw, destSlot)
                if result and result > 0 then
                    transferred = result
                    break
                end
                if attempt < maxRetries then
                    -- Small yield before retry
                    os.queueEvent("yield")
                    os.pullEvent("yield")
                end
            end
            
            if transferred > 0 then
                withdrawn = withdrawn + transferred
                
                -- Update cache directly instead of rescanning
                updateCacheAfterRemoval(loc.inventory, loc.slot, item, transferred)
                
                -- If we're pushing to a specific slot and it's now full, 
                -- clear destSlot so next push can go anywhere
                if destSlot and transferred < toWithdraw then
                    destSlot = nil
                end
            end
        end
    end
    
    return withdrawn
end

---Deposit items from an inventory into storage (batch update)
---Storage inventories pull from the source (works with turtles)
---Uses internal cache to find empty slots and updates cache after transfers
---@param sourceInv string Source inventory name (can be a turtle)
---@param item? string Optional item filter (not used when pulling from turtle)
---@return number deposited Amount deposited
function inventory.deposit(sourceInv, item)
    local deposited = 0
    
    logger.debug(string.format("inventory.deposit called: sourceInv=%s, item=%s", sourceInv, tostring(item)))
    
    -- Get storage inventories only
    local storageInvs = inventory.getStorageInventories()
    logger.debug(string.format("Found %d storage inventories", #storageInvs))
    
    if #storageInvs == 0 then
        -- Fall back to all cached inventories if no storage type found
        logger.warn("No storage inventories found, falling back to all cached inventories")
        local invData = inventoryCache.getAll()  
        for name in pairs(invData) do
            if name ~= sourceInv then
                table.insert(storageInvs, name)
            end
        end
        logger.debug(string.format("Fallback found %d inventories", #storageInvs))
    end
    
    -- Pre-wrap all storage peripherals for efficiency
    local storagePeripherals = {}
    for _, name in ipairs(storageInvs) do
        if name ~= sourceInv then
            local dest = inventory.getPeripheral(name)
            if dest and dest.pullItems then
                -- Get or build empty slot cache for this inventory
                local emptySlot = getEmptySlot(name)
                table.insert(storagePeripherals, {
                    name = name, 
                    peripheral = dest,
                    hasSpace = emptySlot ~= nil
                })
            end
        end
    end
    
    if #storagePeripherals == 0 then
        logger.error("No storage peripherals available for deposit!")
        return 0
    end
    
    -- Sort so inventories with space come first
    table.sort(storagePeripherals, function(a, b)
        if a.hasSpace ~= b.hasSpace then
            return a.hasSpace
        end
        return false
    end)
    
    logger.debug(string.format("Using %d storage peripherals for deposit", #storagePeripherals))
    
    -- For each slot in the source (turtle has 16 slots), try to deposit
    local storageIndex = 1
    local emptySlotStreak = 0
    
    for slot = 1, 16 do
        local slotCleared = false
        local attempts = 0
        local maxAttempts = math.min(3, #storagePeripherals)
        
        while not slotCleared and attempts < maxAttempts do
            local storage = storagePeripherals[storageIndex]
            local success, pulled = pcall(function()
                return storage.peripheral.pullItems(sourceInv, slot)
            end)
            
            if not success then
                logger.debug(string.format("Slot %d: pullItems error from %s: %s", slot, storage.name, tostring(pulled)))
                attempts = attempts + 1
                storageIndex = (storageIndex % #storagePeripherals) + 1
            elseif pulled and pulled > 0 then
                logger.debug(string.format("Slot %d: pulled %d items to %s", slot, pulled, storage.name))
                deposited = deposited + pulled
                slotCleared = true
                emptySlotStreak = 0
                
                -- We received items into storage - update cache
                -- Since we don't know the exact slot/item, we need to scan this inventory
                -- But defer the rebuild until the end
                inventory.scanSingle(storage.name, true)
            else
                attempts = attempts + 1
                storageIndex = (storageIndex % #storagePeripherals) + 1
            end
        end
        
        if not slotCleared then
            emptySlotStreak = emptySlotStreak + 1
        end
        
        -- Early exit: if 4+ consecutive empty slots at end, likely done
        if emptySlotStreak >= 4 and slot >= 12 then
            break
        end
        
        if slot % 4 == 0 then
            storageIndex = (storageIndex % #storagePeripherals) + 1
        end
    end
    
    logger.debug(string.format("inventory.deposit complete: deposited %d items", deposited))
    
    -- Rebuild cache once at the end if we deposited anything
    if deposited > 0 then
        inventory.rebuildFromCache()
    end
    
    return deposited
end

---Clear specific slots from an inventory into storage (batch update)
---Storage inventories pull from the specified slots (works with turtles)
---Uses deferred scanning and batch cache rebuild for efficiency
---@param sourceInv string Source inventory name (can be a turtle)
---@param slots table Array of slot numbers to clear
---@return number cleared Amount of items cleared
function inventory.clearSlots(sourceInv, slots)
    local cleared = 0
    local affectedInventories = {}
    
    logger.debug(string.format("inventory.clearSlots called: sourceInv=%s, slots=%s", sourceInv, textutils.serialize(slots)))
    
    -- Get storage inventories only
    local storageInvs = inventory.getStorageInventories()
    logger.debug(string.format("Found %d storage inventories for clearSlots", #storageInvs))
    
    if #storageInvs == 0 then
        -- Fall back to all cached inventories if no storage type found
        logger.warn("No storage inventories found for clearSlots, falling back to all cached inventories")
        local invData = inventoryCache.getAll()
        for name in pairs(invData) do
            if name ~= sourceInv then
                table.insert(storageInvs, name)
            end
        end
    end
    
    -- Pre-wrap all storage peripherals for efficiency
    -- Prioritize inventories with empty slots
    local storagePeripherals = {}
    for _, name in ipairs(storageInvs) do
        if name ~= sourceInv then
            local dest = inventory.getPeripheral(name)
            if dest and dest.pullItems then
                local emptySlot = getEmptySlot(name)
                table.insert(storagePeripherals, {
                    name = name, 
                    peripheral = dest,
                    hasSpace = emptySlot ~= nil
                })
            end
        end
    end
    
    if #storagePeripherals == 0 then
        logger.error("No storage peripherals available for clearSlots!")
        return 0
    end
    
    -- Sort so inventories with space come first
    table.sort(storagePeripherals, function(a, b)
        if a.hasSpace ~= b.hasSpace then
            return a.hasSpace
        end
        return false
    end)
    
    logger.debug(string.format("Using %d storage peripherals for clearSlots", #storagePeripherals))
    
    local storageIndex = 1
    
    for _, slot in ipairs(slots) do
        local slotCleared = false
        local attempts = 0
        local maxAttempts = math.min(5, #storagePeripherals)
        
        while not slotCleared and attempts < maxAttempts do
            local storage = storagePeripherals[storageIndex]
            local success, pulled = pcall(function()
                return storage.peripheral.pullItems(sourceInv, slot)
            end)
            
            if not success then
                logger.debug(string.format("clearSlots slot %d: pullItems error from %s: %s", slot, storage.name, tostring(pulled)))
                storageIndex = (storageIndex % #storagePeripherals) + 1
                attempts = attempts + 1
            elseif pulled and pulled > 0 then
                logger.debug(string.format("clearSlots slot %d: pulled %d items to %s", slot, pulled, storage.name))
                cleared = cleared + pulled
                affectedInventories[storage.name] = true
                slotCleared = true
            else
                storageIndex = (storageIndex % #storagePeripherals) + 1
                attempts = attempts + 1
            end
        end
        
        if not slotCleared then
            logger.warn(string.format("clearSlots: failed to clear slot %d after %d attempts", slot, attempts))
        end
    end
    
    logger.debug(string.format("inventory.clearSlots complete: cleared %d items", cleared))
    
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
    
    -- Find items in storage
    local locations = inventory.findItem(item)
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
                updateCacheAfterRemoval(loc.inventory, loc.slot, loc.name, transferred)
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
---@param item? string Optional item filter (nil for all items)
---@param maxCount? number Optional max items to deposit (nil for all)
---@return number deposited Amount deposited
---@return string|nil error Error message if failed
function inventory.depositFromPlayer(playerName, item, maxCount)
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
    
    local deposited = 0
    local remaining = maxCount  -- nil means unlimited
    local affectedInventories = {}
    local invData = inventoryCache.getAll()
    
    for slot, slotItem in pairs(playerItems) do
        -- Check if we've reached the max count
        if remaining and remaining <= 0 then
            break
        end
        
        -- Filter by item if specified (support partial matching)
        local matches = not item
        if item then
            matches = slotItem.name == item or slotItem.name:lower():find(item:lower():gsub("minecraft:", ""), 1, true)
        end
        
        if matches then
            -- Calculate how many to transfer from this slot
            local toTransfer = slotItem.count
            if remaining then
                toTransfer = math.min(toTransfer, remaining)
            end
            
            -- Find a destination storage inventory
            for name in pairs(invData) do
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
    end
    
    -- Batch update affected inventories
    for invName in pairs(affectedInventories) do
        inventory.scanSingle(invName)
    end
    
    if deposited == 0 and not item then
        return 0, "No items to deposit or failed to transfer"
    elseif deposited == 0 then
        return 0, "Item not found in player inventory or failed to transfer"
    end
    
    return deposited, nil
end

inventory.VERSION = VERSION

return inventory
