--- AutoCrafter Recipe Override UI
--- Interactive form-based interface for adding custom recipes.
---
---@version 1.0.0

local formui = require("lib.formui")
local overrides = require("config.recipeoverrides")
local logger = require("lib.log")

local ui = {}

---Show main menu for recipe management
function ui.mainMenu()
    local form = formui.new("Recipe Overrides")
    
    form:label("=== Recipe Management ===")
    form:label(string.format("Custom recipes: %d", overrides.count()))
    form:label(string.format("Status: %s", overrides.isEnabled() and "Enabled" or "Disabled"))
    form:label("")
    
    form:label("--- Actions ---")
    local addBtn = form:button("Add New Recipe")
    local listBtn = form:button("List Recipes")
    local toggleBtn = form:button(overrides.isEnabled() and "Disable Recipes" or "Enable Recipes")
    local clearBtn = form:button("Clear All (Danger!)")
    local backBtn = form:button("Back")
    
    form:run()
    
    if addBtn() then
        ui.addRecipeMenu()
    elseif listBtn() then
        ui.listRecipes()
    elseif toggleBtn() then
        if overrides.isEnabled() then
            overrides.disable()
            print("Custom recipes disabled")
        else
            overrides.enable()
            print("Custom recipes enabled")
        end
        ui.mainMenu()
    elseif clearBtn() then
        if ui.confirmClear() then
            overrides.clear()
            print("All custom recipes cleared")
        end
        ui.mainMenu()
    end
end

---Confirm clear all recipes
---@return boolean confirmed
function ui.confirmClear()
    local form = formui.new("Confirm Clear")
    form:label("Are you sure you want to delete")
    form:label("ALL custom recipes?")
    form:label("")
    form:label("This cannot be undone!")
    form:label("")
    
    local yesBtn = form:button("Yes, Delete All")
    local noBtn = form:button("No, Cancel")
    
    form:run()
    return yesBtn()
end

---Show recipe type selection menu
function ui.addRecipeMenu()
    local form = formui.new("Add Recipe")
    
    form:label("=== Select Recipe Type ===")
    form:label("")
    form:label("Shaped: Exact grid pattern")
    form:label("  (like crafting table)")
    form:label("")
    form:label("Shapeless: Any arrangement")
    form:label("  (ingredients can be anywhere)")
    form:label("")
    
    local shapedBtn = form:button("Shaped Recipe")
    local shapelessBtn = form:button("Shapeless Recipe")
    local backBtn = form:button("Back")
    
    form:run()
    
    if shapedBtn() then
        ui.addShapedRecipe()
    elseif shapelessBtn() then
        ui.addShapelessRecipe()
    else
        ui.mainMenu()
    end
end

---Add a shapeless recipe
function ui.addShapelessRecipe()
    local form = formui.new("Shapeless Recipe")
    
    form:label("=== Configure Shapeless Recipe ===")
    form:label("Ingredients can be in any position")
    form:label("")
    
    local outputField = form:text("Output Item", "minecraft:")
    local countField = form:number("Output Count", 1, formui.validation.number_range(1, 64))
    local priorityField = form:number("Priority", 100, formui.validation.number_range(1, 999))
    
    form:label("")
    form:label("--- Ingredients ---")
    form:label("Add items (format: item:id count)")
    form:label("Example: minecraft:stick 2")
    form:label("Or use tags: #c:iron_ingots 3")
    
    local ingredientsField = form:list("Ingredients", {}, "string")
    
    form:label("")
    local saveBtn = form:button("Save Recipe")
    local backBtn = form:button("Cancel")
    
    form:run()
    
    if saveBtn() then
        local output = outputField()
        local count = countField()
        local priority = priorityField()
        local ingredientsList = ingredientsField()
        
        -- Parse ingredients from list
        local ingredients = {}
        for _, line in ipairs(ingredientsList) do
            local item, itemCount = line:match("^(%S+)%s+(%d+)$")
            if item and itemCount then
                table.insert(ingredients, {
                    item = item,
                    count = tonumber(itemCount)
                })
            end
        end
        
        if #ingredients == 0 then
            print("Error: No valid ingredients")
            sleep(2)
            ui.addShapelessRecipe()
            return
        end
        
        local recipe = {
            type = "shapeless",
            ingredients = ingredients,
            output = output,
            outputCount = count,
            priority = priority
        }
        
        local success, err = overrides.add(output, recipe)
        if success then
            print(string.format("Added shapeless recipe for %s", output))
            sleep(1)
            ui.mainMenu()
        else
            print("Error: " .. (err or "Unknown error"))
            sleep(2)
            ui.addShapelessRecipe()
        end
    else
        ui.addRecipeMenu()
    end
end

