--- AutoCrafter Recipe Overrides
--- Allows adding custom recipes and overriding existing ones with full customization.
---
--- Features:
--- - Add completely new recipes
--- - Override existing recipes
--- - Per-slot customization for shaped recipes
--- - Output customization (item, count, NBT)
--- - Support for both shaped and shapeless recipes
--- - Tag support in ingredients
---
--- Example custom recipes:
--- {
---     ["minecraft:diamond_block"] = {
---         {
---             type = "shaped",
---             pattern = {"DDD", "DDD", "DDD"},
---             key = {D = "minecraft:diamond"},
---             output = "minecraft:diamond_block",
---             outputCount = 1,
---             priority = 1  -- Lower = higher priority
---         }
---     },
---     ["minecraft:custom_item"] = {
---         {
---             type = "shapeless",
---             ingredients = {
---                 {item = "minecraft:stick", count = 2},
---                 {item = "#c:iron_ingots", count = 1}
---             },
---             output = "minecraft:custom_item",
---             outputCount = 4
---         }
---     }
--- }
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")

local overrides = persist("recipe-overrides.json")

overrides.setDefault("recipes", {})
overrides.setDefault("enabled", true)

local module = {}

---Validate a recipe structure
---@param recipe table The recipe to validate
---@return boolean valid Whether the recipe is valid
---@return string|nil error Error message if invalid
local function validateRecipe(recipe)
    if not recipe.type or (recipe.type ~= "shaped" and recipe.type ~= "shapeless") then
        return false, "Recipe must have type 'shaped' or 'shapeless'"
    end
    
    if not recipe.output or type(recipe.output) ~= "string" then
        return false, "Recipe must have a valid output item ID"
    end
    
    if recipe.type == "shaped" then
        if not recipe.pattern or type(recipe.pattern) ~= "table" or #recipe.pattern == 0 then
            return false, "Shaped recipe must have a pattern array"
        end
        
        if not recipe.key or type(recipe.key) ~= "table" then
            return false, "Shaped recipe must have a key table"
        end
        
        -- Validate pattern dimensions (must be 1-3 rows, each 1-3 chars)
        if #recipe.pattern > 3 then
            return false, "Pattern cannot have more than 3 rows"
        end
        
        for i, row in ipairs(recipe.pattern) do
            if type(row) ~= "string" or #row > 3 or #row == 0 then
                return false, string.format("Pattern row %d must be 1-3 characters", i)
            end
        end
        
        -- Validate all pattern characters have key mappings
        for _, row in ipairs(recipe.pattern) do
            for i = 1, #row do
                local char = row:sub(i, i)
                if char ~= " " and not recipe.key[char] then
                    return false, string.format("Pattern character '%s' has no key mapping", char)
                end
            end
        end
        
    elseif recipe.type == "shapeless" then
        if not recipe.ingredients or type(recipe.ingredients) ~= "table" or #recipe.ingredients == 0 then
            return false, "Shapeless recipe must have ingredients array"
        end
        
        -- Validate ingredients format
        for i, ingredient in ipairs(recipe.ingredients) do
            if not ingredient.item then
                return false, string.format("Ingredient %d must have an 'item' field", i)
            end
            if ingredient.count and (type(ingredient.count) ~= "number" or ingredient.count < 1) then
                return false, string.format("Ingredient %d count must be a positive number", i)
            end
        end
    end
    
    return true, nil
end

---Normalize a recipe to internal format
---@param recipe table The recipe to normalize
---@return table normalized The normalized recipe
local function normalizeRecipe(recipe)
    local normalized = {
        type = recipe.type,
        output = recipe.output,
        outputCount = recipe.outputCount or 1,
        priority = recipe.priority or 100,
        source = "override",
    }
    
    if recipe.type == "shaped" then
        normalized.pattern = recipe.pattern
        normalized.key = recipe.key
        
        -- Build ingredients list from pattern
        local ingredientCounts = {}
        for _, row in ipairs(recipe.pattern) do
            for i = 1, #row do
                local char = row:sub(i, i)
                if char ~= " " and recipe.key[char] then
                    local item = recipe.key[char]
                    ingredientCounts[item] = (ingredientCounts[item] or 0) + 1
                end
            end
        end
        
        normalized.ingredients = {}
        for item, count in pairs(ingredientCounts) do
            table.insert(normalized.ingredients, {item = item, count = count})
        end
        
    elseif recipe.type == "shapeless" then
        normalized.ingredients = {}
        for _, ingredient in ipairs(recipe.ingredients) do
            table.insert(normalized.ingredients, {
                item = ingredient.item,
                count = ingredient.count or 1
            })
        end
    end
    
    -- Copy any additional fields (like NBT data)
    if recipe.nbt then
        normalized.nbt = recipe.nbt
    end
    if recipe.metadata then
        normalized.metadata = recipe.metadata
    end
    
    return normalized
end

