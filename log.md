# log

A logging utility module for ComputerCraft that provides colored console output and automatic file logging with daily log rotation. Features: Color-coded console output (red for errors, yellow for warnings, blue for info), automatic daily log file creation and rotation, persistent log storage in log/ directory, and timestamped log entries. @module log

## Functions

### `fileDate()`

Generate a file-safe date string for log filenames

**Returns:** string # Date string in YYYY/MM/DD format

### `displayDate()`

Generate a human-readable timestamp for log entries

**Returns:** string # Timestamp string in YYYY-MM-DD HH:MM:SS format

### `writeLog(level, msg)`

Write a log entry to the daily log file

**Parameters:**

- `level` (string): The log level (info, warn, error)
- `msg` (string): The message to log

### `log(level, msg)`

Internal logging function that handles both console and file output

**Parameters:**

- `level` (string): The log level (info, warn, error)
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

