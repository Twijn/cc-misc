# Recipe Overrides and Custom Recipes

The AutoCrafter supports adding custom recipes and overriding existing ones with full control over ingredients, output, and crafting grid layout.

## Quick Start - Using the UI

The easiest way to add custom recipes is through the interactive UI:

```lua
-- From the autocrafter directory, run:
shell.run("tools/recipes.lua")

-- Or quick add mode:
shell.run("tools/recipes.lua", "quick")
```

The UI provides:
- **Add New Recipe**: Step-by-step forms for shaped or shapeless recipes
- **List Recipes**: View all configured custom recipes
- **Enable/Disable**: Toggle custom recipes on/off without deleting
- **Clear All**: Remove all custom recipes (with confirmation)

### UI Walkthrough

1. **Main Menu**: Choose to add, list, or manage recipes
2. **Recipe Type**: Select shaped (exact grid) or shapeless (any position)
3. **Configure Details**:
   - Enter output item (e.g., `minecraft:torch`)
   - Set output count (how many items produced)
   - Set priority (lower numbers = higher priority)
4. **Add Ingredients**:
   - **Shapeless**: List items one per line (`minecraft:stick 2`)
   - **Shaped**: Define pattern rows and map letters to items
5. **Save**: Recipe is validated and saved automatically

## Features

- **Add New Recipes**: Create recipes for items that don't have vanilla recipes
- **Override Existing Recipes**: Replace or supplement existing recipes with custom variants
- **Shaped Recipes**: Define exact grid patterns (like vanilla crafting tables)
- **Shapeless Recipes**: Define recipes where position doesn't matter
- **Tag Support**: Use tags like `#c:iron_ingots` in recipe ingredients
- **Priority Control**: Set recipe priority to control which variant is used
- **Per-Slot Customization**: Full control over each crafting grid slot

## API Reference

### Loading the Module

```lua
local recipeOverrides = require("config.recipeoverrides")
```

### Adding Recipes

#### Shaped Recipe Example
```lua
-- Diamond block from 9 diamonds in 3x3 pattern
recipeOverrides.add("minecraft:diamond_block", {
    type = "shaped",
    pattern = {"DDD", "DDD", "DDD"},
    key = {D = "minecraft:diamond"},
    output = "minecraft:diamond_block",
    outputCount = 1,
    priority = 1  -- Lower = higher priority
})

-- Stick from planks (2x1 pattern)
recipeOverrides.add("minecraft:stick", {
    type = "shaped",
    pattern = {"P", "P"},
    key = {P = "#minecraft:planks"},  -- Use tag
    output = "minecraft:stick",
    outputCount = 4
})

-- Complex pattern with multiple ingredients
recipeOverrides.add("minecraft:compass", {
    type = "shaped",
    pattern = {" I ", "IRI", " I "},
    key = {
        I = "minecraft:iron_ingot",
        R = "minecraft:redstone"
    },
    output = "minecraft:compass",
    outputCount = 1
})
```

#### Shapeless Recipe Example
```lua
-- Simple shapeless recipe
recipeOverrides.add("minecraft:purple_dye", {
    type = "shapeless",
    ingredients = {
        {item = "minecraft:red_dye", count = 1},
        {item = "minecraft:blue_dye", count = 1}
    },
    output = "minecraft:purple_dye",
    outputCount = 2
})

-- Using tags in shapeless recipe
recipeOverrides.add("custom:mixed_metal", {
    type = "shapeless",
    ingredients = {
        {item = "#c:iron_ingots", count = 2},
        {item = "#c:copper_ingots", count = 2},
        {item = "#c:gold_ingots", count = 1}
    },
    output = "custom:mixed_metal",
    outputCount = 5
})
```

### Helper Functions

```lua
-- Shaped recipe helper
local recipe = recipeOverrides.shaped(
    {"III", " S ", " S "},  -- pattern
    {I = "minecraft:iron_ingot", S = "minecraft:stick"},  -- key
    "minecraft:iron_pickaxe",  -- output
    1,  -- output count
    10  -- priority (optional)
)
recipeOverrides.add("minecraft:iron_pickaxe", recipe)

-- Shapeless recipe helper
local recipe = recipeOverrides.shapeless(
    {{item = "minecraft:coal", count = 8}, {item = "minecraft:stick", count = 1}},
    "minecraft:torch",
    8,  -- output count
    5   -- priority (optional)
)
recipeOverrides.add("minecraft:torch", recipe)
```

### Batch Operations

