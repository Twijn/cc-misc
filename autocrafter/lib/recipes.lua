--- AutoCrafter Recipe Library
--- Loads and parses crafting recipes from ROM.
---
--- Supports both shaped and shapeless recipes from Minecraft's JSON format.
---
---@version 1.0.0

local VERSION = "1.0.0"

local recipes = {}
local recipeCache = {}
local recipesByOutput = {}

---Parse a shaped recipe JSON into a usable format
---@param data table The parsed JSON recipe data
---@return table|nil recipe The parsed recipe or nil if invalid
local function parseShaped(data)
    if not data.pattern or not data.key or not data.result then
        return nil
    end
    
    local recipe = {
        type = "shaped",
        output = data.result.item or data.result.id,
        outputCount = data.result.count or 1,
        pattern = data.pattern,
        key = {},
        ingredients = {},
    }
    
    -- Parse key mapping
    for char, ingredient in pairs(data.key) do
        if ingredient.item then
            recipe.key[char] = ingredient.item
        elseif ingredient.tag then
            recipe.key[char] = "#" .. ingredient.tag -- prefix tags with #
        elseif type(ingredient) == "table" and ingredient[1] then
            -- Multiple options - take first for now
            recipe.key[char] = ingredient[1].item or ingredient[1].tag
        end
    end
    
    -- Build ingredient list with counts
    local ingredientCounts = {}
    for _, row in ipairs(data.pattern) do
        for i = 1, #row do
            local char = row:sub(i, i)
            if char ~= " " and recipe.key[char] then
                local item = recipe.key[char]
                ingredientCounts[item] = (ingredientCounts[item] or 0) + 1
            end
        end
    end
    
    for item, count in pairs(ingredientCounts) do
        table.insert(recipe.ingredients, {item = item, count = count})
    end
    
    return recipe
end

---Parse a shapeless recipe JSON into a usable format
---@param data table The parsed JSON recipe data
---@return table|nil recipe The parsed recipe or nil if invalid
local function parseShapeless(data)
    if not data.ingredients or not data.result then
        return nil
    end
    
    local recipe = {
        type = "shapeless",
        output = data.result.item or data.result.id,
        outputCount = data.result.count or 1,
        ingredients = {},
    }
    
    -- Build ingredient list with counts
    local ingredientCounts = {}
    for _, ingredient in ipairs(data.ingredients) do
        local item = nil
        if ingredient.item then
            item = ingredient.item
        elseif ingredient.tag then
            item = "#" .. ingredient.tag
        elseif type(ingredient) == "table" and ingredient[1] then
            item = ingredient[1].item or ingredient[1].tag
        end
        
        if item then
            ingredientCounts[item] = (ingredientCounts[item] or 0) + 1
        end
    end
    
    for item, count in pairs(ingredientCounts) do
        table.insert(recipe.ingredients, {item = item, count = count})
    end
    
    return recipe
end

---Load a single recipe file
---@param path string The path to the recipe JSON file
---@return table|nil recipe The parsed recipe or nil if failed
local function loadRecipeFile(path)
    if recipeCache[path] then
        return recipeCache[path]
    end
    
    if not fs.exists(path) then
        return nil
    end
    
    local file = fs.open(path, "r")
    if not file then
        return nil
    end
    
    local content = file.readAll()
    file.close()
    
    local success, data = pcall(textutils.unserializeJSON, content)
    if not success or not data then
        return nil
    end
    
    local recipe = nil
    
    if data.type == "minecraft:crafting_shaped" then
        recipe = parseShaped(data)
    elseif data.type == "minecraft:crafting_shapeless" then
        recipe = parseShapeless(data)
    end
    
    if recipe then
        recipe.source = path
        recipeCache[path] = recipe
    end
    
    return recipe
end

---Scan a directory for recipe files
---@param dir string The directory to scan
---@return number count The number of recipes loaded
local function scanDirectory(dir)
    if not fs.exists(dir) or not fs.isDir(dir) then
        return 0
    end
    
    local count = 0
    local files = fs.list(dir)
    
    for _, file in ipairs(files) do
        local path = dir .. "/" .. file
        if fs.isDir(path) then
            count = count + scanDirectory(path)
        elseif file:match("%.json$") then
            local recipe = loadRecipeFile(path)
            if recipe then
                count = count + 1
                
                -- Index by output item
                local output = recipe.output
                if not recipesByOutput[output] then
                    recipesByOutput[output] = {}
                end
                table.insert(recipesByOutput[output], recipe)
            end
        end
    end
    
    return count
