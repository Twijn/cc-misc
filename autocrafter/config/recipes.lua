--- AutoCrafter Recipe Preferences Configuration
--- Manages recipe variant preferences, priorities, and enabled/disabled states.
---
--- Example configuration structure:
--- {
---     ["minecraft:stick"] = {
---         priority = {
---             "/rom/mcdata/minecraft/recipes/stick.json",           -- First priority
---             "/rom/mcdata/minecraft/recipes/stick_from_bamboo.json" -- Second priority
---         },
---         disabled = {
---             ["/rom/mcdata/minecraft/recipes/stick_from_bamboo.json"] = true
---         }
---     }
--- }
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")

local prefs = persist("recipe-prefs.json")

prefs.setDefault("preferences", {})

local module = {}

---Get preferences for a specific output item
---@param output string The output item ID
---@return table prefs Preferences for this item {priority = {...}, disabled = {...}}
function module.get(output)
    local all = prefs.get("preferences") or {}
    return all[output] or { priority = {}, disabled = {} }
end

---Set the priority order for recipe variants
---@param output string The output item ID
---@param priorityList table Array of recipe source paths in priority order
function module.setPriority(output, priorityList)
    local all = prefs.get("preferences") or {}
    if not all[output] then
        all[output] = { priority = {}, disabled = {} }
    end
    all[output].priority = priorityList
    prefs.set("preferences", all)
    logger.info(string.format("Updated priority order for %s (%d recipes)", output, #priorityList))
end

---Set a recipe variant as preferred (moves to top of priority list)
---@param output string The output item ID
---@param recipePath string The recipe source path to prefer
function module.setPreferred(output, recipePath)
    local all = prefs.get("preferences") or {}
    if not all[output] then
        all[output] = { priority = {}, disabled = {} }
    end
    
    -- Remove from current position if exists
    local priority = all[output].priority or {}
    for i, path in ipairs(priority) do
        if path == recipePath then
            table.remove(priority, i)
            break
        end
    end
    
    -- Insert at top
    table.insert(priority, 1, recipePath)
    all[output].priority = priority
    prefs.set("preferences", all)
    logger.info(string.format("Set preferred recipe for %s: %s", output, recipePath))
end

---Enable a recipe variant
---@param output string The output item ID
---@param recipePath string The recipe source path to enable
function module.enable(output, recipePath)
    local all = prefs.get("preferences") or {}
    if not all[output] then
        return -- Nothing to enable if no preferences exist
    end
    
    if all[output].disabled then
        all[output].disabled[recipePath] = nil
    end
    prefs.set("preferences", all)
    logger.info(string.format("Enabled recipe for %s: %s", output, recipePath))
end

---Disable a recipe variant
---@param output string The output item ID
---@param recipePath string The recipe source path to disable
function module.disable(output, recipePath)
    local all = prefs.get("preferences") or {}
    if not all[output] then
        all[output] = { priority = {}, disabled = {} }
    end
    
    if not all[output].disabled then
        all[output].disabled = {}
    end
    all[output].disabled[recipePath] = true
    prefs.set("preferences", all)
    logger.info(string.format("Disabled recipe for %s: %s", output, recipePath))
end

---Check if a recipe variant is disabled
---@param output string The output item ID
---@param recipePath string The recipe source path
---@return boolean disabled Whether the recipe is disabled
function module.isDisabled(output, recipePath)
    local pref = module.get(output)
    return pref.disabled and pref.disabled[recipePath] == true
end

---Check if a recipe variant is enabled
---@param output string The output item ID
---@param recipePath string The recipe source path
---@return boolean enabled Whether the recipe is enabled
function module.isEnabled(output, recipePath)
    return not module.isDisabled(output, recipePath)
end

---Get all preferences
---@return table preferences All recipe preferences
function module.getAll()
    return prefs.get("preferences") or {}
end

---Remove all preferences for an item
---@param output string The output item ID
function module.clear(output)
    local all = prefs.get("preferences") or {}
    all[output] = nil
    prefs.set("preferences", all)
    logger.info(string.format("Cleared recipe preferences for %s", output))
end

---Remove all preferences
function module.clearAll()
    prefs.set("preferences", {})
    logger.info("Cleared all recipe preferences")
end

---Get items with custom preferences
---@return table items Array of item IDs with preferences
function module.getCustomizedItems()
    local all = prefs.get("preferences") or {}
    local items = {}
    for output, _ in pairs(all) do
        table.insert(items, output)
    end
    table.sort(items)
    return items
end

---Get a summary of recipe preference for an item
---@param output string The output item ID
---@return string summary Human-readable summary
function module.getSummary(output)
    local pref = module.get(output)
    local parts = {}
    
    local priorityCount = #(pref.priority or {})
    local disabledCount = 0
    for _ in pairs(pref.disabled or {}) do
        disabledCount = disabledCount + 1
    end
    
    if priorityCount > 0 then
        table.insert(parts, priorityCount .. " prioritized")
    end
    if disabledCount > 0 then
        table.insert(parts, disabledCount .. " disabled")
    end
    
    if #parts == 0 then
        return "default"
    end
    return table.concat(parts, ", ")
end

return module
