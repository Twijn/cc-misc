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

---Print a header with color
---@param text string The header text
local function printHeader(text)
    term.setTextColor(colors.yellow)
    print("=" .. string.rep("=", #text) .. "=")
    print(" " .. text)
    print("=" .. string.rep("=", #text) .. "=")
    term.setTextColor(colors.white)
    print()
end

---Print colored text
---@param text string The text to print
---@param color number The color to use
local function printColored(text, color)
    term.setTextColor(color)
    print(text)
    term.setTextColor(colors.white)
end

---Display library selection menu with scrolling support
---@return table|nil Selected library names
local function selectLibraries()
    local selected = {}
    local scroll = 0
    local w, h = term.getSize()
    
    -- Calculate how many items can fit on screen
    -- Account for: header (4 lines) + instructions (3 lines) + input line (1)
    local headerLines = 4
    local footerLines = 4
    local linesPerItem = 2 -- Each library takes 2 lines (name + description)
    local maxVisibleItems = math.floor((h - headerLines - footerLines) / linesPerItem)
    
    while true do
        clearScreen()
        
        -- Header
        term.setTextColor(colors.yellow)
        local header = "CC-Misc Installer Generator"
        print(string.rep("=", w))
        print(header)
        print(string.rep("=", w))
        term.setTextColor(colors.white)
        
        -- Instructions
        term.setTextColor(colors.lightGray)
        print("Toggle: <number> | Continue: Enter | Quit: Q")
        term.setTextColor(colors.white)
        
        -- Calculate visible range
        local totalItems = #LIBRARIES
        local maxScroll = math.max(0, totalItems - maxVisibleItems)
        scroll = math.max(0, math.min(scroll, maxScroll))
        
        local startIdx = scroll + 1
        local endIdx = math.min(startIdx + maxVisibleItems - 1, totalItems)
        
        -- Show scroll indicator
        if scroll > 0 then
            term.setTextColor(colors.gray)
            print("↑ More above")
            term.setTextColor(colors.white)
        else
            print()
        end
        
        -- Display visible items
        for i = startIdx, endIdx do
            local lib = LIBRARIES[i]
            local marker = selected[lib.name] and "[X]" or "[ ]"
            local color = selected[lib.name] and colors.green or colors.white
            
            term.setTextColor(color)
            local name = string.format("%d. %s %s", i, marker, lib.name)
            -- Truncate if too long
            if #name > w then
                name = name:sub(1, w - 3) .. "..."
            end
            print(name)
            
            term.setTextColor(colors.lightGray)
            local desc = "   " .. lib.description
            if #desc > w then
                desc = desc:sub(1, w - 3) .. "..."
            end
            print(desc)
            term.setTextColor(colors.white)
        end
        
        -- Show scroll indicator
        if endIdx < totalItems then
            term.setTextColor(colors.gray)
            print("↓ More below")
            term.setTextColor(colors.white)
        end
        
        -- Move cursor to bottom for input
        local _, cy = term.getCursorPos()
        term.setCursorPos(1, h)
        term.setTextColor(colors.yellow)
        write("Input: ")
        term.setTextColor(colors.white)
        
        local input = read()
        
        if input == "" then
            -- Check if at least one library is selected
            local count = 0
            for _ in pairs(selected) do count = count + 1 end
            
            if count > 0 then
                break
            else
                term.setCursorPos(1, h)
                term.clearLine()
                term.setTextColor(colors.red)
                write("Please select at least one library! ")
                term.setTextColor(colors.white)
                sleep(2)
            end
        elseif input:lower() == "q" then
            return nil
        elseif input:lower() == "u" or input:lower() == "up" then
            scroll = math.max(0, scroll - 1)
        elseif input:lower() == "d" or input:lower() == "down" then
            scroll = math.min(maxScroll, scroll + 1)
        else
            local num = tonumber(input)
            if num and num >= 1 and num <= #LIBRARIES then
                local lib = LIBRARIES[num]
                selected[lib.name] = not selected[lib.name]
                
                -- Auto-scroll to show the selected item
                if num < startIdx then
                    scroll = num - 1
                elseif num > endIdx then
                    scroll = num - maxVisibleItems
                end
            end
        end
    end
    
    -- Convert selected table to array
    local selectedList = {}
    for name in pairs(selected) do
        table.insert(selectedList, name)
    end
    table.sort(selectedList)
    
    return selectedList
end

---Get installation directory from user
---@return string The installation directory
local function getInstallDir()
    clearScreen()
    local w, h = term.getSize()
    
    -- Compact header for small screens
    term.setTextColor(colors.yellow)
    print(string.rep("=", w))
    print("Installation Directory")
    print(string.rep("=", w))
    term.setTextColor(colors.white)
    print()
    
    term.setTextColor(colors.lightGray)
    print("Where should libraries be installed?")
    print("Leave empty for current directory")
    term.setTextColor(colors.white)
    print()
    
    term.setTextColor(colors.yellow)
    write("Directory: ")
    term.setTextColor(colors.white)
    
    local dir = read()
    if dir == "" or dir == "." then
        dir = "."
    else
        -- Remove trailing slash if present
        if dir:sub(-1) == "/" then
            dir = dir:sub(1, -2)
        end
    end
    
    return dir
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
    local selected = selectLibraries()
    if not selected then
        clearScreen()
        printColored("Installation cancelled.", colors.yellow)
        return
    end
    
    -- Get installation directory
    local installDir = getInstallDir()
    
    -- Generate installer
    clearScreen()
    local w, h = term.getSize()
    
    term.setTextColor(colors.yellow)
    print(string.rep("=", w))
    print("Generating Installer")
    print(string.rep("=", w))
    term.setTextColor(colors.white)
    print()
    
    term.setTextColor(colors.lightGray)
    print("Selected libraries:")
    term.setTextColor(colors.white)
    
    -- Show libraries in a compact format for small screens
    local maxToShow = h - 12
    local shown = 0
    for _, lib in ipairs(selected) do
        if shown < maxToShow then
            term.setTextColor(colors.green)
            print("  • " .. lib)
            shown = shown + 1
        end
    end
    
    if #selected > maxToShow then
        term.setTextColor(colors.gray)
        print("  ... and " .. (#selected - maxToShow) .. " more")
    end
    
    term.setTextColor(colors.white)
    print()
    term.setTextColor(colors.lightGray)
    print("Directory: " .. installDir)
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
    print("✓ Installer generated successfully!")
    term.setTextColor(colors.white)
    print()
    term.setTextColor(colors.lightGray)
    print("To install, run:")
    term.setTextColor(colors.yellow)
    print("  lua installer.lua")
    term.setTextColor(colors.white)
    print()
end

-- Run the main function
main()
