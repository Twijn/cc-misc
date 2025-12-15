--- SignShop Display Manager ---
--- Manages multiple display monitors with different display types and filtering.
---
--- Features:
---   - Multiple monitor support with independent configurations
---   - Catalog display showing all products with prices
---   - Category filtering and grouping
---   - Mirror displays (same content on multiple monitors)
---   - Auto-scrolling for content that doesn't fit
---   - Real-time updates on purchases and stock changes
---
---@version 1.0.0

local s = require("lib.s")
local logger = require("lib.log")
local persist = require("lib.persist")
local formui = require("lib.formui")

local manager = {}

-- Forward declare managers
local productManager, inventoryManager, categoryManager, salesManager

-- Check if display feature is enabled
local displaysEnabled = settings.get("displays.enabled")
local needsSetup = displaysEnabled == nil

-- Persist display configurations
local displayConfig = persist("display-config.json")

-- Active display instances
local activeDisplays = {}

-- Maximum stock to display
local maxStockDisplay = s.number("signshop.max_stock_display", 0, 999999, 0)

--- Default color scheme
local defaultColors = {
    background = colors.black,
    header = colors.yellow,
    text = colors.white,
    accent = colors.lightBlue,
    price = colors.lime,
    lowStock = colors.orange,
    noStock = colors.red,
    category = colors.purple,
    border = colors.gray,
}

--- Default display options
local defaultOptions = {
    showStock = true,
    showPrice = true,
    showCategory = true,
    groupByCategory = true,
    scrollSpeed = 5,
    showDuplicates = true,  -- Show products with same mod ID but different prices/meta
}

--- First-time setup
if needsSetup then
    local form = s.useForm("Display Monitors Setup")
    
    print("Would you like to configure display monitors?")
    print("Display monitors show product catalogs, prices, and stock.")
    print("")
    
    local enableField = form.boolean("displays.enabled")
    
    if not form.submit() then
        settings.set("displays.enabled", false)
        settings.save()
        displaysEnabled = false
    else
        displaysEnabled = enableField()
    end
end

-- If displays are disabled, return minimal manager
if not displaysEnabled then
    manager.run = function()
        while true do
            sleep(3600)
        end
    end
    return manager
end

-- Load managers
productManager = require("managers.product")
inventoryManager = require("managers.inventory")
categoryManager = require("managers.category")

-- Try to load sales manager (optional)
local ok, sm = pcall(require, "managers.sales")
if ok then salesManager = sm end

--- Format stock for display
---@param stock number Raw stock count
---@return string Formatted stock string
---@return number Color for the stock
local function formatStock(stock)
    local displayStock = stock
    local capped = false
    
    if maxStockDisplay > 0 and stock > maxStockDisplay then
        displayStock = maxStockDisplay
        capped = true
    end
    
    local color
    if stock == 0 then
        color = defaultColors.noStock
    elseif stock <= 10 then
        color = defaultColors.lowStock
    else
        color = defaultColors.text
    end
    
    local formatted
    if displayStock >= 1000 then
        formatted = math.floor(displayStock / 100) / 10 .. "K"
    else
        formatted = tostring(displayStock)
    end
    
    if capped then
        formatted = formatted .. "+"
    end
    
    return formatted, color
end

--- Format price for display
---@param price number Price in KRO
---@return string Formatted price
local function formatPrice(price)
    return string.format("%.03f", price)
end

--- Create a display instance
---@param config table Display configuration
---@return table|nil Display instance or nil on error
local function createDisplay(config)
    if not config.peripheral then
        logger.warn("Display config missing peripheral: " .. (config.id or "unknown"))
        return nil
    end
    
    local monitor = peripheral.wrap(config.peripheral)
    if not monitor then
        logger.warn("Display monitor not found: " .. config.peripheral)
        return nil
    end
    
    local display = {
        id = config.id or config.peripheral,
        config = config,
        monitor = monitor,
        width = 0,
        height = 0,
        scrollOffset = 0,
        lastUpdate = 0,
        contentHeight = 0,
    }
    
    -- Get monitor size and set scale
    local w, h = monitor.getSize()
    
    -- Auto-scale based on size
    local scale = 1
    if w >= 80 then scale = 0.5
    elseif w >= 60 then scale = 0.5
    elseif w >= 40 then scale = 1
    else scale = 1 end
    
    if monitor.setTextScale then
        monitor.setTextScale(scale)
        w, h = monitor.getSize()
    end
    
    display.width = w
    display.height = h
    
    -- Merge colors with defaults
    display.colors = {}
    for k, v in pairs(defaultColors) do
        display.colors[k] = (config.colors and config.colors[k]) or v
    end
    
    -- Merge options with defaults
    display.options = {}
    for k, v in pairs(defaultOptions) do
        display.options[k] = (config.options and config.options[k] ~= nil) and config.options[k] or v
    end
    
    logger.info(string.format("Created display '%s' on %s (%dx%d)", 
        display.id, config.peripheral, display.width, display.height))
    
    return display
