--- Inventory Management Library for Road Builder
--- Handles road block detection, ender storage, refilling, and debris disposal
---
---@version 1.0.0
-- @module inventory

local module = {}

-- Internal state
local roadBlockType = nil
local roadBlockSlots = {}
local debrisSlots = {}
local enderStorageSlot = nil
local fuelSlots = {}

---Scan inventory and categorize items
---@param fuelItems table List of fuel item names
---@return table summary Inventory summary
function module.scan(fuelItems)
    fuelItems = fuelItems or {
        "minecraft:coal",
        "minecraft:charcoal",
        "minecraft:coal_block",
    }
    
    roadBlockSlots = {}
    debrisSlots = {}
    fuelSlots = {}
    enderStorageSlot = nil
    
    local roadBlockCount = 0
    local debrisCount = 0
    local fuelCount = 0
    local emptySlots = 0
    
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            -- Check for ender storage
            if item.name:find("ender") and item.name:find("storage") then
                enderStorageSlot = slot
            -- Check for fuel
            elseif module.isFuelItem(item.name, fuelItems) then
                table.insert(fuelSlots, slot)
                fuelCount = fuelCount + item.count
            -- Check for road blocks (place-able blocks)
            elseif module.isPlaceableBlock(item.name) then
                if not roadBlockType then
                    roadBlockType = item.name
                end
                if item.name == roadBlockType then
                    table.insert(roadBlockSlots, slot)
                    roadBlockCount = roadBlockCount + item.count
                else
                    -- Different block type = debris
                    table.insert(debrisSlots, slot)
                    debrisCount = debrisCount + item.count
                end
            else
                -- Everything else is debris
                table.insert(debrisSlots, slot)
                debrisCount = debrisCount + item.count
            end
        else
            emptySlots = emptySlots + 1
        end
    end
    
    return {
        roadBlockType = roadBlockType,
        roadBlockCount = roadBlockCount,
        roadBlockSlots = roadBlockSlots,
        debrisCount = debrisCount,
        debrisSlots = debrisSlots,
        fuelCount = fuelCount,
        fuelSlots = fuelSlots,
        enderStorageSlot = enderStorageSlot,
        emptySlots = emptySlots,
    }
end

---Check if an item is a fuel item
---@param itemName string Item name to check
---@param fuelItems table List of fuel item names
---@return boolean isFuel True if item is fuel
function module.isFuelItem(itemName, fuelItems)
    for _, fuel in ipairs(fuelItems) do
        if itemName == fuel or itemName:find(fuel) then
            return true
        end
    end
    return false
end

---Check if an item is a placeable block (likely a building material)
---@param itemName string Item name to check
---@return boolean isPlaceable True if item can be placed
function module.isPlaceableBlock(itemName)
    -- Common non-block items to exclude
    local nonBlocks = {
        "sword", "pickaxe", "axe", "shovel", "hoe",
        "bow", "arrow", "potion", "book", "bucket",
        "dye", "bone_meal", "coal", "charcoal", "diamond",
        "emerald", "iron_ingot", "gold_ingot", "netherite_ingot",
        "stick", "string", "feather", "leather", "paper",
        "egg", "spawn_egg", "music_disc", "disc",
    }
    
    for _, pattern in ipairs(nonBlocks) do
        if itemName:find(pattern) then
            return false
        end
    end
    
    -- Most other items from minecraft that end in common block suffixes are blocks
    local blockPatterns = {
        "stone", "brick", "block", "ore", "wood", "planks",
        "log", "slab", "stairs", "wall", "fence", "glass",
        "concrete", "terracotta", "wool", "carpet", "dirt",
        "grass", "sand", "gravel", "clay", "cobble",
    }
    
    for _, pattern in ipairs(blockPatterns) do
        if itemName:find(pattern) then
            return true
        end
    end
    
    -- Default to true for unknown items (assume they might be blocks)
    return true
end

---Get the current road block type
---@return string|nil blockType The road block type or nil
function module.getRoadBlockType()
    return roadBlockType
end

---Set the road block type manually
---@param blockType string The block type to use for roads
function module.setRoadBlockType(blockType)
    roadBlockType = blockType
end

---Get total count of road blocks
---@return number count Total road blocks in inventory
function module.getRoadBlockCount()
    local count = 0
    for _, slot in ipairs(roadBlockSlots) do
        count = count + turtle.getItemCount(slot)
    end
    return count
