--- AutoCrafter Tag Configuration
--- Maps item tags (used in recipes) to actual items in storage.
---
--- Tags are commonly used in modded recipes (e.g., #c:redstone_dusts).
--- This file allows you to specify which items should be used when
--- a recipe calls for a tag.
---
---@version 1.0.0

local module = {}

-- Try to load persist for saving custom mappings (optional)
local tagData = nil
local function getTagData()
    if tagData == nil then
        local ok, persist = pcall(require, "lib.persist")
        if ok then
            -- Try to get cache path from config, fall back to default
            local cachePath = "/disk/data/cache"
            local configOk, config = pcall(require, "config")
            if configOk and config.cachePath then
                cachePath = config.cachePath
            end
            tagData = persist(cachePath .. "/tags.json")
        else
            -- No persist available, use empty storage
            tagData = {
                get = function() return nil end,
                set = function() end,
            }
        end
    end
    return tagData
end

-- Default tag mappings for common tags
-- Users can add/modify these via the API
local defaultMappings = {
    -- Common Fabric/Forge convention tags
    ["c:redstone_dusts"] = {"minecraft:redstone"},
    ["c:iron_ingots"] = {"minecraft:iron_ingot"},
    ["c:gold_ingots"] = {"minecraft:gold_ingot"},
    ["c:copper_ingots"] = {"minecraft:copper_ingot"},
    ["c:diamonds"] = {"minecraft:diamond"},
    ["c:emeralds"] = {"minecraft:emerald"},
    ["c:lapis"] = {"minecraft:lapis_lazuli"},
    ["c:coal"] = {"minecraft:coal", "minecraft:charcoal"},
    ["c:chests"] = {"minecraft:chest"},
    ["c:glass"] = {"minecraft:glass"},
    ["c:glass_blocks"] = {"minecraft:glass"},
    ["c:glass_panes"] = {"minecraft:glass_pane"},
    ["c:cobblestones"] = {"minecraft:cobblestone"},
    ["c:stones"] = {"minecraft:stone"},
    ["c:dyes"] = {
        "minecraft:white_dye", "minecraft:orange_dye", "minecraft:magenta_dye",
        "minecraft:light_blue_dye", "minecraft:yellow_dye", "minecraft:lime_dye",
        "minecraft:pink_dye", "minecraft:gray_dye", "minecraft:light_gray_dye",
        "minecraft:cyan_dye", "minecraft:purple_dye", "minecraft:blue_dye",
        "minecraft:brown_dye", "minecraft:green_dye", "minecraft:red_dye",
        "minecraft:black_dye"
    },
    -- Individual dye color tags
    ["c:white_dyes"] = {"minecraft:white_dye"},
    ["c:orange_dyes"] = {"minecraft:orange_dye"},
    ["c:magenta_dyes"] = {"minecraft:magenta_dye"},
    ["c:light_blue_dyes"] = {"minecraft:light_blue_dye"},
    ["c:yellow_dyes"] = {"minecraft:yellow_dye"},
    ["c:lime_dyes"] = {"minecraft:lime_dye"},
    ["c:pink_dyes"] = {"minecraft:pink_dye"},
    ["c:gray_dyes"] = {"minecraft:gray_dye"},
    ["c:light_gray_dyes"] = {"minecraft:light_gray_dye"},
    ["c:cyan_dyes"] = {"minecraft:cyan_dye"},
    ["c:purple_dyes"] = {"minecraft:purple_dye"},
    ["c:blue_dyes"] = {"minecraft:blue_dye"},
    ["c:brown_dyes"] = {"minecraft:brown_dye"},
    ["c:green_dyes"] = {"minecraft:green_dye"},
    ["c:red_dyes"] = {"minecraft:red_dye"},
    ["c:black_dyes"] = {"minecraft:black_dye"},
    ["c:wooden_chests"] = {"minecraft:chest"},
    ["c:strings"] = {"minecraft:string"},
    ["c:slimeballs"] = {"minecraft:slime_ball"},
    ["c:ender_pearls"] = {"minecraft:ender_pearl"},
    ["c:feathers"] = {"minecraft:feather"},
    ["c:leather"] = {"minecraft:leather"},
    ["c:sticks"] = {"minecraft:stick"},
    ["c:rods/wooden"] = {"minecraft:stick"},
    ["c:rods/blaze"] = {"minecraft:blaze_rod"},
    ["c:gunpowder"] = {"minecraft:gunpowder"},
    
    -- Minecraft vanilla tags
    ["minecraft:planks"] = {
        "minecraft:oak_planks", "minecraft:spruce_planks", "minecraft:birch_planks",
        "minecraft:jungle_planks", "minecraft:acacia_planks", "minecraft:dark_oak_planks",
        "minecraft:mangrove_planks", "minecraft:cherry_planks", "minecraft:bamboo_planks",
        "minecraft:crimson_planks", "minecraft:warped_planks"
    },
    ["minecraft:logs"] = {
        "minecraft:oak_log", "minecraft:spruce_log", "minecraft:birch_log",
        "minecraft:jungle_log", "minecraft:acacia_log", "minecraft:dark_oak_log",
        "minecraft:mangrove_log", "minecraft:cherry_log",
        "minecraft:crimson_stem", "minecraft:warped_stem"
    },
    ["minecraft:wooden_slabs"] = {
        "minecraft:oak_slab", "minecraft:spruce_slab", "minecraft:birch_slab",
        "minecraft:jungle_slab", "minecraft:acacia_slab", "minecraft:dark_oak_slab",
        "minecraft:mangrove_slab", "minecraft:cherry_slab", "minecraft:bamboo_slab",
        "minecraft:crimson_slab", "minecraft:warped_slab"
    },
    ["minecraft:wool"] = {
        "minecraft:white_wool", "minecraft:orange_wool", "minecraft:magenta_wool",
        "minecraft:light_blue_wool", "minecraft:yellow_wool", "minecraft:lime_wool",
        "minecraft:pink_wool", "minecraft:gray_wool", "minecraft:light_gray_wool",
        "minecraft:cyan_wool", "minecraft:purple_wool", "minecraft:blue_wool",
        "minecraft:brown_wool", "minecraft:green_wool", "minecraft:red_wool",
        "minecraft:black_wool"
    },
    ["minecraft:stone_crafting_materials"] = {"minecraft:cobblestone", "minecraft:blackstone"},
    ["minecraft:coals"] = {"minecraft:coal", "minecraft:charcoal"},
    ["minecraft:sand"] = {"minecraft:sand", "minecraft:red_sand"},
}

---Get all mappings (user + default)
---@return table mappings All tag mappings
local function getMappings()
    local data = getTagData()
    local saved = data:get("mappings") or {}
    -- Merge with defaults (user mappings override defaults)
    local merged = {}
    for tag, items in pairs(defaultMappings) do
        merged[tag] = items
    end
    for tag, items in pairs(saved) do
        merged[tag] = items
    end
    return merged
end

---Resolve a tag to available items
---Returns the first item from the mapping that exists in the provided stock
---@param tag string The tag (with or without # prefix)
---@param stockLevels? table Optional stock levels to find available item
---@return string|nil item The resolved item, or nil if no mapping
---@return number stock The stock level of the resolved item (0 if no stock provided)
function module.resolve(tag, stockLevels)
    -- Remove # prefix if present
    local cleanTag = tag:sub(1, 1) == "#" and tag:sub(2) or tag
    
    local mappings = getMappings()
    local items = mappings[cleanTag]
    
    if not items or #items == 0 then
        return nil, 0
    end
    
    -- If no stock levels provided, return first item
    if not stockLevels then
        return items[1], 0
    end
    
    -- Find the first item with stock, or the one with most stock
    local bestItem = nil
    local bestStock = 0
    
    for _, item in ipairs(items) do
        local stock = stockLevels[item] or 0
        if stock > bestStock then
            bestItem = item
            bestStock = stock
        end
    end
    
    -- If nothing in stock, return first item from mapping
    if not bestItem then
        return items[1], 0
    end
    
    return bestItem, bestStock
end

---Get all items that match a tag
---@param tag string The tag (with or without # prefix)
---@return table items Array of item IDs, or empty table if no mapping
function module.getItems(tag)
    local cleanTag = tag:sub(1, 1) == "#" and tag:sub(2) or tag
    local mappings = getMappings()
    return mappings[cleanTag] or {}
end

---Check if a tag has a mapping
---@param tag string The tag (with or without # prefix)
---@return boolean hasMaping
function module.hasMapping(tag)
    local cleanTag = tag:sub(1, 1) == "#" and tag:sub(2) or tag
    local mappings = getMappings()
    return mappings[cleanTag] ~= nil
end

---Check if an ingredient is a tag
---@param ingredient string The ingredient string
---@return boolean isTag
function module.isTag(ingredient)
    return ingredient:sub(1, 1) == "#"
end

---Add or update a tag mapping
---@param tag string The tag (with or without # prefix)
---@param items table Array of item IDs
function module.setMapping(tag, items)
    local cleanTag = tag:sub(1, 1) == "#" and tag:sub(2) or tag
    local data = getTagData()
    local saved = data:get("mappings") or {}
    saved[cleanTag] = items
    data:set("mappings", saved)
end

---Remove a tag mapping
---@param tag string The tag (with or without # prefix)
function module.removeMapping(tag)
    local cleanTag = tag:sub(1, 1) == "#" and tag:sub(2) or tag
    local data = getTagData()
    local saved = data:get("mappings") or {}
    saved[cleanTag] = nil
    data:set("mappings", saved)
end

---Get all configured tag mappings
---@return table mappings All mappings {tag -> items}
function module.getAllMappings()
    return getMappings()
end

---Get default tag mappings
---@return table mappings Default mappings {tag -> items}
function module.getDefaultMappings()
    return defaultMappings
end

---Get user-defined tag mappings (excluding defaults)
---@return table mappings User mappings {tag -> items}
function module.getUserMappings()
    local data = getTagData()
    return data:get("mappings") or {}
end

---Calculate total stock for a tag across all matching items
---@param tag string The tag (with or without # prefix)
---@param stockLevels table Stock levels for all items
---@return number totalStock Combined stock of all items matching the tag
function module.getTotalStock(tag, stockLevels)
    local items = module.getItems(tag)
    local total = 0
    for _, item in ipairs(items) do
        total = total + (stockLevels[item] or 0)
    end
    return total
end

return module
