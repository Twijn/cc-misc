--- SignShop Category Manager ---
--- Manages product categories for organization and display.
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")

local categoryData = persist("categories.json")

local manager = {}

-- Default categories if none exist
local defaultCategories = {
    {
        id = "uncategorized",
        name = "Uncategorized",
        color = colors.gray,
        icon = "?",
    },
}

--- Initialize categories if they don't exist
local function initCategories()
    if not categoryData.get("categories") then
        categoryData.set("categories", defaultCategories)
    end
    if not categoryData.get("productCategories") then
        categoryData.set("productCategories", {})
    end
end

initCategories()

--- Get all categories
---@return table List of category definitions
function manager.getCategories()
    return categoryData.get("categories") or defaultCategories
end

--- Get a category by ID
---@param categoryId string The category ID
---@return table|nil Category definition or nil if not found
function manager.getCategory(categoryId)
    local categories = manager.getCategories()
    for _, cat in ipairs(categories) do
        if cat.id == categoryId then
            return cat
        end
    end
    return nil
end

--- Create a new category
---@param id string Unique category identifier
---@param name string Display name
---@param color? number Color constant (default: colors.white)
---@param icon? string Single character icon (default: first letter of name)
---@return boolean success
---@return string|nil error
function manager.createCategory(id, name, color, icon)
    if not id or #id == 0 then
        return false, "Category ID is required"
    end
    
    if manager.getCategory(id) then
        return false, "Category already exists: " .. id
    end
    
    local categories = manager.getCategories()
    table.insert(categories, {
        id = id,
        name = name or id,
        color = color or colors.white,
        icon = icon or (name and name:sub(1, 1):upper()) or id:sub(1, 1):upper(),
    })
    
    categoryData.set("categories", categories)
    logger.info("Created category: " .. id)
    os.queueEvent("category_create", id)
    
    return true
end

--- Update a category
---@param id string Category ID to update
---@param updates table Fields to update (name, color, icon)
---@return boolean success
---@return string|nil error
function manager.updateCategory(id, updates)
    local categories = manager.getCategories()
    
    for i, cat in ipairs(categories) do
        if cat.id == id then
            if updates.name then cat.name = updates.name end
            if updates.color then cat.color = updates.color end
            if updates.icon then cat.icon = updates.icon end
            
            categories[i] = cat
            categoryData.set("categories", categories)
            logger.info("Updated category: " .. id)
            os.queueEvent("category_update", id)
            
            return true
        end
    end
    
    return false, "Category not found: " .. id
end

--- Delete a category
---@param id string Category ID to delete
---@return boolean success
---@return string|nil error
function manager.deleteCategory(id)
    if id == "uncategorized" then
        return false, "Cannot delete the uncategorized category"
    end
    
    local categories = manager.getCategories()
    
    for i, cat in ipairs(categories) do
        if cat.id == id then
            table.remove(categories, i)
            categoryData.set("categories", categories)
            
            -- Move products in this category to uncategorized
            local productCategories = categoryData.get("productCategories") or {}
            for meta, catId in pairs(productCategories) do
                if catId == id then
                    productCategories[meta] = "uncategorized"
                end
            end
            categoryData.set("productCategories", productCategories)
            
            logger.info("Deleted category: " .. id)
            os.queueEvent("category_delete", id)
            
            return true
        end
    end
    
    return false, "Category not found: " .. id
end

--- Get the category for a product
---@param productMeta string Product meta/ID
---@return string categoryId
function manager.getProductCategory(productMeta)
    local productCategories = categoryData.get("productCategories") or {}
    return productCategories[productMeta] or "uncategorized"
end

--- Set the category for a product
---@param productMeta string Product meta/ID
---@param categoryId string Category ID
---@return boolean success
---@return string|nil error
function manager.setProductCategory(productMeta, categoryId)
    if categoryId ~= "uncategorized" and not manager.getCategory(categoryId) then
        return false, "Category not found: " .. categoryId
    end
    
    local productCategories = categoryData.get("productCategories") or {}
    productCategories[productMeta] = categoryId
    categoryData.set("productCategories", productCategories)
    
    logger.info(string.format("Set product %s to category %s", productMeta, categoryId))
    os.queueEvent("product_category_change", productMeta, categoryId)
    
    return true
end

--- Remove a product from its category (sets to uncategorized)
---@param productMeta string Product meta/ID
---@return boolean success
function manager.removeProductCategory(productMeta)
    return manager.setProductCategory(productMeta, "uncategorized")
end

--- Get all products in a category
---@param categoryId string Category ID
---@return table List of product metas
function manager.getProductsInCategory(categoryId)
    local products = {}
    local productCategories = categoryData.get("productCategories") or {}
    
    for meta, catId in pairs(productCategories) do
        if catId == categoryId then
            table.insert(products, meta)
        end
    end
    
    -- For uncategorized, also include products not in any category
    if categoryId == "uncategorized" then
        local productManager = require("managers.product")
        local allProducts = productManager.getAll() or {}
        for meta, _ in pairs(allProducts) do
            if not productCategories[meta] then
                table.insert(products, meta)
            end
        end
    end
    
    return products
end

--- Get products grouped by category
---@return table Table mapping category ID to list of product metas
function manager.getProductsByCategory()
    local result = {}
    local productCategories = categoryData.get("productCategories") or {}
    
    -- Initialize all categories
    for _, cat in ipairs(manager.getCategories()) do
        result[cat.id] = {}
    end
    
    -- Add products to their categories
    for meta, catId in pairs(productCategories) do
        if not result[catId] then
            result[catId] = {}
        end
        table.insert(result[catId], meta)
    end
    
    -- Add uncategorized products
    local productManager = require("managers.product")
    local allProducts = productManager.getAll() or {}
    for meta, _ in pairs(allProducts) do
        if not productCategories[meta] then
            if not result["uncategorized"] then
                result["uncategorized"] = {}
            end
            table.insert(result["uncategorized"], meta)
        end
    end
    
    return result
end

--- Run event loop (no-op for category manager)
function manager.run()
    while true do
        sleep(3600)
    end
end

return manager
