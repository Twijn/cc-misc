--- AutoCrafter Crafting Library
--- Handles crafting logic and job preparation.
---
---@version 1.3.0

local VERSION = "1.3.0"

local crafting = {}

-- Lazy load tag config to avoid circular dependencies
local tagConfig = nil
local function getTags()
    if not tagConfig then
        local success, tags = pcall(require, "config.tags")
        if success then
            tagConfig = tags
        else
            -- Fallback: no tag support
            tagConfig = {
                isTag = function() return false end,
                resolve = function(tag) return nil, 0 end,
                getTotalStock = function() return 0 end,
            }
        end
    end
    return tagConfig
end

---Resolve an ingredient to an actual item and get its stock
---Handles both regular items and tags (prefixed with #)
---@param ingredient string The ingredient (item ID or tag)
---@param stockLevels table Current stock levels
---@return string item The resolved item ID
---@return number stock The stock level for this item
local function resolveIngredient(ingredient, stockLevels)
    local tags = getTags()
    if tags.isTag(ingredient) then
        local item, stock = tags.resolve(ingredient, stockLevels)
        if item then
            return item, stock
        end
        -- Tag not mapped, return as-is (will fail to find stock)
        return ingredient, 0
    end
    return ingredient, stockLevels[ingredient] or 0
end

-- Maximum stack sizes for common items (default 64)
local MAX_STACK_SIZES = {
    ["minecraft:ender_pearl"] = 16,
    ["minecraft:snowball"] = 16,
    ["minecraft:egg"] = 16,
    ["minecraft:bucket"] = 16,
    ["minecraft:water_bucket"] = 1,
    ["minecraft:lava_bucket"] = 1,
    ["minecraft:milk_bucket"] = 1,
    ["minecraft:honey_bottle"] = 16,
    ["minecraft:potion"] = 1,
    ["minecraft:splash_potion"] = 1,
    ["minecraft:lingering_potion"] = 1,
}

---Get the maximum stack size for an item
---@param item string The item ID
---@return number maxStack The maximum stack size
function crafting.getMaxStackSize(item)
    return MAX_STACK_SIZES[item] or 64
end

---Calculate how many of an item can be crafted with available materials
---@param recipe table The recipe to evaluate
---@param stockLevels table Current stock levels of all items
---@return number count How many can be crafted
function crafting.canCraft(recipe, stockLevels)
    local minCrafts = math.huge
    
    for _, ingredient in ipairs(recipe.ingredients) do
        local item, available = resolveIngredient(ingredient.item, stockLevels)
        local possible = math.floor(available / ingredient.count)
        minCrafts = math.min(minCrafts, possible)
    end
    
    if minCrafts == math.huge then
        return 0
    end
    
    return minCrafts * recipe.outputCount
end

---Check if a recipe has all required materials
---@param recipe table The recipe to check
---@param stockLevels table Current stock levels
---@param quantity number How many to craft
---@return boolean hasAll Whether all materials are available
---@return table missing Table of missing materials {item, needed, have}
function crafting.hasMaterials(recipe, stockLevels, quantity)
    local crafts = math.ceil(quantity / recipe.outputCount)
    local missing = {}
    local hasAll = true
    
    for _, ingredient in ipairs(recipe.ingredients) do
        local item, have = resolveIngredient(ingredient.item, stockLevels)
        local needed = ingredient.count * crafts
        
        if have < needed then
            hasAll = false
            table.insert(missing, {
                item = item,
                originalItem = ingredient.item,  -- Keep original for display (may be tag)
                needed = needed,
                have = have,
                short = needed - have,
            })
        end
    end
    
    return hasAll, missing
end

---Calculate the maximum items of any single ingredient per grid slot for a recipe
---For shapeless recipes, each ingredient is spread across separate slots (1 per slot per craft)
---For shaped recipes, we need to check the pattern for max items per slot
---@param recipe table The recipe to analyze
---@return table slotMaxCounts Map of item -> max count per slot per craft
local function getMaxItemsPerSlot(recipe)
    local slotMaxCounts = {}
    
    if recipe.type == "shaped" then
        -- For shaped recipes, check pattern to find max items of same type in any slot
        -- Usually 1, but count occurrences per slot position
        local slotItems = {}
        for row = 1, #recipe.pattern do
            local line = recipe.pattern[row]
            for col = 1, #line do
                local char = line:sub(col, col)
                local slot = (row - 1) * 3 + col
                if char ~= " " and recipe.key[char] then
                    slotItems[slot] = recipe.key[char]
                end
            end
        end
        -- Each slot can only have 1 item per craft in shaped recipes
        for _, item in pairs(slotItems) do
            slotMaxCounts[item] = 1
        end
    else
        -- For shapeless recipes, items are spread across slots
        -- Each slot gets 1 item per craft (spread evenly)
        for _, ingredient in ipairs(recipe.ingredients) do
            slotMaxCounts[ingredient.item] = 1
        end
    end
    
    return slotMaxCounts
end

---Calculate maximum crafts possible based on material availability and stack limits
---@param recipe table The recipe to craft
---@param stockLevels table Current stock levels
---@return number maxCrafts Maximum number of crafts possible
function crafting.calculateMaxCrafts(recipe, stockLevels)
    local maxCrafts = math.huge
    
    -- Get the actual per-slot counts for stack limit calculation
    local slotMaxCounts = getMaxItemsPerSlot(recipe)
    
    for _, ingredient in ipairs(recipe.ingredients) do
        local item, available = resolveIngredient(ingredient.item, stockLevels)
        local possible = math.floor(available / ingredient.count)
        maxCrafts = math.min(maxCrafts, possible)
        
        -- Limit by stack size per slot based on actual items per slot
        -- Each slot can hold max 64 items (or less for certain items)
        local stackLimit = crafting.getMaxStackSize(item)
        local itemsPerSlot = slotMaxCounts[ingredient.item] or 1
        local maxPerSlot = math.floor(stackLimit / itemsPerSlot)
        maxCrafts = math.min(maxCrafts, maxPerSlot)
    end
    
    if maxCrafts == math.huge then
        return 0
    end
    
    return maxCrafts
end

---Create a crafting job
---@param recipe table The recipe to craft
---@param quantity number Desired output quantity
---@param stockLevels table Current stock levels
---@param allowPartial? boolean Whether to allow partial crafts (default: true)
---@return table|nil job The crafting job or nil if not possible
---@return table|nil missing Table of missing materials if job not possible
function crafting.createJob(recipe, quantity, stockLevels, allowPartial)
    if allowPartial == nil then allowPartial = true end
    
    local outputCount = recipe.outputCount or 1
    local desiredCrafts = math.ceil(quantity / outputCount)
    
    -- Calculate how many we can actually craft based on materials and stack limits
    local maxCrafts = crafting.calculateMaxCrafts(recipe, stockLevels)
    
    if maxCrafts == 0 then
        -- No materials available - return missing info
        local _, missing = crafting.hasMaterials(recipe, stockLevels, quantity)
        return nil, missing
    end
    
    -- Determine actual crafts to perform
    local crafts = math.min(desiredCrafts, maxCrafts)
    
    -- If not allowing partial and we can't craft the full amount, fail
    if not allowPartial and crafts < desiredCrafts then
        local _, missing = crafting.hasMaterials(recipe, stockLevels, quantity)
        return nil, missing
    end
    
    -- Build the job
    local job = {
        id = os.epoch("utc"),
        recipe = recipe,
        crafts = crafts,
        expectedOutput = crafts * outputCount,
        materials = {},
        resolvedItems = {},  -- Maps tags to resolved item IDs
        status = "pending",
        created = os.epoch("utc"),
    }
    
    -- Calculate exact materials needed (resolve tags to actual items)
    for _, ingredient in ipairs(recipe.ingredients) do
        local item = resolveIngredient(ingredient.item, stockLevels)
        job.materials[item] = (job.materials[item] or 0) + (ingredient.count * crafts)
        -- Track tag-to-item resolution for the crafter
        if getTags().isTag(ingredient.item) then
            job.resolvedItems[ingredient.item] = item
        end
    end
    
    return job
end

---Convert a slot number to turtle inventory slot
---Turtle inventory: 1-16, crafting area: depends on crafty turtle API
---@param gridSlot number 1-9 grid slot
---@return number turtleSlot The corresponding turtle slot
function crafting.gridToTurtleSlot(gridSlot)
    -- Crafty turtle uses slots 1-9 directly for crafting
    -- We need to map 3x3 grid to turtle slots
    -- Turtle slots 1-4 are row 1-4 of inventory
    -- For crafting, we use slots 1,2,3 for row 1, 5,6,7 for row 2, 9,10,11 for row 3
    local row = math.ceil(gridSlot / 3)
    local col = ((gridSlot - 1) % 3) + 1
    return (row - 1) * 4 + col
end

---Convert turtle slot to grid slot
---@param turtleSlot number The turtle inventory slot
---@return number|nil gridSlot The grid slot or nil if not a grid slot
function crafting.turtleSlotToGrid(turtleSlot)
    local craftingSlots = {1, 2, 3, 5, 6, 7, 9, 10, 11}
    for grid, turtle in ipairs(craftingSlots) do
        if turtle == turtleSlot then
            return grid
        end
    end
    return nil
end

---Get list of turtle slots used for crafting
---@return table slots Array of turtle slot numbers
function crafting.getCraftingSlots()
    return {1, 2, 3, 5, 6, 7, 9, 10, 11}
end

---Get turtle slot for crafting output
---@return number slot The output slot
function crafting.getOutputSlot()
    return 16
end

---Get available slots for material storage (non-crafting slots)
---@return table slots Array of available slot numbers
function crafting.getStorageSlots()
    return {4, 8, 12, 13, 14, 15, 16}
end

---Build instructions for turtle to craft
---@param recipe table The recipe to craft
---@return table instructions Array of {action, slot, item, count}
function crafting.buildInstructions(recipe)
    local grid = {}
    for i = 1, 9 do grid[i] = nil end
    
    if recipe.type == "shaped" then
        local pattern = recipe.pattern
        local key = recipe.key
        
        for row = 1, #pattern do
            local line = pattern[row]
            for col = 1, #line do
                local char = line:sub(col, col)
                local gridSlot = (row - 1) * 3 + col
                if char ~= " " and key[char] then
                    grid[gridSlot] = key[char]
                end
            end
        end
    else -- shapeless
        local slot = 1
        for _, ingredient in ipairs(recipe.ingredients) do
            for _ = 1, ingredient.count do
                grid[slot] = ingredient.item
                slot = slot + 1
            end
        end
    end
    
    -- Convert to turtle instructions
    local instructions = {}
    for gridSlot = 1, 9 do
        if grid[gridSlot] then
            table.insert(instructions, {
                action = "place",
                gridSlot = gridSlot,
                turtleSlot = crafting.gridToTurtleSlot(gridSlot),
                item = grid[gridSlot],
                count = 1,
            })
        end
    end
    
    return instructions
end

---Estimate time to complete a crafting job
---@param job table The crafting job
---@return number seconds Estimated time in seconds
function crafting.estimateTime(job)
    -- Rough estimate: 0.5 seconds per craft operation + 2 seconds for material gathering
    return (job.crafts * 0.5) + 2
end

crafting.VERSION = VERSION

return crafting
