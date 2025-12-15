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
- `deposit <item>` - Deposit all of item type
- `crafters` - List connected crafters
- `recipes [search]` - Search available recipes
- `help` - Show help

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
│   └── monitor.lua      # Status display manager
└── config/
    ├── settings.lua     # Settings management
    └── targets.lua      # Craft target management
```

## Future Expansions

- **Ender Storage Integration**: Control ender storage frequencies
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

## Version

Current version: 1.0.0
