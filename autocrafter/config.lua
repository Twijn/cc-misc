--- AutoCrafter Default Configuration
---@version 2.0.0

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
    
    -- Chatbox configuration (for command support)
    chatboxName = "AutoCrafter",  -- Name shown in chat messages
    chatboxEnabled = true,        -- Enable/disable chatbox commands
    chatboxOwner = nil,           -- Player name allowed to use commands (nil = all players)
    
    -- Crafter timeout (seconds) before marking offline
    crafterTimeout = 60,
    
    -- Monitor refresh interval (seconds)
    monitorRefreshInterval = 5,
    
    -- Ping interval for crafters (seconds)
    pingInterval = 30,
    
    -- Recipe search paths
    recipePaths = {
        "/rom/mcdata/minecraft/recipes/",
        "/rom/mcdata/",
    },
    
    -- Message types for network communication
    messageTypes = {
        -- Heartbeat messages
        PING = "ping",
        PONG = "pong",
        STATUS = "status",
        
        -- Crafting messages
        CRAFT_REQUEST = "craft_request",
        CRAFT_COMPLETE = "craft_complete",
        CRAFT_FAILED = "craft_failed",
        
        -- Inventory messages (server -> crafter responses)
        INVENTORY_UPDATE = "inventory_update",
        
        -- Crafter -> Server requests
        REQUEST_STOCK = "request_stock",           -- Request stock levels
        REQUEST_FIND_ITEM = "request_find_item",   -- Request item locations
        REQUEST_WITHDRAW = "request_withdraw",     -- Request items to be pushed to crafter
        REQUEST_DEPOSIT = "request_deposit",       -- Request to accept items from crafter
        
        -- Server -> Crafter responses
        RESPONSE_STOCK = "response_stock",
        RESPONSE_FIND_ITEM = "response_find_item",
        RESPONSE_WITHDRAW = "response_withdraw",
        RESPONSE_DEPOSIT = "response_deposit",
        
        -- Server discovery
        SERVER_ANNOUNCE = "server_announce",       -- Server broadcasts presence
        SERVER_QUERY = "server_query",             -- Client asks for server info
    },
    
    -- Client roles
    roles = {
        SERVER = "server",
        CRAFTER = "crafter",
        UNKNOWN = "unknown",
    },
    
    -- Chatbox commands (via backslash commands in-game)
    -- These are the commands players can use via \command
    chatCommands = {
        "withdraw",   -- \withdraw <item> <count> - Withdraw items to player inventory
        "deposit",    -- \deposit - Deposit items from player inventory to storage
        "stock",      -- \stock [search] - Check stock levels
        "status",     -- \status - Show system status
        "list",       -- \list - Show craft targets
        "help",       -- \help - Show available commands
    },
}
