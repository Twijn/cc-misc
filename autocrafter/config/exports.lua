--- AutoCrafter Export Configuration
--- Manages automated item export to external inventories (e.g., ender storage).
--- Supports both "stock" mode (keep items stocked) and "empty" mode (drain items).
--- Supports slot ranges and "vacuum" slots that deposit non-matching items back to storage.
--- Supports NBT matching modes: "any" (all variants), "none" (no NBT), "with" (has NBT), "exact" (specific NBT)
---
---@version 1.2.0

local persist = require("lib.persist")
local logger = require("lib.log")

local exports = persist("export-config.json")

exports.setDefault("inventories", {})

local module = {}

-- NBT matching modes
module.NBT_MODES = {
    ANY = "any",       -- Match item regardless of NBT (default, backward compatible)
    NONE = "none",     -- Only match items WITHOUT NBT data
    WITH = "with",     -- Only match items WITH any NBT data
    EXACT = "exact",   -- Match items with specific NBT hash
}

---@class ExportSlot
---@field item string The item ID to export ("*" for vacuum slot that accepts any non-matching item)
---@field quantity number Target quantity (for stock mode) or 0 (for empty mode)
---@field slot? number Optional specific slot (nil = any slot)
---@field slotStart? number Start of slot range (inclusive)
---@field slotEnd? number End of slot range (inclusive)
---@field vacuum? boolean If true, deposits non-matching items from these slots to storage
---@field nbtMode? string NBT matching mode: "any", "none", "with", "exact" (default: "any")
---@field nbtHash? string Specific NBT hash to match (only used when nbtMode = "exact")

---@class ExportInventory
---@field name string The peripheral name
---@field searchType string The peripheral search type (default: "ender_storage")
---@field mode "stock"|"empty" Export mode
---@field slots ExportSlot[] Array of slot configurations

---Add or update an export inventory
---@param name string The peripheral name
---@param config ExportInventory The export configuration
function module.set(name, config)
    local inventories = exports.get("inventories") or {}
    inventories[name] = config
    exports.set("inventories", inventories)
    logger.info(string.format("Set export inventory: %s (%s mode)", name, config.mode))
end

---Remove an export inventory
---@param name string The peripheral name
function module.remove(name)
    local inventories = exports.get("inventories") or {}
    inventories[name] = nil
    exports.set("inventories", inventories)
    logger.info(string.format("Removed export inventory: %s", name))
end

---Get a specific export inventory config
---@param name string The peripheral name
---@return ExportInventory|nil config The export configuration
function module.get(name)
    local inventories = exports.get("inventories") or {}
    return inventories[name]
end

---Get all export inventories
---@return table<string, ExportInventory> inventories All export configurations
function module.getAll()
    return exports.get("inventories") or {}
end

---Add an item to an export inventory
---@param invName string The peripheral name
---@param item string The item ID (base name)
---@param quantity number Target quantity (0 for empty mode = drain all)
---@param slot? number Optional specific slot
---@param slotStart? number Optional start of slot range (inclusive)
---@param slotEnd? number Optional end of slot range (inclusive)
---@param vacuum? boolean If true, this is a vacuum slot that deposits non-matching items
---@param nbtMode? string NBT matching mode: "any", "none", "with", "exact" (default: "any")
---@param nbtHash? string Specific NBT hash to match (only used when nbtMode = "exact")
function module.addItem(invName, item, quantity, slot, slotStart, slotEnd, vacuum, nbtMode, nbtHash)
    local inventories = exports.get("inventories") or {}
    local inv = inventories[invName]
    
    if not inv then
        logger.warn("Export inventory not found: " .. invName)
        return
    end
    
    inv.slots = inv.slots or {}
    
    -- Check if item already exists with same slot config
    for i, slotConfig in ipairs(inv.slots) do
        local matchesSlot = slotConfig.slot == slot
        local matchesRange = slotConfig.slotStart == slotStart and slotConfig.slotEnd == slotEnd
        if slotConfig.item == item and (matchesSlot or matchesRange) then
            -- Update existing
            inv.slots[i].quantity = quantity
            inv.slots[i].vacuum = vacuum
            inv.slots[i].nbtMode = nbtMode
            inv.slots[i].nbtHash = nbtHash
            exports.set("inventories", inventories)
            logger.info(string.format("Updated export: %s -> %s x%d (nbtMode=%s)", invName, item, quantity, nbtMode or "any"))
            return
        end
    end
    
    -- Add new
    local newSlot = {
        item = item,
        quantity = quantity,
        slot = slot,
        slotStart = slotStart,
        slotEnd = slotEnd,
        vacuum = vacuum,
        nbtMode = nbtMode,
        nbtHash = nbtHash,
    }
    table.insert(inv.slots, newSlot)
    exports.set("inventories", inventories)
    
    local nbtDesc = nbtMode and nbtMode ~= "any" and (" nbt=" .. nbtMode) or ""
    if slotStart and slotEnd then
        logger.info(string.format("Added export: %s -> %s x%d (slots %d-%d%s%s)", 
            invName, item, quantity, slotStart, slotEnd, vacuum and " vacuum" or "", nbtDesc))
    elseif slot then
        logger.info(string.format("Added export: %s -> %s x%d (slot %d%s%s)", 
            invName, item, quantity, slot, vacuum and " vacuum" or "", nbtDesc))
    else
        logger.info(string.format("Added export: %s -> %s x%d%s%s", 
            invName, item, quantity, vacuum and " vacuum" or "", nbtDesc))
    end
