--- Netherite Mining Program for ComputerCraft with Plethora Scanner
--- Uses the attach library for safe digging and peripheral management,
--- plethora scanner to locate ancient debris, and ender storage for item transfer.
---
--- Requirements:
--- - Turtle with a pickaxe (diamond/netherite)
--- - Plethora scanner module
--- - Ender storage (for depositing items)
--- - Wireless modem (optional, for GPS)
---
---@usage
--- Place the turtle in the nether at Y level 15 (optimal for ancient debris)
--- Ensure turtle has fuel, pickaxe, scanner, and ender storage in inventory
--- Run: netherite/miner
---
---@version 1.1.0

local MINER_VERSION = "1.1.0"
local MINER_UPDATE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main/netherite/miner.lua"

if not package.path:find("lib") then
    package.path = package.path .. ";lib/?.lua;lib/?/init.lua"
end

local attach = require("attach")
local log = require("log")
local persist = require("persist")

-- Optional: updater for auto-update functionality
local updaterLoaded, updater = pcall(require, "updater")
if not updaterLoaded then
    updater = nil
end

-- ======= Configuration =======
local CONFIG = {
    -- Scanner settings
    SCAN_RADIUS = 8,           -- Plethora scanner range
    SCAN_INTERVAL = 2,         -- Seconds between scans when no target

    -- Target blocks to mine
    TARGET_BLOCKS = {
        "minecraft:ancient_debris",
    },

    -- Inventory management
    DEPOSIT_THRESHOLD = 14,     -- Deposit when this many slots are full
    FUEL_MINIMUM = 500,         -- Minimum fuel before returning home
    FUEL_REFUEL_LEVEL = 1000,   -- Refuel to at least this level

    -- Fuel items
    FUEL_ITEMS = {
        "minecraft:coal",
        "minecraft:charcoal",
        "minecraft:coal_block",
        "minecraft:lava_bucket",
    },

    -- Default tools
    DEFAULT_PICKAXE = "minecraft:diamond_pickaxe",
    DEFAULT_SWORD = "minecraft:diamond_sword",
}

-- ======= State Management =======
local state = persist("netherite_miner.json")
state.setDefault("position", {x = 0, y = 0, z = 0})
state.setDefault("facing", 0)  -- 0=north, 1=east, 2=south, 3=west
state.setDefault("home", nil)
state.setDefault("stats", {
    debris_found = 0,
    blocks_mined = 0,
    deposits = 0,
})

-- Direction vectors for each facing
local DIRECTIONS = {
    [0] = {x = 0, z = -1},   -- North
    [1] = {x = 1, z = 0},    -- East
    [2] = {x = 0, z = 1},    -- South
    [3] = {x = -1, z = 0},   -- West
}

-- ======= Position Tracking =======
local pos = state.get("position")
local facing = state.get("facing")

local function savePosition()
    state.set("position", pos)
    state.set("facing", facing)
end

local function updatePosition(direction)
    if direction == "forward" then
        local dir = DIRECTIONS[facing]
        pos.x = pos.x + dir.x
        pos.z = pos.z + dir.z
    elseif direction == "back" then
        local dir = DIRECTIONS[facing]
        pos.x = pos.x - dir.x
        pos.z = pos.z - dir.z
    elseif direction == "up" then
        pos.y = pos.y + 1
    elseif direction == "down" then
        pos.y = pos.y - 1
    end
    savePosition()
end

local function turnLeft()
    turtle.turnLeft()
    facing = (facing - 1) % 4
    savePosition()
end

local function turnRight()
    turtle.turnRight()
    facing = (facing + 1) % 4
    savePosition()
end

-- ======= Movement Functions =======
local function forward()
    if attach.dig() or not turtle.detect() then
        if turtle.forward() then
            updatePosition("forward")
            return true
        end
    end
    return false
end

local function back()
    if turtle.back() then
        updatePosition("back")
        return true
    end
    -- If can't go back, turn around and dig
    turnRight()
    turnRight()
    local success = forward()
    turnRight()
    turnRight()
    return success
