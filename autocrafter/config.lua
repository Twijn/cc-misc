--- AutoCrafter Configuration
--- Uses s.lua for interactive configuration with form UI.
---
---@version 3.0.0

local VERSION = "3.0.0"

-- Setup package path
local diskPrefix = fs.exists("disk/lib") and "disk/" or ""
if not package.path:find(diskPrefix .. "lib") then
    package.path = package.path .. ";/" .. diskPrefix .. "?.lua;/" .. diskPrefix .. "lib/?.lua"
end

local s = require("lib.s")

local config = {}

-- Defaults for settings (used when settings don't exist)
local defaults = {
    logLevel = "warn",
    cachePath = "/disk/data/cache",
    modemChannel = 4200,
    storagePeripheralType = "sc-goodies:diamond_barrel",
    scanInterval = 30,
    craftCheckInterval = 1,
    maxBatchSize = 64,
    serverLabel = "AutoCrafter Server",
    chatboxName = "AutoCrafter",
    chatboxEnabled = true,
    chatboxOwner = "",
    crafterTimeout = 60,
    jobTimeout = 120,
    monitorRefreshInterval = 5,
    exportCheckInterval = 2,
    furnaceCheckInterval = 1,
    exportDefaultType = "ender_storage",
    pingInterval = 30,
    parallelTransferThreads = 4,
    parallelScanThreads = 16,
    parallelBatchSize = 8,
    parallelEnabled = true,
}

--- Get a config value from CC settings
---@param key string The setting key
---@return any value The setting value
local function get(key)
    local value = settings.get("ac." .. key)
    if value == nil then
        return defaults[key]
    end
    return value
end

--- Set a config value in CC settings
---@param key string The setting key
---@param value any The value to set
local function set(key, value)
    if value == nil then
        settings.unset("ac." .. key)
    else
        settings.set("ac." .. key, value)
    end
    settings.save()
end

--- Show the settings configuration form
---@return boolean success Whether settings were saved
function config.showSettingsForm()
    local FormUI = require("lib.formui")
    local form = FormUI.new("AutoCrafter Settings")
    
    -- General Settings
    form:label("--- General ---")
    local serverLabelField = form:text("Server Label", get("serverLabel"))
    local logLevelField = form:select("Log Level", {"error", "warn", "info", "debug"}, 
        ({error=1, warn=2, info=3, debug=4})[get("logLevel")] or 2)
    local cachePathField = form:text("Cache Path", get("cachePath"))
    
    -- Network Settings
    form:label("--- Network ---")
    local modemChannelField = form:number("Modem Channel", get("modemChannel"), 
        FormUI.validation.number_range(1, 65535))
    local pingIntervalField = form:number("Ping Interval (sec)", get("pingInterval"),
        FormUI.validation.number_range(5, 300))
    local crafterTimeoutField = form:number("Crafter Timeout (sec)", get("crafterTimeout"),
        FormUI.validation.number_range(10, 600))
    local jobTimeoutField = form:number("Job Timeout (sec)", get("jobTimeout"),
        FormUI.validation.number_range(30, 600))
    
    -- Storage Settings
    form:label("--- Storage ---")
    local storageTypeField = form:text("Storage Peripheral Type", get("storagePeripheralType"))
    local scanIntervalField = form:number("Scan Interval (sec)", get("scanInterval"),
        FormUI.validation.number_range(5, 300))
    local exportDefaultTypeField = form:text("Export Default Type", get("exportDefaultType"))
    
    -- Crafting Settings
    form:label("--- Crafting ---")
    local craftCheckIntervalField = form:number("Craft Check Interval (sec)", get("craftCheckInterval"),
        FormUI.validation.number_range(1, 60))
    local maxBatchSizeField = form:number("Max Batch Size", get("maxBatchSize"),
        FormUI.validation.number_range(1, 64))
    
    -- Monitor Settings
    form:label("--- Monitor ---")
    local monitorRefreshField = form:number("Monitor Refresh (sec)", get("monitorRefreshInterval"),
        FormUI.validation.number_range(1, 60))
    local furnaceCheckField = form:number("Furnace Check (sec)", get("furnaceCheckInterval"),
        FormUI.validation.number_range(1, 60))
    local exportCheckField = form:number("Export Check (sec)", get("exportCheckInterval"),
        FormUI.validation.number_range(1, 60))
    
    -- Chatbox Settings
    form:label("--- Chatbox ---")
    local chatboxEnabledField = form:checkbox("Chatbox Enabled", get("chatboxEnabled"))
    local chatboxNameField = form:text("Chatbox Name", get("chatboxName"))
    local chatboxOwnerField = form:text("Chatbox Owner (blank=all)", get("chatboxOwner") or "")
    
    -- Parallelism Settings
    form:label("--- Parallelism ---")
    local parallelEnabledField = form:checkbox("Parallel Enabled", get("parallelEnabled"))
    local transferThreadsField = form:number("Transfer Threads", get("parallelTransferThreads"),
        FormUI.validation.number_range(1, 32))
    local scanThreadsField = form:number("Scan Threads", get("parallelScanThreads"),
        FormUI.validation.number_range(1, 64))
    local batchSizeField = form:number("Batch Size", get("parallelBatchSize"),
        FormUI.validation.number_range(1, 64))
    
    form:addSubmitCancel()
    
    if form:run() then
        -- Save all settings
        set("serverLabel", serverLabelField())
        set("logLevel", ({"error", "warn", "info", "debug"})[logLevelField()])
        set("cachePath", cachePathField())
        set("modemChannel", modemChannelField())
        set("pingInterval", pingIntervalField())
        set("crafterTimeout", crafterTimeoutField())
        set("jobTimeout", jobTimeoutField())
        set("storagePeripheralType", storageTypeField())
        set("scanInterval", scanIntervalField())
        set("exportDefaultType", exportDefaultTypeField())
        set("craftCheckInterval", craftCheckIntervalField())
        set("maxBatchSize", maxBatchSizeField())
        set("monitorRefreshInterval", monitorRefreshField())
        set("furnaceCheckInterval", furnaceCheckField())
        set("exportCheckInterval", exportCheckField())
        set("chatboxEnabled", chatboxEnabledField())
        set("chatboxName", chatboxNameField())
        local owner = chatboxOwnerField()
        set("chatboxOwner", owner ~= "" and owner or nil)
        set("parallelEnabled", parallelEnabledField())
        set("parallelTransferThreads", transferThreadsField())
        set("parallelScanThreads", scanThreadsField())
        set("parallelBatchSize", batchSizeField())
        
        return true
    end
    
    return false
end

--- Reset all settings to defaults
function config.reset()
    for key, value in pairs(defaults) do
        settings.unset("ac." .. key)
    end
    settings.save()
end

-- Static config values (read-only properties accessed directly)
config.logLevel = get("logLevel")
config.cachePath = get("cachePath")
config.modemChannel = get("modemChannel")
config.storagePeripheralType = get("storagePeripheralType")
config.scanInterval = get("scanInterval")
config.craftCheckInterval = get("craftCheckInterval")
config.maxBatchSize = get("maxBatchSize")
config.serverLabel = get("serverLabel")
config.chatboxName = get("chatboxName")
config.chatboxEnabled = get("chatboxEnabled")
config.chatboxOwner = get("chatboxOwner")
config.crafterTimeout = get("crafterTimeout")
config.jobTimeout = get("jobTimeout")
config.monitorRefreshInterval = get("monitorRefreshInterval")
config.exportCheckInterval = get("exportCheckInterval")
config.furnaceCheckInterval = get("furnaceCheckInterval")
config.exportDefaultType = get("exportDefaultType")
config.pingInterval = get("pingInterval")

-- Parallelism configuration
config.parallelism = {
    transferThreads = get("parallelTransferThreads"),
    scanThreads = get("parallelScanThreads"),
    batchSize = get("parallelBatchSize"),
    enabled = get("parallelEnabled"),
}

-- Recipe search paths (static)
config.recipePaths = {
    "/rom/mcdata/minecraft/recipes/",
    "/rom/mcdata/",
}

-- Message types for network communication (static constants)
config.messageTypes = {
    -- Heartbeat messages
    PING = "ping",
    PONG = "pong",
    STATUS = "status",
    
    -- Crafting messages
    CRAFT_REQUEST = "craft_request",
    CRAFT_COMPLETE = "craft_complete",
    CRAFT_FAILED = "craft_failed",
    
    -- Worker messages
    WORKER_PING = "worker_ping",
    WORKER_PONG = "worker_pong",
    WORKER_STATUS = "worker_status",
    WORK_REQUEST = "work_request",
    WORK_COMPLETE = "work_complete",
    WORK_FAILED = "work_failed",
    
    -- Inventory messages (server -> crafter responses)
    INVENTORY_UPDATE = "inventory_update",
    
    -- Crafter -> Server requests
    REQUEST_STOCK = "request_stock",
    REQUEST_FIND_ITEM = "request_find_item",
    REQUEST_WITHDRAW = "request_withdraw",
    REQUEST_DEPOSIT = "request_deposit",
    REQUEST_CLEAR_SLOTS = "request_clear_slots",
    REQUEST_PULL_SLOT = "request_pull_slot",
    REQUEST_PULL_SLOTS_BATCH = "request_pull_slots_batch",
    
    -- Server -> Crafter responses
    RESPONSE_STOCK = "response_stock",
    RESPONSE_FIND_ITEM = "response_find_item",
    RESPONSE_WITHDRAW = "response_withdraw",
    RESPONSE_DEPOSIT = "response_deposit",
    RESPONSE_CLEAR_SLOTS = "response_clear_slots",
    RESPONSE_PULL_SLOT = "response_pull_slot",
    RESPONSE_PULL_SLOTS_BATCH = "response_pull_slots_batch",
    
    -- Server discovery
    SERVER_ANNOUNCE = "server_announce",
    SERVER_QUERY = "server_query",
    
    -- Remote control
    REBOOT = "reboot",
}

-- Client roles (static constants)
config.roles = {
    SERVER = "server",
    CRAFTER = "crafter",
    WORKER = "worker",
    UNKNOWN = "unknown",
}

-- Chatbox commands (static list)
config.chatCommands = {
    "withdraw",
    "deposit",
    "stock",
    "status",
    "list",
    "help",
}

-- Expose get/set functions for dynamic access
config.get = get
config.set = set
config.defaults = defaults
config.VERSION = VERSION

return config