end

---Add a slot range to an export inventory
---@param invName string The peripheral name
---@param item string The item ID
---@param quantity number Target quantity per slot
---@param slotStart number Start of slot range (inclusive)
---@param slotEnd number End of slot range (inclusive)
---@param vacuum? boolean If true, non-matching items in range are deposited to storage
---@param nbtMode? string NBT matching mode: "any", "none", "with", "exact" (default: "any")
---@param nbtHash? string Specific NBT hash to match (only used when nbtMode = "exact")
function module.addSlotRange(invName, item, quantity, slotStart, slotEnd, vacuum, nbtMode, nbtHash)
    module.addItem(invName, item, quantity, nil, slotStart, slotEnd, vacuum, nbtMode, nbtHash)
end

---Add a vacuum slot range (deposits non-matching items from these slots to storage)
---@param invName string The peripheral name
---@param slotStart number Start of slot range (inclusive)
---@param slotEnd number End of slot range (inclusive)
function module.addVacuumRange(invName, slotStart, slotEnd)
    module.addItem(invName, "*", 0, nil, slotStart, slotEnd, true)
end

---Get expanded slot list from a slot config (handles ranges)
---@param slotConfig ExportSlot The slot configuration
---@return table slots Array of slot numbers
function module.getExpandedSlots(slotConfig)
    local slots = {}
    if slotConfig.slot then
        table.insert(slots, slotConfig.slot)
    elseif slotConfig.slotStart and slotConfig.slotEnd then
        for s = slotConfig.slotStart, slotConfig.slotEnd do
            table.insert(slots, s)
        end
    end
    return slots
end

---Remove an item from an export inventory
---@param invName string The peripheral name
---@param item string The item ID
---@param slot? number Optional specific slot to match
function module.removeItem(invName, item, slot)
    local inventories = exports.get("inventories") or {}
    local inv = inventories[invName]
    
    if not inv then return end
    
    inv.slots = inv.slots or {}
    
    for i = #inv.slots, 1, -1 do
        local slotConfig = inv.slots[i]
        if slotConfig.item == item and (slot == nil or slotConfig.slot == slot) then
            table.remove(inv.slots, i)
        end
    end
    
    exports.set("inventories", inventories)
    logger.info(string.format("Removed export item: %s from %s", item, invName))
end

---Get all items for an export inventory
---@param invName string The peripheral name
---@return ExportSlot[] slots Array of slot configurations
function module.getItems(invName)
    local inventories = exports.get("inventories") or {}
    local inv = inventories[invName]
    
    if not inv then return {} end
    
    return inv.slots or {}
end

---Count export inventories
---@return number count Number of export inventories
function module.count()
    local inventories = exports.get("inventories") or {}
    local count = 0
    for _ in pairs(inventories) do
        count = count + 1
    end
    return count
end

---Clear all export inventories
function module.clear()
    exports.set("inventories", {})
    logger.info("Cleared all export inventories")
end

return module
