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
local storageSet = {}       -- name -> true (fast lookup cache, rebuilt with storage)
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

---Convert a wildcard pattern to a Lua pattern
---Supports * as a wildcard that matches any characters
---@param wildcardPattern string Pattern with wildcards (e.g., "cobble*", "*dirt")
---@return string luaPattern
local function wildcardToPattern(wildcardPattern)
    -- Escape Lua pattern special characters, except *
    local escaped = wildcardPattern:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
    -- Convert * to Lua pattern .*
    local pattern = escaped:gsub("%*", ".*")
    -- Anchor pattern to match entire string
    return "^" .. pattern .. "$"
end

---Check if an item name matches a filter (supports wildcards)
---@param itemName string Full item name (e.g., "minecraft:cobblestone")
---@param filter string Filter pattern (may contain * wildcards)
---@return boolean
local function matchesFilter(itemName, filter)
    -- Check if filter contains wildcard
    if filter:find("%*") then
        local pattern = wildcardToPattern(filter)
        return itemName:match(pattern) ~= nil
    else
        -- Exact match
        return itemName == filter
    end
end

---Check if an item name matches any of the given filters (supports wildcards)
---@param itemName string Full item name (e.g., "minecraft:cobblestone")
---@param filters string[] Array of filter patterns
---@return boolean
local function matchesAnyFilter(itemName, filters)
    for _, filter in ipairs(filters) do
        if matchesFilter(itemName, filter) then
            return true
        end
    end
    return false
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
    
    local start = os.clock()
    peripherals = {}
    sizes = {}
    storage = {}
    storageSet = {}
    
    local allNames = peripheral.getNames()
    local invCount = 0
    
    for _, name in ipairs(allNames) do
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
                invCount = invCount + 1
                if isStorage then
                    storage[#storage + 1] = name
                    storageSet[name] = true
                end
            end
        end
    end
    
    local elapsed = os.clock() - start
    logger.debug(string.format("Discovered %d peripherals, %d inventories, %d storage (%s) in %.2fs",
        #allNames, invCount, #storage, storageType, elapsed))
    return storage
end

---Scan all inventories and rebuild stock
---@param force? boolean Force peripheral rediscovery
---@return table<string, number> Stock levels
function inventory.scan(force)
    local totalStart = os.clock()
    
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
    
    local listStart = os.clock()
    local results = parallel_run(scanTasks, 32)
    local listTime = os.clock() - listStart
    
    -- Rebuild all caches
    local rebuildStart = os.clock()
    slots = {}
    items = {}
    stock = {}
    
    -- Note: storageSet is already built in discover(), just use it directly
    
    local totalSlots = 0
    local totalItems = 0
    for i, name in ipairs(invList) do
        local list = results[i] and results[i][1] or {}
        slots[name] = list
        
        for slot, item in pairs(list) do
            totalSlots = totalSlots + 1
            local k = key(item)
            
            -- Track locations
            if not items[k] then items[k] = {} end
            items[k][#items[k] + 1] = {inv = name, slot = slot, count = item.count}
            
            -- Only count storage items in stock
            if storageSet[name] then
                stock[k] = (stock[k] or 0) + item.count
                totalItems = totalItems + item.count
            end
        end
    end
    local rebuildTime = os.clock() - rebuildStart
    
    stockCache.set("levels", stock)
    stockCache.set("lastScan", os.epoch("utc"))
    
    local totalTime = os.clock() - totalStart
    logger.debug(string.format("Scan complete: %d inventories, %d slots, %d items (list: %.2fs, rebuild: %.2fs, total: %.2fs)",
        #invList, totalSlots, totalItems, listTime, rebuildTime, totalTime))
    
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
    local count = stock[item] or 0
    
    -- If no exact match and item doesn't have NBT, check for NBT variants
    if count == 0 and not item:find(":.*:") then
        -- Search for items that start with this base name followed by :
        for itemKey, itemCount in pairs(stock) do
            if itemKey:sub(1, #item + 1) == item .. ":" then
                count = count + itemCount
            end
        end
    end
    
    return count
end

---Get stock by base name (ignoring NBT variations)
---@param baseName string Item base name
---@return number total Total stock of all variants
function inventory.getStockByBaseName(baseName)
    local total = 0
    
    for itemKey, itemCount in pairs(stock) do
        if itemKey == baseName or itemKey:sub(1, #baseName + 1) == baseName .. ":" then
            total = total + itemCount
        end
    end
    
    return total
end

---Find item locations
---@param item string Item ID
---@param inStorageOnly? boolean Only search storage inventories
---@return table[] locations {inv, slot, count}
function inventory.findItem(item, inStorageOnly)
    local locs = items[item] or {}
    if not inStorageOnly then return locs end
    
    -- Use cached storageSet for O(1) lookup instead of rebuilding
    local filtered = {}
    for _, loc in ipairs(locs) do
        if storageSet[loc.inv] then
            filtered[#filtered + 1] = loc
        end
    end
    return filtered
end

---Find item locations by base name (ignoring NBT)
---This allows finding all variants of an item (e.g., all enchanted books regardless of enchantment)
---@param baseName string Item base name (e.g., "minecraft:enchanted_book")
---@param inStorageOnly? boolean Only search storage inventories
---@return table[] locations {inv, slot, count, key} - key includes NBT hash if present
function inventory.findItemByBaseName(baseName, inStorageOnly)
    -- Use cached storageSet for O(1) lookup
    local results = {}
    
    -- Search all item keys for those starting with baseName
    for itemKey, locs in pairs(items) do
        -- Check if key matches base name (exact match or starts with baseName:)
        local matches = (itemKey == baseName) or (itemKey:sub(1, #baseName + 1) == baseName .. ":")
        
        if matches then
            for _, loc in ipairs(locs) do
                if not inStorageOnly or storageSet[loc.inv] then
                    results[#results + 1] = {
                        inv = loc.inv,
                        slot = loc.slot,
                        count = loc.count,
                        key = itemKey,  -- Include full key so caller knows which variant
                    }
                end
            end
        end
    end
    
    return results
end

--------------------------------------------------------------------------------
-- Cache Updates (after transfers)
--------------------------------------------------------------------------------

---Update cache after removing items
---@param inv string Inventory name
---@param slot number Slot number
---@param itemKey string Item key (name or name:nbt)
---@param count number Amount removed
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
    
    -- Update stock (only for storage inventories) - use cached storageSet
    if storageSet[inv] and stock[itemKey] then
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
    
    -- Update stock (only for storage) - use cached storageSet
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
    
    -- If no exact match locations found, try searching by base name (ignoring NBT)
    -- This handles cases where storage has items with NBT that we want to treat as equivalent
    if #locs == 0 and not item:find(":.*:") then
        -- Item doesn't already have NBT hash, try finding variants
        local variantLocs = inventory.findItemByBaseName(item, true)
        if #variantLocs > 0 then
            logger.debug(string.format("withdraw: no exact match for %s, found %d NBT variants", 
                item, #variantLocs))
            -- Convert to regular locs format (strip the key field, we don't need it for withdrawal)
            for _, loc in ipairs(variantLocs) do
                locs[#locs + 1] = {inv = loc.inv, slot = loc.slot, count = loc.count, itemKey = loc.key}
            end
        end
    end
    
    -- If still no locations found but stock says we have items, cache may be stale
    if #locs == 0 then
        local stockCount = stock[item] or 0
        if stockCount > 0 then
            logger.warn(string.format("withdraw: cache inconsistency for %s - stock=%d but no locations found, triggering rescan", 
                item, stockCount))
            inventory.scan(false)
            locs = inventory.findItem(item, true)
            -- Try base name again after rescan
            if #locs == 0 and not item:find(":.*:") then
                local variantLocs = inventory.findItemByBaseName(item, true)
                for _, loc in ipairs(variantLocs) do
                    locs[#locs + 1] = {inv = loc.inv, slot = loc.slot, count = loc.count, itemKey = loc.key}
                end
            end
        end
        if #locs == 0 then
            logger.debug(string.format("withdraw: no locations for %s (stock=%d)", item, stock[item] or 0))
            return 0
        end
    end
    
    -- Sort by count descending (withdraw from fullest stacks first for efficiency)
    table.sort(locs, function(a, b) return a.count > b.count end)
    
    local withdrawn = 0
    
    -- Sequential if specific slot (can't parallelize to same slot)
    if destSlot then
        for _, loc in ipairs(locs) do
            if withdrawn >= count then break end
            
            local p = wrap(loc.inv)
            if p and p.pushItems then
                local amt = math.min(count - withdrawn, loc.count)
                local ok, xfer = pcall(p.pushItems, destInv, loc.slot, amt, destSlot)
                xfer = ok and (xfer or 0) or 0
                if xfer > 0 then
                    withdrawn = withdrawn + xfer
                    -- Use the actual item key if we have it (for NBT variants), else use the requested item
                    local cacheKey = loc.itemKey or item
                    cacheRemove(loc.inv, loc.slot, cacheKey, xfer)
                elseif ok and loc.count > 0 then
                    -- Transfer returned 0 but we expected items - slot might be empty (stale cache)
                    logger.debug(string.format("withdraw: slot %s:%d returned 0, expected %d - marking empty", 
                        loc.inv, loc.slot, loc.count))
                    local cacheKey = loc.itemKey or item
                    cacheRemove(loc.inv, loc.slot, cacheKey, loc.count)
                end
            end
        end
        return withdrawn
    end
    
    -- Parallel withdrawal for better performance
    local tasks, meta = {}, {}
    local remaining = count
    
    for _, loc in ipairs(locs) do
        if remaining <= 0 then break end
        
        local p = wrap(loc.inv)
        if p and p.pushItems then
            local amt = math.min(remaining, loc.count)
            remaining = remaining - amt
            
            local capturedInv = loc.inv
            local capturedSlot = loc.slot
            local capturedAmt = amt
            local capturedLocCount = loc.count
            local capturedItemKey = loc.itemKey or item
            
            meta[#meta + 1] = {inv = capturedInv, slot = capturedSlot, amt = capturedAmt, locCount = capturedLocCount, itemKey = capturedItemKey}
            tasks[#tasks + 1] = function()
                local ok, result = pcall(p.pushItems, destInv, capturedSlot, capturedAmt)
                return ok and (result or 0) or 0
            end
        end
    end
    
    local results = parallel_run(tasks)
    
    for i, result in ipairs(results) do
        local xfer = result[1] or 0
        if xfer > 0 then
            withdrawn = withdrawn + xfer
            cacheRemove(meta[i].inv, meta[i].slot, meta[i].itemKey, xfer)
        elseif meta[i].locCount > 0 then
            -- Transfer returned 0 but we expected items - slot might be empty (stale cache)
            logger.debug(string.format("withdraw: slot %s:%d returned 0, expected %d - marking empty", 
                meta[i].inv, meta[i].slot, meta[i].locCount))
            cacheRemove(meta[i].inv, meta[i].slot, meta[i].itemKey, meta[i].locCount)
        end
    end
    
    -- If we withdrew less than expected, log it
    if withdrawn < count and withdrawn > 0 then
        logger.debug(string.format("withdraw: partial withdrawal of %s - got %d/%d", item, withdrawn, count))
    end
    
    return withdrawn
end

---Deposit items from source into storage
---Storage pulls from source (works with turtles)
---Uses cache to prefer storage inventories with empty slots
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
    
    -- Build a list of storage inventories that have empty slots (from cache)
    -- This avoids trying barrels that we know are full
    local storageWithSpace = {}
    for _, invName in ipairs(storage) do
        local invSlots = slots[invName] or {}
        local size = sizes[invName] or 0
        local usedCount = 0
        for _ in pairs(invSlots) do usedCount = usedCount + 1 end
        local emptyCount = size - usedCount
        -- Only include storage that has at least one empty slot
        if emptyCount > 0 then
            storageWithSpace[#storageWithSpace + 1] = {name = invName, emptySlots = emptyCount}
        end
    end
    -- Sort by empty slots descending (prefer inventories with more space)
    table.sort(storageWithSpace, function(a, b) return a.emptySlots > b.emptySlots end)
    
    -- If no storage has space according to cache, fall back to trying all storage
    if #storageWithSpace == 0 then
        logger.debug("deposit: cache shows no storage with space, trying all storage")
        for _, invName in ipairs(storage) do
            storageWithSpace[#storageWithSpace + 1] = {name = invName, emptySlots = 0}
        end
    end
    
    -- Build tasks: each slot tries multiple barrels if first one fails
    local tasks, meta = {}, {}
    local slotList = {}
    for slot in pairs(sourceSlots) do slotList[#slotList + 1] = slot end
    
    for i, slot in ipairs(slotList) do
        local startIdx = ((i - 1) % #storageWithSpace) + 1
        local capturedSlot = slot
        local capturedStartIdx = startIdx
        local capturedStorageList = storageWithSpace
        
        meta[#meta + 1] = {slot = slot}
        tasks[#tasks + 1] = function()
            -- Try ALL barrels with space (not limited to 10)
            local maxAttempts = #capturedStorageList
            
            for attempt = 0, maxAttempts - 1 do
                local storageIdx = ((capturedStartIdx - 1 + attempt) % #capturedStorageList) + 1
                local storageName = capturedStorageList[storageIdx].name
                local p = wrap(storageName)
                
                if p and p.pullItems then
                    local ok, pulled = pcall(p.pullItems, sourceInv, capturedSlot)
                    if ok and pulled and pulled > 0 then
                        return pulled
                    end
                    -- pulled == 0 or error means try next barrel
                end
            end
            return 0
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
---Uses cache to prefer storage inventories with empty slots
---@param sourceInv string Source inventory
---@param slotContents table[] Array of {slot, name, count, nbt?}
---@return table[] results {slot, pulled, error?}
---@return number totalPulled
function inventory.pullSlotsBatch(sourceInv, slotContents)
    if #storage == 0 then
        local results = {}
        for _, s in ipairs(slotContents) do
            results[#results + 1] = {slot = s.slot, pulled = 0, error = "no_storage"}
        end
        return results, 0
    end
    
    local totalPulled = 0
    local results = {}
    
    -- Build a list of storage inventories that have empty slots (from cache)
    -- This avoids trying barrels that we know are full
    local storageWithSpace = {}
    for _, invName in ipairs(storage) do
        local invSlots = slots[invName] or {}
        local size = sizes[invName] or 0
        local usedCount = 0
        for _ in pairs(invSlots) do usedCount = usedCount + 1 end
        local emptyCount = size - usedCount
        -- Only include storage that has at least one empty slot
        if emptyCount > 0 then
            storageWithSpace[#storageWithSpace + 1] = {name = invName, emptySlots = emptyCount}
        end
    end
    -- Sort by empty slots descending (prefer inventories with more space)
    table.sort(storageWithSpace, function(a, b) return a.emptySlots > b.emptySlots end)
    
    -- If no storage has space according to cache, fall back to trying all storage
    -- (cache might be stale)
    if #storageWithSpace == 0 then
        logger.debug("pullSlotsBatch: cache shows no storage with space, trying all storage")
        for _, invName in ipairs(storage) do
            storageWithSpace[#storageWithSpace + 1] = {name = invName, emptySlots = 0}
        end
    end
    
    -- Build parallel tasks
    local tasks, meta = {}, {}
    
    logger.debug(string.format("pullSlotsBatch: %d storage containers with space", #storageWithSpace))
    
    for i, slotInfo in ipairs(slotContents) do
        if slotInfo.count > 0 then
            -- Start with storage that has most empty slots, but distribute across inventories
            local startIdx = ((i - 1) % #storageWithSpace) + 1
            
            meta[#meta + 1] = {index = i, slot = slotInfo.slot}
            local capturedSlot = slotInfo.slot
            local capturedCount = slotInfo.count
            local capturedStartIdx = startIdx
            local capturedStorageList = storageWithSpace
            
            tasks[#tasks + 1] = function()
                -- Try ALL barrels with space (not limited to 10)
                local maxAttempts = #capturedStorageList
                
                for attempt = 0, maxAttempts - 1 do
                    local storageIdx = ((capturedStartIdx - 1 + attempt) % #capturedStorageList) + 1
                    local storageName = capturedStorageList[storageIdx].name
                    local p = wrap(storageName)
                    
                    if p and p.pullItems then
                        local ok, pulled = pcall(p.pullItems, sourceInv, capturedSlot, capturedCount)
                        if ok and pulled and pulled > 0 then
                            logger.debug(string.format("pullItems: %s slot %d -> %s = %d", 
                                sourceInv, capturedSlot, storageName, pulled))
                            return pulled
                        elseif not ok then
                            logger.debug(string.format("pullItems error: %s slot %d -> %s: %s", 
                                sourceInv, capturedSlot, storageName, tostring(pulled)))
                        end
                        -- pulled == 0 means barrel might be full or slot empty, try next barrel
                    end
                end
                
                -- All attempts failed - this is only a problem if we actually had items to pull
                -- Don't warn here, let the caller decide if it's a problem
                return 0
            end
        end
    end
    
    logger.debug(string.format("pullSlotsBatch: created %d tasks", #tasks))
    
    if #tasks == 0 then
        logger.debug("pullSlotsBatch: no tasks created - slots may be empty")
        for _, slotInfo in ipairs(slotContents) do
            results[#results + 1] = {
                slot = slotInfo.slot,
                pulled = 0,
                error = "no_valid_storage"
            }
        end
        return results, 0
    end
    
    local taskResults = parallel_run(tasks)
    
    -- Build results
    local pullBySlot = {}
    for i, result in ipairs(taskResults) do
        local pulled = result[1] or 0
        pullBySlot[meta[i].slot] = pulled
        totalPulled = totalPulled + pulled
    end
    
    logger.debug(string.format("pullSlotsBatch: totalPulled=%d from %d tasks", totalPulled, #taskResults))
    
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
    
    return results, totalPulled
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
    local results, total = inventory.pullSlotsBatch(sourceInv, {
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
    
    local _, total = inventory.pullSlotsBatch(sourceInv, slotContents)
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

---Get storage inventory list (ONLY returns verified storage-type inventories)
---This function ensures only proper storage peripherals (e.g., diamond barrels) are returned,
---never ender storage or other chest types.
---@return string[]
function inventory.getStorageInventories()
    if #storage == 0 then 
        inventory.discover() 
    end
    
    -- Validate that all items in storage are still valid storage-type peripherals
    -- This catches any corruption or edge cases
    local validated = {}
    for _, name in ipairs(storage) do
        local types = {peripheral.getType(name)}
        local isValid = false
        for _, t in ipairs(types) do
            if t == storageType then
                isValid = true
                break
            end
        end
        if isValid then
            validated[#validated + 1] = name
        else
            logger.warn(string.format("getStorageInventories: Removing invalid entry %s (type: %s, expected: %s)",
                name, table.concat(types, ","), storageType))
        end
    end
    
    -- Update storage if we filtered anything out
    if #validated ~= #storage then
        storage = validated
    end
    
    return storage
end

---Get storage inventories that have empty slots (from cache)
---Returns array sorted by empty slots descending (most space first)
---@return table[] Array of {name, emptySlots}
function inventory.getStorageWithSpace()
    if #storage == 0 then 
        inventory.discover() 
    end
    
    local storageWithSpace = {}
    for _, invName in ipairs(storage) do
        local invSlots = slots[invName] or {}
        local size = sizes[invName] or 0
        local usedCount = 0
        for _ in pairs(invSlots) do usedCount = usedCount + 1 end
        local emptyCount = size - usedCount
        if emptyCount > 0 then
            storageWithSpace[#storageWithSpace + 1] = {name = invName, emptySlots = emptyCount}
        end
    end
    
    -- Sort by empty slots descending (prefer inventories with more space)
    table.sort(storageWithSpace, function(a, b) return a.emptySlots > b.emptySlots end)
    
    return storageWithSpace
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

---Get slot contents from cache (no peripheral call)
---@param invName string Inventory name
---@param slot number Slot number
---@return table|nil slotData {name, count, nbt?} or nil if empty
function inventory.getSlotContents(invName, slot)
    if not slots[invName] then return nil end
    return slots[invName][slot]
end

---Get all slots for an inventory from cache (no peripheral call)
---@param invName string Inventory name
---@return table slotData {slot -> {name, count, nbt?}}
function inventory.getAllSlots(invName)
    return slots[invName] or {}
end

---Find an empty slot in storage inventories (uses cache)
---@param preferredInv? string Optional preferred inventory to check first
---@return string|nil invName Inventory with empty slot
---@return number|nil slot Empty slot number
function inventory.findEmptySlot(preferredInv)
    -- Check preferred inventory first
    if preferredInv and slots[preferredInv] and sizes[preferredInv] then
        local invSlots = slots[preferredInv]
        local size = sizes[preferredInv]
        for s = 1, size do
            if not invSlots[s] then
                return preferredInv, s
            end
        end
    end
    
    -- Search all storage inventories
    for _, invName in ipairs(storage) do
        if invName ~= preferredInv then
            local invSlots = slots[invName] or {}
            local size = sizes[invName] or 0
            for s = 1, size do
                if not invSlots[s] then
                    return invName, s
                end
            end
        end
    end
    
    return nil, nil
end

---Find multiple empty slots in storage inventories (uses cache)
---@param count number Number of empty slots needed
---@param preferredInv? string Optional preferred inventory to check first
---@return table emptySlots Array of {inv, slot}
function inventory.findEmptySlots(count, preferredInv)
    local emptySlots = {}
    local found = 0
    
    -- Helper to check an inventory
    local function checkInv(invName)
        if found >= count then return end
        local invSlots = slots[invName] or {}
        local size = sizes[invName] or 0
        for s = 1, size do
            if not invSlots[s] then
                emptySlots[#emptySlots + 1] = {inv = invName, slot = s}
                found = found + 1
                if found >= count then return end
            end
        end
    end
    
    -- Check preferred inventory first
    if preferredInv then
        checkInv(preferredInv)
    end
    
    -- Search all storage inventories
    for _, invName in ipairs(storage) do
        if invName ~= preferredInv then
            checkInv(invName)
        end
    end
    
    return emptySlots
end

---Count empty slots in storage (uses cache)
---@return number emptyCount Number of empty slots in storage
function inventory.countEmptySlots()
    local empty = 0
    for _, invName in ipairs(storage) do
        local invSlots = slots[invName] or {}
        local size = sizes[invName] or 0
        for s = 1, size do
            if not invSlots[s] then
                empty = empty + 1
            end
        end
    end
    return empty
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
    
    local peripheralCount = 0
    for _ in pairs(peripherals) do peripheralCount = peripheralCount + 1 end
    
    local lastScan = stockCache.get("lastScan") or 0
    
    return {
        inventories = invCount,
        itemDetails = detailCount,
        stockItems = itemCount,
        storageCount = #storage,
        lastScan = lastScan,
        wrappedPeripherals = peripheralCount,
        timeSinceScan = os.clock() - lastScan
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
---Uses sequential transfers to avoid conflicts (player inventory has limited slots)
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
    
    -- Sort by count descending (withdraw from fullest stacks first)
    table.sort(locs, function(a, b) return a.count > b.count end)
    
    local withdrawn = 0
    local remaining = count
    
    -- Sequential transfers to player inventory
    -- Parallel transfers don't work well because:
    -- 1. Player inventory has limited slots (36)
    -- 2. Multiple parallel pullItems can conflict trying to use the same slot
    -- 3. This causes partial transfers and weird amounts
    for _, loc in ipairs(locs) do
        if remaining <= 0 then break end
        
        local toTransfer = math.min(remaining, loc.count)
        local ok2, xfer = pcall(playerInv.pullItems, loc.inv, loc.slot, toTransfer)
        xfer = ok2 and (xfer or 0) or 0
        
        if xfer > 0 then
            withdrawn = withdrawn + xfer
            remaining = remaining - xfer
            cacheRemove(loc.inv, loc.slot, item, xfer)
        end
        
        -- If we got less than expected, the player inventory might be full
        if xfer < toTransfer then
            -- Try once more in case it was a temporary issue
            if remaining > 0 then
                local retryAmt = math.min(remaining, loc.count - xfer)
                if retryAmt > 0 then
                    local ok3, xfer2 = pcall(playerInv.pullItems, loc.inv, loc.slot, retryAmt)
                    xfer2 = ok3 and (xfer2 or 0) or 0
                    if xfer2 > 0 then
                        withdrawn = withdrawn + xfer2
                        remaining = remaining - xfer2
                        cacheRemove(loc.inv, loc.slot, item, xfer2)
                    end
                end
            end
            
            -- If still getting partial transfers, player inventory is likely full
            if remaining > 0 and xfer == 0 then
                break
            end
        end
    end
    
    return withdrawn, withdrawn == 0 and "Transfer failed" or nil
end

---Deposit items from player inventory
---Uses parallel transfers for speed
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
    
    -- Build filters (now supports wildcards)
    local filters = nil
    if itemFilter then
        if type(itemFilter) == "string" then
            filters = {itemFilter}
        elseif type(itemFilter) == "table" then
            filters = itemFilter
        end
    end
    
    local excludeSet = {}
    if excludes then
        for _, e in ipairs(excludes) do excludeSet[e] = true end
    end
    
    -- Build list of slots to deposit
    local slotsToDeposit = {}
    local totalToDeposit = 0
    
    for slot, item in pairs(playerItems) do
        if maxCount and totalToDeposit >= maxCount then break end
        if excludeSet[item.name] then goto continue end
        
        -- Check filter match (supports wildcards like "cobble*" or "*dirt")
        local matches = not filters or matchesAnyFilter(item.name, filters)
        if matches then
            local toXfer = maxCount and math.min(item.count, maxCount - totalToDeposit) or item.count
            slotsToDeposit[#slotsToDeposit + 1] = {slot = slot, count = toXfer}
            totalToDeposit = totalToDeposit + toXfer
        end
        ::continue::
    end
    
    if #slotsToDeposit == 0 then return 0, "No items to deposit" end
    
    -- Build parallel tasks - distribute across storage
    local tasks = {}
    local results = {}
    
    for i, slotInfo in ipairs(slotsToDeposit) do
        local capturedSlot = slotInfo.slot
        local capturedCount = slotInfo.count
        local storageIdx = ((i - 1) % #storage) + 1
        
        tasks[#tasks + 1] = function()
            -- Try multiple storage inventories if first fails
            for attempt = 0, math.min(#storage - 1, 5) do
                local tryIdx = ((storageIdx - 1 + attempt) % #storage) + 1
                local storageName = storage[tryIdx]
                local ok3, xfer = pcall(playerInv.pushItems, storageName, capturedSlot, capturedCount)
                if ok3 and xfer and xfer > 0 then
                    return xfer
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
    
    -- Sum results
    local deposited = 0
    for _, result in ipairs(results) do
        deposited = deposited + (result or 0)
    end
    
    if deposited > 0 then inventory.scan() end
    return deposited, deposited == 0 and "No items transferred" or nil
end

---Update cache after items are removed from a slot (public API)
---Use this instead of scanSingle for performance when transfer count is known
---@param inv string Inventory name
---@param slot number Slot number
---@param itemName string Item name (e.g., "minecraft:diamond")
---@param count number Amount that was removed
---@param nbt? string Optional NBT hash
function inventory.updateCacheRemove(inv, slot, itemName, count, nbt)
    local itemKey = key(itemName, nbt)
    cacheRemove(inv, slot, itemKey, count)
end

---Update cache after items are added to a slot (public API)
---Use this instead of scanSingle for performance when transfer count is known
---@param inv string Inventory name
---@param slot number Slot number
---@param itemName string Item name (e.g., "minecraft:diamond")
---@param count number Amount that was added
---@param nbt? string Optional NBT hash
function inventory.updateCacheAdd(inv, slot, itemName, count, nbt)
    cacheAdd(inv, slot, itemName, count, nbt)
end

---Update stock total only (without tracking exact slot location)
---Use this when items were added to storage but exact destination slot is unknown
---This is more efficient than scanSingle but results in slightly stale location cache
---The location cache will self-correct on the next periodic scan
---@param itemName string Item name (e.g., "minecraft:diamond")
---@param count number Amount that was added
---@param nbt? string Optional NBT hash
function inventory.updateStockAdd(itemName, count, nbt)
    local itemKey = key(itemName, nbt)
    stock[itemKey] = (stock[itemKey] or 0) + count
end

inventory.VERSION = VERSION

return inventory
