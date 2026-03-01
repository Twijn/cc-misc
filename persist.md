# persist

A persistence module for ComputerCraft that provides automatic data serialization and storage to files with support for both Lua serialization and JSON formats. Features: Automatic file creation and loading, deep copy functionality to handle circular references, support for both Lua serialize and JSON formats, error handling with fallback mechanisms, array and object manipulation methods, and automatic saving on data changes.

## Examples

```lua
local persist = require("persist")
local config = persist("config.json", false) -- Set to "true" to use textutils.serialize() rather than serializeJSON

config.setDefault("port", 8080)
config.set("name", "MyServer")
print(config.get("port")) -- 8080

```

