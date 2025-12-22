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
