--- SignShop Sales Configuration ---
--- Sales dashboard and statistics screens.
---
---@version 1.0.0

if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

local ui = require("lib.ui")

local salesManager = require("managers.sales")

local sales = {}

--- Format a Krist amount nicely
---@param amount number Amount in KRO
---@return string Formatted string
local function formatKRO(amount)
    return string.format("%.03f KRO", amount or 0)
end

--- Format a timestamp nicely
---@param timestamp number Unix timestamp in milliseconds
---@return string Formatted date/time
local function formatTime(timestamp)
    if not timestamp then return "Unknown" end
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
local function truncateAddress(address, maxLen)
    maxLen = maxLen or 12
    if not address then return "Unknown" end
    if #address <= maxLen then return address end
    return address:sub(1, maxLen - 2) .. ".."
end

--- Show sales dashboard with overview stats
function sales.showDashboard()
    local scroll = 0
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3
        local footerHeight = 2
        local visibleHeight = h - headerHeight - footerHeight
        
        local stats = salesManager.getStats()
        local todayStats = salesManager.getTodayStats()
        
        -- Build content lines
        local contentLines = {}
        
        -- Overall stats
        table.insert(contentLines, { text = "All Time Statistics:", color = colors.yellow })
        table.insert(contentLines, { label = "  Total Sales: ", value = tostring(stats.totalSales or 0), labelColor = colors.lightBlue, valueColor = colors.white })
        table.insert(contentLines, { label = "  Total Revenue: ", value = formatKRO(stats.totalRevenue), labelColor = colors.lightBlue, valueColor = colors.green })
        table.insert(contentLines, { label = "  Items Sold: ", value = tostring(stats.totalItemsSold or 0), labelColor = colors.lightBlue, valueColor = colors.white })
        table.insert(contentLines, { text = "", color = colors.white })
        
        -- Today's stats
        table.insert(contentLines, { text = "Today's Statistics:", color = colors.yellow })
        table.insert(contentLines, { label = "  Sales Today: ", value = tostring(todayStats.sales or 0), labelColor = colors.lightBlue, valueColor = colors.white })
        table.insert(contentLines, { label = "  Revenue Today: ", value = formatKRO(todayStats.revenue), labelColor = colors.lightBlue, valueColor = colors.green })
        table.insert(contentLines, { label = "  Items Sold Today: ", value = tostring(todayStats.itemsSold or 0), labelColor = colors.lightBlue, valueColor = colors.white })
        table.insert(contentLines, { text = "", color = colors.white })
        
        -- Quick stats
        local topProducts = salesManager.getTopProducts(3)
        if #topProducts > 0 then
            table.insert(contentLines, { text = "Top 3 Products:", color = colors.yellow })
            for i, prod in ipairs(topProducts) do
                table.insert(contentLines, { text = string.format("  %d. %s - %s (%d sold)", 
                    i, prod.name or prod.meta, formatKRO(prod.revenue), prod.itemsSold or 0), color = colors.white })
            end
            table.insert(contentLines, { text = "", color = colors.white })
        end
        
        local topBuyers = salesManager.getTopBuyers(3)
        if #topBuyers > 0 then
            table.insert(contentLines, { text = "Top 3 Buyers:", color = colors.yellow })
            for i, buyer in ipairs(topBuyers) do
                table.insert(contentLines, { text = string.format("  %d. %s - %s", 
                    i, truncateAddress(buyer.address, 15), formatKRO(buyer.totalSpent)), color = colors.white })
            end
        end
        
        local totalLines = #contentLines
        
        -- Clamp scroll
        scroll = math.max(0, math.min(scroll, math.max(0, totalLines - visibleHeight)))
        
        -- Title
        term.setTextColor(colors.yellow)
        print("=== Sales Dashboard ===")
        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        print()
        
        -- Draw visible content
        for i = scroll + 1, math.min(totalLines, scroll + visibleHeight) do
            local line = contentLines[i]
            if line.label then
                term.setTextColor(line.labelColor)
                write(line.label)
                term.setTextColor(line.valueColor)
                print(line.value)
            else
                term.setTextColor(line.color)
                print(line.text)
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
        print("Up/Down: Scroll | Q: Back")
        
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
            return
        end
    end
end

