--- Recipe Override Manager
--- Quick launcher for managing custom recipes
---
--- Usage: recipes
---
--- This tool provides an easy interface for:
--- - Adding new custom recipes
--- - Listing existing recipes
--- - Enabling/disabling recipe overrides
--- - Clearing recipes

local ui = require("config.recipeoverrides-ui")

-- Check if command line argument provided
local args = {...}

if args[1] == "add" then
    -- Quick add mode
    ui.quickAdd()
elseif args[1] == "quick" then
    -- Quick add mode
    ui.quickAdd()
elseif args[1] == "list" then
    -- Just list recipes
    ui.listRecipes()
else
    -- Show full menu
    ui.mainMenu()
end
