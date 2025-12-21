--- Pager utility for ComputerCraft that displays long output with pagination
--- Similar to 'less' or 'more' on Unix systems. Allows scrolling through
--- content that exceeds the terminal height.
---
--- Features: Page-by-page navigation, line-by-line scrolling, search/skip to end,
--- dynamic terminal size detection, works with both strings and tables of lines.
---
---@usage
---local pager = require("pager")
---
----- Display a table of lines
---local lines = {"Line 1", "Line 2", ...}
---pager.display(lines, "My Title")
---
----- Use the pager collector to build output
---local p = pager.new("Results")
---p:print("Some text")
---p:write("partial ")
---p:print("line")
---p:setColor(colors.lime)
---p:print("Green text")
---p:show()
---
---@version 1.0.0
-- @module pager

local VERSION = "1.0.0"
local pager = { _v = VERSION }

---@class PagerCollector
---@field lines table[] Array of line data with color information
---@field title string Optional title for the pager
---@field currentLine table Current line being built
---@field currentColor number Current text color
local PagerCollector = {}
PagerCollector.__index = PagerCollector

---Create a new pager collector for building pageable output
---@param title? string Optional title to show at the top
---@return PagerCollector
function pager.new(title)
    local self = setmetatable({}, PagerCollector)
    self.lines = {}
    self.title = title
    self.currentLine = {}
    self.currentColor = colors.white
    return self
end

---Set the current text color for subsequent writes
---@param color number The color constant (e.g., colors.red)
function PagerCollector:setColor(color)
    self.currentColor = color
end

---Write text without a newline (can be called multiple times per line)
---@param text string The text to write
function PagerCollector:write(text)
    if text == nil then return end
    table.insert(self.currentLine, {
        text = tostring(text),
        color = self.currentColor
    })
end

---Print text with a newline (completes the current line)
---@param text? string Optional text to print before the newline
function PagerCollector:print(text)
    if text ~= nil then
        self:write(tostring(text))
    end
    table.insert(self.lines, self.currentLine)
    self.currentLine = {}
end

---Add a blank line
function PagerCollector:newline()
    table.insert(self.lines, self.currentLine)
    self.currentLine = {}
end

---Get the number of lines collected
---@return number
function PagerCollector:lineCount()
    local count = #self.lines
    if #self.currentLine > 0 then
        count = count + 1
    end
    return count
end

---Check if paging is needed based on terminal height
---@return boolean
function PagerCollector:needsPaging()
    local _, h = term.getSize()
    -- Reserve 2 lines for status bar and prompt
    return self:lineCount() > (h - 2)
end

---Render a single collected line to the terminal
---@param lineData table The line data with color segments
local function renderLine(lineData)
    for _, segment in ipairs(lineData) do
        term.setTextColor(segment.color)
        write(segment.text)
    end
    term.setTextColor(colors.white)
end

---Display the collected content with pagination if needed
---If content fits on screen, just prints it directly
function PagerCollector:show()
    -- Flush any remaining content in currentLine
    if #self.currentLine > 0 then
        table.insert(self.lines, self.currentLine)
        self.currentLine = {}
    end
    
    local w, h = term.getSize()
    local totalLines = #self.lines
    
    -- If it fits on screen, just print directly
    if totalLines <= (h - 1) then
        if self.title then
            term.setTextColor(colors.lightBlue)
            print(self.title)
            term.setTextColor(colors.white)
        end
        for _, lineData in ipairs(self.lines) do
            renderLine(lineData)
            print()
        end
        return
    end
    
    -- Pagination mode
    local scrollPos = 1
    -- Reserve lines for: title (1) + status bar (1) = 2, or just status bar (1) if no title
    local headerLines = self.title and 1 or 0
    local viewHeight = h - headerLines - 1  -- -1 for status bar at bottom
    
    local function draw()
        term.clear()
        term.setCursorPos(1, 1)
        
        -- Draw title if present
        if self.title then
            term.setTextColor(colors.lightBlue)
            print(self.title)
            term.setTextColor(colors.white)
        end
        
        -- Draw visible lines
        local endPos = math.min(scrollPos + viewHeight - 1, totalLines)
        for i = scrollPos, endPos do
            local lineData = self.lines[i]
            if lineData then
                renderLine(lineData)
            end
            print()
        end
        
        -- Draw status bar at bottom
        term.setCursorPos(1, h)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.clearLine()
        
        local progress = math.floor((scrollPos / math.max(1, totalLines - viewHeight + 1)) * 100)
        if scrollPos >= totalLines - viewHeight + 1 then
            progress = 100
        end
        local statusText = string.format(" Lines %d-%d of %d (%d%%) | ↑↓:scroll PgUp/PgDn:page q:quit",
            scrollPos, endPos, totalLines, progress)
        write(statusText:sub(1, w))
        
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end
    
    draw()
    
    while true do
        local event, key = os.pullEvent("key")
        
        if key == keys.q or key == keys.enter then
            -- Quit pager
            term.setCursorPos(1, h)
            term.clearLine()
            break
            
        elseif key == keys.up or key == keys.k then
            -- Scroll up one line
            if scrollPos > 1 then
                scrollPos = scrollPos - 1
                draw()
            end
            
        elseif key == keys.down or key == keys.j then
            -- Scroll down one line
            if scrollPos < totalLines - viewHeight + 1 then
                scrollPos = scrollPos + 1
                draw()
            end
            
        elseif key == keys.pageUp then
            -- Page up
            scrollPos = math.max(1, scrollPos - viewHeight)
            draw()
            
        elseif key == keys.pageDown or key == keys.space then
            -- Page down
            scrollPos = math.min(totalLines - viewHeight + 1, scrollPos + viewHeight)
            scrollPos = math.max(1, scrollPos)
            draw()
            
        elseif key == keys.home or key == keys.g then
            -- Go to beginning
            scrollPos = 1
            draw()
            
        elseif key == keys["end"] then
            -- Go to end
            scrollPos = math.max(1, totalLines - viewHeight + 1)
            draw()
        end
    end
end

---Display a table of strings or pre-formatted lines with pagination
---This is a simpler interface for when you just have plain strings
---@param lines string[] Array of strings to display
---@param title? string Optional title
function pager.display(lines, title)
    local p = pager.new(title)
    for _, line in ipairs(lines) do
        p:print(line)
    end
    p:show()
end

---Create a pager that acts like term for easy integration
---Returns an object with print, write, setTextColor that collects output
---@param title? string Optional title for the pager
---@return table Pager object with terminal-like interface
function pager.create(title)
    local p = pager.new(title)
    return {
        print = function(...) 
            local args = {...}
            if #args == 0 then
                p:print("")
            else
                p:print(table.concat(args, "\t"))
            end
        end,
        write = function(text) p:write(text) end,
        setTextColor = function(color) p:setColor(color) end,
        show = function() p:show() end,
        lineCount = function() return p:lineCount() end,
        needsPaging = function() return p:needsPaging() end,
        -- Get the underlying collector if needed
        collector = p,
    }
end

return pager
