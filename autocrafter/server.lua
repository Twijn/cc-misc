--- AutoCrafter Server
--- Main server component for automated crafting and storage management.
---
---@version 1.1.0

local VERSION = "1.1.0"

-- Setup package path
local diskPrefix = fs.exists("disk/lib") and "disk/" or ""
if not package.path:find(diskPrefix .. "lib") then
    package.path = package.path .. ";" .. diskPrefix .. "?.lua;" .. diskPrefix .. "lib/?.lua"
end

local logger = require("lib.log")
local recipes = require("lib.recipes")
local comms = require("lib.comms")
local cmd = require("lib.cmd")
local FormUI = require("lib.formui")
local inventory = require("lib.inventory")

-- Load managers
local queueManager = require("managers.queue")
local storageManager = require("managers.storage")
local crafterManager = require("managers.crafter")
local monitorManager = require("managers.monitor")

-- Load config modules
local settings = require("config.settings")
local targets = require("config.targets")
local config = require("config")

local running = true
local shuttingDown = false
local chatboxAvailable = false  -- Whether chatbox API is available with required capabilities

---Get the server version
function _G.acVersion()
    return VERSION
end

---Check if server is shutting down
function _G.acIsShuttingDown()
    return shuttingDown
end

--- Initialize the server
local function initialize()
    term.clear()
    term.setCursorPos(1, 1)
    
    print("================================")
    print("  AutoCrafter Server v" .. VERSION)
    print("================================")
    print("")
    
    -- Initialize communications
    print("Initializing modem...")
    if comms.init(true) then
        comms.setChannel(settings.get("modemChannel"))
        local modemInfo = comms.getModemInfo()
        print("  Modem: " .. (modemInfo.isWireless and "Wireless" or "Wired"))
        print("  Channel: " .. modemInfo.channel)
    else
        term.setTextColor(colors.yellow)
        print("  Warning: No modem found!")
        term.setTextColor(colors.white)
    end
    print("")
    
    -- Load recipes
    print("Loading recipes...")
    local recipeCount = recipes.init()
    print("  Loaded " .. recipeCount .. " recipes")
    print("")
    
    -- Initialize managers
    print("Initializing managers...")
    queueManager.init()
    storageManager.init(config.storagePeripheralType)
    storageManager.setScanInterval(settings.get("scanInterval"))
    crafterManager.init()
    monitorManager.init(config.monitorRefreshInterval)
    print("")
    
    -- Initial stats
    local storageStats = storageManager.getStats()
    print(string.format("Storage: %d items in %d inventories",
        storageStats.totalItems, storageStats.inventoryCount))
    print(string.format("Slots: %d/%d (%d%% full)",
        storageStats.usedSlots, storageStats.totalSlots, storageStats.percentFull))
    print("")
    
    local targetCount = targets.count()
    print("Craft targets: " .. targetCount)
    print("")
    
    -- Initialize chatbox for in-game commands
    if config.chatboxEnabled then
        print("Initializing chatbox...")
        if chatbox then
            -- Give chatbox time to fully initialize
            sleep(0.5)
            
            if chatbox.hasCapability then
                local hasCommand = chatbox.hasCapability("command")
                local hasTell = chatbox.hasCapability("tell")
                
                if hasCommand then
                    chatboxAvailable = true
                    term.setTextColor(colors.lime)
                    print("  Chatbox available!")
                    print("  - Command capability: YES")
                    print("  - Tell capability: " .. (hasTell and "YES" or "NO"))
                    print("  Use \\help in-game for commands")
                    term.setTextColor(colors.white)
                    
                    -- Show owner restriction status
                    if config.chatboxOwner then
                        term.setTextColor(colors.lime)
                        print("  Owner: " .. config.chatboxOwner)
                        term.setTextColor(colors.white)
                    else
                        term.setTextColor(colors.yellow)
                        print("  Warning: No owner set - all players can use commands!")
                        print("  Set chatboxOwner in config.lua to restrict access")
                        term.setTextColor(colors.white)
                    end
                else
                    term.setTextColor(colors.yellow)
                    print("  Chatbox found but missing 'command' capability")
                    print("  Register a license with /chatbox license register")
                    term.setTextColor(colors.white)
                end
            else
                term.setTextColor(colors.yellow)
                print("  Warning: Chatbox API not available")
                print("  In-game commands disabled")
                term.setTextColor(colors.white)
            end
        else
            term.setTextColor(colors.yellow)
            print("  Warning: Chatbox API not available")
            print("  In-game commands disabled")
            term.setTextColor(colors.white)
        end
        print("")
    end
    
    -- Check manipulator for player inventory access
    print("Checking manipulator...")
    if storageManager.hasManipulator() then
        term.setTextColor(colors.lime)
        print("  Manipulator connected!")
        print("  Player item transfers enabled")
        term.setTextColor(colors.white)
    else
        term.setTextColor(colors.yellow)
        print("  Warning: No manipulator found")
        print("  Player item transfers disabled")
        term.setTextColor(colors.white)
    end
    print("")
    
    sleep(1)
    logger.info("AutoCrafter Server started")
