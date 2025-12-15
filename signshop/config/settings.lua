--- SignShop Settings Configuration ---
--- Settings screens: Krist, modem, ShopSync, monitor, display, category configuration.
---
---@version 1.1.0

if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

local formui = require("lib.formui")

local settingsConfig = {}

--- Configure general shop settings
function settingsConfig.configureGeneral()
    local form = formui.new("General Shop Settings")
    
    local currentMaxStock = settings.get("signshop.max_stock_display") or 0
    
    form:label("--- Stock Display ---")
    form:label("Set max stock to limit displayed stock on signs/ShopSync")
    form:label("(0 = unlimited, shows actual stock)")
    local maxStockField = form:number("Max Stock Display", currentMaxStock,
        formui.validation.number_range(0, 999999))
    
    form:addSubmitCancel()
    
    local result = form:run()
    if result then
        settings.set("signshop.max_stock_display", maxStockField())
        settings.save()
        
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.green)
        print("General settings saved!")
        print("Restart SignShop for changes to take effect.")
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
    end
end

--- Configure Krist settings
function settingsConfig.configureKrist()
    local form = formui.new("Krist Settings")
    
    local currentSyncNode = settings.get("shopk.syncnode") or "https://kromer.reconnected.cc/api/krist/"
    local currentPrivate = settings.get("shopk.private") or ""
    
    local syncNodeField = form:text("Sync Node URL", currentSyncNode)
    local privateField = form:text("Private Key", currentPrivate)
    
    form:addSubmitCancel()
    
    local result = form:run()
    if result then
        settings.set("shopk.syncnode", syncNodeField())
        settings.set("shopk.private", privateField())
        settings.save()
        
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.green)
        print("Krist settings saved!")
        print("Restart SignShop for changes to take effect.")
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
    end
end

--- Configure modem settings
function settingsConfig.configureModem()
    local form = formui.new("Modem Settings")
    
    local currentModem = settings.get("modem.side") or ""
    local currentBroadcast = settings.get("modem.broadcast") or 8698
    local currentReceive = settings.get("modem.receive") or 9698
    local currentPing = settings.get("aisle.ping-frequency-sec") or 3
    
    local modemField = form:peripheral("Modem", "modem")
    local broadcastField = form:number("Broadcast Channel", currentBroadcast, 
        formui.validation.number_range(0, 65535))
    local receiveField = form:number("Receive Channel", currentReceive,
        formui.validation.number_range(0, 65535))
    local pingField = form:number("Ping Frequency (sec)", currentPing,
        formui.validation.number_range(1, 30))
    
    form:addSubmitCancel()
    
    local result = form:run()
    if result then
        settings.set("modem.side", modemField())
        settings.set("modem.broadcast", broadcastField())
        settings.set("modem.receive", receiveField())
        settings.set("aisle.ping-frequency-sec", pingField())
        settings.save()
        
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.green)
        print("Modem settings saved!")
        print("Restart SignShop for changes to take effect.")
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
    end
end

--- Configure ShopSync settings
function settingsConfig.configureShopSync()
    local form = formui.new("ShopSync Settings")
    
    local currentModem = settings.get("shopsync.modem") or ""
    local currentChannel = settings.get("shopsync.channel") or 9773
    local currentName = settings.get("shopsync.name") or ""
    local currentDesc = settings.get("shopsync.description") or ""
    local currentOwner = settings.get("shopsync.owner") or ""
    local currentLocDesc = settings.get("shopsync.location.description") or ""
    local currentDim = settings.get("shopsync.location.dimension") or "overworld"
    
    form:label("--- Network ---")
    local modemField = form:peripheral("Modem", "modem")
    local channelField = form:number("Channel", currentChannel,
        formui.validation.number_range(0, 65535))
    
    form:label("")
    form:label("--- Shop Info ---")
    local nameField = form:text("Shop Name", currentName)
    local descField = form:text("Description", currentDesc)
    local ownerField = form:text("Owner", currentOwner)
    
    form:label("")
    form:label("--- Location ---")
    local locDescField = form:text("Location Description", currentLocDesc)
    local dimField = form:text("Dimension", currentDim)
    
    form:addSubmitCancel()
    
    local result = form:run()
    if result then
        settings.set("shopsync.modem", modemField())
        settings.set("shopsync.channel", channelField())
        settings.set("shopsync.name", nameField())
        settings.set("shopsync.description", descField())
        settings.set("shopsync.owner", ownerField())
        settings.set("shopsync.location.description", locDescField())
        settings.set("shopsync.location.dimension", dimField())
        settings.save()
        
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.green)
        print("ShopSync settings saved!")
        print("Restart SignShop for changes to take effect.")
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
    end
end

