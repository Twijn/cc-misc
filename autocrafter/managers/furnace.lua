--- AutoCrafter Furnace Manager
--- Manages furnace peripherals for automated smelting.
---
---@version 1.0.0

local logger = require("lib.log")
local inventory = require("lib.inventory")
local furnaceConfig = require("config.furnaces")

local manager = {}

-- Cache of wrapped furnace peripherals
local furnacePeripherals = {}
local lastSmeltCheck = 0
local smeltCheckInterval = 5  -- Seconds between smelt checks

-- Fuel burn times (in ticks, 1 item smelted = 200 ticks)
-- Values represent number of items that can be smelted per fuel item
local fuelBurnTimes = {
    ["minecraft:lava_bucket"] = 100,
    ["minecraft:coal_block"] = 80,
    ["minecraft:dried_kelp_block"] = 20,
    ["minecraft:blaze_rod"] = 12,
    ["minecraft:coal"] = 8,
    ["minecraft:charcoal"] = 8,
    ["minecraft:dried_kelp"] = 0.5,
    ["minecraft:bamboo_block"] = 2,
    ["minecraft:bamboo"] = 0.25,
    ["minecraft:oak_log"] = 1.5,
    ["minecraft:spruce_log"] = 1.5,
    ["minecraft:birch_log"] = 1.5,
    ["minecraft:jungle_log"] = 1.5,
    ["minecraft:acacia_log"] = 1.5,
    ["minecraft:dark_oak_log"] = 1.5,
    ["minecraft:mangrove_log"] = 1.5,
    ["minecraft:cherry_log"] = 1.5,
    ["minecraft:oak_planks"] = 1.5,
    ["minecraft:spruce_planks"] = 1.5,
    ["minecraft:birch_planks"] = 1.5,
    ["minecraft:jungle_planks"] = 1.5,
    ["minecraft:acacia_planks"] = 1.5,
    ["minecraft:dark_oak_planks"] = 1.5,
    ["minecraft:stick"] = 0.5,
}

