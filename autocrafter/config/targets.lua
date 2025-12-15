--- AutoCrafter Craft Targets Configuration
--- Manages items to keep stocked.
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")

local targets = persist("craft-targets.json")

targets.setDefault("items", {})

local module = {}

---Add or update a craft target
---@param item string The item ID
---@param quantity number Target quantity
function module.set(item, quantity)
    local items = targets.get("items") or {}
    items[item] = quantity
    targets.set("items", items)
    logger.info(string.format("Set craft target: %s x%d", item, quantity))
end

---Remove a craft target
---@param item string The item ID
function module.remove(item)
    local items = targets.get("items") or {}
    items[item] = nil
    targets.set("items", items)
    logger.info(string.format("Removed craft target: %s", item))
end

---Get a specific craft target
---@param item string The item ID
---@return number|nil quantity The target quantity or nil
function module.get(item)
    local items = targets.get("items") or {}
    return items[item]
end

---Get all craft targets
---@return table items Table of item -> quantity
function module.getAll()
    return targets.get("items") or {}
end

---Get craft targets with current stock levels
---@param stockLevels table Current stock levels
---@return table targets Array of {item, target, current, needed}
function module.getWithStock(stockLevels)
    local items = targets.get("items") or {}
    local result = {}
    
    for item, quantity in pairs(items) do
        local current = stockLevels[item] or 0
        table.insert(result, {
            item = item,
            target = quantity,
            current = current,
            needed = math.max(0, quantity - current),
        })
    end
    
    -- Sort by most needed first
    table.sort(result, function(a, b)
        return a.needed > b.needed
    end)
    
    return result
end

---Get items that need crafting
---@param stockLevels table Current stock levels
---@return table needed Array of {item, target, current, needed}
function module.getNeeded(stockLevels)
    local all = module.getWithStock(stockLevels)
    local needed = {}
    
    for _, target in ipairs(all) do
        if target.needed > 0 then
            table.insert(needed, target)
        end
    end
    
    return needed
end

---Clear all craft targets
function module.clear()
    targets.set("items", {})
    logger.info("Cleared all craft targets")
end

---Get count of craft targets
---@return number count Number of targets
function module.count()
    local items = targets.get("items") or {}
    local count = 0
    for _ in pairs(items) do
        count = count + 1
    end
    return count
end

return module
