--- A package updater module for CC-Misc utilities that checks for and installs updates
--- programmatically using the GitHub API.
---
--- Features: Check for available updates, programmatic package installation and updates,
--- version comparison, dependency resolution, batch update operations, JSON API integration,
--- and detailed logging for debugging.
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
----- Enable verbose mode for debugging
---updater.setVerbose(true)
---
---@version 1.1.0
-- @module updater

local VERSION = "1.1.0"

local API_BASE = "https://ccmisc.twijn.dev/api/"
local DOWNLOAD_BASE = "https://raw.githubusercontent.com/Twijn/cc-misc/main/util/"
local LOG_DIR = "log"

local module = {}

-- Internal state
local verboseMode = false
local updateLog = {}

---Enable or disable verbose output
---@param enabled boolean Whether to enable verbose output
function module.setVerbose(enabled)
    verboseMode = enabled == true
end

---Get the current log entries
---@return table Array of log entries
function module.getLog()
    return updateLog
end

---Clear the log
function module.clearLog()
    updateLog = {}
end

---Internal logging function
---@param level string Log level (info, warn, error, debug)
---@param msg string Message to log
local function log(level, msg)
    local entry = {
        time = os.date("%H:%M:%S"),
        level = level,
        message = msg
    }
    table.insert(updateLog, entry)
    
    -- Write to file
    if not fs.exists(LOG_DIR) then
        fs.makeDir(LOG_DIR)
    end
    
    local f = fs.open(LOG_DIR .. "/updater-" .. os.date("%Y-%m-%d") .. ".txt", "a")
    if f then
        f.writeLine(string.format("[%s] [%s] %s", entry.time, level:upper(), msg))
        f.close()
    end
    
    -- Print if verbose
    if verboseMode then
        if level == "error" then
            term.setTextColor(colors.red)
        elseif level == "warn" then
            term.setTextColor(colors.yellow)
        elseif level == "debug" then
            term.setTextColor(colors.gray)
        else
            term.setTextColor(colors.lightBlue)
        end
        print("[" .. level:upper() .. "] " .. msg)
        term.setTextColor(colors.white)
    end