end

local function up()
    if attach.digUp() or not turtle.detectUp() then
        if turtle.up() then
            updatePosition("up")
            return true
        end
    end
    return false
end

local function down()
    if attach.digDown() or not turtle.detectDown() then
        if turtle.down() then
            updatePosition("down")
            return true
        end
    end
    return false
end

-- Turn to face a specific direction (0-3)
local function turnToFace(targetFacing)
    local diff = (targetFacing - facing) % 4
    if diff == 1 then
        turnRight()
    elseif diff == 2 then
        turnRight()
        turnRight()
    elseif diff == 3 then
        turnLeft()
    end
end

-- ======= Peripheral Setup =======
local scanner = nil
local enderStorage = nil

local function setupPeripherals()
    -- Set up default tools
    attach.setDefaultEquipped(CONFIG.DEFAULT_PICKAXE, CONFIG.DEFAULT_SWORD)

    -- Find plethora scanner
    scanner = attach.find("plethora:scanner")
    if not scanner then
        log.error("Plethora scanner not found! Please equip a scanner module.")
        return false
    end
    log.info("Scanner found and ready")

    -- Ender storage will be placed when needed
    log.info("Peripherals initialized")
    return true
end

-- ======= Scanner Functions =======
local function scanForDebris()
    if not scanner then
        log.error("No scanner available")
        return nil
    end

    local blocks = scanner.scan()
    local targets = {}

    for _, block in ipairs(blocks) do
        for _, target in ipairs(CONFIG.TARGET_BLOCKS) do
            if block.name == target then
                table.insert(targets, {
                    x = block.x,
                    y = block.y,
                    z = block.z,
                    name = block.name,
                    distance = math.sqrt(block.x^2 + block.y^2 + block.z^2)
                })
            end
        end
    end

    -- Sort by distance
    table.sort(targets, function(a, b) return a.distance < b.distance end)

    return targets
end

-- ======= Navigation =======
-- Navigate to a relative position from current location
local function navigateTo(relX, relY, relZ)
    -- Move vertically first (safer in nether)
    while relY > 0 do
        if not up() then
            log.warn("Blocked moving up")
            return false
        end
        relY = relY - 1
    end
    while relY < 0 do
        if not down() then
            log.warn("Blocked moving down")
            return false
        end
        relY = relY + 1
    end

    -- Move on X axis
    if relX > 0 then
        turnToFace(1)  -- East (+X)
        while relX > 0 do
            if not forward() then
                log.warn("Blocked moving east")
                return false
            end
            relX = relX - 1
        end
    elseif relX < 0 then
        turnToFace(3)  -- West (-X)
        while relX < 0 do
            if not forward() then
                log.warn("Blocked moving west")
                return false
            end
            relX = relX + 1
        end
    end

    -- Move on Z axis
    if relZ > 0 then
        turnToFace(2)  -- South (+Z)
        while relZ > 0 do
            if not forward() then
                log.warn("Blocked moving south")
                return false
            end
            relZ = relZ - 1
        end
    elseif relZ < 0 then
        turnToFace(0)  -- North (-Z)
        while relZ < 0 do
            if not forward() then
                log.warn("Blocked moving north")
                return false
            end
            relZ = relZ + 1
        end
    end

    return true
end

-- Navigate to absolute position
local function navigateToAbsolute(targetX, targetY, targetZ)
    local relX = targetX - pos.x
    local relY = targetY - pos.y
    local relZ = targetZ - pos.z
    return navigateTo(relX, relY, relZ)
end

-- ======= Inventory Management =======
local function countFullSlots()
    local count = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            count = count + 1
        end
    end
    return count
end

local function findEnderStorageSlot()
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and item.name:find("ender") and item.name:find("storage") then
            return slot
        end
    end
    return nil
end

