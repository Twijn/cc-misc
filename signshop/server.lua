--- SignShop Server ---
--- Main server component that manages aisles, inventory, products, and purchases.
---
---@version 1.4.0
-- @module signshop-server

local VERSION = "1.3.0"

if not package.path:find("disk") then
    package.path = package.path .. ";disk/?.lua;disk/lib/?.lua"
end

local logger = require("lib.log")

local managers = {}

function _G.ssVersion()
    return VERSION
end

-- Determine if running from disk or local
local managersPath = fs.exists("disk/managers") and "disk/managers" or "managers"

for i, fileName in pairs(fs.list(managersPath)) do
    local name = fileName:gsub(".lua", "")
    managers[name] = require("managers." .. name)
end

local function handleTerminate()
    os.pullEventRaw("terminate")
    for name, manager in pairs(managers) do
        if manager.close then manager.close() end
    end
    logger.error("Terminated")
end

local runFuncs = {handleTerminate}
for name, manager in pairs(managers) do
    if manager.run then table.insert(runFuncs, manager.run) end
end

parallel.waitForAny(table.unpack(runFuncs))
