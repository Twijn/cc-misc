--- AutoCrafter Settings Configuration
--- Manages server settings.
---
---@version 1.0.0

local persist = require("lib.persist")
local config = require("config")

local settings = persist("settings.json")

-- Set defaults from config
settings.setDefault("modemChannel", config.modemChannel)
settings.setDefault("scanInterval", config.scanInterval)
settings.setDefault("craftCheckInterval", config.craftCheckInterval)
settings.setDefault("maxBatchSize", config.maxBatchSize)
settings.setDefault("serverLabel", config.serverLabel)
settings.setDefault("crafterTimeout", config.crafterTimeout)
settings.setDefault("cachePath", config.cachePath)

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
end

---Get all settings
---@return table settings All settings
function module.getAll()
    return settings.getAll()
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
end

return module
