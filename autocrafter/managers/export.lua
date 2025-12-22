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

---Push items to an export inventory
---@param item string The item ID
---@param count number Amount to push
---@param destInv string Destination inventory name
---@param destSlot? number Optional destination slot
---@return number pushed Amount actually pushed
---@return table sources Array of {inventory, count} pairs indicating where items came from
local function pushToExport(item, count, destInv, destSlot)
    -- Find item in storage only (not in other export inventories)
    local locations = inventory.findItem(item, true)
    if #locations == 0 then return 0, {} end
    
    -- Sort by count (largest first) for efficiency
    table.sort(locations, function(a, b) return a.count > b.count end)
    
    local pushed = 0
    local sources = {}  -- Track which inventories we pulled from
    
    for _, loc in ipairs(locations) do
        if pushed >= count then break end
        
        -- Skip if the source is the same as the destination
        if loc.inventory == destInv then
            goto continue
        end
        
        local source = inventory.getPeripheral(loc.inventory)
        if source then
            local toPush = math.min(count - pushed, loc.count)
            local transferred = source.pushItems(destInv, loc.slot, toPush, destSlot) or 0
            pushed = pushed + transferred
            
            if transferred > 0 then
                -- Track this source
                if sources[loc.inventory] then
                    sources[loc.inventory] = sources[loc.inventory] + transferred
                else
                    sources[loc.inventory] = transferred
                end
                -- Update cache for source inventory
                inventory.scanSingle(loc.inventory, true)
            end
        end
        
        ::continue::
    end
    
    -- Rebuild cache if we pushed anything
    if pushed > 0 then
        inventory.rebuildFromCache()
    end
    
    -- Convert sources to array format for return
    local sourceList = {}
    for inv, cnt in pairs(sources) do
        table.insert(sourceList, {inventory = inv, count = cnt})
    end
    
    return pushed, sourceList
end

---Pull items from an export inventory back to storage
---@param item string The item ID
---@param count number Amount to pull
---@param sourceInv string Source export inventory name
---@param sourceSlot? number Optional source slot
---@return number pulled Amount actually pulled
local function pullFromExport(item, count, sourceInv, sourceSlot)
    local source = getExportPeripheral(sourceInv)
    if not source then return 0 end
    
    local pulled = 0
    local storageInvs = inventory.getStorageInventories()
    
    if #storageInvs == 0 then return 0 end
    
    -- If specific slot, just pull from that
    if sourceSlot then
        for _, destName in ipairs(storageInvs) do
            local dest = inventory.getPeripheral(destName)
            if dest and dest.pullItems then
                local transferred = dest.pullItems(sourceInv, sourceSlot, count) or 0
                if transferred > 0 then
                    pulled = pulled + transferred
                    inventory.scanSingle(destName, true)
                    break
                end
            end
        end
    else
        -- Pull from any slot containing the item
        local _, slots = getInventoryItemCount(source, item)
        for _, slotInfo in ipairs(slots) do
            if pulled >= count then break end
            
            for _, destName in ipairs(storageInvs) do
                local dest = inventory.getPeripheral(destName)
                if dest and dest.pullItems then
                    local toPull = math.min(count - pulled, slotInfo.count)
                    local transferred = dest.pullItems(sourceInv, slotInfo.slot, toPull) or 0
                    if transferred > 0 then
                        pulled = pulled + transferred
                        inventory.scanSingle(destName, true)
                        break
                    end
                end
            end
        end
    end
    
    -- Rebuild cache if we pulled anything
    if pulled > 0 then
        inventory.rebuildFromCache()
    end
    
    return pulled
end

---Pull all items from an export inventory back to storage
---@param sourceInv string Source export inventory name
---@return number pulled Total amount of items pulled
local function pullAllFromExport(sourceInv)
    local source = getExportPeripheral(sourceInv)
    if not source then return 0 end
    
    local pulled = 0
    local storageInvs = inventory.getStorageInventories()
    
    if #storageInvs == 0 then return 0 end
    
    -- Get all items in the export inventory
    local list = source.list()
    if not list then return 0 end
    
    -- Pull each slot
    for slot, slotItem in pairs(list) do
        for _, destName in ipairs(storageInvs) do
            local dest = inventory.getPeripheral(destName)
            if dest and dest.pullItems then
                local transferred = dest.pullItems(sourceInv, slot) or 0
                if transferred > 0 then
                    pulled = pulled + transferred
                    inventory.scanSingle(destName, true)
                    break
                end
            end
        end
    end
    
    -- Rebuild cache if we pulled anything
    if pulled > 0 then
        inventory.rebuildFromCache()
    end
    
    return pulled
end

---Process vacuum slots (remove items that don't match expected item in slot range)
---@param name string The peripheral name
---@param inv table The wrapped peripheral
---@param slotConfig table The slot configuration
---@return number pulled Amount of non-matching items pulled to storage
local function processVacuumSlots(name, inv, slotConfig)
    local pulled = 0
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
                -- Pull to storage
                for _, destName in ipairs(storageInvs) do
                    local dest = inventory.getPeripheral(destName)
                    if dest and dest.pullItems then
                        local transferred = dest.pullItems(name, slot) or 0
                        if transferred > 0 then
                            pulled = pulled + transferred
                            inventory.scanSingle(destName, true)
                            break
                        end
                    end
                end
            end
        end
    end
    
    if pulled > 0 then
        inventory.rebuildFromCache()
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
    
    -- Special case: empty mode with no items configured = pull ALL items
    if config.mode == "empty" and #slots == 0 then
        local pulled = pullAllFromExport(name)
        result.pulled = result.pulled + pulled
        if pulled > 0 then
            logger.debug(string.format("Emptied all: %d items from %s", pulled, name))
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
                    if currentCount > 0 then
                        local toPull = currentCount
                        if targetQty > 0 then
                            toPull = math.max(0, currentCount - targetQty)
                        end
                        if toPull > 0 then
                            local pulled = pullFromExport(item, toPull, name, slot)
                            result.pulled = result.pulled + pulled
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
            
            if currentCount < targetQty then
                local needed = targetQty - currentCount
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
    
    local inventories = exportConfig.getAll()
    local stats = {
        inventoriesProcessed = 0,
        totalPushed = 0,
        totalPulled = 0,
        errors = 0,
    }
    
    for name, config in pairs(inventories) do
        local ok, result = pcall(processExportInventory, name, config)
        
        if ok then
            stats.inventoriesProcessed = stats.inventoriesProcessed + 1
            stats.totalPushed = stats.totalPushed + result.pushed
            stats.totalPulled = stats.totalPulled + result.pulled
        else
            stats.errors = stats.errors + 1
            logger.warn(string.format("Error processing export %s: %s", name, tostring(result)))
        end
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