-- Smelting recipes (input -> output mappings)
-- This is a simplified set - can be extended or loaded from ROM
local smeltingRecipes = {
    -- Ores to ingots (furnace or blast furnace)
    ["minecraft:iron_ore"] = { output = "minecraft:iron_ingot", type = "ore", fuelTime = 10 },
    ["minecraft:deepslate_iron_ore"] = { output = "minecraft:iron_ingot", type = "ore", fuelTime = 10 },
    ["minecraft:raw_iron"] = { output = "minecraft:iron_ingot", type = "ore", fuelTime = 10 },
    ["minecraft:gold_ore"] = { output = "minecraft:gold_ingot", type = "ore", fuelTime = 10 },
    ["minecraft:deepslate_gold_ore"] = { output = "minecraft:gold_ingot", type = "ore", fuelTime = 10 },
    ["minecraft:raw_gold"] = { output = "minecraft:gold_ingot", type = "ore", fuelTime = 10 },
    ["minecraft:copper_ore"] = { output = "minecraft:copper_ingot", type = "ore", fuelTime = 10 },
    ["minecraft:deepslate_copper_ore"] = { output = "minecraft:copper_ingot", type = "ore", fuelTime = 10 },
    ["minecraft:raw_copper"] = { output = "minecraft:copper_ingot", type = "ore", fuelTime = 10 },
    ["minecraft:ancient_debris"] = { output = "minecraft:netherite_scrap", type = "ore", fuelTime = 10 },
    
    -- Sand to glass
    ["minecraft:sand"] = { output = "minecraft:glass", type = "material", fuelTime = 10 },
    ["minecraft:red_sand"] = { output = "minecraft:glass", type = "material", fuelTime = 10 },
    
    -- Stone/clay products
    ["minecraft:cobblestone"] = { output = "minecraft:stone", type = "material", fuelTime = 10 },
    ["minecraft:stone"] = { output = "minecraft:smooth_stone", type = "material", fuelTime = 10 },
    ["minecraft:clay_ball"] = { output = "minecraft:brick", type = "material", fuelTime = 10 },
    ["minecraft:clay"] = { output = "minecraft:terracotta", type = "material", fuelTime = 10 },
    ["minecraft:netherrack"] = { output = "minecraft:nether_brick", type = "material", fuelTime = 10 },
    ["minecraft:sandstone"] = { output = "minecraft:smooth_sandstone", type = "material", fuelTime = 10 },
    ["minecraft:red_sandstone"] = { output = "minecraft:smooth_red_sandstone", type = "material", fuelTime = 10 },
    ["minecraft:quartz_block"] = { output = "minecraft:smooth_quartz", type = "material", fuelTime = 10 },
    ["minecraft:basalt"] = { output = "minecraft:smooth_basite", type = "material", fuelTime = 10 },
    ["minecraft:cobbled_deepslate"] = { output = "minecraft:deepslate", type = "material", fuelTime = 10 },
    
    -- Food (furnace or smoker)
    ["minecraft:beef"] = { output = "minecraft:cooked_beef", type = "food", fuelTime = 10 },
    ["minecraft:porkchop"] = { output = "minecraft:cooked_porkchop", type = "food", fuelTime = 10 },
    ["minecraft:chicken"] = { output = "minecraft:cooked_chicken", type = "food", fuelTime = 10 },
    ["minecraft:mutton"] = { output = "minecraft:cooked_mutton", type = "food", fuelTime = 10 },
    ["minecraft:rabbit"] = { output = "minecraft:cooked_rabbit", type = "food", fuelTime = 10 },
    ["minecraft:cod"] = { output = "minecraft:cooked_cod", type = "food", fuelTime = 10 },
    ["minecraft:salmon"] = { output = "minecraft:cooked_salmon", type = "food", fuelTime = 10 },
    ["minecraft:potato"] = { output = "minecraft:baked_potato", type = "food", fuelTime = 10 },
    ["minecraft:kelp"] = { output = "minecraft:dried_kelp", type = "food", fuelTime = 10 },
    
    -- Wood to charcoal
    ["minecraft:oak_log"] = { output = "minecraft:charcoal", type = "material", fuelTime = 10 },
    ["minecraft:spruce_log"] = { output = "minecraft:charcoal", type = "material", fuelTime = 10 },
    ["minecraft:birch_log"] = { output = "minecraft:charcoal", type = "material", fuelTime = 10 },
    ["minecraft:jungle_log"] = { output = "minecraft:charcoal", type = "material", fuelTime = 10 },
    ["minecraft:acacia_log"] = { output = "minecraft:charcoal", type = "material", fuelTime = 10 },
    ["minecraft:dark_oak_log"] = { output = "minecraft:charcoal", type = "material", fuelTime = 10 },
    ["minecraft:mangrove_log"] = { output = "minecraft:charcoal", type = "material", fuelTime = 10 },
    ["minecraft:cherry_log"] = { output = "minecraft:charcoal", type = "material", fuelTime = 10 },
    
    -- Misc
    ["minecraft:cactus"] = { output = "minecraft:green_dye", type = "material", fuelTime = 10 },
    ["minecraft:sea_pickle"] = { output = "minecraft:lime_dye", type = "material", fuelTime = 10 },
    ["minecraft:wet_sponge"] = { output = "minecraft:sponge", type = "material", fuelTime = 10 },
    ["minecraft:chorus_fruit"] = { output = "minecraft:popped_chorus_fruit", type = "material", fuelTime = 10 },
}

---Initialize the furnace manager
function manager.init()
    furnacePeripherals = {}
    logger.info("Furnace manager initialized")
end

---Set the smelt check interval
---@param seconds number Interval in seconds
function manager.setCheckInterval(seconds)
    smeltCheckInterval = seconds
end

