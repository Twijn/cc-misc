--- AutoCrafter Installation Script
--- Uses the cc-misc installer to download required libraries, then downloads AutoCrafter components.
---
---@usage
---wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/autocrafter/install.lua
---

local VERSION = "1.2.0"
local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"
local INSTALLER_URL = BASE_URL .. "/util/installer.lua"

--- Deep merge tables, preserving user values from old config
--- @param defaults table The new default config
--- @param userConfig table The user's existing config
--- @return table The merged config
local function mergeConfigs(defaults, userConfig)
    local result = {}
    for k, v in pairs(defaults) do
        if type(v) == "table" and type(userConfig[k]) == "table" then
            result[k] = mergeConfigs(v, userConfig[k])
        elseif userConfig[k] ~= nil then
            result[k] = userConfig[k]
        else
            result[k] = v
        end
    end
    return result
end

--- Serialize a table to a Lua string
local function serializeConfig(tbl, indent)
    indent = indent or 0
    local pad = string.rep("    ", indent)
    local lines = {}
    
    for k, v in pairs(tbl) do
        local key = type(k) == "string" and k or "[" .. tostring(k) .. "]"
        if type(v) == "table" then
            table.insert(lines, pad .. key .. " = {")
            table.insert(lines, serializeConfig(v, indent + 1))
            table.insert(lines, pad .. "},")
        elseif type(v) == "string" then
            table.insert(lines, pad .. key .. " = \"" .. v .. "\",")
        elseif type(v) == "nil" then
            table.insert(lines, pad .. key .. " = nil,")
        else
            table.insert(lines, pad .. key .. " = " .. tostring(v) .. ",")
        end
    end
    return table.concat(lines, "\n")
end

print("================================")
print("  AutoCrafter Installer v" .. VERSION)
print("================================")
print("")

-- Check for command-line arguments (used by updater)
local args = {...}
local choice = args[1]
local isServer
local isDisk = fs.exists("disk")
local diskPrefix = isDisk and "disk/" or ""

-- If on disk, we download everything (shared between all machines)
if isDisk then
    isServer = true  -- Download all files including server files
    print("Disk drive detected - installing all components")
    print("")
else
    -- Auto-detect installation type if running as update
    local canAutoDetect = fs.exists("server.lua") or fs.exists("crafter.lua")
    
    if choice == "1" then
        isServer = true
    elseif choice == "2" then
        isServer = false
    elseif canAutoDetect then
        -- Auto-detect based on existing files
        isServer = fs.exists("server.lua")
        print("Auto-detected: " .. (isServer and "Server" or "Crafter"))
        print("")
    else
        -- Fresh install - ask user
        print("Select installation type:")
        print("  1. Server (main computer)")
        print("  2. Crafter (turtle with crafting table)")
        print("")
        term.setTextColor(colors.yellow)
        write("Choice (1/2): ")
        term.setTextColor(colors.white)
        choice = read()
        isServer = choice ~= "2"
    end
end

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
-- Always install all libraries when on disk (shared between machines)
if isServer or isDisk then
    shell.run(installerPath, "s", "tables", "log", "persist", "formui", "cmd", "pager", "updater")
else
    shell.run(installerPath, "s", "tables", "log", "persist", "updater")
end

-- Clean up installer
fs.delete(installerPath)

-- Step 2: Download AutoCrafter components
print("")
print("Downloading AutoCrafter components...")

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
    {url = BASE_URL .. "/autocrafter/lib/menu.lua", path = diskPrefix .. "lib/menu.lua"},
    {url = BASE_URL .. "/autocrafter/managers/queue.lua", path = diskPrefix .. "managers/queue.lua"},
    {url = BASE_URL .. "/autocrafter/managers/storage.lua", path = diskPrefix .. "managers/storage.lua"},
    {url = BASE_URL .. "/autocrafter/managers/crafter.lua", path = diskPrefix .. "managers/crafter.lua"},
    {url = BASE_URL .. "/autocrafter/managers/monitor.lua", path = diskPrefix .. "managers/monitor.lua"},
    {url = BASE_URL .. "/autocrafter/managers/export.lua", path = diskPrefix .. "managers/export.lua"},
    {url = BASE_URL .. "/autocrafter/managers/furnace.lua", path = diskPrefix .. "managers/furnace.lua"},
    {url = BASE_URL .. "/autocrafter/managers/worker.lua", path = diskPrefix .. "managers/worker.lua"},
    {url = BASE_URL .. "/autocrafter/managers/request.lua", path = diskPrefix .. "managers/request.lua"},
    {url = BASE_URL .. "/autocrafter/config/settings.lua", path = diskPrefix .. "config/settings.lua"},
    {url = BASE_URL .. "/autocrafter/config/targets.lua", path = diskPrefix .. "config/targets.lua"},
    {url = BASE_URL .. "/autocrafter/config/exports.lua", path = diskPrefix .. "config/exports.lua"},
    {url = BASE_URL .. "/autocrafter/config/recipes.lua", path = diskPrefix .. "config/recipes.lua"},
    {url = BASE_URL .. "/autocrafter/config/recipeprefs.lua", path = diskPrefix .. "config/recipeprefs.lua"},
    {url = BASE_URL .. "/autocrafter/config/recipeoverrides.lua", path = diskPrefix .. "config/recipeoverrides.lua"},
    {url = BASE_URL .. "/autocrafter/config/recipeoverrides-ui.lua", path = diskPrefix .. "config/recipeoverrides-ui.lua"},
    {url = BASE_URL .. "/autocrafter/config/furnaces.lua", path = diskPrefix .. "config/furnaces.lua"},
    {url = BASE_URL .. "/autocrafter/config/workers.lua", path = diskPrefix .. "config/workers.lua"},
    {url = BASE_URL .. "/autocrafter/config/tags.lua", path = diskPrefix .. "config/tags.lua"},
}

