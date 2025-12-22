--- AutoCrafter Recipe Preferences Configuration Menu ---
--- Interactive menu for managing recipe variant preferences.
--- View, prioritize, enable/disable recipe variants with filtering.
---
---@version 1.0.0

if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

local menu = require("lib.menu")
local recipes = require("lib.recipes")
local recipePrefs = require("config.recipes")

local recipeprefsConfig = {}

--- Get display name from item ID
---@param item string The full item ID
---@return string displayName The shortened display name
local function getDisplayName(item)
    local result = item:gsub("minecraft:", ""):gsub("_", " ")
    return result
end

--- Get short source name from full path
---@param source string The full recipe source path
---@return string shortSource The shortened source name
local function getShortSource(source)
    local result = source:gsub(".*/recipes/", ""):gsub("%.json$", "")
    return result
end

--- Format ingredient list for display
---@param ingredients table The recipe ingredients
---@return string formatted The formatted ingredient string
local function formatIngredients(ingredients)
    local parts = {}
    for _, ing in ipairs(ingredients) do
        local name = ing.item:gsub("minecraft:", "")
        if name:sub(1, 1) == "#" then
            name = name:sub(2) .. " (tag)"
        end
        table.insert(parts, ing.count .. "x " .. name)
    end
    return table.concat(parts, ", ")
end

--- Filter function for recipe options
---@param opt table The option to check
---@param filterText string The lowercase filter text
---@return boolean True if option matches filter
local function recipeFilterFn(opt, filterText)
    if not opt.recipe and not opt.item then return false end
    
    if opt.item then
        -- Item-level option
        local name = getDisplayName(opt.item)
        if name:lower():find(filterText, 1, true) then return true end
        if opt.item:lower():find(filterText, 1, true) then return true end
    end
    
    if opt.recipe then
        -- Recipe-level option
        local recipe = opt.recipe
        if getDisplayName(recipe.output):lower():find(filterText, 1, true) then return true end
        if recipe.output:lower():find(filterText, 1, true) then return true end
        if getShortSource(recipe.source):lower():find(filterText, 1, true) then return true end
        -- Check ingredients
        for _, ing in ipairs(recipe.ingredients) do
            if ing.item:lower():find(filterText, 1, true) then return true end
        end
    end
    
    return false
end