---Get a wrapped furnace peripheral (cached)
---@param name string The peripheral name
---@return table|nil peripheral The wrapped peripheral or nil
local function getFurnacePeripheral(name)
    if furnacePeripherals[name] then
        return furnacePeripherals[name]
    end
    
    local p = peripheral.wrap(name)
    if p then
        furnacePeripherals[name] = p
    end
    
    return p
end

---Check if a smelt check is needed based on interval
---@return boolean needsCheck Whether a check should be performed
function manager.needsCheck()
    return (os.clock() - lastSmeltCheck) >= smeltCheckInterval
end

---Get smelting recipe for an input item
---@param input string The input item ID
---@return table|nil recipe The smelting recipe or nil
function manager.getSmeltRecipe(input)
    return smeltingRecipes[input]
end

---Get all smelting recipes
---@return table recipes All smelting recipes
function manager.getAllRecipes()
    return smeltingRecipes
end

---Get smelting recipe by output
---@param output string The output item ID
---@return string|nil input The input item ID or nil
function manager.getSmeltInput(output)
    for input, recipe in pairs(smeltingRecipes) do
        if recipe.output == output then
            return input
        end
    end
    return nil
end

---Search smelting recipes
---@param query string Search query (partial match)
---@return table results Array of {input, output, type}
function manager.searchRecipes(query)
    local results = {}
    query = query:lower()
    
    for input, recipe in pairs(smeltingRecipes) do
        if input:lower():find(query, 1, true) or recipe.output:lower():find(query, 1, true) then
            table.insert(results, {
                input = input,
                output = recipe.output,
                type = recipe.type,
            })
        end
    end
    
    table.sort(results, function(a, b)
        return a.output < b.output
    end)
    
    return results
end

---Add a custom smelting recipe
---@param input string The input item ID
---@param output string The output item ID
---@param recipeType? string The recipe type (ore, food, material)
function manager.addRecipe(input, output, recipeType)
    smeltingRecipes[input] = {
        output = output,
        type = recipeType or "material",
        fuelTime = 10,
    }
    logger.info(string.format("Added smelting recipe: %s -> %s", input, output))
end

---Get furnace slot contents
---@param furnace table The wrapped furnace peripheral
---@return table contents {input, fuel, output} slot contents
local function getFurnaceContents(furnace)
    local list = furnace.list and furnace.list() or {}
    return {
        input = list[1],   -- Slot 1: input
        fuel = list[2],    -- Slot 2: fuel
        output = list[3],  -- Slot 3: output
    }
end

---Check if a furnace is available for smelting
---@param furnace table The wrapped furnace peripheral
---@return boolean available Whether the furnace can accept input
---@return string|nil reason Why the furnace is not available
local function isFurnaceAvailable(furnace)
    local contents = getFurnaceContents(furnace)
    
    -- Check if input slot is empty or has room
    if contents.input and contents.input.count >= 64 then
        return false, "Input slot full"
    end
    
    -- Check if output slot is not full
    if contents.output and contents.output.count >= 64 then
        return false, "Output slot full"
    end
    
    return true
end

---Check if a furnace needs fuel
---@param furnace table The wrapped furnace peripheral
---@return boolean needsFuel Whether the furnace needs fuel
---@return number|nil fuelCount Current fuel count (nil if no fuel)
local function furnaceNeedsFuel(furnace)
    local contents = getFurnaceContents(furnace)
    
    -- Check if fuel slot is empty or low
    if not contents.fuel then
        return true, 0
    end
    
    -- Consider needing fuel if below 32 items (except lava bucket which is 1)
    local threshold = 32
    if contents.fuel.name == "minecraft:lava_bucket" then
        return false, contents.fuel.count
    end
    
    if contents.fuel.count < threshold then
        return true, contents.fuel.count
    end
    
    return false, contents.fuel.count
end

---Get fuel burn time for an item
---@param item string The fuel item ID
---@return number burnTime Number of items this fuel can smelt
function manager.getFuelBurnTime(item)
    return fuelBurnTimes[item] or 0
