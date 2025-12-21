# pager

Pager utility for ComputerCraft that displays long output with pagination Similar to 'less' or 'more' on Unix systems. Allows scrolling through content that exceeds the terminal height. Features: Page-by-page navigation, line-by-line scrolling, search/skip to end, dynamic terminal size detection, works with both strings and tables of lines.

## Examples

```lua
local pager = require("pager")
-- Display a table of lines
local lines = {"Line 1", "Line 2", ...}
pager.display(lines, "My Title")
-- Use the pager collector to build output
local p = pager.new("Results")
p:print("Some text")
p:write("partial ")
p:print("line")
p:setColor(colors.lime)
p:print("Green text")
p:show()
```

## Functions

### `pager.new(title?)`

Create a new pager collector for building pageable output

**Parameters:**

- `title?` (string): Optional title to show at the top

**Returns:** PagerCollector

### `PagerCollector:setColor(color)`

Set the current text color for subsequent writes

**Parameters:**

- `color` (number): The color constant (e.g., colors.red)

### `PagerCollector:write(text)`

Write text without a newline (can be called multiple times per line)

**Parameters:**

- `text` (string): The text to write

### `PagerCollector:print(text?)`

Print text with a newline (completes the current line)

**Parameters:**

- `text?` (string): Optional text to print before the newline

### `PagerCollector:newline()`

Add a blank line

### `PagerCollector:lineCount()`

Get the number of lines collected

**Returns:** number

### `PagerCollector:needsPaging()`

Check if paging is needed based on terminal height

**Returns:** boolean

### `PagerCollector:show()`

Display the collected content with pagination if needed If content fits on screen, just prints it directly

### `pager.display(lines, title?)`

Display a table of strings or pre-formatted lines with pagination This is a simpler interface for when you just have plain strings

**Parameters:**

- `lines` (string[]): Array of strings to display
- `title?` (string): Optional title

### `pager.create(title?)`

Create a pager that acts like term for easy integration Returns an object with print, write, setTextColor that collects output

**Parameters:**

- `title?` (string): Optional title for the pager

**Returns:** table Pager object with terminal-like interface

