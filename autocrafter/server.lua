--- AutoCrafter Server
--- Main server component for automated crafting and storage management.
---
---@version 1.0.0

local VERSION = "1.0.0"

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

-- Load managers
local queueManager = require("managers.queue")
local storageManager = require("managers.storage")
local crafterManager = require("managers.crafter")
local monitorManager = require("managers.monitor")

-- Load config modules
local settings = require("config.settings")
local targets = require("config.targets")

local running = true
local shuttingDown = false

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
    storageManager.init()
    storageManager.setScanInterval(settings.get("scanInterval"))
    crafterManager.init()
    monitorManager.init()
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
    
    sleep(1)
    logger.info("AutoCrafter Server started")
end

--- Process crafting targets and create jobs
local function processCraftTargets()
    local stock = storageManager.getAllStock()
    local needed = targets.getNeeded(stock)
    
    for _, target in ipairs(needed) do
        -- Check if we already have a job for this item
        local jobs = queueManager.getJobs()
        local hasJob = false
        for _, job in ipairs(jobs) do
            if job.recipe and job.recipe.output == target.item then
                hasJob = true
                break
            end
        end
        
        if not hasJob then
            local maxBatch = settings.get("maxBatchSize")
            local toCraft = math.min(target.needed, maxBatch)
            
            local job, err = queueManager.addJob(target.item, toCraft, stock)
            if not job and err then
                logger.warn("Cannot craft " .. target.item .. ": " .. err)
            end
        end
    end
end

--- Dispatch jobs to available crafters
local function dispatchJobs()
    local job = queueManager.getNextJob()
    if not job then return end
    
    local crafter = crafterManager.getIdleCrafter()
    if not crafter then return end
    
    if queueManager.assignJob(job.id, crafter.id) then
        crafterManager.sendCraftRequest(crafter.id, job)
        crafterManager.updateStatus(crafter.id, "crafting", job.id)
    end
end

--- Handle network messages
local function messageHandler()
    while running do
        local message = comms.receive(1)
        if message then
            local result = crafterManager.handleMessage(message)
            
            if result then
                if result.type == "craft_complete" then
                    queueManager.completeJob(result.jobId, result.actualOutput)
                    storageManager.scan()
                elseif result.type == "craft_failed" then
                    queueManager.failJob(result.jobId, result.reason)
                end
            end
        end
    end
end

--- Periodic tasks handler
local function periodicTasks()
    local lastCraftCheck = 0
    local lastPing = 0
    local craftCheckInterval = settings.get("craftCheckInterval")
    
    while running do
        local now = os.clock()
        
        -- Scan storage if needed
        if storageManager.needsScan() then
            storageManager.scan()
        end
        
        -- Check craft targets
        if now - lastCraftCheck >= craftCheckInterval then
            processCraftTargets()
            dispatchJobs()
            lastCraftCheck = now
        end
        
        -- Ping crafters
        if now - lastPing >= 10 then
            crafterManager.pingAll()
            lastPing = now
        end
        
        -- Update monitor
        if monitorManager.needsRefresh() then
            local stock = storageManager.getAllStock()
            monitorManager.drawStatus({
                storage = storageManager.getStats(),
                queue = queueManager.getStats(),
                crafters = crafterManager.getStats(),
                targets = targets.getWithStock(stock),
            })
        end
        
        sleep(0.5)
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
                -- Complete item names
                local results = recipes.search(args[1])
                local completions = {}
                for _, r in ipairs(results) do
                    table.insert(completions, r.output:gsub("minecraft:", ""))
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
                local all = targets.getAll()
                local completions = {}
                for item in pairs(all) do
                    if item:lower():find(args[1]:lower(), 1, true) then
                        table.insert(completions, item:gsub("minecraft:", ""))
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
            ctx.mess("Scanning inventories...")
            storageManager.scan()
            local stats = storageManager.getStats()
            ctx.succ(string.format("Found %d items in %d slots",
                stats.totalItems, stats.usedSlots))
        end
    },
    
    withdraw = {
        description = "Withdraw items from storage",
        execute = function(args, ctx)
            if #args < 2 then
                ctx.err("Usage: withdraw <item> <count>")
                return
            end
            
            local item = args[1]
            local count = tonumber(args[2])
            
            if not item:find(":") then
                item = "minecraft:" .. item
            end
            
            if not count or count <= 0 then
                ctx.err("Count must be a positive number")
                return
            end
            
            local stock = storageManager.getStock(item)
            if stock == 0 then
                ctx.err("Item not found in storage: " .. item)
                return
            end
            
            ctx.mess("Place a chest or other inventory adjacent to retrieve items")
            ctx.mess("(Feature requires destination inventory)")
            -- TODO: Implement actual withdrawal to player/chest
        end
    },
    
    deposit = {
        description = "Deposit items to storage",
        execute = function(args, ctx)
            ctx.mess("Place items in adjacent inventory to deposit")
            -- TODO: Implement deposit from adjacent inventory
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
end

--- Main entry point
local function main()
    initialize()
    
    -- Start the command interface
    parallel.waitForAny(
        handleTerminate,
        periodicTasks,
        messageHandler,
        function()
            cmd("AutoCrafter", VERSION, commands)
        end
    )
end

main()
