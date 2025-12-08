--- RBC Configuration
--- Edit this file to customize road building behavior
---
---@version 1.2.0

local config = {}

-- ======= Network Settings =======
config.NETWORK = {
    -- Wireless modem channel for turtle-controller communication
    CHANNEL = 4521,
    -- Reply channel for responses
    REPLY_CHANNEL = 4522,
    -- GPS timeout in seconds
    GPS_TIMEOUT = 2,
    -- Heartbeat interval (seconds) - how often turtles report status
    HEARTBEAT_INTERVAL = 5,
}

-- ======= Road Settings =======
config.ROAD = {
    -- Default road width (number of blocks)
    DEFAULT_WIDTH = 3,
    -- Height to mine above the road surface
    MINE_HEIGHT = 5,
    -- Default road block (will be auto-detected from inventory if not set)
    DEFAULT_BLOCK = nil, -- e.g., "minecraft:stone_bricks"
}

-- ======= Ender Storage Settings =======
config.ENDER_STORAGE = {
    -- Enable ender storage for automatic block refill and debris deposit
    ENABLED = true,
    -- Ender storage for depositing broken blocks (debris)
    -- Set to a color code like "white" or specific ender storage name
    DEBRIS_STORAGE = nil,
    -- Ender storage for refilling road blocks
    -- Can use same storage or different one
    REFILL_STORAGE = nil,
    -- When to trigger a refill (percentage of inventory empty)
    REFILL_THRESHOLD = 0.25, -- 25% of road blocks remaining
    -- When to deposit debris (percentage of inventory full with non-road blocks)
    DEPOSIT_THRESHOLD = 0.75, -- 75% of non-road slots full
}

-- ======= Fuel Settings =======
config.FUEL = {
    -- Minimum fuel level before stopping for refuel
    MINIMUM = 500,
    -- Target fuel level when refueling
    TARGET = 2000,
    -- Fuel items in order of preference
    ITEMS = {
        "minecraft:coal",
        "minecraft:charcoal",
        "minecraft:coal_block",
        "minecraft:lava_bucket",
    },
}

-- ======= Tool Settings =======
config.TOOLS = {
    -- Preferred pickaxe for digging
    PICKAXE = "minecraft:diamond_pickaxe",
    -- Blocks that should never be mined
    PROTECTED_BLOCKS = {
        "minecraft:chest",
        "minecraft:trapped_chest",
        "minecraft:barrel",
        "minecraft:ender_chest",
        "computercraft:turtle_normal",
        "computercraft:turtle_advanced",
        "computercraft:computer_normal",
        "computercraft:computer_advanced",
    },
}

-- ======= Display Settings (for controller) =======
config.DISPLAY = {
    -- Enable color output
    COLORS = true,
    -- Refresh rate for controller display (seconds)
    REFRESH_RATE = 1,
    -- Show detailed turtle information
    SHOW_DETAILS = true,
}

-- ======= Updater Settings =======
config.UPDATER = {
    -- Base URL for updates
    BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main/roadbuilder/",
    -- Check for updates on startup
    CHECK_ON_STARTUP = true,
}

return config
