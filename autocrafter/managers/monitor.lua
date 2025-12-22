--- AutoCrafter Monitor Manager
--- Manages display output to monitors.
---
---@version 2.0.0

local logger = require("lib.log")

local manager = {}

local monitor = nil
local refreshInterval = 5  -- Default, can be overridden
local lastRefresh = 0

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

---Draw a status display
---@param data table Status data to display
function manager.drawStatus(data)
    if not monitor then return end
    
    manager.clear()
    manager.header("AutoCrafter")
    
    local y = 3
    local w, h = monitor.getSize()
    
    -- Storage stats
    monitor.setTextColor(colors.yellow)
    monitor.setCursorPos(2, y)
    monitor.write("-- Storage --")
    y = y + 1
    
    if data.storage then
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(2, y)
        monitor.write("Items: ")
        monitor.setTextColor(colors.white)
        monitor.write(tostring(data.storage.totalItems or 0))
        y = y + 1
        
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(2, y)
        monitor.write("Slots: ")
        monitor.setTextColor(colors.white)
        monitor.write(string.format("%d/%d", data.storage.usedSlots or 0, data.storage.totalSlots or 0))
        y = y + 1
        
        -- Draw bar
        local barWidth = w - 4
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
        monitor.write(string.rep(" ", fill))
        monitor.setBackgroundColor(colors.black)
        y = y + 2
    end
    
    -- Queue stats
    monitor.setTextColor(colors.yellow)
    monitor.setCursorPos(2, y)
    monitor.write("-- Queue --")
    y = y + 1
    
    if data.queue then
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(2, y)
        monitor.write("Pending: ")
        monitor.setTextColor(colors.white)
        monitor.write(tostring(data.queue.pending or 0))
        y = y + 1
        
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(2, y)
        monitor.write("Active: ")
        monitor.setTextColor(colors.lime)
        monitor.write(tostring((data.queue.assigned or 0) + (data.queue.crafting or 0)))
        y = y + 2
    end
    
    -- Crafter stats
    monitor.setTextColor(colors.yellow)
    monitor.setCursorPos(2, y)
    monitor.write("-- Crafters --")
    y = y + 1
    
    if data.crafters then
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(2, y)
        monitor.write("Online: ")
        monitor.setTextColor(colors.lime)
        monitor.write(tostring(data.crafters.online or 0))
        monitor.setTextColor(colors.gray)
        monitor.write("/" .. tostring(data.crafters.total or 0))
        y = y + 1
        
        monitor.setTextColor(colors.lightGray)
        monitor.setCursorPos(2, y)
        monitor.write("Idle: ")
        monitor.setTextColor(colors.white)
        monitor.write(tostring(data.crafters.idle or 0))
        monitor.setTextColor(colors.lightGray)
        monitor.write(" Busy: ")
        monitor.setTextColor(colors.orange)
        monitor.write(tostring(data.crafters.busy or 0))
        y = y + 2
    end
    
    -- Craft targets
    if data.targets and #data.targets > 0 then
        monitor.setTextColor(colors.yellow)
        monitor.setCursorPos(2, y)
        monitor.write("-- Craft Targets --")
        y = y + 1
        
        for i, target in ipairs(data.targets) do
            if y > h - 1 then break end
            
            monitor.setCursorPos(2, y)
            
            -- Status indicator
            if target.current >= target.target then
                monitor.setTextColor(colors.lime)
                monitor.write("+ ")
            else
                monitor.setTextColor(colors.orange)
                monitor.write("* ")
            end
            
            -- Item name (shortened)
            monitor.setTextColor(colors.white)
            local name = target.item:gsub("minecraft:", "")
            if #name > w - 12 then
                name = name:sub(1, w - 15) .. "..."
            end
            monitor.write(name)
            
            -- Count
            monitor.setCursorPos(w - 8, y)
            monitor.setTextColor(colors.lightGray)
            monitor.write(string.format("%d/%d", target.current, target.target))
            
            y = y + 1
        end
        y = y + 1
    end
    
    -- Smelt targets
    if data.smeltTargets and #data.smeltTargets > 0 then
        monitor.setTextColor(colors.yellow)
        monitor.setCursorPos(2, y)
        monitor.write("-- Smelt Targets --")
        y = y + 1
        
        for i, target in ipairs(data.smeltTargets) do
            if y > h - 1 then break end
            
            monitor.setCursorPos(2, y)
            
            -- Status indicator
            if target.current >= target.target then
                monitor.setTextColor(colors.lime)
                monitor.write("+ ")
            else
                monitor.setTextColor(colors.red)
                monitor.write("~ ")
            end
            
            -- Item name (shortened)
            monitor.setTextColor(colors.white)
            local name = target.item:gsub("minecraft:", "")
            if #name > w - 12 then
                name = name:sub(1, w - 15) .. "..."
            end
            monitor.write(name)
            
            -- Count
            monitor.setCursorPos(w - 8, y)
            monitor.setTextColor(colors.lightGray)
            monitor.write(string.format("%d/%d", target.current, target.target))
            
            y = y + 1
        end
        y = y + 1
    end
    
    -- Fuel summary (compact)
    if data.fuelSummary and data.fuelSummary.fuelStock then
        monitor.setTextColor(colors.yellow)
        monitor.setCursorPos(2, y)
        monitor.write("-- Fuel --")
        y = y + 1
        
        -- Show top 3 fuels in compact form
        local fuelList = {}
        for i, fuel in ipairs(data.fuelSummary.fuelStock) do
            if i > 3 then break end
            local name = fuel.item:gsub("minecraft:", "")
            -- Shorten common fuel names
            name = name:gsub("_bucket", "")
            name = name:gsub("_block", "B")
            name = name:gsub("charcoal", "char")
            if #name > 8 then name = name:sub(1, 6) .. ".." end
            
            local stockColor = fuel.stock > 0 and colors.lime or colors.red
            table.insert(fuelList, {name = name, stock = fuel.stock, color = stockColor})
        end
        
        monitor.setCursorPos(2, y)
        for i, fuel in ipairs(fuelList) do
            monitor.setTextColor(colors.white)
            monitor.write(fuel.name .. ":")
            monitor.setTextColor(fuel.color)
            monitor.write(tostring(fuel.stock))
            if i < #fuelList then
                monitor.setTextColor(colors.gray)
                monitor.write(" ")
            end
        end
        y = y + 1
        
        -- Total smelt capacity
        monitor.setCursorPos(2, y)
        monitor.setTextColor(colors.lightGray)
        monitor.write("Cap: ")
        local cap = data.fuelSummary.totalSmeltCapacity or 0
        if cap >= 1000 then
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
        monitor.write(" items")
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
