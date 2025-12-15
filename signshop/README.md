# SignShop

CC: Tweaked program that creates plugin-like SignShops with automated item dispensing and Krist payment processing.

## Installation

Install SignShop on a disk drive to enable automatic startup for connected computers and turtles:

```text
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/signshop/install.lua
```

## Components

- **Server** - Runs on a regular computer, manages inventory, products, and Krist payments
- **Aisle** - Runs on turtles, handles item dispensing from storage to customers

## Updating

To update SignShop and its libraries, run:

```text
update            # Update all components
update libs       # Update only libraries  
update signshop   # Update only SignShop files
```

## Features

- Automatic item dispensing via networked turtles
- Krist payment integration via ShopK
- ShopSync broadcasting for shop directories
- Interactive form-based setup using FormUI
- Persistent data storage with automatic recovery
- **Display Monitors** - Multiple monitors showing product catalogs, prices, and stock
- **Product Categories** - Organize products into categories for display grouping
- **Stock Display Limits** - Configurable max stock shown on signs and ShopSync

## Display Monitors

SignShop supports multiple display monitors with different configurations:

### Display Types

- **catalog** - Shows all products with prices, organized by category
- **stock** - Shows all products with stock levels (sorted by stock)
- **category** - Shows products from specific categories only
- **sales_feed** - Live scrolling sales feed

### Configuration

Enable display monitors in settings and use the display manager to add monitors:

```lua
-- Example: Add a catalog display
displayManager.addDisplay({
    id = "main_catalog",
    peripheral = "monitor_0",
    displayType = "catalog",
    title = "Shop Catalog",
    refreshRate = 10,
    filter = {
        categories = nil,  -- All categories (or {"tools", "food"} for specific)
        sortBy = "category",
    },
    options = {
        showStock = true,
        showPrice = true,
        groupByCategory = true,
    },
})
```

### Filtering Options

- `categories` - List of category IDs to show (nil = all)
- `products` - List of specific product metas to show
- `minStock` / `maxStock` - Filter by stock levels
- `sortBy` - "name", "price", "stock", or "category"
- `sortDesc` - true for descending order

## Product Categories

Organize products into categories for better display organization:

```lua
-- Create a category
categoryManager.createCategory("tools", "Tools", colors.orange, "T")

-- Assign a product to a category
categoryManager.setProductCategory("diamond_pickaxe", "tools")

-- Get all products in a category
local products = categoryManager.getProductsInCategory("tools")
```

## Stock Display Limits

Limit the maximum stock shown on signs and ShopSync to hide your actual inventory:

- Set `signshop.max_stock_display` in settings (0 = unlimited)
- Stock above the limit will show as "X+" (e.g., "100+" if limit is 100)

## Requirements

- Wired modems for inventory and turtle communication
- Wireless modem for Krist/ShopSync
- Signs with product information formatted as:
  - Line 1: Product name (part 1)
  - Line 2: Product name (part 2)
  - Line 3: `<price> <aisle-name>`
  - Line 4: Product meta identifier

