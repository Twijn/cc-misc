--- A package updater module for CC-Misc utilities that checks for and installs updates
--- programmatically using the GitHub API.
---
--- Features: Check for available updates, programmatic package installation and updates,
--- version comparison, dependency resolution, batch update operations, and JSON API integration.
---
---@usage
---local updater = require("updater")
---
----- Check for updates
---local updates = updater.checkUpdates()
---for _, update in ipairs(updates) do
---  print(update.name .. ": " .. update.current .. " -> " .. update.latest)
---end
---
----- Update a specific package
---updater.update("s")
---
----- Update all packages
---updater.updateAll()
---
---@version 1.0.1
-- @module updater

local VERSION = "1.0.1"

local API_BASE = "https://ccmisc.twijn.dev/api/"
local DOWNLOAD_BASE = "https://raw.githubusercontent.com/Twijn/cc-misc/main/util/"

local module = {}

---Find existing library installation
---@param libName string Library name
---@return string|nil Path to existing file or nil
local function findExistingLibrary(libName)
    local searchPaths = {
        "disk/lib/" .. libName .. ".lua",
        "/lib/" .. libName .. ".lua",
        libName .. ".lua",
        "disk/" .. libName .. ".lua"
    }
    
    for _, path in ipairs(searchPaths) do
        if fs.exists(path) then
            return path
        end
    end
    
    return nil
end

---Parse version from a Lua file
---@param filepath string Path to the file
---@return string|nil Version string or nil
local function parseVersion(filepath)
    if not fs.exists(filepath) then
        return nil
    end
    
    local file = fs.open(filepath, "r")
    if not file then
        return nil
    end
    
    local content = file.readAll()
    file.close()
    
    -- Look for VERSION = "x.x.x" pattern
    local version = content:match('VERSION%s*=%s*["\']([^"\']+)["\']')
    if version then
        return version
    end
    
    -- Look for @version tag in comments
    version = content:match('%-%-%-@version%s+([%d%.]+)')
    return version
end

