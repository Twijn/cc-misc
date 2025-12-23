# log

A logging utility module for ComputerCraft that provides colored console output and automatic file logging with daily log rotation. Features: Color-coded console output (red for errors, yellow for warnings, blue for info), automatic daily log file creation and rotation, persistent log storage in log/ directory, timestamped log entries, buffered writes for performance, and configurable log levels.

## Examples

```lua
local log = require("log")
log.debug("This is a debug message")
log.info("Server started")
log.warn("High memory usage detected")
log.error("Failed to connect to database")
log.setLevel("debug")  -- Show all messages including debug
log.setLevel("warn")   -- Show only warnings and errors
```

## Functions

### `module.debug(msg)`

Log a debug message in gray (only to file, not console by default)

**Parameters:**

- `msg` (string): The message to log

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

### `module.critical(msg)`

Log a critical/crash message in red This is always logged both to console and file, and immediately flushed

**Parameters:**

- `msg` (string): The message to log

### `module.flush()`

Flush any pending log entries to disk

### `module.setLevel(level)`

Set the current log level Messages with levels more verbose than this will only be written to file, not console

**Parameters:**

- `level` (string|number): The log level: "error", "warn", "info", "debug" (or 1-4)

**Returns:** string? error Error message if failed

### `module.getLevel()`

Get the current log level name

**Returns:** string levelName The current log level name

### `module.getLevels()`

Get all available log levels

**Returns:** table levels Table with level names as keys and numbers as values

### `module.registerCommands(commands)`

Register log level commands with a cmd command table This adds "loglevel" command with aliases "log-level" and "ll"

**Parameters:**

- `commands` (table): The commands table to add the log level command to

**Returns:** table commands The modified commands table (also modifies in place)