--- View and manage recipe variants for a specific item
---@param item string The item ID to view recipes for
local function viewItemRecipes(item)
    while true do
        local allRecipes = recipes.getRecipesFor(item, true)
        if #allRecipes == 0 then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.red)
            print("No recipes found for: " .. getDisplayName(item))
            term.setTextColor(colors.gray)
            print("\nPress any key to continue...")
            os.pullEvent("key")
            return
        end
        
        -- Build menu options
        local menuOptions = {
            { separator = true, label = string.format("== %s (%d variants) ==", getDisplayName(item), #allRecipes) },
            { separator = true, label = "" },
        }
        
        local pref = recipePrefs.get(item)
        local priorityIndex = {}
        for i, source in ipairs(pref.priority or {}) do
            priorityIndex[source] = i
        end
        
        for i, recipe in ipairs(allRecipes) do
            local isDisabled = recipePrefs.isDisabled(item, recipe.source)
            local isPrioritized = priorityIndex[recipe.source] ~= nil
            
            local statusIcon = isDisabled and "[X]" or (isPrioritized and "[*]" or "[ ]")
            local statusStr = isDisabled and " (DISABLED)" or (isPrioritized and " (PRIORITY)" or "")
            
            local label = string.format("%s #%d: %dx from %s%s",
                statusIcon,
                i,
                recipe.outputCount,
                formatIngredients(recipe.ingredients),
                statusStr)
            
            table.insert(menuOptions, {
                label = label,
                action = "recipe_" .. i,
                recipe = recipe,
                index = i,
                isDisabled = isDisabled,
                isPrioritized = isPrioritized
            })
            
            -- Add source as sub-item
            table.insert(menuOptions, {
                separator = true,
                label = "    +- " .. getShortSource(recipe.source)
            })
        end
        
        table.insert(menuOptions, { separator = true, label = "" })
        table.insert(menuOptions, { separator = true, label = "--- Actions ---" })
        table.insert(menuOptions, { label = "Clear all preferences for this item", action = "clear" })
        table.insert(menuOptions, { label = "Back to recipe list", action = "back" })
        
        table.insert(menuOptions, { separator = true, label = "" })
        table.insert(menuOptions, { separator = true, label = "Legend: [*]=prioritized [X]=disabled [ ]=default" })
        
        local action = menu.show("Recipe Variants: " .. getDisplayName(item), menuOptions, true, recipeFilterFn)
        
        if action == "back" or action == nil then
            return
        elseif action == "clear" then
            recipePrefs.clear(item)
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.green)
            print("Cleared preferences for " .. getDisplayName(item))
            sleep(0.5)
        elseif action:match("^recipe_") then
            local idx = tonumber(action:match("recipe_(%d+)"))
            local recipe = allRecipes[idx]
            if recipe then
                -- Show recipe action menu
                local isDisabled = recipePrefs.isDisabled(item, recipe.source)
                local isPrioritized = priorityIndex[recipe.source] ~= nil
                
                local actionOptions = {
                    { separator = true, label = "=== Recipe #" .. idx .. " ===" },
                    { separator = true, label = "" },
                    { separator = true, label = "Output: " .. recipe.outputCount .. "x " .. getDisplayName(recipe.output) },
                    { separator = true, label = "Type: " .. recipe.type },
                    { separator = true, label = "Source: " .. getShortSource(recipe.source) },
                    { separator = true, label = "" },
                    { separator = true, label = "Ingredients:" },
                }
                
                for _, ing in ipairs(recipe.ingredients) do
                    local ingName = ing.item:gsub("minecraft:", "")
                    if ingName:sub(1, 1) == "#" then
                        ingName = ingName:sub(2) .. " (tag)"
                    end
                    table.insert(actionOptions, { separator = true, label = "  - " .. ing.count .. "x " .. ingName })
                end
                
                table.insert(actionOptions, { separator = true, label = "" })
                table.insert(actionOptions, { separator = true, label = "--- Actions ---" })
                
                if isPrioritized then
                    table.insert(actionOptions, { label = "Remove from priority", action = "unprioritize" })
                else
                    table.insert(actionOptions, { label = "Set as preferred (move to top priority)", action = "prefer" })
                end
                
                if isDisabled then
                    table.insert(actionOptions, { label = "Enable this recipe", action = "enable" })
                else
                    table.insert(actionOptions, { label = "Disable this recipe", action = "disable" })
                end
                
                table.insert(actionOptions, { separator = true, label = "" })
                table.insert(actionOptions, { label = "Back to recipe list", action = "back" })
                
                local recipeAction = menu.show("Recipe Actions", actionOptions)
                
                if recipeAction == "prefer" then
                    recipePrefs.setPreferred(item, recipe.source)
                    term.clear()
                    term.setCursorPos(1, 1)
                    term.setTextColor(colors.green)
                    print("Set recipe #" .. idx .. " as preferred")
                    sleep(0.5)
                elseif recipeAction == "unprioritize" then
                    -- Remove from priority list
                    local priority = pref.priority or {}
                    local newPriority = {}
                    for _, src in ipairs(priority) do
                        if src ~= recipe.source then
                            table.insert(newPriority, src)
                        end
                    end
                    recipePrefs.setPriority(item, newPriority)
                    term.clear()
                    term.setCursorPos(1, 1)
                    term.setTextColor(colors.green)
                    print("Removed recipe #" .. idx .. " from priority")
                    sleep(0.5)
                elseif recipeAction == "enable" then
                    recipePrefs.enable(item, recipe.source)
                    term.clear()
                    term.setCursorPos(1, 1)
                    term.setTextColor(colors.green)
                    print("Enabled recipe #" .. idx)
                    sleep(0.5)
                elseif recipeAction == "disable" then
                    recipePrefs.disable(item, recipe.source)
                    term.clear()
                    term.setCursorPos(1, 1)
                    term.setTextColor(colors.orange)
                    print("Disabled recipe #" .. idx)
                    sleep(0.5)
                end
            end
        end
    end
end

--- Get all items that have multiple recipe variants
---@return table items Array of {item, recipeCount}
local function getItemsWithMultipleRecipes()
    local allItems = {}
    
    -- Get all recipes directly - faster than search("")
    local allRecipes = recipes.getAll()
    
    for output, recipeList in pairs(allRecipes) do
        if #recipeList >= 1 then
            -- Get preferences once, reuse for both checks
            local pref = recipePrefs.get(output)
            table.insert(allItems, {
                item = output,
                recipeCount = #recipeList,
                hasPrefs = #(pref.priority or {}) > 0 or 
                          next(pref.disabled or {}) ~= nil
            })
        end
    end
    
    -- Sort by name
    table.sort(allItems, function(a, b)
        return getDisplayName(a.item) < getDisplayName(b.item)
    end)
    
    return allItems
end

--- Show items with custom preferences
local function showCustomizedItems()
    while true do
        local items = recipePrefs.getCustomizedItems()
        
        if #items == 0 then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            print("No recipe preferences configured yet.")
            term.setTextColor(colors.lightGray)
            print("\nUse 'Browse All Recipes' to find items and set preferences.")
            term.setTextColor(colors.gray)
            print("\nPress any key to continue...")
            os.pullEvent("key")
            return
        end
        
        -- Build menu
        local menuOptions = {
            { separator = true, label = string.format("== Items with Custom Preferences (%d) ==", #items) },
            { separator = true, label = "" },
        }
        
        for _, itemId in ipairs(items) do
            local summary = recipePrefs.getSummary(itemId)
            local variants = recipes.getRecipesFor(itemId, true)
            local label = string.format("%s (%d variants) - %s", 
                getDisplayName(itemId), #variants, summary)
            table.insert(menuOptions, {
                label = label,
                action = itemId,
                item = itemId
            })
        end
        
        table.insert(menuOptions, { separator = true, label = "" })
        table.insert(menuOptions, { label = "Clear ALL preferences", action = "clearall" })
        table.insert(menuOptions, { label = "Back to main menu", action = "back" })
        
        local action = menu.show("Customized Recipes", menuOptions, true, recipeFilterFn)
        
        if action == "back" or action == nil then
            return
        elseif action == "clearall" then
            -- Confirmation
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.red)
            print("=== CLEAR ALL PREFERENCES ===")
            term.setTextColor(colors.white)
            print()
            print("This will remove all recipe preferences for " .. #items .. " items.")
            print()
            term.setTextColor(colors.yellow)
            print("Are you sure? Press Y to confirm.")
            
            local _, key = os.pullEvent("key")
            if key == keys.y then
                recipePrefs.clearAll()
                term.setTextColor(colors.green)
                print("\nAll preferences cleared!")
                sleep(0.5)
                return
            end
        else
            viewItemRecipes(action)
        end
    end
end

--- Browse all recipes
local function browseAllRecipes()
    while true do
        local allItems = getItemsWithMultipleRecipes()
        
        if #allItems == 0 then
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.red)
            print("No recipes loaded. Make sure recipes.init() has been called.")
            term.setTextColor(colors.gray)
            print("\nPress any key to continue...")
            os.pullEvent("key")
            return
        end
        
        -- Separate items with multiple variants
        local multiVariant = {}
        local singleVariant = {}
        
        for _, item in ipairs(allItems) do
            if item.recipeCount > 1 then
                table.insert(multiVariant, item)
            else
                table.insert(singleVariant, item)
            end
        end
        
        -- Build menu showing items with multiple variants first
        local menuOptions = {
            { separator = true, label = string.format("== All Craftable Items (%d) ==", #allItems) },
            { separator = true, label = "Press / or F to filter by name" },
            { separator = true, label = "" },
        }
        
        if #multiVariant > 0 then
            table.insert(menuOptions, { separator = true, label = "--- Items with Multiple Variants ---" })
            for _, item in ipairs(multiVariant) do
                local prefMark = item.hasPrefs and " [CUSTOMIZED]" or ""
                local label = string.format("%s (%d variants)%s",
                    getDisplayName(item.item), item.recipeCount, prefMark)
                table.insert(menuOptions, {
                    label = label,
                    action = item.item,
                    item = item.item
                })
            end
            table.insert(menuOptions, { separator = true, label = "" })
        end
        
        table.insert(menuOptions, { separator = true, label = "--- Single Recipe Items ---" })
        for _, item in ipairs(singleVariant) do
            local label = getDisplayName(item.item)
            table.insert(menuOptions, {
                label = label,
                action = item.item,
                item = item.item
            })
        end
        
        table.insert(menuOptions, { separator = true, label = "" })
        table.insert(menuOptions, { label = "Back to main menu", action = "back" })
        
        local action = menu.show("All Recipes", menuOptions, true, recipeFilterFn)
        
        if action == "back" or action == nil then
            menu.clearFilter()
            return
        else
            viewItemRecipes(action)
        end
    end
end

--- Search for specific items
local function searchRecipes()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("=== Search Recipes ===")
    term.setTextColor(colors.white)
    print()
    print("Enter item name to search for:")
    term.setTextColor(colors.lightGray)
    print("(partial matches allowed, e.g., 'plank', 'iron', 'chest')")
    print()
    
    term.setTextColor(colors.white)
    write("> ")
    local query = read()
    
    if not query or query == "" then
        return
    end
    
    -- Search
    local results = recipes.search(query)
    
    if #results == 0 then
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.red)
        print("No recipes found matching: " .. query)
        term.setTextColor(colors.gray)
        print("\nPress any key to continue...")
        os.pullEvent("key")
        return
    end
    
    -- Deduplicate by output
    local seen = {}
    local items = {}
    for _, result in ipairs(results) do
        if not seen[result.output] then
            seen[result.output] = true
            local variants = recipes.getRecipesFor(result.output, true)
            table.insert(items, {
                item = result.output,
                recipeCount = #variants,
                hasPrefs = #recipePrefs.get(result.output).priority > 0 or 
                          next(recipePrefs.get(result.output).disabled or {}) ~= nil
            })
        end
    end
    
    -- Sort by name
    table.sort(items, function(a, b)
        return getDisplayName(a.item) < getDisplayName(b.item)
    end)
    
    -- Show results menu
    while true do
        local menuOptions = {
            { separator = true, label = string.format("== Search: '%s' (%d results) ==", query, #items) },
            { separator = true, label = "" },
        }
        
        for _, item in ipairs(items) do
            local prefMark = item.hasPrefs and " [CUSTOMIZED]" or ""
            local label = string.format("%s (%d variants)%s",
                getDisplayName(item.item), item.recipeCount, prefMark)
            table.insert(menuOptions, {
                label = label,
                action = item.item,
                item = item.item
            })
        end
        
        table.insert(menuOptions, { separator = true, label = "" })
        table.insert(menuOptions, { label = "New search", action = "search" })
        table.insert(menuOptions, { label = "Back to main menu", action = "back" })
        
        local action = menu.show("Search Results", menuOptions, true, recipeFilterFn)
        
        if action == "back" or action == nil then
            return
        elseif action == "search" then
            searchRecipes()
            return
        else
            viewItemRecipes(action)
        end
    end
end

--- Main menu for recipe preferences
function recipeprefsConfig.showMenu()
    while true do
        local customCount = #recipePrefs.getCustomizedItems()
        
        local menuOptions = {
            { separator = true, label = "=== Recipe Preferences ===" },
            { separator = true, label = "Configure which recipe variants to use for crafting" },
            { separator = true, label = "" },
            { label = string.format("View Customized Items (%d)", customCount), action = "customized" },
            { label = "Browse All Recipes", action = "browse" },
            { label = "Search Recipes", action = "search" },
            { separator = true, label = "" },
            { label = "Back to Commands", action = "back" },
        }
        
        local action = menu.show("Recipe Preferences", menuOptions)
        
        if action == "back" or action == nil then
            return
        elseif action == "customized" then
            showCustomizedItems()
        elseif action == "browse" then
            browseAllRecipes()
        elseif action == "search" then
            searchRecipes()
        end
    end
end

--- Run as standalone config utility
---@param args table Command line arguments
function recipeprefsConfig.run(args)
    -- Initialize recipes if not already done
    local count = recipes.init()
    if count == 0 then
        term.setTextColor(colors.red)
        print("Warning: No recipes loaded!")
    end
    
    if args and args[1] then
        -- Direct item lookup
        local item = args[1]
        if not item:find(":") then
            item = "minecraft:" .. item
        end
        viewItemRecipes(item)
    else
        -- Show main menu
        recipeprefsConfig.showMenu()
    end
end

return recipeprefsConfig