end

---Check if an item is valid fuel
---@param item string The item ID
---@return boolean isFuel Whether the item is valid fuel
function manager.isFuel(item)
    return fuelBurnTimes[item] ~= nil
end

---Get all fuel burn times
---@return table fuelBurnTimes Map of item -> burn time
function manager.getAllFuelBurnTimes()
    return fuelBurnTimes
end

---Get fuel stock levels for preferred fuels
---@param stockLevels table Current stock levels
---@return table fuelStock Array of {item, stock, burnTime, priority}
function manager.getFuelStock(stockLevels)
    local preferredFuels = furnaceConfig.getPreferredFuels()
    local fuelStock = {}
    
    for priority, fuelItem in ipairs(preferredFuels) do
        -- Skip lava bucket if not enabled
        if fuelItem == "minecraft:lava_bucket" and not furnaceConfig.isLavaBucketEnabled() then
            goto continue
        end
        
        local stock = stockLevels[fuelItem] or 0
        local burnTime = fuelBurnTimes[fuelItem] or 0
        
        table.insert(fuelStock, {
            item = fuelItem,
            stock = stock,
            burnTime = burnTime,
            priority = priority,
            totalSmeltCapacity = stock * burnTime,
        })
        
        ::continue::
    end
    
    return fuelStock
end

---Find the best available fuel from storage
---@param stockLevels table Current stock levels
---@return string|nil fuelItem The best fuel item ID, or nil if none available
---@return number available Amount available
local function findBestFuel(stockLevels)
    local preferredFuels = furnaceConfig.getPreferredFuels()
    
    for _, fuelItem in ipairs(preferredFuels) do
        -- Skip lava bucket if not enabled
        if fuelItem == "minecraft:lava_bucket" and not furnaceConfig.isLavaBucketEnabled() then
            goto continue
        end
        
        local available = stockLevels[fuelItem] or 0
        if available > 0 then
            return fuelItem, available
        end
        
        ::continue::
    end
    
    return nil, 0
end

---Push fuel to a furnace
---@param furnaceName string The furnace peripheral name
---@param stockLevels table Current stock levels
---@return number pushed Amount of fuel pushed
---@return string|nil fuelUsed The fuel item that was pushed
local function pushFuelToFurnace(furnaceName, stockLevels)
    local furnace = getFurnacePeripheral(furnaceName)
    if not furnace then return 0, nil end
    
    local needsFuel, currentFuelCount = furnaceNeedsFuel(furnace)
    if not needsFuel then return 0, nil end
    
    -- Check what fuel is already in the furnace
    local contents = getFurnaceContents(furnace)
    local existingFuelType = contents.fuel and contents.fuel.name or nil
    
    -- Determine which fuel to use
    local fuelItem, available
    local preferredFuels = furnaceConfig.getPreferredFuels()
    
    if existingFuelType then
        -- Furnace already has fuel - check if it's in our preferred list
        local existingIsPreferred = false
        for _, pf in ipairs(preferredFuels) do
            if pf == existingFuelType then
                existingIsPreferred = true
                break
            end
        end
        
        if existingIsPreferred then
            -- Only push more of the same type
            available = stockLevels[existingFuelType] or 0
            if available > 0 then
                fuelItem = existingFuelType
            else
                -- No more of this fuel available, don't mix fuels
                return 0, nil
            end
        else
            -- Existing fuel is not in preferred list - don't add anything
            -- (wait for it to burn out)
            return 0, nil
        end
    else
        -- Furnace is empty - find best available fuel from preferred list
        fuelItem, available = findBestFuel(stockLevels)
        if not fuelItem then return 0, nil end
    end
    
    -- Handle lava bucket specially - check input chest first
    if fuelItem == "minecraft:lava_bucket" then
        local lavaInputChest = furnaceConfig.getLavaBucketInputChest()
        if lavaInputChest then
            local lavaChest = peripheral.wrap(lavaInputChest)
            if lavaChest and lavaChest.pushItems then
                -- Find lava bucket in the chest
                local items = lavaChest.list and lavaChest.list() or {}
                for slot, item in pairs(items) do
                    if item.name == "minecraft:lava_bucket" then
                        -- Push to fuel slot (slot 2)
                        local transferred = lavaChest.pushItems(furnaceName, slot, 1, 2) or 0
                        if transferred > 0 then
                            logger.debug(string.format("Pushed lava bucket from %s to %s", lavaInputChest, furnaceName))
                            return transferred, fuelItem
                        end
                    end
                end
            end
        end
    end
    
    -- Normal fuel - push from storage
    local toPush = math.min(available, 64 - (currentFuelCount or 0))
    if toPush <= 0 then return 0, nil end
    
    -- Find fuel in storage only (not in export inventories)
    local locations = inventory.findItem(fuelItem, true)
    if #locations == 0 then return 0, nil end
    
    -- Sort by count (largest first)
    table.sort(locations, function(a, b) return a.count > b.count end)
    
    local pushed = 0
    
    for _, loc in ipairs(locations) do
        if pushed >= toPush then break end
        
        local amount = math.min(toPush - pushed, loc.count)
        -- Push to slot 2 (fuel slot) - use inventory.pushItems for proper cache handling
        local transferred = inventory.pushItems(loc.inventory, loc.slot, furnaceName, amount, 2)
        pushed = pushed + transferred
    end
    
    if pushed > 0 then
        logger.debug(string.format("Pushed %d %s fuel to %s", pushed, fuelItem, furnaceName))
    end
    
    return pushed, fuelItem
