# s

A settings management module for ComputerCraft that provides interactive configuration with automatic validation, peripheral detection, and persistent storage using CC settings. Features: Interactive peripheral selection with type filtering, number input with range validation, string input with default values, boolean selection with menu interface, automatic settings persistence, peripheral availability checking and recovery, side-only peripheral filtering, and optional form UI integration.

## Examples

```lua
local s = require("s")
local modem = s.peripheral("modem", "modem", true)
local port = s.number("port", 1, 65535, 8080)
local name = s.string("server_name", "MyServer")
local enabled = s.boolean("enabled")
```

```lua
local s = require("s")
local form = s.useForm("My App Configuration")
local modem = form.peripheral("modem", "modem", true)
local port = form.number("port", 1, 65535, 8080)
local name = form.string("server_name", "MyServer")
local enabled = form.boolean("enabled")
if form.submit() then
 print("Settings saved!")
 print("Modem:", modem())
 print("Port:", port())
end
```

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

### `module.color(name, default?)`

Get or configure a color setting using an interactive menu

**Parameters:**

- `name` (string): The setting name to store/retrieve
- `default?` (number): Default color value (e.g., colors.white)

**Returns:** number # The configured color value

### `module.useForm(title?)`

Create a form-based settings interface using formui.lua Requires formui.lua to be installed. Returns a table with form-based versions of all s.lua functions.  local s = require("s") local form = s.useForm("My App Configuration")  local modem = form.peripheral("modem", "modem", true) local port = form.number("port", 1, 65535, 8080) local name = form.string("server_name", "MyServer") local enabled = form.boolean("enabled")  if form.submit() then print("Settings saved!") print("Modem:", modem()) print("Port:", port()) end 

**Parameters:**

- `title?` (string): The form title (defaults to "Settings")

**Returns:** table # Form interface with peripheral, number, string, boolean, and submit functions

### `formInterface.peripheral(name, type, sideOnly?)`

Add a peripheral field to the form

**Parameters:**

- `name` (string): The setting name
- `type` (string): The peripheral type to filter for
- `sideOnly?` (boolean): If true, only show peripherals attached to computer sides

**Returns:** function # Getter function that returns the peripheral name

### `formInterface.number(name, from?, to?, default?)`

Add a number field to the form

**Parameters:**

- `name` (string): The setting name
- `from?` (number): Minimum allowed value
- `to?` (number): Maximum allowed value
- `default?` (number): Default value

**Returns:** function # Getter function that returns the number value

### `formInterface.string(name, default?)`

Add a string field to the form

**Parameters:**

- `name` (string): The setting name
- `default?` (string): Default value

**Returns:** function # Getter function that returns the string value

### `formInterface.boolean(name)`

Add a boolean field to the form

**Parameters:**

- `name` (string): The setting name

**Returns:** function # Getter function that returns the boolean value

### `formInterface.color(name, default?)`

Add a color field to the form

**Parameters:**

- `name` (string): The setting name
- `default?` (number): Default color value (e.g., colors.white)

**Returns:** function # Getter function that returns the color value

### `formInterface.submit()`

Add submit and cancel buttons, then run the form

**Returns:** boolean # True if submitted, false if cancelled

