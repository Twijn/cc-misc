--- Netherite Miner Installation Script
--- Uses the cc-misc installer to download required libraries, then downloads the miner program.
---
---@usage
---wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/netherite/install.lua
---

local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"
local INSTALLER_URL = BASE_URL .. "/util/installer.lua"

print("================================")
print("  Netherite Miner Installer")
print("================================")
print("")

-- Step 1: Download and run the library installer with pre-selected libraries
print("Installing required libraries...")
print("")

-- Download installer temporarily
local installerPath = "/.netherite_installer_temp.lua"
fs.delete(installerPath)
shell.run("wget", INSTALLER_URL, installerPath)

if not fs.exists(installerPath) then
    term.setTextColor(colors.red)
    print("ERROR: Failed to download library installer")
    term.setTextColor(colors.white)
    return
end

-- Run installer with pre-selected libraries (attach, log, persist)
shell.run(installerPath, "attach", "log", "persist")

-- Clean up installer
fs.delete(installerPath)

-- Step 2: Download the miner program
print("")
print("Downloading netherite miner...")

local minerUrl = BASE_URL .. "/netherite/miner.lua"
fs.delete("miner.lua")
local success = shell.run("wget", minerUrl, "miner.lua")

if not success or not fs.exists("miner.lua") then
    term.setTextColor(colors.red)
    print("ERROR: Failed to download miner.lua")
    term.setTextColor(colors.white)
    return
end

term.setTextColor(colors.green)
print("Miner downloaded successfully!")
term.setTextColor(colors.white)

print("")

-- Offer to set as startup
print("Would you like to run the miner on startup? (y/n)")
local input = read()
if input:lower() == "y" or input:lower() == "yes" then
    fs.delete("startup.lua")
    local startup = fs.open("startup.lua", "w")
    startup.write('shell.run("miner")')
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
print("To start mining, run: miner")
print("")
term.setTextColor(colors.yellow)
print("Requirements:")
term.setTextColor(colors.white)
print("  - Plethora scanner module")
print("  - Diamond/netherite pickaxe")
print("  - Ender storage")
print("  - Fuel (coal, charcoal, etc.)")
print("")
term.setTextColor(colors.lightBlue)
print("Place the turtle at Y=15 in the Nether")
print("for optimal ancient debris spawning.")
term.setTextColor(colors.white)
