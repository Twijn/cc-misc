--- RBC Update Script
--- Updates all RBC components to the latest version
---
---@usage
---wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/roadbuilder/update.lua
---

local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"

-- Detect device type
local isTurtle = turtle ~= nil
local isPocket = pocket ~= nil

print("================================")
print("  RBC Updater")
print("================================")
print("")

-- Determine library directory
local libDir = fs.exists("disk") and "disk/lib" or "lib"

-- Files to update based on device type
local filesToUpdate = {
    -- Shared libraries
    {url = BASE_URL .. "/roadbuilder/lib/gps.lua", path = libDir .. "/gps.lua"},
    {url = BASE_URL .. "/roadbuilder/lib/comms.lua", path = libDir .. "/comms.lua"},
    {url = BASE_URL .. "/roadbuilder/lib/inventory.lua", path = libDir .. "/inventory.lua"},
    {url = BASE_URL .. "/roadbuilder/config.lua", path = "config.lua", optional = true},
}

-- Add device-specific files
if isTurtle then
    table.insert(filesToUpdate, {url = BASE_URL .. "/roadbuilder/turtle.lua", path = "turtle.lua"})
else
    table.insert(filesToUpdate, {url = BASE_URL .. "/roadbuilder/controller.lua", path = "controller.lua"})
end

-- Also update util libraries if they exist
local utilLibs = {"attach", "log", "persist", "updater", "formui"}
for _, lib in ipairs(utilLibs) do
    local libPath = libDir .. "/" .. lib .. ".lua"
    if fs.exists(libPath) then
        table.insert(filesToUpdate, {
            url = BASE_URL .. "/util/" .. lib .. ".lua",
            path = libPath,
            name = lib,
        })
    end
end

print("Updating files...")
print("")

local updated = 0
local failed = 0
local skipped = 0

for _, file in ipairs(filesToUpdate) do
    local displayName = file.name or file.path
    term.setTextColor(colors.white)
    write("  " .. displayName .. "... ")
    
    -- Skip optional files that don't exist (like config.lua which user may have customized)
    if file.optional and not fs.exists(file.path) then
        term.setTextColor(colors.yellow)
        print("skipped (not found)")
        skipped = skipped + 1
    else
        -- Backup config if it exists
        if file.path == "config.lua" and fs.exists("config.lua") then
            fs.delete("config.lua.bak")
            fs.copy("config.lua", "config.lua.bak")
        end
        
        -- Download new version
        fs.delete(file.path .. ".tmp")
        local success = shell.run("wget", file.url, file.path .. ".tmp")
        
        if success and fs.exists(file.path .. ".tmp") then
            fs.delete(file.path)
            fs.move(file.path .. ".tmp", file.path)
            term.setTextColor(colors.lime)
            print("updated")
            updated = updated + 1
        else
            fs.delete(file.path .. ".tmp")
            term.setTextColor(colors.red)
            print("failed")
            failed = failed + 1
        end
    end
end

print("")
term.setTextColor(colors.white)
print("================================")

if failed == 0 then
    term.setTextColor(colors.lime)
    print("  Update complete!")
else
    term.setTextColor(colors.yellow)
    print("  Update completed with errors")
end

term.setTextColor(colors.white)
print("================================")
print("")
print("  Updated: " .. updated)
print("  Failed:  " .. failed)
print("  Skipped: " .. skipped)
print("")

if fs.exists("config.lua.bak") then
    term.setTextColor(colors.yellow)
    print("Note: Your config.lua was backed up to")
    print("config.lua.bak. Review new config for")
    print("any new options.")
    term.setTextColor(colors.white)
    print("")
end

if isTurtle then
    print("Restart with: turtle")
else
    print("Restart with: controller")
end
