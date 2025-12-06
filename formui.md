# formui

A dynamic form user interface library for ComputerCraft that provides interactive forms with various field types, validation, and peripheral detection. Features: Text and number input fields, select dropdowns and peripheral selection, checkbox/toggle fields, multi-select dropdowns, list fields with item management, built-in validation system, labels and buttons, real-time peripheral detection, keyboard navigation with arrow keys, and form submission and cancellation.

## Examples

```lua
local FormUI = require("formui")
local form = FormUI.new("Configuration")
local nameField = form:text("Name", "default")
local portField = form:number("Port", 8080)
local modemField = form:peripheral("Modem", "modem")
local enabledField = form:checkbox("Enabled", true)
local featuresField = form:multiselect("Features", {"feature1", "feature2", "feature3"})
local itemsField = form:list("Items", {"item1", "item2"}, "string")
form:addSubmitCancel()
local result = form:run()
if result then
 print("Name:", nameField())
 print("Port:", portField())
 print("Enabled:", enabledField())
 print("Features:", table.concat(featuresField(), ", "))
end
```

## Functions

### `FormUI.new(title?)`

Create a new FormUI instance

**Parameters:**

- `title?` (string): The form title (defaults to "Form")

**Returns:** FormUI # New FormUI instance

### `FormUI:addField(field)`

Add a field to the form and return a getter function

**Parameters:**

- `field` (FormField): The field definition to add

**Returns:** fun(): any # Function that returns the field's final value after form submission

### `FormUI:text(label, default?, validator?, allowEmpty?)`

Add a text input field

**Parameters:**

- `label` (string): The field label
- `default?` (string): Default value
- `validator?` (ValidationFunction): Custom validation function
- `allowEmpty?` (boolean): Whether empty values are allowed (default: false)

**Returns:** fun(): string # Function to get the field value after submission

### `FormUI:number(label, default?, validator?)`

Add a number input field

**Parameters:**

- `label` (string): The field label
- `default?` (number): Default value
- `validator?` (ValidationFunction): Custom validation function

**Returns:** fun(): number # Function to get the field value after submission

### `FormUI:select(label, options?, defaultIndex?, validator?)`

Add a select dropdown field

**Parameters:**

- `label` (string): The field label
- `options?` (string[]): Available options
- `defaultIndex?` (number): Index of default selection (1-based)
- `validator?` (ValidationFunction): Custom validation function

**Returns:** fun(): string # Function to get the selected option after submission

### `FormUI:peripheral(label, filterType?, validator?, defaultValue?)`

Add a peripheral selector field that automatically detects peripherals

**Parameters:**

- `label` (string): The field label
- `filterType?` (string): Peripheral type to filter by (e.g., "modem", "monitor")
- `validator?` (ValidationFunction): Custom validation function
- `defaultValue?` (string|number): Default peripheral (name or index)

**Returns:** fun(): string # Function to get the selected peripheral name after submission

### `FormUI:label(text)`

Add a non-interactive label for display purposes

**Parameters:**

- `text` (string): The label text to display

**Returns:** fun(): string # Function to get the label text (always returns the same text)

### `FormUI:button(text, action?)`

Add a button that can trigger actions

**Parameters:**

- `text` (string): The button text
- `action?` (string): Action identifier (defaults to lowercase text)

**Returns:** fun(): string # Function to get the button text

### `FormUI:checkbox(label, default?)`

Add a checkbox/toggle field

**Parameters:**

- `label` (string): The field label
- `default?` (boolean): Default value (true/false)

**Returns:** fun(): boolean # Function to get the field value after submission

### `FormUI:multiselect(label, options, defaultIndices?)`

Add a multi-select dropdown field

**Parameters:**

- `label` (string): The field label
- `options` (string[]): Available options
- `defaultIndices?` (number[]): Indices of default selections (1-based)

**Returns:** fun(): string[] # Function to get selected options after submission

### `FormUI:list(label, default?, itemType?)`

Add a list field (string or number list, with item reordering)

**Parameters:**

- `label` (string): The field label
- `default?` (table): Default list value
- `itemType?` (string): "string" or "number"

**Returns:** fun(): table # Function to get the list after submission

### `FormUI:addSubmitCancel()`

Add standard Submit and Cancel buttons to the form

### `FormUI:validateField(i)`

Validate a specific field by index

**Parameters:**

- `i` (number): The field index to validate

**Returns:** string? error Error message if validation failed

### `FormUI:isValid()`

Validate all fields in the form

**Returns:** boolean # True if all fields are valid

### `FormUI:get(label)`

Get the current value of a field by label

**Parameters:**

- `label` (string): The field label

**Returns:** any # The field's current value, or nil if not found

### `FormUI:setValue(label, value)`

Set the value of a field by label

**Parameters:**

- `label` (string): The field label
- `value` (any): The new value to set

**Returns:** boolean # True if field was found and updated, false otherwise

### `FormUI:draw()`

Draw the form to the terminal

### `FormUI:edit(index)`

Edit a field at the specified index

**Parameters:**

- `index` (number): The field index to edit

**Returns:** string? action Action identifier if a button was pressed

### `FormUI:nextSelectableField(from)`

Find the next selectable field index (skips labels)

**Parameters:**

- `from` (number): Starting field index

**Returns:** number # Next selectable field index (wraps around)

### `FormUI:prevSelectableField(from)`

Find the previous selectable field index (skips labels)

**Parameters:**

- `from` (number): Starting field index

**Returns:** number # Previous selectable field index (wraps around)

### `FormUI:run()`

Run the form's main input loop

**Returns:** FormResult? result Table of field values indexed by label, or nil if cancelled

