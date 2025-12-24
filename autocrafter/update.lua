--- AutoCrafter Update Script
--- Uses the enhanced updater to manage both libraries and project files.
--- Config values are preserved during update.
---
---@version 2.1.0

local VERSION = "2.1.0"
local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"
local UPDATER_URL = BASE_URL .. "/util/updater.lua"

-- Determine if we're running from disk
local isDisk = fs.exists("disk") and fs.isDir("disk")
local diskPrefix = isDisk and "disk/" or ""

-- Auto-detect installation type
local isServer = fs.exists(diskPrefix .. "server.lua") or isDisk
local isCrafter = fs.exists(diskPrefix .. "crafter.lua")

print("================================")
print("  AutoCrafter Updater v" .. VERSION)
print("================================")
print("")

-- Ensure we have the updater library
local updaterPath = diskPrefix .. "lib/updater.lua"
if not fs.exists(updaterPath) and not fs.exists("lib/updater.lua") then
    print("Downloading updater library...")
    local libDir = diskPrefix .. "lib"
    if not fs.exists(libDir) then
        fs.makeDir(libDir)
    end
    shell.run("wget", UPDATER_URL, updaterPath)
end

-- Try to load updater
local ok, updater = pcall(require, "updater")
if not ok then
    -- Try disk path
    ok, updater = pcall(dofile, updaterPath)
end

if not ok or not updater then
    term.setTextColor(colors.red)
    print("ERROR: Could not load updater library")
    term.setTextColor(colors.white)
    return
end

-- Check if updater supports project mode
if not updater.withProject then
    -- Fall back to old update method
    term.setTextColor(colors.yellow)
    print("Updater doesn't support project mode.")
    print("Falling back to legacy update...")
    term.setTextColor(colors.white)
    print("")
    
    local installerPath = "/.autocrafter_update_temp.lua"
    fs.delete(installerPath)
    local installerUrl = BASE_URL .. "/autocrafter/install.lua"
    shell.run("wget", installerUrl, installerPath)
    
    if fs.exists(installerPath) then
        shell.run(installerPath)
        fs.delete(installerPath)
    else
        term.setTextColor(colors.red)
        print("ERROR: Failed to download installer")
        term.setTextColor(colors.white)
    end
    return
end

-- Build file lists based on installation type
local commonFiles = {
    {url = BASE_URL .. "/autocrafter/config.lua", path = "config.lua", name = "config.lua", category = "Config", isConfig = true},
    {url = BASE_URL .. "/autocrafter/update.lua", path = "update.lua", name = "update.lua", category = "Core Files"},
    {url = BASE_URL .. "/autocrafter/startup.lua", path = "startup.lua", name = "startup.lua", category = "Core Files"},
    {url = BASE_URL .. "/autocrafter/lib/comms.lua", path = "lib/comms.lua", name = "comms.lua", category = "Libraries"},
}

