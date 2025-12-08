# attach

A turtle utility module for ComputerCraft that provides safe block interaction, automatic tool management, and peripheral handling for turtles. Features: Automatic tool equipping based on action type (dig, attack, place), unsafe block protection to prevent accidentally digging storage blocks, peripheral auto-placement and wrapping, modem protection (never unequips modems), configurable default and always-equipped tools, and proxy wrappers for peripherals.

## Examples

```lua
local attach = require("attach")
-- Set up default tools
attach.setDefaultEquipped("minecraft:diamond_pickaxe", "minecraft:diamond_sword")
attach.setAlwaysEquipped("computercraft:wireless_modem_advanced")
-- Safe digging (won't dig chests, other turtles, etc.)
attach.dig()      -- Automatically equips pickaxe
attach.digUp()    -- Also safe
attach.digDown()  -- Also safe
-- Attack with automatic sword equipping
attach.attack()
-- Find and wrap a peripheral
local modem = attach.find("modem")
```

## Functions

### `module.setDefaultEquipped(leftTool, rightTool)`

Set the default tools to be equipped on each side

**Parameters:**

- `leftTool` (string|nil): The tool to equip on the left side (e.g., "minecraft:diamond_pickaxe")
- `rightTool` (string|nil): The tool to equip on the right side (e.g., "minecraft:diamond_sword")

### `module.setAlwaysEquipped(toolName)`

Set a tool that should always be kept equipped (has highest priority)

**Parameters:**

- `toolName` (string|nil): The tool that should always be equipped

### `module.wrap(peripheralName, side)`

Wrap a peripheral, automatically placing it if not present

**Parameters:**

- `peripheralName` (string): The name/type of peripheral to wrap
- `side` (string): The side to place/wrap the peripheral on ("top", "bottom", "front", "back", "left", "right")

**Returns:** table # A proxy table with all peripheral methods that auto-replaces if removed

### `module.find(peripheralType)`

Find and wrap a peripheral by type, equipping it as a tool if necessary

**Parameters:**

- `peripheralType` (string): The type of peripheral to find (e.g., "modem", "workbench")

**Returns:** string|nil # Error message if peripheral was not found

### `module.getScanner()`

Get a plethora block scanner if available Returns a cached scanner proxy if already found, otherwise tries to find and wrap one

**Returns:** table|nil # A scanner proxy with scan() method, or nil if not found

### `module.hasScanner()`

Check if a plethora scanner is available

**Returns:** boolean # True if a scanner is available

### `module._debug()`

Print debug information about the module state, peripherals, and inventory Pauses between sections for user to read (press Enter to continue)

