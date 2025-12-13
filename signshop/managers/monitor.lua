--- SignShop Monitor Manager ---
--- Manages external monitor displays for shop information.
---
--- Features: Multiple layout options (dashboard, sales feed, stock, custom),
--- real-time updates on purchase events, configurable colors and sections,
--- automatic monitor detection, text scaling for different monitor sizes.
---
---@version 1.5.0
-- @module signshop-monitor

local s = require("lib.s")
local logger = require("lib.log")
local formui = require("lib.formui")

local manager = {}

-- Forward declare managers we'll need (loaded after check)
local salesManager, productManager, inventoryManager, aisleManager

-- Check if monitor feature is configured
local monitorEnabled = settings.get("monitor.enabled")

-- If monitor.enabled is not set at all, offer setup
if monitorEnabled == nil then
    local form = s.useForm("Monitor Display Setup")
    
    print("Would you like to configure an external monitor display?")
    print("This will show shop stats, sales, and stock information.")
    print()
    
    local enableField = form.boolean("monitor.enabled", false)
    
    if not form.submit() then
        -- Setup cancelled, disable monitor
        settings.set("monitor.enabled", false)
        settings.save()
        monitorEnabled = false
    else
        monitorEnabled = enableField()
    end
end

-- If monitor is disabled, return minimal manager
if not monitorEnabled then
    manager.run = function()
        -- No-op, monitor disabled
        while true do
            sleep(3600)
        end
    end
    return manager
end

-- Load managers now that we know we need them
salesManager = require("managers.sales")
productManager = require("managers.product")
inventoryManager = require("managers.inventory")
aisleManager = require("managers.aisle")

-- Monitor configuration with defaults
local monitorSide = s.string("monitor.side", "")
local layout = s.string("monitor.layout", "dashboard")
local refreshRate = s.number("monitor.refresh_rate", 1, 60, 5)

-- Color configuration
local colorBackground = s.number("monitor.colors.background", 0, 15, colors.black)
local colorHeader = s.number("monitor.colors.header", 0, 15, colors.yellow)
local colorText = s.number("monitor.colors.text", 0, 15, colors.white)
local colorAccent = s.number("monitor.colors.accent", 0, 15, colors.lightBlue)

-- Sections to show (stored as comma-separated string)
local defaultSections = "header,stats,recent_sales,low_stock,aisle_health"
local showSectionsStr = s.string("monitor.show_sections", defaultSections)

-- Parse sections string into table
local function parseSections(str)
    local sections = {}
    for section in str:gmatch("[^,]+") do
        sections[section:match("^%s*(.-)%s*$")] = true
    end
    return sections
end

local showSections = parseSections(showSectionsStr)

-- Monitor peripheral
local monitor = nil
local monitorWidth, monitorHeight = 0, 0

--- Find and attach to a monitor
---@return boolean success Whether a monitor was found
local function findMonitor()
    if monitorSide and #monitorSide > 0 then
        -- Use configured monitor
        monitor = peripheral.wrap(monitorSide)
        if not monitor then
            logger.warn("Configured monitor '" .. monitorSide .. "' not found")
            return false
        end
    else
        -- Auto-detect first monitor
        monitor = peripheral.find("monitor")
        if not monitor then
            logger.warn("No monitor found for display")
            return false
        end
        logger.info("Auto-detected monitor: " .. peripheral.getName(monitor))
    end
    
    if monitor then
        monitorWidth, monitorHeight = monitor.getSize()
        
        -- Scale text based on monitor size
        local scale = 1
        if monitorWidth >= 60 then
            scale = 0.5
        elseif monitorWidth >= 40 then
            scale = 1
        else
            scale = 1
        end
        
        if monitor.setTextScale then
            monitor.setTextScale(scale)
            monitorWidth, monitorHeight = monitor.getSize()
        end
        
        return true
    end
    
    return false
end

