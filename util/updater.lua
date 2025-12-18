--- A package updater module for CC-Misc utilities that checks for and installs updates
--- programmatically using the GitHub API.
---
--- Features: Check for available updates, programmatic package installation and updates,
--- version comparison, dependency resolution, batch update operations, JSON API integration,
--- project file management, interactive UI mode, and detailed logging for debugging.
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
----- Project mode (for application updaters)
---updater.withProject("AutoCrafter")
---  .withRequiredLibs({"s", "tables", "log"})
---  .withOptionalLibs({"formui", "cmd"})
---  .withFiles({
---    {url = "https://...", path = "server.lua", required = true},
---    {url = "https://...", path = "lib/ui.lua", required = true},
---  })
---  .run()
---
---@version 2.0.0
-- @module updater

local VERSION = "2.0.0"

local API_BASE = "https://ccmisc.twijn.dev/api/"
local DOWNLOAD_BASE = "https://raw.githubusercontent.com/Twijn/cc-misc/main/util/"
local LOG_DIR = "log"

local module = {}

-- Internal state
local verboseMode = false
local updateLog = {}

-- Project context state (for project mode)
---@class ProjectContext
---@field name string|nil Project name
---@field requiredLibs table Required library names
---@field optionalLibs table Optional library names
---@field files table Project files
---@field diskPrefix string Disk prefix for paths
local projectContext = nil

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

--------------------------------------------------------------------------------
-- Project Mode API
-- These functions enable the updater to manage project files alongside libraries
--------------------------------------------------------------------------------

---Reset project context
local function resetProjectContext()
    projectContext = {
        name = nil,
        requiredLibs = {},
        optionalLibs = {},
        files = {},
        diskPrefix = (fs.exists("disk") and fs.isDir("disk")) and "disk/" or "",
    }
end

---Fetch JSON data from URL (exported version)
---@param url string URL to fetch
---@return table|nil Parsed JSON data or nil on error
function module.fetchJSON(url)
    return fetchJSON(url)
end

---Download and install a file (exported version)
---@param url string The URL to download from
---@param filepath string The local file path to save to
---@param name string? Optional name for logging
---@return boolean Success
function module.downloadFile(url, filepath, name)
    return downloadFile(url, filepath, name)
end

---Builder object for project configuration
local ProjectBuilder = {}
ProjectBuilder.__index = ProjectBuilder

---Set the project name
---@param name string Project name (displayed in header)
---@return table Builder object for chaining
function ProjectBuilder:withName(name)
    projectContext.name = name
    return self
end

---Set the disk prefix for file paths
---@param prefix string Disk prefix (e.g., "disk/")
---@return table Builder object for chaining
function ProjectBuilder:withDiskPrefix(prefix)
    projectContext.diskPrefix = prefix
    return self
end

---Add required libraries (must be installed)
---@param libs table Array of library names
---@return table Builder object for chaining
function ProjectBuilder:withRequiredLibs(libs)
    for _, lib in ipairs(libs) do
        table.insert(projectContext.requiredLibs, lib)
    end
    return self
end

---Add optional libraries (can be toggled)
---@param libs table Array of library names
---@return table Builder object for chaining
function ProjectBuilder:withOptionalLibs(libs)
    for _, lib in ipairs(libs) do
        table.insert(projectContext.optionalLibs, lib)
    end
    return self
end

---Add project files to manage
---@param files table Array of {url, path, required?, name?, category?}
---@return table Builder object for chaining
function ProjectBuilder:withFiles(files)
    for _, file in ipairs(files) do
        table.insert(projectContext.files, {
            url = file.url,
            path = file.path,
            required = file.required ~= false, -- default true
            name = file.name or fs.getName(file.path),
            category = file.category or "Project Files",
        })
    end
    return self
end

---Clear screen helper
local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

---Fetch library data from API
---@return table|nil Array of library info
local function fetchLibraryData()
    local data = fetchJSON(API_BASE .. "all.json")
    if not data or not data.libraries then
        return nil
    end
    
    local libs = {}
    for name, info in pairs(data.libraries) do
        libs[name] = {
            name = name,
            version = info.version or "unknown",
            description = info.description or "No description",
            dependencies = info.dependencies or {},
            download_url = info.download_url or (DOWNLOAD_BASE .. name .. ".lua"),
        }
    end
    return libs
