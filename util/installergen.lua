--- Installer Generator for CC-Misc Utilities
--- Interactive tool to generate custom installer scripts for ComputerCraft libraries
---
--- This tool provides a user-friendly interface to select multiple libraries from the cc-misc
--- repository and generates a single installer.lua file that will download all selected
--- libraries to your ComputerCraft computer.
---
---@usage
---wget https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installergen.lua installergen.lua
---installergen.lua
---
-- @module installergen

local VERSION = "1.3.1"
local GITHUB_RAW_BASE = "https://raw.githubusercontent.com/Twijn/cc-misc/main/util/"

-- Available libraries with descriptions
local LIBRARIES = {
    {name = "cmd", description = "Command-line interface with REPL, autocompletion, and history"},
    {name = "formui", description = "Form-based UI builder for creating interactive forms"},
    {name = "log", description = "Logging utility with file and term output support"},
    {name = "persist", description = "Data persistence utility for saving/loading Lua tables"},
    {name = "s", description = "String manipulation utilities and extensions"},
    {name = "tables", description = "Table manipulation utilities (deep copy, merge, etc.)"},
    {name = "timeutil", description = "Time formatting and manipulation utilities"},
    {name = "shopk", description = "Kromer API client for shop integration"},
}

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

---Display library selection menu with scrolling support
---@return table|nil Selected library names
---@return table|nil Libraries to delete
local function selectLibraries()
    local selected = {}
    local cursor = 1
    local w, h = term.getSize()
    
    -- Pre-select existing libraries
    for _, lib in ipairs(LIBRARIES) do
        local existing = findExistingLibrary(lib.name)
        if existing then
            selected[lib.name] = true
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
        print("Up/Down: Move | Space: Toggle | D: Delete | Enter: Continue | Q: Quit")
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
            
            -- Determine marker
            local marker
            if willDelete then
                marker = "[D]" -- Marked for deletion
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
                    term.setTextColor(colors.red) -- Marked for deletion
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
            statusText = statusText .. string.format(" | To Delete: %d", deleteCount)
        end
        write(statusText)
        term.setTextColor(colors.white)
        
        -- Handle input
        local event, key = os.pullEvent("key")
        
        if key == keys.up then
            cursor = math.max(1, cursor - 1)
        elseif key == keys.down then
            cursor = math.min(totalItems, cursor + 1)
        elseif key == keys.space or key == keys.d then
            local lib = LIBRARIES[cursor]
            if selected[lib.name] then
                selected[lib.name] = nil
            else
                selected[lib.name] = true
            end
        elseif key == keys.enter then
            if selectedCount > 0 or deleteCount > 0 then
                break
            end
        elseif key == keys.q then
            return nil, nil
        end
    end
    
    -- Convert selected table to array
    local selectedList = {}
    for name in pairs(selected) do
        table.insert(selectedList, name)
    end
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
    
    return selectedList, deleteList
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
        {key = "install", label = "Install Now", desc = "Download and install libraries immediately"},
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
local function installLibraries(libraries, installDir, skipClear)
    -- Check existing libraries
    local status = checkLibraryStatus(libraries)
    
    if not skipClear then
        clearScreen()
    end
    
    term.setTextColor(colors.yellow)
    print("Installing/Updating Libraries")
    term.setTextColor(colors.white)
    print()
    
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

---Delete libraries
---@param libraries table List of library names to delete
local function deleteLibraries(libraries)
    if #libraries == 0 then
        return
    end
    
    print()
    term.setTextColor(colors.red)
    print("Deleting Libraries")
    term.setTextColor(colors.white)
    print()
    
    local success = 0
    local failed = 0
    
    for _, lib in ipairs(libraries) do
        local path = findExistingLibrary(lib)
        if path then
            term.setTextColor(colors.red)
            write("Deleting " .. lib .. " from " .. path .. "... ")
            
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
        print("All libraries deleted successfully!")
    elseif success > 0 then
        term.setTextColor(colors.yellow)
        print(string.format("Delete complete: %d succeeded, %d failed", success, failed))
    end
    
    term.setTextColor(colors.white)
end

---Generate installer script content
---@param libraries table List of library names
---@param installDir string Installation directory
---@return string The installer script content
local function generateInstaller(libraries, installDir)
    local script = [[--- Auto-generated installer for CC-Misc utilities
--- Generated by installergen.lua
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
local function main()
    -- Check if we're in a ComputerCraft environment
    if not term or not colors then
        print("This script must be run in ComputerCraft!")
        return
    end
    
    -- Select libraries
    local selected, toDelete = selectLibraries()
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
        
        -- Delete libraries first
        if toDelete and #toDelete > 0 then
            deleteLibraries(toDelete)
        end
        
        -- Then install/update selected libraries
        if #selected > 0 then
            installLibraries(selected, installDir, toDelete and #toDelete > 0)
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
main()