---Add a shaped recipe
function ui.addShapedRecipe()
    local form = formui.new("Shaped Recipe")
    
    form:label("=== Configure Shaped Recipe ===")
    form:label("Define exact grid pattern")
    form:label("")
    
    local outputField = form:text("Output Item", "minecraft:")
    local countField = form:number("Output Count", 1, formui.validation.number_range(1, 64))
    local priorityField = form:number("Priority", 100, formui.validation.number_range(1, 999))
    
    form:label("")
    form:label("--- Pattern (3x3 max) ---")
    form:label("Use letters for items, space for empty")
    form:label("Example: 'III' 'ISI' 'III'")
    
    local row1Field = form:text("Row 1", "")
    local row2Field = form:text("Row 2", "")
    local row3Field = form:text("Row 3", "")
    
    form:label("")
    form:label("--- Key Mapping ---")
    form:label("Add mappings (format: A=item:id)")
    
    local keyField = form:list("Key Mappings", {}, "string")
    
    form:label("")
    local saveBtn = form:button("Save Recipe")
    local backBtn = form:button("Cancel")
    
    form:run()
    
    if saveBtn() then
        local output = outputField()
        local count = countField()
        local priority = priorityField()
        
        -- Build pattern
        local pattern = {}
        local row1 = row1Field()
        local row2 = row2Field()
        local row3 = row3Field()
        
        if row1 ~= "" then table.insert(pattern, row1) end
        if row2 ~= "" then table.insert(pattern, row2) end
        if row3 ~= "" then table.insert(pattern, row3) end
        
        if #pattern == 0 then
            print("Error: Pattern is empty")
            sleep(2)
            ui.addShapedRecipe()
            return
        end
        
        -- Parse key mappings from list
        local key = {}
        local keyList = keyField()
        for _, line in ipairs(keyList) do
            local char, item = line:match("^(%S)=(%S+)$")
            if char and item then
                key[char] = item
            end
        end
        
        if not next(key) then
            print("Error: No key mappings")
            sleep(2)
            ui.addShapedRecipe()
            return
        end
        
        local recipe = {
            type = "shaped",
            pattern = pattern,
            key = key,
            output = output,
            outputCount = count,
            priority = priority
        }
        
        local success, err = overrides.add(output, recipe)
        if success then
            print(string.format("Added shaped recipe for %s", output))
            sleep(1)
            ui.mainMenu()
        else
            print("Error: " .. (err or "Unknown error"))
            sleep(2)
            ui.addShapedRecipe()
        end
    else
        ui.addRecipeMenu()
    end
end

---List all custom recipes
function ui.listRecipes()
    local all = overrides.getAll()
    
    -- Count recipes
    local outputs = {}
    for output, recipes in pairs(all) do
        table.insert(outputs, output)
    end
    table.sort(outputs)
    
    if #outputs == 0 then
        print("No custom recipes")
        sleep(2)
        ui.mainMenu()
        return
    end
    
    local form = formui.new("Custom Recipes")
    form:label(string.format("=== %d Items ===", #outputs))
    form:label("")
    
    -- Show up to 10 items
    local maxShow = math.min(10, #outputs)
    for i = 1, maxShow do
        local output = outputs[i]
        local recipes = all[output]
        local shortName = output:gsub("minecraft:", ""):gsub("_", " ")
        form:label(string.format("%s (%d)", shortName, #recipes))
    end
    
    if #outputs > maxShow then
        form:label(string.format("... and %d more", #outputs - maxShow))
    end
    
    form:label("")
    local backBtn = form:button("Back")
    
    form:run()
    ui.mainMenu()
end

---Quick add helper - guided recipe creation
function ui.quickAdd()
    print("=== Quick Recipe Add ===")
    print()
    
    -- Get output
    write("Output item (e.g. minecraft:torch): ")
    local output = read()
    if output == "" then return end
    
    -- Get type
    print()
    print("Recipe type:")
    print("1. Shapeless (ingredients anywhere)")
    print("2. Shaped (exact pattern)")
    write("Choice [1/2]: ")
    local choice = read()
    
    if choice == "1" then
        -- Shapeless
        print()
        write("Output count: ")
        local count = tonumber(read()) or 1
        
        print()
        print("Enter ingredients (one per line)")
        print("Format: item count")
        print("Example: minecraft:stick 2")
        print("Enter blank line when done:")
        
        local ingredients = {}
        while true do
            write("> ")
            local line = read()
            if line == "" then break end
            
            local item, itemCount = line:match("^(%S+)%s+(%d+)$")
            if item and itemCount then
                table.insert(ingredients, {
                    item = item,
                    count = tonumber(itemCount)
                })
            else
                print("Invalid format, skipped")
            end
        end
        
        if #ingredients > 0 then
            local success, err = overrides.add(output, {
                type = "shapeless",
                ingredients = ingredients,
                output = output,
                outputCount = count
            })
            
            if success then
                print()
                print("Recipe added successfully!")
            else
                print()
                print("Error: " .. (err or "Unknown"))
            end
        end
        
    elseif choice == "2" then
        -- Shaped
        print()
        write("Output count: ")
        local count = tonumber(read()) or 1
        
        print()
        print("Enter pattern rows (1-3 rows):")
        print("Use letters for items, space for empty")
        print("Example: III")
        
        local pattern = {}
        for i = 1, 3 do
            write(string.format("Row %d (or blank): ", i))
            local row = read()
            if row ~= "" then
                table.insert(pattern, row)
            else
                break
            end
        end
        
        if #pattern == 0 then
            print("Error: Empty pattern")
            return
        end
        
        print()
        print("Enter key mappings:")
        print("Format: A=minecraft:item")
        print("Enter blank line when done:")
        
        local key = {}
        while true do
            write("> ")
            local line = read()
            if line == "" then break end
            
            local char, item = line:match("^(%S)=(%S+)$")
            if char and item then
                key[char] = item
            else
                print("Invalid format, skipped")
            end
        end
        
        if not next(key) then
            print("Error: No key mappings")
            return
        end
        
        local success, err = overrides.add(output, {
            type = "shaped",
            pattern = pattern,
            key = key,
            output = output,
            outputCount = count
        })
        
        if success then
            print()
            print("Recipe added successfully!")
        else
            print()
            print("Error: " .. (err or "Unknown"))
        end
    end
end

return ui
