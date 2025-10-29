# s

A settings management module for ComputerCraft that provides interactive configuration with automatic validation, peripheral detection, and persistent storage using CC settings. Features: - Interactive peripheral selection with type filtering - Number input with range validation - String input with default values - Boolean selection with menu interface - Automatic settings persistence - Peripheral availability checking and recovery - Side-only peripheral filtering @usage local s = require("s") local modem = s.peripheral("modem", "modem", true) -- Side-attached modems only local port = s.number("port", 1, 65535, 8080) -- Port 1-65535, default 8080 local name = s.string("server_name", "MyServer") -- String with default local enabled = s.boolean("enabled") -- Boolean selection

## Functions

### `selectMenu(title, subtitle, options, selected?)`

Display an interactive menu for selecting from a list of options

**Parameters:**

- `title` (string): The main title to display
- `subtitle` (string): The subtitle/description to display
- `options` (string[]): Array of selectable options
- `selected?` (number): Currently selected option index (defaults to 1)

**Returns:** string # The selected option string

### `requestPeripheral(name, type, sideOnly?)`

Interactively request user to select a peripheral of a specific type

**Parameters:**

- `name` (string): The setting name to store the selection
- `type` (string): The peripheral type to filter for
- `sideOnly?` (boolean): If true, only show peripherals attached to computer sides

**Returns:** string # The selected peripheral name

### `module.peripheral(name, type, sideOnly?)`

Get or configure a peripheral setting with automatic validation and recovery

**Parameters:**

- `name` (string): The setting name to store/retrieve
- `type` (string): The required peripheral type (e.g., "modem", "monitor")
- `sideOnly?` (boolean): If true, only allow peripherals attached to computer sides

**Returns:** table # The wrapped peripheral object

### `module.number(name, from?, to?, default?)`

Get or configure a number setting with range validation

**Parameters:**

- `name` (string): The setting name to store/retrieve
- `from?` (number): Minimum allowed value (nil for no minimum)
- `to?` (number): Maximum allowed value (nil for no maximum)
- `default?` (number): Default value if user provides empty input

**Returns:** number # The configured number value

### `module.string(name, default?)`

Get or configure a string setting with optional default value

**Parameters:**

- `name` (string): The setting name to store/retrieve
- `default?` (string): Default value if user provides empty input

**Returns:** string # The configured string value

### `module.boolean(name)`

Get or configure a boolean setting using an interactive menu

**Parameters:**

- `name` (string): The setting name to store/retrieve

**Returns:** boolean # The configured boolean value

