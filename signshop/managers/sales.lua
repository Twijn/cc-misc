--- SignShop Sales Manager ---
--- Tracks and persists sales data for analytics.
---
---@version 1.6.0

local persist = require("lib.persist")

local salesData = persist("sales.json", false)

-- Initialize defaults
salesData.setDefault("sales", {})
salesData.setDefault("stats", {
    totalSales = 0,
    totalRevenue = 0,
    totalItemsSold = 0,
})

local manager = {}

---@class SaleRecord
---@field id number Unique sale ID
---@field timestamp number Unix timestamp of the sale
---@field date string Human-readable date
---@field productMeta string Product meta/ID
---@field productName string Product display name
---@field quantity number Number of items sold
---@field unitPrice number Price per item
---@field totalPrice number Total price paid
---@field refundAmount number Amount refunded (if any)
---@field buyerAddress string Krist address of buyer
---@field transactionId number Krist transaction ID
---@field aisleName string Aisle where product is located

--- Record a new sale
---@param product table The product that was sold
---@param quantity number Number of items sold
---@param transaction table The Krist transaction
---@param refundAmount number Amount refunded
function manager.recordSale(product, quantity, transaction, refundAmount)
    local data = salesData.getAll()
    
    -- Generate sale ID
    local saleId = (data.stats.totalSales or 0) + 1
    
    -- Build sale record
    local sale = {
        id = saleId,
        timestamp = os.epoch("utc"),
        date = os.date("%Y-%m-%d %H:%M:%S"),
        productMeta = product.meta,
        productName = product.line1 or product.meta,
        quantity = quantity,
        unitPrice = product.cost,
        totalPrice = product.cost * quantity,
        refundAmount = refundAmount or 0,
        buyerAddress = transaction.from,
        transactionId = transaction.id,
        aisleName = product.aisleName or "Unknown",
    }
    
    -- Update sales list (prepend for most recent first)
    local sales = data.sales or {}
    table.insert(sales, 1, sale)
    
    -- Limit to last 1000 sales to prevent file from growing too large
    while #sales > 1000 do
        table.remove(sales)
    end
    
    -- Update stats
    local stats = data.stats or {}
    stats.totalSales = (stats.totalSales or 0) + 1
    stats.totalRevenue = (stats.totalRevenue or 0) + sale.totalPrice
    stats.totalItemsSold = (stats.totalItemsSold or 0) + quantity
    
    -- Update per-product stats
    local productStats = stats.byProduct or {}
    if not productStats[product.meta] then
        productStats[product.meta] = {
            sales = 0,
            revenue = 0,
            itemsSold = 0,
            productName = sale.productName,
        }
    end
    productStats[product.meta].sales = productStats[product.meta].sales + 1
    productStats[product.meta].revenue = productStats[product.meta].revenue + sale.totalPrice
    productStats[product.meta].itemsSold = productStats[product.meta].itemsSold + quantity
    productStats[product.meta].productName = sale.productName -- Update in case name changed
    stats.byProduct = productStats
    
    -- Update per-buyer stats
    local buyerStats = stats.byBuyer or {}
    if not buyerStats[transaction.from] then
        buyerStats[transaction.from] = {
            purchases = 0,
            totalSpent = 0,
            itemsBought = 0,
        }
    end
    buyerStats[transaction.from].purchases = buyerStats[transaction.from].purchases + 1
    buyerStats[transaction.from].totalSpent = buyerStats[transaction.from].totalSpent + sale.totalPrice
    buyerStats[transaction.from].itemsBought = buyerStats[transaction.from].itemsBought + quantity
    stats.byBuyer = buyerStats
    
    -- Save everything
    salesData.set("sales", sales)
    salesData.set("stats", stats)
    
    return sale
end

--- Get recent sales
---@param limit? number Maximum number of sales to return (default 50)
---@return table[] Array of sale records
function manager.getRecentSales(limit)
    limit = limit or 50
    local sales = salesData.get("sales") or {}
    local result = {}
    for i = 1, math.min(limit, #sales) do
        table.insert(result, sales[i])
    end
    return result
end

--- Get all sales
---@return table[] Array of all sale records
function manager.getAllSales()
    return salesData.get("sales") or {}
end

--- Get overall stats
---@return table Stats object
function manager.getStats()
    return salesData.get("stats") or {
        totalSales = 0,
        totalRevenue = 0,
        totalItemsSold = 0,
        byProduct = {},
        byBuyer = {},
    }
end

--- Get stats for a specific product
---@param meta string Product meta
---@return table|nil Product stats or nil
function manager.getProductStats(meta)
    local stats = manager.getStats()
    if stats.byProduct then
        return stats.byProduct[meta]
    end
    return nil
end

--- Get stats for a specific buyer
---@param address string Krist address
---@return table|nil Buyer stats or nil
function manager.getBuyerStats(address)
    local stats = manager.getStats()
    if stats.byBuyer then
        return stats.byBuyer[address]
    end
    return nil
end

--- Get top products by revenue
---@param limit? number Maximum number to return (default 10)
---@return table[] Array of {meta, stats} sorted by revenue
function manager.getTopProducts(limit)
    limit = limit or 10
    local stats = manager.getStats()
    local products = {}
    
    if stats.byProduct then
        for meta, productStats in pairs(stats.byProduct) do
            table.insert(products, {
                meta = meta,
                name = productStats.productName,
                sales = productStats.sales,
                revenue = productStats.revenue,
                itemsSold = productStats.itemsSold,
            })
        end
    end
    
    table.sort(products, function(a, b)
        return a.revenue > b.revenue
    end)
    
    local result = {}
    for i = 1, math.min(limit, #products) do
        table.insert(result, products[i])
    end
    return result
end

--- Get top buyers by total spent
---@param limit? number Maximum number to return (default 10)
---@return table[] Array of {address, stats} sorted by total spent
function manager.getTopBuyers(limit)
    limit = limit or 10
    local stats = manager.getStats()
    local buyers = {}
    
    if stats.byBuyer then
        for address, buyerStats in pairs(stats.byBuyer) do
            table.insert(buyers, {
                address = address,
                purchases = buyerStats.purchases,
                totalSpent = buyerStats.totalSpent,
                itemsBought = buyerStats.itemsBought,
            })
        end
    end
    
    table.sort(buyers, function(a, b)
        return a.totalSpent > b.totalSpent
    end)
    
    local result = {}
    for i = 1, math.min(limit, #buyers) do
        table.insert(result, buyers[i])
    end
    return result
end

--- Get sales for today
---@return table[] Array of today's sales
function manager.getTodaySales()
    local today = os.date("%Y-%m-%d")
    local sales = manager.getAllSales()
    local result = {}
    
    for _, sale in ipairs(sales) do
        if sale.date and sale.date:sub(1, 10) == today then
            table.insert(result, sale)
        end
    end
    
    return result
end

--- Calculate today's stats
---@return table Stats for today
function manager.getTodayStats()
    local todaySales = manager.getTodaySales()
    local stats = {
        sales = #todaySales,
        revenue = 0,
        itemsSold = 0,
    }
    
    for _, sale in ipairs(todaySales) do
        stats.revenue = stats.revenue + sale.totalPrice
        stats.itemsSold = stats.itemsSold + sale.quantity
    end
    
    return stats
end

--- Clear all sales data (use with caution!)
function manager.clearAll()
    salesData.set("sales", {})
    salesData.set("stats", {
        totalSales = 0,
        totalRevenue = 0,
        totalItemsSold = 0,
        byProduct = {},
        byBuyer = {},
    })
end

return manager
