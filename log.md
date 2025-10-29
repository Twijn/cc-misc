# log

A logging utility module for ComputerCraft that provides colored console output and automatic file logging with daily log rotation. Features: Color-coded console output (red for errors, yellow for warnings, blue for info), automatic daily log file creation and rotation, persistent log storage in log/ directory, and timestamped log entries.

## Examples

```lua
local log = require("log")
log.info("Server started")
log.warn("High memory usage detected")
log.error("Failed to connect to database")
```

## Functions

### `module.info(msg)`

Log an informational message in blue

**Parameters:**

- `msg` (string): The message to log

### `module.warn(msg)`

Log a warning message in yellow

**Parameters:**

- `msg` (string): The message to log

### `module.error(msg)`

Log an error message in red

**Parameters:**

- `msg` (string): The message to log

