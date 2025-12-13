--- SignShop Installation Script
--- Uses the cc-misc installer to download required libraries, then downloads SignShop components.
---
--- This installer sets up SignShop on disk drives for aisle turtles and server computers.
---
---@usage
---wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/signshop/install.lua
---

local VERSION = "1.0.0"
local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"
local INSTALLER_URL = BASE_URL .. "/util/installer.lua"

print("================================")
print("  SignShop Installer v" .. VERSION)
print("================================")
print("")

-- Step 1: Download and run the library installer with pre-selected libraries
print("Installing required libraries...")
print("")

-- Ensure lib directory exists
local libDir = fs.exists("disk") and "disk/lib" or "lib"
fs.makeDir(libDir)

-- Download installer temporarily
local installerPath = "/.signshop_installer_temp.lua"
fs.delete(installerPath)
shell.run("wget", INSTALLER_URL, installerPath)

if not fs.exists(installerPath) then
    term.setTextColor(colors.red)
    print("ERROR: Failed to download library installer")
    term.setTextColor(colors.white)
    return
end

-- Run installer with pre-selected libraries
shell.run(installerPath, "s", "tables", "log", "persist", "formui", "shopk", "updater", "cmd")

-- Clean up installer
fs.delete(installerPath)

-- Step 2: Download SignShop components
print("")
print("Downloading SignShop components...")

local diskPrefix = fs.exists("disk") and "disk/" or ""

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
    {url = BASE_URL .. "/signshop/managers/inventory.lua", path = diskPrefix .. "managers/inventory.lua"},
    {url = BASE_URL .. "/signshop/managers/product.lua", path = diskPrefix .. "managers/product.lua"},
    {url = BASE_URL .. "/signshop/managers/purchase.lua", path = diskPrefix .. "managers/purchase.lua"},
    {url = BASE_URL .. "/signshop/managers/sales.lua", path = diskPrefix .. "managers/sales.lua"},
    {url = BASE_URL .. "/signshop/managers/shopsync.lua", path = diskPrefix .. "managers/shopsync.lua"},
    {url = BASE_URL .. "/signshop/managers/sign.lua", path = diskPrefix .. "managers/sign.lua"},
}

-- Create directories
fs.makeDir(diskPrefix .. "lib")
fs.makeDir(diskPrefix .. "managers")

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
print("  Installation Complete!")
print("================================")
print("")
print("SignShop is now installed.")
print("")
term.setTextColor(colors.lightBlue)
print("For disk drives:")
term.setTextColor(colors.white)
print("  Computers will automatically start")
print("  the appropriate component.")
print("")
term.setTextColor(colors.lightBlue)
print("To update SignShop later, run:")
term.setTextColor(colors.white)
print("  " .. diskPrefix .. "update")
print("")
term.setTextColor(colors.yellow)
print("Requirements:")
term.setTextColor(colors.white)
print("  - Wired modems for inventory access")
print("  - Wireless modem for krist/shopsync")
print("  - Signs with product information")
print("")