end

---Initialize the recipe system by scanning ROM
---@param paths? table Array of paths to scan (defaults to standard ROM paths)
---@return number count Total number of recipes loaded
function recipes.init(paths)
    paths = paths or {
        "/rom/mcdata/minecraft/recipes",
        "/rom/mcdata",
    }
    
    recipeCache = {}
    recipesByOutput = {}
    
    local totalCount = 0
    for _, path in ipairs(paths) do
        totalCount = totalCount + scanDirectory(path)
    end
    
    return totalCount
end

---Get all recipes that produce a specific item
---@param output string The output item ID (e.g., "minecraft:torch")
---@return table recipes Array of recipes that produce this item
function recipes.getRecipesFor(output)
    return recipesByOutput[output] or {}
end

---Get a single recipe for an item (prefers simplest recipe)
---@param output string The output item ID
---@return table|nil recipe A recipe for the item or nil
function recipes.getRecipeFor(output)
    local available = recipesByOutput[output]
    if not available or #available == 0 then
        return nil
    end
    
    -- Return recipe with fewest unique ingredients
    local best = available[1]
    local bestCount = #best.ingredients
    
    for i = 2, #available do
        if #available[i].ingredients < bestCount then
            best = available[i]
            bestCount = #best.ingredients
        end
    end
    
    return best
end

---Check if an item can be crafted
---@param output string The output item ID
---@return boolean canCraft Whether the item has a known recipe
function recipes.canCraft(output)
    return recipesByOutput[output] ~= nil and #recipesByOutput[output] > 0
end

---Get all known recipes
---@return table recipes Table of all recipes indexed by output
function recipes.getAll()
    return recipesByOutput
end

---Search for recipes by name
---@param query string Search query (partial match)
---@return table results Array of {output, recipes} pairs
function recipes.search(query)
    local results = {}
    query = query:lower()
    
    for output, recipeList in pairs(recipesByOutput) do
        if output:lower():find(query, 1, true) then
            table.insert(results, {
                output = output,
                recipes = recipeList,
            })
        end
    end
    
    table.sort(results, function(a, b)
        return a.output < b.output
    end)
    
    return results
end

---Get count of all loaded recipes
---@return number count Total number of loaded recipes
function recipes.count()
    local count = 0
    for _, recipeList in pairs(recipesByOutput) do
        count = count + #recipeList
    end
    return count
end

---Calculate materials needed to craft an item
---@param output string The output item ID
---@param quantity number How many to craft
---@return table|nil materials Table of {item, count} pairs, or nil if no recipe
function recipes.getMaterials(output, quantity)
    local recipe = recipes.getRecipeFor(output)
    if not recipe then
        return nil
    end
    
    -- Calculate how many crafting operations needed
    local crafts = math.ceil(quantity / recipe.outputCount)
    
    local materials = {}
    for _, ingredient in ipairs(recipe.ingredients) do
        materials[ingredient.item] = (materials[ingredient.item] or 0) + (ingredient.count * crafts)
    end
    
    return materials
end

---Convert a recipe pattern to a turtle crafting grid (3x3)
---@param recipe table The recipe to convert
---@return table|nil grid Array of 9 slots with item IDs or nil
function recipes.toGrid(recipe)
    if recipe.type == "shaped" then
        local grid = {}
        for i = 1, 9 do grid[i] = nil end
        
        local pattern = recipe.pattern
        local key = recipe.key
        
        for row = 1, #pattern do
            local line = pattern[row]
            for col = 1, #line do
                local char = line:sub(col, col)
                local slot = (row - 1) * 3 + col
                if char ~= " " and key[char] then
                    grid[slot] = key[char]
                end
            end
        end
        
        return grid
    elseif recipe.type == "shapeless" then
        local grid = {}
        for i = 1, 9 do grid[i] = nil end
        
        local slot = 1
        for _, ingredient in ipairs(recipe.ingredients) do
            for _ = 1, ingredient.count do
                grid[slot] = ingredient.item
                slot = slot + 1
                if slot > 9 then break end
            end
        end
        
        return grid
    end
    
    return nil
end

recipes.VERSION = VERSION

return recipes
