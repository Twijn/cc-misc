--- AutoCrafter Server
--- Main server component for automated crafting and storage management.
---
---@version 1.1.1

local VERSION = "1.1.1"

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
local exportManager = require("managers.export")

-- Load config modules
local settings = require("config.settings")
local targets = require("config.targets")
local exportConfig = require("config.exports")
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
    exportManager.init()
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
    
    local exportCount = exportConfig.count()
    print("Export inventories: " .. exportCount)
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
    
    -- Get count of idle crafters and pending jobs
    local crafterStats = crafterManager.getStats()
    local idleCrafters = crafterStats.idle or 0
    
    -- Count all pending jobs (not yet assigned to a crafter)
    local allJobs = queueManager.getJobs()
    local pendingJobCount = 0
    for _, job in ipairs(allJobs) do
        if job.status == "pending" then
            pendingJobCount = pendingJobCount + 1
        end
    end
    
    -- Available slots = idle crafters minus pending jobs waiting for assignment
    local availableSlots = idleCrafters - pendingJobCount
    
    if availableSlots <= 0 then
        return -- No capacity for new jobs
    end
    
    for _, target in ipairs(needed) do
        if availableSlots <= 0 then
            break -- No more capacity
        end
        
        -- Count queued output for this item to avoid over-queuing
        local totalQueued = 0
        for _, job in ipairs(allJobs) do
            if job.recipe and job.recipe.output == target.item then
                if job.status == "pending" or job.status == "assigned" or job.status == "crafting" then
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
        
        -- Get recipe to determine output count per craft
        local recipe = require("lib.recipes").getRecipeFor(target.item)
        if not recipe then
            goto continue
        end
        
        local outputPerCraft = recipe.outputCount or 1
        local maxBatch = settings.get("maxBatchSize")
        
        -- Create jobs to distribute work across available crafters
        while remainingNeeded > 0 and availableSlots > 0 do
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
            availableSlots = availableSlots - 1
            
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

--- Export processing loop
local function exportProcessLoop()
    local exportInterval = config.exportCheckInterval or 5
    while running do
        if exportManager.needsCheck() then
            exportManager.processExports()
        end
        sleep(exportInterval)
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

