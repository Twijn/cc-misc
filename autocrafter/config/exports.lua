--- AutoCrafter Export Configuration
--- Manages automated item export to external inventories (e.g., ender storage).
--- Supports both "stock" mode (keep items stocked) and "empty" mode (drain items).
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")

local exports = persist("export-config.json")

exports.setDefault("inventories", {})

local module = {}

---@class ExportSlot
---@field item string The item ID to export
---@field quantity number Target quantity (for stock mode) or 0 (for empty mode)
---@field slot? number Optional specific slot (nil = any slot)

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
---@param item string The item ID
---@param quantity number Target quantity (0 for empty mode = drain all)
---@param slot? number Optional specific slot
function module.addItem(invName, item, quantity, slot)
    local inventories = exports.get("inventories") or {}
    local inv = inventories[invName]
    
    if not inv then
        logger.warn("Export inventory not found: " .. invName)
        return
    end
    
    inv.slots = inv.slots or {}
    
    -- Check if item already exists
    for i, slotConfig in ipairs(inv.slots) do
        if slotConfig.item == item and slotConfig.slot == slot then
            -- Update existing
            inv.slots[i].quantity = quantity
            exports.set("inventories", inventories)
            logger.info(string.format("Updated export: %s -> %s x%d", invName, item, quantity))
            return
        end
    end
    
    -- Add new
    table.insert(inv.slots, {
        item = item,
        quantity = quantity,
        slot = slot,
    })
    exports.set("inventories", inventories)
    logger.info(string.format("Added export: %s -> %s x%d", invName, item, quantity))
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
