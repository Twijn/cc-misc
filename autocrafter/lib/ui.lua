--- AutoCrafter UI Library
--- UI components for the server display.
---
---@version 1.0.0

local VERSION = "1.0.0"

local ui = {}

local termWidth, termHeight = term.getSize()

---Clear the screen and set colors
function ui.clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    termWidth, termHeight = term.getSize()
end

---Draw a header bar
---@param title string The title to display
---@param version? string Optional version string
function ui.header(title, version)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    
    local text = " " .. title
    if version then
        text = text .. " v" .. version
    end
    term.write(text)
    
    -- Right-align computer ID
    local idText = "ID:" .. os.getComputerID() .. " "
    term.setCursorPos(termWidth - #idText + 1, 1)
    term.write(idText)
    
    term.setBackgroundColor(colors.black)
end

---Draw a footer bar
---@param text string The text to display
function ui.footer(text)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(1, termHeight)
    term.clearLine()
    term.write(" " .. text)
    term.setBackgroundColor(colors.black)
end

---Draw a status line
---@param y number The Y position
---@param label string The label
---@param value string|number The value
---@param valueColor? number Optional color for value
function ui.statusLine(y, label, value, valueColor)
    term.setCursorPos(2, y)
    term.setTextColor(colors.lightGray)
    term.write(label .. ": ")
    term.setTextColor(valueColor or colors.white)
    term.write(tostring(value))
end

---Draw a progress bar
---@param y number The Y position
---@param label string The label
---@param current number Current value
---@param max number Maximum value
---@param barColor? number Optional bar color
function ui.progressBar(y, label, current, max, barColor)
    barColor = barColor or colors.lime
    local barWidth = termWidth - 4 - #label - 8
    
    term.setCursorPos(2, y)
    term.setTextColor(colors.lightGray)
    term.write(label .. " ")
    
    local fill = max > 0 and math.floor((current / max) * barWidth) or 0
    
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", barWidth))
    
    term.setCursorPos(2 + #label + 1, y)
    term.setBackgroundColor(barColor)
    term.write(string.rep(" ", fill))
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(string.format(" %d/%d", current, max))
end

---Draw a section header
---@param y number The Y position
---@param title string The section title
function ui.sectionHeader(y, title)
    term.setCursorPos(2, y)
    term.setTextColor(colors.yellow)
    term.write("-- " .. title .. " ")
    term.setTextColor(colors.gray)
    local remaining = termWidth - 5 - #title
    if remaining > 0 then
        term.write(string.rep("-", remaining))
    end
end

---Draw a list item
---@param y number The Y position
---@param text string The item text
---@param status? string Optional status indicator
---@param statusColor? number Optional status color
function ui.listItem(y, text, status, statusColor)
    term.setCursorPos(2, y)
    term.setTextColor(colors.white)
    
    local maxTextWidth = termWidth - 4
    if status then
        maxTextWidth = maxTextWidth - #status - 2
    end
    
    if #text > maxTextWidth then
        text = text:sub(1, maxTextWidth - 3) .. "..."
    end
    
    term.write(text)
    
    if status then
        term.setCursorPos(termWidth - #status - 1, y)
        term.setTextColor(statusColor or colors.gray)
        term.write(status)
    end
end

---Draw a table header
---@param y number The Y position
---@param columns table Array of {name, width}
function ui.tableHeader(y, columns)
    term.setCursorPos(2, y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    
    local x = 2
    for _, col in ipairs(columns) do
        term.setCursorPos(x, y)
        local text = col.name
        if #text > col.width then
            text = text:sub(1, col.width - 1) .. "."
        end
        term.write(text .. string.rep(" ", col.width - #text))
        x = x + col.width + 1
    end
    
    term.write(string.rep(" ", termWidth - x + 1))
    term.setBackgroundColor(colors.black)
end

---Draw a table row
---@param y number The Y position
---@param columns table Column definitions {name, width}
---@param values table Values for each column
---@param colors? table Optional colors for each column
function ui.tableRow(y, columns, values, rowColors)
    term.setCursorPos(2, y)
    
    local x = 2
    for i, col in ipairs(columns) do
        term.setCursorPos(x, y)
        term.setTextColor(rowColors and rowColors[i] or colors.white)
        
        local value = tostring(values[i] or "")
        if #value > col.width then
            value = value:sub(1, col.width - 1) .. "."
        end
        term.write(value .. string.rep(" ", col.width - #value))
        x = x + col.width + 1
    end
end

---Show a message box
---@param title string The title
---@param message string The message
---@param wait? boolean Wait for key press
function ui.messageBox(title, message, wait)
    local boxWidth = math.max(#title + 4, #message + 4, 20)
    local boxHeight = 5
    local startX = math.floor((termWidth - boxWidth) / 2)
    local startY = math.floor((termHeight - boxHeight) / 2)
    
    -- Draw box
    term.setBackgroundColor(colors.gray)
    for y = startY, startY + boxHeight - 1 do
        term.setCursorPos(startX, y)
        term.write(string.rep(" ", boxWidth))
    end
    
    -- Title
    term.setBackgroundColor(colors.blue)
    term.setCursorPos(startX, startY)
    term.write(string.rep(" ", boxWidth))
    term.setCursorPos(startX + 1, startY)
    term.write(title)
    
    -- Message
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(startX + 2, startY + 2)
    term.write(message)
    
    if wait then
        term.setCursorPos(startX + 2, startY + 4)
        term.setTextColor(colors.lightGray)
        term.write("Press any key...")
        os.pullEvent("key")
    end
    
    term.setBackgroundColor(colors.black)
end

---Show an input dialog
---@param prompt string The prompt text
---@param default? string Default value
---@return string|nil input The input or nil if cancelled
function ui.input(prompt, default)
    local y = termHeight - 2
    
    term.setCursorPos(2, y)
    term.setBackgroundColor(colors.gray)
    term.clearLine()
    term.setTextColor(colors.white)
    term.write(" " .. prompt .. ": ")
    
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    
    local inputWidth = termWidth - #prompt - 6
    term.write(string.rep(" ", inputWidth))
    term.setCursorPos(#prompt + 5, y)
    
    local input = read(nil, nil, nil, default)
    
    term.setBackgroundColor(colors.black)
    
    return input
end

---Get screen dimensions
---@return number width Screen width
---@return number height Screen height
function ui.getSize()
    return termWidth, termHeight
end

---Update screen dimensions
function ui.updateSize()
    termWidth, termHeight = term.getSize()
end

ui.VERSION = VERSION

return ui
