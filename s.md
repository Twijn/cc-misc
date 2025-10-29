# s

A settings management module for ComputerCraft that provides interactive configuration with automatic validation, peripheral detection, and persistent storage using CC settings. Features: Interactive peripheral selection with type filtering, number input with range validation, string input with default values, boolean selection with menu interface, automatic settings persistence, peripheral availability checking and recovery, and side-only peripheral filtering.

## Functions

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