end

---Pull empty buckets from furnace fuel slot (after lava bucket is used)
---@param furnaceName string The furnace peripheral name
---@return number pulled Amount of buckets pulled
local function pullEmptyBucketsFromFurnace(furnaceName)
    if not furnaceConfig.isLavaBucketEnabled() then return 0 end
    
    local outputChest = furnaceConfig.getLavaBucketOutputChest()
    if not outputChest then return 0 end
    
    local furnace = getFurnacePeripheral(furnaceName)
    if not furnace then return 0 end
    
    local contents = getFurnaceContents(furnace)
    if not contents.fuel or contents.fuel.name ~= "minecraft:bucket" then
        return 0
    end
    
    local destChest = peripheral.wrap(outputChest)
    if not destChest or not destChest.pullItems then return 0 end
    
    -- Pull from slot 2 (fuel slot)
    local pulled = destChest.pullItems(furnaceName, 2) or 0
    
    if pulled > 0 then
        logger.debug(string.format("Pulled %d empty buckets from %s to %s", pulled, furnaceName, outputChest))
    end
    
    return pulled
end

---Get which furnace types can smelt an item
---@param recipeType string The recipe type (ore, food, material)
---@return table types Array of furnace types that can smelt this
local function getFurnaceTypesForRecipe(recipeType)
    if recipeType == "ore" then
        -- Ores can be smelted in furnace or blast furnace (faster)
        return {"blast_furnace", "furnace"}
    elseif recipeType == "food" then
        -- Food can be smelted in furnace or smoker (faster)
        return {"smoker", "furnace"}
    else
        -- Everything else: furnace only
        return {"furnace"}
    end
end

---Find available furnaces for a recipe
---@param recipeType string The recipe type
---@return table furnaces Array of available furnace peripherals with names
function manager.findAvailableFurnaces(recipeType)
    local furnaceTypes = getFurnaceTypesForRecipe(recipeType)
    local available = {}
    
    for _, fType in ipairs(furnaceTypes) do
        local enabledFurnaces = furnaceConfig.getEnabled(fType)
        for _, furnaceData in ipairs(enabledFurnaces) do
            local p = getFurnacePeripheral(furnaceData.name)
            if p then
                local isAvailable, reason = isFurnaceAvailable(p)
                if isAvailable then
                    table.insert(available, {
                        peripheral = p,
                        name = furnaceData.name,
                        type = furnaceData.type,
                    })
                end
            end
        end
    end
    
    return available
