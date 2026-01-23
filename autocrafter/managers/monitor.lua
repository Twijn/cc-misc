--- AutoCrafter Monitor Manager
--- Manages display output to monitors.
---
---@version 2.2.0

local logger = require("lib.log")

local manager = {}

local monitor = nil
local refreshInterval = 5  -- Default, can be overridden
local lastRefresh = 0
local columnsPerRow = 2  -- Default: 2 columns for compact layout

---Find and attach to a monitor
---@param interval? number Optional refresh interval override
---@return boolean success Whether a monitor was found
function manager.init(interval)
    monitor = peripheral.find("monitor")
    
    if interval then
        refreshInterval = interval
    end
    
    if monitor then
        monitor.setTextScale(0.5)
        logger.info("Monitor manager initialized")
        return true
    else
        logger.info("No monitor found, display disabled")
        return false
    end
end

---Set number of columns per row for target display
---@param cols number Number of columns (1, 2, or 3)
function manager.setColumns(cols)
    if cols >= 1 and cols <= 3 then
        columnsPerRow = cols
        logger.info(string.format("Monitor columns set to %d", cols))
    end
end

---Get current column setting
---@return number columns Current number of columns
function manager.getColumns()
    return columnsPerRow
end

---Check if monitor is available
---@return boolean hasMonitor Whether a monitor is attached
function manager.hasMonitor()
    return monitor ~= nil
end

---Get the monitor peripheral
---@return table|nil monitor The monitor or nil
function manager.getMonitor()
    return monitor
end

---Clear the monitor
function manager.clear()
    if not monitor then return end
    
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

