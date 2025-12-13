--- SignShop Update Script
--- Updates SignShop components and libraries from GitHub.
---
--- This script downloads the latest versions of all SignShop files and libraries.
---
---@usage
---update            -- Update all components
---update libs       -- Update only libraries
---update signshop   -- Update only SignShop files
---

local VERSION = "1.0.1"
local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"

local args = {...}
local mode = args[1] or "all"

-- Adjust package path for disk-based installations
if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

-- Try to use the updater library for libs
local updater = nil
pcall(function()
    updater = require("lib.updater")
end)

local diskPrefix = fs.exists("disk") and "disk/" or ""

local function downloadFile(url, path)
    fs.delete(path)
    local success = shell.run("wget", url, path)
    return success and fs.exists(path)
end

local function updateLibraries()
    print("Updating libraries...")
    print("")
    
    if updater then
        -- Use the updater library for smart updates
        local updated = updater.updateAll()
        print("")
        print(string.format("Updated %d library(ies)", updated))
    else
        -- Fallback to manual library download
        local libs = {"s", "tables", "log", "persist", "formui", "shopk", "updater", "cmd"}
        local libDir = diskPrefix .. "lib"
        local successCount = 0
        
        for _, lib in ipairs(libs) do
            local url = BASE_URL .. "/util/" .. lib .. ".lua"
            local path = libDir .. "/" .. lib .. ".lua"
            if downloadFile(url, path) then
                successCount = successCount + 1
                term.setTextColor(colors.green)
                print("  + " .. lib)
            else
                term.setTextColor(colors.red)
                print("  ! " .. lib)
            end
            term.setTextColor(colors.white)
        end
        
        print("")
        print(string.format("Updated %d/%d libraries", successCount, #libs))
    end
end

local function updateSignShop()
    print("Updating SignShop components...")
    print("")
    
    local files = {
        -- Core files
        {url = BASE_URL .. "/signshop/aisle.lua", path = diskPrefix .. "aisle.lua"},
        {url = BASE_URL .. "/signshop/config.lua", path = diskPrefix .. "config.lua"},
        {url = BASE_URL .. "/signshop/server.lua", path = diskPrefix .. "server.lua"},
        {url = BASE_URL .. "/signshop/startup.lua", path = diskPrefix .. "startup.lua"},
        {url = BASE_URL .. "/signshop/update.lua", path = diskPrefix .. "update.lua"},
        -- SignShop lib files
        {url = BASE_URL .. "/signshop/lib/errors.lua", path = diskPrefix .. "lib/errors.lua"},
        -- Manager files
        {url = BASE_URL .. "/signshop/managers/aisle.lua", path = diskPrefix .. "managers/aisle.lua"},
        {url = BASE_URL .. "/signshop/managers/history.lua", path = diskPrefix .. "managers/history.lua"},
        {url = BASE_URL .. "/signshop/managers/inventory.lua", path = diskPrefix .. "managers/inventory.lua"},
        {url = BASE_URL .. "/signshop/managers/monitor.lua", path = diskPrefix .. "managers/monitor.lua"},
        {url = BASE_URL .. "/signshop/managers/product.lua", path = diskPrefix .. "managers/product.lua"},
        {url = BASE_URL .. "/signshop/managers/purchase.lua", path = diskPrefix .. "managers/purchase.lua"},
        {url = BASE_URL .. "/signshop/managers/sales.lua", path = diskPrefix .. "managers/sales.lua"},
        {url = BASE_URL .. "/signshop/managers/shopsync.lua", path = diskPrefix .. "managers/shopsync.lua"},
        {url = BASE_URL .. "/signshop/managers/sign.lua", path = diskPrefix .. "managers/sign.lua"},
    }
    
    local successCount = 0
    for _, file in ipairs(files) do
        if downloadFile(file.url, file.path) then
            successCount = successCount + 1
            term.setTextColor(colors.green)
            print("  + " .. fs.getName(file.path))
        else
            term.setTextColor(colors.red)
            print("  ! " .. fs.getName(file.path))
        end
        term.setTextColor(colors.white)
    end
    
    print("")
    print(string.format("Updated %d/%d files", successCount, #files))
end

print("================================")
print("  SignShop Updater v" .. VERSION)
print("================================")
print("")

if mode == "all" then
    updateLibraries()
    print("")
    updateSignShop()
elseif mode == "libs" or mode == "libraries" then
    updateLibraries()
elseif mode == "signshop" or mode == "shop" then
    updateSignShop()
else
    print("Unknown mode: " .. mode)
    print("")
    print("Usage:")
    print("  update            - Update all")
    print("  update libs       - Update libraries only")
    print("  update signshop   - Update SignShop only")
    return
end

print("")
print("================================")
print("  Update Complete!")
print("================================")
print("")
term.setTextColor(colors.yellow)
print("Restart the computer to apply changes.")
term.setTextColor(colors.white)
