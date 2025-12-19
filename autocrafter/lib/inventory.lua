--- AutoCrafter Inventory Library
--- Manages inventory scanning and item storage with comprehensive caching.
--- All peripheral calls are cached to minimize network/peripheral overhead.
---
---@version 2.0.0

local VERSION = "2.0.0"

-- Ensure cache directory exists
fs.makeDir("data/cache")

local persist = require("lib.persist")

local inventory = {}

-- Persistent caches
local inventoryCache = persist("cache/inventories.json")
local itemDetailCache = persist("cache/item-details.json")
local stockCache = persist("cache/stock.json")

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
    
    for _, name in ipairs(invNames) do
        local inv = inventory.getPeripheral(name)
        if inv then
            local list = inv.list()
            if list then
                local size = inventory.getSize(name)
                
                newInventoryData[name] = {
                    slots = list,
                    size = size,
                }
                
                for slot, item in pairs(list) do
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
---@return table slots The slots in that inventory
function inventory.scanSingle(name)
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
    
    -- Rebuild stock levels and locations from cached inventory data
    inventory.rebuildFromCache()
    
    return list
end

---Rebuild stock levels and item locations from cached inventory data
---@return table stockLevels The rebuilt stock levels
function inventory.rebuildFromCache()
    local invData = inventoryCache.getAll()
    local newStockLevels = {}
    itemLocations = {}
    
    for name, data in pairs(invData) do
        if data.slots then
            for slot, item in pairs(data.slots) do
                local key = getItemKey(item)
                
                newStockLevels[key] = (newStockLevels[key] or 0) + item.count
                
                if not itemLocations[key] then
                    itemLocations[key] = {}
                end
                table.insert(itemLocations[key], {
                    inventory = name,
                    slot = slot,
                    count = item.count,
                })
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
                    table.insert(locations, {
                        inventory = name,
                        slot = slot,
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
                if not data.slots[slot] then
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
    if not invData or not invData.slots or not invData.slots[slot] then
        return nil
    end
    
    local item = invData.slots[slot]
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
---Updates cache after transfer
---@param fromInv string Source inventory name
---@param fromSlot number Source slot
---@param toInv string Destination inventory name
---@param count? number Amount to transfer (nil for all)
---@param toSlot? number Destination slot (nil for any)
---@return number transferred Amount actually transferred
function inventory.pushItems(fromInv, fromSlot, toInv, count, toSlot)
    local source = inventory.getPeripheral(fromInv)
    if not source then return 0 end
    
    local transferred = source.pushItems(toInv, fromSlot, count, toSlot) or 0
    
    if transferred > 0 then
        -- Update cache for both inventories
        inventory.scanSingle(fromInv)
        inventory.scanSingle(toInv)
    end
    
    return transferred
end

---Pull items from one inventory slot to another
---Updates cache after transfer
---@param toInv string Destination inventory name
---@param fromInv string Source inventory name
---@param fromSlot number Source slot
---@param count? number Amount to transfer (nil for all)
---@param toSlot? number Destination slot (nil for any)
---@return number transferred Amount actually transferred
function inventory.pullItems(toInv, fromInv, fromSlot, count, toSlot)
    local dest = inventory.getPeripheral(toInv)
    if not dest then return 0 end
    
    local transferred = dest.pullItems(fromInv, fromSlot, count, toSlot) or 0
    
    if transferred > 0 then
        -- Update cache for both inventories
        inventory.scanSingle(fromInv)
        inventory.scanSingle(toInv)
    end
    
    return transferred
end

---Withdraw items to a specific inventory (batch update)
---@param item string The item ID to withdraw
---@param count number Amount to withdraw
---@param destInv string Destination inventory name
---@param destSlot? number Optional destination slot
---@return number withdrawn Amount actually withdrawn
function inventory.withdraw(item, count, destInv, destSlot)
    local locations = inventory.findItem(item)
    if #locations == 0 then return 0 end
    
    local withdrawn = 0
    local affectedInventories = {[destInv] = true}
    
    for _, loc in ipairs(locations) do
        if withdrawn >= count then break end
        
        local source = inventory.getPeripheral(loc.inventory)
        if source then
            local toWithdraw = math.min(count - withdrawn, loc.count)
            local transferred = source.pushItems(destInv, loc.slot, toWithdraw, destSlot) or 0
            withdrawn = withdrawn + transferred
            
            if transferred > 0 then
                affectedInventories[loc.inventory] = true
            end
        end
    end
    
    -- Batch update affected inventories
    for invName in pairs(affectedInventories) do
        inventory.scanSingle(invName)
    end
    
    return withdrawn
end

---Deposit items from an inventory into storage (batch update)
---Only deposits to storage-type inventories (configured via setStorageType)
---@param sourceInv string Source inventory name
---@param item? string Optional item filter
---@return number deposited Amount deposited
function inventory.deposit(sourceInv, item)
    local source = inventory.getPeripheral(sourceInv)
    if not source then return 0 end
    
    local deposited = 0
    local sourceList = source.list()
    
    if not sourceList then return 0 end
    
    local affectedInventories = {[sourceInv] = true}
    
    -- Get storage inventories only
    local storageInvs = inventory.getStorageInventories()
    if #storageInvs == 0 then
        -- Fall back to all cached inventories if no storage type found
        local invData = inventoryCache.getAll()
        for name in pairs(invData) do
            if name ~= sourceInv then
                table.insert(storageInvs, name)
            end
        end
    end
    
    for slot, slotItem in pairs(sourceList) do
        if not item or slotItem.name == item then
            -- Find a destination from storage inventories
            for _, name in ipairs(storageInvs) do
                if name ~= sourceInv then
                    local transferred = source.pushItems(name, slot)
                    deposited = deposited + (transferred or 0)
                    
                    if transferred and transferred > 0 then
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
    
    return deposited
end

---Get time since last scan
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
    lastScanTime = 0
    lastFullScan = 0
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
    
    return {
        inventories = invCount,
        itemDetails = detailCount,
        wrappedPeripherals = wrappedCount,
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
    local affectedInventories = {}
    
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
            
            if transferred > 0 then
                affectedInventories[loc.inventory] = true
            end
        end
    end
    
    -- Batch update affected inventories
    for invName in pairs(affectedInventories) do
        inventory.scanSingle(invName)
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
