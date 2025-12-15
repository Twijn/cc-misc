--- AutoCrafter Inventory Library
--- Manages inventory scanning and item storage.
---
---@version 1.0.0

local VERSION = "1.0.0"

local inventory = {}

local inventoryCache = {}
local itemLocations = {}
local stockLevels = {}
local lastScan = 0

---Get all connected inventory peripherals
---@return table inventories Array of inventory peripheral wrappers
local function getInventories()
    local results = {}
    for _, name in ipairs(peripheral.getNames()) do
        local types = {peripheral.getType(name)}
        for _, t in ipairs(types) do
            if t == "inventory" then
                table.insert(results, {
                    name = name,
                    wrap = peripheral.wrap(name),
                })
                break
            end
        end
    end
    return results
end

---Generate a unique key for an item
---@param item table The item data
---@return string key The unique item key
local function getItemKey(item)
    if item.nbt then
        return item.name .. ":" .. item.nbt
    end
    return item.name
end

---Scan all inventories and update caches
---@return table stockLevels Table of item counts
function inventory.scan()
    local startTime = os.clock()
    
    inventoryCache = {}
    itemLocations = {}
    stockLevels = {}
    
    local inventories = getInventories()
    
    for _, inv in ipairs(inventories) do
        local list = inv.wrap.list()
        if list then
            inventoryCache[inv.name] = {
                wrap = inv.wrap,
                slots = list,
                size = inv.wrap.size(),
            }
            
            for slot, item in pairs(list) do
                local key = getItemKey(item)
                
                -- Update stock levels
                stockLevels[key] = (stockLevels[key] or 0) + item.count
                
                -- Track item locations
                if not itemLocations[key] then
                    itemLocations[key] = {}
                end
                table.insert(itemLocations[key], {
                    inventory = inv.name,
                    slot = slot,
                    count = item.count,
                })
            end
        end
    end
    
    lastScan = os.clock()
    
    return stockLevels
end

---Get stock level for an item
---@param item string The item ID
---@return number count The total count across all inventories
function inventory.getStock(item)
    return stockLevels[item] or 0
end

---Get all stock levels
---@return table stockLevels Table of all item counts
function inventory.getAllStock()
    return stockLevels
end

---Find slots containing an item
---@param item string The item ID
---@return table locations Array of {inventory, slot, count}
function inventory.findItem(item)
    return itemLocations[item] or {}
end

---Find empty slots in inventories
---@return table slots Array of {inventory, slot}
function inventory.findEmptySlots()
    local empty = {}
    
    for name, inv in pairs(inventoryCache) do
        for slot = 1, inv.size do
            if not inv.slots[slot] then
                table.insert(empty, {
                    inventory = name,
                    slot = slot,
                })
            end
        end
    end
    
    return empty
end

---Push items from one inventory slot to another
---@param fromInv string Source inventory name
---@param fromSlot number Source slot
---@param toInv string Destination inventory name
---@param count? number Amount to transfer (nil for all)
---@return number transferred Amount actually transferred
function inventory.pushItems(fromInv, fromSlot, toInv, count)
    local source = peripheral.wrap(fromInv)
    if not source then return 0 end
    
    return source.pushItems(toInv, fromSlot, count) or 0
end

---Pull items from one inventory slot to another
---@param toInv string Destination inventory name
---@param fromInv string Source inventory name
---@param fromSlot number Source slot
---@param count? number Amount to transfer (nil for all)
---@return number transferred Amount actually transferred
function inventory.pullItems(toInv, fromInv, fromSlot, count)
    local dest = peripheral.wrap(toInv)
    if not dest then return 0 end
    
    return dest.pullItems(fromInv, fromSlot, count) or 0
end

---Withdraw items to a specific inventory
---@param item string The item ID to withdraw
---@param count number Amount to withdraw
---@param destInv string Destination inventory name
---@return number withdrawn Amount actually withdrawn
function inventory.withdraw(item, count, destInv)
    local locations = inventory.findItem(item)
    if #locations == 0 then return 0 end
    
    local withdrawn = 0
    
    for _, loc in ipairs(locations) do
        if withdrawn >= count then break end
        
        local toWithdraw = math.min(count - withdrawn, loc.count)
        local transferred = inventory.pushItems(loc.inventory, loc.slot, destInv, toWithdraw)
        withdrawn = withdrawn + transferred
    end
    
    return withdrawn
end

---Deposit items from an inventory into storage
---@param sourceInv string Source inventory name
---@param item? string Optional item filter
---@return number deposited Amount deposited
function inventory.deposit(sourceInv, item)
    local source = peripheral.wrap(sourceInv)
    if not source then return 0 end
    
    local deposited = 0
    local sourceList = source.list()
    
    if not sourceList then return 0 end
    
    for slot, slotItem in pairs(sourceList) do
        if not item or slotItem.name == item then
            -- Find a destination
            for name, inv in pairs(inventoryCache) do
                if name ~= sourceInv then
                    local transferred = source.pushItems(name, slot)
                    deposited = deposited + (transferred or 0)
                    
                    if transferred and transferred > 0 then
                        break
                    end
                end
            end
        end
    end
    
    return deposited
end

---Get time since last scan
---@return number seconds Time since last scan in seconds
function inventory.timeSinceLastScan()
    return os.clock() - lastScan
end

---Get list of connected inventories
---@return table names Array of inventory names
function inventory.getInventoryNames()
    local names = {}
    for name in pairs(inventoryCache) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

---Get inventory details
---@param name string The inventory name
---@return table|nil details The inventory details or nil
function inventory.getInventoryDetails(name)
    return inventoryCache[name]
end

---Count total slots across all inventories
---@return number total Total slots
---@return number used Used slots
---@return number free Free slots
function inventory.slotCounts()
    local total = 0
    local used = 0
    
    for _, inv in pairs(inventoryCache) do
        total = total + inv.size
        for _ in pairs(inv.slots) do
            used = used + 1
        end
    end
    
    return total, used, total - used
end

inventory.VERSION = VERSION

return inventory
