--- Hierarchical Router Installation Script
--- Uses the cc-misc installer to download required libraries, then downloads router components.
---
---@usage
---wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/router/install.lua
---

local VERSION = "1.0.0"
local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"
local INSTALLER_URL = BASE_URL .. "/util/installer.lua"

print("================================")
print("  Router Installer v" .. VERSION)
print("================================")
print("")

-- Step 1: Download and run the library installer with pre-selected libraries
print("Installing required libraries...")
print("")

-- Download installer temporarily
local installerPath = "/.router_installer_temp.lua"
fs.delete(installerPath)
shell.run("wget", INSTALLER_URL, installerPath)

if not fs.exists(installerPath) then
    term.setTextColor(colors.red)
    print("ERROR: Failed to download library installer")
    term.setTextColor(colors.white)
    return
end

-- Run installer with pre-selected libraries
shell.run(installerPath, "s", "tables", "log", "persist", "updater")

-- Clean up installer
fs.delete(installerPath)

-- Step 2: Download Router components
print("")
print("Downloading Router components...")

local files = {
    {src = "router/router.lua", dest = "router.lua"},
    {src = "router/config.lua", dest = "config.lua"},
    {src = "router/lib/router.lua", dest = "lib/router.lua"},
    {src = "router/tools/ping.lua", dest = "tools/ping.lua"},
    {src = "router/tools/discover.lua", dest = "tools/discover.lua"},
    {src = "router/tools/send.lua", dest = "tools/send.lua"},
}

-- Create directories
fs.makeDir("lib")
fs.makeDir("tools")

-- Download each file
local success = true
for _, file in ipairs(files) do
    local url = BASE_URL .. "/" .. file.src
    local dest = file.dest
    
    print("  Downloading " .. file.dest .. "...")
    
    fs.delete(dest)
    local result = shell.run("wget", url, dest)
    
    if not fs.exists(dest) then
        term.setTextColor(colors.yellow)
        print("    Warning: Failed to download " .. file.dest)
        term.setTextColor(colors.white)
    end
end

-- Step 3: Create startup file
print("")
print("Creating startup file...")

local startupContent = [[
-- Router Startup Script
-- Automatically starts the router on boot

shell.run("router")
]]

local f = fs.open("startup.lua", "w")
f.write(startupContent)
f.close()

print("")
print("================================")
term.setTextColor(colors.lime)
print("  Installation Complete!")
term.setTextColor(colors.white)
print("================================")
print("")
print("To configure and run the router:")
print("  1. Run 'router' to start")
print("  2. Enter your router ID (e.g., 101, 201, 301)")
print("  3. Select if this is a final router")
print("  4. Configure routes to other routers")
print("")
print("Utility tools:")
print("  tools/ping <router_id>   - Ping a router")
print("  tools/discover           - Discover nearby routers")
print("  tools/send <id> <msg>    - Send a message")
print("")
print("Router will auto-start on reboot.")
print("")
