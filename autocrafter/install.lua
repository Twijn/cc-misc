--- AutoCrafter Installation Script
--- Uses the cc-misc installer to download required libraries, then downloads AutoCrafter components.
---
---@usage
---wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/autocrafter/install.lua
---

local VERSION = "1.0.0"
local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"
local INSTALLER_URL = BASE_URL .. "/util/installer.lua"

print("================================")
print("  AutoCrafter Installer v" .. VERSION)
print("================================")
print("")

-- Determine install type
print("Select installation type:")
print("  1. Server (main computer)")
print("  2. Crafter (turtle with crafting table)")
print("")
term.setTextColor(colors.yellow)
write("Choice (1/2): ")
term.setTextColor(colors.white)

local choice = read()
local isServer = choice ~= "2"

-- Step 1: Download and run the library installer with pre-selected libraries
print("")
print("Installing required libraries...")
print("")

-- Ensure lib directory exists
local libDir = fs.exists("disk") and "disk/lib" or "lib"
fs.makeDir(libDir)

-- Download installer temporarily
local installerPath = "/.autocrafter_installer_temp.lua"
fs.delete(installerPath)
shell.run("wget", INSTALLER_URL, installerPath)

if not fs.exists(installerPath) then
    term.setTextColor(colors.red)
    print("ERROR: Failed to download library installer")
    term.setTextColor(colors.white)
    return
end

-- Run installer with pre-selected libraries
if isServer then
    shell.run(installerPath, "s", "tables", "log", "persist", "formui", "cmd", "updater")
else
    shell.run(installerPath, "s", "tables", "log", "persist", "updater")
end

-- Clean up installer
fs.delete(installerPath)

-- Step 2: Download AutoCrafter components
print("")
print("Downloading AutoCrafter components...")

local diskPrefix = fs.exists("disk") and "disk/" or ""

local commonFiles = {
    {url = BASE_URL .. "/autocrafter/config.lua", path = diskPrefix .. "config.lua"},
    {url = BASE_URL .. "/autocrafter/update.lua", path = diskPrefix .. "update.lua"},
    {url = BASE_URL .. "/autocrafter/startup.lua", path = diskPrefix .. "startup.lua"},
    {url = BASE_URL .. "/autocrafter/lib/comms.lua", path = diskPrefix .. "lib/comms.lua"},
}

local serverFiles = {
    {url = BASE_URL .. "/autocrafter/server.lua", path = diskPrefix .. "server.lua"},
    {url = BASE_URL .. "/autocrafter/lib/recipes.lua", path = diskPrefix .. "lib/recipes.lua"},
    {url = BASE_URL .. "/autocrafter/lib/inventory.lua", path = diskPrefix .. "lib/inventory.lua"},
    {url = BASE_URL .. "/autocrafter/lib/crafting.lua", path = diskPrefix .. "lib/crafting.lua"},
    {url = BASE_URL .. "/autocrafter/lib/ui.lua", path = diskPrefix .. "lib/ui.lua"},
    {url = BASE_URL .. "/autocrafter/managers/queue.lua", path = diskPrefix .. "managers/queue.lua"},
    {url = BASE_URL .. "/autocrafter/managers/storage.lua", path = diskPrefix .. "managers/storage.lua"},
    {url = BASE_URL .. "/autocrafter/managers/crafter.lua", path = diskPrefix .. "managers/crafter.lua"},
    {url = BASE_URL .. "/autocrafter/managers/monitor.lua", path = diskPrefix .. "managers/monitor.lua"},
    {url = BASE_URL .. "/autocrafter/config/settings.lua", path = diskPrefix .. "config/settings.lua"},
    {url = BASE_URL .. "/autocrafter/config/targets.lua", path = diskPrefix .. "config/targets.lua"},
}

local crafterFiles = {
    {url = BASE_URL .. "/autocrafter/crafter.lua", path = diskPrefix .. "crafter.lua"},
}

-- Collect files to download
local files = {}
for _, f in ipairs(commonFiles) do table.insert(files, f) end
if isServer then
    for _, f in ipairs(serverFiles) do table.insert(files, f) end
else
    for _, f in ipairs(crafterFiles) do table.insert(files, f) end
end

-- Create directories
fs.makeDir(diskPrefix .. "lib")
if isServer then
    fs.makeDir(diskPrefix .. "managers")
    fs.makeDir(diskPrefix .. "config")
end

local successCount = 0
for _, file in ipairs(files) do
    fs.delete(file.path)
    local success = shell.run("wget", file.url, file.path)
    if success and fs.exists(file.path) then
        successCount = successCount + 1
        term.setTextColor(colors.green)
        print("  + " .. file.path)
    else
        term.setTextColor(colors.red)
        print("  ! Failed: " .. file.path)
    end
    term.setTextColor(colors.white)
end

print("")
print(string.format("Downloaded %d/%d files", successCount, #files))

if successCount < #files then
    term.setTextColor(colors.yellow)
    print("Warning: Some files failed to download")
    term.setTextColor(colors.white)
end

print("")
print("================================")
term.setTextColor(colors.lime)
print("  Installation Complete!")
term.setTextColor(colors.white)
print("================================")
print("")

if isServer then
    print("AutoCrafter Server is now installed.")
    print("")
    term.setTextColor(colors.lightBlue)
    print("To start the server:")
    term.setTextColor(colors.white)
    print("  " .. diskPrefix .. "server")
    print("")
    term.setTextColor(colors.yellow)
    print("Requirements:")
    term.setTextColor(colors.white)
    print("  - Wired modems to storage inventories")
    print("  - Wireless modem for crafter communication")
else
    print("AutoCrafter Crafter is now installed.")
    print("")
    term.setTextColor(colors.lightBlue)
    print("To start the crafter:")
    term.setTextColor(colors.white)
    print("  " .. diskPrefix .. "crafter")
    print("")
    term.setTextColor(colors.yellow)
    print("Requirements:")
    term.setTextColor(colors.white)
    print("  - Crafting table equipped (craft turtle)")
    print("  - Wired modem for network connection")
    print("  - Access to storage inventories")
end

print("")
term.setTextColor(colors.lightBlue)
print("To update later, run:")
term.setTextColor(colors.white)
print("  " .. diskPrefix .. "update")
print("")
