# persist

@class PersistModule
A persistence module for ComputerCraft that provides automatic data serialization
and storage to files with support for both Lua serialization and JSON formats.

Features:
Automatic file creation and loading
Deep copy functionality to handle circular references
Support for both Lua serialize and JSON formats
Error handling with fallback mechanisms
Array and object manipulation methods
Automatic saving on data changes

@usage
local persist = require("persist")
local config = persist("config.json", false) -- Use JSON format

config.setDefault("port", 8080)
config.set("name", "MyServer")
print(config.get("port")) -- 8080

local history = persist("history.lua", true) -- Use Lua serialization
history.push("command1")
history.push("command2")