end

--- Process crafting targets and create jobs
--- Creates multiple jobs per item to utilize all available idle crafters
local function processCraftTargets()
    local stock = storageManager.getAllStock()
    local needed = targets.getNeeded(stock)
    
    -- Get count of idle crafters available
    local crafterStats = crafterManager.getStats()
    local availableCrafters = crafterStats.idle or 0
    
    if availableCrafters == 0 then
        return -- No idle crafters, don't create jobs yet
    end
    
    for _, target in ipairs(needed) do
        -- Count existing active jobs for this item (pending, assigned, or crafting)
        local jobs = queueManager.getJobs()
        local activeJobCount = 0
        local totalQueued = 0
        for _, job in ipairs(jobs) do
            if job.recipe and job.recipe.output == target.item then
                if job.status == "pending" or job.status == "assigned" or job.status == "crafting" then
                    activeJobCount = activeJobCount + 1
                    totalQueued = totalQueued + (job.expectedOutput or 0)
                end
            end
        end
        
        -- Calculate how many items still need to be queued
        local remainingNeeded = target.needed - totalQueued
        if remainingNeeded <= 0 then
            -- Already have enough queued
            goto continue
        end
        
        -- Calculate how many more jobs we can create (up to available crafters)
        local maxNewJobs = availableCrafters - activeJobCount
        if maxNewJobs <= 0 then
            goto continue
        end
        
        -- Get recipe to determine output count per craft
        local recipe = require("lib.recipes").getRecipeFor(target.item)
        if not recipe then
            goto continue
        end
        
        local outputPerCraft = recipe.outputCount or 1
        local maxBatch = settings.get("maxBatchSize")
        
        -- Create multiple jobs to distribute work across crafters
        local jobsCreated = 0
        while remainingNeeded > 0 and jobsCreated < maxNewJobs do
            -- Calculate batch size for this job
            local toCraft = math.min(remainingNeeded, maxBatch)
            
            -- Create the job
            local job, err = queueManager.addJob(target.item, toCraft, stock)
            if not job then
                if err then
                    logger.warn("Cannot craft " .. target.item .. ": " .. err)
                end
                break -- Stop if we can't create more jobs (likely missing materials)
            end
            
            remainingNeeded = remainingNeeded - toCraft
            jobsCreated = jobsCreated + 1
            
            -- Update stock to reflect materials reserved for this job
            -- This prevents creating jobs that can't be fulfilled
            for item, count in pairs(job.materials or {}) do
                stock[item] = (stock[item] or 0) - count
            end
        end
        
        ::continue::
    end
end

--- Dispatch jobs to available crafters
local function dispatchJobs()
    -- Dispatch all pending jobs to all available idle crafters
    while true do
        local job = queueManager.getNextJob()
        if not job then return end
        
        local crafter = crafterManager.getIdleCrafter()
        if not crafter then return end
        
        if queueManager.assignJob(job.id, crafter.id) then
            crafterManager.sendCraftRequest(crafter.id, job)
            crafterManager.updateStatus(crafter.id, "crafting", job.id)
        else
            -- Failed to assign, stop trying to avoid infinite loop
            return
        end
    end
end

-- Throttle state to prevent excessive processing
local lastCraftTargetProcess = 0
local craftTargetProcessInterval = 5  -- Minimum seconds between processCraftTargets calls