---Compare two version strings
---@param v1 string First version
---@param v2 string Second version
---@return number -1 if v1 < v2, 0 if equal, 1 if v1 > v2
local function compareVersions(v1, v2)
    if not v1 then return -1 end
    if not v2 then return 1 end
    
    local parts1 = {}
    for part in v1:gmatch("[^%.]+") do
        table.insert(parts1, tonumber(part) or 0)
    end
    
    local parts2 = {}
    for part in v2:gmatch("[^%.]+") do
        table.insert(parts2, tonumber(part) or 0)
    end
    
    for i = 1, math.max(#parts1, #parts2) do
        local p1 = parts1[i] or 0
        local p2 = parts2[i] or 0
        
        if p1 < p2 then
            return -1
        elseif p1 > p2 then
            return 1
        end
    end
    
    return 0
end

---Fetch JSON data from URL
---@param url string URL to fetch
---@return table|nil Parsed JSON data or nil on error
local function fetchJSON(url)
    local response = http.get(url)
    if not response then
        return nil
    end
    
    local content = response.readAll()
    response.close()
    
    return textutils.unserializeJSON(content)
end

---Download and install a file
---@param url string The URL to download from
---@param filepath string The local file path to save to
---@return boolean Success
local function downloadFile(url, filepath)
    local response = http.get(url)
    if not response then
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    -- Create directory if needed
    local dir = fs.getDir(filepath)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    
    local file = fs.open(filepath, "w")
    if not file then
        return false
    end
    
    file.write(content)
    file.close()
    
    return true
end

---Get information about all available libraries
---@return table|nil List of library info or nil on error
function module.getLibraries()
    return fetchJSON(API_BASE .. "libraries.json")
end

---Get information about a specific library
---@param name string Library name
---@return table|nil Library info or nil on error
function module.getLibraryInfo(name)
    return fetchJSON(API_BASE .. name .. ".json")
end

---Check for updates to installed libraries
---@return table List of libraries with available updates
function module.checkUpdates()
    local updates = {}
    local librariesData = module.getLibraries()
    
    if not librariesData or not librariesData.libraries then
        return updates
    end
    
    for _, lib in ipairs(librariesData.libraries) do
        local path = findExistingLibrary(lib.name)
        if path then
            local currentVersion = parseVersion(path)
            local latestVersion = lib.version
            
            if currentVersion and latestVersion and compareVersions(currentVersion, latestVersion) < 0 then
                table.insert(updates, {
                    name = lib.name,
                    current = currentVersion,
                    latest = latestVersion,
                    path = path,
                    download_url = lib.download_url,
                    dependencies = lib.dependencies
                })
            end
        end
    end
    
    return updates
end

---Check if a specific library has an update available
---@param name string Library name
---@return boolean, string|nil, string|nil Has update, current version, latest version
function module.hasUpdate(name)
    local path = findExistingLibrary(name)
    if not path then
        return false, nil, nil
    end
    
    local currentVersion = parseVersion(path)
    local info = module.getLibraryInfo(name)
    
    if not info or not info.version then
        return false, currentVersion, nil
    end
    
    local latestVersion = info.version
    local hasUpdate = compareVersions(currentVersion, latestVersion) < 0
    
    return hasUpdate, currentVersion, latestVersion
end

---Install or update a library
---@param name string Library name
---@param silent? boolean Suppress output messages
---@return boolean Success
function module.update(name, silent)
    local info = module.getLibraryInfo(name)
    if not info then
        if not silent then
            print("Failed to get library info for " .. name)
        end
        return false
    end
    
    -- Determine target path
    local existingPath = findExistingLibrary(name)
    local targetPath
    
    if existingPath then
        targetPath = existingPath
        if not silent then
            print("Updating " .. name .. "...")
        end
    else
        -- Install to disk/lib if disk exists, otherwise /lib
        local baseDir = (fs.exists("disk") and fs.isDir("disk")) and "disk/lib" or "/lib"
        targetPath = baseDir .. "/" .. name .. ".lua"
        if not silent then
            print("Installing " .. name .. "...")
        end
    end
    
    -- Download the file
    local success = downloadFile(info.download_url, targetPath)
    
    if success then
        if not silent then
            print("Successfully updated " .. name .. " to v" .. (info.version or "unknown"))
        end
        return true
    else
        if not silent then
            print("Failed to download " .. name)
        end
        return false
    end
end

---Update all installed libraries that have updates available
---@param silent? boolean Suppress output messages
---@return number Number of successful updates
function module.updateAll(silent)
    if not silent then
        print("Checking for updates...")
    end
    
    local updates = module.checkUpdates()
    
    if #updates == 0 then
        if not silent then
            print("All libraries are up to date!")
        end
        return 0
    end
    
    if not silent then
        print("Found " .. #updates .. " update(s) available")
        print()
    end
    
    local successCount = 0
    
    for _, update in ipairs(updates) do
        if module.update(update.name, silent) then
            successCount = successCount + 1
        end
    end
    
    if not silent then
        print()
        print("Updated " .. successCount .. "/" .. #updates .. " libraries")
    end
    
    return successCount
end

---List all installed libraries with their versions
---@return table List of {name, version, path} for installed libraries
function module.listInstalled()
    local installed = {}
    local librariesData = module.getLibraries()
    
    if not librariesData or not librariesData.libraries then
        return installed
    end
    
    for _, lib in ipairs(librariesData.libraries) do
        local path = findExistingLibrary(lib.name)
        if path then
            local version = parseVersion(path)
            table.insert(installed, {
                name = lib.name,
                version = version,
                path = path
            })
        end
    end
    
    return installed
end

---Install a new library with its dependencies
---@param name string Library name
---@param silent? boolean Suppress output messages
---@return boolean Success
function module.install(name, silent)
    -- Check if already installed
    if findExistingLibrary(name) then
        if not silent then
            print(name .. " is already installed. Use update() to update it.")
        end
        return false
    end
    
    local info = module.getLibraryInfo(name)
    if not info then
        if not silent then
            print("Library " .. name .. " not found")
        end
        return false
    end
    
    -- Install dependencies first
    if info.dependencies and #info.dependencies > 0 then
        if not silent then
            print("Installing dependencies: " .. table.concat(info.dependencies, ", "))
        end
        
        for _, dep in ipairs(info.dependencies) do
            if not findExistingLibrary(dep) then
                if not module.install(dep, silent) then
                    if not silent then
                        print("Failed to install dependency: " .. dep)
                    end
                    return false
                end
            end
        end
    end
    
    -- Install the library
    return module.update(name, silent)
end

module.VERSION = VERSION

return module