end

---Get library info for dependency resolution
---@param name string Library name
---@param libData table Library data map
---@return table|nil Library info
local function getLibInfo(name, libData)
    return libData and libData[name]
end

---Resolve dependencies recursively
---@param libNames table Array of library names
---@param libData table Library data map
---@return table Ordered list of libraries with dependencies first
local function resolveDeps(libNames, libData)
    local resolved = {}
    local resolvedSet = {}
    local visiting = {}
    
    local function resolve(name)
        if resolvedSet[name] then return end
        if visiting[name] then return end -- circular dep
        
        visiting[name] = true
        
        local lib = getLibInfo(name, libData)
        if lib and lib.dependencies then
            for _, dep in ipairs(lib.dependencies) do
                resolve(dep)
            end
        end
        
        visiting[name] = nil
        
        if not resolvedSet[name] then
            table.insert(resolved, name)
            resolvedSet[name] = true
        end
    end
    
    for _, name in ipairs(libNames) do
        resolve(name)
    end
    
    return resolved
end

---Category sort order (lower = higher priority)
local CATEGORY_ORDER = {
    ["Core Files"] = 1,
    ["Server"] = 2,
    ["Crafter"] = 3,
    ["Managers"] = 4,
    ["Libraries"] = 5,
    ["Config"] = 6,
    ["Required Libraries"] = 10,
    ["Optional Libraries"] = 11,
    ["Dependencies"] = 12,
}

---Get category sort priority
---@param category string Category name
---@return number Sort priority
local function getCategoryOrder(category)
    return CATEGORY_ORDER[category] or 50
end

---Sort items by category order, then by name
---@param items table Array of items
local function sortItemsByCategory(items)
    table.sort(items, function(a, b)
        local orderA = getCategoryOrder(a.category)
        local orderB = getCategoryOrder(b.category)
        if orderA ~= orderB then
            return orderA < orderB
        end
        return a.name < b.name
    end)
end

