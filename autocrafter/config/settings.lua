--- AutoCrafter Settings Configuration
--- Manages server settings.
---
---@version 1.1.0

local persist = require("lib.persist")
local config = require("config")

local settings = persist("settings.json")

-- Get parallelism defaults from config
local defaultParallelism = config.parallelism or {}

-- Set defaults from config
settings.setDefault("modemChannel", config.modemChannel)
settings.setDefault("scanInterval", config.scanInterval)
settings.setDefault("craftCheckInterval", config.craftCheckInterval)
settings.setDefault("maxBatchSize", config.maxBatchSize)
settings.setDefault("serverLabel", config.serverLabel)
settings.setDefault("crafterTimeout", config.crafterTimeout)
settings.setDefault("cachePath", config.cachePath)

-- Parallelism settings
settings.setDefault("parallelTransferThreads", defaultParallelism.transferThreads or 4)
settings.setDefault("parallelScanThreads", defaultParallelism.scanThreads or 16)
settings.setDefault("parallelBatchSize", defaultParallelism.batchSize or 8)
settings.setDefault("parallelEnabled", defaultParallelism.enabled ~= false)

local module = {}

---Get a setting value
---@param key string The setting key
---@return any value The setting value
function module.get(key)
    return settings.get(key)
end

---Set a setting value
---@param key string The setting key
---@param value any The setting value
function module.set(key, value)
    settings.set(key, value)
    
    -- If parallelism setting changed, update inventory library
    if key:find("^parallel") then
        module.applyParallelSettings()
    end
end

---Get all settings
---@return table settings All settings
function module.getAll()
    return settings.getAll()
end

---Get parallelism configuration table
---@return table parallelism Current parallelism settings
function module.getParallelism()
    return {
        transferThreads = settings.get("parallelTransferThreads"),
        scanThreads = settings.get("parallelScanThreads"),
        batchSize = settings.get("parallelBatchSize"),
        enabled = settings.get("parallelEnabled"),
    }
end

---Apply parallelism settings to inventory library
function module.applyParallelSettings()
    local ok, inventory = pcall(require, "lib.inventory")
    if ok and inventory and inventory.setParallelConfig then
        inventory.setParallelConfig(module.getParallelism())
    end
end

-- Default deposit excludes - item types to skip when depositing all items
local defaultDepositExcludes = {
    -- Tools
    "minecraft:wooden_pickaxe", "minecraft:stone_pickaxe", "minecraft:iron_pickaxe",
    "minecraft:golden_pickaxe", "minecraft:diamond_pickaxe", "minecraft:netherite_pickaxe",
    "minecraft:wooden_axe", "minecraft:stone_axe", "minecraft:iron_axe",
    "minecraft:golden_axe", "minecraft:diamond_axe", "minecraft:netherite_axe",
    "minecraft:wooden_shovel", "minecraft:stone_shovel", "minecraft:iron_shovel",
    "minecraft:golden_shovel", "minecraft:diamond_shovel", "minecraft:netherite_shovel",
    "minecraft:wooden_hoe", "minecraft:stone_hoe", "minecraft:iron_hoe",
    "minecraft:golden_hoe", "minecraft:diamond_hoe", "minecraft:netherite_hoe",
    "minecraft:shears", "minecraft:flint_and_steel", "minecraft:fishing_rod",
    "minecraft:bow", "minecraft:crossbow", "minecraft:trident", "minecraft:shield",
    
    -- Swords
    "minecraft:wooden_sword", "minecraft:stone_sword", "minecraft:iron_sword",
    "minecraft:golden_sword", "minecraft:diamond_sword", "minecraft:netherite_sword",
    
    -- Armor
    "minecraft:leather_helmet", "minecraft:leather_chestplate", "minecraft:leather_leggings", "minecraft:leather_boots",
    "minecraft:chainmail_helmet", "minecraft:chainmail_chestplate", "minecraft:chainmail_leggings", "minecraft:chainmail_boots",
    "minecraft:iron_helmet", "minecraft:iron_chestplate", "minecraft:iron_leggings", "minecraft:iron_boots",
    "minecraft:golden_helmet", "minecraft:golden_chestplate", "minecraft:golden_leggings", "minecraft:golden_boots",
    "minecraft:diamond_helmet", "minecraft:diamond_chestplate", "minecraft:diamond_leggings", "minecraft:diamond_boots",
    "minecraft:netherite_helmet", "minecraft:netherite_chestplate", "minecraft:netherite_leggings", "minecraft:netherite_boots",
    "minecraft:turtle_helmet", "minecraft:elytra",
    
    -- Food (commonly eaten)
    "minecraft:cooked_beef", "minecraft:cooked_porkchop", "minecraft:cooked_chicken",
    "minecraft:cooked_mutton", "minecraft:cooked_rabbit", "minecraft:cooked_cod", "minecraft:cooked_salmon",
    "minecraft:baked_potato", "minecraft:bread", "minecraft:golden_apple", "minecraft:enchanted_golden_apple",
    "minecraft:golden_carrot", "minecraft:apple",
}

---Get deposit excludes list
---@return table excludes Array of item IDs to exclude from deposit
function module.getDepositExcludes()
    local excludes = settings.get("depositExcludes")
    if excludes then
        return excludes
    end
    return defaultDepositExcludes
end

---Set deposit excludes list
---@param excludes table Array of item IDs to exclude
function module.setDepositExcludes(excludes)
    settings.set("depositExcludes", excludes)
end

---Add item to deposit excludes
---@param item string The item ID to add
function module.addDepositExclude(item)
    local excludes = module.getDepositExcludes()
    -- Check if already in list
    for _, ex in ipairs(excludes) do
        if ex == item then return end
    end
    table.insert(excludes, item)
    settings.set("depositExcludes", excludes)
end

---Remove item from deposit excludes
---@param item string The item ID to remove
function module.removeDepositExclude(item)
    local excludes = module.getDepositExcludes()
    for i, ex in ipairs(excludes) do
        if ex == item then
            table.remove(excludes, i)
            settings.set("depositExcludes", excludes)
            return
        end
    end
end

---Check if item is in deposit excludes
---@param item string The item ID to check
---@return boolean excluded Whether the item is excluded
function module.isDepositExcluded(item)
    local excludes = module.getDepositExcludes()
    for _, ex in ipairs(excludes) do
        if ex == item or item:find(ex, 1, true) then
            return true
        end
    end
    return false
end

---Reset settings to defaults
function module.reset()
    settings.setAll({})
    settings.setDefault("modemChannel", config.modemChannel)
    settings.setDefault("scanInterval", config.scanInterval)
    settings.setDefault("craftCheckInterval", config.craftCheckInterval)
    settings.setDefault("maxBatchSize", config.maxBatchSize)
    settings.setDefault("serverLabel", config.serverLabel)
    settings.setDefault("crafterTimeout", config.crafterTimeout)
    settings.setDefault("cachePath", config.cachePath)
    settings.setDefault("parallelTransferThreads", defaultParallelism.transferThreads or 4)
    settings.setDefault("parallelScanThreads", defaultParallelism.scanThreads or 16)
    settings.setDefault("parallelBatchSize", defaultParallelism.batchSize or 8)
    settings.setDefault("parallelEnabled", defaultParallelism.enabled ~= false)
end

return module
