--- SignShop Startup Script
--- Automatically starts the appropriate SignShop component based on computer type.
---
--- For disk-based installations, this script runs from the disk drive and
--- automatically starts either the aisle (turtle) or server (computer) component.
---
---@version 1.4.0

print("SignShop - Starting from disk...")

-- Adjust package path for disk-based installations
if not package.path:find("disk") then
    package.path = package.path .. ";disk/?.lua;disk/lib/?.lua"
end

local start = shell.openTab or shell.run

sleep(1)

-- Turn on any connected computers/turtles
for _, name in pairs(peripheral.getNames()) do
    if peripheral.hasType(name, "turtle") or peripheral.hasType(name, "computer") then
        local comp = peripheral.wrap(name)
        if not comp.isOn() then
            print(string.format("Turning %s %d on!", peripheral.getType(comp), comp.getID()))
            comp.turnOn()
        end
    end
end

-- Check for restock controller
if fs.exists("restock-controller.lua") then
    start("restock-controller.lua")
end

-- Check for local startup override
if fs.exists("startup.lua") then
    print("Local startup.lua exists, overriding signshop startup!")
    shell.run("startup.lua")
    return
end

-- Determine what to run based on computer type
if turtle then
    print("Starting SignShop Aisle...")
    start("disk/aisle")
else
    -- Check if server has been configured previously
    if not fs.exists("data/products.json") then
        print("This computer hasn't had SignShop server run on it previously.")
        print("Run SignShop server now? y/(n)")
        local response = read():lower()
        if response ~= "y" and response ~= "yes" then
            return
        end
    end
    
    print("Starting SignShop Server...")
    start("disk/server")
    
    -- Clear screen and start configuration UI
    sleep(1) -- Give server time to start
    term.clear()
    term.setCursorPos(1, 1)
    
    local config = require("config")
    config.run()
end