local serverFiles = {
    {url = BASE_URL .. "/autocrafter/server.lua", path = "server.lua", name = "server.lua", category = "Server"},
    {url = BASE_URL .. "/autocrafter/lib/recipes.lua", path = "lib/recipes.lua", name = "recipes.lua", category = "Libraries"},
    {url = BASE_URL .. "/autocrafter/lib/inventory.lua", path = "lib/inventory.lua", name = "inventory.lua", category = "Libraries"},
    {url = BASE_URL .. "/autocrafter/lib/crafting.lua", path = "lib/crafting.lua", name = "crafting.lua", category = "Libraries"},
    {url = BASE_URL .. "/autocrafter/lib/ui.lua", path = "lib/ui.lua", name = "ui.lua", category = "Libraries"},
    {url = BASE_URL .. "/autocrafter/lib/menu.lua", path = "lib/menu.lua", name = "menu.lua", category = "Libraries"},
    {url = BASE_URL .. "/autocrafter/managers/queue.lua", path = "managers/queue.lua", name = "queue.lua", category = "Managers"},
    {url = BASE_URL .. "/autocrafter/managers/storage.lua", path = "managers/storage.lua", name = "storage.lua", category = "Managers"},
    {url = BASE_URL .. "/autocrafter/managers/crafter.lua", path = "managers/crafter.lua", name = "crafter.lua", category = "Managers"},
    {url = BASE_URL .. "/autocrafter/managers/monitor.lua", path = "managers/monitor.lua", name = "monitor.lua", category = "Managers"},
    {url = BASE_URL .. "/autocrafter/managers/export.lua", path = "managers/export.lua", name = "export.lua", category = "Managers"},
    {url = BASE_URL .. "/autocrafter/managers/furnace.lua", path = "managers/furnace.lua", name = "furnace.lua", category = "Managers"},
    {url = BASE_URL .. "/autocrafter/managers/worker.lua", path = "managers/worker.lua", name = "worker.lua", category = "Managers"},
    {url = BASE_URL .. "/autocrafter/config/settings.lua", path = "config/settings.lua", name = "settings.lua", category = "Config"},
    {url = BASE_URL .. "/autocrafter/config/targets.lua", path = "config/targets.lua", name = "targets.lua", category = "Config"},
    {url = BASE_URL .. "/autocrafter/config/exports.lua", path = "config/exports.lua", name = "exports.lua", category = "Config"},
    {url = BASE_URL .. "/autocrafter/config/recipes.lua", path = "config/recipes.lua", name = "recipes.lua", category = "Config"},
    {url = BASE_URL .. "/autocrafter/config/recipeprefs.lua", path = "config/recipeprefs.lua", name = "recipeprefs.lua", category = "Config"},
    {url = BASE_URL .. "/autocrafter/config/furnaces.lua", path = "config/furnaces.lua", name = "furnaces.lua", category = "Config"},
    {url = BASE_URL .. "/autocrafter/config/workers.lua", path = "config/workers.lua", name = "workers.lua", category = "Config"},
}

local crafterFiles = {
    {url = BASE_URL .. "/autocrafter/crafter.lua", path = "crafter.lua", name = "crafter.lua", category = "Crafter"},
    {url = BASE_URL .. "/autocrafter/worker.lua", path = "worker.lua", name = "worker.lua", category = "Crafter"},
}

-- Collect files based on installation type
local projectFiles = {}
for _, f in ipairs(commonFiles) do
    table.insert(projectFiles, f)
end

if isDisk then
    -- Disk install: include everything
    for _, f in ipairs(serverFiles) do
        table.insert(projectFiles, f)
    end
    for _, f in ipairs(crafterFiles) do
        table.insert(projectFiles, f)
    end
    print("Disk installation detected - all components")
elseif isServer then
    for _, f in ipairs(serverFiles) do
        table.insert(projectFiles, f)
    end
    print("Server installation detected")
elseif isCrafter then
    for _, f in ipairs(crafterFiles) do
        table.insert(projectFiles, f)
    end
    print("Crafter installation detected")
else
    -- Fresh install or unknown - include common only
    print("Unknown installation type - core files only")
end

print("")

-- Define library requirements based on installation type
local requiredLibs, optionalLibs
if isServer or isDisk then
    requiredLibs = {"s", "tables", "log", "persist"}
    optionalLibs = {"formui", "cmd", "pager", "updater"}
else
    requiredLibs = {"s", "tables", "log", "persist"}
    optionalLibs = {"updater"}
end

-- Run the updater with project mode
local result = updater.withProject("AutoCrafter")
    :withDiskPrefix(diskPrefix)
    :withRequiredLibs(requiredLibs)
    :withOptionalLibs(optionalLibs)
    :withFiles(projectFiles)
    :run()

if result then
    print("")
    term.setTextColor(colors.lightBlue)
    if isDisk then
        print("To start: disk/server or disk/crafter")
    elseif isServer then
        print("To start the server: server")
    else
        print("To start the crafter: crafter")
    end
    term.setTextColor(colors.white)
end
