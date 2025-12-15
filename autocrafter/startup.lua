--- AutoCrafter Server Startup Script
--- Automatically starts the server on boot.
---
---@version 1.0.0

-- Add lib to package path
local diskPrefix = fs.exists("disk/server.lua") and "disk/" or ""
package.path = package.path .. ";" .. diskPrefix .. "?.lua;" .. diskPrefix .. "lib/?.lua"

shell.run(diskPrefix .. "server")
