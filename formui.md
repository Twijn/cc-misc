# formui

A dynamic form user interface library for ComputerCraft that provides interactive forms with various field types, validation, and peripheral detection. Features: Text and number input fields, select dropdowns and peripheral selection, built-in validation system, labels and buttons, real-time peripheral detection, keyboard navigation with arrow keys, and form submission and cancellation.

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

### `FormUI:addField(field)`

Add a field to the form and return a getter function

**Parameters:**

- `field` (FormField): The field definition to add

**Returns:** fun(): any # Function that returns the field's final value after form submission

### `FormUI:text(label, default?, validator?)`

Add a text input field

**Parameters:**

- `label` (string): The field label
- `default?` (string): Default value
- `validator?` (ValidationFunction): Custom validation function

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