--- Show recent sales with scrolling
function sales.showRecent()
    local scroll = 0
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3
        local footerHeight = 2
        local visibleHeight = h - headerHeight - footerHeight
        
        local recentSales = salesManager.getRecentSales(100)
        
        -- Title
        term.setTextColor(colors.yellow)
        print("=== Recent Sales ===")
        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        print()
        
        if #recentSales == 0 then
            term.setTextColor(colors.gray)
            print("No sales recorded yet.")
        else
            -- Clamp scroll
            scroll = math.max(0, math.min(scroll, math.max(0, #recentSales - visibleHeight)))
            
            -- Draw sales
            for i = scroll + 1, math.min(#recentSales, scroll + visibleHeight) do
                local sale = recentSales[i]
                local line = string.format("#%d %s - %s x%d = %s from %s",
                    sale.id or i,
                    formatTime(sale.timestamp),
                    sale.productName or sale.productMeta or "?",
                    sale.quantity or 0,
                    formatKRO(sale.totalPrice),
                    truncateAddress(sale.buyerAddress, 10))
                
                -- Truncate if too long
                if #line > w - 1 then
                    line = line:sub(1, w - 4) .. "..."
                end
                
                term.setTextColor(colors.white)
                print(line)
            end
            
            -- Draw scroll indicators
            term.setTextColor(colors.gray)
            if scroll > 0 then
                term.setCursorPos(w, headerHeight + 1)
                write("^")
            end
            if scroll + visibleHeight < #recentSales then
                term.setCursorPos(w, h - footerHeight)
                write("v")
            end
        end
        
        -- Footer
        term.setCursorPos(1, h - 1)
        term.setTextColor(colors.gray)
        print("Up/Down: Scroll | Q: Back")
        
        local e, key = os.pullEvent("key")
        if key == keys.q then
            return
        elseif key == keys.up then
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
            scroll = #recentSales - visibleHeight
        end
    end
end

--- Show top products by revenue
function sales.showTopProducts()
    local scroll = 0
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3
        local footerHeight = 2
        local visibleHeight = h - headerHeight - footerHeight
        
        local products = salesManager.getTopProducts(50)
        
        -- Title
        term.setTextColor(colors.yellow)
        print("=== Top Products by Revenue ===")
        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        print()
        
        if #products == 0 then
            term.setTextColor(colors.gray)
            print("No product sales recorded yet.")
        else
            -- Clamp scroll
            scroll = math.max(0, math.min(scroll, math.max(0, #products - visibleHeight)))
            
            -- Draw products
            for i = scroll + 1, math.min(#products, scroll + visibleHeight) do
                local prod = products[i]
                local rank = i
                
                -- Format: #1 Product Name - 123.456 KRO (45 sales, 120 items)
                local line = string.format("#%d %s - %s (%d sales, %d items)",
                    rank,
                    prod.name or prod.meta or "?",
                    formatKRO(prod.revenue),
                    prod.sales or 0,
                    prod.itemsSold or 0)
                
                -- Truncate if too long
                if #line > w - 1 then
                    line = line:sub(1, w - 4) .. "..."
                end
                
                -- Color based on rank
                if rank <= 3 then
                    term.setTextColor(colors.green)
                elseif rank <= 10 then
                    term.setTextColor(colors.yellow)
                else
                    term.setTextColor(colors.white)
                end
                print(line)
            end
            
            -- Draw scroll indicators
            term.setTextColor(colors.gray)
            if scroll > 0 then
                term.setCursorPos(w, headerHeight + 1)
                write("^")
            end
            if scroll + visibleHeight < #products then
                term.setCursorPos(w, h - footerHeight)
                write("v")
            end
        end
        
        -- Footer
        term.setCursorPos(1, h - 1)
        term.setTextColor(colors.gray)
        print("Up/Down: Scroll | Q: Back")
        
        local e, key = os.pullEvent("key")
        if key == keys.q then
            return
        elseif key == keys.up then
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
            scroll = #products - visibleHeight
        end
    end
end

--- Show top buyers by total spent
function sales.showTopBuyers()
    local scroll = 0
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3
        local footerHeight = 2
        local visibleHeight = h - headerHeight - footerHeight
        
        local buyers = salesManager.getTopBuyers(50)
        
        -- Title
        term.setTextColor(colors.yellow)
        print("=== Top Buyers by Spending ===")
        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        print()
        
        if #buyers == 0 then
            term.setTextColor(colors.gray)
            print("No buyer data recorded yet.")
        else
            -- Clamp scroll
            scroll = math.max(0, math.min(scroll, math.max(0, #buyers - visibleHeight)))
            
            -- Draw buyers
            for i = scroll + 1, math.min(#buyers, scroll + visibleHeight) do
                local buyer = buyers[i]
                local rank = i
                
                -- Format: #1 k1234abcd... - 123.456 KRO (45 purchases, 120 items)
                local line = string.format("#%d %s - %s (%d purchases, %d items)",
                    rank,
                    truncateAddress(buyer.address, 14),
                    formatKRO(buyer.totalSpent),
                    buyer.purchases or 0,
                    buyer.itemsBought or 0)
                
                -- Truncate if too long
                if #line > w - 1 then
                    line = line:sub(1, w - 4) .. "..."
                end
                
                -- Color based on rank
                if rank <= 3 then
                    term.setTextColor(colors.green)
                elseif rank <= 10 then
                    term.setTextColor(colors.yellow)
                else
                    term.setTextColor(colors.white)
                end
                print(line)
            end
            
            -- Draw scroll indicators
            term.setTextColor(colors.gray)
            if scroll > 0 then
                term.setCursorPos(w, headerHeight + 1)
                write("^")
            end
            if scroll + visibleHeight < #buyers then
                term.setCursorPos(w, h - footerHeight)
                write("v")
            end
        end
        
        -- Footer
        term.setCursorPos(1, h - 1)
        term.setTextColor(colors.gray)
        print("Up/Down: Scroll | Q: Back")
        
        local e, key = os.pullEvent("key")
        if key == keys.q then
            return
        elseif key == keys.up then
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
            scroll = #buyers - visibleHeight
        end
    end
end

return sales