end

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
    log("debug", "Fetching JSON from: " .. url)
    local response = http.get(url)
    if not response then
        log("error", "HTTP request failed: " .. url)
        return nil
    end
    
    local content = response.readAll()
    response.close()
    log("debug", "Received " .. #content .. " bytes")
    
    return textutils.unserializeJSON(content)
end

---Download and install a file
---@param url string The URL to download from
---@param filepath string The local file path to save to
---@param libName string? Optional library name for logging
---@return boolean Success
local function downloadFile(url, filepath, libName)
    log("debug", "Downloading: " .. url)
    local response = http.get(url)
    if not response then
        log("error", "Failed to download from: " .. url)
        return false
    end
    
    local content = response.readAll()
    response.close()
    log("debug", "Downloaded " .. #content .. " bytes")
    
    -- Create directory if needed
    local dir = fs.getDir(filepath)
    if dir ~= "" and not fs.exists(dir) then
        log("debug", "Creating directory: " .. dir)
        fs.makeDir(dir)
    end
    
    local file = fs.open(filepath, "w")
    if not file then
        log("error", "Failed to open file for writing: " .. filepath)
        return false
    end
    
    file.write(content)
    file.close()
    
    log("info", "Saved " .. (libName or "file") .. " to " .. filepath .. " (" .. #content .. " bytes)")
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
    log("info", "Updating library: " .. name)
    local info = module.getLibraryInfo(name)
    if not info then
        log("error", "Failed to get library info for " .. name)
        if not silent then
            print("Failed to get library info for " .. name)
        end
        return false
    end
    
    -- Determine target path
    local existingPath = findExistingLibrary(name)
    local targetPath
    local action
    local currentVersion
    
    if existingPath then
        targetPath = existingPath
        currentVersion = parseVersion(existingPath) or "unknown"
        action = "Updating"
        log("info", "Found existing installation at " .. existingPath .. " (v" .. currentVersion .. ")")
        if not silent then
            term.setTextColor(colors.yellow)
            write("Updating " .. name .. " (v" .. currentVersion .. " -> v" .. (info.version or "unknown") .. ")... ")
        end
    else
        -- Install to disk/lib if disk exists, otherwise /lib
        local baseDir = (fs.exists("disk") and fs.isDir("disk")) and "disk/lib" or "/lib"
        targetPath = baseDir .. "/" .. name .. ".lua"
        action = "Installing"
        log("info", "Installing new library to " .. targetPath)
        if not silent then
            term.setTextColor(colors.lightGray)
            write("Installing " .. name .. " (v" .. (info.version or "unknown") .. ") to " .. targetPath .. "... ")
        end
    end
    
    -- Download the file
    log("debug", "Downloading from: " .. (info.download_url or "unknown URL"))
    local success = downloadFile(info.download_url, targetPath, name)
    
    if success then
        log("info", action .. " " .. name .. " complete (v" .. (info.version or "unknown") .. ")")
        if not silent then
            term.setTextColor(colors.green)
            print("OK")
            term.setTextColor(colors.white)
        end
        return true
    else
        log("error", "Failed to download " .. name .. " from " .. (info.download_url or "unknown URL"))
        if not silent then
            term.setTextColor(colors.red)
            print("FAILED")
            term.setTextColor(colors.white)
        end
        return false
    end
end

---Update all installed libraries that have updates available
---@param silent? boolean Suppress output messages
---@return number Number of successful updates
function module.updateAll(silent)
    log("info", "Checking for updates to all installed libraries")
    if not silent then
        term.setTextColor(colors.lightGray)
        print("Checking for updates...")
        term.setTextColor(colors.white)
    end
    
    local updates = module.checkUpdates()
    
    if #updates == 0 then
        log("info", "All libraries are up to date")
        if not silent then
            term.setTextColor(colors.green)
            print("All libraries are up to date!")
            term.setTextColor(colors.white)
        end
        return 0
    end
    
    log("info", "Found " .. #updates .. " update(s) available")
    if not silent then
        term.setTextColor(colors.yellow)
        print("Found " .. #updates .. " update(s) available:")
        term.setTextColor(colors.white)
        for _, update in ipairs(updates) do
            print("  - " .. update.name .. ": v" .. update.current .. " -> v" .. update.latest)
        end
        print()
    end
    
    local successCount = 0
    
    for i, update in ipairs(updates) do
        if not silent then
            term.setTextColor(colors.lightGray)
            write("[" .. i .. "/" .. #updates .. "] ")
            term.setTextColor(colors.white)
        end
        if module.update(update.name, silent) then
            successCount = successCount + 1
        end
    end
    
    if not silent then
        print()
        if successCount == #updates then
            term.setTextColor(colors.green)
            print("Successfully updated all " .. successCount .. " libraries!")
        else
            term.setTextColor(colors.yellow)
            print("Updated " .. successCount .. "/" .. #updates .. " libraries")
        end
        term.setTextColor(colors.white)
    end
    
    log("info", "Update complete: " .. successCount .. "/" .. #updates .. " succeeded")
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
    log("info", "Installing library: " .. name)
    
    -- Check if already installed
    local existingPath = findExistingLibrary(name)
    if existingPath then
        log("info", name .. " is already installed at " .. existingPath)
        if not silent then
            term.setTextColor(colors.yellow)
            print(name .. " is already installed at " .. existingPath)
            print("Use update() to update it.")
            term.setTextColor(colors.white)
        end
        return false
    end
    
    local info = module.getLibraryInfo(name)
    if not info then
        log("error", "Library " .. name .. " not found in API")
        if not silent then
            term.setTextColor(colors.red)
            print("Library " .. name .. " not found")
            term.setTextColor(colors.white)
        end
        return false
    end
    
    -- Install dependencies first
    if info.dependencies and #info.dependencies > 0 then
        log("info", "Library " .. name .. " requires dependencies: " .. table.concat(info.dependencies, ", "))
        if not silent then
            term.setTextColor(colors.cyan)
            print("Installing dependencies for " .. name .. ": " .. table.concat(info.dependencies, ", "))
            term.setTextColor(colors.white)
        end
        
        for _, dep in ipairs(info.dependencies) do
            if not findExistingLibrary(dep) then
                log("info", "Installing dependency: " .. dep)
                if not module.install(dep, silent) then
                    log("error", "Failed to install dependency: " .. dep)
                    if not silent then
                        term.setTextColor(colors.red)
                        print("Failed to install dependency: " .. dep)
                        term.setTextColor(colors.white)
                    end
                    return false
                end
            else
                log("debug", "Dependency " .. dep .. " already installed")
            end
        end
    end
    
    -- Install the library
    return module.update(name, silent)
end

---Show the update log in a scrollable view (interactive)
function module.showLog()
    local scroll = 0
    local w, h = term.getSize()
    local maxVisibleLines = h - 4
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        -- Header
        term.setTextColor(colors.yellow)
        print("Updater Log (" .. #updateLog .. " entries)")
        term.setTextColor(colors.lightGray)
        print("Up/Down: Scroll | Q: Close")
        term.setTextColor(colors.white)
        print()
        
        -- Display log entries
        local startIdx = scroll + 1
        local endIdx = math.min(startIdx + maxVisibleLines - 1, #updateLog)
        
        for i = startIdx, endIdx do
            local entry = updateLog[i]
            if entry then
                -- Color based on level
                if entry.level == "error" then
                    term.setTextColor(colors.red)
                elseif entry.level == "warn" then
                    term.setTextColor(colors.yellow)
                elseif entry.level == "debug" then
                    term.setTextColor(colors.gray)
                else
                    term.setTextColor(colors.white)
                end
                
                local line = string.format("[%s] %s", entry.time, entry.message)
                if #line > w then
                    line = line:sub(1, w)
                end
                print(line)
            end
        end
        
        -- Footer
        term.setCursorPos(1, h)
        term.setTextColor(colors.gray)
        if #updateLog > 0 then
            write(string.format("Line %d-%d of %d", startIdx, endIdx, #updateLog))
        else
            write("No log entries")
        end
        term.setTextColor(colors.white)
        
        -- Handle input
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            scroll = math.max(0, scroll - 1)
        elseif key == keys.down then
            scroll = math.min(math.max(0, #updateLog - maxVisibleLines), scroll + 1)
        elseif key == keys.q then
            break
        end
    end
end

---Get the log file path for the current day
---@return string Log file path
function module.getLogFile()
    return LOG_DIR .. "/updater-" .. os.date("%Y-%m-%d") .. ".txt"
end

module.VERSION = VERSION

return module
