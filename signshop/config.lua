--- SignShop Configuration UI ---
--- Interactive configuration interface for SignShop using formui.
---
---@version 1.1.0

if not package.path:find("disk") then
    package.path = package.path .. ";disk/?.lua;disk/lib/?.lua"
end

local formui = require("lib.formui")

local productManager = require("managers.product")
local inventoryManager = require("managers.inventory")
local aisleManager = require("managers.aisle")
local signManager = require("managers.sign")

local VERSION = ssVersion and ssVersion() or "1.1.0"

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
        { separator = true, label = "--- Products ---" },
        { label = "View Products", action = "products" },
        { label = "Add Product", action = "add_product" },
        { label = "Edit Product", action = "edit_product" },
        { label = "Delete Product", action = "delete_product" },
        { separator = true, label = "--- Signs ---" },
        { label = "View Signs", action = "view_signs" },
        { label = "Update All Signs", action = "signs" },
        { label = "Refresh Sign for Product", action = "refresh_product_sign" },
        { separator = true, label = "--- Aisles ---" },
        { label = "View Aisles", action = "aisles" },
        { label = "Update All Aisles", action = "update_aisles" },
        { separator = true, label = "--- Inventory ---" },
        { label = "Rescan Inventory", action = "rescan" },
        { separator = true, label = "--- Settings ---" },
        { label = "Krist Settings", action = "krist" },
        { label = "Modem Settings", action = "modem" },
        { label = "ShopSync Settings", action = "shopsync" },
        { separator = true, label = "" },
        { label = "Exit", action = "exit" },
    })
end

--- Build a list of product options for menu selection
---@return table options Array of {label, action, product} for menu
local function getProductOptions()
    local products = productManager.getAll()
    local options = {}
    
    if products then
        for meta, product in pairs(products) do
            local stock = inventoryManager.getItemStock(product.modid, product.itemnbt) or 0
            local label = string.format("%s [%s] - %.03f KRO (Stock: %d)",
                productManager.getName(product), meta, product.cost, stock)
            table.insert(options, { label = label, action = meta, product = product })
        end
    end
    
    -- Sort by name
    table.sort(options, function(a, b) 
        return productManager.getName(a.product) < productManager.getName(b.product) 
    end)
    
    return options
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
            term.setTextColor(colors.gray)
            print(string.format("  ModID: %s", product.modid or "unknown"))
        end
        term.setTextColor(colors.lightGray)
        print("\nTotal: " .. count .. " product(s)")
    end
    
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

--- Add a new product
local function addProduct()
    local form = formui.new("Add New Product")
    
    -- Get available aisles for dropdown
    local aisles = aisleManager.getAisles() or {}
    local aisleNames = {}
    for name, _ in pairs(aisles) do
        table.insert(aisleNames, name)
    end
    table.sort(aisleNames)
    
    local metaField = form:text("Meta (unique ID)", "")
    local line1Field = form:text("Line 1 (name)", "")
    local line2Field = form:text("Line 2 (desc)", "")
    local costField = form:number("Cost (KRO)", 0.001, formui.validation.number_range(0.001, 999999))
    local aisleField = form:text("Aisle Name", aisleNames[1] or "")
    local modidField = form:text("Mod ID (e.g., minecraft:diamond)", "")
    
    form:addSubmitCancel()
    
    local result = form:run()
    if result then
        local meta = metaField()
        if meta == "" then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.red)
            print("Error: Meta cannot be empty!")
            term.setTextColor(colors.gray)
            print("\nPress any key to continue...")
            os.pullEvent("key")
            return
        end
        
        local product = {
            meta = meta,
            line1 = line1Field(),
            line2 = line2Field(),
            cost = costField(),
            aisleName = aisleField(),
            modid = modidField()
        }
        
        productManager.set(meta, product)
        os.queueEvent("product_create", product)
        
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.green)
        print("Product added successfully!")
        print("Run 'Update All Signs' to update shop signs.")
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
    end
end

