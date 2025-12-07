# updater

A package updater module for CC-Misc utilities that checks for and installs updates programmatically using the GitHub API. Features: Check for available updates, programmatic package installation and updates, version comparison, dependency resolution, batch update operations, JSON API integration, and detailed logging for debugging.

## Examples

```lua
local updater = require("updater")
-- Check for updates
local updates = updater.checkUpdates()
for _, update in ipairs(updates) do
 print(update.name .. ": " .. update.current .. " -> " .. update.latest)
end
-- Update a specific package
updater.update("s")
-- Update all packages
updater.updateAll()
-- Enable verbose mode for debugging
updater.setVerbose(true)
```

## Functions

### `module.setVerbose(enabled)`

Enable or disable verbose output

**Parameters:**

- `enabled` (boolean): Whether to enable verbose output

### `module.getLog()`

Get the current log entries

**Returns:** table Array of log entries

### `module.clearLog()`

Clear the log

### `module.getLibraries()`

Get information about all available libraries

**Returns:** table|nil List of library info or nil on error

### `module.getLibraryInfo(name)`

Get information about a specific library

**Parameters:**

- `name` (string): Library name

**Returns:** table|nil Library info or nil on error

### `module.checkUpdates()`

Check for updates to installed libraries

**Returns:** table List of libraries with available updates

### `module.hasUpdate(name)`

Check if a specific library has an update available

**Parameters:**

- `name` (string): Library name

**Returns:** boolean, string|nil, string|nil Has update, current version, latest version

### `module.update(name, silent?)`

Install or update a library

**Parameters:**

- `name` (string): Library name
- `silent?` (boolean): Suppress output messages

**Returns:** boolean Success

### `module.updateAll(silent?)`

Update all installed libraries that have updates available

**Parameters:**

- `silent?` (boolean): Suppress output messages

**Returns:** number Number of successful updates

### `module.listInstalled()`

List all installed libraries with their versions

**Returns:** table List of {name, version, path} for installed libraries

### `module.install(name, silent?)`

Install a new library with its dependencies

**Parameters:**

- `name` (string): Library name
- `silent?` (boolean): Suppress output messages

**Returns:** boolean Success

### `module.showLog()`

Show the update log in a scrollable view (interactive)

### `module.getLogFile()`

Get the log file path for the current day

**Returns:** string Log file path

