--- SignShop Configuration UI ---
--- Interactive configuration interface for SignShop using formui.
---
---@version 1.0.0

if not package.path:find("disk") then
    package.path = package.path .. ";disk/?.lua;disk/lib/?.lua"
end

local formui = require("lib.formui")

local productManager = require("managers.product")
local inventoryManager = require("managers.inventory")
local aisleManager = require("managers.aisle")

local VERSION = ssVersion and ssVersion() or "1.0.0"

local config = {}

--- Display a simple menu with arrow key navigation
---@param title string Menu title
---@param options table Array of {label, action} pairs
---@return string|nil action The selected action or nil if cancelled
local function showMenu(title, options)
    local selected = 1
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        
        -- Draw title
        term.setTextColor(colors.yellow)
        term.setCursorPos(math.floor((w - #title) / 2), 1)
        print(title)
        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        print()
        
        -- Draw options
        for i, opt in ipairs(options) do
            if opt.separator then
                term.setTextColor(colors.gray)
                print()
                if opt.label ~= "" then
                    print(opt.label)
                end
            else
                if i == selected then
                    term.setTextColor(colors.black)
                    term.setBackgroundColor(colors.white)
                    write("> " .. opt.label .. " ")
                    term.setBackgroundColor(colors.black)
                    print()
                else
                    term.setTextColor(colors.white)
                    print("  " .. opt.label)
                end
            end
        end
        
        -- Draw help
        term.setCursorPos(1, h - 1)
        term.setTextColor(colors.gray)
        print("Up/Down: Navigate | Enter: Select | Q: Exit")
        
        -- Handle input
        local e, key = os.pullEvent("key")
        if key == keys.up then
            repeat
                selected = selected - 1
                if selected < 1 then selected = #options end
            until not options[selected].separator
        elseif key == keys.down then
            repeat
                selected = selected + 1
                if selected > #options then selected = 1 end
            until not options[selected].separator
        elseif key == keys.enter then
            return options[selected].action
        elseif key == keys.q then
            return nil
        end
    end
end

--- Display the main menu
---@return string|nil action The selected action or nil if cancelled
local function mainMenu()
    return showMenu("SignShop v" .. VERSION, {
        { separator = true, label = "--- Actions ---" },
        { label = "View Products", action = "products" },
        { label = "View Aisles", action = "aisles" },
        { label = "Rescan Inventory", action = "rescan" },
        { label = "Update All Signs", action = "signs" },
        { label = "Update All Aisles", action = "update_aisles" },
        { separator = true, label = "--- Settings ---" },
        { label = "Krist Settings", action = "krist" },
        { label = "Modem Settings", action = "modem" },
        { label = "ShopSync Settings", action = "shopsync" },
        { separator = true, label = "" },
        { label = "Exit", action = "exit" },
    })
end

--- Display the products list
local function showProducts()
    local products = productManager.getAll()
    
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("=== Products ===")
    term.setTextColor(colors.white)
    
    if not products or not next(products) then
        print("No products found.")
    else
        local count = 0
        for meta, product in pairs(products) do
            count = count + 1
            local stock = inventoryManager.getItemStock(product.modid, product.itemnbt) or 0
            term.setTextColor(colors.lightBlue)
            write(productManager.getName(product))
            term.setTextColor(colors.gray)
            write(" [" .. meta .. "]")
            term.setTextColor(colors.white)
            print()
            print(string.format("  Cost: %.03f KRO | Stock: %d | Aisle: %s", 
                product.cost, stock, product.aisleName))
        end
        term.setTextColor(colors.lightGray)
        print("\nTotal: " .. count .. " product(s)")
    end
    
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

--- Display the aisles list
local function showAisles()
    local aisles = aisleManager.getAisles()
    
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("=== Aisles ===")
    term.setTextColor(colors.white)
    
    if not aisles or not next(aisles) then
        print("No aisles found.")
        print("Make sure aisle turtles are running!")
    else
        local count = 0
        for name, aisle in pairs(aisles) do
            count = count + 1
            local lastSeen = aisle.lastSeen and os.epoch("utc") - aisle.lastSeen or nil
            local status = "unknown"
            if lastSeen then
                if lastSeen < 10000 then
                    status = "online"
                    term.setTextColor(colors.green)
                elseif lastSeen < 60000 then
                    status = "stale"
                    term.setTextColor(colors.yellow)
                else
                    status = "offline"
                    term.setTextColor(colors.red)
                end
            else
                term.setTextColor(colors.gray)
            end
            
            write(name)
            term.setTextColor(colors.gray)
            write(" - ")
            term.setTextColor(status == "online" and colors.green or 
                             status == "stale" and colors.yellow or 
                             status == "offline" and colors.red or colors.gray)
            print(status)
            term.setTextColor(colors.white)
            if aisle.self then
                print("  Turtle: " .. aisle.self)
            end
        end
        term.setTextColor(colors.lightGray)
        print("\nTotal: " .. count .. " aisle(s)")
    end
    
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

--- Rescan inventory
local function rescanInventory()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("Rescanning inventory...")
    term.setTextColor(colors.white)
    
    inventoryManager.rescan()
    
    term.setTextColor(colors.green)
    print("Done!")
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

--- Update all signs
local function updateSigns()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("Updating all signs...")
    term.setTextColor(colors.white)
    
    local signManager = require("managers.sign")
    signManager.updateAll()
    
    term.setTextColor(colors.green)
    print("Done!")
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

--- Update all aisles (send update command)
local function updateAisles()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("Sending update command to all aisles...")
    term.setTextColor(colors.white)
    
    aisleManager.updateAisles()
    
    term.setTextColor(colors.green)
    print("Update command sent!")
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

--- Configure Krist settings
local function configureKrist()
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
local function configureModem()
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
local function configureShopSync()
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

--- Main configuration loop
function config.run()
    while true do
        local action = mainMenu()
        
        if action == "products" then
            showProducts()
        elseif action == "aisles" then
            showAisles()
        elseif action == "rescan" then
            rescanInventory()
        elseif action == "signs" then
            updateSigns()
        elseif action == "update_aisles" then
            updateAisles()
        elseif action == "krist" then
            configureKrist()
        elseif action == "modem" then
            configureModem()
        elseif action == "shopsync" then
            configureShopSync()
        elseif action == "exit" or action == nil then
            term.clear()
            term.setCursorPos(1, 1)
            break
        end
    end
end

return config
