--- SignShop Signs Configuration ---
--- Sign management screens: view signs, sign details, refresh signs.
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
local signManager = require("managers.sign")

local signs = {}

--- Build sign options for menu selection
---@return table options Array of sign options for menu
local function getSignOptions()
    local signPeripherals = table.pack(peripheral.find("minecraft:sign"))
    local options = {}
    local signData = {}
    
    -- Read all sign texts in parallel for better performance
    local tasks = {}
    for i, sign in ipairs(signPeripherals) do
        tasks[i] = function()
            signData[i] = sign.getSignText()
        end
    end
    if #tasks > 0 then
        parallel.waitForAll(table.unpack(tasks))
    end
    
    -- Process sign data (no peripheral calls, fast)
    for i, sign in ipairs(signPeripherals) do
        local signName = peripheral.getName(sign)
        local data = signData[i]
        local meta = data[4]
        local product = productManager.get(meta)
        
        local label
        local status
        if product then
            local stock = inventoryManager.getItemStock(product.modid, product.itemnbt, product.anyNbt) or 0
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
            local stock = inventoryManager.getItemStock(signOpt.product.modid, signOpt.product.itemnbt, signOpt.product.anyNbt) or 0
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
            local anyNbtField = form:checkbox("Match Any NBT", product.anyNbt or false)
            local maxStockField = form:number("Max Stock Display (0=unlimited)", product.maxStockDisplay or 0, formui.validation.number_range(0, 999999))
            
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
                    anyNbt = anyNbtField(),
                    maxStockDisplay = maxStockField()
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
function signs.showList()
    while true do
        -- Show loading screen
        ui.showLoading("Scanning signs...", "Please wait...")
        
        local signOptions = getSignOptions()
        
        if #signOptions == 0 then
            ui.showError("No signs found!")
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
        
        local action = menu.show("Shop Signs", menuOptions)
        
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

--- Update all signs
function signs.updateAll()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("Updating all signs...")
    term.setTextColor(colors.white)
    
    signManager.updateAll()
    
    term.setTextColor(colors.green)
    print("Done!")
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

return signs
