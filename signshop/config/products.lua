--- SignShop Products Configuration ---
--- Product management screens: view, add, edit, delete, select.
---
---@version 1.0.0

if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

local formui = require("lib.formui")
local menu = require("lib.menu")
local ui = require("lib.ui")

local productManager = require("managers.product")
local inventoryManager = require("managers.inventory")
local aisleManager = require("managers.aisle")
local signManager = require("managers.sign")

local products = {}

--- Filter function for product options
---@param opt table The option to check
---@param filterText string The lowercase filter text
---@return boolean True if option matches filter
local function productFilterFn(opt, filterText)
    if not opt.product then return false end
    local product = opt.product
    
    -- Match product name (line1 + line2)
    local name = (product.line1 or "") .. " " .. (product.line2 or "")
    if name:lower():find(filterText, 1, true) then return true end
    
    -- Match meta
    if product.meta and product.meta:lower():find(filterText, 1, true) then return true end
    
    -- Match aisle name
    if product.aisleName and product.aisleName:lower():find(filterText, 1, true) then return true end
    
    -- Match mod ID
    if product.modid and product.modid:lower():find(filterText, 1, true) then return true end
    
    return false
end

--- Build a list of product options for menu selection
---@return table options Array of {label, action, product} for menu
local function getProductOptions()
    local allProducts = productManager.getAll()
    local options = {}
    
    if allProducts then
        for meta, product in pairs(allProducts) do
            local stock = inventoryManager.getItemStock(product.modid, product.itemnbt, product.anyNbt) or 0
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

--- View product details
---@param product table The product to view
---@return string|nil result "deleted" if product was deleted
local function viewProductDetails(product)
    local scroll = 0
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3
        local footerHeight = 2
        local visibleHeight = h - headerHeight - footerHeight
        local stock = inventoryManager.getItemStock(product.modid, product.itemnbt, product.anyNbt) or 0
        
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
        
        if product.anyNbt then
            table.insert(contentLines, { label = "NBT: ", value = "Any (matches all NBT values)", labelColor = colors.lightBlue, valueColor = colors.orange })
        elseif product.itemnbt then
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
            local anyNbtField = form:checkbox("Match Any NBT", product.anyNbt or false)
            
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
                    itemnbt = product.itemnbt,
                    anyNbt = anyNbtField()
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

--- Add a new product
function products.add()
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
    local anyNbtField = form:checkbox("Match Any NBT", false)
    
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
            modid = modidField(),
            anyNbt = anyNbtField()
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
function products.select(title)
    -- Show loading screen
    ui.showLoading("Loading products...", "Please wait...")
    
    local options = getProductOptions()
    
    if #options == 0 then
        ui.showError("No products found!")
        return nil
    end
    
    table.insert(options, 1, { separator = true, label = "Select a product:" })
    table.insert(options, { separator = true, label = "" })
    table.insert(options, { label = "Cancel", action = "cancel" })
    
    local action = menu.show(title, options)
    
    if action == "cancel" or action == nil then
        return nil
    end
    
    return productManager.get(action)
end

--- Edit an existing product
function products.edit()
    local product = products.select("Edit Product")
    if not product then return end
    
    local form = formui.new("Edit Product: " .. productManager.getName(product))
    
    local metaField = form:text("Meta (unique ID)", product.meta)
    local line1Field = form:text("Line 1 (name)", product.line1)
    local line2Field = form:text("Line 2 (desc)", product.line2, nil, true)
    local costField = form:number("Cost (KRO)", product.cost, formui.validation.number_range(0.001, 999999))
    local aisleField = form:text("Aisle Name", product.aisleName)
    local modidField = form:text("Mod ID", product.modid or "")
    local anyNbtField = form:checkbox("Match Any NBT", product.anyNbt or false)
    
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
            itemnbt = product.itemnbt,  -- Preserve NBT if exists
            anyNbt = anyNbtField()
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
function products.delete()
    local product = products.select("Delete Product")
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

--- Display the products list with interactive menu
function products.showList()
    while true do
        -- Show loading screen
        ui.showLoading("Loading products...", "Please wait...")
        
        local options = getProductOptions()
        
        if #options == 0 then
            ui.showError("No products found!")
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
            { separator = true, label = string.format("Total: %d products | Press / or F to filter", #options) },
        }
        
        for _, aisleName in ipairs(aisleNames) do
            table.insert(menuOptions, { separator = true, label = "--- " .. aisleName .. " ---" })
            for _, opt in ipairs(byAisle[aisleName]) do
                -- Shorter label for menu
                local stock = inventoryManager.getItemStock(opt.product.modid, opt.product.itemnbt, opt.product.anyNbt) or 0
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
        
        -- Use filterable menu with product filter function
        local action = menu.show("Products", menuOptions, true, productFilterFn)
        
        if action == "back" or action == nil then
            menu.clearFilter()  -- Clear filter when leaving
            return
        elseif action == "add" then
            products.add()
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

--- Refresh signs for a specific product
function products.refreshSign()
    local product = products.select("Refresh Sign for Product")
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

return products
