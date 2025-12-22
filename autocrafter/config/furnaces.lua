--- AutoCrafter Furnace Configuration
--- Manages furnace peripherals for smelting operations.
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")

local furnaces = persist("furnace-config.json")

furnaces.setDefault("furnaces", {})
furnaces.setDefault("smeltTargets", {})

local module = {}

---@class FurnaceConfig
---@field name string The peripheral name
---@field type string The furnace type (furnace, blast_furnace, smoker)
---@field enabled boolean Whether the furnace is enabled for smelting

---Add or update a furnace
---@param name string The peripheral name
---@param furnaceType? string The furnace type (auto-detected if nil)
function module.add(name, furnaceType)
    local furnaceList = furnaces.get("furnaces") or {}
    
    -- Auto-detect type if not provided
    if not furnaceType then
        local p = peripheral.wrap(name)
        if p then
            local types = {peripheral.getType(name)}
            for _, t in ipairs(types) do
                if t == "minecraft:furnace" or t == "furnace" then
                    furnaceType = "furnace"
                    break
                elseif t == "minecraft:blast_furnace" or t == "blast_furnace" then
                    furnaceType = "blast_furnace"
                    break
                elseif t == "minecraft:smoker" or t == "smoker" then
                    furnaceType = "smoker"
                    break
                end
            end
        end
        furnaceType = furnaceType or "furnace"
    end
    
    furnaceList[name] = {
        name = name,
        type = furnaceType,
        enabled = true,
    }
    furnaces.set("furnaces", furnaceList)
    logger.info(string.format("Added furnace: %s (%s)", name, furnaceType))
end

---Remove a furnace
---@param name string The peripheral name
function module.remove(name)
    local furnaceList = furnaces.get("furnaces") or {}
    furnaceList[name] = nil
    furnaces.set("furnaces", furnaceList)
    logger.info(string.format("Removed furnace: %s", name))
end

---Enable or disable a furnace
---@param name string The peripheral name
---@param enabled boolean Whether to enable
function module.setEnabled(name, enabled)
    local furnaceList = furnaces.get("furnaces") or {}
    if furnaceList[name] then
        furnaceList[name].enabled = enabled
        furnaces.set("furnaces", furnaceList)
        logger.info(string.format("%s furnace: %s", enabled and "Enabled" or "Disabled", name))
    end
end

---Get a furnace by name
---@param name string The peripheral name
---@return FurnaceConfig|nil furnace The furnace config
function module.get(name)
    local furnaceList = furnaces.get("furnaces") or {}
    return furnaceList[name]
end

---Get all furnaces
---@return table<string, FurnaceConfig> furnaces All furnace configs
function module.getAll()
    return furnaces.get("furnaces") or {}
end

---Get enabled furnaces of a specific type
---@param furnaceType? string Optional type filter (furnace, blast_furnace, smoker)
---@return FurnaceConfig[] furnaces Array of enabled furnaces
function module.getEnabled(furnaceType)
    local furnaceList = furnaces.get("furnaces") or {}
    local result = {}
    
    for _, furnace in pairs(furnaceList) do
        if furnace.enabled then
            if not furnaceType or furnace.type == furnaceType then
                table.insert(result, furnace)
            end
        end
    end
    
    return result
end

---Count furnaces
---@return number count Number of furnaces
function module.count()
    local furnaceList = furnaces.get("furnaces") or {}
    local count = 0
    for _ in pairs(furnaceList) do
        count = count + 1
    end
    return count
end

---Clear all furnaces
function module.clear()
    furnaces.set("furnaces", {})
    logger.info("Cleared all furnaces")
end

---Add or update a smelt target
---@param item string The item ID to smelt
---@param quantity number Target quantity to maintain
function module.setSmeltTarget(item, quantity)
    local targets = furnaces.get("smeltTargets") or {}
    targets[item] = quantity
    furnaces.set("smeltTargets", targets)
    logger.info(string.format("Set smelt target: %s x%d", item, quantity))
end

---Remove a smelt target
---@param item string The item ID
function module.removeSmeltTarget(item)
    local targets = furnaces.get("smeltTargets") or {}
    targets[item] = nil
    furnaces.set("smeltTargets", targets)
    logger.info(string.format("Removed smelt target: %s", item))
end

---Get a smelt target
---@param item string The item ID
---@return number|nil quantity The target quantity
function module.getSmeltTarget(item)
    local targets = furnaces.get("smeltTargets") or {}
    return targets[item]
end

---Get all smelt targets
---@return table<string, number> targets All smelt targets
function module.getAllSmeltTargets()
    return furnaces.get("smeltTargets") or {}
end

---Get smelt targets with current stock levels
---@param stockLevels table Current stock levels
---@return table targets Array of {item, target, current, needed}
function module.getSmeltTargetsWithStock(stockLevels)
    local targets = furnaces.get("smeltTargets") or {}
    local result = {}
    
    for item, quantity in pairs(targets) do
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

---Get smelt items that need smelting
---@param stockLevels table Current stock levels
---@return table needed Array of {item, target, current, needed}
function module.getNeededSmelt(stockLevels)
    local all = module.getSmeltTargetsWithStock(stockLevels)
    local needed = {}
    
    for _, target in ipairs(all) do
        if target.needed > 0 then
            table.insert(needed, target)
        end
    end
    
    return needed
end

return module