local crafterFiles = {
    {url = BASE_URL .. "/autocrafter/crafter.lua", path = diskPrefix .. "crafter.lua"},
    {url = BASE_URL .. "/autocrafter/worker.lua", path = diskPrefix .. "worker.lua"},
}

-- Collect files to download
local files = {}
for _, f in ipairs(commonFiles) do table.insert(files, f) end
if isDisk then
    -- On disk: download everything (shared between all machines)
    for _, f in ipairs(serverFiles) do table.insert(files, f) end
    for _, f in ipairs(crafterFiles) do table.insert(files, f) end
elseif isServer then
    for _, f in ipairs(serverFiles) do table.insert(files, f) end
else
    for _, f in ipairs(crafterFiles) do table.insert(files, f) end
end

-- Create directories
fs.makeDir(diskPrefix .. "lib")
if isServer or isDisk then
    fs.makeDir(diskPrefix .. "managers")
    fs.makeDir(diskPrefix .. "config")
end

-- Backup existing config if present
local configPath = diskPrefix .. "config.lua"
local oldConfig = nil
if fs.exists(configPath) then
    local ok, cfg = pcall(dofile, configPath)
    if ok and type(cfg) == "table" then
        oldConfig = cfg
    end
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

-- Merge old config with new defaults
if oldConfig and fs.exists(configPath) then
    local ok, newConfig = pcall(dofile, configPath)
    if ok and type(newConfig) == "table" then
        local mergedConfig = mergeConfigs(newConfig, oldConfig)
        local configContent = "--- AutoCrafter Configuration\n--- User values preserved during update\n\nreturn {\n" .. serializeConfig(mergedConfig, 1) .. "\n}\n"
        local f = fs.open(configPath, "w")
        if f then
            f.write(configContent)
            f.close()
            term.setTextColor(colors.cyan)
            print("  * Config merged (user values preserved)")
            term.setTextColor(colors.white)
        end
    end
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

if isDisk then
    print("AutoCrafter components installed to disk.")
    print("")
    term.setTextColor(colors.lightBlue)
    print("Server:") 
    term.setTextColor(colors.white)
    print("  disk/server")
    term.setTextColor(colors.lightBlue)
    print("Crafter:")
    term.setTextColor(colors.white)
    print("  disk/crafter")
    print("")
    
    -- Offer to reboot connected computers
    term.setTextColor(colors.yellow)
    write("Reboot all connected computers? (y/N): ")
    term.setTextColor(colors.white)
    local rebootChoice = read()
    if rebootChoice:lower() == "y" then
        print("")
        print("Rebooting connected computers...")
        local rebooted = 0
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "computer" then
                local comp = peripheral.wrap(name)
                if comp and comp.reboot then
                    pcall(function() comp.reboot() end)
                    rebooted = rebooted + 1
                    term.setTextColor(colors.green)
                    print("  + Rebooted: " .. name)
                    term.setTextColor(colors.white)
                end
            end
        end
        if rebooted == 0 then
            term.setTextColor(colors.gray)
            print("  No connected computers found.")
            term.setTextColor(colors.white)
        else
            print(string.format("Rebooted %d computer(s).", rebooted))
        end
    end
elseif isServer then
    print("AutoCrafter Server is now installed.")
    print("")
    term.setTextColor(colors.lightBlue)
    print("To start the server:")
    term.setTextColor(colors.white)
    print("  server")
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
    print("  crafter")
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