local function depositItems()
    log.info("Depositing items to ender storage...")

    -- Find ender storage in inventory
    local enderSlot = findEnderStorageSlot()
    if not enderSlot then
        log.warn("No ender storage found in inventory!")
        return false
    end

    -- Place ender storage above us
    if turtle.detectUp() then
        attach.digUp()
    end

    turtle.select(enderSlot)
    if not turtle.placeUp() then
        log.error("Failed to place ender storage")
        return false
    end

    -- Wrap the ender storage
    local chest = peripheral.wrap("top")
    if not chest then
        log.error("Failed to wrap ender storage")
        turtle.digUp()  -- Pick it back up
        return false
    end

    -- Deposit all items except tools and the ender storage
    local deposited = 0
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            -- Skip tools, fuel, and important items
            local isImportant = item.name:find("pickaxe") or
                               item.name:find("sword") or
                               item.name:find("modem") or
                               item.name:find("scanner") or
                               item.name:find("ender")

            if not isImportant then
                turtle.select(slot)
                if turtle.dropUp() then
                    deposited = deposited + turtle.getItemCount(slot)
                end
            end
        end
    end

    -- Pick up ender storage
    turtle.select(enderSlot)
    turtle.digUp()

    log.info("Deposited items successfully")
    local stats = state.get("stats")
    stats.deposits = stats.deposits + 1
    state.set("stats", stats)

    return true
end

local function shouldDeposit()
    return countFullSlots() >= CONFIG.DEPOSIT_THRESHOLD
end

-- ======= Fuel Management =======
local function refuel()
    local currentFuel = turtle.getFuelLevel()
    if currentFuel == "unlimited" then return true end

    if currentFuel >= CONFIG.FUEL_REFUEL_LEVEL then return true end

    log.info("Refueling...")
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            for _, fuelItem in ipairs(CONFIG.FUEL_ITEMS) do
                if item.name == fuelItem then
                    turtle.select(slot)
                    turtle.refuel()
                    if turtle.getFuelLevel() >= CONFIG.FUEL_REFUEL_LEVEL then
                        return true
                    end
                end
            end
        end
    end

    return turtle.getFuelLevel() >= CONFIG.FUEL_MINIMUM
end

local function checkFuel()
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then return true end
    if fuel < CONFIG.FUEL_MINIMUM then
        log.warn("Low fuel: " .. fuel)
        refuel()
    end
    return fuel >= CONFIG.FUEL_MINIMUM
end

-- ======= Mining Logic =======
local function isTargetBlock(blockName)
    for _, targetName in ipairs(CONFIG.TARGET_BLOCKS) do
        if blockName == targetName then
            return true
        end
    end
    return false
end

