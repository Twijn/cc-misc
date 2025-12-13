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

-- Check if this is first run or settings are missing
local needsSetup = monitorEnabled == nil

local monitorSide, refreshRate
local colorBackground, colorHeader, colorText, colorAccent
local showSectionsStr

-- Default sections
local defaultSections = "header,stats,recent_sales,low_stock,aisle_health"

if needsSetup then
    -- Use form-based setup for new installations
    local form = s.useForm("Monitor Display Setup")
    
    print("Would you like to configure an external monitor display?")
    print("This will show shop stats, sales, and stock information.")
    print()
    
    local enableField = form.boolean("monitor.enabled")
    local monitorField = form.peripheral("monitor.side", "monitor")
    local refreshField = form.number("monitor.refresh_rate", 1, 60, 5)
    local bgColorField = form.color("monitor.colors.background", colors.black)
    local headerColorField = form.color("monitor.colors.header", colors.yellow)
    local textColorField = form.color("monitor.colors.text", colors.white)
    local accentColorField = form.color("monitor.colors.accent", colors.lightBlue)
    local sectionsField = form.string("monitor.show_sections", defaultSections)
    
    if not form.submit() then
        -- Setup cancelled, disable monitor
        settings.set("monitor.enabled", false)
        settings.save()
        monitorEnabled = false
    else
        monitorEnabled = enableField()
        if monitorEnabled then
            -- Call the getters to save values to settings
            monitorField()
            refreshField()
            bgColorField()
            headerColorField()
            textColorField()
            accentColorField()
            sectionsField()
            
            -- Read values back from settings
            monitorSide = settings.get("monitor.side") or ""
            refreshRate = settings.get("monitor.refresh_rate") or 5
            colorBackground = settings.get("monitor.colors.background") or colors.black
            colorHeader = settings.get("monitor.colors.header") or colors.yellow
            colorText = settings.get("monitor.colors.text") or colors.white
            colorAccent = settings.get("monitor.colors.accent") or colors.lightBlue
            showSectionsStr = settings.get("monitor.show_sections") or defaultSections
        end
    end
else
    monitorEnabled = settings.get("monitor.enabled")
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

-- Load configuration from settings if not already set by form
if not monitorSide then
    -- Use s.peripheral for monitor selection when not using form
    local monitorPeripheral = s.peripheral("monitor.side", "monitor")
    monitorSide = monitorPeripheral and peripheral.getName(monitorPeripheral) or ""
end
if not refreshRate then refreshRate = s.number("monitor.refresh_rate", 1, 60, 5) end

-- Color configuration (load if not set by form)
if not colorBackground then colorBackground = s.color("monitor.colors.background", colors.black) end
if not colorHeader then colorHeader = s.color("monitor.colors.header", colors.yellow) end
if not colorText then colorText = s.color("monitor.colors.text", colors.white) end
if not colorAccent then colorAccent = s.color("monitor.colors.accent", colors.lightBlue) end

-- Sections to show (stored as comma-separated string)
if not showSectionsStr then showSectionsStr = s.string("monitor.show_sections", defaultSections) end

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
        
        -- Scale text based on monitor size for optimal readability
        local scale = 1
        if monitorWidth >= 80 then
            scale = 0.5
        elseif monitorWidth >= 60 then
            scale = 0.5
        elseif monitorWidth >= 40 then
            scale = 1
        elseif monitorWidth >= 20 then
            scale = 1
        else
            scale = 2  -- Very small monitors need larger text
        end
        
        if monitor.setTextScale then
            monitor.setTextScale(scale)
            monitorWidth, monitorHeight = monitor.getSize()
        end
        
        logger.info(string.format("Monitor configured: %dx%d (scale %.1f)", monitorWidth, monitorHeight, scale))
        
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
    
    -- Adapt layout based on monitor width
    if monitorWidth >= 40 then
        -- Wide monitor: show more detail
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
    elseif monitorWidth >= 25 then
        -- Medium monitor: compact format
        drawText(1, y, "Today:", colorAccent)
        y = y + 1
        drawText(2, y, string.format("%d sales", todayStats.sales or 0))
        y = y + 1
        drawText(2, y, formatKRO(todayStats.revenue))
        y = y + 1
        
        if monitorHeight > 8 then
            drawText(1, y, "Total:", colorAccent)
            y = y + 1
            drawText(2, y, formatKRO(allStats.totalRevenue))
            y = y + 1
        end
    else
        -- Small monitor: minimal info
        drawText(1, y, string.format("$%d", todayStats.sales or 0), colorAccent)
        y = y + 1
        drawText(1, y, formatKRO(todayStats.revenue))
        y = y + 1
    end
    
    return y
end

