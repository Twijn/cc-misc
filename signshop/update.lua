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

local VERSION = "1.0.2"
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

-- Progress bar utilities
local screenWidth = term.getSize()
local progressBarWidth = math.max(10, screenWidth - 30)

local function drawProgressBar(line, current, total, label, status)
    local _, curY = term.getCursorPos()
    term.setCursorPos(1, line)
    term.clearLine()
    
    local progress = current / total
    local filled = math.floor(progress * progressBarWidth)
    local empty = progressBarWidth - filled
    
    -- Status indicator
    if status == "done" then
        term.setTextColor(colors.green)
        term.write("[+] ")
    elseif status == "fail" then
        term.setTextColor(colors.red)
        term.write("[!] ")
    elseif status == "working" then
        term.setTextColor(colors.yellow)
        term.write("[>] ")
    else
        term.setTextColor(colors.gray)
        term.write("[ ] ")
    end
    
    -- Label (truncate if needed)
    term.setTextColor(colors.white)
    local maxLabelLen = 15
    local displayLabel = #label > maxLabelLen and label:sub(1, maxLabelLen - 2) .. ".." or label
    term.write(string.format("%-" .. maxLabelLen .. "s ", displayLabel))
    
    -- Progress bar
    term.setTextColor(colors.gray)
    term.write("[")
    term.setTextColor(colors.green)
    term.write(string.rep("=", filled))
    term.setTextColor(colors.gray)
    term.write(string.rep("-", empty))
    term.write("]")
    
    -- Percentage
    term.setTextColor(colors.white)
    term.write(string.format(" %3d%%", math.floor(progress * 100)))
    
    term.setCursorPos(1, curY)
end

local function downloadFile(url, path)
    fs.delete(path)
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        local file = fs.open(path, "w")
        if file then
            file.write(content)
            file.close()
            return true
        end
    end
    return false
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
        -- Fallback to manual library download with progress bars
        local libs = {"s", "tables", "log", "persist", "formui", "shopk", "updater", "cmd"}
        local libDir = diskPrefix .. "lib"
        local successCount = 0
        local results = {}
        
        -- Reserve lines for each library
        local _, startY = term.getCursorPos()
        for i, lib in ipairs(libs) do
            print("") -- Reserve a line
            results[i] = {lib = lib, status = "pending", progress = 0}
        end
        
        -- Download each library and update its progress bar
        for i, lib in ipairs(libs) do
            local line = startY + i - 1
            results[i].status = "working"
            drawProgressBar(line, i - 0.5, #libs, lib .. ".lua", "working")
            
            local url = BASE_URL .. "/util/" .. lib .. ".lua"
            local path = libDir .. "/" .. lib .. ".lua"
            
            if downloadFile(url, path) then
                successCount = successCount + 1
                results[i].status = "done"
                drawProgressBar(line, i, #libs, lib .. ".lua", "done")
            else
                results[i].status = "fail"
                drawProgressBar(line, i, #libs, lib .. ".lua", "fail")
            end
        end
        
        -- Move cursor past progress bars
        term.setCursorPos(1, startY + #libs)
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
        {url = BASE_URL .. "/signshop/lib/menu.lua", path = diskPrefix .. "lib/menu.lua"},
        {url = BASE_URL .. "/signshop/lib/ui.lua", path = diskPrefix .. "lib/ui.lua"},
        -- Config module files
        {url = BASE_URL .. "/signshop/config/products.lua", path = diskPrefix .. "config/products.lua"},
        {url = BASE_URL .. "/signshop/config/signs.lua", path = diskPrefix .. "config/signs.lua"},
        {url = BASE_URL .. "/signshop/config/aisles.lua", path = diskPrefix .. "config/aisles.lua"},
        {url = BASE_URL .. "/signshop/config/sales.lua", path = diskPrefix .. "config/sales.lua"},
        {url = BASE_URL .. "/signshop/config/settings.lua", path = diskPrefix .. "config/settings.lua"},
        {url = BASE_URL .. "/signshop/config/history.lua", path = diskPrefix .. "config/history.lua"},
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
    
    -- Ensure directories exist
    fs.makeDir(diskPrefix .. "lib")
    fs.makeDir(diskPrefix .. "config")
    fs.makeDir(diskPrefix .. "managers")
    
    local successCount = 0
    local results = {}
    
    -- Reserve lines for each file
    local _, startY = term.getCursorPos()
    for i, file in ipairs(files) do
        print("") -- Reserve a line
        results[i] = {file = file, status = "pending", progress = 0}
    end
    
    -- Download each file and update its progress bar
    for i, file in ipairs(files) do
        local line = startY + i - 1
        local fileName = fs.getName(file.path)
        results[i].status = "working"
        drawProgressBar(line, i - 0.5, #files, fileName, "working")
        
        if downloadFile(file.url, file.path) then
            successCount = successCount + 1
            results[i].status = "done"
            drawProgressBar(line, i, #files, fileName, "done")
        else
            results[i].status = "fail"
            drawProgressBar(line, i, #files, fileName, "fail")
        end
    end
    
    -- Move cursor past progress bars
    term.setCursorPos(1, startY + #files)
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
