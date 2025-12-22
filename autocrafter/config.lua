--- AutoCrafter Default Configuration
---@version 2.1.0

return {
    -- Cache storage path (for inventories.json, item-details.json, stock.json)
    -- Must be an absolute path (starting with /) to bypass persist.lua's data/ prefix
    -- Set to nil to use default "/disk/data/cache"
    cachePath = "/disk/data/cache",
    
    -- Network channel for crafter communication
    modemChannel = 4200,
    
    -- Storage peripheral type (items are deposited to/withdrawn from these)
    storagePeripheralType = "sc-goodies:diamond_barrel",
    
    -- How often to scan inventories (seconds)
    scanInterval = 30,
    
    -- How often to check craft targets (seconds)
    craftCheckInterval = 1,
    
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
    
    -- Job timeout (seconds) - assigned/crafting jobs older than this are reset
    jobTimeout = 120,

    -- Monitor refresh interval (seconds)
    monitorRefreshInterval = 5,
    
    -- Export check interval (seconds)
    exportCheckInterval = 2,
    
    -- Furnace check interval (seconds)
    furnaceCheckInterval = 1,

    -- Default peripheral type for export inventories
    exportDefaultType = "ender_storage",
    
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
        REQUEST_CLEAR_SLOTS = "request_clear_slots", -- Request to pull items from specific slots (legacy)
        REQUEST_PULL_SLOT = "request_pull_slot",   -- Request to pull a specific slot with known contents
        
        -- Server -> Crafter responses
        RESPONSE_STOCK = "response_stock",
        RESPONSE_FIND_ITEM = "response_find_item",
        RESPONSE_WITHDRAW = "response_withdraw",
        RESPONSE_DEPOSIT = "response_deposit",
        RESPONSE_CLEAR_SLOTS = "response_clear_slots",
        RESPONSE_PULL_SLOT = "response_pull_slot",
        
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
    
    -- Parallelism configuration for inventory operations
    -- Higher values = faster operations but more peripheral calls at once
    -- Set to 1 to disable parallelism (sequential execution)
    parallelism = {
        -- Number of concurrent transfer operations for withdraw/deposit/clear
        -- Recommended: 4-8 for most systems, reduce if experiencing issues
        transferThreads = 4,
        
        -- Number of concurrent inventory scans
        -- This is already used by the scan function
        scanThreads = 16,
        
        -- Batch size for grouping operations before parallel execution
        -- Larger batches = fewer parallel.waitForAll calls but longer waits
        batchSize = 8,
        
        -- Enable/disable parallel transfers entirely
        enabled = true,
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
