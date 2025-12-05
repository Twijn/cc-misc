# Netherite Mining Program

A netherite mining turtle program that uses a Plethora scanner to locate and mine ancient debris in the Nether. Automatically deposits items to an ender storage when inventory gets full.

## Features

- **Plethora Scanner Integration**: Scans for ancient debris within range
- **Smart Navigation**: Tracks position and navigates to targets efficiently
- **Safe Block Protection**: Uses the attach library to avoid digging storage blocks
- **Automatic Tool Management**: Equips the right tools for the job
- **Ender Storage Deposits**: Automatically deposits items when inventory is full
- **Fuel Management**: Monitors fuel levels and auto-refuels when possible
- **State Persistence**: Saves position and statistics to survive reboots
- **Logging**: Full logging of operations to console and file

## Requirements

- **Turtle**: Advanced turtle recommended
- **Pickaxe**: Diamond or netherite pickaxe (equipped or in inventory)
- **Plethora Scanner**: `plethora:module_scanner` (equippable module)
- **Ender Storage**: Ender chest/pouch from Ender Storage mod
- **Fuel**: Coal, charcoal, coal blocks, or lava buckets
- **Wireless Modem** (optional): For GPS and communication

## Installation

Install the program using:
```text
wget run https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/netherite/install.lua
```

Or manually:
```text
mkdir lib
wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/attach.lua lib/attach.lua
wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/log.lua lib/log.lua
wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/persist.lua lib/persist.lua
wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/netherite/miner.lua startup.lua
```

## Usage

1. Place the turtle in the Nether at Y level 15 (optimal for ancient debris)
2. Ensure the turtle has:
   - Fuel (coal/charcoal)
   - A pickaxe (diamond or netherite)
   - A plethora scanner module (will be auto-equipped)
   - An ender storage for depositing items
3. Run the program:
   ```text
   miner
   ```
   Or if installed as `startup.lua`, simply reboot the turtle.

## Configuration

The program has configurable options at the top of `miner.lua`:

| Setting | Default | Description |
|---------|---------|-------------|
| `SCAN_RADIUS` | 8 | Plethora scanner range |
| `SCAN_INTERVAL` | 2 | Seconds between scans |
| `DEPOSIT_THRESHOLD` | 14 | Deposit when N slots are full |
| `FUEL_MINIMUM` | 500 | Minimum fuel before stopping |
| `FUEL_REFUEL_LEVEL` | 1000 | Target fuel level when refueling |

## How It Works

1. **Scanning**: The turtle uses the Plethora scanner to detect ancient debris within range
2. **Navigation**: When debris is found, it calculates the relative position and navigates there
3. **Mining**: Uses the attach library's safe dig functions to mine the debris
4. **Exploration**: When no debris is found, it explores in a random pattern
5. **Deposits**: When inventory is near full, places ender storage and deposits items
6. **Persistence**: Position and stats are saved, allowing recovery after crashes

## Statistics Tracked

- Ancient debris found
- Total blocks mined
- Number of deposits made
- Current position

## Libraries Used

- `attach.lua` - Safe block interaction and peripheral management
- `log.lua` - Colored logging with file output
- `persist.lua` - JSON-based state persistence