---Draw text centered on a line
---@param y number The line number
---@param text string The text to draw
---@param color? number Text color
function manager.centerText(y, text, color)
    if not monitor then return end
    
    local w, _ = monitor.getSize()
    local x = math.floor((w - #text) / 2) + 1
    
    monitor.setCursorPos(x, y)
    monitor.setTextColor(color or colors.white)
    monitor.write(text)
end

---Draw a header
---@param title string The title
function manager.header(title)
    if not monitor then return end
    
    local w, _ = monitor.getSize()
    
    monitor.setBackgroundColor(colors.blue)
    monitor.setCursorPos(1, 1)
    monitor.clearLine()
    manager.centerText(1, title, colors.white)
    monitor.setBackgroundColor(colors.black)
end

---Shorten item name for display
---@param item string The full item name
---@param maxLen number Maximum length
---@return string shortened The shortened name
local function shortenName(item, maxLen)
    local name = item:gsub("minecraft:", ""):gsub("_", " ")
    if #name > maxLen then
        name = name:sub(1, maxLen - 2) .. ".."
    end
    return name
end

---Format a number compactly (e.g., 1500 -> 1.5k)
---@param num number The number to format
---@return string formatted The formatted number
local function formatNum(num)
    if num >= 10000 then
        return string.format("%.0fk", num / 1000)
    elseif num >= 1000 then
        return string.format("%.1fk", num / 1000)
    else
        return tostring(num)
    end
end

---Draw a compact status bar
---@param x number X position
---@param y number Y position
---@param width number Bar width
---@param current number Current value
---@param target number Target value
local function drawMiniBar(x, y, width, current, target)
    if not monitor then return end
    local pct = math.min(1, current / math.max(1, target))
    local fill = math.floor(width * pct)
    
    monitor.setCursorPos(x, y)
    monitor.setBackgroundColor(colors.gray)
    monitor.write(string.rep(" ", width))
    monitor.setCursorPos(x, y)
    
    if pct >= 1 then
        monitor.setBackgroundColor(colors.lime)
    elseif pct >= 0.5 then
        monitor.setBackgroundColor(colors.yellow)
    else
        monitor.setBackgroundColor(colors.orange)
    end
    if fill > 0 then
        monitor.write(string.rep(" ", fill))
    end
    monitor.setBackgroundColor(colors.black)
end

---Draw a status display
---@param data table Status data to display
function manager.drawStatus(data)
    if not monitor then return end
    
    manager.clear()
    manager.header("AutoCrafter")
    
    local w, h = monitor.getSize()
    local y = 3
    
    -- Determine layout based on monitor width
    local isWide = w >= 40
    local isTall = h >= 30
    
    -- === COMPACT STATUS BAR (line 3) ===
    -- Storage: 85% | Q: 3/2 | C: 4/4
    monitor.setCursorPos(2, y)
    monitor.setTextColor(colors.lightGray)
    monitor.write("Sto:")
    
    if data.storage then
        local pct = data.storage.percentFull or 0
        if pct > 90 then
            monitor.setTextColor(colors.red)
        elseif pct > 70 then
            monitor.setTextColor(colors.orange)
        else
            monitor.setTextColor(colors.lime)
        end
        monitor.write(string.format("%d%%", pct))
    end
    
    monitor.setTextColor(colors.gray)
    monitor.write(" | ")
    
    monitor.setTextColor(colors.lightGray)
    monitor.write("Q:")
    if data.queue then
        local pending = data.queue.pending or 0
        local active = (data.queue.assigned or 0) + (data.queue.crafting or 0)
        if pending > 0 or active > 0 then
            monitor.setTextColor(colors.yellow)
        else
            monitor.setTextColor(colors.white)
        end
        monitor.write(string.format("%d", pending))
        monitor.setTextColor(colors.lime)
        monitor.write("/" .. string.format("%d", active))
    end
    
    monitor.setTextColor(colors.gray)
    monitor.write(" | ")
    
    monitor.setTextColor(colors.lightGray)
    monitor.write("C:")
    if data.crafters then
        local online = data.crafters.online or 0
        local total = data.crafters.total or 0
        if online == total and total > 0 then
            monitor.setTextColor(colors.lime)
        elseif online > 0 then
            monitor.setTextColor(colors.yellow)
        else
            monitor.setTextColor(colors.red)
        end
        monitor.write(string.format("%d/%d", online, total))
    end
    
    y = y + 1
    
    -- Storage bar (compact)
    if data.storage then
        local barWidth = math.min(w - 4, 20)
        local fillPct = (data.storage.percentFull or 0) / 100
        local fill = math.floor(barWidth * fillPct)
        
        monitor.setCursorPos(2, y)
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", barWidth))
        monitor.setCursorPos(2, y)
        
        if fillPct > 0.9 then
            monitor.setBackgroundColor(colors.red)
        elseif fillPct > 0.7 then
            monitor.setBackgroundColor(colors.orange)
        else
            monitor.setBackgroundColor(colors.lime)
        end
        if fill > 0 then
            monitor.write(string.rep(" ", fill))
        end
        monitor.setBackgroundColor(colors.black)
        
        -- Show item count next to bar
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(barWidth + 4, y)
        monitor.write(formatNum(data.storage.totalItems or 0) .. " items")
    end
    y = y + 2
    
    -- === TARGETS SECTION ===
    local craftTargets = data.targets or {}
    local smeltTargets = data.smeltTargets or {}
    local totalTargets = #craftTargets + #smeltTargets
    
    -- Calculate space for targets
    local targetStartY = y
    local availableLines = h - y - 3  -- Reserve space for fuel section
    
    -- Count satisfied vs needing work
    local craftSatisfied, craftNeeded = 0, 0
    local smeltSatisfied, smeltNeeded = 0, 0
    
    for _, t in ipairs(craftTargets) do
        if t.current >= t.target then
            craftSatisfied = craftSatisfied + 1
        else
            craftNeeded = craftNeeded + 1
        end
    end
    for _, t in ipairs(smeltTargets) do
        if t.current >= t.target then
            smeltSatisfied = smeltSatisfied + 1
        else
            smeltNeeded = smeltNeeded + 1
        end
    end
    
    -- Use flexible column layout (configurable via manager.setColumns)
    local colWidth = math.floor((w - 2) / columnsPerRow) - 1  -- -1 for spacing
    local nameWidth = math.max(8, colWidth - 12)  -- Reserve space for status + progress
    
    -- Helper to draw a single target entry
    local function drawTarget(target, colX, rowY, isSmelt)
        monitor.setCursorPos(colX, rowY)
        
        -- Status indicator
        if target.current >= target.target then
            monitor.setTextColor(colors.lime)
            monitor.write("+")
        else
            if isSmelt then
                monitor.setTextColor(colors.red)
                monitor.write("~")
            else
                monitor.setTextColor(colors.orange)
                monitor.write("*")
            end
        end
        
        -- Item name
        monitor.setTextColor(colors.white)
        local name = shortenName(target.item, nameWidth)
        monitor.write(name)
        
        -- Progress (right-aligned in column)
        local progX = colX + nameWidth + 1
        monitor.setCursorPos(progX, rowY)
        monitor.setTextColor(colors.lightGray)
        local prog = string.format("%s/%s", formatNum(target.current), formatNum(target.target))
        monitor.write(prog)
    end
    
    -- Combine all targets and sort by priority
    local allTargets = {}
    
    -- Add craft targets
    for _, t in ipairs(craftTargets) do
        local target = {
            item = t.item,
            current = t.current,
            target = t.target,
            isSmelt = false,
            needsWork = t.current < t.target,
            shortage = t.target - t.current
        }
        table.insert(allTargets, target)
    end
    
    -- Add smelt targets
    for _, t in ipairs(smeltTargets) do
        local target = {
            item = t.item,
            current = t.current,
            target = t.target,
            isSmelt = true,
            needsWork = t.current < t.target,
            shortage = t.target - t.current
        }
        table.insert(allTargets, target)
    end
    
    -- Sort: items needing work first, then by largest shortage
    table.sort(allTargets, function(a, b)
        if a.needsWork ~= b.needsWork then return a.needsWork end
        return a.shortage > b.shortage
    end)
    
    -- === TARGETS HEADER ===
    monitor.setTextColor(colors.yellow)
    monitor.setCursorPos(2, y)
    local totalSatisfied = craftSatisfied + smeltSatisfied
    local headerText = string.format("Targets [%d/%d]", totalSatisfied, totalTargets)
    monitor.write(headerText)
    
    -- Show crafting/smelting breakdown if both exist
    if #craftTargets > 0 and #smeltTargets > 0 then
        monitor.setTextColor(colors.gray)
        monitor.write(string.format(" (C:%d S:%d)", #craftTargets, #smeltTargets))
    end
    y = y + 1
    
    -- Calculate how many targets we can show
    local maxRows = h - y - 4  -- Reserve space for fuel section
    local maxTargets = maxRows * columnsPerRow
    
    -- Draw targets in 2-column layout
    local shown = 0
    local col = 0
    local rowY = y
    
    for i, target in ipairs(allTargets) do
        if shown >= maxTargets then
            -- Show "more" indicator
            local remaining = #allTargets - shown
            if remaining > 0 then
                monitor.setCursorPos(2, rowY)
                monitor.setTextColor(colors.gray)
                monitor.write(string.format("... +%d more", remaining))
                rowY = rowY + 1
            end
            break
        end
        
        -- Calculate column position
        local colX = 2 + (col * (colWidth + 1))
        
        -- Draw the target
        drawTarget(target, colX, rowY, target.isSmelt)
        
        shown = shown + 1
        col = col + 1
        
        -- Move to next row after filling all columns
        if col >= columnsPerRow then
            col = 0
            rowY = rowY + 1
        end
    end
    
    -- Move y position past the last row
    if col > 0 then
        rowY = rowY + 1
    end
    y = rowY + 1
    
    -- === FUEL SECTION (bottom) ===
    if data.fuelSummary and data.fuelSummary.fuelStock then
        y = h - 2
        
        monitor.setTextColor(colors.yellow)
        monitor.setCursorPos(2, y)
        monitor.write("Fuel: ")
        
        -- Total smelt capacity
        local cap = data.fuelSummary.totalSmeltCapacity or 0
        if cap >= 10000 then
            monitor.setTextColor(colors.lime)
            monitor.write(string.format("%.1fk", cap / 1000))
        elseif cap >= 1000 then
            monitor.setTextColor(colors.lime)
            monitor.write(string.format("%.1fk", cap / 1000))
        elseif cap > 0 then
            monitor.setTextColor(colors.orange)
            monitor.write(tostring(math.floor(cap)))
        else
            monitor.setTextColor(colors.red)
            monitor.write("0")
        end
        monitor.setTextColor(colors.lightGray)
        monitor.write(" smelts")
        
        -- Show top fuels compactly
        y = y + 1
        monitor.setCursorPos(2, y)
        local fuelParts = {}
        for i, fuel in ipairs(data.fuelSummary.fuelStock) do
            if i > 3 then break end
            if fuel.stock > 0 then
                local name = fuel.item:gsub("minecraft:", ""):gsub("_bucket", ""):gsub("_block", "B"):sub(1, 6)
                table.insert(fuelParts, name .. ":" .. formatNum(fuel.stock))
            end
        end
        monitor.setTextColor(colors.gray)
        monitor.write(table.concat(fuelParts, " "))
    end
    
    lastRefresh = os.clock()
end

---Check if refresh is needed
---@return boolean needsRefresh Whether display should be refreshed
function manager.needsRefresh()
    return (os.clock() - lastRefresh) >= refreshInterval
end

---Set refresh interval
---@param seconds number Interval in seconds
function manager.setRefreshInterval(seconds)
    refreshInterval = seconds
end

---Shutdown handler
function manager.beforeShutdown()
    if monitor then
        manager.clear()
        manager.centerText(1, "System Offline", colors.red)
    end
end

return manager