```lua
-- Add multiple recipes at once
local recipes = {
    ["minecraft:torch"] = {
        {
            type = "shapeless",
            ingredients = {
                {item = "minecraft:coal", count = 1},
                {item = "minecraft:stick", count = 1}
            },
            output = "minecraft:torch",
            outputCount = 4
        }
    },
    ["minecraft:diamond_block"] = {
        {
            type = "shaped",
            pattern = {"DDD", "DDD", "DDD"},
            key = {D = "minecraft:diamond"},
            output = "minecraft:diamond_block",
            outputCount = 1
        }
    }
}

local added, failed = recipeOverrides.addBatch(recipes)
print(string.format("Added %d recipes, %d failed", added, failed))
```

### Managing Recipes

```lua
-- Get custom recipes for an item
local recipes = recipeOverrides.get("minecraft:diamond_block")

-- Check if custom recipes exist
if recipeOverrides.has("minecraft:torch") then
    print("Custom torch recipe exists")
end

-- Remove specific recipe (by index)
recipeOverrides.remove("minecraft:torch", 1)

-- Remove all recipes for an item
recipeOverrides.remove("minecraft:torch")

-- Clear all custom recipes
recipeOverrides.clear()

-- Count total custom recipes
local count = recipeOverrides.count()
print(string.format("%d custom recipes loaded", count))
```

### Enable/Disable

```lua
-- Disable all custom recipes (doesn't delete them)
recipeOverrides.disable()

-- Enable custom recipes
recipeOverrides.enable()

-- Check if enabled
if recipeOverrides.isEnabled() then
    print("Custom recipes are active")
end
```

### Import/Export

```lua
-- Export all recipes to a table (for backup or transfer)
local allRecipes = recipeOverrides.export()

-- Import recipes (replaces existing)
recipeOverrides.import(allRecipes)
```

## Pattern Format

### Shaped Recipes

Patterns are arrays of 1-3 strings, each 1-3 characters long:

```lua
-- 3x3 pattern
pattern = {"ABC", "DEF", "GHI"}

-- 2x2 pattern
pattern = {"AB", "CD"}

-- 1x3 pattern (vertical)
pattern = {"A", "B", "C"}

-- Patterns with spaces (empty slots)
pattern = {" A ", " B ", "   "}

-- 3x1 pattern (horizontal)
pattern = {"ABC"}
```

### Key Mapping

Each character in the pattern must have a corresponding key mapping:

```lua
key = {
    A = "minecraft:diamond",           -- Specific item
    B = "#minecraft:planks",          -- Tag (any plank)
    C = "#c:iron_ingots",             -- Common tag
    D = "minecraft:stick"
}
```

## Priority System

Lower priority values are selected first:

```lua
-- Priority 1 - will be used first
recipeOverrides.add("minecraft:stick", {
    type = "shaped",
    pattern = {"P", "P"},
    key = {P = "minecraft:oak_planks"},
    output = "minecraft:stick",
    outputCount = 4,
    priority = 1
})

-- Priority 10 - fallback if oak planks not available
recipeOverrides.add("minecraft:stick", {
    type = "shaped",
    pattern = {"P", "P"},
    key = {P = "#minecraft:planks"},
    output = "minecraft:stick",
    outputCount = 4,
    priority = 10
})
```

## Complete Example: Adding Multiple Custom Recipes

```lua
local recipeOverrides = require("config.recipeoverrides")

-- Clear existing custom recipes
recipeOverrides.clear()

-- Add custom torch recipe with better yield
recipeOverrides.add("minecraft:torch", {
    type = "shapeless",
    ingredients = {
        {item = "minecraft:coal", count = 1},
        {item = "minecraft:stick", count = 1}
    },
    output = "minecraft:torch",
    outputCount = 8,  -- More than vanilla
    priority = 1
})

-- Add custom diamond block compression
recipeOverrides.add("minecraft:diamond_block", {
    type = "shaped",
    pattern = {"DDD", "DDD", "DDD"},
    key = {D = "minecraft:diamond"},
    output = "minecraft:diamond_block",
    outputCount = 1,
    priority = 1
})

-- Add custom recipe using tags
recipeOverrides.add("custom:alloy", {
    type = "shapeless",
    ingredients = {
        {item = "#c:iron_ingots", count = 3},
        {item = "#c:copper_ingots", count = 3}
    },
    output = "custom:alloy",
    outputCount = 6
})

print("Custom recipes loaded: " .. recipeOverrides.count())
```

## Integration with AutoCrafter

Custom recipes are automatically integrated into the crafting system:

1. **Priority**: Custom recipes are checked before ROM recipes by default
2. **Tag Resolution**: Tags in custom recipes are resolved using the tag system
3. **Queue System**: Works seamlessly with the job queue and dependency resolution
4. **Crafters**: Crafters will use custom recipes when assigned jobs

The system automatically validates all recipes when they're added, ensuring they have valid structure before being saved.