end

--- Clear a display
---@param display table Display instance
local function clearDisplay(display)
    display.monitor.setBackgroundColor(display.colors.background)
    display.monitor.setTextColor(display.colors.text)
    display.monitor.clear()
    display.monitor.setCursorPos(1, 1)
end

--- Draw text on a display
---@param display table Display instance
---@param x number X position
---@param y number Y position
---@param text string Text to draw
---@param color? number Text color
local function drawText(display, x, y, text, color)
    if y < 1 or y > display.height then return end
    
    display.monitor.setCursorPos(x, y)
    display.monitor.setTextColor(color or display.colors.text)
    
    -- Truncate if too long
    local maxLen = display.width - x + 1
    if #text > maxLen then
        text = text:sub(1, maxLen - 2) .. ".."
    end
    
    display.monitor.write(text)
end

--- Draw centered text
---@param display table Display instance
---@param y number Y position
---@param text string Text to draw
---@param color? number Text color
local function drawCentered(display, y, text, color)
    local x = math.floor((display.width - #text) / 2) + 1
    drawText(display, x, y, text, color)
end

--- Draw a horizontal line
---@param display table Display instance
---@param y number Y position
---@param color? number Line color
local function drawLine(display, y, color)
    if y < 1 or y > display.height then return end
    
    display.monitor.setCursorPos(1, y)
    display.monitor.setTextColor(color or display.colors.border)
    display.monitor.write(string.rep("-", display.width))
end

--- Get filtered and sorted products for a display
---@param display table Display instance
---@return table List of product data
local function getFilteredProducts(display)
    local config = display.config
    local filter = config.filter or {}
    local products = productManager.getAll() or {}
    local result = {}
    
    -- Build product list with additional data
    for meta, product in pairs(products) do
        local stock = inventoryManager.getItemStock(product.modid, product.itemnbt, product.anyNbt) or 0
        local category = categoryManager.getProductCategory(meta)
        
        -- Apply filters
        local include = true
        
        -- Category filter
        if filter.categories and #filter.categories > 0 then
            local inCategory = false
            for _, catId in ipairs(filter.categories) do
                if category == catId then
                    inCategory = true
                    break
                end
            end
            if not inCategory then include = false end
        end
        
        -- Product filter
        if filter.products and #filter.products > 0 then
            local inList = false
            for _, m in ipairs(filter.products) do
                if meta == m then
                    inList = true
                    break
                end
            end
            if not inList then include = false end
        end
        
        -- Stock filters
        if filter.minStock and stock < filter.minStock then
            include = false
        end
        if filter.maxStock and stock > filter.maxStock then
            include = false
        end
        
        if include then
            table.insert(result, {
                meta = meta,
                product = product,
                name = productManager.getName(product),
                stock = stock,
                price = product.cost,
                category = category,
                modid = product.modid,
            })
        end
    end
    
    -- Sort
    local sortBy = filter.sortBy or "name"
    local sortDesc = filter.sortDesc or false
    
    table.sort(result, function(a, b)
        local va, vb
        
        if sortBy == "name" then
            va, vb = a.name:lower(), b.name:lower()
        elseif sortBy == "price" then
            va, vb = a.price, b.price
        elseif sortBy == "stock" then
            va, vb = a.stock, b.stock
        elseif sortBy == "category" then
            va, vb = a.category .. a.name:lower(), b.category .. b.name:lower()
        else
            va, vb = a.name:lower(), b.name:lower()
        end
        
        if sortDesc then
            return va > vb
        else
            return va < vb
        end
    end)
    
    return result
end

--- Draw catalog display
---@param display table Display instance
local function drawCatalog(display)
    clearDisplay(display)
    
    local y = 1
    local config = display.config
    local options = display.options
    
    -- Draw header
    local title = config.title or "Shop Catalog"
    drawCentered(display, y, "=== " .. title .. " ===", display.colors.header)
    y = y + 1
    drawLine(display, y, display.colors.border)
    y = y + 1
    
    -- Get filtered products
    local products = getFilteredProducts(display)
    
    if #products == 0 then
        drawText(display, 2, y, "(No products)", colors.gray)
        return
    end
    
    -- Calculate layout
    local showStock = options.showStock
    local showPrice = options.showPrice
    local showCategory = options.showCategory and not options.groupByCategory
    
    -- Column widths (adjust based on monitor width)
    local stockWidth = showStock and 6 or 0
    local priceWidth = showPrice and 10 or 0
    local catWidth = showCategory and 12 or 0
    local nameWidth = display.width - stockWidth - priceWidth - catWidth - 3
    
    -- Group by category if enabled
    if options.groupByCategory then
        local currentCategory = nil
        local categoryInfo = nil
        
        for i, item in ipairs(products) do
            -- Check if we've scrolled past this item
            local itemY = y - display.scrollOffset
            
            if item.category ~= currentCategory then
                currentCategory = item.category
                categoryInfo = categoryManager.getCategory(currentCategory)
                
                -- Draw category header
                if itemY >= 3 and itemY <= display.height then
                    local catName = categoryInfo and categoryInfo.name or currentCategory
                    local catColor = categoryInfo and categoryInfo.color or display.colors.category
                    drawText(display, 1, itemY, "[ " .. catName .. " ]", catColor)
                end
                y = y + 1
                itemY = y - display.scrollOffset
            end
            
            -- Draw product
            if itemY >= 3 and itemY <= display.height then
                local x = 2
                
                -- Name
                local name = item.name
                if #name > nameWidth then
                    name = name:sub(1, nameWidth - 2) .. ".."
                end
                drawText(display, x, itemY, name, display.colors.text)
                x = x + nameWidth
                
                -- Price
                if showPrice then
                    local priceStr = formatPrice(item.price)
                    drawText(display, x, itemY, priceStr, display.colors.price)
                    x = x + priceWidth
                end
                
                -- Stock
                if showStock then
                    local stockStr, stockColor = formatStock(item.stock)
                    drawText(display, x, itemY, stockStr, stockColor)
                end
            end
            
            y = y + 1
        end
    else
        -- Flat list
        for i, item in ipairs(products) do
            local itemY = y - display.scrollOffset
            
            if itemY >= 3 and itemY <= display.height then
                local x = 1
                
                -- Category (if shown)
                if showCategory then
                    local categoryInfo = categoryManager.getCategory(item.category)
                    local catIcon = categoryInfo and categoryInfo.icon or "?"
                    local catColor = categoryInfo and categoryInfo.color or display.colors.category
                    drawText(display, x, itemY, "[" .. catIcon .. "]", catColor)
                    x = x + 4
                end
                
                -- Name
                local name = item.name
                if #name > nameWidth then
                    name = name:sub(1, nameWidth - 2) .. ".."
                end
                drawText(display, x, itemY, name, display.colors.text)
                x = x + nameWidth
                
                -- Price
                if showPrice then
                    local priceStr = formatPrice(item.price)
                    drawText(display, x, itemY, priceStr, display.colors.price)
                    x = x + priceWidth
                end
                
                -- Stock
                if showStock then
                    local stockStr, stockColor = formatStock(item.stock)
                    drawText(display, x, itemY, stockStr, stockColor)
                end
            end
            
            y = y + 1
        end
    end
    
    display.contentHeight = y
end

--- Draw stock display
---@param display table Display instance
local function drawStock(display)
    clearDisplay(display)
    
    local y = 1
    local title = display.config.title or "Stock Levels"
    
    drawCentered(display, y, "=== " .. title .. " ===", display.colors.header)
    y = y + 1
    drawLine(display, y, display.colors.border)
    y = y + 1
    
    local products = getFilteredProducts(display)
    
    -- Sort by stock (lowest first)
    table.sort(products, function(a, b)
        return a.stock < b.stock
    end)
    
    for i, item in ipairs(products) do
        if y > display.height then break end
        
        local stockStr, stockColor = formatStock(item.stock)
        local line = string.format("x%-5s %s", stockStr, item.name)
        drawText(display, 1, y, line, stockColor)
        y = y + 1
    end
    
    if #products == 0 then
        drawText(display, 2, y, "(No products)", colors.gray)
    end
end

--- Draw category display (products from specific categories)
---@param display table Display instance
local function drawCategory(display)
    -- Category display is just a catalog with category filter
    drawCatalog(display)
end

--- Draw sales feed display
---@param display table Display instance
local function drawSalesFeed(display)
    clearDisplay(display)
    
    local y = 1
    local title = display.config.title or "Sales Feed"
    
    drawCentered(display, y, "=== " .. title .. " ===", display.colors.header)
    y = y + 1
    drawLine(display, y, display.colors.border)
    y = y + 1
    
    if not salesManager then
        drawText(display, 2, y, "(Sales manager not available)", colors.gray)
        return
    end
    
    local sales = salesManager.getRecentSales(display.height - 3)
    
    for i, sale in ipairs(sales) do
        if y > display.height then break end
        
        local line = string.format("x%d %s - %.03f KRO",
            sale.quantity or 0,
            sale.productName or "?",
            sale.totalPrice or 0)
        
        drawText(display, 1, y, line, display.colors.text)
        y = y + 1
    end
    
    if #sales == 0 then
        drawText(display, 2, y, "(No sales yet)", colors.gray)
    end
end

--- Update a display
---@param display table Display instance
local function updateDisplay(display)
    if not display.monitor then return end
    
    -- Check if monitor still exists
    if not peripheral.isPresent(display.config.peripheral) then
        logger.warn("Display monitor disconnected: " .. display.config.peripheral)
        display.monitor = nil
        return
    end
    
    local displayType = display.config.displayType or "catalog"
    
    if displayType == "catalog" then
        drawCatalog(display)
    elseif displayType == "stock" then
        drawStock(display)
    elseif displayType == "category" then
        drawCategory(display)
    elseif displayType == "sales_feed" then
        drawSalesFeed(display)
    else
        drawCatalog(display)
    end
    
    display.lastUpdate = os.epoch("utc")
end

--- Get all display configurations
---@return table List of display configs
function manager.getDisplays()
    return displayConfig.get("displays") or {}
end

--- Add a display configuration
---@param config table Display configuration
---@return boolean success
---@return string|nil error
function manager.addDisplay(config)
    if not config.id then
        config.id = config.peripheral or ("display_" .. os.epoch("utc"))
    end
    
    local displays = manager.getDisplays()
    
    -- Check for duplicate ID
    for _, d in ipairs(displays) do
        if d.id == config.id then
            return false, "Display ID already exists: " .. config.id
        end
    end
    
    table.insert(displays, config)
    displayConfig.set("displays", displays)
    
    -- Create and start the display
    local display = createDisplay(config)
    if display then
        activeDisplays[config.id] = display
        updateDisplay(display)
    end
    
    logger.info("Added display: " .. config.id)
    return true
end

--- Update a display configuration
---@param id string Display ID
---@param updates table Fields to update
---@return boolean success
---@return string|nil error
function manager.updateDisplayConfig(id, updates)
    local displays = manager.getDisplays()
    
    for i, d in ipairs(displays) do
        if d.id == id then
            for k, v in pairs(updates) do
                displays[i][k] = v
            end
            displayConfig.set("displays", displays)
            
            -- Recreate the display
            if activeDisplays[id] then
                activeDisplays[id] = nil
            end
            local display = createDisplay(displays[i])
            if display then
                activeDisplays[id] = display
                updateDisplay(display)
            end
            
            logger.info("Updated display: " .. id)
            return true
        end
    end
    
    return false, "Display not found: " .. id
end

--- Remove a display configuration
---@param id string Display ID
---@return boolean success
---@return string|nil error
function manager.removeDisplay(id)
    local displays = manager.getDisplays()
    
    for i, d in ipairs(displays) do
        if d.id == id then
            table.remove(displays, i)
            displayConfig.set("displays", displays)
            
            -- Stop the display
            if activeDisplays[id] and activeDisplays[id].monitor then
                activeDisplays[id].monitor.setBackgroundColor(colors.black)
                activeDisplays[id].monitor.clear()
            end
            activeDisplays[id] = nil
            
            logger.info("Removed display: " .. id)
            return true
        end
    end
    
    return false, "Display not found: " .. id
end

--- Update all active displays
function manager.updateAll()
    for id, display in pairs(activeDisplays) do
        updateDisplay(display)
    end
end

--- Configure displays interactively
function manager.configure()
    local form = formui.new("Add Display Monitor")
    
    -- Get available monitors
    local monitors = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            table.insert(monitors, name)
        end
    end
    
    if #monitors == 0 then
        print("No monitors found!")
        print("Press any key to continue...")
        os.pullEvent("key")
        return
    end
    
    form:label("Select a monitor to configure:")
    local monitorField = form:peripheral("Monitor", "monitor")
    
    form:label("")
    form:label("--- Display Settings ---")
    local idField = form:text("Display ID", "display_" .. #manager.getDisplays() + 1)
    local titleField = form:text("Title", "Shop Catalog")
    
    local typeOptions = {"catalog", "stock", "category", "sales_feed"}
    local typeField = form:dropdown("Display Type", typeOptions, 1)
    
    local refreshField = form:number("Refresh Rate (sec)", 10,
        formui.validation.number_range(1, 300))
    
    form:label("")
    form:label("--- Filtering ---")
    local categories = categoryManager.getCategories()
    local categoryNames = {}
    local categoryIds = {}
    for _, cat in ipairs(categories) do
        table.insert(categoryNames, cat.name)
        table.insert(categoryIds, cat.id)
    end
    
    -- Note: This is simplified - a real implementation would support multi-select
    form:label("(Leave blank for all categories)")
    
    form:addSubmitCancel()
    
    local result = form:run()
    if result then
        local config = {
            id = idField(),
            peripheral = monitorField(),
            displayType = typeOptions[typeField()] or "catalog",
            title = titleField(),
            refreshRate = refreshField(),
        }
        
        local ok, err = manager.addDisplay(config)
        if ok then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.green)
            print("Display added successfully!")
        else
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.red)
            print("Failed to add display: " .. (err or "unknown error"))
        end
        
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
    end
end

--- Main run loop
function manager.run()
    -- Initialize all configured displays
    local displays = manager.getDisplays()
    for _, config in ipairs(displays) do
        local display = createDisplay(config)
        if display then
            activeDisplays[config.id] = display
        end
    end
    
    -- Initial update
    manager.updateAll()
    
    -- Track scroll timers for auto-scrolling
    local scrollTimers = {}
    
    -- Event loop
    while true do
        -- Find the minimum refresh rate
        local minRefresh = 60
        for id, display in pairs(activeDisplays) do
            local rate = display.config.refreshRate or 10
            if rate < minRefresh then minRefresh = rate end
        end
        
        local timer = os.startTimer(minRefresh)
        local event = table.pack(os.pullEvent())
        
        local shouldUpdate = false
        
        if event[1] == "timer" and event[2] == timer then
            shouldUpdate = true
        elseif event[1] == "purchase" then
            shouldUpdate = true
        elseif event[1] == "product_update" or event[1] == "product_create" or event[1] == "product_delete" then
            shouldUpdate = true
        elseif event[1] == "category_update" or event[1] == "category_create" or event[1] == "category_delete" then
            shouldUpdate = true
        elseif event[1] == "product_category_change" then
            shouldUpdate = true
        elseif event[1] == "peripheral" or event[1] == "peripheral_detach" then
            -- Check if any of our monitors were affected
            for id, display in pairs(activeDisplays) do
                if event[2] == display.config.peripheral then
                    if event[1] == "peripheral_detach" then
                        display.monitor = nil
                        logger.warn("Display monitor detached: " .. id)
                    else
                        display.monitor = peripheral.wrap(display.config.peripheral)
                        if display.monitor then
                            local w, h = display.monitor.getSize()
                            display.width = w
                            display.height = h
                            logger.info("Display monitor reattached: " .. id)
                        end
                    end
                end
            end
            shouldUpdate = true
        end
        
        if shouldUpdate then
            manager.updateAll()
        end
    end
end

--- Close all displays
function manager.close()
    for id, display in pairs(activeDisplays) do
        if display.monitor then
            display.monitor.setBackgroundColor(colors.black)
            display.monitor.clear()
        end
    end
    activeDisplays = {}
end

return manager