end

---Push input items to a furnace
---@param item string The input item ID
---@param count number Amount to push
---@param furnaceName string The furnace peripheral name
---@return number pushed Amount actually pushed
local function pushToFurnace(item, count, furnaceName)
    -- Find item in storage only (not in export inventories)
    local locations = inventory.findItem(item, true)
    if #locations == 0 then return 0 end
    
    -- Sort by count (largest first) for efficiency
    table.sort(locations, function(a, b) return a.count > b.count end)
    
    local pushed = 0
    
    for _, loc in ipairs(locations) do
        if pushed >= count then break end
        
        local toPush = math.min(count - pushed, loc.count)
        -- Push to slot 1 (input slot) - use inventory.pushItems for proper cache handling
        local transferred = inventory.pushItems(loc.inventory, loc.slot, furnaceName, toPush, 1)
        pushed = pushed + transferred
    end
    
    return pushed
end

---Pull output items from a furnace to storage
---@param furnaceName string The furnace peripheral name
---@return number pulled Amount pulled from output slot
local function pullFromFurnace(furnaceName)
    local furnace = getFurnacePeripheral(furnaceName)
    if not furnace then return 0 end
    
    local contents = getFurnaceContents(furnace)
    if not contents.output or contents.output.count == 0 then
        return 0
    end
    
    local pulled = 0
    local storageInvs = inventory.getStorageInventories()
    
    for _, destName in ipairs(storageInvs) do
        local dest = inventory.getPeripheral(destName)
        if dest and dest.pullItems then
            -- Pull from slot 3 (output slot) - use inventory.pullItems for proper cache handling
            local transferred = inventory.pullItems(destName, furnaceName, 3)
            pulled = pulled + transferred
            
            if transferred > 0 then
                -- Check if we got everything
                local newContents = getFurnaceContents(furnace)
                if not newContents.output or newContents.output.count == 0 then
                    break
                end
            end
        end
    end
    
    return pulled
end