--- Configure monitor settings
function settingsConfig.configureMonitor()
    local form = formui.new("Monitor Display Settings")
    
    local currentEnabled = settings.get("monitor.enabled") or false
    local currentSide = settings.get("monitor.side") or ""
    local currentRefresh = settings.get("monitor.refresh_rate") or 5
    
    -- Parse current sections string into individual booleans
    local currentSectionsStr = settings.get("monitor.show_sections") or "header,stats,recent_sales,low_stock,aisle_health"
    local currentSections = {}
    for section in currentSectionsStr:gmatch("[^,]+") do
        currentSections[section:match("^%s*(.-)%s*$")] = true
    end
    
    local enabledField = form:checkbox("Enable Monitor", currentEnabled)
    local sideField = form:peripheral("Monitor", "monitor", nil, currentSide)
    local refreshField = form:number("Refresh Rate (seconds)", currentRefresh,
        formui.validation.number_range(1, 60))
    
    form:label("")
    form:label("--- Display Sections ---")
    local headerField = form:checkbox("Show Header", currentSections.header ~= false)
    local statsField = form:checkbox("Show Today's Stats", currentSections.stats ~= false)
    local recentSalesField = form:checkbox("Show Recent Sales", currentSections.recent_sales ~= false)
    local lowStockField = form:checkbox("Show Low Stock Warnings", currentSections.low_stock ~= false)
    local aisleHealthField = form:checkbox("Show Aisle Health", currentSections.aisle_health ~= false)
    local topProductsField = form:checkbox("Show Top Products", currentSections.top_products or false)
    local topBuyersField = form:checkbox("Show Top Buyers", currentSections.top_buyers or false)
    
    form:label("")
    form:label("--- Colors ---")
    local bgColorField = form:color("Background Color", settings.get("monitor.colors.background") or colors.black)
    local headerColorField = form:color("Header Color", settings.get("monitor.colors.header") or colors.yellow)
    local textColorField = form:color("Text Color", settings.get("monitor.colors.text") or colors.white)
    local accentColorField = form:color("Accent Color", settings.get("monitor.colors.accent") or colors.lightBlue)
    
    form:addSubmitCancel()
    
    local result = form:run()
    if result then
        settings.set("monitor.enabled", enabledField())
        settings.set("monitor.side", sideField())
        settings.set("monitor.refresh_rate", refreshField())
        
        -- Build sections string from checkboxes
        local sections = {}
        if headerField() then table.insert(sections, "header") end
        if statsField() then table.insert(sections, "stats") end
        if recentSalesField() then table.insert(sections, "recent_sales") end
        if lowStockField() then table.insert(sections, "low_stock") end
        if aisleHealthField() then table.insert(sections, "aisle_health") end
        if topProductsField() then table.insert(sections, "top_products") end
        if topBuyersField() then table.insert(sections, "top_buyers") end
        settings.set("monitor.show_sections", table.concat(sections, ","))
        
        settings.set("monitor.colors.background", bgColorField())
        settings.set("monitor.colors.header", headerColorField())
        settings.set("monitor.colors.text", textColorField())
        settings.set("monitor.colors.accent", accentColorField())
        settings.save()
        
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.green)
        print("Monitor settings saved!")
        print("Restart SignShop for changes to take effect.")
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
    end
end

--- Configure display monitors
function settingsConfig.configureDisplays()
    local form = formui.new("Display Monitors Settings")
    
    local currentEnabled = settings.get("displays.enabled") or false
    
    local enabledField = form:checkbox("Enable Display Monitors", currentEnabled)
    
    form:label("")
    form:label("Display monitors show product catalogs")
    form:label("with prices, categories, and stock levels.")
    form:label("")
    form:label("After enabling, use the display manager")
    form:label("to add and configure individual monitors.")
    
    form:addSubmitCancel()
    
    local result = form:run()
    if result then
        settings.set("displays.enabled", enabledField())
        settings.save()
        
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.green)
        print("Display settings saved!")
        print("Restart SignShop for changes to take effect.")
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
    end
end

