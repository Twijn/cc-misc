--- AutoCrafter Crafter Startup Script
--- Automatically starts the crafter turtle on boot.
---
---@version 1.0.0

-- Add lib to package path
local diskPrefix = fs.exists("disk/crafter.lua") and "disk/" or ""
package.path = package.path .. ";" .. diskPrefix .. "?.lua;" .. diskPrefix .. "lib/?.lua"

shell.run(diskPrefix .. "crafter")
