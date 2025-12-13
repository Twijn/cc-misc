--- SignShop Settings Configuration ---
--- Settings screens: Krist, modem, ShopSync, monitor configuration.
---
---@version 1.0.0

if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

local formui = require("lib.formui")

local settingsConfig = {}

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

return settingsConfig