--- Draw recent sales section
---@param y number Starting line
---@param limit? number Max sales to show
---@return number Next available line
local function drawRecentSales(y, limit)
    -- Adapt limit based on available space
    limit = limit or math.max(2, math.floor((monitorHeight - y) / 2))
    local sales = salesManager.getRecentSales(limit)
    
    drawLine(y, colors.gray)
    y = y + 1
    
    if monitorWidth >= 20 then
        drawText(1, y, "Recent Sales:", colorAccent)
        y = y + 1
    end
    
    if #sales == 0 then
        drawText(2, y, "(no sales yet)", colors.gray)
        y = y + 1
    else
        local indent = monitorWidth >= 20 and 2 or 1
        local availableWidth = monitorWidth - indent
        
        for i, sale in ipairs(sales) do
            if y >= monitorHeight - 1 then break end
            
            -- Build the line dynamically based on available width
            local qty = string.format("x%d", sale.quantity or 0)
            local time = formatTime(sale.timestamp)
            local product = sale.productName or "?"
            local buyer = truncateAddress(sale.buyerAddress, 10)
            
            local line
            if availableWidth >= 60 then
                -- Very wide: full details with price
                line = string.format("%s %s %s - %s %s", time, qty, product, formatKRO(sale.totalPrice), buyer)
            elseif availableWidth >= 45 then
                -- Wide: time, qty, product, buyer
                line = string.format("%s %s %s - %s", time, qty, product, buyer)
            elseif availableWidth >= 30 then
                -- Medium: qty, product, truncated buyer
                local maxProduct = availableWidth - #qty - 10
                if #product > maxProduct then
                    product = product:sub(1, maxProduct - 2) .. ".."
                end
                line = string.format("%s %s - %s", qty, product, truncateAddress(sale.buyerAddress, 6))
            elseif availableWidth >= 18 then
                -- Narrow: qty and product only
                local maxProduct = availableWidth - #qty - 1
                if #product > maxProduct then
                    product = product:sub(1, maxProduct - 2) .. ".."
                end
                line = string.format("%s %s", qty, product)
            else
                -- Very narrow: just product truncated
                if #product > availableWidth then
                    product = product:sub(1, availableWidth - 2) .. ".."
                end
                line = product
            end
            
            drawText(indent, y, line)
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
    
    if monitorWidth >= 15 then
        drawText(1, y, "Low Stock:", colorAccent)
        y = y + 1
    end
    
    if #lowStock == 0 then
        local indent = monitorWidth >= 20 and 2 or 1
        drawText(indent, y, "(all stocked)", colors.green)
        y = y + 1
    else
        -- Limit based on screen height
        local maxItems = math.min(5, math.max(2, monitorHeight - y - 1))
        for i, item in ipairs(lowStock) do
            if y >= monitorHeight - 1 or i > maxItems then break end
            
            local stockColor = item.stock == 0 and colors.red or colors.orange
            local line
            if monitorWidth >= 25 then
                line = string.format("x%d %s", item.stock, item.name)
            else
                line = string.format("%d %s", item.stock, item.name:sub(1, monitorWidth - 4))
            end
            
            local indent = monitorWidth >= 20 and 2 or 1
            drawText(indent, y, line, stockColor)
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
    
    if monitorWidth >= 12 then
        drawText(1, y, "Aisles:", colorAccent)
        y = y + 1
    end
    
    -- Collect aisle data first
    local aisleList = {}
    for name, aisle in pairs(aisles) do
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
        
        table.insert(aisleList, {
            name = name,
            symbol = symbol,
            color = healthColor
        })
    end
    
    -- Sort aisles by name
    table.sort(aisleList, function(a, b) return a.name < b.name end)
    
    if #aisleList == 0 then
        local indent = monitorWidth >= 20 and 2 or 1
        drawText(indent, y, "(no aisles)", colors.gray)
        y = y + 1
        return y
    end
    
    local indent = monitorWidth >= 20 and 2 or 1
    local availableWidth = monitorWidth - indent
    
    -- Calculate how many aisles can fit per line
    -- Format: "[+] Name" = 4 + name length, with 2 spaces between items
    local maxNameLen = 0
    for _, aisle in ipairs(aisleList) do
        maxNameLen = math.max(maxNameLen, #aisle.name)
    end
    
    -- Determine item width and items per row
    local itemWidth
    if monitorWidth >= 40 then
        -- Wide: show full names with brackets
        itemWidth = math.min(maxNameLen + 5, 20)  -- "[+] Name" + padding
    elseif monitorWidth >= 25 then
        -- Medium: shorter format
        itemWidth = math.min(maxNameLen + 3, 12)  -- "+Name" + padding
    else
        -- Narrow: very compact
        itemWidth = math.min(maxNameLen + 2, 8)
    end
    
    local itemsPerRow = math.max(1, math.floor(availableWidth / itemWidth))
    
    -- Draw aisles in rows
    local col = 0
    local currentX = indent
    
    for i, aisle in ipairs(aisleList) do
        if y >= monitorHeight then break end
        
        local displayName = aisle.name
        local maxDisplayLen = itemWidth - 4  -- Account for symbol and spacing
        if #displayName > maxDisplayLen then
            displayName = displayName:sub(1, maxDisplayLen - 1) .. "."
        end
        
        local text
        if monitorWidth >= 40 then
            text = string.format("[%s] %s", aisle.symbol, displayName)
        else
            text = string.format("%s%s", aisle.symbol, displayName)
        end
        
        -- Pad to item width for alignment (except last item in row)
        if col < itemsPerRow - 1 and i < #aisleList then
            text = text .. string.rep(" ", math.max(0, itemWidth - #text))
        end
        
        monitor.setCursorPos(currentX, y)
        monitor.setTextColor(aisle.color)
        monitor.write(text)
        
        col = col + 1
        currentX = currentX + itemWidth
        
        if col >= itemsPerRow then
            col = 0
            currentX = indent
            y = y + 1
        end
    end
    
    -- Move to next line if we didn't just do so
    if col > 0 then
        y = y + 1
    end
    
    return y
end

--- Draw top products section
---@param y number Starting line
---@param limit? number Max products to show
---@return number Next available line
local function drawTopProducts(y, limit)
    limit = limit or math.max(2, math.min(5, math.floor((monitorHeight - y) / 2)))
    local products = salesManager.getTopProducts(limit)
    
    drawLine(y, colors.gray)
    y = y + 1
    
    if monitorWidth >= 18 then
        drawText(1, y, "Top Products:", colorAccent)
        y = y + 1
    end
    
    if #products == 0 then
        local indent = monitorWidth >= 20 and 2 or 1
        drawText(indent, y, "(no sales)", colors.gray)
        y = y + 1
    else
        for i, prod in ipairs(products) do
            if y >= monitorHeight - 1 then break end
            
            local line
            if monitorWidth >= 40 then
                line = string.format("#%d %s - %s", i, prod.name or prod.meta or "?", formatKRO(prod.revenue))
            elseif monitorWidth >= 25 then
                line = string.format("#%d %s", i, prod.name or prod.meta or "?")
            else
                line = string.format("%d.%s", i, (prod.name or "?"):sub(1, monitorWidth - 3))
            end
            
            local indent = monitorWidth >= 20 and 2 or 1
            local rankColor = i <= 3 and colors.green or colorText
            drawText(indent, y, line, rankColor)
            y = y + 1
        end
    end
    
    return y
end

--- Draw top buyers section
---@param y number Starting line
---@param limit? number Max buyers to show
---@return number Next available line
local function drawTopBuyers(y, limit)
    limit = limit or math.max(2, math.min(5, math.floor((monitorHeight - y) / 2)))
    local buyers = salesManager.getTopBuyers(limit)
    
    drawLine(y, colors.gray)
    y = y + 1
    
    if monitorWidth >= 16 then
        drawText(1, y, "Top Buyers:", colorAccent)
        y = y + 1
    end
    
    if #buyers == 0 then
        local indent = monitorWidth >= 20 and 2 or 1
        drawText(indent, y, "(no buyers)", colors.gray)
        y = y + 1
    else
        for i, buyer in ipairs(buyers) do
            if y >= monitorHeight - 1 then break end
            
            local addrLen = monitorWidth >= 40 and 12 or (monitorWidth >= 25 and 8 or 6)
            local line
            if monitorWidth >= 35 then
                line = string.format("#%d %s - %s", i, truncateAddress(buyer.address, addrLen), formatKRO(buyer.totalSpent))
            else
                line = string.format("%d.%s", i, truncateAddress(buyer.address, addrLen))
            end
            
            local indent = monitorWidth >= 20 and 2 or 1
            local rankColor = i <= 3 and colors.green or colorText
            drawText(indent, y, line, rankColor)
            y = y + 1
        end
    end
    
    return y
end

--- Draw dashboard layout (based on enabled sections)
local function drawDashboard()
    clearMonitor()
    local y = 1
    
    if showSections.header then
        y = drawHeader(y)
        y = y + 1
    end
    
    if showSections.stats and y < monitorHeight - 2 then
        y = drawStats(y)
    end
    
    if showSections.recent_sales and y < monitorHeight - 3 then
        y = drawRecentSales(y)
    end
    
    if showSections.top_products and y < monitorHeight - 3 then
        y = drawTopProducts(y)
    end
    
    if showSections.top_buyers and y < monitorHeight - 3 then
        y = drawTopBuyers(y)
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
    
    -- Always use dashboard layout which respects section settings
    drawDashboard()
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
