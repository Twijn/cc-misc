# updater

A package updater module for CC-Misc utilities that checks for and installs updates programmatically using the GitHub API. Features: Check for available updates, programmatic package installation and updates, version comparison, dependency resolution, batch update operations, JSON API integration, project file management, interactive UI mode, and detailed logging for debugging.

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
-- Project mode (for application updaters)
updater.withProject("AutoCrafter")
 .withRequiredLibs({"s", "tables", "log"})
 .withOptionalLibs({"formui", "cmd"})
 .withFiles({
   {url = "https://...", path = "server.lua", required = true},
   {url = "https://...", path = "lib/ui.lua", required = true},
 })
 .run()
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

### `module.fetchJSON(url)`

Fetch JSON data from URL (exported version)

**Parameters:**

- `url` (string): URL to fetch

**Returns:** table|nil Parsed JSON data or nil on error

### `module.downloadFile(url, filepath, name)`

Download and install a file (exported version)

**Parameters:**

- `url` (string): The URL to download from
- `filepath` (string): The local file path to save to
- `name` (string?): Optional name for logging

**Returns:** boolean Success

### `ProjectBuilder:withName(name)`

Set the project name

**Parameters:**

- `name` (string): Project name (displayed in header)

**Returns:** table Builder object for chaining

### `ProjectBuilder:withDiskPrefix(prefix)`

Set the disk prefix for file paths

**Parameters:**

- `prefix` (string): Disk prefix (e.g., "disk/")

**Returns:** table Builder object for chaining

### `ProjectBuilder:withRequiredLibs(libs)`

Add required libraries (must be installed)

**Parameters:**

- `libs` (table): Array of library names

**Returns:** table Builder object for chaining

### `ProjectBuilder:withOptionalLibs(libs)`

Add optional libraries (can be toggled)

**Parameters:**

- `libs` (table): Array of library names

**Returns:** table Builder object for chaining

### `ProjectBuilder:withFiles(files)`

Add project files to manage

**Parameters:**

- `files` (table): Array of {url, path, required?, name?, category?}

**Returns:** table Builder object for chaining

### `ProjectBuilder:run()`

Interactive UI for project updater

**Returns:** boolean Success

### `module.withProject(name)`

Start project mode with optional name

**Parameters:**

- `name` (string?): Project name

**Returns:** table Builder object for chaining