local function mineTarget(target)
    log.info(string.format("Mining %s at relative (%d, %d, %d)", target.name, target.x, target.y, target.z))

    -- Scanner returns coordinates relative to the turtle's current position
    -- We need to navigate to a position NEXT TO the block, not into it
    
    -- Calculate target position (one block short on the primary axis)
    local targetX, targetY, targetZ = target.x, target.y, target.z
    
    -- Determine which direction to approach from (prefer horizontal approach)
    local approachX, approachY, approachZ = targetX, targetY, targetZ
    local mineDirection = nil  -- "forward", "up", "down"
    
    -- Calculate absolute distances
    local absX, absY, absZ = math.abs(targetX), math.abs(targetY), math.abs(targetZ)
    
    -- Choose approach direction - prefer horizontal, then vertical
    if absX >= absY and absX >= absZ and absX > 0 then
        -- Approach from X axis
        if targetX > 0 then
            approachX = targetX - 1
            mineDirection = "east"
        else
            approachX = targetX + 1
            mineDirection = "west"
        end
    elseif absZ >= absY and absZ > 0 then
        -- Approach from Z axis
        if targetZ > 0 then
            approachZ = targetZ - 1
            mineDirection = "south"
        else
            approachZ = targetZ + 1
            mineDirection = "north"
        end
    elseif absY > 0 then
        -- Approach vertically
        if targetY > 0 then
            approachY = targetY - 1
            mineDirection = "up"
        else
            approachY = targetY + 1
            mineDirection = "down"
        end
    else
        -- Block is at our position (shouldn't happen)
        log.warn("Target at turtle position?")
        return false
    end
    
    log.info(string.format("Navigating to (%d, %d, %d), will mine %s", approachX, approachY, approachZ, mineDirection))
    
    -- Navigate to the approach position
    if not navigateTo(approachX, approachY, approachZ) then
        log.warn("Could not reach approach position")
        return false
    end
    
    -- Now mine in the correct direction
    local found = false
    local success, block
    
    if mineDirection == "up" then
        success, block = turtle.inspectUp()
        if success and isTargetBlock(block.name) then
            attach.digUp()
            found = true
        end
    elseif mineDirection == "down" then
        success, block = turtle.inspectDown()
        if success and isTargetBlock(block.name) then
            attach.digDown()
            found = true
        end
    else
        -- Horizontal direction - need to face the right way
        local facingMap = {north = 0, east = 1, south = 2, west = 3}
        local targetFacing = facingMap[mineDirection]
        turnToFace(targetFacing)
        
        success, block = turtle.inspect()
        if success and isTargetBlock(block.name) then
            attach.dig()
            found = true
        end
    end
    
    -- If we didn't find it where expected, check all adjacent blocks
    if not found then
        log.info("Target not found at expected position, checking all directions...")
        
        -- Check all 4 horizontal directions
        for i = 0, 3 do
            turnToFace(i)
            success, block = turtle.inspect()
            if success and isTargetBlock(block.name) then
                attach.dig()
                found = true
                break
            end
        end
        
        -- Check up
        if not found then
            success, block = turtle.inspectUp()
            if success and isTargetBlock(block.name) then
                attach.digUp()
                found = true
            end
        end
        
        -- Check down
        if not found then
            success, block = turtle.inspectDown()
            if success and isTargetBlock(block.name) then
                attach.digDown()
                found = true
            end
        end
    end

    if found then
        local stats = state.get("stats")
        stats.debris_found = stats.debris_found + 1
        stats.blocks_mined = stats.blocks_mined + 1
        state.set("stats", stats)
        log.info("Ancient debris collected! Total: " .. stats.debris_found)
    else
        log.warn("Could not find target block after navigation")
    end

    return found
end

local function mineExplore()
    -- Simple exploration: mine forward in a pattern
    local stats = state.get("stats")

    for _ = 1, 3 do
        if forward() then
            stats.blocks_mined = stats.blocks_mined + 1
        else
            break
        end
    end

    state.set("stats", stats)
end

-- ======= Main Loop =======
local function printStats()
    local stats = state.get("stats")
    print("=== Netherite Miner Stats ===")
    print("Ancient Debris Found: " .. stats.debris_found)
    print("Blocks Mined: " .. stats.blocks_mined)
    print("Deposits: " .. stats.deposits)
    print("Position: " .. pos.x .. ", " .. pos.y .. ", " .. pos.z)
    print("Fuel: " .. turtle.getFuelLevel())
    print("=============================")
end

local function mainLoop()
    while true do
        -- Check fuel
        if not checkFuel() then
            log.error("Out of fuel! Stopping.")
            return
        end

        -- Check if we need to deposit
        if shouldDeposit() then
            depositItems()
        end

        -- Scan for ancient debris
        local targets = scanForDebris()

        if targets and #targets > 0 then
            log.info("Found " .. #targets .. " ancient debris nearby!")
            for _, target in ipairs(targets) do
                if mineTarget(target) then
                    -- Re-scan after mining each target
                    break
                end
            end
        else
            -- No targets found, explore
            mineExplore()

            -- Random direction change occasionally
            if math.random() < 0.2 then
                if math.random() < 0.5 then
                    turnLeft()
                else
                    turnRight()
                end
            end
        end

        -- Small delay between scans
        sleep(CONFIG.SCAN_INTERVAL)
    end
end

-- ======= Auto-Update =======
local function checkForMinerUpdate()
    log.info("Checking for miner updates...")
    
    local response = http.get(MINER_UPDATE_URL)
    if not response then
        log.warn("Could not check for miner updates")
        return false
    end
    
    local content = response.readAll()
    response.close()
    
    -- Parse version from downloaded content
    local remoteVersion = content:match('MINER_VERSION%s*=%s*["\']([^"\']+)["\']')
    if not remoteVersion then
        log.warn("Could not parse remote version")
        return false
    end
    
    -- Compare versions
    local function compareVersions(v1, v2)
        local parts1, parts2 = {}, {}
        for part in v1:gmatch("[^%.]+") do table.insert(parts1, tonumber(part) or 0) end
        for part in v2:gmatch("[^%.]+") do table.insert(parts2, tonumber(part) or 0) end
        for i = 1, math.max(#parts1, #parts2) do
            local p1, p2 = parts1[i] or 0, parts2[i] or 0
            if p1 < p2 then return -1 elseif p1 > p2 then return 1 end
        end
        return 0
    end
    
    if compareVersions(MINER_VERSION, remoteVersion) < 0 then
        log.info("Update available: " .. MINER_VERSION .. " -> " .. remoteVersion)
        
        -- Save the update
        local file = fs.open(shell.getRunningProgram(), "w")
        if file then
            file.write(content)
            file.close()
            log.info("Miner updated! Restarting...")
            sleep(1)
            os.reboot()
            return true
        else
            log.error("Failed to write update")
        end
    else
        log.info("Miner is up to date (v" .. MINER_VERSION .. ")")
    end
    
    return false
end

local function checkForLibraryUpdates()
    if not updater then
        return
    end
    
    log.info("Checking for library updates...")
    
    local updates = updater.checkUpdates()
    if #updates > 0 then
        log.info("Found " .. #updates .. " library update(s)")
        for _, update in ipairs(updates) do
            log.info("Updating " .. update.name .. ": " .. update.current .. " -> " .. update.latest)
            local success, err = updater.update(update.name)
            if success then
                log.info(update.name .. " updated successfully")
            else
                log.warn("Failed to update " .. update.name .. ": " .. tostring(err))
            end
        end
    else
        log.info("All libraries are up to date")
    end
end

local function autoUpdate()
    -- Check for miner updates first
    checkForMinerUpdate()
    
    -- Then check for library updates
    checkForLibraryUpdates()
end

-- ======= Initial Setup =======
local function askFacingDirection()
    print("")
    print("Which direction is the turtle facing?")
    print("  0 = North (-Z)")
    print("  1 = East  (+X)")
    print("  2 = South (+Z)")
    print("  3 = West  (-X)")
    print("")
    write("Enter direction (0-3): ")
    
    local input = read()
    local dir = tonumber(input)
    
    if dir and dir >= 0 and dir <= 3 then
        facing = dir
        savePosition()
        log.info("Facing direction set to " .. ({"North", "East", "South", "West"})[dir + 1])
        return true
    else
        print("Invalid input. Please enter 0, 1, 2, or 3.")
        return askFacingDirection()
    end
end

local function initialSetup()
    if not state.get("home") then
        print("")
        log.info("First time setup detected!")
        
        -- Ask for facing direction
        askFacingDirection()
        
        -- Set home position
        state.set("home", {x = pos.x, y = pos.y, z = pos.z, facing = facing})
        log.info("Home position set at (0, 0, 0)")
        print("")
    end
end

-- ======= Entry Point =======
local function main()
    print("=================================")
    print("  Netherite Mining Program v" .. MINER_VERSION)
    print("=================================")

    -- Auto-update check
    autoUpdate()

    -- First-time setup (asks for facing direction)
    initialSetup()

    -- Setup peripherals
    if not setupPeripherals() then
        log.error("Failed to setup peripherals. Exiting.")
        return
    end

    -- Initial refuel
    refuel()

    printStats()
    log.info("Starting mining operation...")

    -- Main mining loop with error handling
    local success, err = pcall(mainLoop)
    if not success then
        log.error("Error in main loop: " .. tostring(err))
    end

    printStats()
    log.info("Mining operation complete")
end

-- Run the program
main()