--- Clear the monitor with background color
local function clearMonitor()
    if not monitor then return end
    monitor.setBackgroundColor(colorBackground)
    monitor.setTextColor(colorText)
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

--- Draw centered text on the monitor
---@param y number Line number
---@param text string Text to center
---@param color? number Text color
local function drawCentered(y, text, color)
    if not monitor then return end
    local x = math.floor((monitorWidth - #text) / 2) + 1
    monitor.setCursorPos(x, y)
    monitor.setTextColor(color or colorText)
    monitor.write(text)
end

--- Draw text at position
---@param x number X position
---@param y number Y position
---@param text string Text to draw
---@param color? number Text color
local function drawText(x, y, text, color)
    if not monitor then return end
    monitor.setCursorPos(x, y)
    monitor.setTextColor(color or colorText)
    
    -- Truncate if too long
    if #text > monitorWidth - x + 1 then
        text = text:sub(1, monitorWidth - x - 2) .. ".."
    end
    
    monitor.write(text)
end

--- Draw a horizontal line
---@param y number Line number
---@param color? number Line color
local function drawLine(y, color)
    if not monitor then return end
    monitor.setCursorPos(1, y)
    monitor.setTextColor(color or colors.gray)
    monitor.write(string.rep("-", monitorWidth))
end

--- Format a Krist amount
---@param amount number Amount in KRO
---@return string Formatted string
local function formatKRO(amount)
    return string.format("%.03f KRO", amount or 0)
end

--- Format relative time
---@param timestamp number Unix timestamp in ms
---@return string Relative time string
local function formatTime(timestamp)
    if not timestamp then return "?" end
    local diff = os.epoch("utc") - timestamp
    
    if diff < 60000 then
        return "now"
    elseif diff < 3600000 then
        return math.floor(diff / 60000) .. "m"
    elseif diff < 86400000 then
        return math.floor(diff / 3600000) .. "h"
    else
        return math.floor(diff / 86400000) .. "d"
    end
end

--- Truncate address for display
---@param address string Krist address
---@param maxLen? number Max length
---@return string Truncated address
local function truncateAddress(address, maxLen)
    maxLen = maxLen or 10
    if not address then return "?" end
    if #address <= maxLen then return address end
    return address:sub(1, maxLen - 2) .. ".."
end

--- Get the shop name from settings
---@return string Shop name
local function getShopName()
    return settings.get("shopsync.name") or "SignShop"
end

--- Draw the header section
---@param y number Starting line
---@return number Next available line
local function drawHeader(y)
    local shopName = getShopName()
    drawCentered(y, "=== " .. shopName .. " ===", colorHeader)
    return y + 1
end

--- Draw today's stats section
---@param y number Starting line
---@return number Next available line
local function drawStats(y)
    local todayStats = salesManager.getTodayStats()
    local allStats = salesManager.getStats()
    
    drawText(1, y, "Today:", colorAccent)
    y = y + 1
    
    drawText(2, y, string.format("Sales: %d | Revenue: %s", 
        todayStats.sales or 0, formatKRO(todayStats.revenue)))
    y = y + 1
    
    drawText(2, y, string.format("Items Sold: %d", todayStats.itemsSold or 0))
    y = y + 1
    
    if monitorHeight > 10 then
        y = y + 1
        drawText(1, y, "All Time:", colorAccent)
        y = y + 1
        drawText(2, y, string.format("Total Revenue: %s", formatKRO(allStats.totalRevenue)))
        y = y + 1
    end
    
    return y
end

--- Draw recent sales section
---@param y number Starting line
---@param limit? number Max sales to show
---@return number Next available line
local function drawRecentSales(y, limit)
    limit = limit or 5
    local sales = salesManager.getRecentSales(limit)
    
    drawLine(y, colors.gray)
    y = y + 1
    
    drawText(1, y, "Recent Sales:", colorAccent)
    y = y + 1
    
    if #sales == 0 then
        drawText(2, y, "(no sales yet)", colors.gray)
        y = y + 1
    else
        for i, sale in ipairs(sales) do
            if y >= monitorHeight - 1 then break end
            
            local line = string.format("%s x%d %s - %s",
                formatTime(sale.timestamp),
                sale.quantity or 0,
                sale.productName or "?",
                truncateAddress(sale.buyerAddress, 8))
            
            drawText(2, y, line)
            y = y + 1
        end
    end
    
    return y
end

--- Draw low stock warnings section
---@param y number Starting line
---@param threshold? number Stock threshold for warning
---@return number Next available line
local function drawLowStock(y, threshold)
    threshold = threshold or 10
    local products = productManager.getAll()
    local lowStock = {}
    
    if products then
        for meta, product in pairs(products) do
            local stock = inventoryManager.getItemStock(product.modid, product.itemnbt, product.anyNbt) or 0
            if stock <= threshold then
                table.insert(lowStock, {
                    name = productManager.getName(product),
                    stock = stock,
                })
            end
        end
    end
    
    -- Sort by stock (lowest first)
    table.sort(lowStock, function(a, b)
        return a.stock < b.stock
    end)
    
    drawLine(y, colors.gray)
    y = y + 1
    
    drawText(1, y, "Low Stock:", colorAccent)
    y = y + 1
    
    if #lowStock == 0 then
        drawText(2, y, "(all stocked)", colors.green)
        y = y + 1
    else
        for i, item in ipairs(lowStock) do
            if y >= monitorHeight - 1 or i > 5 then break end
            
            local stockColor = item.stock == 0 and colors.red or colors.orange
            local line = string.format("x%d %s", item.stock, item.name)
            
            drawText(2, y, line, stockColor)
            y = y + 1
        end
    end
    
    return y
end

--- Draw aisle health section
---@param y number Starting line
---@return number Next available line
local function drawAisleHealth(y)
    local aisles = aisleManager.getAisles() or {}
    
    drawLine(y, colors.gray)
    y = y + 1
    
    drawText(1, y, "Aisles:", colorAccent)
    y = y + 1
    
    local hasAisles = false
    for name, aisle in pairs(aisles) do
        if y >= monitorHeight then break end
        hasAisles = true
        
        local health = aisleManager.getAisleHealth and aisleManager.getAisleHealth(name) or "unknown"
        local healthColor = colors.gray
        local symbol = "?"
        
        if health == "online" then
            healthColor = colors.green
            symbol = "+"
        elseif health == "degraded" then
            healthColor = colors.yellow
            symbol = "~"
        elseif health == "offline" then
            healthColor = colors.red
            symbol = "!"
        end
        
        drawText(2, y, string.format("[%s] %s", symbol, name), healthColor)
        y = y + 1
    end
    
    if not hasAisles then
        drawText(2, y, "(no aisles)", colors.gray)
        y = y + 1
    end
    
    return y
end

--- Draw dashboard layout (default)
local function drawDashboard()
    clearMonitor()
    local y = 1
    
    if showSections.header then
        y = drawHeader(y)
        y = y + 1
    end
    
    if showSections.stats then
        y = drawStats(y)
    end
    
    if showSections.recent_sales and y < monitorHeight - 3 then
        y = drawRecentSales(y, 5)
    end
    
    if showSections.low_stock and y < monitorHeight - 3 then
        y = drawLowStock(y, 10)
    end
    
    if showSections.aisle_health and y < monitorHeight - 2 then
        y = drawAisleHealth(y)
    end
end

--- Draw sales feed layout (scrolling sales)
local function drawSalesFeed()
    clearMonitor()
    
    drawCentered(1, "=== Sales Feed ===", colorHeader)
    drawLine(2)
    
    local sales = salesManager.getRecentSales(monitorHeight - 3)
    local y = 3
    
    for i, sale in ipairs(sales) do
        if y > monitorHeight then break end
        
        local line = string.format("%s | x%d %s | %s | %s",
            formatTime(sale.timestamp),
            sale.quantity or 0,
            sale.productName or "?",
            formatKRO(sale.totalPrice),
            truncateAddress(sale.buyerAddress, 10))
        
        drawText(1, y, line)
        y = y + 1
    end
    
    if #sales == 0 then
        drawText(1, 4, "No sales recorded yet.", colors.gray)
    end
end

--- Draw stock layout (all products with stock)
local function drawStockDisplay()
    clearMonitor()
    
    drawCentered(1, "=== Stock Levels ===", colorHeader)
    drawLine(2)
    
    local products = productManager.getAll()
    local productList = {}
    
    if products then
        for meta, product in pairs(products) do
            local stock = inventoryManager.getItemStock(product.modid, product.itemnbt, product.anyNbt) or 0
            table.insert(productList, {
                name = productManager.getName(product),
                stock = stock,
                meta = meta,
            })
        end
    end
    
    -- Sort by name
    table.sort(productList, function(a, b)
        return a.name < b.name
    end)
    
    local y = 3
    for _, item in ipairs(productList) do
        if y > monitorHeight then break end
        
        local stockColor
        if item.stock == 0 then
            stockColor = colors.red
        elseif item.stock <= 10 then
            stockColor = colors.orange
        elseif item.stock <= 50 then
            stockColor = colors.yellow
        else
            stockColor = colors.green
        end
        
        local line = string.format("x%-4d %s", item.stock, item.name)
        drawText(1, y, line, stockColor)
        y = y + 1
    end
    
    if #productList == 0 then
        drawText(1, 4, "No products configured.", colors.gray)
    end
end

--- Draw custom layout based on selected sections
local function drawCustom()
    -- Custom just uses dashboard with custom section selection
    drawDashboard()
end

--- Main display update function
local function updateDisplay()
    if not monitor then
        if not findMonitor() then
            return
        end
    end
    
    -- Check if monitor still exists
    if not peripheral.isPresent(peripheral.getName(monitor)) then
        monitor = nil
        logger.warn("Monitor disconnected")
        return
    end
    
    if layout == "dashboard" then
        drawDashboard()
    elseif layout == "sales_feed" then
        drawSalesFeed()
    elseif layout == "stock" then
        drawStockDisplay()
    elseif layout == "custom" then
        drawCustom()
    else
        drawDashboard()
    end
end

--- Main run loop
function manager.run()
    if not findMonitor() then
        logger.warn("No monitor found, monitor manager will retry periodically")
    end
    
    -- Initial display
    updateDisplay()
    
    -- Event-driven updates with periodic refresh
    local lastUpdate = os.epoch("utc")
    
    while true do
        local timer = os.startTimer(refreshRate)
        local event = table.pack(os.pullEvent())
        
        local shouldUpdate = false
        
        if event[1] == "timer" and event[2] == timer then
            shouldUpdate = true
        elseif event[1] == "purchase" then
            -- Immediate update on purchase
            shouldUpdate = true
        elseif event[1] == "aisle_status_change" then
            -- Update on aisle status change
            shouldUpdate = true
        elseif event[1] == "product_update" or event[1] == "product_create" or event[1] == "product_delete" then
            shouldUpdate = true
        elseif event[1] == "peripheral" or event[1] == "peripheral_detach" then
            -- Monitor might have been added/removed
            if event[1] == "peripheral_detach" and monitor then
                local name = peripheral.getName(monitor)
                if event[2] == name then
                    monitor = nil
                    logger.warn("Monitor detached")
                end
            else
                findMonitor()
            end
            shouldUpdate = true
        end
        
        if shouldUpdate then
            updateDisplay()
            lastUpdate = os.epoch("utc")
        end
    end
end

--- Close the monitor manager
function manager.close()
    if monitor then
        monitor.setBackgroundColor(colors.black)
        monitor.clear()
    end
end

return manager
