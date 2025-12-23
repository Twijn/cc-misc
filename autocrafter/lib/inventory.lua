--- AutoCrafter Inventory Library
--- Manages inventory scanning and item transfers for massive storage systems.
--- Optimized for hundreds of diamond barrels (108 slots each) with parallel operations.
---
---@version 4.0.0

local VERSION = "4.0.0"

local persist = require("lib.persist")
local logger = require("lib.log")
local config = require("config")

local inventory = {}

-- Cache path and persistent storage
local cachePath = config.cachePath or "/disk/data/cache"
fs.makeDir(cachePath)

local stockCache = persist(cachePath .. "/stock.json")
local detailCache = persist(cachePath .. "/item-details.json")

-- Config
local storageType = config.storagePeripheralType or "sc-goodies:diamond_barrel"
local threadCount = (config.parallelism or {}).transferThreads or 8

-- Runtime state (rebuilt on scan)
local peripherals = {}      -- name -> wrapped peripheral
local sizes = {}            -- name -> slot count  
local storage = {}          -- array of storage inventory names
local slots = {}            -- name -> {slot -> {name, count, nbt?}}
local items = {}            -- itemKey -> {{inv, slot, count}, ...}
local stock = {}            -- itemKey -> total count

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

---Get item key for tracking
---@param item table|string Item data or item name
---@param nbt? string NBT hash
---@return string
local function key(item, nbt)
    if type(item) == "table" then
        return item.nbt and (item.name .. ":" .. item.nbt) or item.name
    end
    return nbt and (item .. ":" .. nbt) or item
end

---Get or wrap a peripheral
---@param name string Peripheral name
---@return table? peripheral
local function wrap(name)
    if not peripherals[name] then
        peripherals[name] = peripheral.wrap(name)
    end
    return peripherals[name]
end