--- Handle network messages
local function messageHandler()
    while running do
        local message = comms.receive(1)
        if message then
            local result = crafterManager.handleMessage(message)
            
            if result then
                if result.type == "craft_complete" then
                    queueManager.completeJob(result.jobId, result.actualOutput)
                    -- Mark storage as needing a scan (will happen in storageScanLoop)
                    -- Don't block here with a full scan
                    storageManager.invalidateCache()
                    -- Dispatch any pending jobs immediately
                    dispatchJobs()
                elseif result.type == "craft_failed" then
                    queueManager.failJob(result.jobId, result.reason)
                    -- Try to dispatch other jobs
                    dispatchJobs()
                elseif result.type == "crafter_idle" then
                    -- Crafter just became idle, try to dispatch pending jobs
                    dispatchJobs()
                end
            end
            
            -- Handle inventory requests from crafters
            local msgType = message.type
            local sender = message.sender
            local data = message.data or {}
            
            if msgType == config.messageTypes.REQUEST_STOCK then
                -- Crafter requesting stock levels
                local stock = storageManager.getAllStock()
                comms.send(config.messageTypes.RESPONSE_STOCK, {
                    stock = stock,
                    timestamp = os.epoch("utc"),
                }, sender)
                
            elseif msgType == config.messageTypes.REQUEST_FIND_ITEM then
                -- Crafter requesting item locations
                local locations = inventory.findItem(data.item)
                comms.send(config.messageTypes.RESPONSE_FIND_ITEM, {
                    item = data.item,
                    locations = locations,
                }, sender)
                
            elseif msgType == config.messageTypes.REQUEST_WITHDRAW then
                -- Crafter requesting items to be pushed to it
                local withdrawn = storageManager.withdraw(data.item, data.count, data.destInv, data.destSlot)
                comms.send(config.messageTypes.RESPONSE_WITHDRAW, {
                    item = data.item,
                    requested = data.count,
                    withdrawn = withdrawn,
                }, sender)
                
            elseif msgType == config.messageTypes.REQUEST_DEPOSIT then
                -- Crafter wants to deposit items
                local deposited = storageManager.deposit(data.sourceInv, data.item)
                comms.send(config.messageTypes.RESPONSE_DEPOSIT, {
                    deposited = deposited,
                }, sender)
                
            elseif msgType == config.messageTypes.REQUEST_CLEAR_SLOTS then
                -- Crafter wants to clear specific slots
                local cleared = storageManager.clearSlots(data.sourceInv, data.slots)
                comms.send(config.messageTypes.RESPONSE_CLEAR_SLOTS, {
                    cleared = cleared,
                }, sender)
                
            elseif msgType == config.messageTypes.SERVER_QUERY then
                -- Client asking if server exists
                comms.send(config.messageTypes.SERVER_ANNOUNCE, {
                    serverId = os.getComputerID(),
                    serverLabel = settings.get("serverLabel"),
                    version = VERSION,
                    online = true,
                }, sender)
            end
        end
    end
end

--- Storage scan loop
local function storageScanLoop()
    while running do
        if storageManager.needsScan() then
            storageManager.scan()
        end
        sleep(1)
    end
end

--- Craft target processing loop
local function craftTargetLoop()
    local craftCheckInterval = settings.get("craftCheckInterval")
    while running do
        -- Only process if enough time has passed (prevents spam from multiple triggers)
        local now = os.clock()
        if (now - lastCraftTargetProcess) >= craftTargetProcessInterval then
            lastCraftTargetProcess = now
            processCraftTargets()
        end
        dispatchJobs()
        sleep(craftCheckInterval)
    end
end

--- Crafter ping loop
local function crafterPingLoop()
    local pingInterval = config.pingInterval or 30
    while running do
        crafterManager.pingAll()
        sleep(pingInterval)
    end
end

--- Server announce loop
local function serverAnnounceLoop()
    while running do
        if comms.isConnected() then
            comms.broadcast(config.messageTypes.SERVER_ANNOUNCE, {
                serverId = os.getComputerID(),
                serverLabel = settings.get("serverLabel"),
                version = VERSION,
                online = true,
            })
        end
        sleep(60)
    end
end

--- Monitor refresh loop
local function monitorRefreshLoop()
    while running do
        if monitorManager.needsRefresh() then
            local stock = storageManager.getAllStock()
            monitorManager.drawStatus({
                storage = storageManager.getStats(),
                queue = queueManager.getStats(),
                crafters = crafterManager.getStats(),
                targets = targets.getWithStock(stock),
            })
        end
        sleep(config.monitorRefreshInterval or 5)
    end
end

