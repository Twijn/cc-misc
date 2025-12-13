--- SignShop Configuration UI ---
--- Interactive configuration interface for SignShop using formui.
--- Main entry point that routes to modular configuration screens.
---
---@version 2.0.0

if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

-- Load menu library
local menu = require("lib.menu")

-- Load configuration modules
local productsConfig = require("config.products")
local signsConfig = require("config.signs")
local aislesConfig = require("config.aisles")
local salesConfig = require("config.sales")
local settingsConfig = require("config.settings")
local historyConfig = require("config.history")

local VERSION = ssVersion and ssVersion() or "unknown"

local config = {}

--- Display the main menu
---@return string|nil action The selected action or nil if cancelled
local function mainMenu()
    return menu.show("SignShop v" .. VERSION, {
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
        { separator = true, label = "--- History ---" },
        { label = "View History", action = "view_history" },
        { label = "Undo Change", action = "undo_change" },
        { separator = true, label = "--- Settings ---" },
        { label = "Krist Settings", action = "krist" },
        { label = "Modem Settings", action = "modem" },
        { label = "ShopSync Settings", action = "shopsync" },
        { label = "Monitor Settings", action = "monitor" },
        { separator = true, label = "" },
        { label = "Exit", action = "exit" },
    })
end

--- Main configuration loop
function config.run()
    while true do
        local action = mainMenu()
        
        -- Products
        if action == "products" then
            productsConfig.showList()
        elseif action == "add_product" then
            productsConfig.add()
        elseif action == "edit_product" then
            productsConfig.edit()
        elseif action == "delete_product" then
            productsConfig.delete()
        
        -- Sales
        elseif action == "sales_dashboard" then
            salesConfig.showDashboard()
        elseif action == "recent_sales" then
            salesConfig.showRecent()
        elseif action == "top_products" then
            salesConfig.showTopProducts()
        elseif action == "top_buyers" then
            salesConfig.showTopBuyers()
        
        -- Signs
        elseif action == "view_signs" then
            signsConfig.showList()
        elseif action == "refresh_product_sign" then
            productsConfig.refreshSign()
        elseif action == "signs" then
            signsConfig.updateAll()
        
        -- Aisles
        elseif action == "aisles" then
            aislesConfig.showList()
        elseif action == "update_aisles" then
            aislesConfig.updateAll()
        elseif action == "rescan" then
            aislesConfig.rescanInventory()
        
        -- History
        elseif action == "view_history" then
            historyConfig.showHistory()
        elseif action == "undo_change" then
            historyConfig.showUndoMenu()
        
        -- Settings
        elseif action == "krist" then
            settingsConfig.configureKrist()
        elseif action == "modem" then
            settingsConfig.configureModem()
        elseif action == "shopsync" then
            settingsConfig.configureShopSync()
        elseif action == "monitor" then
            settingsConfig.configureMonitor()
        
        -- Exit
        elseif action == "exit" or action == nil then
            term.clear()
            term.setCursorPos(1, 1)
            break
        end
    end
end

return config
