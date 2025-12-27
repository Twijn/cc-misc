# AutoCrafter - Automated Crafting & Storage System

A fully-featured automated crafting and storage system for ComputerCraft that maintains a desired set of items by automatically crafting them when stock runs low.

## Features

- **Automatic Crafting**: Keep items stocked automatically by defining target quantities
- **Recipe Loading**: Loads recipes directly from ROM (`/rom/mcdata/minecraft/recipes/`)
- **Multi-Turtle Support**: Multiple crafter turtles can work together
- **Inventory Scanning**: Scans all connected inventories for item counts
- **Server UI**: Easy-to-use interface to manage settings and view statuses
- **Storage Commands**: Withdraw and deposit items via commands
- **Expandable Architecture**: Designed to grow into a full storage system

## Components

### Server (`server.lua`)
The main server that:
- Coordinates crafter turtles
- Manages the crafting queue
- Provides a terminal UI for configuration
- Handles withdraw/deposit commands
- Scans inventory levels

### Crafter (`crafter.lua`)
Turtle with a crafting table that:
- Receives crafting jobs from the server
- Gathers materials from connected storage
- Crafts items and deposits results
- Reports status back to server

## Installation

```
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/autocrafter/install.lua
```

## Setup

### Server Computer
1. Connect wired modems to all storage inventories
2. Connect a wired modem to the network with crafters
3. Run `server` to start the server
4. Use the UI to add items to the craft queue

### Crafter Turtle
1. Equip the turtle with a crafting table
2. Connect to the network via wired modem
3. Position near storage inventories
4. Run `crafter` to start crafting

## Commands

The server provides a command interface:

- `status` - View system status
- `queue` - View current crafting queue
- `add <item> <quantity>` - Add item to auto-craft list
- `remove <item>` - Remove item from auto-craft list
- `list` - List all auto-craft items
- `scan` - Force inventory rescan
- `withdraw <item> <count>` - Withdraw items from storage
- `deposit [items...]` - Deposit items from player (supports wildcards, e.g., `deposit cobble* *dirt`)
- `crafters` - List connected crafters
- `recipes [search]` - Search available recipes
- `exports` - Manage export inventories (see below)
- `help` - Show help

## Export System

The export system allows automatic item transfer to/from external inventories like ender storages. This is useful for:

- **Stocking ender storages**: Keep remote locations supplied with items
- **Emptying ender storages**: Automatically collect items deposited remotely

### Export Commands

- `exports list` - List all configured export inventories
- `exports add` - Add a new export inventory (opens interactive form)
- `exports remove <name>` - Remove an export inventory
- `exports edit [name]` - Edit an export inventory interactively
- `exports items <name>` - List items for an export inventory
- `exports additem <inv> <item> <qty> [slot]` - Add item to export
- `exports rmitem <inv> <item>` - Remove item from export
- `exports status` - View export system status

### Export Modes

- **Stock Mode**: Push items FROM storage TO the export inventory (keep it stocked)
- **Empty Mode**: Pull items FROM the export inventory TO storage (drain it)

### Example Usage

```
# Add an ender storage as an export target
> exports add

# Edit the export to add items
> exports edit ender_storage_0

# Or add items via command
> exports additem ender_storage_0 torch 64
> exports additem ender_storage_0 coal 128 1  # Slot 1 only
```

## Furnace/Smelting System

The system supports automated smelting via furnaces, blast furnaces, and smokers.

### Furnace Commands

- `furnaces list` - List configured furnaces
- `furnaces discover` - Auto-discover furnaces on the network
- `furnaces add <name>` - Add a furnace by peripheral name
- `furnaces remove <name>` - Remove a furnace
- `furnaces enable/disable <name>` - Enable or disable a furnace
- `furnaces status` - Show detailed furnace status
- `furnaces targets` - List smelt targets
- `furnaces recipes [search]` - Search available smelting recipes

### Adding Smelt Targets

Use the `--smelt` flag with the add command to add items to the smelt list:

```
# Add iron ingots as a smelt target (will smelt raw iron automatically)
> add iron_ingot 128 --smelt

# Add cooked beef as a smelt target
> add cooked_beef 64 --smelt
```

### Furnace Types

- **Furnace**: Can smelt anything
- **Blast Furnace**: Smelts ores faster (preferred for ores)
- **Smoker**: Cooks food faster (preferred for food)

The system will automatically use the appropriate furnace type for each recipe.

## Configuration

Settings are stored in `data/settings.json`:

```json
{
  "craftTargets": {
    "minecraft:torch": 256,
    "minecraft:chest": 32
  },
  "scanInterval": 30,
  "modemChannel": 4200,
  "serverLabel": "AutoCrafter Server"
}
```

## Architecture

```
autocrafter/
├── install.lua          # Installation script
├── server.lua           # Main server application
├── crafter.lua          # Crafter turtle application
├── config.lua           # Default configuration
├── startup.lua          # Startup script
├── update.lua           # Update script
├── lib/
│   ├── recipes.lua      # Recipe loading & parsing
│   ├── inventory.lua    # Inventory management
│   ├── crafting.lua     # Crafting logic
│   ├── comms.lua        # Network communication
│   └── ui.lua           # UI components
├── managers/
│   ├── queue.lua        # Crafting queue manager
│   ├── storage.lua      # Storage manager
│   ├── crafter.lua      # Crafter coordination
│   ├── monitor.lua      # Status display manager
│   ├── export.lua       # Export/ender storage manager
│   └── furnace.lua      # Furnace/smelting manager
└── config/
    ├── settings.lua     # Settings management
    ├── targets.lua      # Craft target management
    ├── exports.lua      # Export inventory management
    └── furnaces.lua     # Furnace configuration
```

## Future Expansions

- **Ender Storage Integration**: ~~Control ender storage frequencies~~ ✓ Added via export system
- **Furnace Integration**: ~~Automated smelting~~ ✓ Added via furnace system
- **Remote API**: HTTP API for external access
- **Multi-server networking**: Connect multiple storage systems
- **Advanced filtering**: Item filters and priorities
- **Recipe learning**: Automatically learn new recipes

## Requirements

- CC:Tweaked (ComputerCraft)
- Wired modems for inventory access
- Wireless modem for crafter communication (optional, can use wired)
- Storage inventory blocks (chests, barrels, etc.)
- Crafty turtle(s) with crafting table
- Furnaces, blast furnaces, or smokers (optional, for smelting)

## Version

Current version: 1.2.0
