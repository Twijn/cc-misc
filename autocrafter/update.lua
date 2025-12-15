--- AutoCrafter Update Script
--- Updates all AutoCrafter components from the repository.
---
---@version 1.0.0

local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"

print("================================")
print("  AutoCrafter Updater")
print("================================")
print("")

-- Detect installation type
local isServer = fs.exists("server.lua") or fs.exists("disk/server.lua")
local diskPrefix = fs.exists("disk/config.lua") and "disk/" or ""

print("Detected: " .. (isServer and "Server" or "Crafter"))
print("")

-- Run the installer again
local installerPath = "/.autocrafter_update_temp.lua"
fs.delete(installerPath)

local installerUrl = BASE_URL .. "/autocrafter/install.lua"
shell.run("wget", installerUrl, installerPath)

if fs.exists(installerPath) then
    -- Create a file to skip the prompt
    if isServer then
        shell.run(installerPath, "1")
    else
        shell.run(installerPath, "2")
    end
    fs.delete(installerPath)
else
    term.setTextColor(colors.red)
    print("ERROR: Failed to download updater")
    term.setTextColor(colors.white)
end