---Process smelting for all configured furnaces
---@param stockLevels table Current stock levels
---@return table stats {itemsPushed, itemsPulled, furnacesUsed, fuelPushed}
function manager.processSmelt(stockLevels)
    lastSmeltCheck = os.clock()
    
    local stats = {
        itemsPushed = 0,
        itemsPulled = 0,
        furnacesUsed = 0,
        fuelPushed = 0,
        emptyBucketsPulled = 0,
    }
    
    -- Use batch mode to defer cache rebuilds until the end
    inventory.beginBatch()
    
    -- First, pull completed items and empty buckets from all furnaces
    for _, furnaceData in pairs(furnaceConfig.getAll()) do
        if furnaceData.enabled then
            local pulled = pullFromFurnace(furnaceData.name)
            stats.itemsPulled = stats.itemsPulled + pulled
            
            -- Pull empty buckets if lava bucket fuel is enabled
            local buckets = pullEmptyBucketsFromFurnace(furnaceData.name)
            stats.emptyBucketsPulled = stats.emptyBucketsPulled + buckets
        end
    end
    
    -- Refuel furnaces that need fuel
    for _, furnaceData in pairs(furnaceConfig.getAll()) do
        if furnaceData.enabled then
            local fuelPushed, fuelType = pushFuelToFurnace(furnaceData.name, stockLevels)
            if fuelPushed > 0 then
                stats.fuelPushed = stats.fuelPushed + fuelPushed
                -- Update stock levels
                if fuelType and fuelType ~= "minecraft:lava_bucket" then
                    stockLevels[fuelType] = (stockLevels[fuelType] or 0) - fuelPushed
                end
            end
        end
    end
    
    -- Get items that need smelting
    local needed = furnaceConfig.getNeededSmelt(stockLevels)
    
    for _, target in ipairs(needed) do
        -- Find the input item for this output
        local inputItem = manager.getSmeltInput(target.item)
        if not inputItem then
            logger.debug("No smelting recipe found for output: " .. target.item)
            goto continue
        end
        
        local recipe = smeltingRecipes[inputItem]
        if not recipe then
            goto continue
        end
        
        -- Check if we have input materials
        local inputAvailable = stockLevels[inputItem] or 0
        if inputAvailable == 0 then
            goto continue
        end
        
        -- Find available furnaces
        local furnaces = manager.findAvailableFurnaces(recipe.type)
        if #furnaces == 0 then
            goto continue
        end
        
        -- Calculate how much to smelt
        local toSmelt = math.min(target.needed, inputAvailable)
        
        -- Distribute across available furnaces
        local smelted = 0
        for _, furnaceInfo in ipairs(furnaces) do
            if smelted >= toSmelt then break end
            
            local remaining = toSmelt - smelted
            local perFurnace = math.min(remaining, 64)  -- Max 64 per furnace at a time
            
            local pushed = pushToFurnace(inputItem, perFurnace, furnaceInfo.name)
            if pushed > 0 then
                smelted = smelted + pushed
                stats.itemsPushed = stats.itemsPushed + pushed
                stats.furnacesUsed = stats.furnacesUsed + 1
                
                -- Update stock levels for next iteration
                stockLevels[inputItem] = (stockLevels[inputItem] or 0) - pushed
                
                logger.debug(string.format("Pushed %d %s to %s", pushed, inputItem, furnaceInfo.name))
            end
        end
        
        ::continue::
    end
    
    -- Process dried kelp mode if enabled (before ending batch)
    stats.driedKelpProcessed = manager.processDriedKelpMode(stockLevels)
    
    -- End batch mode and rebuild cache once at the very end
    inventory.endBatch()
    
    return stats
end

---Process dried kelp mode - smelt kelp and queue crafting of dried kelp blocks
---@param stockLevels table Current stock levels
---@return table stats {kelpSmelted, blocksQueued}
function manager.processDriedKelpMode(stockLevels)
    local stats = {
        kelpSmelted = 0,
        blocksQueued = 0,
    }
    
    if not furnaceConfig.isDriedKelpModeEnabled() then
        return stats
    end
    
    local target = furnaceConfig.getDriedKelpTarget()
    if target <= 0 then
        return stats
    end
    
    local currentBlocks = stockLevels["minecraft:dried_kelp_block"] or 0
    local currentDriedKelp = stockLevels["minecraft:dried_kelp"] or 0
    local currentKelp = stockLevels["minecraft:kelp"] or 0
    
    -- Calculate how many blocks we need
    local blocksNeeded = target - currentBlocks
    if blocksNeeded <= 0 then
        return stats
    end
    
    -- Each dried kelp block requires 9 dried kelp
    local driedKelpNeeded = blocksNeeded * 9
    local driedKelpToSmelt = driedKelpNeeded - currentDriedKelp
    
    -- If we need to smelt more kelp, add a temporary smelt target
    if driedKelpToSmelt > 0 and currentKelp > 0 then
        local toSmelt = math.min(driedKelpToSmelt, currentKelp)
        
        -- Find available furnaces (kelp is food type, can use smoker)
        local furnaces = manager.findAvailableFurnaces("food")
        
        for _, furnaceInfo in ipairs(furnaces) do
            if stats.kelpSmelted >= toSmelt then break end
            
            local remaining = toSmelt - stats.kelpSmelted
            local perFurnace = math.min(remaining, 64)
            
            local pushed = pushToFurnace("minecraft:kelp", perFurnace, furnaceInfo.name)
            if pushed > 0 then
                stats.kelpSmelted = stats.kelpSmelted + pushed
                stockLevels["minecraft:kelp"] = (stockLevels["minecraft:kelp"] or 0) - pushed
                logger.debug(string.format("Dried kelp mode: pushed %d kelp to %s", pushed, furnaceInfo.name))
            end
        end
    end
    
    -- Check if we have enough dried kelp to craft blocks
    -- Refresh dried kelp count from cache (may have been updated by furnace pulls)
    -- Return the count so the caller can queue the crafting job
    local freshDriedKelp = inventory.getStock("minecraft:dried_kelp")
    if freshDriedKelp >= 9 then
        local blocksToCraft = math.floor(freshDriedKelp / 9)
        blocksToCraft = math.min(blocksToCraft, blocksNeeded)
        if blocksToCraft > 0 then
            stats.blocksToQueue = blocksToCraft
            logger.debug(string.format("Dried kelp mode: need to craft %d dried kelp blocks (have %d dried kelp)", blocksToCraft, freshDriedKelp))
        end
    end
    
    return stats
