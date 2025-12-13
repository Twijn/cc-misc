--- SignShop Aisles Configuration ---
--- Aisle management screens: view aisles, aisle details, update aisles.
---
---@version 1.0.0

if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

local menu = require("lib.menu")
local ui = require("lib.ui")

local productManager = require("managers.product")
local inventoryManager = require("managers.inventory")
local aisleManager = require("managers.aisle")

local aisles = {}

--- View aisle details
---@param opt table Aisle option with aisle data
local function viewAisleDetails(opt)
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
                local stock = inventoryManager.getItemStock(product.modid, product.itemnbt, product.anyNbt) or 0
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
end

--- Display the aisles list with interactive menu
function aisles.showList()
    while true do
        -- Show loading screen
        ui.showLoading("Loading aisles...", "Please wait...")
        
        local aisleData = aisleManager.getAisles()
        
        if not aisleData or not next(aisleData) then
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
        for name, aisle in pairs(aisleData) do
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
        
        local action = menu.show("Aisles", menuOptions)
        
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
                    viewAisleDetails(opt)
                    break
                end
            end
        end
    end
end

--- Update all aisles (send update command)
function aisles.updateAll()
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

--- Rescan inventory
function aisles.rescanInventory()
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

return aisles
