--- AutoCrafter Menu Library ---
--- Reusable arrow-key navigation menu with scrolling and filtering.
--- Modeled after signshop's menu system for consistent UX.
---
---@version 1.0.0

local menu = {}

-- Current filter state (persisted while navigating menus)
local currentFilter = ""

--- Get the current filter text
---@return string currentFilter The current filter text
function menu.getCurrentFilter()
    return currentFilter
end

--- Set the current filter text
---@param filter string The new filter text
function menu.setCurrentFilter(filter)
    currentFilter = filter
end

--- Clear the current filter
function menu.clearFilter()
    currentFilter = ""
end

--- Display a simple menu with arrow key navigation and scrolling
---@param title string Menu title
---@param options table Array of {label, action} pairs, can include {separator=true, label=...}
---@param filterable? boolean Whether to enable filter mode with / or F key
---@param filterFn? function Function to filter options: fn(option, filterText) -> boolean
---@return string|nil action The selected action or nil if cancelled
function menu.show(title, options, filterable, filterFn)
    local selected = 1
    local scroll = 0
    local filterText = filterable and currentFilter or ""
    local isFiltering = false
    
    -- Apply filter to options
    local function getFilteredOptions()
        if not filterable or filterText == "" then
            return options
        end
        
        local filtered = {}
        local lowerFilter = filterText:lower()
        
        for _, opt in ipairs(options) do
            if opt.separator then
                -- Keep separators
            else
                local include = false
                if filterFn then
                    include = filterFn(opt, lowerFilter)
                else
                    -- Default: match label
                    include = opt.label and opt.label:lower():find(lowerFilter, 1, true)
                end
                if include then
                    table.insert(filtered, opt)
                end
            end
        end
        
        return filtered
    end
    
    -- Find first non-separator option
    local function findFirstOption(opts)
        for i, opt in ipairs(opts) do
            if not opt.separator then
                return i
            end
        end
        return 1
    end
    
    local filteredOptions = getFilteredOptions()
    selected = findFirstOption(filteredOptions)
    
    while true do
        filteredOptions = getFilteredOptions()
        
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3  -- title + separator + blank line
        local footerHeight = filterable and 3 or 2  -- help text + filter line if filterable
        local visibleHeight = h - headerHeight - footerHeight
        
        -- Draw title
        term.setTextColor(colors.yellow)
        term.setCursorPos(math.floor((w - #title) / 2), 1)
        print(title)
        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        
        -- Show filter status if active
        if filterable and filterText ~= "" then
            term.setTextColor(colors.lightBlue)
            local filterInfo = string.format("Filter: %s (Showing %d of %d)", 
                filterText, #filteredOptions, #options)
            print(filterInfo)
        else
            print()
        end
        
        -- Calculate which items to show (flattened view for scrolling)
        local displayLines = {}
        for i, opt in ipairs(filteredOptions) do
            if opt.separator then
                if opt.label ~= "" then
                    table.insert(displayLines, { type = "separator", label = opt.label, index = i })
                else
                    table.insert(displayLines, { type = "blank", index = i })
                end
            else
                table.insert(displayLines, { type = "option", label = opt.label, index = i, action = opt.action })
            end
        end
        
        -- Find which display line corresponds to selected option
        local selectedDisplayLine = 1
        for i, line in ipairs(displayLines) do
            if line.index == selected then
                selectedDisplayLine = i
                break
            end
        end
        
        -- Adjust scroll to keep selection visible
        if selectedDisplayLine <= scroll then
            scroll = selectedDisplayLine - 1
        elseif selectedDisplayLine > scroll + visibleHeight then
            scroll = selectedDisplayLine - visibleHeight
        end
        
        -- Draw visible items
        for i = scroll + 1, math.min(#displayLines, scroll + visibleHeight) do
            local line = displayLines[i]
            
            if line.type == "blank" then
                print()
            elseif line.type == "separator" then
                term.setTextColor(colors.gray)
                print(line.label)
            else
                if line.index == selected then
                    term.setTextColor(colors.black)
                    term.setBackgroundColor(colors.white)
                    local displayLabel = line.label
                    if #displayLabel > w - 3 then
                        displayLabel = displayLabel:sub(1, w - 6) .. "..."
                    end
                    write("> " .. displayLabel .. " ")
                    term.setBackgroundColor(colors.black)
                    print()
                else
                    term.setTextColor(colors.white)
                    local displayLabel = line.label
                    if #displayLabel > w - 3 then
                        displayLabel = displayLabel:sub(1, w - 6) .. "..."
                    end
                    print("  " .. displayLabel)
                end
            end
        end
        
        -- Draw scroll indicators if needed
        term.setTextColor(colors.gray)
        if scroll > 0 then
            term.setCursorPos(w, headerHeight + 1)
            write("^")
        end
        if scroll + visibleHeight < #displayLines then
            term.setCursorPos(w, h - footerHeight)
            write("v")
        end
        
        -- Draw help and filter input
        term.setCursorPos(1, h - (filterable and 2 or 1))
        term.setTextColor(colors.gray)
        if filterable then
            print("Up/Down: Navigate | Enter: Select | /,F: Filter | Esc: Clear | Q: Back")
            if isFiltering then
                term.setTextColor(colors.yellow)
                write("Filter: ")
                term.setTextColor(colors.white)
                write(filterText .. "_")
            end
        else
            print("Up/Down: Navigate | Enter: Select | Q: Back")
        end
        
        -- Handle input
        if isFiltering then
            local e, p1 = os.pullEvent()
            if e == "key" then
                if p1 == keys.enter or p1 == keys.escape then
                    isFiltering = false
                    if p1 == keys.escape then
                        filterText = ""
                        currentFilter = ""
                    end
                elseif p1 == keys.backspace then
                    filterText = filterText:sub(1, -2)
                    currentFilter = filterText
                    selected = findFirstOption(getFilteredOptions())
                    scroll = 0
                end
            elseif e == "char" then
                filterText = filterText .. p1
                currentFilter = filterText
                selected = findFirstOption(getFilteredOptions())
                scroll = 0
            end
        else
            local e, key = os.pullEvent("key")
            if key == keys.up then
                repeat
                    selected = selected - 1
                    if selected < 1 then selected = #filteredOptions end
                until not filteredOptions[selected] or not filteredOptions[selected].separator
            elseif key == keys.down then
                repeat
                    selected = selected + 1
                    if selected > #filteredOptions then selected = 1 end
                until not filteredOptions[selected] or not filteredOptions[selected].separator
            elseif key == keys.pageUp then
                for _ = 1, visibleHeight - 1 do
                    repeat
                        selected = selected - 1
                        if selected < 1 then selected = #filteredOptions end
                    until not filteredOptions[selected] or not filteredOptions[selected].separator
                end
            elseif key == keys.pageDown then
                for _ = 1, visibleHeight - 1 do
                    repeat
                        selected = selected + 1
                        if selected > #filteredOptions then selected = 1 end
                    until not filteredOptions[selected] or not filteredOptions[selected].separator
                end
            elseif key == keys.home then
                selected = findFirstOption(filteredOptions)
            elseif key == keys["end"] then
                selected = #filteredOptions
                while filteredOptions[selected] and filteredOptions[selected].separator do
                    selected = selected - 1
                end
            elseif key == keys.enter then
                if filteredOptions[selected] then
                    return filteredOptions[selected].action
                end
            elseif key == keys.q then
                return nil
            elseif filterable and (key == keys.slash or key == keys.f) then
                isFiltering = true
                -- Consume the pending char event to prevent the trigger key from being added to filter
                os.pullEvent("char")
            elseif filterable and key == keys.escape then
                filterText = ""
                currentFilter = ""
                selected = findFirstOption(getFilteredOptions())
                scroll = 0
            end
        end
    end
end

return menu
