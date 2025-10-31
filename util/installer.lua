--- Installer Generator for CC-Misc Utilities
--- Interactive tool to install ComputerCraft libraries with dependency management
---
--- This tool provides a user-friendly interface to select and install libraries from the cc-misc
--- repository directly to your ComputerCraft computer. Library information is loaded from the
--- online API at https://ccmisc.twijn.dev/api/all.json with automatic fallback to offline mode.
---
--- Features:
--- - Dynamic library loading from API with detailed information
--- - Press RIGHT arrow to view library details (functions, version, dependencies)
--- - Automatic dependency resolution
--- - Visual indicators for selections and requirements
--- - Install/update or generate installer scripts
---
---@usage
---wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installer.lua
---
--- Or pre-select libraries:
---wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installer.lua cmd s
---
-- @module installer

local VERSION = "3.0.1"
local GITHUB_RAW_BASE = "https://raw.githubusercontent.com/Twijn/cc-misc/main/util/"
local API_URL = "https://ccmisc.twijn.dev/api/all.json"

-- Available libraries (loaded from API or fallback)
local LIBRARIES = nil
local API_DATA = nil -- Full API data with detailed information

---Load libraries from API
---@return boolean Success
local function loadLibrariesFromAPI()
    term.setTextColor(colors.lightGray)
    print("Loading library information from API...")
    term.setTextColor(colors.white)
    
    local response = http.get(API_URL)
    if not response then
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    -- Parse JSON
    local data = textutils.unserializeJSON(content)
    if not data or not data.libraries then
        return false
    end
    
    -- Store full API data
    API_DATA = data.libraries
    
    -- Convert to LIBRARIES format
    LIBRARIES = {}
    for name, info in pairs(data.libraries) do
        table.insert(LIBRARIES, {
            name = name,
            version = info.version or "unknown",
            description = info.description or "No description available",
            deps = info.dependencies or {}
        })
    end
    
    -- Sort by name
    table.sort(LIBRARIES, function(a, b) return a.name < b.name end)
    
    return true
end

---Fallback libraries (used if API is unavailable)
local function loadFallbackLibraries()
    LIBRARIES = {
        {name = "cmd", version = "1.0.0", description = "Command-line interface with REPL, autocompletion, and history", deps = {}},
        {name = "formui", version = "0.2.0", description = "Form-based UI builder for creating interactive forms", deps = {}},
        {name = "log", version = "1.0.0", description = "Logging utility with file and term output support", deps = {}},
        {name = "persist", version = "1.0.0", description = "Data persistence utility for saving/loading Lua tables", deps = {}},
        {name = "s", version = "2.0.0", description = "Settings management with interactive config", deps = {"tables"}},
        {name = "tables", version = "1.0.0", description = "Table manipulation utilities (deep copy, merge, etc.)", deps = {}},
        {name = "timeutil", version = "1.0.0", description = "Time formatting and manipulation utilities", deps = {}},
        {name = "shopk", version = "0.0.4", description = "Kromer API client for shop integration", deps = {}},
        {name = "updater", version = "1.0.1", description = "Programmatic package updater and version manager", deps = {}},
    }
    API_DATA = nil
end

---Clear the terminal screen
local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

---Print colored text
---@param text string The text to print
---@param color number The color to use
local function printColored(text, color)
    term.setTextColor(color)
    print(text)
    term.setTextColor(colors.white)
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

---Get library info by name
---@param name string Library name
---@return table|nil Library info or nil
local function getLibraryInfo(name)
    for _, lib in ipairs(LIBRARIES) do
        if lib.name == name then
            return lib
        end
    end
    return nil
end