end

---Get dried kelp mode status
---@param stockLevels table Current stock levels
---@return table status Status of dried kelp mode
function manager.getDriedKelpStatus(stockLevels)
    local config = furnaceConfig.getDriedKelpConfig()
    local currentBlocks = stockLevels["minecraft:dried_kelp_block"] or 0
    local currentDriedKelp = stockLevels["minecraft:dried_kelp"] or 0
    local currentKelp = stockLevels["minecraft:kelp"] or 0
    
    return {
        enabled = config.enabled,
        target = config.target,
        currentBlocks = currentBlocks,
        currentDriedKelp = currentDriedKelp,
        currentKelp = currentKelp,
        blocksNeeded = math.max(0, config.target - currentBlocks),
        canCraftBlocks = math.floor(currentDriedKelp / 9),
    }
end

---Get status of all furnaces
---@return table status Array of furnace status info
function manager.getStatus()
    local status = {}
    
    for name, furnaceData in pairs(furnaceConfig.getAll()) do
        local p = getFurnacePeripheral(name)
        local info = {
            name = name,
            type = furnaceData.type,
            enabled = furnaceData.enabled,
            connected = p ~= nil,
        }
        
        if p then
            local contents = getFurnaceContents(p)
            info.input = contents.input
            info.fuel = contents.fuel
            info.output = contents.output
            info.available = isFurnaceAvailable(p)
            info.needsFuel, info.fuelCount = furnaceNeedsFuel(p)
        end
        
        table.insert(status, info)
    end
    
    table.sort(status, function(a, b)
        return a.name < b.name
    end)
    
    return status
end

---Get fuel configuration and stock summary
---@param stockLevels table Current stock levels
---@return table summary Fuel configuration and stock info
function manager.getFuelSummary(stockLevels)
    local config = furnaceConfig.getFuelConfig()
    local fuelStock = manager.getFuelStock(stockLevels)
    
    local totalCapacity = 0
    for _, fuel in ipairs(fuelStock) do
        totalCapacity = totalCapacity + fuel.totalSmeltCapacity
    end
    
    return {
        config = config,
        fuelStock = fuelStock,
        totalSmeltCapacity = totalCapacity,
    }
end

---Auto-discover furnaces on the network
---@return number count Number of furnaces discovered
function manager.autoDiscover()
    local furnaceTypes = {
        "minecraft:furnace",
        "minecraft:blast_furnace", 
        "minecraft:smoker",
        "furnace",
        "blast_furnace",
        "smoker",
    }
    
    local discovered = 0
    local existing = furnaceConfig.getAll()
    
    for _, name in ipairs(peripheral.getNames()) do
        local types = {peripheral.getType(name)}
        for _, t in ipairs(types) do
            for _, furnaceType in ipairs(furnaceTypes) do
                if t == furnaceType then
                    -- Skip if already configured
                    if not existing[name] then
                        furnaceConfig.add(name)
                        discovered = discovered + 1
                    end
                    break
                end
            end
        end
    end
    
    return discovered
end

---Shutdown handler
function manager.beforeShutdown()
    logger.info("Furnace manager shutting down")
end

return manager