--- Configure categories
function settingsConfig.configureCategories()
    local categoryManager = require("managers.category")
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        print("=== Category Management ===")
        print("")
        term.setTextColor(colors.white)
        
        local categories = categoryManager.getCategories()
        print("Current categories:")
        for i, cat in ipairs(categories) do
            term.setTextColor(cat.color or colors.white)
            print(string.format("  %d. [%s] %s", i, cat.icon or "?", cat.name))
        end
        
        term.setTextColor(colors.white)
        print("")
        print("Options:")
        print("  1. Add category")
        print("  2. Edit category")
        print("  3. Delete category")
        print("  4. Assign product to category")
        print("  5. View products by category")
        print("  0. Back")
        print("")
        write("Select: ")
        
        local choice = read()
        
        if choice == "0" then
            return
        elseif choice == "1" then
            -- Add category
            local form = formui.new("Add Category")
            local idField = form:text("Category ID (unique)", "")
            local nameField = form:text("Display Name", "")
            local colorField = form:color("Color", colors.white)
            local iconField = form:text("Icon (1 char)", "?")
            form:addSubmitCancel()
            
            if form:run() then
                local id = idField()
                local name = nameField()
                local color = colorField()
                local icon = iconField():sub(1, 1)
                
                local ok, err = categoryManager.createCategory(id, name, color, icon)
                term.clear()
                term.setCursorPos(1, 1)
                if ok then
                    term.setTextColor(colors.green)
                    print("Category created: " .. name)
                else
                    term.setTextColor(colors.red)
                    print("Error: " .. (err or "unknown"))
                end
                term.setTextColor(colors.gray)
                print("\nPress any key to continue...")
                os.pullEvent("key")
            end
        elseif choice == "2" then
            -- Edit category
            write("Enter category ID to edit: ")
            local id = read()
            local cat = categoryManager.getCategory(id)
            
            if cat then
                local form = formui.new("Edit Category: " .. cat.name)
                local nameField = form:text("Display Name", cat.name)
                local colorField = form:color("Color", cat.color)
                local iconField = form:text("Icon (1 char)", cat.icon)
                form:addSubmitCancel()
                
                if form:run() then
                    local ok, err = categoryManager.updateCategory(id, {
                        name = nameField(),
                        color = colorField(),
                        icon = iconField():sub(1, 1),
                    })
                    term.clear()
                    term.setCursorPos(1, 1)
                    if ok then
                        term.setTextColor(colors.green)
                        print("Category updated!")
                    else
                        term.setTextColor(colors.red)
                        print("Error: " .. (err or "unknown"))
                    end
                    term.setTextColor(colors.gray)
                    print("\nPress any key to continue...")
                    os.pullEvent("key")
                end
            else
                term.setTextColor(colors.red)
                print("Category not found: " .. id)
                term.setTextColor(colors.gray)
                print("\nPress any key to continue...")
                os.pullEvent("key")
            end
        elseif choice == "3" then
            -- Delete category
            write("Enter category ID to delete: ")
            local id = read()
            
            local ok, err = categoryManager.deleteCategory(id)
            term.clear()
            term.setCursorPos(1, 1)
            if ok then
                term.setTextColor(colors.green)
                print("Category deleted!")
            else
                term.setTextColor(colors.red)
                print("Error: " .. (err or "unknown"))
            end
            term.setTextColor(colors.gray)
            print("\nPress any key to continue...")
            os.pullEvent("key")
        elseif choice == "4" then
            -- Assign product to category
            local productManager = require("managers.product")
            local products = productManager.getAll() or {}
            
            term.clear()
            term.setCursorPos(1, 1)
            print("Available products:")
            local productList = {}
            for meta, product in pairs(products) do
                table.insert(productList, {meta = meta, name = productManager.getName(product)})
            end
            table.sort(productList, function(a, b) return a.name < b.name end)
            
            for i, p in ipairs(productList) do
                local currentCat = categoryManager.getProductCategory(p.meta)
                print(string.format("  %s [%s]", p.name, currentCat))
            end
            
            print("")
            write("Enter product meta: ")
            local meta = read()
            
            if products[meta] then
                print("")
                print("Available categories:")
                for _, cat in ipairs(categories) do
                    print(string.format("  %s - %s", cat.id, cat.name))
                end
                print("")
                write("Enter category ID: ")
                local catId = read()
                
                local ok, err = categoryManager.setProductCategory(meta, catId)
                term.clear()
                term.setCursorPos(1, 1)
                if ok then
                    term.setTextColor(colors.green)
                    print("Product assigned to category!")
                else
                    term.setTextColor(colors.red)
                    print("Error: " .. (err or "unknown"))
                end
            else
                term.setTextColor(colors.red)
                print("Product not found!")
            end
            term.setTextColor(colors.gray)
            print("\nPress any key to continue...")
            os.pullEvent("key")
        elseif choice == "5" then
            -- View products by category
            local productManager = require("managers.product")
            local byCategory = categoryManager.getProductsByCategory()
            
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            print("=== Products by Category ===")
            print("")
            
            for _, cat in ipairs(categories) do
                term.setTextColor(cat.color or colors.white)
                print("[" .. cat.icon .. "] " .. cat.name .. ":")
                term.setTextColor(colors.white)
                
                local prods = byCategory[cat.id] or {}
                if #prods == 0 then
                    print("  (empty)")
                else
                    for _, meta in ipairs(prods) do
                        local product = productManager.get(meta)
                        if product then
                            print("  - " .. productManager.getName(product))
                        end
                    end
                end
                print("")
            end
            
            term.setTextColor(colors.gray)
            print("Press any key to continue...")
            os.pullEvent("key")
        end
    end
end

return settingsConfig
