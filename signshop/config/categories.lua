--- SignShop Categories Configuration ---
--- Defines product categories for display organization.
---
---@version 1.0.0

-- Example categories configuration:
-- Each category has a name, color, and optional icon
--
-- To add products to a category, use the category manager:
--   categoryManager.addProduct("category-id", "product-meta")
--
-- Categories will be automatically created on first use
--
-- Default categories (can be customized):
return {
    categories = {
        -- {
        --     id = "tools",
        --     name = "Tools",
        --     color = colors.orange,
        --     icon = "T",  -- Single character icon
        -- },
        -- {
        --     id = "food",
        --     name = "Food",
        --     color = colors.green,
        --     icon = "F",
        -- },
        -- {
        --     id = "building",
        --     name = "Building",
        --     color = colors.brown,
        --     icon = "B",
        -- },
    },
    -- Product to category mapping (product meta -> category id)
    productCategories = {
        -- ["diamond_pickaxe"] = "tools",
        -- ["apple"] = "food",
    },
}