--- Select a product from the list
---@param title string Title for selection menu
---@return table|nil product The selected product or nil
local function selectProduct(title)
    local options = getProductOptions()
    
    if #options == 0 then
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.red)
        print("No products found!")
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
        return nil
    end
    
    table.insert(options, 1, { separator = true, label = "Select a product:" })
    table.insert(options, { separator = true, label = "" })
    table.insert(options, { label = "Cancel", action = "cancel" })
    
    local action = showMenu(title, options)
    
    if action == "cancel" or action == nil then
        return nil
    end
    
    return productManager.get(action)
end

--- Edit an existing product
local function editProduct()
    local product = selectProduct("Edit Product")
    if not product then return end
    
    local form = formui.new("Edit Product: " .. productManager.getName(product))
    
    local metaField = form:text("Meta (unique ID)", product.meta)
    local line1Field = form:text("Line 1 (name)", product.line1)
    local line2Field = form:text("Line 2 (desc)", product.line2)
    local costField = form:number("Cost (KRO)", product.cost, formui.validation.number_range(0.001, 999999))
    local aisleField = form:text("Aisle Name", product.aisleName)
    local modidField = form:text("Mod ID", product.modid or "")
    
    form:addSubmitCancel()
    
    local result = form:run()
    if result then
        local newProduct = {
            meta = metaField(),
            line1 = line1Field(),
            line2 = line2Field(),
            cost = costField(),
            aisleName = aisleField(),
            modid = modidField(),
            itemnbt = product.itemnbt  -- Preserve NBT if exists
        }
        
        local success, err = productManager:updateItem(product, newProduct)
        
        term.clear()
        term.setCursorPos(1, 1)
        if success then
            term.setTextColor(colors.green)
            print("Product updated successfully!")
            print("Signs will be updated automatically.")
        else
            term.setTextColor(colors.red)
            print("Error updating product:")
            print(err or "Unknown error")
        end
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
    end
end

--- Delete a product
local function deleteProduct()
    local product = selectProduct("Delete Product")
    if not product then return end
    
    -- Confirmation
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("=== DELETE PRODUCT ===")
    term.setTextColor(colors.white)
    print()
    print("Product: " .. productManager.getName(product))
    print("Meta: " .. product.meta)
    print("Cost: " .. product.cost .. " KRO")
    print()
    term.setTextColor(colors.yellow)
    print("Are you sure you want to delete this product?")
    print("This action cannot be undone!")
    print()
    term.setTextColor(colors.white)
    print("Press Y to confirm, any other key to cancel")
    
    local _, key = os.pullEvent("key")
    if key == keys.y then
        productManager.unset(product.meta)
        os.queueEvent("product_delete", product)
        
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.green)
        print("Product deleted successfully!")
    else
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        print("Deletion cancelled.")
    end
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

--- View all signs
local function viewSigns()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("=== Shop Signs ===")
    term.setTextColor(colors.white)
    
    local signs = table.pack(peripheral.find("minecraft:sign"))
    
    if #signs == 0 then
        print("No signs found.")
    else
        for i, sign in ipairs(signs) do
            local data = sign.getSignText()
            local meta = data[4]
            local product = productManager.get(meta)
            
            term.setTextColor(colors.lightBlue)
            write(peripheral.getName(sign))
            term.setTextColor(colors.gray)
            
            if product then
                write(" -> ")
                term.setTextColor(colors.white)
                print(productManager.getName(product))
            elseif meta and #meta > 0 then
                write(" -> ")
                term.setTextColor(colors.red)
                print("Unknown: " .. meta)
            else
                term.setTextColor(colors.gray)
                print(" (no product)")
            end
        end
        term.setTextColor(colors.lightGray)
        print("\nTotal: " .. #signs .. " sign(s)")
    end
    
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

--- Refresh signs for a specific product
local function refreshProductSign()
    local product = selectProduct("Refresh Sign for Product")
    if not product then return end
    
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("Refreshing signs for " .. productManager.getName(product) .. "...")
    term.setTextColor(colors.white)
    
    signManager.updateItemSigns(product)
    
    term.setTextColor(colors.green)
    print("Done!")
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
        elseif action == "add_product" then
            addProduct()
        elseif action == "edit_product" then
            editProduct()
        elseif action == "delete_product" then
            deleteProduct()
        elseif action == "view_signs" then
            viewSigns()
        elseif action == "refresh_product_sign" then
            refreshProductSign()
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