---Run tasks in parallel batches
---@param tasks function[] Functions to execute
---@param limit? number Max concurrent (default threadCount)
---@return any[][] Results array
local function parallel_run(tasks, limit)
    if #tasks == 0 then return {} end
    limit = limit or threadCount
    
    local results = {}
    for batch = 1, #tasks, limit do
        local batchEnd = math.min(batch + limit - 1, #tasks)
        local batchFns = {}
        
        for i = batch, batchEnd do
            local idx = i
            batchFns[#batchFns + 1] = function()
                results[idx] = {tasks[idx]()}
            end
        end
        
        parallel.waitForAll(table.unpack(batchFns))
    end
    return results
end

--------------------------------------------------------------------------------
-- Discovery & Scanning
--------------------------------------------------------------------------------

---Discover all inventory peripherals
---@param force? boolean Force rediscovery
---@return string[] names All inventory names
function inventory.discover(force)
    if not force and #storage > 0 then
        return storage
    end
    
    peripherals = {}
    sizes = {}
    storage = {}
    
    for _, name in ipairs(peripheral.getNames()) do
        local types = {peripheral.getType(name)}
        local isInv, isStorage = false, false
        
        for _, t in ipairs(types) do
            if t == "inventory" then isInv = true end
            if t == storageType then isStorage = true end
        end
        
        if isInv then
            local p = peripheral.wrap(name)
            if p then
                peripherals[name] = p
                sizes[name] = p.size and p.size() or 0
                if isStorage then
                    storage[#storage + 1] = name
                end
            end
        end
    end
    
    logger.debug(("Discovered %d storage peripherals (%s)"):format(#storage, storageType))
    return storage
end

---Scan all inventories and rebuild stock
---@param force? boolean Force peripheral rediscovery
---@return table<string, number> Stock levels
function inventory.scan(force)
    inventory.discover(force)
    
    -- Parallel scan all inventories
    local scanTasks = {}
    local invList = {}
    
    for name, p in pairs(peripherals) do
        invList[#invList + 1] = name
        scanTasks[#scanTasks + 1] = function()
            return p.list and p.list() or {}
        end
    end
    
    local results = parallel_run(scanTasks, 32)
    
    -- Rebuild all caches
    slots = {}
    items = {}
    stock = {}
    
    local storageSet = {}
    for _, name in ipairs(storage) do storageSet[name] = true end
    
    for i, name in ipairs(invList) do
        local list = results[i] and results[i][1] or {}
        slots[name] = list
        
        for slot, item in pairs(list) do
            local k = key(item)
            
            -- Track locations
            if not items[k] then items[k] = {} end
            items[k][#items[k] + 1] = {inv = name, slot = slot, count = item.count}
            
            -- Only count storage items in stock
            if storageSet[name] then
                stock[k] = (stock[k] or 0) + item.count
            end
        end
    end
    
    stockCache.set("levels", stock)
    stockCache.set("lastScan", os.epoch("utc"))
    
    return stock
end

---Get all stock levels
---@return table<string, number>
function inventory.getAllStock()
    return stock
end

---Get stock for a specific item
---@param item string Item ID
---@return number
function inventory.getStock(item)
    return stock[item] or 0
end

---Find item locations
---@param item string Item ID
---@param storageOnly? boolean Only search storage inventories
---@return table[] locations {inv, slot, count}
function inventory.findItem(item, storageOnly)
    local locs = items[item] or {}
    if not storageOnly then return locs end
    
    local storageSet = {}
    for _, name in ipairs(storage) do storageSet[name] = true end
    
    local filtered = {}
    for _, loc in ipairs(locs) do
        if storageSet[loc.inv] then
            filtered[#filtered + 1] = loc
        end
    end
    return filtered
end

--------------------------------------------------------------------------------
-- Cache Updates (after transfers)
--------------------------------------------------------------------------------

---Update cache after removing items
local function cacheRemove(inv, slot, itemKey, count)
    if not slots[inv] then return end
    
    local slotData = slots[inv][slot]
    if not slotData then return end
    
    local newCount = slotData.count - count
    if newCount <= 0 then
        slots[inv][slot] = nil
    else
        slotData.count = newCount
    end
    
    -- Update stock
    if stock[itemKey] then
        stock[itemKey] = math.max(0, stock[itemKey] - count)
        if stock[itemKey] == 0 then stock[itemKey] = nil end
    end
    
    -- Update item locations
    if items[itemKey] then
        for i, loc in ipairs(items[itemKey]) do
            if loc.inv == inv and loc.slot == slot then
                if newCount <= 0 then
                    table.remove(items[itemKey], i)
                else
                    loc.count = newCount
                end
                break
            end
        end
    end
end

---Update cache after adding items
local function cacheAdd(inv, slot, itemName, count, nbt)
    if not slots[inv] then slots[inv] = {} end
    
    local itemKey = key(itemName, nbt)
    local existing = slots[inv][slot]
    
    if existing then
        existing.count = existing.count + count
    else
        slots[inv][slot] = {name = itemName, count = count, nbt = nbt}
    end
    
    -- Update stock (only for storage)
    local storageSet = {}
    for _, name in ipairs(storage) do storageSet[name] = true end
    if storageSet[inv] then
        stock[itemKey] = (stock[itemKey] or 0) + count
    end
    
    -- Update item locations
    if not items[itemKey] then items[itemKey] = {} end
    local found = false
    for _, loc in ipairs(items[itemKey]) do
        if loc.inv == inv and loc.slot == slot then
            loc.count = loc.count + count
            found = true
            break
        end
    end
    if not found then
        items[itemKey][#items[itemKey] + 1] = {inv = inv, slot = slot, count = count}
    end
end

--------------------------------------------------------------------------------
-- Transfer Operations
--------------------------------------------------------------------------------

---Withdraw items from storage to destination
---@param item string Item ID
---@param count number Amount to withdraw
---@param destInv string Destination inventory
---@param destSlot? number Specific destination slot
---@return number withdrawn
function inventory.withdraw(item, count, destInv, destSlot)
    local locs = inventory.findItem(item, true)
    if #locs == 0 then return 0 end
    
    -- Sort by count descending
    table.sort(locs, function(a, b) return a.count > b.count end)
    
    local withdrawn = 0
    
    -- Sequential if specific slot (can't parallelize)
    if destSlot then
        for _, loc in ipairs(locs) do
            if withdrawn >= count then break end
            
            local p = wrap(loc.inv)
            if p and p.pushItems then
                local amt = math.min(count - withdrawn, loc.count)
                local xfer = p.pushItems(destInv, loc.slot, amt, destSlot) or 0
                if xfer > 0 then
                    withdrawn = withdrawn + xfer
                    cacheRemove(loc.inv, loc.slot, item, xfer)
                end
            end
        end
        return withdrawn
    end
    
    -- Parallel withdrawal
    local tasks, meta = {}, {}
    local remaining = count
    
    for _, loc in ipairs(locs) do
        if remaining <= 0 then break end
        
        local p = wrap(loc.inv)
        if p and p.pushItems then
            local amt = math.min(remaining, loc.count)
            remaining = remaining - amt
            
            meta[#meta + 1] = {inv = loc.inv, slot = loc.slot, amt = amt}
            tasks[#tasks + 1] = function()
                return p.pushItems(destInv, loc.slot, amt) or 0
            end
        end
    end
    
    local results = parallel_run(tasks)
    
    for i, result in ipairs(results) do
        local xfer = result[1] or 0
        if xfer > 0 then
            withdrawn = withdrawn + xfer
            cacheRemove(meta[i].inv, meta[i].slot, item, xfer)
        end
    end
    
    return withdrawn
end

---Deposit items from source into storage
---Storage pulls from source (works with turtles)
---@param sourceInv string Source inventory name
---@param itemFilter? string Optional item ID to filter (only deposit this item)
---@return number deposited
function inventory.deposit(sourceInv, itemFilter)
    if #storage == 0 then
        logger.error("No storage inventories available")
        return 0
    end
    
    -- Get source contents
    local sourceP = wrap(sourceInv)
    local sourceSlots = {}
    
    if sourceP and sourceP.list then
        local list = sourceP.list() or {}
        -- Filter by item if specified
        if itemFilter then
            for slot, item in pairs(list) do
                if item.name == itemFilter then
                    sourceSlots[slot] = item
                end
            end
        else
            sourceSlots = list
        end
    else
        -- Assume turtle (16 slots) - can't filter without list()
        for i = 1, 16 do sourceSlots[i] = true end
    end
    
    local deposited = 0
    
    -- Build tasks: each storage pulls from each source slot
    local tasks, meta = {}, {}
    local slotList = {}
    for slot in pairs(sourceSlots) do slotList[#slotList + 1] = slot end
    
    for i, slot in ipairs(slotList) do
        local storageIdx = ((i - 1) % #storage) + 1
        local storageName = storage[storageIdx]
        local p = wrap(storageName)
        
        if p and p.pullItems then
            meta[#meta + 1] = {storage = storageName, slot = slot}
            tasks[#tasks + 1] = function()
                local ok, pulled = pcall(p.pullItems, sourceInv, slot)
                return ok and pulled or 0
            end
        end
    end
    
    local results = parallel_run(tasks)
    
    for i, result in ipairs(results) do
        local pulled = result[1] or 0
        if pulled > 0 then
            deposited = deposited + pulled
        end
    end
    
    -- Rescan affected storage
    if deposited > 0 then
        inventory.scan()
    end
    
    return deposited
end

---Pull specific slots from source into storage
---@param sourceInv string Source inventory
---@param slotContents table[] Array of {slot, name, count, nbt?}
---@return number totalPulled
---@return table[] results {slot, pulled, error?}
function inventory.pullSlotsBatch(sourceInv, slotContents)
    if #storage == 0 then
        local results = {}
        for _, s in ipairs(slotContents) do
            results[#results + 1] = {slot = s.slot, pulled = 0, error = "no_storage"}
        end
        return 0, results
    end
    
    local totalPulled = 0
    local results = {}
    
    -- Build parallel tasks
    local tasks, meta = {}, {}
    
    for i, slotInfo in ipairs(slotContents) do
        if slotInfo.count > 0 then
            local storageIdx = ((i - 1) % #storage) + 1
            local storageName = storage[storageIdx]
            local p = wrap(storageName)
            
            if p and p.pullItems then
                meta[#meta + 1] = {index = i, slot = slotInfo.slot, storage = storageName}
                tasks[#tasks + 1] = function()
                    local ok, pulled = pcall(p.pullItems, sourceInv, slotInfo.slot, slotInfo.count)
                    return ok and pulled or 0
                end
            end
        end
    end
    
    local taskResults = parallel_run(tasks)
    
    -- Build results
    local pullBySlot = {}
    for i, result in ipairs(taskResults) do
        local pulled = result[1] or 0
        pullBySlot[meta[i].slot] = pulled
        totalPulled = totalPulled + pulled
    end
    
    for _, slotInfo in ipairs(slotContents) do
        local pulled = pullBySlot[slotInfo.slot] or 0
        results[#results + 1] = {
            slot = slotInfo.slot,
            pulled = pulled,
            error = pulled < slotInfo.count and "partial" or nil
        }
    end
    
    if totalPulled > 0 then
        inventory.scan()
    end
    
    return totalPulled, results
end

---Pull a single slot from source into storage
---@param sourceInv string Source inventory
---@param slot number Slot number
---@param itemName string Item name
---@param itemCount number Item count
---@param itemNbt? string Optional NBT
---@return number pulled
---@return string? error
function inventory.pullSlot(sourceInv, slot, itemName, itemCount, itemNbt)
    local total, results = inventory.pullSlotsBatch(sourceInv, {
        {slot = slot, name = itemName, count = itemCount, nbt = itemNbt}
    })
    return total, results[1] and results[1].error or nil
end

---Clear specific slots from source into storage (legacy)
---@param sourceInv string Source inventory
---@param slotsToCheck table Slots to clear
---@return number cleared
function inventory.clearSlots(sourceInv, slotsToCheck)
    -- Get source contents to build slot info
    local sourceP = wrap(sourceInv)
    local slotContents = {}
    
    if sourceP and sourceP.list then
        local list = sourceP.list() or {}
        for _, slot in ipairs(slotsToCheck) do
            local item = list[slot]
            if item then
                slotContents[#slotContents + 1] = {
                    slot = slot,
                    name = item.name,
                    count = item.count,
                    nbt = item.nbt
                }
            end
        end
    else
        -- Blind pull
        for _, slot in ipairs(slotsToCheck) do
            slotContents[#slotContents + 1] = {slot = slot, name = "unknown", count = 64}
        end
    end
    
    local total = inventory.pullSlotsBatch(sourceInv, slotContents)
    return total
end

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

---Get wrapped peripheral
---@param name string
---@return table?
function inventory.getPeripheral(name)
    return wrap(name)
end

---Get storage inventory list
---@return string[]
function inventory.getStorageInventories()
    if #storage == 0 then inventory.discover() end
    return storage
end

---Get all inventory names
---@return string[]
function inventory.getInventoryNames()
    local names = {}
    for name in pairs(peripherals) do names[#names + 1] = name end
    return names
end

---Get inventory size
---@param name string
---@return number
function inventory.getSize(name)
    return sizes[name] or 0
end

---Check if inventory is storage type
---@param name string
---@return boolean
function inventory.isStorageInventory(name)
    for _, n in ipairs(storage) do
        if n == name then return true end
    end
    return false
end

---Get item details (cached)
---@param invName string
---@param slot number
---@return table?
function inventory.getItemDetail(invName, slot)
    local slotData = slots[invName] and slots[invName][slot]
    if not slotData then return nil end
    
    local cacheKey = key(slotData)
    local cached = detailCache.get(cacheKey)
    if cached then return cached end
    
    local p = wrap(invName)
    if p and p.getItemDetail then
        local details = p.getItemDetail(slot)
        if details then
            detailCache.set(cacheKey, details)
        end
        return details
    end
    return nil
end

---Get slot counts
---@return number total, number used, number free
function inventory.slotCounts()
    local total, used = 0, 0
    for name, slotData in pairs(slots) do
        total = total + (sizes[name] or 0)
        for _ in pairs(slotData) do
            used = used + 1
        end
    end
    return total, used, total - used
end

---Time since last scan
---@return number seconds
function inventory.timeSinceLastScan()
    local lastScan = stockCache.get("lastScan") or 0
    return (os.epoch("utc") - lastScan) / 1000
end

---Get last scan timestamp
---@return number
function inventory.getLastScanTime()
    return stockCache.get("lastScan") or 0
end

---Set storage peripheral type
---@param pType string
function inventory.setStorageType(pType)
    storageType = pType
end

---Get storage peripheral type
---@return string
function inventory.getStorageType()
    return storageType
end

---Clear all caches
function inventory.clearCaches()
    stockCache.setAll({})
    detailCache.setAll({})
    peripherals = {}
    sizes = {}
    storage = {}
    slots = {}
    items = {}
    stock = {}
end

---Initialize from cache
function inventory.init()
    local cached = stockCache.get("levels")
    if cached then
        stock = cached
    end
end

---Discover inventories (alias)
function inventory.discoverInventories(force)
    return inventory.discover(force)
end

---Scan a single inventory and update caches
---@param name string Inventory name
---@param skipRebuild? boolean Ignored (kept for compatibility)
---@return table slots
function inventory.scanSingle(name, skipRebuild)
    local p = wrap(name)
    if not p or not p.list then return {} end
    
    local list = p.list() or {}
    slots[name] = list
    
    -- Check if this is a storage inventory
    local isStorage = false
    for _, n in ipairs(storage) do
        if n == name then 
            isStorage = true 
            break 
        end
    end
    
    -- Update items/stock for this inventory
    -- First remove old entries for this inventory
    for itemKey, locs in pairs(items) do
        for i = #locs, 1, -1 do
            if locs[i].inv == name then
                if isStorage then
                    stock[itemKey] = (stock[itemKey] or 0) - locs[i].count
                    if stock[itemKey] <= 0 then stock[itemKey] = nil end
                end
                table.remove(locs, i)
            end
        end
    end
    
    -- Add new entries
    for slot, item in pairs(list) do
        local k = key(item)
        if not items[k] then items[k] = {} end
        items[k][#items[k] + 1] = {inv = name, slot = slot, count = item.count}
        if isStorage then
            stock[k] = (stock[k] or 0) + item.count
        end
    end
    
    return list
end

---Rebuild from cache (no-op for compatibility)
function inventory.rebuildFromCache()
    -- No longer needed - scanSingle updates caches directly
    return stock
end

---Begin batch operation (no-op for compatibility)
function inventory.beginBatch()
end

---End batch operation (no-op for compatibility)  
function inventory.endBatch()
end

---Push items from one inventory to another
---@param fromInv string Source inventory
---@param fromSlot number Source slot
---@param toInv string Destination inventory
---@param count? number Amount (nil = all)
---@param toSlot? number Destination slot (nil = any)
---@return number transferred
function inventory.pushItems(fromInv, fromSlot, toInv, count, toSlot)
    local p = wrap(fromInv)
    if not p or not p.pushItems then return 0 end
    
    -- Get item info before transfer
    local slotData = slots[fromInv] and slots[fromInv][fromSlot]
    local itemKey = slotData and key(slotData) or nil
    
    local transferred = p.pushItems(toInv, fromSlot, count, toSlot) or 0
    
    if transferred > 0 and itemKey then
        cacheRemove(fromInv, fromSlot, itemKey, transferred)
    end
    
    return transferred
end

---Pull items from one inventory to another
---@param toInv string Destination inventory
---@param fromInv string Source inventory
---@param fromSlot number Source slot
---@param count? number Amount (nil = all)
---@param toSlot? number Destination slot (nil = any)
---@return number transferred
function inventory.pullItems(toInv, fromInv, fromSlot, count, toSlot)
    local p = wrap(toInv)
    if not p or not p.pullItems then return 0 end
    
    -- Get item info before transfer
    local slotData = slots[fromInv] and slots[fromInv][fromSlot]
    local itemKey = slotData and key(slotData) or nil
    
    local transferred = p.pullItems(fromInv, fromSlot, count, toSlot) or 0
    
    if transferred > 0 and itemKey then
        cacheRemove(fromInv, fromSlot, itemKey, transferred)
    end
    
    return transferred
end

---Get inventory details from cache
---@param name string Inventory name
---@return table? details {slots, size}
function inventory.getInventoryDetails(name)
    if not slots[name] then return nil end
    return {
        slots = slots[name],
        size = sizes[name] or 0
    }
end

---Get cache statistics
---@return table stats
function inventory.getCacheStats()
    local invCount = 0
    for _ in pairs(slots) do invCount = invCount + 1 end
    
    local detailCount = 0
    for _ in pairs(detailCache.getAll()) do detailCount = detailCount + 1 end
    
    local itemCount = 0
    for _ in pairs(stock) do itemCount = itemCount + 1 end
    
    return {
        inventories = invCount,
        itemDetails = detailCount,
        stockItems = itemCount,
        storageCount = #storage,
        lastScan = stockCache.get("lastScan") or 0
    }
end

---Update parallelism config at runtime
---@param newConfig table {transferThreads?, enabled?}
function inventory.setParallelConfig(newConfig)
    if newConfig.transferThreads then
        threadCount = newConfig.transferThreads
    end
    logger.debug(("Parallelism config updated: threads=%d"):format(threadCount))
end

---Get parallelism config
---@return table
function inventory.getParallelConfig()
    return {
        transferThreads = threadCount,
        enabled = true
    }
end

--------------------------------------------------------------------------------
-- Manipulator Support (Player Inventory Access)
--------------------------------------------------------------------------------

local manipulator = nil

---Get manipulator peripheral
---@return table?
function inventory.getManipulator()
    if not manipulator then
        manipulator = peripheral.find("manipulator")
    end
    return manipulator
end

---Check if manipulator is available
---@return boolean
function inventory.hasManipulator()
    return inventory.getManipulator() ~= nil
end

---Withdraw items to player inventory
---@param item string Item ID
---@param count number Amount
---@param playerName string Player name (unused, uses manipulator target)
---@return number withdrawn
---@return string? error
function inventory.withdrawToPlayer(item, count, playerName)
    local manip = inventory.getManipulator()
    if not manip then return 0, "No manipulator" end
    
    local ok, playerInv = pcall(manip.getInventory)
    if not ok or not playerInv then return 0, "Cannot access player inventory" end
    
    local locs = inventory.findItem(item, true)
    if #locs == 0 then return 0, "Item not found" end
    
    local withdrawn = 0
    for _, loc in ipairs(locs) do
        if withdrawn >= count then break end
        
        local ok2, xfer = pcall(playerInv.pullItems, loc.inv, loc.slot, count - withdrawn)
        if ok2 and xfer and xfer > 0 then
            withdrawn = withdrawn + xfer
            cacheRemove(loc.inv, loc.slot, item, xfer)
        end
    end
    
    return withdrawn, withdrawn == 0 and "Transfer failed" or nil
end

---Deposit items from player inventory
---@param playerName string Player name (unused)
---@param itemFilter? string|string[] Item filter
---@param maxCount? number Max items
---@param excludes? string[] Items to exclude
---@return number deposited
---@return string? error
function inventory.depositFromPlayer(playerName, itemFilter, maxCount, excludes)
    local manip = inventory.getManipulator()
    if not manip then return 0, "No manipulator" end
    
    local ok, playerInv = pcall(manip.getInventory)
    if not ok or not playerInv then return 0, "Cannot access player inventory" end
    
    local ok2, playerItems = pcall(playerInv.list)
    if not ok2 or not playerItems then return 0, "Cannot list player inventory" end
    
    -- Build filters
    local filterSet = nil
    if itemFilter then
        filterSet = {}
        if type(itemFilter) == "string" then filterSet[itemFilter] = true
        elseif type(itemFilter) == "table" then
            for _, f in ipairs(itemFilter) do filterSet[f] = true end
        end
    end
    
    local excludeSet = {}
    if excludes then
        for _, e in ipairs(excludes) do excludeSet[e] = true end
    end
    
    local deposited = 0
    local remaining = maxCount
    
    for slot, item in pairs(playerItems) do
        if remaining and remaining <= 0 then break end
        if excludeSet[item.name] then goto continue end
        
        local matches = not filterSet or filterSet[item.name]
        if matches then
            local toXfer = remaining and math.min(item.count, remaining) or item.count
            
            for _, storageName in ipairs(storage) do
                local ok3, xfer = pcall(playerInv.pushItems, storageName, slot, toXfer)
                if ok3 and xfer and xfer > 0 then
                    deposited = deposited + xfer
                    if remaining then remaining = remaining - xfer end
                    break
                end
            end
        end
        ::continue::
    end
    
    if deposited > 0 then inventory.scan() end
    return deposited, deposited == 0 and "No items transferred" or nil
end

inventory.VERSION = VERSION

return inventory