---Show detailed library information
---@param libName string Library name
local function showLibraryDetails(libName)
    local lib = getLibraryInfo(libName)
    if not lib then
        return
    end
    
    local apiInfo = API_DATA and API_DATA[libName]
    local w, h = term.getSize()
    local scroll = 0
    
    while true do
        clearScreen()
        
        -- Header
        term.setTextColor(colors.yellow)
        print(libName .. " - Details")
        term.setTextColor(colors.lightGray)
        print("Up/Down: Scroll | Left/ESC: Back")
        term.setTextColor(colors.white)
        print()
        
        -- Build content lines
        local lines = {}
        
        -- Version
        table.insert(lines, {text = "Version: " .. lib.version, color = colors.lightBlue})
        table.insert(lines, {text = "", color = colors.white})
        
        -- Description
        table.insert(lines, {text = "Description:", color = colors.yellow})
        -- Word wrap description
        local desc = lib.description
        local maxWidth = w - 2
        while #desc > 0 do
            if #desc <= maxWidth then
                table.insert(lines, {text = "  " .. desc, color = colors.lightGray})
                break
            else
                local cutoff = maxWidth
                -- Try to break at a space
                local lastSpace = desc:sub(1, maxWidth):match("^.*() ")
                if lastSpace and lastSpace > maxWidth * 0.6 then
                    cutoff = lastSpace - 1
                end
                table.insert(lines, {text = "  " .. desc:sub(1, cutoff), color = colors.lightGray})
                desc = desc:sub(cutoff + 1):match("^%s*(.*)") -- Trim leading whitespace
            end
        end
        table.insert(lines, {text = "", color = colors.white})
        
        -- Dependencies
        if lib.deps and #lib.deps > 0 then
            table.insert(lines, {text = "Dependencies:", color = colors.yellow})
            for _, dep in ipairs(lib.deps) do
                table.insert(lines, {text = "  - " .. dep, color = colors.cyan})
            end
            table.insert(lines, {text = "", color = colors.white})
        end
        
        -- API information (if available)
        if apiInfo then
            -- Functions
            if apiInfo.functions and #apiInfo.functions > 0 then
                table.insert(lines, {text = "Functions (" .. #apiInfo.functions .. "):", color = colors.yellow})
                for i, func in ipairs(apiInfo.functions) do
                    if i <= 10 then -- Limit to first 10 functions
                        local signature = func.name .. "("
                        if func.params and #func.params > 0 then
                            local paramNames = {}
                            for _, param in ipairs(func.params) do
                                table.insert(paramNames, param.name)
                            end
                            signature = signature .. table.concat(paramNames, ", ")
                        end
                        signature = signature .. ")"
                        
                        table.insert(lines, {text = "  " .. signature, color = colors.lightBlue})
                        if func.description and func.description ~= "" then
                            -- Word wrap function description
                            local funcDesc = "    " .. func.description
                            local fmaxWidth = w - 4
                            while #funcDesc > 0 do
                                if #funcDesc <= fmaxWidth then
                                    table.insert(lines, {text = funcDesc, color = colors.gray})
                                    break
                                else
                                    local fcutoff = fmaxWidth
                                    local flastSpace = funcDesc:sub(1, fmaxWidth):match("^.*() ")
                                    if flastSpace and flastSpace > fmaxWidth * 0.6 then
                                        fcutoff = flastSpace - 1
                                    end
                                    table.insert(lines, {text = funcDesc:sub(1, fcutoff), color = colors.gray})
                                    funcDesc = "    " .. funcDesc:sub(fcutoff + 1):match("^%s*(.*)")
                                end
                            end
                        end
                        if func.returns and func.returns ~= "" then
                            table.insert(lines, {text = "    Returns: " .. func.returns, color = colors.green})
                        end
                    end
                end
                if #apiInfo.functions > 10 then
                    table.insert(lines, {text = "  ... and " .. (#apiInfo.functions - 10) .. " more", color = colors.gray})
                end
                table.insert(lines, {text = "", color = colors.white})
            end
            
            -- Classes
            if apiInfo.classes and #apiInfo.classes > 0 then
                table.insert(lines, {text = "Classes (" .. #apiInfo.classes .. "):", color = colors.yellow})
                for _, class in ipairs(apiInfo.classes) do
                    table.insert(lines, {text = "  " .. class.name, color = colors.lightBlue})
                    if class.description and class.description ~= "" then
                        table.insert(lines, {text = "    " .. class.description, color = colors.gray})
                    end
                end
                table.insert(lines, {text = "", color = colors.white})
            end
            
            -- Links
            if apiInfo.documentation_url then
                table.insert(lines, {text = "Documentation:", color = colors.yellow})
                table.insert(lines, {text = "  " .. apiInfo.documentation_url, color = colors.blue})
                table.insert(lines, {text = "", color = colors.white})
            end
        else
            table.insert(lines, {text = "No detailed information available (offline mode)", color = colors.gray})
        end
        
        -- Display visible lines with scrolling
        local maxVisibleLines = h - 4
        local startLine = scroll + 1
        local endLine = math.min(startLine + maxVisibleLines - 1, #lines)
        
        for i = startLine, endLine do
            term.setTextColor(lines[i].color)
            print(lines[i].text)
        end
        
        -- Scroll indicator
        if #lines > maxVisibleLines then
            term.setCursorPos(1, h)
            term.setTextColor(colors.gray)
            write(string.format("Line %d-%d of %d", startLine, endLine, #lines))
        end
        
        term.setTextColor(colors.white)
        
        -- Handle input
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            scroll = math.max(0, scroll - 1)
        elseif key == keys.down then
            scroll = math.min(math.max(0, #lines - maxVisibleLines), scroll + 1)
        elseif key == keys.left or key == keys.backspace then
            break
        end
    end
end

---Resolve dependencies recursively
---@param libNames table List of library names
---@return table List of library names with all dependencies
local function resolveDependencies(libNames)
    local resolved = {}
    local resolvedSet = {}
    local visiting = {}
    
    local function resolve(name)
        if resolvedSet[name] then
            return -- Already resolved
        end
        
        if visiting[name] then
            -- Circular dependency detected - skip
            return
        end
        
        visiting[name] = true
        
        local lib = getLibraryInfo(name)
        if lib and lib.deps then
            for _, dep in ipairs(lib.deps) do
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

---Display library selection menu with scrolling support
---@param preselected table? Table of library names to pre-select
---@return table|nil Selected library names (with dependencies resolved)
---@return table|nil Libraries to delete
---@return table|nil Original selection (before dependency resolution)
local function selectLibraries(preselected)
    local selected = {}
    local cursor = 1
    local w, h = term.getSize()
    local forceSelected = {} -- Track libraries that were pre-selected via args
    
    -- Pre-select existing libraries
    for _, lib in ipairs(LIBRARIES) do
        local existing = findExistingLibrary(lib.name)
        if existing then
            selected[lib.name] = true
        end
    end
    
    -- Apply preselected libraries from arguments (force-selected)
    if preselected then
        for _, libName in ipairs(preselected) do
            selected[libName] = true
            forceSelected[libName] = true
        end
    end
    
    -- Calculate how many items can fit on screen
    local headerLines = 3
    local footerLines = 2
    local maxVisibleItems = h - headerLines - footerLines
    
    while true do
        clearScreen()
        
        -- Header
        term.setTextColor(colors.yellow)
        print("CC-Misc Installer v" .. VERSION)
        term.setTextColor(colors.lightGray)
        print("Up/Down: Move | Space: Toggle | Right: Details | Enter: Continue | Q: Quit")
        term.setTextColor(colors.white)
        print()
        
        -- Calculate visible range (scroll window)
        local totalItems = #LIBRARIES
        local scroll = math.max(0, math.min(cursor - math.floor(maxVisibleItems / 2), totalItems - maxVisibleItems))
        scroll = math.max(0, scroll)
        
        local startIdx = scroll + 1
        local endIdx = math.min(startIdx + maxVisibleItems - 1, totalItems)
        
        -- Display items
        for i = startIdx, endIdx do
            local lib = LIBRARIES[i]
            local isExisting = findExistingLibrary(lib.name) ~= nil
            local isCursor = (i == cursor)
            local willDelete = isExisting and not selected[lib.name]
            
            -- Check if this library is required by any selected library
            local isRequiredBy = {}
            for _, otherLib in ipairs(LIBRARIES) do
                if selected[otherLib.name] and otherLib.deps then
                    for _, dep in ipairs(otherLib.deps) do
                        if dep == lib.name then
                            table.insert(isRequiredBy, otherLib.name)
                        end
                    end
                end
            end
            
            -- Check if required by force-selected (argument) libraries
            local requiredByArgs = false
            for _, reqBy in ipairs(isRequiredBy) do
                if forceSelected[reqBy] then
                    requiredByArgs = true
                    break
                end
            end
            
            -- Determine marker
            local marker
            if willDelete then
                marker = "[D]" -- Marked for uninstall (unchecked existing library)
            elseif forceSelected[lib.name] then
                marker = "[A]" -- Specified via arguments (forced selection)
            elseif requiredByArgs then
                marker = "[R]" -- Required by argument-specified packages
            elseif #isRequiredBy > 0 and selected[lib.name] then
                marker = "[+]" -- Required by other selected packages (dependency)
            elseif selected[lib.name] then
                marker = "[X]"
            else
                marker = "[ ]"
            end
            
            if isCursor then
                term.setTextColor(colors.black)
                term.setBackgroundColor(colors.white)
            else
                -- Color based on status
                if willDelete then
                    term.setTextColor(colors.red) -- Marked for uninstall (always red)
                elseif forceSelected[lib.name] then
                    term.setTextColor(colors.orange) -- Specified via arguments
                elseif requiredByArgs then
                    term.setTextColor(colors.cyan) -- Required by argument packages
                elseif #isRequiredBy > 0 and selected[lib.name] then
                    term.setTextColor(colors.lightBlue) -- Auto-added dependency
                elseif isExisting then
                    term.setTextColor(colors.yellow) -- Existing library (update)
                elseif selected[lib.name] then
                    term.setTextColor(colors.green) -- New library to install
                else
                    term.setTextColor(colors.white) -- Not selected
                end
                term.setBackgroundColor(colors.black)
            end
            
            local line = string.format("%s %s - %s", marker, lib.name, lib.description)
            if lib.deps and #lib.deps > 0 then
                line = line .. " (requires: " .. table.concat(lib.deps, ", ") .. ")"
            end
            if #isRequiredBy > 0 then
                line = line .. " (required by: " .. table.concat(isRequiredBy, ", ") .. ")"
            end
            if #line > w then
                line = line:sub(1, w)
            else
                line = line .. string.rep(" ", w - #line)
            end
            print(line)
        end
        
        -- Reset colors
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        
        -- Footer - count selected, installed, and to delete
        local selectedCount = 0
        local installedCount = 0
        local deleteCount = 0
        for _ in pairs(selected) do selectedCount = selectedCount + 1 end
        for _, lib in ipairs(LIBRARIES) do
            local existing = findExistingLibrary(lib.name)
            if existing then
                installedCount = installedCount + 1
                if not selected[lib.name] then
                    deleteCount = deleteCount + 1
                end
            end
        end
        
        term.setCursorPos(1, h)
        term.setTextColor(colors.lightGray)
        local statusText = string.format("Selected: %d/%d | Installed: %d/%d", selectedCount, totalItems, installedCount, totalItems)
        if deleteCount > 0 then
            statusText = statusText .. string.format(" | To Uninstall: %d", deleteCount)
        end
        write(statusText)
        term.setTextColor(colors.white)
        
        -- Handle input
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            cursor = math.max(1, cursor - 1)
        elseif key == keys.down then
            cursor = math.min(totalItems, cursor + 1)
        elseif key == keys.right then
            -- Show library details
            local lib = LIBRARIES[cursor]
            showLibraryDetails(lib.name)
        elseif key == keys.space or key == keys.d then
            local lib = LIBRARIES[cursor]
            
            -- Check if this library is force-selected (from arguments)
            if forceSelected[lib.name] and selected[lib.name] then
                -- Cannot deselect force-selected libraries
                term.setTextColor(colors.red)
                term.setCursorPos(1, h - 1)
                term.clearLine()
                write("Cannot deselect: required by arguments")
                term.setTextColor(colors.white)
                sleep(2.5)
            else
                -- Check if this library is required by any selected library
                local isRequiredBy = {}
                for _, otherLib in ipairs(LIBRARIES) do
                    if selected[otherLib.name] and otherLib.deps then
                        for _, dep in ipairs(otherLib.deps) do
                            if dep == lib.name then
                                table.insert(isRequiredBy, otherLib.name)
                            end
                        end
                    end
                end
                
                if #isRequiredBy > 0 and selected[lib.name] then
                    -- Cannot deselect if required by other selected libraries
                    term.setTextColor(colors.red)
                    term.setCursorPos(1, h - 1)
                    term.clearLine()
                    write("Cannot deselect: required by " .. table.concat(isRequiredBy, ", "))
                    term.setTextColor(colors.white)
                    sleep(2.5)
                else
                    -- Toggle selection
                    if selected[lib.name] then
                        selected[lib.name] = nil
                    else
                        selected[lib.name] = true
                    end
                end
            end
        elseif key == keys.enter then
            if selectedCount > 0 or deleteCount > 0 then
                break
            end
        elseif key == keys.q then
            sleep()
            return nil, nil
        end
    end
    
    -- Convert selected table to array
    local selectedList = {}
    for name in pairs(selected) do
        table.insert(selectedList, name)
    end
    table.sort(selectedList)
    
    -- Keep original selection for tracking which were user-selected vs auto-added deps
    local originalSelection = {}
    for _, name in ipairs(selectedList) do
        table.insert(originalSelection, name)
    end
    
    -- Resolve dependencies (add any missing dependencies)
    selectedList = resolveDependencies(selectedList)
    table.sort(selectedList)
    
    -- Build delete list (installed but not selected)
    local deleteList = {}
    for _, lib in ipairs(LIBRARIES) do
        local existing = findExistingLibrary(lib.name)
        if existing and not selected[lib.name] then
            table.insert(deleteList, lib.name)
        end
    end
    table.sort(deleteList)
    
    return selectedList, deleteList, originalSelection
end

---Get installation directory from user
---@return string The installation directory
local function getInstallDir()
    clearScreen()
    
    -- Determine default directory
    local defaultDir = "/lib"
    if fs.exists("disk") and fs.isDir("disk") then
        defaultDir = "disk/lib"
    end
    
    -- Compact header
    term.setTextColor(colors.yellow)
    print("Installation Directory")
    term.setTextColor(colors.lightGray)
    print("Where should libraries be installed?")
    print("(Leave empty for default: " .. defaultDir .. ")")
    term.setTextColor(colors.white)
    print()
    
    write("> ")
    
    local dir = read()
    if dir == "" then
        dir = defaultDir
    else
        -- Remove trailing slash if present
        if dir:sub(-1) == "/" then
            dir = dir:sub(1, -2)
        end
    end
    
    return dir
end

---Choose installation action
---@return string|nil "install" or "generate" or nil for cancel
local function chooseAction()
    local cursor = 1
    local options = {
        {key = "install", label = "Install/Uninstall Now", desc = "Download and install or uninstall libraries immediately"},
        {key = "generate", label = "Generate Installer", desc = "Create installer.lua script for later use"}
    }
    
    while true do
        clearScreen()
        
        term.setTextColor(colors.yellow)
        print("Choose Action")
        term.setTextColor(colors.lightGray)
        print("Up/Down: Move | Enter: Select | Q: Cancel")
        term.setTextColor(colors.white)
        print()
        
        for i, opt in ipairs(options) do
            if i == cursor then
                term.setTextColor(colors.black)
                term.setBackgroundColor(colors.white)
            else
                term.setTextColor(colors.white)
                term.setBackgroundColor(colors.black)
            end
            
            local w = term.getSize()
            local line = opt.label
            line = line .. string.rep(" ", w - #line)
            print(line)
            
            term.setTextColor(colors.lightGray)
            term.setBackgroundColor(colors.black)
            print("  " .. opt.desc)
            term.setTextColor(colors.white)
        end
        
        term.setBackgroundColor(colors.black)
        
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            cursor = math.max(1, cursor - 1)
        elseif key == keys.down then
            cursor = math.min(#options, cursor + 1)
        elseif key == keys.enter then
            return options[cursor].key
        elseif key == keys.q then
            sleep()
            return nil
        end
    end
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
    local version = content:match('VERSION%s*=%s*["\']([%d%.]+)["\']')
    if version then
        return version
    end
    
    -- Look for @version tag in comments
    version = content:match('%-%-%-@version%s+([%d%.]+)')
    return version
end

---Check which libraries need updates
---@param libraries table List of library names
---@return table Map of library name to {exists: bool, path: string, version: string}
local function checkLibraryStatus(libraries)
    local status = {}
    
    for _, lib in ipairs(libraries) do
        local existing = findExistingLibrary(lib)
        if existing then
            local version = parseVersion(existing)
            status[lib] = {
                exists = true,
                path = existing,
                version = version or "ersion unknown"
            }
        else
            status[lib] = {
                exists = false,
                path = nil,
                version = nil
            }
        end
    end
    
    return status
end

---Install libraries immediately
---@param libraries table List of library names
---@param installDir string Installation directory
---@param skipClear boolean? Skip clearing screen (for when deletions happened first)
---@param originalSelection table? Original selection before dependency resolution
local function installLibraries(libraries, installDir, skipClear, originalSelection)
    -- Check existing libraries
    local status = checkLibraryStatus(libraries)
    
    if not skipClear then
        clearScreen()
    end
    
    term.setTextColor(colors.yellow)
    print("Installing/Updating Libraries")
    term.setTextColor(colors.white)
    print()
    
    -- Show dependencies that were automatically added
    if originalSelection then
        local addedDeps = {}
        local origSet = {}
        for _, name in ipairs(originalSelection) do
            origSet[name] = true
        end
        for _, name in ipairs(libraries) do
            if not origSet[name] then
                table.insert(addedDeps, name)
            end
        end
        if #addedDeps > 0 then
            term.setTextColor(colors.cyan)
            print("Auto-adding dependencies: " .. table.concat(addedDeps, ", "))
            term.setTextColor(colors.white)
            print()
        end
    end
    
    local success = 0
    local failed = 0
    
    for _, lib in ipairs(libraries) do
        local url = GITHUB_RAW_BASE .. lib .. ".lua"
        local info = status[lib]
        
        -- Determine target path
        local filepath
        if info.exists then
            filepath = info.path -- Update in place
            term.setTextColor(colors.yellow)
            write("Updating " .. lib .. "... ")
        else
            filepath = installDir .. "/" .. lib .. ".lua"
            term.setTextColor(colors.lightGray)
            write("Installing " .. lib .. "... ")
        end
        
        if downloadFile(url, filepath) then
            term.setTextColor(colors.green)
            print("OK")
            success = success + 1
        else
            term.setTextColor(colors.red)
            print("FAILED")
            failed = failed + 1
        end
    end
    
    term.setTextColor(colors.white)
    print()
    
    if failed == 0 then
        term.setTextColor(colors.green)
        print("All libraries processed successfully!")
    else
        term.setTextColor(colors.yellow)
        print(string.format("Complete: %d succeeded, %d failed", success, failed))
    end
    
    term.setTextColor(colors.white)
end

---Uninstall libraries
---@param libraries table List of library names to uninstall
local function deleteLibraries(libraries)
    if #libraries == 0 then
        return
    end
    
    print()
    term.setTextColor(colors.red)
    print("Uninstalling Libraries")
    term.setTextColor(colors.white)
    print()
    
    local success = 0
    local failed = 0
    
    for _, lib in ipairs(libraries) do
        local path = findExistingLibrary(lib)
        if path then
            term.setTextColor(colors.red)
            write("Uninstalling " .. lib .. " from " .. path .. "... ")
            
            local ok, err = pcall(function()
                fs.delete(path)
            end)
            
            if ok then
                term.setTextColor(colors.green)
                print("OK")
                success = success + 1
            else
                term.setTextColor(colors.red)
                print("FAILED: " .. tostring(err))
                failed = failed + 1
            end
        else
            term.setTextColor(colors.yellow)
            print("Skipping " .. lib .. " (not found)")
        end
    end
    
    term.setTextColor(colors.white)
    print()
    
    if failed == 0 and success > 0 then
        term.setTextColor(colors.green)
        print("All libraries uninstalled successfully!")
    elseif success > 0 then
        term.setTextColor(colors.yellow)
        print(string.format("Uninstall complete: %d succeeded, %d failed", success, failed))
    end
    
    term.setTextColor(colors.white)
end

---Generate installer script content
---@param libraries table List of library names
---@param installDir string Installation directory
---@return string The installer script content
local function generateInstaller(libraries, installDir)
    local script = [[--- Auto-generated installer for CC-Misc utilities
--- Generated by installer.lua
---
--- This script will download and install the following libraries:
]]

    for _, lib in ipairs(libraries) do
        script = script .. string.format("---   - %s\n", lib)
    end
    
    script = script .. [[---
--- Usage: lua installer.lua

local GITHUB_RAW_BASE = "https://raw.githubusercontent.com/Twijn/cc-misc/main/util/"
local INSTALL_DIR = "]] .. installDir .. [["

local LIBRARIES = {
]]

    for _, lib in ipairs(libraries) do
        script = script .. string.format('    "%s",\n', lib)
    end
    
    script = script .. [[}

local function printColored(text, color)
    term.setTextColor(color)
    print(text)
    term.setTextColor(colors.white)
end

local function downloadFile(url, filename)
    printColored("Downloading " .. filename .. "...", colors.yellow)
    
    local response = http.get(url)
    if not response then
        printColored("Failed to download " .. filename, colors.red)
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    -- Create directory if needed
    if INSTALL_DIR ~= "." then
        fs.makeDir(INSTALL_DIR)
    end
    
    local filepath = INSTALL_DIR == "." and filename or (INSTALL_DIR .. "/" .. filename)
    local file = fs.open(filepath, "w")
    if not file then
        printColored("Failed to write " .. filename, colors.red)
        return false
    end
    
    file.write(content)
    file.close()
    
    printColored("✓ Installed " .. filename, colors.green)
    return true
end

-- Main installation process
print("CC-Misc Utilities Installer")
print("============================\n")

local success = 0
local failed = 0

for _, lib in ipairs(LIBRARIES) do
    local url = GITHUB_RAW_BASE .. lib .. ".lua"
    local filename = lib .. ".lua"
    
    if downloadFile(url, filename) then
        success = success + 1
    else
        failed = failed + 1
    end
end

print()
print("============================")
printColored(string.format("Installation complete: %d succeeded, %d failed", success, failed), 
    failed == 0 and colors.green or colors.yellow)

if failed == 0 then
    print("\nAll libraries installed successfully!")
    if INSTALL_DIR ~= "." then
        print("Libraries installed to: " .. INSTALL_DIR)
    end
else
    print("\nSome libraries failed to install. Check your internet connection.")
end
]]

    return script
end

---Main function
---@param ... string Library names to pre-select
local function main(...)
    -- Check if we're in a ComputerCraft environment
    if not term or not colors then
        print("This script must be run in ComputerCraft!")
        return
    end
    
    -- Load libraries from API or fallback
    clearScreen()
    if not loadLibrariesFromAPI() then
        printColored("Warning: Could not load from API, using offline library list", colors.yellow)
        sleep(1.5)
        loadFallbackLibraries()
    else
        printColored("Successfully loaded " .. #LIBRARIES .. " libraries from API", colors.green)
        sleep(1)
    end
    
    -- Parse command-line arguments for pre-selection
    local args = {...}
    local preselected = {}
    local validLibs = {}
    for _, lib in ipairs(LIBRARIES) do
        validLibs[lib.name] = true
    end
    
    -- Validate and collect pre-selected libraries
    for _, arg in ipairs(args) do
        if validLibs[arg] then
            table.insert(preselected, arg)
        else
            -- Show warning for invalid library names
            printColored("Warning: Unknown library '" .. arg .. "' - ignoring", colors.yellow)
            sleep(1)
        end
    end
    
    -- Select libraries (with optional pre-selection)
    local selected, toDelete, originalSelection = selectLibraries(#preselected > 0 and preselected or nil)
    if not selected then
        clearScreen()
        printColored("Cancelled.", colors.yellow)
        return
    end
    
    -- Choose action
    local action = chooseAction()
    if not action then
        clearScreen()
        printColored("Cancelled.", colors.yellow)
        return
    end
    
    -- Get installation directory
    local installDir = getInstallDir()
    
    if action == "install" then
        -- Clear screen before operations
        clearScreen()
        
        -- Uninstall libraries first (unchecked existing libraries)
        if toDelete and #toDelete > 0 then
            deleteLibraries(toDelete)
        end
        
        -- Then install/update selected libraries
        if #selected > 0 then
            installLibraries(selected, installDir, toDelete and #toDelete > 0, originalSelection)
        end
        
        -- Final summary
        if (not toDelete or #toDelete == 0) and #selected == 0 then
            clearScreen()
            printColored("No changes to make.", colors.yellow)
        end
    else
        -- Generate installer script
        clearScreen()
        
        term.setTextColor(colors.yellow)
        print("Generating Installer")
        term.setTextColor(colors.white)
        print()
        
        term.setTextColor(colors.lightGray)
        print("Selected: " .. #selected .. " libraries")
        print("Directory: " .. installDir)
        term.setTextColor(colors.white)
        print()
        
        for _, lib in ipairs(selected) do
            term.setTextColor(colors.green)
            print("  * " .. lib)
        end
        
        term.setTextColor(colors.white)
        print()
        
        local installerContent = generateInstaller(selected, installDir)
        
        -- Save installer
        local file = fs.open("installer.lua", "w")
        if not file then
            term.setTextColor(colors.red)
            print("Failed to create installer.lua!")
            term.setTextColor(colors.white)
            return
        end
        
        file.write(installerContent)
        file.close()
        
        term.setTextColor(colors.green)
        print("Success!")
        term.setTextColor(colors.white)
        print()
        print("Run: lua installer.lua")
    end
end

-- Run the main function
main(...)
