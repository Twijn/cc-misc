--- AutoCrafter Default Configuration
---@version 1.0.0

return {
    -- Network channel for crafter communication
    modemChannel = 4200,
    
    -- How often to scan inventories (seconds)
    scanInterval = 30,
    
    -- How often to check craft targets (seconds)
    craftCheckInterval = 10,
    
    -- Maximum crafting batch size
    maxBatchSize = 64,
    
    -- Server label
    serverLabel = "AutoCrafter Server",
    
    -- Crafter timeout (seconds) before marking offline
    crafterTimeout = 60,
    
    -- Recipe search paths
    recipePaths = {
        "/rom/mcdata/minecraft/recipes/",
        "/rom/mcdata/",
    },
    
    -- Message types for network communication
    messageTypes = {
        PING = "ping",
        PONG = "pong",
        STATUS = "status",
        CRAFT_REQUEST = "craft_request",
        CRAFT_COMPLETE = "craft_complete",
        CRAFT_FAILED = "craft_failed",
        INVENTORY_UPDATE = "inventory_update",
        WITHDRAW = "withdraw",
        DEPOSIT = "deposit",
    },
}
