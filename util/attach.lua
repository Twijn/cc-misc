--- A turtle utility module for ComputerCraft that provides safe block interaction,
--- automatic tool management, and peripheral handling for turtles.
---
--- Features: Automatic tool equipping based on action type (dig, attack, place),
--- unsafe block protection to prevent accidentally digging storage blocks,
--- peripheral auto-placement and wrapping, modem protection (never unequips modems),
--- configurable default and always-equipped tools, and proxy wrappers for peripherals.
---
---@usage
---local attach = require("attach")
---
--- -- Set up default tools
---attach.setDefaultEquipped("minecraft:diamond_pickaxe", "minecraft:diamond_sword")
---attach.setAlwaysEquipped("computercraft:wireless_modem_advanced")
---
--- -- Safe digging (won't dig chests, other turtles, etc.)
---attach.dig()      -- Automatically equips pickaxe
---attach.digUp()    -- Also safe
---attach.digDown()  -- Also safe
---
--- -- Attack with automatic sword equipping
---attach.attack()
---
--- -- Find and wrap a peripheral
---local modem = attach.find("modem")
---
---@version 1.0.2
-- @module attach

local VERSION = "1.0.2"

---@class AttachModule
---@field _unsafeBlocks string[] List of block IDs that should not be dug
---@field _defaultEquipped {left: string|nil, right: string|nil} Default tools for left/right sides
---@field _alwaysEquipped string|nil Tool that should always be equipped
---@field VERSION string Module version
local module = {
    _unsafeBlocks = {
        -- Vanilla storage blocks
        "minecraft:chest",
        "minecraft:trapped_chest",
        "minecraft:barrel",
        "minecraft:shulker_box",
        "minecraft:ender_chest",

        -- Vanilla containers / utility blocks
        "minecraft:furnace",
        "minecraft:blast_furnace",
        "minecraft:smoker",
        "minecraft:hopper",
        "minecraft:dispenser",
        "minecraft:dropper",
        "minecraft:brewing_stand",

        -- Redstone / miscellaneous
        "minecraft:note_block",
        "minecraft:jukebox",
        "minecraft:enchanting_table",
        "minecraft:lectern",

        -- ComputerCraft computers / turtles
        "computercraft:turtle_normal",
        "computercraft:turtle_advanced",
        "computercraft:computer_normal",
        "computercraft:computer_advanced",
    },

    -- Configurable default tools
    _defaultEquipped = {left = nil, right = nil}, -- max 2
    _alwaysEquipped = nil, -- max 1
}

-- Map sides to turtle functions
local sides = {
    top = { name = "top", dig = turtle.digUp, attack = turtle.attackUp, inspect = turtle.inspectUp, place = turtle.placeUp },
    bottom = { name = "bottom", dig = turtle.digDown, attack = turtle.attackDown, inspect = turtle.inspectDown, place = turtle.placeDown },
    front = { name = "front", dig = turtle.dig, attack = turtle.attack, inspect = turtle.inspect, place = turtle.place },
    left = { name = "left" },
    right = { name = "right" },
    back = { name = "back" },
}

-- Tool priorities
local toolPriority = {
    dig = { "pickaxe", "axe", "shovel" },
    attack = { "sword" },
    place = { "any" }
}

-- Copy turtle API into module
for k, v in pairs(turtle) do
    module[k] = v
end

-- ======= Internal Helpers =======
local function getSideData(side)
    local result = sides[side]
    assert(result and result.name, "unknown side " .. side)
    return result
end

local function isUnsafe(side)
    local sideData = getSideData(side)
    if not sideData.inspect then return false end
    local success, data = sideData.inspect()
    if not success then return false end
    local blockName = data.name
    for _, unsafe in ipairs(module._unsafeBlocks) do
        if blockName == unsafe then return true end
    end
    return false
end

local function findToolSlot(action)
    local priorities = toolPriority[action]
    if not priorities then return nil end

    for slot = 1, 16 do
        local stack = turtle.getItemDetail(slot)
        if stack then
            for _, tool in ipairs(priorities) do
                if tool == "any" or stack.name:lower():find(tool) then
                    return slot
                end
            end
        end
    end
    return nil
end

-- ======= Equip Tools Logic =======

-- Check if an item is a modem (should not be unequipped due to open channels)
local function isModem(itemDetail)
    return itemDetail and itemDetail.name:lower():find("modem")
end

-- Check if an item is the "always equipped" tool
local function isAlwaysEquipped(itemDetail)
    return module._alwaysEquipped and itemDetail and itemDetail.name == module._alwaysEquipped
end

-- Check if an item is a configured default equipped tool
local function isDefaultEquipped(itemDetail, side)
    local configuredTool = module._defaultEquipped[side]
    return configuredTool and itemDetail and itemDetail.name == configuredTool
end

-- Check if a side is safe to replace (not a modem, not always equipped, not default equipped)
local function canReplaceSide(side)
    local equipped = side == "left" and turtle.getEquippedLeft() or turtle.getEquippedRight()
    if not equipped then return true end
    if isModem(equipped) then return false end
    if isAlwaysEquipped(equipped) then return false end
    if isDefaultEquipped(equipped, side) then return false end
    return true
end

-- Find a safe side to equip to, preferring empty slots
local function findSafeEquipSide()
    local left = turtle.getEquippedLeft()
    local right = turtle.getEquippedRight()

    -- Prefer empty sides first
    if not left then return "left" end
    if not right then return "right" end

    -- Try to find a replaceable side (right first, then left)
    if canReplaceSide("right") then return "right" end
    if canReplaceSide("left") then return "left" end

    return nil
end

-- Equip an item from the given slot to a safe side
local function equipToSafeSide(slot)
    local side = findSafeEquipSide()
    if not side then return nil end

    turtle.select(slot)
    if side == "left" then
        if turtle.equipLeft() then return "left" end
    else
        if turtle.equipRight() then return "right" end
    end
    return nil
end

local function equipBestTool(action)
    -- Always equipped priority: check if already equipped
    if module._alwaysEquipped then
        local leftEquipped = turtle.getEquippedLeft()
        local rightEquipped = turtle.getEquippedRight()
        if leftEquipped and leftEquipped.name == module._alwaysEquipped then
            return "left"
        elseif rightEquipped and rightEquipped.name == module._alwaysEquipped then
            return "right"
        else
            -- Try to equip the always-equipped tool
            for slot = 1, 16 do
                local stack = turtle.getItemDetail(slot)
                if stack and stack.name == module._alwaysEquipped then
                    local side = equipToSafeSide(slot)
                    if side then return side end
                end
            end
        end
    end

    -- Default equipped: check if already equipped, otherwise try to equip
    for side, toolName in pairs(module._defaultEquipped) do
        if toolName then
            local equipped = side == "left" and turtle.getEquippedLeft() or turtle.getEquippedRight()
            if equipped and equipped.name == toolName then
                return side
            end
            -- Try to equip it
            for slot = 1, 16 do
                local stack = turtle.getItemDetail(slot)
                if stack and stack.name == toolName then
                    turtle.select(slot)
                    if side == "left" then
                        turtle.equipLeft()
                    else
                        turtle.equipRight()
                    end
                    return side
                end
            end
        end
    end

    -- Fallback: find tool based on action
    local slot = findToolSlot(action)
    if slot then
        local side = equipToSafeSide(slot)
        if side then return side end
    end

    return nil
end

-- ======= Config Functions =======

---Set the default tools to be equipped on each side
---@param leftTool string|nil The tool to equip on the left side (e.g., "minecraft:diamond_pickaxe")
---@param rightTool string|nil The tool to equip on the right side (e.g., "minecraft:diamond_sword")
function module.setDefaultEquipped(leftTool, rightTool)
    module._defaultEquipped.left = leftTool
    module._defaultEquipped.right = rightTool
end

---Set a tool that should always be kept equipped (has highest priority)
---@param toolName string|nil The tool that should always be equipped
function module.setAlwaysEquipped(toolName)
    module._alwaysEquipped = toolName
end

-- ======= Turtle Overrides =======
local function wrapTurtleFunc(originalFunc, actionType, side)
    return function(...)
        equipBestTool(actionType)
        if actionType == "dig" and isUnsafe(side) then
            return false, "Unsafe block"
        end
        return originalFunc(...)
    end
end

module.dig = wrapTurtleFunc(turtle.dig, "dig", "front")
module.digUp = wrapTurtleFunc(turtle.digUp, "dig", "top")
module.digDown = wrapTurtleFunc(turtle.digDown, "dig", "bottom")

module.attack = wrapTurtleFunc(turtle.attack, "attack", "front")
module.attackUp = wrapTurtleFunc(turtle.attackUp, "attack", "top")
module.attackDown = wrapTurtleFunc(turtle.attackDown, "attack", "bottom")

-- ======= Peripheral Functions =======

-- Mapping from peripheral types to item name patterns
-- Used when equipping peripherals from inventory
local peripheralItemPatterns = {
    ["modem"] = {"modem"},
    ["plethora:scanner"] = {"plethora:module_scanner", "scanner"},
    ["plethora:sensor"] = {"plethora:module_sensor", "sensor"},
    ["plethora:introspection"] = {"plethora:module_introspection", "introspection"},
    ["plethora:kinetic"] = {"plethora:module_kinetic", "kinetic"},
    ["plethora:laser"] = {"plethora:module_laser", "laser"},
    ["workbench"] = {"crafty", "workbench", "crafting"},
}

local function placePeripheral(side, peripheralName)
    local sideData = getSideData(side)
    for slot = 1, 16 do
        local stack = turtle.getItemDetail(slot)
        if stack and stack.name:lower():find(peripheralName:lower()) then
            turtle.select(slot)
            if sideData.place then
                return sideData.place()
            end
        end
    end
    return false
end

-- Equip a peripheral as a tool (for modems, plethora modules, etc.)
local function equipPeripheralTool(peripheralType)
    peripheralType = peripheralType:lower()
    
    -- Get item patterns for this peripheral type
    local patterns = peripheralItemPatterns[peripheralType]
    if not patterns then
        -- Fallback: use the peripheral type itself as a pattern
        patterns = {peripheralType}
    end

    -- Check inventory for the peripheral
    for slot = 1, 16 do
        local stack = turtle.getItemDetail(slot)
        if stack then
            local itemName = stack.name:lower()
            for _, pattern in ipairs(patterns) do
                if itemName:find(pattern:lower()) then
                    -- Use shared safe equip logic
                    local side = equipToSafeSide(slot)
                    if side then return side end
                end
            end
        end
    end

    return nil
end

-- Re-attach a peripheral that was removed, handling both placed and equipped peripherals
local function reattachPeripheral(peripheralName, side)
    if side == "left" or side == "right" then
        -- Tool peripheral (like modem) - need to re-equip
        return equipPeripheralTool(peripheralName) == side
    else
        -- Placed peripheral - use placePeripheral
        return placePeripheral(side, peripheralName)
    end
end

local function wrapPeripheralInternal(peripheralName, side)
    if not peripheral.isPresent(side) then
        reattachPeripheral(peripheralName, side)
    end
    local p = peripheral.wrap(side)
    assert(p, "Could not wrap peripheral " .. peripheralName .. " on " .. side)

    local proxy = {}
    for funcName, func in pairs(p) do
        proxy[funcName] = function(...)
            if not peripheral.isPresent(side) then
                reattachPeripheral(peripheralName, side)
                p = peripheral.wrap(side)
                if not p then
                    error("Could not reattach peripheral " .. peripheralName .. " on " .. side)
                end
            end
            return p[funcName](...)
        end
    end
    return proxy
end

---Wrap a peripheral, automatically placing it if not present
---@param peripheralName string The name/type of peripheral to wrap
---@param side string The side to place/wrap the peripheral on ("top", "bottom", "front", "back", "left", "right")
---@return table # A proxy table with all peripheral methods that auto-replaces if removed
function module.wrap(peripheralName, side)
    return wrapPeripheralInternal(peripheralName, side)
end


-- Check if a peripheral type matches the requested type
-- Handles cases like "plethora:scanner" matching "scanner" or vice versa
local function peripheralTypeMatches(actualType, requestedType)
    if actualType == requestedType then
        return true
    end
    -- Check if one contains the other (case-insensitive)
    local actualLower = actualType:lower()
    local requestedLower = requestedType:lower()
    if actualLower:find(requestedLower, 1, true) or requestedLower:find(actualLower, 1, true) then
        return true
    end
    return false
end

---Find and wrap a peripheral by type, equipping it as a tool if necessary
---@param peripheralType string The type of peripheral to find (e.g., "modem", "workbench")
---@return table|nil # A proxy table with all peripheral methods, or nil if not found
---@return string|nil # Error message if peripheral was not found
function module.find(peripheralType)
    local debugInfo = {
        requestedType = peripheralType,
        attachedPeripherals = {},
        inventoryItems = {},
        equippedLeft = turtle.getEquippedLeft(),
        equippedRight = turtle.getEquippedRight(),
    }

    -- 1. First look for an already-attached peripheral
    for _, side in ipairs({"left","right","front","back","top","bottom"}) do
        if peripheral.isPresent(side) then
            local pType = peripheral.getType(side)
            debugInfo.attachedPeripherals[side] = pType
            if peripheralTypeMatches(pType, peripheralType) then
                return wrapPeripheralInternal(peripheralType, side)
            end
        end
    end

    -- 2. Collect inventory info for debugging
    for slot = 1, 16 do
        local stack = turtle.getItemDetail(slot)
        if stack then
            debugInfo.inventoryItems[slot] = stack.name
        end
    end

    -- 3. Try to equip it as a tool (wireless modem behavior)
    local equippedSide = equipPeripheralTool(peripheralType)
    if equippedSide then
        -- Newly equipped tool will expose a peripheral on that side
        if peripheral.isPresent(equippedSide) then
            local equippedType = peripheral.getType(equippedSide)
            debugInfo.equippedPeripheralType = equippedType
            debugInfo.equippedSide = equippedSide
            if peripheralTypeMatches(equippedType, peripheralType) then
                return wrapPeripheralInternal(peripheralType, equippedSide)
            else
                -- Equipped something but type doesn't match
                local errMsg = string.format(
                    "Peripheral type mismatch: requested '%s', equipped '%s' on %s",
                    peripheralType, equippedType, equippedSide
                )
                debugInfo.error = errMsg
                return nil, textutils.serialiseJSON(debugInfo)
            end
        else
            debugInfo.error = "Equipped item to " .. equippedSide .. " but no peripheral detected"
            return nil, textutils.serialiseJSON(debugInfo)
        end
    end

    -- 4. Nothing found - build detailed error message
    local patterns = peripheralItemPatterns[peripheralType:lower()]
    debugInfo.searchPatterns = patterns or {peripheralType:lower()}
    debugInfo.error = "No matching peripheral found in attached peripherals or inventory"
    
    return nil, textutils.serialiseJSON(debugInfo)
end


-- ======= Debug =======

---Print debug information about the module state, peripherals, and inventory
---Pauses between sections for user to read (press Enter to continue)
function module._debug()
    print("Attach module version:", VERSION)
    print("\nUnsafe blocks:")
    for _, b in ipairs(module._unsafeBlocks) do
        print("-", b)
    end
    read()
    print("\nConnected peripherals:")
    for _, side in ipairs({"front","back","top","bottom","left","right"}) do
        if peripheral.isPresent(side) then
            print("-", side, ":", peripheral.getType(side))
        end
    end
    read()
    print("\nTool availability:")
    for action, _ in pairs(toolPriority) do
        local slot = findToolSlot(action)
        if slot then
            print("-", action, "tool in slot", slot, turtle.getItemDetail(slot).name)
        else
            print("-", action, "tool not found")
        end
    end
    read()
    print("\nTurtle inventory:")
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            print("-", "Slot", slot, ":", item.count, item.name)
        end
    end
end

module.VERSION = VERSION
return module
