# formui

@class FormUI
A dynamic form user interface library for ComputerCraft that provides interactive forms
with various field types, validation, and peripheral detection.

Features:
Text and number input fields
Select dropdowns and peripheral selection
Built-in validation system
Labels and buttons
Real-time peripheral detection
Keyboard navigation with arrow keys
Form submission and cancellation

@usage
local FormUI = require("formui")
local form = FormUI.new("Configuration")

local nameField = form:text("Name", "default")
local portField = form:number("Port", 8080)
local modemField = form:peripheral("Modem", "modem")

form:addSubmitCancel()
local result = form:run()
if result then
print("Name:", nameField())
print("Port:", portField())
end

## Functions

### `centerText(y, text, termW)`

Center text horizontally on the terminal at a specific line

**Parameters:**

- `y` (number): The line number to write on
- `text` (string): The text to center
- `termW` (number): The terminal width

### `truncate(text, width)`

Truncate text to fit within a specified width

**Parameters:**

- `text` (string): The text to truncate
- `width` (number): Maximum width

**Returns:** string # Truncated text with "..." if needed

### `findPeripheralsOfType(pType?)`

Find all peripherals of a specific type

**Parameters:**

- `pType?` (string): The peripheral type to filter by (nil for all)

**Returns:** string[] # Array of peripheral names

### `FormUI.new(title?)`

Create a new FormUI instance

**Parameters:**

- `title?` (string): The form title (defaults to "Form")

**Returns:** FormUI # New FormUI instance