--- Stale job cleanup loop
local function staleJobCleanupLoop()
    local jobTimeout = (config.jobTimeout or 120) * 1000  -- Convert to milliseconds
    local checkInterval = 15  -- Check every 15 seconds
    
    while running do
        local resetCount = queueManager.resetStaleJobs(jobTimeout)
        if resetCount > 0 then
            logger.info(string.format("Reset %d stale job(s), dispatching...", resetCount))
            dispatchJobs()
        end
        sleep(checkInterval)
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
        description = "View or manage crafting queue",
        execute = function(args, ctx)
            local subCmd = args[1]
            
            if subCmd == "clear" then
                -- Clear all pending jobs from the queue
                local jobs = queueManager.getJobs()
                local pendingCount = 0
                for _, job in ipairs(jobs) do
                    if job.status == "pending" then
                        pendingCount = pendingCount + 1
                    end
                end
                
                if pendingCount == 0 then
                    ctx.mess("No pending jobs to clear")
                    return
                end
                
                queueManager.clearQueue()
                ctx.succ(string.format("Cleared %d pending job(s) from queue", pendingCount))
                return
            end
            
            -- Default: show queue
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
            print("")
            ctx.mess("Use 'queue clear' to clear all pending jobs")
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"clear"}
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
            
            local recipePrefs = require("config.recipes")
            local allRecipes = recipes.getRecipesSorted(item, true)
            local activeRecipe = recipes.getRecipeFor(item)
            
            if #allRecipes == 0 then
                ctx.err("No recipe found for: " .. item)
                return
            end
            
            print("")
            local displayName = item:gsub("minecraft:", "")
            ctx.mess("=== Recipe: " .. displayName .. " ===")
            
            if #allRecipes > 1 then
                term.setTextColor(colors.lightGray)
                print("  (" .. #allRecipes .. " variants available - use 'recipeprefs' to configure)")
            end
            
            for i, recipe in ipairs(allRecipes) do
                local isActive = activeRecipe and activeRecipe.source == recipe.source
                local isDisabled = recipePrefs.isDisabled(item, recipe.source)
                
                if i > 1 then
                    print("")
                    local variantLabel = "--- Variant " .. i
                    if isDisabled then
                        variantLabel = variantLabel .. " (DISABLED)"
                    elseif isActive then
                        variantLabel = variantLabel .. " (ACTIVE)"
                    end
                    variantLabel = variantLabel .. " ---"
                    ctx.mess(variantLabel)
                else
                    if isActive then
                        term.setTextColor(colors.lime)
                        print("  [ACTIVE - will be used for autocrafting]")
                    elseif isDisabled then
                        term.setTextColor(colors.red)
                        print("  [DISABLED]")
                    end
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
    
    exports = {
        description = "Manage export inventories",
        execute = function(args, ctx)
            local subCmd = args[1]
            
            if not subCmd or subCmd == "list" then
                -- List export inventories
                local all = exportConfig.getAll()
                local count = 0
                for _ in pairs(all) do count = count + 1 end
                
                if count == 0 then
                    ctx.mess("No export inventories configured")
                    ctx.mess("Use 'exports add' to add one")
                    return
                end
                
                print("")
                ctx.mess("=== Export Inventories ===")
                for name, cfg in pairs(all) do
                    local itemCount = #(cfg.slots or {})
                    local modeDisplay = cfg.mode
                    if cfg.mode == "empty" and itemCount == 0 then
                        modeDisplay = "drain all"
                    end
                    term.setTextColor(colors.lime)
                    write(cfg.mode == "stock" and "+" or "-")
                    term.setTextColor(colors.white)
                    write(" " .. name .. " ")
                    term.setTextColor(colors.lightGray)
                    if cfg.mode == "empty" and itemCount == 0 then
                        print(string.format("[%s]", modeDisplay))
                    else
                        print(string.format("[%s] %d items", modeDisplay, itemCount))
                    end
                end
                term.setTextColor(colors.white)
                
            elseif subCmd == "add" then
                -- Add a new export inventory using FormUI
                local searchType = config.exportDefaultType or "ender_storage"
                local peripheralNames = exportManager.findExportPeripherals(searchType)
                
                if #peripheralNames == 0 then
                    ctx.err("No " .. searchType .. " peripherals found")
                    ctx.mess("Try connecting ender storages or configure a different type")
                    return
                end
                
                local form = FormUI.new("Add Export Inventory")
                local peripheralField = form:peripheral("Inventory", searchType)
                local modeField = form:select("Mode", {"stock", "empty"}, 1)
                form:label("stock = push TO inventory | empty = pull FROM inventory")
                form:addSubmitCancel()
                
                local result = form:run()
                if not result then
                    ctx.mess("Cancelled")
                    return
                end
                
                local invName = peripheralField()
                local mode = modeField()
                
                exportConfig.set(invName, {
                    name = invName,
                    searchType = searchType,
                    mode = mode,
                    slots = {},
                })
                
                ctx.succ("Added export inventory: " .. invName)
                ctx.mess("Use 'exports items <name>' to add items")
                
            elseif subCmd == "remove" then
                local invName = args[2]
                if not invName then
                    ctx.err("Usage: exports remove <inventory>")
                    return
                end
                
                if not exportConfig.get(invName) then
                    ctx.err("Export inventory not found: " .. invName)
                    return
                end
                
                exportConfig.remove(invName)
                ctx.succ("Removed export inventory: " .. invName)
                
            elseif subCmd == "items" then
                local invName = args[2]
                if not invName then
                    ctx.err("Usage: exports items <inventory>")
                    return
                end
                
                local cfg = exportConfig.get(invName)
                if not cfg then
                    ctx.err("Export inventory not found: " .. invName)
                    return
                end
                
                -- Show and manage items for this export
                local items = cfg.slots or {}
                
                print("")
                ctx.mess("=== Items for " .. invName .. " ===")
                ctx.mess("Mode: " .. cfg.mode)
                print("")
                
                if #items == 0 then
                    if cfg.mode == "empty" then
                        term.setTextColor(colors.lime)
                        print("  (draining ALL items)")
                        term.setTextColor(colors.white)
                    else
                        ctx.mess("No items configured")
                    end
                else
                    for i, item in ipairs(items) do
                        term.setTextColor(colors.white)
                        write(string.format("%d. %s ", i, item.item:gsub("minecraft:", "")))
                        term.setTextColor(colors.lightGray)
                        if item.slot then
                            print(string.format("x%d (slot %d)", item.quantity, item.slot))
                        else
                            print(string.format("x%d", item.quantity))
                        end
                    end
                end
                term.setTextColor(colors.white)
                print("")
                ctx.mess("Use 'exports additem <inv> <item> <qty> [slot]' to add")
                ctx.mess("Use 'exports rmitem <inv> <item>' to remove")
                if cfg.mode == "empty" then
                    ctx.mess("Tip: Leave empty to drain ALL items from inventory")
                end
                
            elseif subCmd == "additem" then
                local invName = args[2]
                local item = args[3]
                local qty = tonumber(args[4]) or 0
                local slot = args[5] and tonumber(args[5]) or nil
                
                if not invName or not item then
                    ctx.err("Usage: exports additem <inventory> <item> <quantity> [slot]")
                    return
                end
                
                if not exportConfig.get(invName) then
                    ctx.err("Export inventory not found: " .. invName)
                    return
                end
                
                -- Add minecraft: prefix if missing
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                exportConfig.addItem(invName, item, qty, slot)
                ctx.succ(string.format("Added %s x%d to %s", item:gsub("minecraft:", ""), qty, invName))
                
            elseif subCmd == "rmitem" then
                local invName = args[2]
                local item = args[3]
                
                if not invName or not item then
                    ctx.err("Usage: exports rmitem <inventory> <item>")
                    return
                end
                
                if not exportConfig.get(invName) then
                    ctx.err("Export inventory not found: " .. invName)
                    return
                end
                
                -- Add minecraft: prefix if missing
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                exportConfig.removeItem(invName, item)
                ctx.succ(string.format("Removed %s from %s", item:gsub("minecraft:", ""), invName))
                
            elseif subCmd == "status" then
                local stats = exportManager.getStats()
                print("")
                ctx.mess("=== Export Status ===")
                print(string.format("  Inventories: %d", stats.inventoryCount))
                print(string.format("  Total items: %d", stats.itemCount))
                print(string.format("  Check interval: %ds", stats.checkInterval))
                print(string.format("  Last check: %.1fs ago", os.clock() - stats.lastCheck))
                
            elseif subCmd == "edit" then
                local invName = args[2]
                if not invName then
                    -- Show list of export inventories to choose from
                    local all = exportConfig.getAll()
                    local invNames = {}
                    for name in pairs(all) do
                        table.insert(invNames, name)
                    end
                    
                    if #invNames == 0 then
                        ctx.err("No export inventories configured")
                        ctx.mess("Use 'exports add' to create one first")
                        return
                    end
                    
                    local selectForm = FormUI.new("Select Export Inventory")
                    local invField = selectForm:select("Inventory", invNames, 1)
                    selectForm:addSubmitCancel()
                    
                    local selectResult = selectForm:run()
                    if not selectResult then
                        ctx.mess("Cancelled")
                        return
                    end
                    
                    invName = invField()
                end
                
                local cfg = exportConfig.get(invName)
                if not cfg then
                    ctx.err("Export inventory not found: " .. invName)
                    return
                end
                
                -- Interactive edit loop for managing items
                local items = cfg.slots or {}
                local editing = true
                
                while editing do
                    -- Build display of current items
                    local itemDisplay = {}
                    for i, item in ipairs(items) do
                        local display = item.item:gsub("minecraft:", "")
                        if item.slot then
                            display = display .. string.format(" x%d (slot %d)", item.quantity, item.slot)
                        else
                            display = display .. string.format(" x%d", item.quantity)
                        end
                        table.insert(itemDisplay, display)
                    end
                    
                    local form = FormUI.new("Edit Export: " .. invName)
                    form:label("Mode: " .. cfg.mode)
                    form:label(cfg.mode == "stock" and "Items will be pushed TO this inventory" or "Items will be pulled FROM this inventory")
                    form:label("")
                    form:label("Current items (" .. #items .. "):")
                    
                    if #itemDisplay == 0 then
                        if cfg.mode == "empty" then
                            form:label("  (draining ALL items)")
                        else
                            form:label("  (no items configured)")
                        end
                    else
                        for _, display in ipairs(itemDisplay) do
                            form:label("  " .. display)
                        end
                    end
                    
                    form:label("")
                    form:button("Add Item", "add")
                    if #items > 0 then
                        form:button("Remove Item", "remove")
                    end
                    form:button("Change Mode", "mode")
                    form:label("")
                    form:button("Done", "done")
                    
                    local result = form:run()
                    if not result then
                        editing = false
                    else
                        local action = nil
                        -- Find which button was pressed
                        for _, field in ipairs(form.fields) do
                            if field.type == "button" and result[field.label] then
                                action = field.action
                                break
                            end
                        end
                        
                        if action == "add" then
                            -- Form to add a new item
                            local addForm = FormUI.new("Add Item to Export")
                            local itemField = addForm:text("Item Name", "", nil, false)
                            local qtyField = addForm:number("Quantity", cfg.mode == "stock" and 64 or 0)
                            local useSlotField = addForm:checkbox("Use specific slot", false)
                            local slotField = addForm:number("Slot number", 1)
                            addForm:label("")
                            if cfg.mode == "stock" then
                                addForm:label("Quantity = amount to keep stocked")
                            else
                                addForm:label("Quantity = amount to leave (0 = take all)")
                            end
                            addForm:addSubmitCancel()
                            
                            local addResult = addForm:run()
                            if addResult then
                                local itemName = itemField()
                                local qty = qtyField()
                                local useSlot = useSlotField()
                                local slot = useSlot and slotField() or nil
                                
                                -- Add minecraft: prefix if missing
                                if itemName ~= "" and not itemName:find(":") then
                                    itemName = "minecraft:" .. itemName
                                end
                                
                                if itemName ~= "" then
                                    exportConfig.addItem(invName, itemName, qty, slot)
                                    -- Refresh items list
                                    cfg = exportConfig.get(invName)
                                    items = cfg.slots or {}
                                end
                            end
                            
                        elseif action == "remove" and #items > 0 then
                            -- Form to remove an item
                            local removeNames = {}
                            for _, item in ipairs(items) do
                                local display = item.item:gsub("minecraft:", "")
                                if item.slot then
                                    display = display .. " (slot " .. item.slot .. ")"
                                end
                                table.insert(removeNames, display)
                            end
                            
                            local removeForm = FormUI.new("Remove Item")
                            local removeField = removeForm:select("Item to remove", removeNames, 1)
                            removeForm:addSubmitCancel()
                            
                            local removeResult = removeForm:run()
                            if removeResult then
                                local idx = 1
                                for i, name in ipairs(removeNames) do
                                    if name == removeField() then
                                        idx = i
                                        break
                                    end
                                end
                                local toRemove = items[idx]
                                if toRemove then
                                    exportConfig.removeItem(invName, toRemove.item, toRemove.slot)
                                    -- Refresh items list
                                    cfg = exportConfig.get(invName)
                                    items = cfg.slots or {}
                                end
                            end
                            
                        elseif action == "mode" then
                            -- Toggle mode
                            local newMode = cfg.mode == "stock" and "empty" or "stock"
                            cfg.mode = newMode
                            exportConfig.set(invName, cfg)
                            
                        elseif action == "done" then
                            editing = false
                        end
                    end
                end
                
                ctx.succ("Export configuration saved")
                
            else
                ctx.err("Unknown subcommand: " .. subCmd)
                ctx.mess("Available: list, add, remove, items, additem, rmitem, edit, status")
            end
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"list", "add", "remove", "items", "additem", "rmitem", "edit", "status"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) then
                        table.insert(matches, opt)
                    end
                end
                return matches
            elseif #args == 2 and (args[1] == "remove" or args[1] == "items" or args[1] == "additem" or args[1] == "rmitem" or args[1] == "edit") then
                -- Complete export inventory names
                local query = (args[2] or ""):lower()
                local all = exportConfig.getAll()
                local matches = {}
                for name in pairs(all) do
                    if name:lower():find(query, 1, true) then
                        table.insert(matches, name)
                    end
                end
                return matches
            elseif #args == 3 and (args[1] == "additem" or args[1] == "rmitem") then
                -- Complete item names from stock
                local query = args[3] or ""
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
    
    recipeprefs = {
        description = "Manage recipe variant preferences",
        execute = function(args, ctx)
            local recipePrefs = require("config.recipes")
            local subCmd = args[1]
            
            if not subCmd or subCmd == "help" then
                print("")
                ctx.mess("=== Recipe Preferences Commands ===")
                term.setTextColor(colors.lightGray)
                print("  recipeprefs list [item]   - List items with preferences or recipes for item")
                print("  recipeprefs show <item>   - Show all recipe variants for an item")
                print("  recipeprefs prefer <item> <#> - Set preferred recipe variant")
                print("  recipeprefs enable <item> <#> - Enable a recipe variant")
                print("  recipeprefs disable <item> <#> - Disable a recipe variant")
                print("  recipeprefs clear <item>  - Clear preferences for an item")
                print("  recipeprefs clearall      - Clear all recipe preferences")
                term.setTextColor(colors.white)
                return
            end
            
            if subCmd == "list" then
                local item = args[2]
                
                if item then
                    -- List recipes for a specific item
                    if not item:find(":") then
                        item = "minecraft:" .. item
                    end
                    
                    local allRecipes = recipes.getRecipesFor(item, true)
                    if #allRecipes == 0 then
                        ctx.err("No recipes found for: " .. item)
                        return
                    end
                    
                    print("")
                    ctx.mess("=== Recipes for " .. item:gsub("minecraft:", "") .. " ===")
                    
                    for i, recipe in ipairs(allRecipes) do
                        local disabled = recipePrefs.isDisabled(item, recipe.source)
                        local pref = recipePrefs.get(item)
                        local isPrioritized = false
                        for _, src in ipairs(pref.priority or {}) do
                            if src == recipe.source then
                                isPrioritized = true
                                break
                            end
                        end
                        
                        local statusIcon = disabled and "X" or (isPrioritized and "*" or " ")
                        local statusColor = disabled and colors.red or (isPrioritized and colors.lime or colors.white)
                        
                        term.setTextColor(colors.lightGray)
                        write(string.format("  %d. ", i))
                        term.setTextColor(statusColor)
                        write("[" .. statusIcon .. "] ")
                        term.setTextColor(colors.white)
                        
                        -- Show ingredients summary
                        local ingList = {}
                        for _, ing in ipairs(recipe.ingredients) do
                            table.insert(ingList, ing.count .. "x " .. ing.item:gsub("minecraft:", ""))
                        end
                        print(recipe.outputCount .. "x from: " .. table.concat(ingList, ", "))
                        
                        -- Show source file (shortened)
                        term.setTextColor(colors.gray)
                        local shortSource = recipe.source:gsub(".*/recipes/", "")
                        print("     " .. shortSource)
                    end
                    
                    term.setTextColor(colors.white)
                    print("")
                    print("Legend: [*] = prioritized, [X] = disabled")
                else
                    -- List items with custom preferences
                    local items = recipePrefs.getCustomizedItems()
                    
                    if #items == 0 then
                        ctx.mess("No recipe preferences configured")
                        return
                    end
                    
                    print("")
                    ctx.mess("=== Items with Recipe Preferences ===")
                    for _, itemId in ipairs(items) do
                        local summary = recipePrefs.getSummary(itemId)
                        term.setTextColor(colors.yellow)
                        write("  " .. itemId:gsub("minecraft:", ""))
                        term.setTextColor(colors.lightGray)
                        print(" - " .. summary)
                    end
                    term.setTextColor(colors.white)
                end
                return
            end
            
            if subCmd == "show" then
                local item = args[2]
                if not item then
                    ctx.err("Usage: recipeprefs show <item>")
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                local allRecipes = recipes.getRecipesFor(item, true)
                if #allRecipes == 0 then
                    ctx.err("No recipes found for: " .. item)
                    return
                end
                
                print("")
                local displayName = item:gsub("minecraft:", "")
                ctx.mess("=== Recipe Variants: " .. displayName .. " ===")
                
                for i, recipe in ipairs(allRecipes) do
                    local disabled = recipePrefs.isDisabled(item, recipe.source)
                    
                    print("")
                    term.setTextColor(disabled and colors.red or colors.lime)
                    write(string.format("  [%d] ", i))
                    term.setTextColor(colors.white)
                    print(recipe.outputCount .. "x " .. displayName .. (disabled and " (DISABLED)" or ""))
                    
                    -- Show recipe type
                    term.setTextColor(colors.lightGray)
                    write("      Type: ")
                    term.setTextColor(colors.white)
                    print(recipe.type)
                    
                    -- Show ingredients
                    term.setTextColor(colors.lightGray)
                    print("      Ingredients:")
                    for _, ingredient in ipairs(recipe.ingredients) do
                        local ingName = ingredient.item:gsub("minecraft:", "")
                        if ingName:sub(1, 1) == "#" then
                            ingName = ingName:sub(2) .. " (tag)"
                        end
                        term.setTextColor(colors.yellow)
                        write("        " .. ingredient.count .. "x ")
                        term.setTextColor(colors.white)
                        print(ingName)
                    end
                    
                    -- Show source
                    term.setTextColor(colors.gray)
                    local shortSource = recipe.source:gsub(".*/recipes/", "")
                    print("      Source: " .. shortSource)
                end
                term.setTextColor(colors.white)
                return
            end
            
            if subCmd == "prefer" then
                local item = args[2]
                local idx = tonumber(args[3])
                
                if not item or not idx then
                    ctx.err("Usage: recipeprefs prefer <item> <recipe#>")
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                local allRecipes = recipes.getRecipesFor(item, true)
                if idx < 1 or idx > #allRecipes then
                    ctx.err("Invalid recipe number. Use 'recipeprefs show " .. item:gsub("minecraft:", "") .. "' to see variants.")
                    return
                end
                
                local recipe = allRecipes[idx]
                recipePrefs.setPreferred(item, recipe.source)
                ctx.succ("Set recipe #" .. idx .. " as preferred for " .. item:gsub("minecraft:", ""))
                return
            end
            
            if subCmd == "enable" then
                local item = args[2]
                local idx = tonumber(args[3])
                
                if not item or not idx then
                    ctx.err("Usage: recipeprefs enable <item> <recipe#>")
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                local allRecipes = recipes.getRecipesFor(item, true)
                if idx < 1 or idx > #allRecipes then
                    ctx.err("Invalid recipe number. Use 'recipeprefs show " .. item:gsub("minecraft:", "") .. "' to see variants.")
                    return
                end
                
                local recipe = allRecipes[idx]
                recipePrefs.enable(item, recipe.source)
                ctx.succ("Enabled recipe #" .. idx .. " for " .. item:gsub("minecraft:", ""))
                return
            end
            
            if subCmd == "disable" then
                local item = args[2]
                local idx = tonumber(args[3])
                
                if not item or not idx then
                    ctx.err("Usage: recipeprefs disable <item> <recipe#>")
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                local allRecipes = recipes.getRecipesFor(item, true)
                if idx < 1 or idx > #allRecipes then
                    ctx.err("Invalid recipe number. Use 'recipeprefs show " .. item:gsub("minecraft:", "") .. "' to see variants.")
                    return
                end
                
                local recipe = allRecipes[idx]
                recipePrefs.disable(item, recipe.source)
                ctx.succ("Disabled recipe #" .. idx .. " for " .. item:gsub("minecraft:", ""))
                return
            end
            
            if subCmd == "clear" then
                local item = args[2]
                
                if not item then
                    ctx.err("Usage: recipeprefs clear <item>")
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                recipePrefs.clear(item)
                ctx.succ("Cleared recipe preferences for " .. item:gsub("minecraft:", ""))
                return
            end
            
            if subCmd == "clearall" then
                recipePrefs.clearAll()
                ctx.succ("Cleared all recipe preferences")
                return
            end
            
            ctx.err("Unknown subcommand: " .. subCmd)
            ctx.mess("Use 'recipeprefs help' to see available commands")
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"list", "show", "prefer", "enable", "disable", "clear", "clearall", "help"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) then
                        table.insert(matches, opt)
                    end
                end
                return matches
            elseif #args == 2 and (args[1] == "list" or args[1] == "show" or args[1] == "prefer" or args[1] == "enable" or args[1] == "disable" or args[1] == "clear") then
                -- Complete item names
                local query = args[2] or ""
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
}

-- Register log level commands (loglevel, log-level, ll aliases)
logger.registerCommands(commands)

-- Register alias for recipeprefs command
commands.rp = commands.recipeprefs

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
                
                local allRecipes = recipes.getRecipesSorted(item, false)
                local activeRecipe = recipes.getRecipeFor(item)
                
                if #allRecipes == 0 then
                    chatTell(user, "No recipe found for: " .. item, true)
                else
                    local recipe = activeRecipe or allRecipes[1]
                    local displayName = item:gsub("minecraft:", "")
                    
                    chatTell(user, "=== Recipe: " .. displayName .. " ===")
                    if #allRecipes > 1 then
                        chatTell(user, "[Active recipe shown - " .. #allRecipes .. " variants available]")
                    end
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
                        chatTell(user, "Use terminal 'recipeprefs' to configure variants")
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
    exportManager.beforeShutdown()
    
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
        staleJobCleanupLoop,
        monitorRefreshLoop,
        exportProcessLoop,
        chatboxHandler,
        function()
            cmd("AutoCrafter", VERSION, commands)
        end
    )
end

main()