end

---Select a slot with road blocks
---@return boolean success True if a road block slot was selected
function module.selectRoadBlock()
    for _, slot in ipairs(roadBlockSlots) do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            return true
        end
    end
    return false
end

---Get the ender storage slot
---@return number|nil slot Ender storage slot or nil
function module.getEnderStorageSlot()
    return enderStorageSlot
end

---Place ender storage above turtle
---@return boolean success True if ender storage was placed
function module.placeEnderStorageUp()
    if not enderStorageSlot then
        return false
    end
    
    -- Dig if something is above
    if turtle.detectUp() then
        turtle.digUp()
    end
    
    local prevSlot = turtle.getSelectedSlot()
    turtle.select(enderStorageSlot)
    local success = turtle.placeUp()
    turtle.select(prevSlot)
    
    return success
end

---Pick up ender storage from above
---@return boolean success True if ender storage was picked up
function module.pickUpEnderStorageUp()
    local prevSlot = turtle.getSelectedSlot()
    if enderStorageSlot then
        turtle.select(enderStorageSlot)
    end
    local success = turtle.digUp()
    turtle.select(prevSlot)
    return success
end

---Deposit debris into ender storage above
---@return number deposited Number of items deposited
function module.depositDebrisUp()
    local deposited = 0
    local prevSlot = turtle.getSelectedSlot()
    
    for _, slot in ipairs(debrisSlots) do
        turtle.select(slot)
        if turtle.dropUp() then
            deposited = deposited + turtle.getItemCount(slot)
        end
    end
    
    turtle.select(prevSlot)
    return deposited
end

---Refill road blocks from ender storage above
---@param targetCount number|nil Target number of blocks to have
---@return number refilled Number of items refilled
function module.refillRoadBlocksUp(targetCount)
    targetCount = targetCount or (64 * 8) -- Default to 8 stacks
    
    local currentCount = module.getRoadBlockCount()
    local needed = targetCount - currentCount
    
    if needed <= 0 then
        return 0
    end
    
    local refilled = 0
    local prevSlot = turtle.getSelectedSlot()
    
    -- Try to fill empty slots first, then road block slots
    for slot = 1, 16 do
        if slot ~= enderStorageSlot then
            local item = turtle.getItemDetail(slot)
            -- Only fill empty slots or slots with matching road blocks
            if not item or item.name == roadBlockType then
                turtle.select(slot)
                local before = turtle.getItemCount(slot)
                if turtle.suckUp(math.min(64, needed)) then
                    local after = turtle.getItemCount(slot)
                    local got = after - before
                    refilled = refilled + got
                    needed = needed - got
                    
                    -- Update road block slots if this was empty
                    if not item then
                        table.insert(roadBlockSlots, slot)
                    end
                end
                
                if needed <= 0 then
                    break
                end
            end
        end
    end
    
    turtle.select(prevSlot)
    return refilled
end

---Refuel from inventory
---@param targetLevel number Target fuel level
---@param fuelItems table List of fuel item names
---@return number consumed Number of fuel items consumed
function module.refuel(targetLevel, fuelItems)
    fuelItems = fuelItems or {"minecraft:coal", "minecraft:charcoal"}
    local consumed = 0
    local prevSlot = turtle.getSelectedSlot()
    
    for _, slot in ipairs(fuelSlots) do
        if turtle.getFuelLevel() >= targetLevel then
            break
        end
        
        turtle.select(slot)
        local before = turtle.getItemCount(slot)
        turtle.refuel()
        local after = turtle.getItemCount(slot)
        consumed = consumed + (before - after)
    end
    
    turtle.select(prevSlot)
    return consumed
end

---Get inventory summary for status reporting
---@return table summary Inventory status summary
function module.getStatus()
    return {
        roadBlockType = roadBlockType,
        roadBlockCount = module.getRoadBlockCount(),
        roadBlockSlots = #roadBlockSlots,
        debrisSlots = #debrisSlots,
        fuelSlots = #fuelSlots,
        hasEnderStorage = enderStorageSlot ~= nil,
        fuelLevel = turtle.getFuelLevel(),
    }
end

---Compact inventory by consolidating stacks
function module.compact()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            for targetSlot = 1, slot - 1 do
                if turtle.getItemCount(targetSlot) > 0 then
                    turtle.transferTo(targetSlot)
                end
            end
        end
    end
end

module.VERSION = "1.0.0"
return module
