--- SignShop Server ---
--- Main server component that manages aisles, inventory, products, and purchases.
--- Includes graceful shutdown handling for proper state persistence.
---
---@version 1.6.0
-- @module signshop-server

local VERSION = "1.6.0"

if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

local logger = require("lib.log")

local managers = {}
local shuttingDown = false

function _G.ssVersion()
    return VERSION
end

--- Check if the server is shutting down
---@return boolean True if shutdown is in progress
function _G.ssIsShuttingDown()
    return shuttingDown
end

-- Determine if running from disk or local
local managersPath = fs.exists("disk/managers") and "disk/managers" or "managers"

for i, fileName in pairs(fs.list(managersPath)) do
    local name = fileName:gsub(".lua", "")
    managers[name] = require("managers." .. name)
end

--- Perform graceful shutdown of all managers
local function performShutdown()
    shuttingDown = true
    logger.info("Initiating graceful shutdown...")
    
    -- Phase 1: Call beforeShutdown for state saving
    for name, manager in pairs(managers) do
        if manager.beforeShutdown then
            local ok, err = pcall(manager.beforeShutdown)
            if ok then
                logger.info(string.format("Manager %s: beforeShutdown completed", name))
            else
                logger.error(string.format("Manager %s: beforeShutdown failed: %s", name, tostring(err)))
            end
        end
    end
    
    -- Phase 2: Call close for cleanup
    for name, manager in pairs(managers) do
        if manager.close then
            local ok, err = pcall(manager.close)
            if ok then
                logger.info(string.format("Manager %s: closed", name))
            else
                logger.error(string.format("Manager %s: close failed: %s", name, tostring(err)))
            end
        end
    end
    
    logger.info("Shutdown complete")
end

local function handleTerminate()
    os.pullEventRaw("terminate")
    performShutdown()
end

local runFuncs = {handleTerminate}
for name, manager in pairs(managers) do
    if manager.run then table.insert(runFuncs, manager.run) end
end

parallel.waitForAny(table.unpack(runFuncs))
