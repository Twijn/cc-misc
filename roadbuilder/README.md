# RBC (Road Builder Controller)

A multi-turtle road building system for ComputerCraft with wireless control. Build roads automatically with GPS positioning, configurable road widths, and ender storage integration for extended operations.

## Features

- **GPS Integration**: Turtles track their position using GPS and automatically detect facing direction
- **Wireless Control**: Control multiple turtles from a pocket computer or regular computer
- **Configurable Road Building**:
  - Variable road width (multi-lane support)
  - Automatic block detection from inventory
  - Mines 5 blocks above road surface (configurable)
  - Places road block below turtle position
- **Ender Storage Support**:
  - Automatic refilling of road blocks
  - Debris deposit to ender storage
  - Configurable thresholds
- **Easy Updates**: Integrated updater support for keeping programs current

## Installation

### Quick Install (All Devices)

```lua
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/roadbuilder/install.lua
```

The installer will automatically detect the device type (turtle, pocket computer, or computer) and install the appropriate programs.

### Manual Installation

Download each file manually to the appropriate location:

```
roadbuilder/
├── turtle.lua        -- Main turtle program
├── controller.lua    -- Pocket/computer controller
├── config.lua        -- Configuration file
├── install.lua       -- Installer script
└── lib/
    ├── gps.lua       -- GPS and position tracking
    ├── comms.lua     -- Wireless communications
    └── inventory.lua -- Inventory management
```

## Requirements

### Turtle
- Mining turtle (diamond/netherite pickaxe recommended)
- Wireless modem (for GPS and remote control)
- Road blocks in inventory
- Fuel (coal, charcoal, etc.)
- (Optional) Ender storage for block refill/debris deposit

### Controller (Pocket Computer / Computer)
- Wireless modem (ender modem recommended for range)

### GPS Network
- 4+ GPS host computers for accurate positioning
- See CC:Tweaked documentation for GPS setup

## Usage

### Turtle

After installation, run:
```
turtle
```

The turtle will:
1. Initialize the wireless modem
2. Acquire GPS position
3. Detect facing direction
4. Scan inventory for road blocks
5. Wait for commands from the controller

### Controller

After installation, run:
```
controller
```

The controller provides an interactive UI:

#### Main Menu
- **[1-9]** Select a turtle by number
- **[R]** Refresh turtle list
- **[P]** Ping all turtles
- **[Q]** Quit

#### Turtle Control Menu
- **[F]** Build Forward - Build road in front of turtle
- **[B]** Build Backward - Build road behind turtle
- **[U]** Move Up - Move turtle up
- **[D]** Move Down - Move turtle down
- **[L]** Turn Left
- **[R]** Turn Right
- **[W]** Set Width - Change road width
- **[T]** Set Block Type - Manually set road block
- **[H]** Go Home - Navigate to home position
- **[G]** Set Home - Set current position as home
- **[I]** Refill - Refill blocks from ender storage
- **[O]** Deposit - Deposit debris to ender storage
- **[S]** Stop - Stop current operation
- **[ESC]** Back to turtle list

## Configuration

Edit `config.lua` to customize behavior:

```lua
-- Network Settings
config.NETWORK = {
    CHANNEL = 4521,           -- Communication channel
    REPLY_CHANNEL = 4522,     -- Reply channel
    GPS_TIMEOUT = 2,          -- GPS timeout in seconds
    HEARTBEAT_INTERVAL = 5,   -- Status update interval
}

-- Road Settings
config.ROAD = {
    DEFAULT_WIDTH = 3,        -- Default road width
    MINE_HEIGHT = 5,          -- Blocks to mine above road
    DEFAULT_BLOCK = nil,      -- Auto-detect from inventory
}

-- Ender Storage
config.ENDER_STORAGE = {
    ENABLED = true,
    REFILL_THRESHOLD = 0.25,  -- Refill at 25% blocks remaining
    DEPOSIT_THRESHOLD = 0.75, -- Deposit at 75% debris capacity
}

-- Fuel Settings
config.FUEL = {
    MINIMUM = 500,            -- Min fuel before warning
    TARGET = 2000,            -- Target fuel when refueling
}
```

## Road Building Process

When building a road, the turtle:

1. **Places road block below** - Places the configured block type beneath the turtle
2. **Mines column above** - Mines blocks from current position up to `MINE_HEIGHT`
3. **Moves forward** - Advances to the next position
4. **Repeats** - Continues for the specified distance

For wide roads (width > 1):
- Builds first lane forward
- Shifts to next lane
- Builds lane in opposite direction (serpentine pattern)
- Returns to starting side when complete

## Ender Storage Setup

### Block Refill
1. Place ender storage containing road blocks in turtle inventory
2. Set the same frequency on an ender chest connected to your block supply
3. Turtle will automatically refill when blocks run low

### Debris Deposit
1. Same ender storage or a separate one can be used
2. Turtle deposits non-road-block items when inventory fills up
3. Connect the other end to a storage system or void

## Updating

RBC supports automatic updates through the cc-misc updater:

```lua
local updater = require("updater")
updater.update("roadbuilder")
```

Or re-run the installer to get the latest version:
```lua
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/roadbuilder/install.lua
```

## Troubleshooting

### No GPS Signal
- Ensure GPS network is set up with 4+ GPS hosts
- Check that turtle has a wireless modem equipped
- Verify GPS hosts are powered and running

### Turtles Not Connecting
- Verify both devices have wireless modems
- Check that channels match in `config.lua`
- Ensure devices are within wireless range

### Running Out of Blocks
- Enable ender storage in config
- Add ender storage to turtle inventory
- Connect ender storage to block supply

### Low Fuel
- Add fuel items to turtle inventory
- Configure auto-refuel from ender storage
- Increase `FUEL.MINIMUM` warning threshold

## Dependencies

RBC uses these cc-misc libraries:
- `attach` - Safe block digging and tool management
- `log` - Colored logging with file output
- `persist` - State persistence across restarts
- `updater` - (Optional) Automatic updates
- `formui` - (Optional) Form UI for configuration

## License

MIT License - See repository LICENSE file.

## Contributing

Issues and pull requests welcome at: https://github.com/Twijn/cc-misc