---Add or update a custom recipe
---@param output string The output item ID
---@param recipe table The recipe definition
---@return boolean success Whether the recipe was added
---@return string|nil error Error message if failed
function module.add(output, recipe)
    local valid, err = validateRecipe(recipe)
    if not valid then
        logger.warn(string.format("Invalid recipe for %s: %s", output, err))
        return false, err
    end
    
    local normalized = normalizeRecipe(recipe)
    
    local all = overrides.get("recipes") or {}
    if not all[output] then
        all[output] = {}
    end
    
    -- Add the recipe
    table.insert(all[output], normalized)
    overrides.set("recipes", all)
    
    logger.info(string.format("Added custom recipe for %s (type: %s)", output, recipe.type))
    return true, nil
end

---Add multiple custom recipes at once
---@param recipes table Table of {output -> recipe array}
---@return number added Number of recipes successfully added
---@return number failed Number of recipes that failed validation
function module.addBatch(recipes)
    local added, failed = 0, 0
    
    for output, recipeList in pairs(recipes) do
        -- Handle single recipe or array
        local list = recipeList
        if recipeList.type then
            list = {recipeList}
        end
        
        for _, recipe in ipairs(list) do
            local success = module.add(output, recipe)
            if success then
                added = added + 1
            else
                failed = failed + 1
            end
        end
    end
    
    logger.info(string.format("Batch import: %d added, %d failed", added, failed))
    return added, failed
end

---Remove a custom recipe
---@param output string The output item ID
---@param index? number Optional index to remove specific recipe (1-based), or nil to remove all
function module.remove(output, index)
    local all = overrides.get("recipes") or {}
    
    if not all[output] then
        return
    end
    
    if index then
        if all[output][index] then
            table.remove(all[output], index)
            logger.info(string.format("Removed custom recipe %d for %s", index, output))
        end
        
        -- Clean up if no recipes left
        if #all[output] == 0 then
            all[output] = nil
        end
    else
        all[output] = nil
        logger.info(string.format("Removed all custom recipes for %s", output))
    end
    
    overrides.set("recipes", all)
end

---Clear all custom recipes
function module.clear()
    overrides.set("recipes", {})
    logger.info("Cleared all custom recipes")
end

---Get custom recipes for an output
---@param output string The output item ID
---@return table recipes Array of custom recipes, or empty array
function module.get(output)
    if not module.isEnabled() then
        return {}
    end
    
    local all = overrides.get("recipes") or {}
    return all[output] or {}
end

---Get all custom recipes
---@return table recipes Table of {output -> recipes array}
function module.getAll()
    if not module.isEnabled() then
        return {}
    end
    
    return overrides.get("recipes") or {}
end

---Check if custom recipes exist for an output
---@param output string The output item ID
---@return boolean hasRecipes Whether custom recipes exist
function module.has(output)
    if not module.isEnabled() then
        return false
    end
    
    local all = overrides.get("recipes") or {}
    return all[output] ~= nil and #all[output] > 0
end

---Enable custom recipes
function module.enable()
    overrides.set("enabled", true)
    logger.info("Custom recipes enabled")
end

---Disable custom recipes
function module.disable()
    overrides.set("enabled", false)
    logger.info("Custom recipes disabled")
end

---Check if custom recipes are enabled
---@return boolean enabled Whether custom recipes are enabled
function module.isEnabled()
    return overrides.get("enabled") ~= false  -- Default to true
end

---Count total custom recipes
---@return number count Total number of custom recipes
function module.count()
    if not module.isEnabled() then
        return 0
    end
    
    local all = overrides.get("recipes") or {}
    local count = 0
    for _, recipes in pairs(all) do
        count = count + #recipes
    end
    return count
end

---Import recipes from a table (replaces existing)
---@param recipes table Table of {output -> recipe or recipe array}
function module.import(recipes)
    overrides.set("recipes", {})
    return module.addBatch(recipes)
end

---Export all recipes to a table
---@return table recipes All custom recipes
function module.export()
    return overrides.get("recipes") or {}
end

---Create a shaped recipe helper
---@param pattern table Array of pattern strings (1-3 rows, each 1-3 chars)
---@param key table Mapping of pattern characters to items {char = "item:id"}
---@param output string The output item ID
---@param count? number Output count (default: 1)
---@param priority? number Recipe priority (lower = higher priority, default: 100)
---@return table recipe A shaped recipe definition
function module.shaped(pattern, key, output, count, priority)
    return {
        type = "shaped",
        pattern = pattern,
        key = key,
        output = output,
        outputCount = count or 1,
        priority = priority or 100
    }
end

---Create a shapeless recipe helper
---@param ingredients table Array of {item = "item:id", count = number}
---@param output string The output item ID
---@param count? number Output count (default: 1)
---@param priority? number Recipe priority (lower = higher priority, default: 100)
---@return table recipe A shapeless recipe definition
function module.shapeless(ingredients, output, count, priority)
    return {
        type = "shapeless",
        ingredients = ingredients,
        output = output,
        outputCount = count or 1,
        priority = priority or 100
    }
end

return module
