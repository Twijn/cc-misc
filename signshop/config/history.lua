--- SignShop History Configuration ---
--- History view and undo functionality screens.
---
---@version 1.0.0

if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

local menu = require("lib.menu")

local historyManager = require("managers.history")
local productManager = require("managers.product")

local history = {}

--- View change history
function history.showHistory()
    local scroll = 0
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        
        local w, h = term.getSize()
        local headerHeight = 3
        local footerHeight = 2
        local visibleHeight = h - headerHeight - footerHeight
        
        local historyData = historyManager.getHistory(50)
        
        -- Title
        term.setTextColor(colors.yellow)
        print("=== Change History ===")
        term.setTextColor(colors.gray)
        print(string.rep("-", w))
        print()
        
        if #historyData == 0 then
            term.setTextColor(colors.gray)
            print("No history recorded yet.")
        else
            -- Clamp scroll
            scroll = math.max(0, math.min(scroll, math.max(0, #historyData - visibleHeight)))
            
            -- Draw history entries
            for i = scroll + 1, math.min(#historyData, scroll + visibleHeight) do
                local entry = historyData[i]
                
                local line = string.format("#%d %s - %s",
                    entry.id,
                    entry.date or "?",
                    historyManager.formatEntry(entry))
                
                -- Truncate if too long
                if #line > w - 1 then
                    line = line:sub(1, w - 4) .. "..."
                end
                
                -- Color based on status
                if entry.undone then
                    term.setTextColor(colors.gray)
                elseif entry.action == "delete" then
                    term.setTextColor(colors.red)
                elseif entry.action == "create" then
                    term.setTextColor(colors.green)
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
            if scroll + visibleHeight < #historyData then
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
            scroll = #historyData - visibleHeight
        end
    end
end

--- Show undo menu with undoable changes
function history.showUndoMenu()
    local undoable = historyManager.getUndoableChanges(20)
    
    if #undoable == 0 then
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        print("No changes available to undo.")
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
        return
    end
    
    local options = {
        { separator = true, label = "Select a change to undo:" },
    }
    
    for _, entry in ipairs(undoable) do
        local label = string.format("#%d %s - %s",
            entry.id,
            entry.date or "?",
            historyManager.formatEntry(entry))
        table.insert(options, {
            label = label,
            action = tostring(entry.id),
            entry = entry,
        })
    end
    
    table.insert(options, { separator = true, label = "" })
    table.insert(options, { label = "Cancel", action = "cancel" })
    
    local action = menu.show("Undo Change", options)
    
    if action == "cancel" or action == nil then
        return
    end
    
    local entryId = tonumber(action)
    if not entryId then return end
    
    -- Confirmation
    local entry = historyManager.getEntry(entryId)
    if not entry then return end
    
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("=== Confirm Undo ===")
    term.setTextColor(colors.white)
    print()
    print("You are about to undo:")
    term.setTextColor(colors.lightBlue)
    print("  " .. historyManager.formatEntry(entry))
    print()
    
    if entry.action == "create" then
        term.setTextColor(colors.red)
        print("This will DELETE the created product.")
    elseif entry.action == "update" then
        term.setTextColor(colors.orange)
        print("This will RESTORE the previous state.")
    elseif entry.action == "delete" then
        term.setTextColor(colors.green)
        print("This will RESTORE the deleted product.")
    end
    
    print()
    term.setTextColor(colors.white)
    print("Press Y to confirm, any other key to cancel")
    
    local _, key = os.pullEvent("key")
    if key == keys.y then
        local success, err = historyManager.undo(entryId, productManager)
        
        term.clear()
        term.setCursorPos(1, 1)
        if success then
            term.setTextColor(colors.green)
            print("Change undone successfully!")
        else
            term.setTextColor(colors.red)
            print("Failed to undo: " .. (err or "Unknown error"))
        end
    else
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        print("Undo cancelled.")
    end
    
    term.setTextColor(colors.gray)
    print("\nPress any key to continue...")
    os.pullEvent("key")
end

return history
