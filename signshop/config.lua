--- SignShop Configuration UI ---
--- Interactive configuration interface for SignShop using formui.
---
---@version 1.4.0

if not package.path:find("disk") then
    package.path = package.path .. ";disk/?.lua;disk/lib/?.lua"
end

local formui = require("lib.formui")

local productManager = require("managers.product")
local inventoryManager = require("managers.inventory")
local aisleManager = require("managers.aisle")
local signManager = require("managers.sign")
local salesManager = require("managers.sales")

local VERSION = ssVersion and ssVersion() or "unknown"

local config = {}

--- Display a simple menu with arrow key navigation and scrolling
---@param title string Menu title
---@param options table Array of {label, action} pairs
---@return string|nil action The selected action or nil if cancelled
local function showMenu(title, options)
    local selected = 1
    local scroll = 0
    
    -- Find first non-separator option
    while options[selected] and options[selected].separator do
        selected = selected + 1
    end
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3  -- title + separator + blank line
        local footerHeight = 2  -- help text
        local visibleHeight = h - headerHeight - footerHeight
        
        -- Draw title
        term.setTextColor(colors.yellow)
        term.setCursorPos(math.floor((w - #title) / 2), 1)
        print(title)
        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        print()
        
        -- Calculate which items to show (flattened view for scrolling)
        local displayLines = {}
        for i, opt in ipairs(options) do
            if opt.separator then
                if opt.label ~= "" then
                    table.insert(displayLines, { type = "separator", label = opt.label, index = i })
                else
                    table.insert(displayLines, { type = "blank", index = i })
                end
            else
                table.insert(displayLines, { type = "option", label = opt.label, index = i, action = opt.action })
            end
        end
        
        -- Find which display line corresponds to selected option
        local selectedDisplayLine = 1
        for i, line in ipairs(displayLines) do
            if line.index == selected then
                selectedDisplayLine = i
                break
            end
        end
        
        -- Adjust scroll to keep selection visible
        if selectedDisplayLine <= scroll then
            scroll = selectedDisplayLine - 1
        elseif selectedDisplayLine > scroll + visibleHeight then
            scroll = selectedDisplayLine - visibleHeight
        end
        
        -- Draw visible items
        local drawnLines = 0
        for i = scroll + 1, math.min(#displayLines, scroll + visibleHeight) do
            local line = displayLines[i]
            drawnLines = drawnLines + 1
            
            if line.type == "blank" then
                print()
            elseif line.type == "separator" then
                term.setTextColor(colors.gray)
                print(line.label)
            else
                if line.index == selected then
                    term.setTextColor(colors.black)
                    term.setBackgroundColor(colors.white)
                    local displayLabel = line.label
                    if #displayLabel > w - 3 then
                        displayLabel = displayLabel:sub(1, w - 6) .. "..."
                    end
                    write("> " .. displayLabel .. " ")
                    term.setBackgroundColor(colors.black)
                    print()
                else
                    term.setTextColor(colors.white)
                    local displayLabel = line.label
                    if #displayLabel > w - 3 then
                        displayLabel = displayLabel:sub(1, w - 6) .. "..."
                    end
                    print("  " .. displayLabel)
                end
            end
        end
        
        -- Draw scroll indicators if needed
        term.setTextColor(colors.gray)
        if scroll > 0 then
            term.setCursorPos(w, headerHeight + 1)
            write("^")
        end
        if scroll + visibleHeight < #displayLines then
            term.setCursorPos(w, h - footerHeight)
            write("v")
        end
        
        -- Draw help
        term.setCursorPos(1, h - 1)
        term.setTextColor(colors.gray)
        print("Up/Down: Navigate | Enter: Select | Q: Back")
        
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
        elseif key == keys.pageUp then
            for _ = 1, visibleHeight - 1 do
                repeat
                    selected = selected - 1
                    if selected < 1 then selected = #options end
                until not options[selected].separator
            end
        elseif key == keys.pageDown then
            for _ = 1, visibleHeight - 1 do
                repeat
                    selected = selected + 1
                    if selected > #options then selected = 1 end
                until not options[selected].separator
            end
        elseif key == keys.home then
            selected = 1
            while options[selected] and options[selected].separator do
                selected = selected + 1
            end
        elseif key == keys["end"] then
            selected = #options
            while options[selected] and options[selected].separator do
                selected = selected - 1
            end
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
        { separator = true, label = "--- Sales ---" },
        { label = "View Sales Dashboard", action = "sales_dashboard" },
        { label = "Recent Sales", action = "recent_sales" },
        { label = "Top Products", action = "top_products" },
        { label = "Top Buyers", action = "top_buyers" },
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

-- Forward declarations for functions that reference each other
local addProduct
local viewProductDetails
local showProducts

--- View product details
---@param product table The product to view
viewProductDetails = function(product)
    local scroll = 0
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3
        local footerHeight = 2
        local visibleHeight = h - headerHeight - footerHeight
        local stock = inventoryManager.getItemStock(product.modid, product.itemnbt) or 0
        
        -- Build content lines
        local contentLines = {}
        
        table.insert(contentLines, { label = "Name: ", value = productManager.getName(product), labelColor = colors.lightBlue, valueColor = colors.white })
        table.insert(contentLines, { label = "Meta: ", value = product.meta, labelColor = colors.lightBlue, valueColor = colors.gray })
        table.insert(contentLines, { text = "", color = colors.white })
        table.insert(contentLines, { label = "Line 1: ", value = product.line1, labelColor = colors.lightBlue, valueColor = colors.white })
        table.insert(contentLines, { label = "Line 2: ", value = product.line2 or "", labelColor = colors.lightBlue, valueColor = colors.white })
        table.insert(contentLines, { text = "", color = colors.white })
        table.insert(contentLines, { label = "Cost: ", value = string.format("%.03f KRO", product.cost), labelColor = colors.lightBlue, valueColor = colors.green })
        table.insert(contentLines, { label = "Aisle: ", value = product.aisleName, labelColor = colors.lightBlue, valueColor = colors.white })
        table.insert(contentLines, { label = "Stock: ", value = tostring(stock), labelColor = colors.lightBlue, valueColor = stock > 0 and colors.green or colors.red })
        table.insert(contentLines, { text = "", color = colors.white })
        table.insert(contentLines, { label = "Mod ID: ", value = product.modid or "unknown", labelColor = colors.lightBlue, valueColor = colors.gray })
        
        if product.itemnbt then
            table.insert(contentLines, { label = "NBT: ", value = product.itemnbt, labelColor = colors.lightBlue, valueColor = colors.gray })
        end
        
        table.insert(contentLines, { text = "", color = colors.white })
        table.insert(contentLines, { text = string.rep("-", w), color = colors.gray })
        table.insert(contentLines, { text = "Actions:", color = colors.yellow })
        table.insert(contentLines, { text = "  [E] Edit product", color = colors.white })
        table.insert(contentLines, { text = "  [R] Refresh signs", color = colors.white })
        table.insert(contentLines, { text = "  [D] Delete product", color = colors.white })
        table.insert(contentLines, { text = "  [Q] Back to product list", color = colors.white })
        
        local totalLines = #contentLines
        
        -- Clamp scroll
        scroll = math.max(0, math.min(scroll, math.max(0, totalLines - visibleHeight)))
        
        -- Title
        term.setTextColor(colors.yellow)
        print("=== Product Details ===")
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
        print("Up/Down: Scroll | E/R/D/Q: Actions")
        
        local e, key = os.pullEvent("key")
        if key == keys.up then
            scroll = scroll - 1
        elseif key == keys.down then
            scroll = scroll + 1
        elseif key == keys.pageUp then
            scroll = scroll - (visibleHeight - 1)
        elseif key == keys.pageDown then
            scroll = scroll + (visibleHeight - 1)
        elseif key == keys.q then
            return nil
        elseif key == keys.r then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            print("Refreshing signs for " .. productManager.getName(product) .. "...")
            signManager.updateItemSigns(product)
            term.setTextColor(colors.green)
            print("Done!")
            sleep(0.5)
        elseif key == keys.d then
            -- Delete confirmation
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.red)
            print("=== DELETE PRODUCT ===")
            term.setTextColor(colors.white)
            print()
            print("Product: " .. productManager.getName(product))
            print("Meta: " .. product.meta)
            print()
            term.setTextColor(colors.yellow)
            print("Are you sure? Press Y to confirm.")
            
            local _, confirmKey = os.pullEvent("key")
            if confirmKey == keys.y then
                productManager.unset(product.meta)
                os.queueEvent("product_delete", product)
                term.setTextColor(colors.green)
                print("\nProduct deleted!")
                sleep(0.5)
                return "deleted"
            end
        elseif key == keys.e then
            local form = formui.new("Edit Product: " .. productManager.getName(product))
            
            local metaField = form:text("Meta (unique ID)", product.meta)
            local line1Field = form:text("Line 1 (name)", product.line1)
            local line2Field = form:text("Line 2 (desc)", product.line2, nil, true)
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
                    itemnbt = product.itemnbt
                }
                
                local success, err = productManager:updateItem(product, newProduct)
                
                term.clear()
                term.setCursorPos(1, 1)
                if success then
                    term.setTextColor(colors.green)
                    print("Product updated!")
                    -- Update our local reference
                    for k, v in pairs(newProduct) do
                        product[k] = v
                    end
                else
                    term.setTextColor(colors.red)
                    print("Error: " .. (err or "Unknown"))
                end
                sleep(0.5)
            end
        end
    end
end

--- Display the products list with interactive menu
showProducts = function()
    while true do
        -- Show loading screen
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        print("Loading products...")
        term.setTextColor(colors.gray)
        print("Please wait...")
        
        local options = getProductOptions()
        
        if #options == 0 then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.red)
            print("No products found!")
            term.setTextColor(colors.gray)
            print("\nPress any key to continue...")
            os.pullEvent("key")
            return
        end
        
        -- Group by aisle
        local byAisle = {}
        for _, opt in ipairs(options) do
            local aisle = opt.product.aisleName or "Unknown"
            if not byAisle[aisle] then
                byAisle[aisle] = {}
            end
            table.insert(byAisle[aisle], opt)
        end
        
        -- Get sorted aisle names
        local aisleNames = {}
        for name, _ in pairs(byAisle) do
            table.insert(aisleNames, name)
        end
        table.sort(aisleNames)
        
        -- Build menu with aisle grouping
        local menuOptions = {
            { separator = true, label = string.format("Total: %d products", #options) },
        }
        
        for _, aisleName in ipairs(aisleNames) do
            table.insert(menuOptions, { separator = true, label = "--- " .. aisleName .. " ---" })
            for _, opt in ipairs(byAisle[aisleName]) do
                -- Shorter label for menu
                local stock = inventoryManager.getItemStock(opt.product.modid, opt.product.itemnbt) or 0
                local label = string.format("%s - %.03f KRO (x%d)",
                    productManager.getName(opt.product), opt.product.cost, stock)
                table.insert(menuOptions, { 
                    label = label, 
                    action = opt.action, 
                    product = opt.product 
                })
            end
        end
        
        table.insert(menuOptions, { separator = true, label = "" })
        table.insert(menuOptions, { label = "Add New Product", action = "add" })
        table.insert(menuOptions, { label = "Back to Main Menu", action = "back" })
        
        local action = showMenu("Products", menuOptions)
        
        if action == "back" or action == nil then
            return
        elseif action == "add" then
            addProduct()
        else
            -- Find and view the selected product
            local product = productManager.get(action)
            if product then
                local result = viewProductDetails(product)
                if result == "deleted" then
                    -- Product was deleted, refresh the list
                end
            end
        end
    end
end

--- Add a new product
addProduct = function()
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
    local line2Field = form:text("Line 2 (desc)", "", nil, true)
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
    -- Show loading screen
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("Loading products...")
    term.setTextColor(colors.gray)
    print("Please wait...")
    
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
    local line2Field = form:text("Line 2 (desc)", product.line2, nil, true)
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

--- Build sign options for menu selection
---@return table options Array of sign options for menu
local function getSignOptions()
    local signs = table.pack(peripheral.find("minecraft:sign"))
    local options = {}
    local signData = {}
    
    -- Read all sign texts in parallel for better performance
    local tasks = {}
    for i, sign in ipairs(signs) do
        tasks[i] = function()
            signData[i] = sign.getSignText()
        end
    end
    if #tasks > 0 then
        parallel.waitForAll(table.unpack(tasks))
    end
    
    -- Process sign data (no peripheral calls, fast)
    for i, sign in ipairs(signs) do
        local signName = peripheral.getName(sign)
        local data = signData[i]
        local meta = data[4]
        local product = productManager.get(meta)
        
        local label
        local status
        if product then
            local stock = inventoryManager.getItemStock(product.modid, product.itemnbt) or 0
            label = string.format("%s -> %s (Stock: %d)", signName, productManager.getName(product), stock)
            status = "linked"
        elseif meta and #meta > 0 then
            label = string.format("%s -> UNKNOWN: %s", signName, meta)
            status = "unknown"
        else
            label = string.format("%s (no product)", signName)
            status = "empty"
        end
        
        table.insert(options, {
            label = label,
            action = signName,
            sign = sign,
            signName = signName,
            product = product,
            meta = meta,
            status = status
        })
    end
    
    -- Sort by status (linked first, then unknown, then empty)
    table.sort(options, function(a, b)
        local statusOrder = { linked = 1, unknown = 2, empty = 3 }
        if statusOrder[a.status] ~= statusOrder[b.status] then
            return statusOrder[a.status] < statusOrder[b.status]
        end
        return a.signName < b.signName
    end)
    
    return options
end

--- View sign details
---@param signOpt table Sign option from getSignOptions
local function viewSignDetails(signOpt)
    local sign = signOpt.sign
    local data = sign.getSignText()
    local scroll = 0
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3
        local footerHeight = 2
        local visibleHeight = h - headerHeight - footerHeight
        
        -- Build content lines
        local contentLines = {}
        
        table.insert(contentLines, { label = "Peripheral: ", value = signOpt.signName, labelColor = colors.lightBlue, valueColor = colors.white })
        table.insert(contentLines, { text = "", color = colors.white })
        table.insert(contentLines, { text = "Current Sign Text:", color = colors.yellow })
        table.insert(contentLines, { text = string.rep("-", 20), color = colors.gray })
        for i, line in ipairs(data) do
            table.insert(contentLines, { text = line ~= "" and line or "(empty)", color = colors.white })
        end
        table.insert(contentLines, { text = string.rep("-", 20), color = colors.gray })
        table.insert(contentLines, { text = "", color = colors.white })
        
        -- Product info
        if signOpt.product then
            local stock = inventoryManager.getItemStock(signOpt.product.modid, signOpt.product.itemnbt) or 0
            table.insert(contentLines, { text = "Linked Product:", color = colors.green })
            table.insert(contentLines, { text = "  Name: " .. productManager.getName(signOpt.product), color = colors.white })
            table.insert(contentLines, { text = "  Meta: " .. signOpt.product.meta, color = colors.white })
            table.insert(contentLines, { text = "  Cost: " .. signOpt.product.cost .. " KRO", color = colors.white })
            table.insert(contentLines, { text = "  Aisle: " .. signOpt.product.aisleName, color = colors.white })
            table.insert(contentLines, { text = "  Stock: " .. stock, color = stock > 0 and colors.green or colors.red })
        elseif signOpt.meta and #signOpt.meta > 0 then
            table.insert(contentLines, { text = "Unknown Product Meta: " .. signOpt.meta, color = colors.red })
            table.insert(contentLines, { text = "This sign references a product that doesn't exist.", color = colors.gray })
        else
            table.insert(contentLines, { text = "No product linked to this sign.", color = colors.gray })
        end
        
        -- Actions
        table.insert(contentLines, { text = "", color = colors.white })
        table.insert(contentLines, { text = string.rep("-", w), color = colors.gray })
        table.insert(contentLines, { text = "Actions:", color = colors.yellow })
        if signOpt.product then
            table.insert(contentLines, { text = "  [R] Refresh this sign", color = colors.white })
            table.insert(contentLines, { text = "  [E] Edit linked product", color = colors.white })
        end
        table.insert(contentLines, { text = "  [Q] Back to sign list", color = colors.white })
        
        local totalLines = #contentLines
        
        -- Clamp scroll
        scroll = math.max(0, math.min(scroll, math.max(0, totalLines - visibleHeight)))
        
        -- Title
        term.setTextColor(colors.yellow)
        print("=== Sign Details ===")
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
        print("Up/Down: Scroll | R/E/Q: Actions")
        
        local e, key = os.pullEvent("key")
        if key == keys.up then
            scroll = scroll - 1
        elseif key == keys.down then
            scroll = scroll + 1
        elseif key == keys.pageUp then
            scroll = scroll - (visibleHeight - 1)
        elseif key == keys.pageDown then
            scroll = scroll + (visibleHeight - 1)
        elseif key == keys.q then
            return
        elseif key == keys.r and signOpt.product then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            print("Refreshing sign...")
            signManager.updateItemSigns(signOpt.product)
            term.setTextColor(colors.green)
            print("Done!")
            sleep(0.5)
            -- Refresh sign data
            data = sign.getSignText()
        elseif key == keys.e and signOpt.product then
            -- Edit the linked product
            local product = signOpt.product
            local form = formui.new("Edit Product: " .. productManager.getName(product))
            
            local metaField = form:text("Meta (unique ID)", product.meta)
            local line1Field = form:text("Line 1 (name)", product.line1)
            local line2Field = form:text("Line 2 (desc)", product.line2, nil, true)
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
                    itemnbt = product.itemnbt
                }
                
                local success, err = productManager:updateItem(product, newProduct)
                
                term.clear()
                term.setCursorPos(1, 1)
                if success then
                    term.setTextColor(colors.green)
                    print("Product updated!")
                    signOpt.product = newProduct
                else
                    term.setTextColor(colors.red)
                    print("Error: " .. (err or "Unknown"))
                end
                sleep(0.5)
                -- Refresh sign data
                data = sign.getSignText()
            end
        end
    end
end

--- View all signs with interactive menu
local function viewSigns()
    while true do
        -- Show loading screen
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        print("Scanning signs...")
        term.setTextColor(colors.gray)
        print("Please wait...")
        
        local signOptions = getSignOptions()
        
        if #signOptions == 0 then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.red)
            print("No signs found!")
            term.setTextColor(colors.gray)
            print("\nPress any key to continue...")
            os.pullEvent("key")
            return
        end
        
        -- Add summary header
        local linkedCount = 0
        local unknownCount = 0
        local emptyCount = 0
        for _, opt in ipairs(signOptions) do
            if opt.status == "linked" then linkedCount = linkedCount + 1
            elseif opt.status == "unknown" then unknownCount = unknownCount + 1
            else emptyCount = emptyCount + 1 end
        end
        
        local menuOptions = {
            { separator = true, label = string.format("Total: %d | Linked: %d | Unknown: %d | Empty: %d", 
                #signOptions, linkedCount, unknownCount, emptyCount) },
            { separator = true, label = "" },
        }
        
        -- Add grouped signs
        if linkedCount > 0 then
            table.insert(menuOptions, { separator = true, label = "--- Linked Signs ---" })
            for _, opt in ipairs(signOptions) do
                if opt.status == "linked" then
                    table.insert(menuOptions, opt)
                end
            end
        end
        
        if unknownCount > 0 then
            table.insert(menuOptions, { separator = true, label = "--- Unknown Products ---" })
            for _, opt in ipairs(signOptions) do
                if opt.status == "unknown" then
                    table.insert(menuOptions, opt)
                end
            end
        end
        
        if emptyCount > 0 then
            table.insert(menuOptions, { separator = true, label = "--- Empty Signs ---" })
            for _, opt in ipairs(signOptions) do
                if opt.status == "empty" then
                    table.insert(menuOptions, opt)
                end
            end
        end
        
        table.insert(menuOptions, { separator = true, label = "" })
        table.insert(menuOptions, { label = "Refresh All Signs", action = "refresh_all" })
        table.insert(menuOptions, { label = "Back to Main Menu", action = "back" })
        
        local action = showMenu("Shop Signs", menuOptions)
        
        if action == "back" or action == nil then
            return
        elseif action == "refresh_all" then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            print("Updating all signs...")
            signManager.updateAll()
            term.setTextColor(colors.green)
            print("Done!")
            sleep(0.5)
        else
            -- Find the selected sign option
            for _, opt in ipairs(signOptions) do
                if opt.action == action then
                    viewSignDetails(opt)
                    break
                end
            end
        end
    end
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

--- Display the aisles list with interactive menu
local function showAisles()
    while true do
        -- Show loading screen
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        print("Loading aisles...")
        term.setTextColor(colors.gray)
        print("Please wait...")
        
        local aisles = aisleManager.getAisles()
        
        if not aisles or not next(aisles) then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.red)
            print("No aisles found!")
            term.setTextColor(colors.gray)
            print("Make sure aisle turtles are running!")
            print("\nPress any key to continue...")
            os.pullEvent("key")
            return
        end
        
        -- Count aisles by status
        local onlineCount = 0
        local staleCount = 0
        local offlineCount = 0
        local unknownCount = 0
        
        local aisleOptions = {}
        for name, aisle in pairs(aisles) do
            local lastSeen = aisle.lastSeen and os.epoch("utc") - aisle.lastSeen or nil
            local status = "unknown"
            local statusText = "unknown"
            
            if lastSeen then
                if lastSeen < 10000 then
                    status = "online"
                    statusText = "online"
                    onlineCount = onlineCount + 1
                elseif lastSeen < 60000 then
                    status = "stale"
                    statusText = string.format("stale (%ds ago)", math.floor(lastSeen / 1000))
                    staleCount = staleCount + 1
                else
                    status = "offline"
                    statusText = string.format("offline (%dm ago)", math.floor(lastSeen / 60000))
                    offlineCount = offlineCount + 1
                end
            else
                unknownCount = unknownCount + 1
            end
            
            table.insert(aisleOptions, {
                label = string.format("%s - %s", name, statusText),
                action = name,
                aisle = aisle,
                aisleName = name,
                status = status
            })
        end
        
        -- Sort by status then name
        table.sort(aisleOptions, function(a, b)
            local statusOrder = { online = 1, stale = 2, offline = 3, unknown = 4 }
            if statusOrder[a.status] ~= statusOrder[b.status] then
                return statusOrder[a.status] < statusOrder[b.status]
            end
            return a.aisleName < b.aisleName
        end)
        
        -- Build menu
        local menuOptions = {
            { separator = true, label = string.format("Online: %d | Stale: %d | Offline: %d", 
                onlineCount, staleCount, offlineCount) },
            { separator = true, label = "" },
        }
        
        for _, opt in ipairs(aisleOptions) do
            table.insert(menuOptions, opt)
        end
        
        table.insert(menuOptions, { separator = true, label = "" })
        table.insert(menuOptions, { label = "Ping All Aisles", action = "ping" })
        table.insert(menuOptions, { label = "Update All Aisles", action = "update" })
        table.insert(menuOptions, { label = "Back to Main Menu", action = "back" })
        
        local action = showMenu("Aisles", menuOptions)
        
        if action == "back" or action == nil then
            return
        elseif action == "ping" then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            print("Pinging aisles...")
            term.setTextColor(colors.gray)
            print("(Aisles should respond within a few seconds)")
            sleep(1)
        elseif action == "update" then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            print("Sending update command to all aisles...")
            aisleManager.updateAisles()
            term.setTextColor(colors.green)
            print("Update command sent!")
            sleep(0.5)
        else
            -- View aisle details
            for _, opt in ipairs(aisleOptions) do
                if opt.action == action then
                    local w, h = term.getSize()
                    local aisle = opt.aisle
                    local scroll = 0
                    
                    -- Build content lines
                    local function buildContentLines()
                        local lines = {}
                        
                        -- Status
                        local statusColor, statusText
                        if opt.status == "online" then
                            statusColor = colors.green
                            statusText = "Online"
                        elseif opt.status == "stale" then
                            statusColor = colors.yellow
                            statusText = "Stale"
                        elseif opt.status == "offline" then
                            statusColor = colors.red
                            statusText = "Offline"
                        else
                            statusColor = colors.gray
                            statusText = "Unknown"
                        end
                        table.insert(lines, { label = "Status: ", value = statusText, labelColor = colors.lightBlue, valueColor = statusColor })
                        
                        -- Turtle ID
                        if aisle.self then
                            table.insert(lines, { label = "Turtle: ", value = tostring(aisle.self), labelColor = colors.lightBlue, valueColor = colors.white })
                        end
                        
                        -- Last seen
                        if aisle.lastSeen then
                            local ago = os.epoch("utc") - aisle.lastSeen
                            local lastSeenText
                            if ago < 1000 then
                                lastSeenText = "just now"
                            elseif ago < 60000 then
                                lastSeenText = math.floor(ago / 1000) .. " seconds ago"
                            else
                                lastSeenText = math.floor(ago / 60000) .. " minutes ago"
                            end
                            table.insert(lines, { label = "Last seen: ", value = lastSeenText, labelColor = colors.lightBlue, valueColor = colors.white })
                        end
                        
                        -- Blank line
                        table.insert(lines, { text = "", color = colors.white })
                        
                        -- Products header
                        table.insert(lines, { text = "Products in this aisle:", color = colors.yellow })
                        
                        -- Get products
                        local products = productManager.getAll()
                        local aisleProducts = {}
                        if products then
                            for meta, product in pairs(products) do
                                if product.aisleName == opt.aisleName then
                                    table.insert(aisleProducts, product)
                                end
                            end
                        end
                        
                        if #aisleProducts == 0 then
                            table.insert(lines, { text = "  (none)", color = colors.gray })
                        else
                            table.sort(aisleProducts, function(a, b)
                                return productManager.getName(a) < productManager.getName(b)
                            end)
                            for _, product in ipairs(aisleProducts) do
                                local stock = inventoryManager.getItemStock(product.modid, product.itemnbt) or 0
                                table.insert(lines, { text = string.format("  %s (x%d)", productManager.getName(product), stock), color = colors.white })
                            end
                        end
                        
                        return lines
                    end
                    
                    while true do
                        term.clear()
                        term.setCursorPos(1, 1)
                        
                        local headerHeight = 3  -- title + separator + blank
                        local footerHeight = 2  -- help text
                        local visibleHeight = h - headerHeight - footerHeight
                        
                        -- Draw header
                        term.setTextColor(colors.yellow)
                        print("=== Aisle: " .. opt.aisleName .. " ===")
                        term.setTextColor(colors.gray)
                        print(string.rep("-", w))
                        print()
                        
                        local contentLines = buildContentLines()
                        local totalLines = #contentLines
                        
                        -- Clamp scroll
                        scroll = math.max(0, math.min(scroll, math.max(0, totalLines - visibleHeight)))
                        
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
                        
                        -- Draw footer
                        term.setCursorPos(1, h - 1)
                        term.setTextColor(colors.gray)
                        print("Up/Down: Scroll | Q: Back")
                        
                        local e, key = os.pullEvent("key")
                        if key == keys.q then
                            break
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
                            scroll = totalLines - visibleHeight
                        end
                    end
                    break
                end
            end
        end
    end
end

--- Rescan inventory
local function rescanInventory()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("Rescanning inventory...")
    term.setTextColor(colors.gray)
    print("This may take a moment...")
    term.setTextColor(colors.white)
    print()
    
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
    -- Convert from epoch milliseconds to a relative time
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
local function showSalesDashboard()
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
local function showRecentSales()
    local scroll = 0
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3
        local footerHeight = 2
        local visibleHeight = h - headerHeight - footerHeight
        
        local sales = salesManager.getRecentSales(100)
        
        -- Title
        term.setTextColor(colors.yellow)
        print("=== Recent Sales ===")
        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        print()
        
        if #sales == 0 then
            term.setTextColor(colors.gray)
            print("No sales recorded yet.")
        else
            -- Clamp scroll
            scroll = math.max(0, math.min(scroll, math.max(0, #sales - visibleHeight)))
            
            -- Draw sales
            for i = scroll + 1, math.min(#sales, scroll + visibleHeight) do
                local sale = sales[i]
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
            if scroll + visibleHeight < #sales then
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
            scroll = #sales - visibleHeight
        end
    end
end

--- Show top products by revenue
local function showTopProducts()
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
local function showTopBuyers()
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
        elseif action == "sales_dashboard" then
            showSalesDashboard()
        elseif action == "recent_sales" then
            showRecentSales()
        elseif action == "top_products" then
            showTopProducts()
        elseif action == "top_buyers" then
            showTopBuyers()
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
