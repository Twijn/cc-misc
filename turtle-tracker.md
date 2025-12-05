# turtle-tracker

A turtle API client module for ComputerCraft that provides easy integration with the krawlet-api turtle tracking system. Features: Automatic stat tracking, position reporting, configurable API endpoint, periodic sync support, and simple state management for turtle data.

## Examples

```lua
local turtleApi = require("turtleApi")
-- Configure the API endpoint
turtleApi.setEndpoint("http://localhost:3000")
-- Initialize with turtle ID (defaults to os.getComputerID())
turtleApi.init()
-- Update stats
turtleApi.incrementStat("blocks_mined")
turtleApi.incrementStat("debris_found", 5)
-- Update position
turtleApi.setAbsolutePosition(100, 64, -200)
turtleApi.setRelativePosition(5, 0, 10)
-- Push data to server
turtleApi.sync()
-- Or use auto-sync (syncs every N seconds)
turtleApi.startAutoSync(30)
```

## Functions

### `module.setEndpoint(endpoint)`

Set the API endpoint URL

**Parameters:**

- `endpoint` (string): The base URL of the turtle API (e.g., "http://localhost:3000")

### `module.getEndpoint()`

Get the current API endpoint

**Returns:** string # The current API endpoint URL

### `module.init(id, label)`

Initialize the turtle API client

**Parameters:**

- `id` (string|number|nil): Optional turtle ID (defaults to os.getComputerID())
- `label` (string|nil): Optional turtle label (defaults to os.getComputerLabel())

### `module.setDefault(stats)`

Set default stats (similar to CC state.setDefault pattern)

**Parameters:**

- `stats` (table): Default stat values

### `module.getStats()`

Get the current stats

**Returns:** TurtleStats # Current stats table

### `module.getStat(statName)`

Get a specific stat value

**Parameters:**

- `statName` (string): Name of the stat

**Returns:** number # The stat value

### `module.setStat(statName, value)`

Set a specific stat value

**Parameters:**

- `statName` (string): Name of the stat
- `value` (number): The value to set

### `module.incrementStat(statName, amount)`

Increment a stat by a value (default 1)

**Parameters:**

- `statName` (string): Name of the stat to increment
- `amount` (number|nil): Amount to increment by (default 1)

### `module.decrementStat(statName, amount)`

Decrement a stat by a value (default 1)

**Parameters:**

- `statName` (string): Name of the stat to decrement
- `amount` (number|nil): Amount to decrement by (default 1)

### `module.setAbsolutePosition(x, y, z)`

Set the absolute position (world coordinates)

**Parameters:**

- `x` (number): X coordinate
- `y` (number): Y coordinate
- `z` (number): Z coordinate

### `module.getAbsolutePosition()`

Get the absolute position

**Returns:** TurtlePosition # Absolute position table

### `module.setRelativePosition(x, y, z)`

Set the relative position (from starting point)

**Parameters:**

- `x` (number): X offset
- `y` (number): Y offset
- `z` (number): Z offset

### `module.getRelativePosition()`

Get the relative position

**Returns:** TurtlePosition # Relative position table

### `module.moveRelative(dx, dy, dz)`

Update relative position by offset

**Parameters:**

- `dx` (number): X offset to add
- `dy` (number): Y offset to add
- `dz` (number): Z offset to add

### `module.moveAbsolute(dx, dy, dz)`

Update absolute position by offset

**Parameters:**

- `dx` (number): X offset to add
- `dy` (number): Y offset to add
- `dz` (number): Z offset to add

### `module.setLabel(label)`

Set the turtle label

**Parameters:**

- `label` (string): The label to set

### `module.getLabel()`

Get the turtle label

**Returns:** string|nil # The turtle label

### `module.updateFuel()`

Update fuel level from turtle API

### `module.setFuel(fuel)`

Set fuel level manually

**Parameters:**

- `fuel` (number): The fuel level

### `module.getFuel()`

Get the current fuel level

**Returns:** number|nil # The fuel level

### `module.buildPayload()`

Build the full data payload for syncing

**Returns:** table # The data payload

### `module.sync()`

Sync all turtle data to the server

**Returns:** string|nil # Error message if sync failed

### `module.syncStats()`

Sync only stats to the server

**Returns:** string|nil # Error message if sync failed

### `module.syncPosition()`

Sync only position to the server

**Returns:** string|nil # Error message if sync failed

### `module.fetch()`

Fetch turtle data from the server

**Returns:** table|nil # The turtle data or nil if not found

### `module.fetchAll()`

Fetch all turtles from the server

**Returns:** table|nil # Array of turtle data or nil on error

### `module.delete()`

Delete the current turtle from the server

**Returns:** string|nil # Error message if deletion failed

### `module.deleteById(id)`

Delete a specific turtle by ID from the server

**Parameters:**

- `id` (string|number): The turtle ID to delete

**Returns:** string|nil # Error message if deletion failed

### `module.startAutoSync(intervalSeconds)`

Start automatic syncing at a given interval

**Parameters:**

- `intervalSeconds` (number): Seconds between syncs (default 30)

### `module.stopAutoSync()`

Stop automatic syncing

### `module.isAutoSyncRunning()`

Check if auto-sync is running

**Returns:** boolean # True if auto-sync is active

### `module.forward()`

Wrapper for turtle.forward() that updates relative position

**Returns:** boolean # True if movement succeeded

### `module.back()`

Wrapper for turtle.back() that updates relative position

**Returns:** boolean # True if movement succeeded

### `module.up()`

Wrapper for turtle.up() that updates relative position

**Returns:** boolean # True if movement succeeded

### `module.down()`

Wrapper for turtle.down() that updates relative position

**Returns:** boolean # True if movement succeeded

### `module.dig()`

Wrapper for turtle.dig() that increments blocks_mined stat

**Returns:** boolean # True if dig succeeded

### `module.digUp()`

Wrapper for turtle.digUp() that increments blocks_mined stat

**Returns:** boolean # True if dig succeeded

### `module.digDown()`

Wrapper for turtle.digDown() that increments blocks_mined stat

**Returns:** boolean # True if dig succeeded

### `module._debug()`

Print debug information about the current state