---Interactive UI for project updater
---@return boolean Success
function ProjectBuilder:run()
    if not projectContext then
        log("error", "No project context - call withProject() first")
        return false
    end
    
    log("info", "Starting project updater for: " .. (projectContext.name or "Unknown"))
    
    -- Load library data from API
    clearScreen()
    term.setTextColor(colors.lightGray)
    print("Loading library information...")
    term.setTextColor(colors.white)
    
    local libData = fetchLibraryData()
    if not libData then
        term.setTextColor(colors.yellow)
        print("Warning: Could not load library data from API")
        term.setTextColor(colors.white)
        sleep(1)
    end
    
    -- Build list of all items (files + libraries)
    local items = {}
    local selected = {}
    local forceSelected = {}
    
    -- Add project files
    for _, file in ipairs(projectContext.files) do
        local fullPath = projectContext.diskPrefix .. file.path
        local exists = fs.exists(fullPath)
        local item = {
            type = "file",
            name = file.name,
            path = file.path,
            fullPath = fullPath,
            url = file.url,
            category = file.category,
            required = file.required,
            exists = exists,
            description = file.path,
        }
        table.insert(items, item)
        
        if file.required or exists then
            selected[file.path] = true
            if file.required then
                forceSelected[file.path] = true
            end
        end
    end
    
    -- Add required libraries
    for _, libName in ipairs(projectContext.requiredLibs) do
        local lib = libData and libData[libName]
        local existingPath = findExistingLibrary(libName)
        local currentVer = existingPath and parseVersion(existingPath) or nil
        
        local item = {
            type = "library",
            name = libName,
            category = "Required Libraries",
            required = true,
            exists = existingPath ~= nil,
            existingPath = existingPath,
            version = lib and lib.version or "unknown",
            currentVersion = currentVer,
            description = lib and lib.description or "CC-Misc library",
            download_url = lib and lib.download_url,
            dependencies = lib and lib.dependencies or {},
        }
        table.insert(items, item)
        selected[libName] = true
        forceSelected[libName] = true
    end
    
    -- Add optional libraries
    for _, libName in ipairs(projectContext.optionalLibs) do
        local lib = libData and libData[libName]
        local existingPath = findExistingLibrary(libName)
        local currentVer = existingPath and parseVersion(existingPath) or nil
        
        local item = {
            type = "library",
            name = libName,
            category = "Optional Libraries",
            required = false,
            exists = existingPath ~= nil,
            existingPath = existingPath,
            version = lib and lib.version or "unknown",
            currentVersion = currentVer,
            description = lib and lib.description or "CC-Misc library",
            download_url = lib and lib.download_url,
            dependencies = lib and lib.dependencies or {},
        }
        table.insert(items, item)
        
        -- Pre-select if already installed
        if existingPath then
            selected[libName] = true
        end
    end
    
    -- Sort items by category
    sortItemsByCategory(items)
    
    -- Build display list with category headers
    local displayItems = {}
    local lastCategory = nil
    for _, item in ipairs(items) do
        if item.category ~= lastCategory then
            lastCategory = item.category
            table.insert(displayItems, {
                type = "header",
                category = item.category,
            })
        end
        table.insert(displayItems, item)
    end
    
    -- UI state
    local cursor = 1
    -- Skip to first non-header item
    while cursor <= #displayItems and displayItems[cursor].type == "header" do
        cursor = cursor + 1
    end
    
    local w, h = term.getSize()
    
    while true do
        clearScreen()
        
        -- Header
        local headerText = projectContext.name and (projectContext.name .. " Updater") or "Project Updater"
        term.setTextColor(colors.yellow)
        print("================================")
        print("  " .. headerText)
        print("================================")
        term.setTextColor(colors.lightGray)
        print("Up/Down: Move | Space: Toggle | Enter: Install | Q: Quit")
        term.setTextColor(colors.white)
        print()
        
        local headerLines = 6
        local footerLines = 2
        local maxVisibleItems = h - headerLines - footerLines
        
        -- Calculate scroll based on displayItems
        local totalDisplayItems = #displayItems
        local scroll = math.max(0, math.min(cursor - math.floor(maxVisibleItems / 2), totalDisplayItems - maxVisibleItems))
        scroll = math.max(0, scroll)
        
        local startIdx = scroll + 1
        local endIdx = math.min(startIdx + maxVisibleItems - 1, totalDisplayItems)
        
        for i = startIdx, endIdx do
            local item = displayItems[i]
            
            -- Handle category headers
            if item.type == "header" then
                term.setTextColor(colors.black)
                term.setBackgroundColor(colors.lightGray)
                local headerLine = " >> " .. item.category .. " "
                headerLine = headerLine .. string.rep("-", math.max(0, w - #headerLine))
                print(headerLine)
                term.setBackgroundColor(colors.black)
            else
                -- Regular item
                local key = item.type == "file" and item.path or item.name
                local isCursor = (i == cursor)
                local isSelected = selected[key]
                local isForced = forceSelected[key]
                
                -- Check if required by selected libraries (dependency)
                local isRequiredBy = nil
                if item.type == "library" then
                    for _, otherItem in ipairs(items) do
                        if otherItem.type == "library" and selected[otherItem.name] and otherItem.dependencies then
                            for _, dep in ipairs(otherItem.dependencies) do
                                if dep == item.name then
                                    isRequiredBy = otherItem.name
                                    break
                                end
                            end
                        end
                        if isRequiredBy then break end
                    end
                end
                
                -- Determine marker
                local marker
                if isForced then
                    marker = "[R]" -- Required
                elseif isRequiredBy then
                    marker = "[+]" -- Dependency
                    if not selected[key] then
                        selected[key] = true -- Auto-select dependencies
                    end
                elseif isSelected then
                    marker = "[X]"
                else
                    marker = "[ ]"
                end
                
                -- Status indicator
                local status = ""
                if item.type == "library" then
                    if item.exists and item.currentVersion then
                        if item.currentVersion == item.version then
                            status = " (v" .. item.currentVersion .. " - current)"
                        else
                            status = " (v" .. (item.currentVersion or "?") .. " -> v" .. item.version .. ")"
                        end
                    elseif item.exists then
                        status = " (installed)"
                    else
                        status = " (v" .. item.version .. " - new)"
                    end
                else
                    status = item.exists and " (update)" or " (new)"
                end
                
                -- Cursor highlighting
                if isCursor then
                    term.setTextColor(colors.black)
                    term.setBackgroundColor(colors.white)
                else
                    -- Color based on status
                    if isForced then
                        term.setTextColor(colors.orange)
                    elseif isRequiredBy then
                        term.setTextColor(colors.cyan)
                    elseif isSelected then
                        if item.exists then
                            term.setTextColor(colors.yellow)
                        else
                            term.setTextColor(colors.green)
                        end
                    else
                        term.setTextColor(colors.lightGray)
                    end
                    term.setBackgroundColor(colors.black)
                end
                
                local line = "  " .. marker .. " " .. item.name .. status
                if #line > w then
                    line = line:sub(1, w)
                else
                    line = line .. string.rep(" ", w - #line)
                end
                print(line)
            end
        end
        
        -- Reset colors
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        
        -- Footer
        local selectedCount = 0
        for _ in pairs(selected) do selectedCount = selectedCount + 1 end
        
        term.setCursorPos(1, h)
        term.setTextColor(colors.lightGray)
        write(string.format("Selected: %d/%d items", selectedCount, #items))
        term.setTextColor(colors.white)
        
        -- Handle input
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            -- Move up, skipping headers
            repeat
                cursor = cursor - 1
            until cursor < 1 or displayItems[cursor].type ~= "header"
            if cursor < 1 then cursor = 1 end
            -- If we landed on a header at the top, find the first non-header
            while cursor <= #displayItems and displayItems[cursor].type == "header" do
                cursor = cursor + 1
            end
        elseif key == keys.down then
            -- Move down, skipping headers
            repeat
                cursor = cursor + 1
            until cursor > #displayItems or displayItems[cursor].type ~= "header"
            if cursor > #displayItems then
                cursor = #displayItems
                -- If we landed on a header at the bottom, go back up
                while cursor > 1 and displayItems[cursor].type == "header" do
                    cursor = cursor - 1
                end
            end
        elseif key == keys.space then
            local item = displayItems[cursor]
            if item.type == "header" then
                -- Skip headers
            else
                local itemKey = item.type == "file" and item.path or item.name
                
                if forceSelected[itemKey] then
                    -- Cannot toggle required items
                    term.setCursorPos(1, h - 1)
                    term.clearLine()
                    term.setTextColor(colors.red)
                    write("Cannot deselect: required for project")
                    term.setTextColor(colors.white)
                    sleep(1.5)
                else
                    -- Check if it's a dependency
                    local isRequiredBy = nil
                    if item.type == "library" then
                        for _, otherItem in ipairs(items) do
                            if otherItem.type == "library" and selected[otherItem.name] and otherItem.dependencies then
                                for _, dep in ipairs(otherItem.dependencies) do
                                    if dep == item.name then
                                        isRequiredBy = otherItem.name
                                        break
                                    end
                                end
                            end
                            if isRequiredBy then break end
                        end
                    end
                    
                    if isRequiredBy and selected[itemKey] then
                        term.setCursorPos(1, h - 1)
                        term.clearLine()
                        term.setTextColor(colors.red)
                        write("Cannot deselect: required by " .. isRequiredBy)
                        term.setTextColor(colors.white)
                        sleep(1.5)
                    else
                        selected[itemKey] = not selected[itemKey]
                    end
                end
            end
        elseif key == keys.enter then
            break
        elseif key == keys.q then
            clearScreen()
            term.setTextColor(colors.yellow)
            print("Update cancelled.")
            term.setTextColor(colors.white)
            log("info", "Project update cancelled by user")
            return false
        end
    end
    
    -- Perform installation
    clearScreen()
    term.setTextColor(colors.yellow)
    print("================================")
    print("  Installing/Updating...")
    print("================================")
    term.setTextColor(colors.white)
    print()
    
    local success = 0
    local failed = 0
    local total = 0
    
    -- Count selected items
    for _, item in ipairs(items) do
        local key = item.type == "file" and item.path or item.name
        if selected[key] then
            total = total + 1
        end
    end
    
    -- Collect libraries for dependency resolution
    local selectedLibs = {}
    for _, item in ipairs(items) do
        if item.type == "library" then
            local key = item.name
            if selected[key] then
                table.insert(selectedLibs, item.name)
            end
        end
    end
    
    -- Resolve library dependencies
    local resolvedLibs = resolveDeps(selectedLibs, libData)
    
    -- Add any new dependencies that weren't in original list
    for _, libName in ipairs(resolvedLibs) do
        local found = false
        for _, item in ipairs(items) do
            if item.type == "library" and item.name == libName then
                found = true
                break
            end
        end
        if not found then
            -- Add dependency that wasn't in original list
            local lib = libData and libData[libName]
            local existingPath = findExistingLibrary(libName)
            if not existingPath then
                -- Need to install this dependency
                total = total + 1
                local item = {
                    type = "library",
                    name = libName,
                    category = "Dependencies",
                    required = true,
                    exists = false,
                    version = lib and lib.version or "unknown",
                    download_url = lib and lib.download_url,
                }
                table.insert(items, item)
                selected[libName] = true
                term.setTextColor(colors.cyan)
                print("  + Adding dependency: " .. libName)
                term.setTextColor(colors.white)
            end
        end
    end
    
    print()
    
    -- Install files first
    local fileCount = 1
    for _, item in ipairs(items) do
        if item.type == "file" and selected[item.path] then
            term.setTextColor(colors.lightGray)
            local action = item.exists and "Updating" or "Installing"
            write(string.format("[%d/%d] %s %s... ", fileCount, total, action, item.name))
            
            local fullPath = projectContext.diskPrefix .. item.path
            
            -- Create directory if needed
            local dir = fs.getDir(fullPath)
            if dir ~= "" and not fs.exists(dir) then
                fs.makeDir(dir)
            end
            
            if downloadFile(item.url, fullPath, item.name) then
                term.setTextColor(colors.green)
                print("OK")
                success = success + 1
            else
                term.setTextColor(colors.red)
                print("FAILED")
                failed = failed + 1
            end
            fileCount = fileCount + 1
        end
    end
    
    -- Install libraries
    local libCount = fileCount
    for _, libName in ipairs(resolvedLibs) do
        if selected[libName] or not findExistingLibrary(libName) then
            local lib = libData and libData[libName]
            local existingPath = findExistingLibrary(libName)
            local currentVer = existingPath and parseVersion(existingPath) or nil
            
            term.setTextColor(colors.lightGray)
            local action, verInfo
            if existingPath then
                action = "Updating"
                verInfo = (currentVer or "?") .. " -> " .. (lib and lib.version or "?")
            else
                action = "Installing"
                verInfo = "v" .. (lib and lib.version or "?")
            end
            write(string.format("[%d/%d] %s %s (%s)... ", libCount, total, action, libName, verInfo))
            
            -- Determine target path
            local targetPath
            if existingPath then
                targetPath = existingPath
            else
                local libDir = projectContext.diskPrefix .. "lib"
                if not fs.exists(libDir) then
                    fs.makeDir(libDir)
                end
                targetPath = libDir .. "/" .. libName .. ".lua"
            end
            
            local url = lib and lib.download_url or (DOWNLOAD_BASE .. libName .. ".lua")
            if downloadFile(url, targetPath, libName) then
                term.setTextColor(colors.green)
                print("OK")
                success = success + 1
            else
                term.setTextColor(colors.red)
                print("FAILED")
                failed = failed + 1
            end
            libCount = libCount + 1
        end
    end
    
    -- Summary
    print()
    if failed == 0 then
        term.setTextColor(colors.green)
        print("================================")
        print("  Update Complete!")
        print("================================")
        log("info", "Project update complete: " .. success .. " items installed/updated")
    else
        term.setTextColor(colors.yellow)
        print("================================")
        print(string.format("  Update finished: %d OK, %d failed", success, failed))
        print("================================")
        log("warn", "Project update finished with errors: " .. success .. " ok, " .. failed .. " failed")
    end
    term.setTextColor(colors.white)
    
    return failed == 0
end

---Start project mode with optional name
---@param name string? Project name
---@return table Builder object for chaining
function module.withProject(name)
    resetProjectContext()
    if name then
        projectContext.name = name
    end
    return setmetatable({}, ProjectBuilder)
end

module.VERSION = VERSION

return module
