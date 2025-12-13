--- SignShop UI Helpers ---
--- Common UI utility functions for display formatting and user interaction.
---
---@version 1.0.0

local ui = {}

--- Format a Krist amount nicely
---@param amount number Amount in KRO
---@return string Formatted string
function ui.formatKRO(amount)
    return string.format("%.03f KRO", amount or 0)
end

--- Format a timestamp nicely
---@param timestamp number Unix timestamp in milliseconds
---@return string Formatted date/time
function ui.formatTime(timestamp)
    if not timestamp then return "Unknown" end
    -- Convert from epoch milliseconds to a relative time
    local now = os.epoch("utc")
    local diff = now - timestamp
    
    if diff < 60000 then
        return "just now"
    elseif diff < 3600000 then
        return math.floor(diff / 60000) .. "m ago"
    elseif diff < 86400000 then
        return math.floor(diff / 3600000) .. "h ago"
    else
        return math.floor(diff / 86400000) .. "d ago"
    end
end

--- Truncate a Krist address for display
---@param address string Full address
---@param maxLen? number Max length (default 12)
---@return string Truncated address
function ui.truncateAddress(address, maxLen)
    maxLen = maxLen or 12
    if not address then return "Unknown" end
    if #address <= maxLen then return address end
    return address:sub(1, maxLen - 2) .. ".."
end

--- Show a loading screen with a message
---@param message string The loading message
---@param subtext? string Optional sub-message
function ui.showLoading(message, subtext)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print(message)
    if subtext then
        term.setTextColor(colors.gray)
        print(subtext)
    end
end

--- Show a confirmation prompt
---@param title string The title/header
---@param message string|table The message (string or lines table)
---@param confirmKey? number The key code to confirm (default: keys.y)
---@return boolean confirmed True if user confirmed
function ui.showConfirm(title, message, confirmKey)
    confirmKey = confirmKey or keys.y
    
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print(title)
    term.setTextColor(colors.white)
    print()
    
    if type(message) == "table" then
        for _, line in ipairs(message) do
            print(line)
        end
    else
        print(message)
    end
    
    print()
    term.setTextColor(colors.gray)
    print("Press Y to confirm, any other key to cancel")
    
    local _, key = os.pullEvent("key")
    return key == confirmKey
end

--- Show a message and wait for keypress
---@param message string The message to show
---@param color? number Text color (default: colors.white)
function ui.showMessage(message, color)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(color or colors.white)
    print(message)
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

--- Show a success message and wait briefly
---@param message string The success message
---@param duration? number How long to wait (default: 0.5)
function ui.showSuccess(message, duration)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.green)
    print(message)
    sleep(duration or 0.5)
end

--- Show an error message and wait for keypress
---@param message string The error message
function ui.showError(message)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print(message)
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

--- Draw a scrollable content view
---@param title string The title
---@param contentLines table Array of line objects {text, color} or {label, value, labelColor, valueColor}
---@param actions? table Optional action handlers keyed by key code
---@param helpText? string Optional custom help text
function ui.showScrollableView(title, contentLines, actions, helpText)
    local scroll = 0
    actions = actions or {}
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3
        local footerHeight = 2
        local visibleHeight = h - headerHeight - footerHeight
        local totalLines = #contentLines
        
        -- Clamp scroll
        scroll = math.max(0, math.min(scroll, math.max(0, totalLines - visibleHeight)))
        
        -- Title
        term.setTextColor(colors.yellow)
        print("=== " .. title .. " ===")
        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        print()
        
        -- Draw visible content
        for i = scroll + 1, math.min(totalLines, scroll + visibleHeight) do
            local line = contentLines[i]
            if line.label then
                term.setTextColor(line.labelColor or colors.lightBlue)
                write(line.label)
                term.setTextColor(line.valueColor or colors.white)
                print(line.value or "")
            else
                term.setTextColor(line.color or colors.white)
                print(line.text or "")
            end
        end
        
        -- Draw scroll indicators
        term.setTextColor(colors.gray)
        if scroll > 0 then
            term.setCursorPos(w, headerHeight + 1)
            write("^")
        end
        if scroll + visibleHeight < totalLines then
            term.setCursorPos(w, h - footerHeight)
            write("v")
        end
        
        -- Footer
        term.setCursorPos(1, h - 1)
        term.setTextColor(colors.gray)
        print(helpText or "Up/Down: Scroll | Q: Back")
        
        local e, key = os.pullEvent("key")
        if key == keys.up then
            scroll = scroll - 1
        elseif key == keys.down then
            scroll = scroll + 1
        elseif key == keys.pageUp then
            scroll = scroll - (visibleHeight - 1)
        elseif key == keys.pageDown then
            scroll = scroll + (visibleHeight - 1)
        elseif key == keys.home then
            scroll = 0
        elseif key == keys["end"] then
            scroll = totalLines - visibleHeight
        elseif key == keys.q then
            return nil
        elseif actions[key] then
            local result = actions[key]()
            if result == "break" then
                return result
            elseif result == "refresh" then
                -- Continue loop to refresh display
            end
        end
    end
end

return ui
