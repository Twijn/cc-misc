--- Router Configuration
--- Edit this file to customize router behavior
---
---@version 1.0.0

local config = {}

-- ======= Router Identity =======
config.ROUTER = {
    -- Router ID in hierarchical format:
    -- 1xx = Main server layer (e.g., 101, 102, 103)
    -- 2xx = Secondary layer (e.g., 201, 202)
    -- 3xx = Tertiary layer (e.g., 301, 302)
    -- This should be set per-router via settings or install
    ID = nil, -- Will be configured on first run
    
    -- Whether this router is a final destination (executes messages)
    -- vs a midway router (just forwards messages)
    IS_FINAL = false,
}

-- ======= Network Settings =======
config.NETWORK = {
    -- Default port for router communication
    DEFAULT_PORT = 4800,
    
    -- Maximum number of hops before a message is dropped
    MAX_HOPS = 64,
    
    -- Message receive timeout (seconds)
    RECEIVE_TIMEOUT = 30,
    
    -- Heartbeat interval for router status (seconds)
    HEARTBEAT_INTERVAL = 10,
}

-- ======= Port Configuration =======
-- Maximum number of ports per modem side
config.PORTS = {
    MAX_PORTS_PER_SIDE = 128,
    
    -- Default ports to open on startup
    -- Format: {port1, port2, ...}
    DEFAULT_PORTS = {4800, 4801, 4802},
}

-- ======= Modem Configuration =======
-- Which sides to attach modems on startup
-- Set to nil to auto-detect all modems
config.MODEMS = {
    -- Explicit modem sides (nil = auto-detect)
    SIDES = nil, -- e.g., {"top", "back"}
    
    -- Whether to use wired modems (false = wireless only)
    ALLOW_WIRED = true,
}

-- ======= Routing Table =======
-- Default routes for message forwarding
-- Format: prefix = "modem_side"
-- Example: [1] = "top" means all 1xx destinations go through top modem
config.ROUTES = {
    -- These should be configured per-router
    -- [1] = "top",    -- Route to 1xx routers
    -- [2] = "back",   -- Route to 2xx routers
    -- [3] = "left",   -- Route to 3xx routers
}

-- ======= Filtering =======
config.FILTERS = {
    -- Protocols to block (true = blocked)
    BLOCKED_PROTOCOLS = {
        -- ["debug"] = true,
    },
    
    -- Ports to block (true = blocked)
    BLOCKED_PORTS = {
        -- [9999] = true,
    },
}

-- ======= Logging =======
config.LOGGING = {
    -- Enable verbose logging
    VERBOSE = true,
    
    -- Log all message hops
    LOG_HOPS = true,
    
    -- Log filtered/blocked messages
    LOG_FILTERED = true,
}

-- ======= Protocol Handlers =======
-- Default protocols that final routers should handle
config.PROTOCOLS = {
    -- Ping/pong for network testing
    PING = "router.ping",
    PONG = "router.pong",
    
    -- Status request/response
    STATUS_REQUEST = "router.status.request",
    STATUS_RESPONSE = "router.status.response",
    
    -- Command execution (for final routers)
    COMMAND = "router.command",
    COMMAND_RESPONSE = "router.command.response",
    
    -- Discovery protocol
    DISCOVER = "router.discover",
    ANNOUNCE = "router.announce",
}

return config