--- Command definitions
local commands = {
    status = {
        description = "Show system status",
        execute = function(args, ctx)
            local storageStats = storageManager.getStats()
            local queueStats = queueManager.getStats()
            local crafterStats = crafterManager.getStats()
            
            print("")
            ctx.mess("=== Storage ===")
            print(string.format("  Items: %d unique, %d total",
                storageStats.uniqueItems, storageStats.totalItems))
            print(string.format("  Slots: %d/%d (%d%% full)",
                storageStats.usedSlots, storageStats.totalSlots, storageStats.percentFull))
            print(string.format("  Inventories: %d", storageStats.inventoryCount))
            
            print("")
            ctx.mess("=== Queue ===")
            print(string.format("  Pending: %d, Active: %d",
                queueStats.pending, queueStats.assigned + queueStats.crafting))
            print(string.format("  Today: %d completed, %d failed",
                queueStats.completedToday, queueStats.failedToday))
            
            print("")
            ctx.mess("=== Crafters ===")
            print(string.format("  Online: %d/%d",
                crafterStats.online, crafterStats.total))
            print(string.format("  Idle: %d, Busy: %d",
                crafterStats.idle, crafterStats.busy))
        end
    },
    
    queue = {
        description = "View crafting queue",
        execute = function(args, ctx)
            local jobs = queueManager.getJobs()
            
            if #jobs == 0 then
                ctx.mess("Queue is empty")
                return
            end
            
            print("")
            ctx.mess("=== Crafting Queue ===")
            for _, job in ipairs(jobs) do
                local output = job.recipe and job.recipe.output or "unknown"
                output = output:gsub("minecraft:", "")
                
                local status = job.status
                local statusColor = colors.white
                if status == "pending" then
                    statusColor = colors.yellow
                elseif status == "assigned" or status == "crafting" then
                    statusColor = colors.lime
                end
                
                term.setTextColor(colors.lightGray)
                write(string.format("#%d ", job.id))
                term.setTextColor(colors.white)
                write(string.format("%dx %s ", job.expectedOutput, output))
                term.setTextColor(statusColor)
                print("[" .. status .. "]")
            end
            term.setTextColor(colors.white)
        end
    },
    
    add = {
        description = "Add item to auto-craft list",
        execute = function(args, ctx)
            if #args < 2 then
                ctx.err("Usage: add <item> <quantity>")
                return
            end
            
            local item = args[1]
            local quantity = tonumber(args[2])
            
            if not quantity or quantity <= 0 then
                ctx.err("Quantity must be a positive number")
                return
            end
            
            -- Add minecraft: prefix if missing
            if not item:find(":") then
                item = "minecraft:" .. item
            end
            
            -- Check if recipe exists
            if not recipes.canCraft(item) then
                ctx.err("No recipe found for " .. item)
                return
            end
            
            targets.set(item, quantity)
            ctx.succ(string.format("Added %s (target: %d)", item, quantity))
        end,
        complete = function(args)
            if #args == 1 then
                -- Complete item names (handle empty string)
                local query = args[1] or ""
                if query == "" then return {} end
                local results = recipes.search(query)
                local completions = {}
                for _, r in ipairs(results) do
                    table.insert(completions, (r.output:gsub("minecraft:", "")))
                end
                return completions
            end
            return {}
        end
    },
    
    remove = {
        description = "Remove item from auto-craft list",
        execute = function(args, ctx)
            if #args < 1 then
                ctx.err("Usage: remove <item>")
                return
            end
            
            local item = args[1]
            if not item:find(":") then
                item = "minecraft:" .. item
            end
            
            if not targets.get(item) then
                ctx.err("Item not in craft list: " .. item)
                return
            end
            
            targets.remove(item)
            ctx.succ("Removed " .. item)
        end,
        complete = function(args)
            if #args == 1 then
                local query = args[1] or ""
                if query == "" then return {} end
                local all = targets.getAll()
                local completions = {}
                for item in pairs(all) do
                    if item:lower():find(query:lower(), 1, true) then
                        table.insert(completions, (item:gsub("minecraft:", "")))
                    end
                end
                return completions
            end
            return {}
        end
    },
    
    list = {
        description = "List auto-craft items",
        execute = function(args, ctx)
            local stock = storageManager.getAllStock()
            local all = targets.getWithStock(stock)
            
            if #all == 0 then
                ctx.mess("No craft targets configured")
                return
            end
            
            print("")
            ctx.mess("=== Craft Targets ===")
            for _, target in ipairs(all) do
                local item = target.item:gsub("minecraft:", "")
                
                if target.current >= target.target then
                    term.setTextColor(colors.lime)
                    write("+ ")
                else
                    term.setTextColor(colors.orange)
                    write("* ")
                end
                
                term.setTextColor(colors.white)
                write(item .. " ")
                term.setTextColor(colors.lightGray)
                print(string.format("%d/%d", target.current, target.target))
            end
            term.setTextColor(colors.white)
        end
    },
    
    scan = {
        description = "Force inventory rescan",
        execute = function(args, ctx)
            local forceRefresh = args[1] == "full" or args[1] == "-f"
            if forceRefresh then
                ctx.mess("Performing full rescan (rediscovering peripherals)...")
            else
                ctx.mess("Scanning inventories...")
            end
            storageManager.scan(forceRefresh)
            local stats = storageManager.getStats()
            ctx.succ(string.format("Found %d items in %d slots",
                stats.totalItems, stats.usedSlots))
        end
    },
    
    cache = {
        description = "View or clear cache statistics",
        execute = function(args, ctx)
            if args[1] == "clear" then
                ctx.mess("Clearing all caches...")
                storageManager.clearCaches()
                ctx.succ("Caches cleared and rescanned")
                return
            end
            
            local stats = storageManager.getCacheStats()
            print("")
            ctx.mess("=== Cache Statistics ===")
            print(string.format("  Cached inventories: %d", stats.inventories))
            print(string.format("  Cached item details: %d", stats.itemDetails))
            print(string.format("  Wrapped peripherals: %d", stats.wrappedPeripherals))
            print(string.format("  Time since last scan: %.1fs", stats.timeSinceScan))
            print("")
            ctx.mess("Use 'cache clear' to clear all caches")
        end
    },
    
    withdraw = {
        description = "Withdraw items from storage to player",
        execute = function(args, ctx)
            if #args < 2 then
                ctx.err("Usage: withdraw <item> <count>")
                return
            end
            
            if not storageManager.hasManipulator() then
                ctx.err("No manipulator available for player transfers")
                return
            end
            
            local itemQuery = args[1]
            local count = tonumber(args[2])
            
            if not count or count <= 0 then
                ctx.err("Count must be a positive number")
                return
            end
            
            -- Use fuzzy matching to find the item
            local item, stock = storageManager.resolveItem(itemQuery)
            
            if not item or stock == 0 then
                ctx.err("Item not found in storage: " .. itemQuery)
                return
            end
            
            local toWithdraw = math.min(count, stock)
            local withdrawn, err = storageManager.withdrawToPlayer(item, toWithdraw, "player")
            
            if withdrawn > 0 then
                ctx.succ(string.format("Withdrew %d %s to player", withdrawn, item:gsub("minecraft:", "")))
            else
                ctx.err("Failed to withdraw: " .. (err or "unknown error"))
            end
        end,
        complete = function(args)
            if #args == 1 then
                local query = args[1] or ""
                if query == "" then return {} end
                local results = storageManager.searchItems(query)
                local completions = {}
                for _, item in ipairs(results) do
                    table.insert(completions, (item.item:gsub("minecraft:", "")))
                end
                return completions
            end
            return {}
        end
    },
    
    deposit = {
        description = "Deposit items from player to storage",
        execute = function(args, ctx)
            if not storageManager.hasManipulator() then
                ctx.err("No manipulator available for player transfers")
                return
            end
            
            local item = args[1]
            local count = args[2] and tonumber(args[2]) or nil
            
            if item and not item:find(":") then
                item = "minecraft:" .. item
            end
            
            local deposited, err = storageManager.depositFromPlayer("player", item, count)
            if deposited > 0 then
                if item then
                    ctx.succ(string.format("Deposited %d %s from player", deposited, item:gsub("minecraft:", "")))
                else
                    ctx.succ(string.format("Deposited %d items from player", deposited))
                end
            else
                ctx.mess("Nothing to deposit" .. (err and (": " .. err) or ""))
            end
        end,
        complete = function(args)
            return {}
        end
    },
    
    history = {
        description = "View job history (completed/failed)",
        execute = function(args, ctx)
            local historyType = args[1]  -- "completed", "failed", or nil for both
            local limit = tonumber(args[2]) or 10
            
            local history = queueManager.getHistory(historyType)
            
            print("")
            
            if historyType == "completed" or not historyType then
                local completed = historyType == "completed" and history or history.completed
                ctx.mess("=== Completed Jobs ===")
                if #completed == 0 then
                    print("  No completed jobs")
                else
                    local shown = 0
                    for _, job in ipairs(completed) do
                        if shown >= limit then
                            ctx.mess("... and " .. (#completed - limit) .. " more")
                            break
                        end
                        local output = job.recipe and job.recipe.output or "unknown"
                        output = output:gsub("minecraft:", "")
                        term.setTextColor(colors.lime)
                        write("  #" .. job.id .. " ")
                        term.setTextColor(colors.white)
                        print(string.format("%dx %s", job.actualOutput or 0, output))
                        shown = shown + 1
                    end
                end
                print("")
            end
            
            if historyType == "failed" or not historyType then
                local failed = historyType == "failed" and history or history.failed
                ctx.mess("=== Failed Jobs ===")
                if #failed == 0 then
                    print("  No failed jobs")
                else
                    local shown = 0
                    for _, job in ipairs(failed) do
                        if shown >= limit then
                            ctx.mess("... and " .. (#failed - limit) .. " more")
                            break
                        end
                        local output = job.recipe and job.recipe.output or "unknown"
                        output = output:gsub("minecraft:", "")
                        term.setTextColor(colors.red)
                        write("  #" .. job.id .. " ")
                        term.setTextColor(colors.white)
                        write(output .. " - ")
                        term.setTextColor(colors.orange)
                        print(job.failReason or "Unknown")
                        shown = shown + 1
                    end
                end
            end
            term.setTextColor(colors.white)
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"completed", "failed"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) then
                        table.insert(matches, opt)
                    end
                end
                return matches
            end
            return {}
        end
    },
    
    crafters = {
        description = "List connected crafters",
        execute = function(args, ctx)
            local allCrafters = crafterManager.getCrafters()
            
            if #allCrafters == 0 then
                ctx.mess("No crafters registered")
                return
            end
            
            print("")
            ctx.mess("=== Crafters ===")
            for _, crafter in ipairs(allCrafters) do
                local statusColor = colors.red
                if crafter.isOnline then
                    if crafter.status == "idle" then
                        statusColor = colors.lime
                    else
                        statusColor = colors.orange
                    end
                end
                
                term.setTextColor(colors.lightGray)
                write(string.format("#%d ", crafter.id))
                term.setTextColor(colors.white)
                write(crafter.label .. " ")
                term.setTextColor(statusColor)
                print("[" .. crafter.status .. "]")
            end
            term.setTextColor(colors.white)
        end
    },
    
    recipes = {
        description = "Search available recipes",
        execute = function(args, ctx)
            local query = args[1] or ""
            local results = recipes.search(query)
            
            if #results == 0 then
                ctx.mess("No recipes found" .. (query ~= "" and " for: " .. query or ""))
                return
            end
            
            print("")
            ctx.mess("=== Recipes ===")
            local shown = 0
            for _, r in ipairs(results) do
                if shown >= 20 then
                    ctx.mess("... and " .. (#results - 20) .. " more")
                    break
                end
                
                local output = r.output:gsub("minecraft:", "")
                print("  " .. output)
                shown = shown + 1
            end
        end
    },
    
    recipe = {
        description = "View recipe details",
        execute = function(args, ctx)
            if #args < 1 then
                ctx.err("Usage: recipe <item>")
                return
            end
            
            local item = args[1]
            if not item:find(":") then
                item = "minecraft:" .. item
            end
            
            local allRecipes = recipes.getRecipesFor(item)
            
            if #allRecipes == 0 then
                ctx.err("No recipe found for: " .. item)
                return
            end
            
            print("")
            local displayName = item:gsub("minecraft:", "")
            ctx.mess("=== Recipe: " .. displayName .. " ===")
            
            for i, recipe in ipairs(allRecipes) do
                if i > 1 then
                    print("")
                    ctx.mess("--- Alternative Recipe " .. i .. " ---")
                end
                
                -- Show output count
                term.setTextColor(colors.lightGray)
                write("  Output: ")
                term.setTextColor(colors.lime)
                print(recipe.outputCount .. "x " .. displayName)
                
                -- Show recipe type
                term.setTextColor(colors.lightGray)
                write("  Type: ")
                term.setTextColor(colors.white)
                print(recipe.type)
                
                -- Show ingredients
                term.setTextColor(colors.lightGray)
                print("  Ingredients:")
                for _, ingredient in ipairs(recipe.ingredients) do
                    local ingName = ingredient.item:gsub("minecraft:", "")
                    -- Handle tags (prefixed with #)
                    if ingName:sub(1, 1) == "#" then
                        ingName = ingName:sub(2) .. " (tag)"
                    end
                    term.setTextColor(colors.yellow)
                    write("    " .. ingredient.count .. "x ")
                    term.setTextColor(colors.white)
                    print(ingName)
                end
                
                -- Show crafting grid for shaped recipes
                if recipe.type == "shaped" and recipe.pattern then
                    term.setTextColor(colors.lightGray)
                    print("  Pattern:")
                    for _, row in ipairs(recipe.pattern) do
                        term.setTextColor(colors.gray)
                        write("    [")
                        for c = 1, #row do
                            local char = row:sub(c, c)
                            if char == " " then
                                term.setTextColor(colors.gray)
                                write(" ")
                            else
                                term.setTextColor(colors.cyan)
                                write(char)
                            end
                        end
                        term.setTextColor(colors.gray)
                        print("]")
                    end
                    
                    -- Show key legend
                    term.setTextColor(colors.lightGray)
                    print("  Key:")
                    for char, keyItem in pairs(recipe.key) do
                        local keyName = keyItem:gsub("minecraft:", "")
                        if keyName:sub(1, 1) == "#" then
                            keyName = keyName:sub(2) .. " (tag)"
                        end
                        term.setTextColor(colors.cyan)
                        write("    " .. char .. " = ")
                        term.setTextColor(colors.white)
                        print(keyName)
                    end
                end
                
                -- Only show first 3 recipes max
                if i >= 3 and #allRecipes > 3 then
                    print("")
                    ctx.mess("... and " .. (#allRecipes - 3) .. " more alternative recipes")
                    break
                end
            end
            term.setTextColor(colors.white)
        end,
        complete = function(args)
            if #args == 1 then
                local query = args[1] or ""
                if query == "" then return {} end
                local results = recipes.search(query)
                local completions = {}
                for _, r in ipairs(results) do
                    table.insert(completions, (r.output:gsub("minecraft:", "")))
                end
                return completions
            end
            return {}
        end
    },
    
    settings = {
        description = "View/edit settings",
        execute = function(args, ctx)
            if #args == 0 then
                -- Show current settings
                local all = settings.getAll()
                print("")
                ctx.mess("=== Settings ===")
                for key, value in pairs(all) do
                    term.setTextColor(colors.lightGray)
                    write("  " .. key .. ": ")
                    term.setTextColor(colors.white)
                    print(tostring(value))
                end
                return
            end
            
            -- Set a setting
            if #args < 2 then
                ctx.err("Usage: settings <key> <value>")
                return
            end
            
            local key = args[1]
            local value = args[2]
            
            -- Try to parse as number
            local numValue = tonumber(value)
            if numValue then
                value = numValue
            elseif value == "true" then
                value = true
            elseif value == "false" then
                value = false
            end
            
            settings.set(key, value)
            ctx.succ(string.format("Set %s = %s", key, tostring(value)))
        end
    },
    
    stock = {
        description = "Search item stock",
        execute = function(args, ctx)
            local query = args[1] or ""
            local results = storageManager.searchItems(query)
            
            if #results == 0 then
                ctx.mess("No items found" .. (query ~= "" and " for: " .. query or ""))
                return
            end
            
            print("")
            ctx.mess("=== Stock ===")
            local shown = 0
            for _, item in ipairs(results) do
                if shown >= 20 then
                    ctx.mess("... and " .. (#results - 20) .. " more")
                    break
                end
                
                local name = item.item:gsub("minecraft:", "")
                term.setTextColor(colors.white)
                write("  " .. name .. " ")
                term.setTextColor(colors.lightGray)
                print("x" .. item.count)
                shown = shown + 1
            end
            term.setTextColor(colors.white)
        end
    },
}

--- Send a message to a player via chatbox
---@param user string The username to send to
---@param message string The message to send
---@param isError? boolean Whether this is an error message
local function chatTell(user, message, isError)
    if not chatbox or not chatbox.hasCapability or not chatbox.hasCapability("tell") then
        return
    end
    
    local mode = "format"
    local prefix = isError and "&c" or "&a"
    local formattedMessage = prefix .. message
    
    pcall(chatbox.tell, user, formattedMessage, config.chatboxName, mode)
end

--- Handle chatbox commands from players
local function chatboxHandler()
    if not chatboxAvailable then
        -- No chatbox with command capability, just sleep forever
        while running do
            sleep(60)
        end
        return
    end
    
    while running do
        local event, user, command, args, data = os.pullEvent("command")
        
        -- Check if user is allowed to use commands
        if config.chatboxOwner and user ~= config.chatboxOwner then
            -- Ignore commands from other players
        elseif command == "help" then
            chatTell(user, "=== AutoCrafter Commands ===")
            chatTell(user, "\\withdraw <item> <count> - Get items from storage")
            chatTell(user, "\\deposit [item] [count] - Store items from your inventory")
            chatTell(user, "\\stock [search] - Search item stock")
            chatTell(user, "\\recipe <item> - View recipe details")
            chatTell(user, "\\status - Show system status")
            chatTell(user, "\\list - Show craft targets")
            
        elseif command == "withdraw" then
            if not storageManager.hasManipulator() then
                chatTell(user, "No manipulator available for item transfers", true)
            elseif not args or #args < 2 then
                chatTell(user, "Usage: \\withdraw <item> <count>", true)
            else
                local itemQuery = args[1]
                local count = tonumber(args[2])
                
                if not count or count <= 0 then
                    chatTell(user, "Count must be a positive number", true)
                else
                    -- Use fuzzy matching to find the item
                    local item, stock = storageManager.resolveItem(itemQuery)
                    
                    if not item or stock == 0 then
                        chatTell(user, "Item not found: " .. itemQuery, true)
                    else
                        local toWithdraw = math.min(count, stock)
                        local withdrawn, err = storageManager.withdrawToPlayer(item, toWithdraw, user)
                        
                        if withdrawn > 0 then
                            chatTell(user, string.format("Withdrew %dx %s", withdrawn, item:gsub("minecraft:", "")))
                        else
                            chatTell(user, "Failed to withdraw: " .. (err or "unknown error"), true)
                        end
                    end
                end
            end
            
        elseif command == "deposit" then
            if not storageManager.hasManipulator() then
                chatTell(user, "No manipulator available for item transfers", true)
            else
                local itemQuery = args and args[1] or nil
                local count = args and args[2] and tonumber(args[2]) or nil
                
                -- Resolve item name using fuzzy matching if specified
                local item = nil
                if itemQuery then
                    item = itemQuery
                    if not item:find(":") then
                        item = "minecraft:" .. item
                    end
                end
                
                local deposited, err = storageManager.depositFromPlayer(user, item, count)
                
                if deposited > 0 then
                    if item then
                        chatTell(user, string.format("Deposited %dx %s", deposited, item:gsub("minecraft:", "")))
                    else
                        chatTell(user, string.format("Deposited %d items", deposited))
                    end
                else
                    chatTell(user, "Nothing to deposit" .. (err and (": " .. err) or ""), true)
                end
            end
            
        elseif command == "stock" then
            local query = args and args[1] or ""
            local results = storageManager.searchItems(query)
            
            if #results == 0 then
                chatTell(user, "No items found" .. (query ~= "" and " for: " .. query or ""))
            else
                chatTell(user, "=== Stock ===")
                local shown = 0
                for _, item in ipairs(results) do
                    if shown >= 10 then
                        chatTell(user, "... and " .. (#results - 10) .. " more items")
                        break
                    end
                    
                    local name = item.item:gsub("minecraft:", "")
                    chatTell(user, string.format("  %s x%d", name, item.count))
                    shown = shown + 1
                end
            end
            
        elseif command == "status" then
            local storageStats = storageManager.getStats()
            local queueStats = queueManager.getStats()
            local crafterStats = crafterManager.getStats()
            
            chatTell(user, "=== AutoCrafter Status ===")
            chatTell(user, string.format("Storage: %d items, %d%% full",
                storageStats.totalItems, storageStats.percentFull))
            chatTell(user, string.format("Queue: %d pending, %d active",
                queueStats.pending, queueStats.assigned + queueStats.crafting))
            chatTell(user, string.format("Crafters: %d/%d online",
                crafterStats.online, crafterStats.total))
            
        elseif command == "list" then
            local stock = storageManager.getAllStock()
            local all = targets.getWithStock(stock)
            
            if #all == 0 then
                chatTell(user, "No craft targets configured")
            else
                chatTell(user, "=== Craft Targets ===")
                local shown = 0
                for _, target in ipairs(all) do
                    if shown >= 10 then
                        chatTell(user, "... and " .. (#all - 10) .. " more targets")
                        break
                    end
                    
                    local item = target.item:gsub("minecraft:", "")
                    local status = target.current >= target.target and "+" or "*"
                    chatTell(user, string.format("%s %s: %d/%d", status, item, target.current, target.target))
                    shown = shown + 1
                end
            end
            
        elseif command == "recipe" then
            if not args or #args < 1 then
                chatTell(user, "Usage: \\recipe <item>", true)
            else
                local item = args[1]
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                local allRecipes = recipes.getRecipesFor(item)
                
                if #allRecipes == 0 then
                    chatTell(user, "No recipe found for: " .. item, true)
                else
                    local recipe = allRecipes[1]
                    local displayName = item:gsub("minecraft:", "")
                    
                    chatTell(user, "=== Recipe: " .. displayName .. " ===")
                    chatTell(user, string.format("Output: %dx %s (%s)", recipe.outputCount, displayName, recipe.type))
                    
                    chatTell(user, "Ingredients:")
                    for _, ingredient in ipairs(recipe.ingredients) do
                        local ingName = ingredient.item:gsub("minecraft:", "")
                        if ingName:sub(1, 1) == "#" then
                            ingName = ingName:sub(2) .. " (tag)"
                        end
                        chatTell(user, string.format("  %dx %s", ingredient.count, ingName))
                    end
                    
                    if #allRecipes > 1 then
                        chatTell(user, string.format("(%d alternative recipes available)", #allRecipes - 1))
                    end
                end
            end
        end
    end
end

--- Handle termination
local function handleTerminate()
    os.pullEventRaw("terminate")
    
    shuttingDown = true
    running = false
    
    logger.info("Initiating graceful shutdown...")
    
    -- Call shutdown handlers
    storageManager.beforeShutdown()
    crafterManager.beforeShutdown()
    monitorManager.beforeShutdown()
    
    comms.close()
    
    logger.info("Shutdown complete")
    -- Flush any remaining log entries
    logger.flush()
end

--- Main entry point
local function main()
    initialize()
    
    -- Start all parallel loops
    parallel.waitForAny(
        handleTerminate,
        messageHandler,
        storageScanLoop,
        craftTargetLoop,
        crafterPingLoop,
        serverAnnounceLoop,
        monitorRefreshLoop,
        chatboxHandler,
        function()
            cmd("AutoCrafter", VERSION, commands)
        end
    )
end

main()
