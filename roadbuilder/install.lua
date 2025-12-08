--- Road Builder Installation Script
--- Uses the cc-misc installer to download required libraries, then downloads the road builder programs.
---
---@usage
---wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/roadbuilder/install.lua
---

local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"
local INSTALLER_URL = BASE_URL .. "/util/installer.lua"

-- Detect device type
local isTurtle = turtle ~= nil
local isPocket = pocket ~= nil
local isComputer = not isTurtle and not isPocket

print("================================")
print("  Road Builder Installer")
print("================================")
print("")

if isTurtle then
    print("Detected: Turtle")
elseif isPocket then
    print("Detected: Pocket Computer")
else
    print("Detected: Computer (Server Mode)")
end
print("")

-- Step 1: Download and run the library installer with pre-selected libraries
print("Installing required libraries...")
print("")

-- Download installer temporarily
local installerPath = "/.roadbuilder_installer_temp.lua"
fs.delete(installerPath)
shell.run("wget", INSTALLER_URL, installerPath)

if not fs.exists(installerPath) then
    term.setTextColor(colors.red)
    print("ERROR: Failed to download library installer")
    term.setTextColor(colors.white)
    return
end

-- Run installer with pre-selected libraries
shell.run(installerPath, "attach", "log", "persist", "updater", "formui")

-- Clean up installer
fs.delete(installerPath)

-- Step 2: Determine which files to download based on device type
print("")
print("Downloading road builder components...")

local libDir = fs.exists("disk") and "disk/lib" or "lib"
fs.makeDir(libDir)

-- Download shared libraries
local sharedLibs = {
    "lib/gps.lua",
    "lib/comms.lua",
    "lib/inventory.lua",
}

for _, lib in ipairs(sharedLibs) do
    local libName = lib:match("lib/(.+)$")
    local libUrl = BASE_URL .. "/roadbuilder/" .. lib
    local libPath = libDir .. "/" .. libName
    print("  Downloading " .. libName .. "...")
    fs.delete(libPath)
    shell.run("wget", libUrl, libPath)
end

-- Step 3: Download the main program based on device type
print("")
local mainProgram = nil
local mainUrl = nil

if isTurtle then
    mainProgram = "turtle.lua"
    mainUrl = BASE_URL .. "/roadbuilder/turtle.lua"
    print("Downloading road builder turtle program...")
elseif isPocket then
    mainProgram = "controller.lua"
    mainUrl = BASE_URL .. "/roadbuilder/controller.lua"
    print("Downloading road builder controller...")
else
    mainProgram = "controller.lua"
    mainUrl = BASE_URL .. "/roadbuilder/controller.lua"
    print("Downloading road builder controller...")
end

fs.delete(mainProgram)
local success = shell.run("wget", mainUrl, mainProgram)

if not success or not fs.exists(mainProgram) then
    term.setTextColor(colors.red)
    print("ERROR: Failed to download " .. mainProgram)
    term.setTextColor(colors.white)
    return
end

-- Also download config
print("Downloading configuration template...")
local configUrl = BASE_URL .. "/roadbuilder/config.lua"
fs.delete("config.lua")
shell.run("wget", configUrl, "config.lua")

term.setTextColor(colors.green)
print("Downloaded successfully!")
term.setTextColor(colors.white)

print("")

-- Offer to set as startup
print("Would you like to run the road builder on startup? (y/n)")
local input = read()
if input:lower() == "y" or input:lower() == "yes" then
    fs.delete("startup.lua")
    local startup = fs.open("startup.lua", "w")
    startup.write('shell.run("' .. mainProgram:gsub(".lua", "") .. '")')
    startup.close()
    term.setTextColor(colors.green)
    print("Startup configured!")
    term.setTextColor(colors.white)
end

print("")
print("================================")
print("  Installation Complete!")
print("================================")
print("")

if isTurtle then
    print("To start building roads, run: turtle")
    print("")
    term.setTextColor(colors.yellow)
    print("Requirements:")
    term.setTextColor(colors.white)
    print("  - Diamond/netherite pickaxe")
    print("  - Wireless modem (for GPS & comms)")
    print("  - Road blocks in inventory")
    print("  - Fuel (coal, charcoal, etc.)")
    print("")
    term.setTextColor(colors.lightBlue)
    print("Optional: Ender storage for refill")
elseif isPocket then
    print("To control turtles, run: controller")
    print("")
    term.setTextColor(colors.yellow)
    print("Requirements:")
    term.setTextColor(colors.white)
    print("  - Wireless modem (ender modem)")
    print("")
    term.setTextColor(colors.lightBlue)
    print("Use the controller to manage all")
    print("road builder turtles on the network.")
else
    print("To control turtles, run: controller")
    print("")
    term.setTextColor(colors.lightBlue)
    print("Connect a monitor for a dashboard view.")
end
term.setTextColor(colors.white)
