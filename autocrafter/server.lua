--- AutoCrafter Server
--- Main server component for automated crafting and storage management.
---
---@version 1.4.0

local VERSION = "1.4.0"

-- Setup package path
local diskPrefix = fs.exists("disk/lib") and "disk/" or ""
if not package.path:find(diskPrefix .. "lib") then
    package.path = package.path .. ";/" .. diskPrefix .. "?.lua;/" .. diskPrefix .. "lib/?.lua"
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
local furnaceManager = require("managers.furnace")
local workerManager = require("managers.worker")
local requestManager = require("managers.request")

-- Load config modules
local settings = require("config.settings")
local targets = require("config.targets")
local exportConfig = require("config.exports")
local furnaceConfig = require("config.furnaces")
local workerConfig = require("config.workers")
local config = require("config")

local running = true
local shuttingDown = false
local chatboxAvailable = false  -- Whether chatbox API is available with required capabilities

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
    
    -- Set log level from config (default: warn for production)
    if config.logLevel then
        logger.setLevel(config.logLevel)
    end
    
    print("AutoCrafter Server v" .. VERSION)
    print("")
    
    -- Helper for timing startup phases
    local function timed(label, fn)
        local start = os.clock()
        term.setTextColor(colors.lightGray)
        term.write("  " .. label .. "... ")
        local result = fn()
        local elapsed = os.clock() - start
        term.setTextColor(colors.gray)
        print(string.format("%.2fs", elapsed))
        term.setTextColor(colors.white)
        return result
    end
    
    print("Initializing subsystems:")
    
    -- Initialize communications
    timed("Modem/comms", function()
        if comms.init(true) then
            comms.setChannel(settings.get("modemChannel"))
        end
    end)
    
    -- Load recipes and initialize managers
    local recipeCount = timed("Loading recipes", function()
        return recipes.init()
    end)
    
    timed("Queue manager", function()
        queueManager.init()
    end)
    
    timed("Storage manager", function()
        storageManager.init(config.storagePeripheralType)
        storageManager.setScanInterval(settings.get("scanInterval"))
    end)
    
    -- Verify storage peripherals are available
    local storageInvs = inventory.getStorageInventories()
    if #storageInvs == 0 then
        term.setTextColor(colors.red)
        print("ERROR: No storage peripherals found!")
        print("Configured type: " .. (config.storagePeripheralType or "not set"))
        print("Items will NOT be stored correctly until this is fixed.")
        term.setTextColor(colors.white)
    else
        term.setTextColor(colors.lime)
        print(string.format("Storage peripherals: %d (%s)", #storageInvs, config.storagePeripheralType))
        term.setTextColor(colors.white)
    end
    
    timed("Crafter manager", function() crafterManager.init() end)
    timed("Monitor manager", function() monitorManager.init(config.monitorRefreshInterval) end)
    timed("Export manager", function() exportManager.init() end)
    timed("Furnace manager", function() furnaceManager.init() end)
    timed("Worker manager", function() workerManager.init() end)
    timed("Request manager", function() requestManager.init() end)
    
    -- Show summary stats
    local storageStats = storageManager.getStats()
    print(string.format("Storage: %d items, %d/%d slots (%d%%)",
        storageStats.totalItems, storageStats.usedSlots, storageStats.totalSlots, storageStats.percentFull))
    print(string.format("Recipes: %d | Targets: %d | Exports: %d | Furnaces: %d | Workers: %d",
        recipeCount, targets.count(), exportConfig.count(), furnaceConfig.count(), workerConfig.countWorkers()))
    
    -- Initialize chatbox for in-game commands
    if config.chatboxEnabled and chatbox then
        sleep(0.5)
        if chatbox.hasCapability and chatbox.hasCapability("command") then
            chatboxAvailable = true
            term.setTextColor(colors.lime)
            print("Chatbox: OK" .. (config.chatboxOwner and (" (owner: " .. config.chatboxOwner .. ")") or " (no owner set)"))
            term.setTextColor(colors.white)
        else
            term.setTextColor(colors.yellow)
            print("Chatbox: missing 'command' capability")
            term.setTextColor(colors.white)
        end
    end
    
    -- Check manipulator
    if storageManager.hasManipulator() then
        term.setTextColor(colors.lime)
        print("Manipulator: OK")
        term.setTextColor(colors.white)
    else
        term.setTextColor(colors.yellow)
        print("Manipulator: DISCONNECTED (player inventory transfers disabled)")
        term.setTextColor(colors.white)
    end
    
    print("")
    logger.info("AutoCrafter Server started")
end

-- Track last error per item to avoid spam (reset after 60 seconds)
local lastCraftError = {}
local CRAFT_ERROR_COOLDOWN = 60  -- seconds

--- Process crafting targets and create jobs
--- Creates jobs to meet craft targets, queuing work for when crafters become available
local function processCraftTargets()
    local stock = storageManager.getAllStock()
    local needed = targets.getNeeded(stock)
    
    if #needed == 0 then
        return  -- No targets need crafting
    end
    
    -- Get all current jobs and build a lookup table of queued amounts per item
    -- This is O(jobs) instead of O(targets * jobs)
    -- Include ALL jobs (pending, waiting, assigned, crafting) to avoid duplicate queuing
    local allJobs = queueManager.getJobs()
    local queuedByItem = {}
    for _, job in ipairs(allJobs) do
        if job.recipe and job.recipe.output then
            -- Count all non-completed/non-failed jobs to avoid creating duplicates
            if job.status == "pending" or job.status == "waiting" or 
               job.status == "assigned" or job.status == "crafting" then
                local output = job.recipe.output
                queuedByItem[output] = (queuedByItem[output] or 0) + (job.expectedOutput or 0)
            end
        end
    end
    
    for _, target in ipairs(needed) do
        -- Look up queued count from pre-built table (O(1) instead of O(jobs))
        local totalQueued = queuedByItem[target.item] or 0
        
        -- Calculate how many items still need to be queued
        local remainingNeeded = target.needed - totalQueued
        if remainingNeeded <= 0 then
            -- Already have enough queued, no need to log this
            goto continue
        end
        
        -- Get recipe to determine output count per craft
        local recipe = recipes.getRecipeFor(target.item)
        if not recipe then
            -- Rate-limit "no recipe" messages
            local now = os.clock()
            local lastErr = lastCraftError[target.item]
            if not lastErr or (now - lastErr) >= CRAFT_ERROR_COOLDOWN then
                lastCraftError[target.item] = now
                logger.debug(string.format("processCraftTargets: no recipe for %s", target.item))
            end
            goto continue
        end
        
        -- Create a job for this target (one job at a time per target to avoid flooding)
        -- Pass the total target quantity; createJobTree will account for current stock
        local job, err = queueManager.addJob(target.item, target.target, stock)
        if not job then
            -- Don't log "Already have enough in stock" as an error since it's expected
            -- when current stock + queued jobs >= target
            if err and err ~= "Already have enough in stock" then
                -- logger.info(string.format("Failed to queue %s: %s", target.item:gsub("minecraft:", ""), err))
                
                -- Rate-limit error logging to avoid spam
                local now = os.clock()
                local lastErr = lastCraftError[target.item]
                if not lastErr or (now - lastErr) >= CRAFT_ERROR_COOLDOWN then
                    lastCraftError[target.item] = now
                    logger.debug(string.format("Cannot queue %s (need %d): %s", 
                        target.item:gsub("minecraft:", ""), target.needed, err))
                    
                    -- Add detailed material check
                    local hasMats, missing = require("lib.crafting").hasMaterials(recipe, stock, target.needed)
                    if not hasMats and missing then
                        for _, m in ipairs(missing) do
                            logger.debug(string.format("  Missing: %s (need %d, have %d)",
                                m.item:gsub("minecraft:", ""), m.needed, m.have))
                        end
                    end
                end
            end
            goto continue
        end
        
        logger.debug(string.format("processCraftTargets: queued job #%d for %dx %s", 
            job.id, job.expectedOutput, target.item))
        
        -- Update queued lookup table for the root job
        queuedByItem[target.item] = (queuedByItem[target.item] or 0) + job.expectedOutput
        
        -- IMPORTANT: Also update for any child jobs created (dependencies)
        -- This prevents creating duplicate jobs when both an item and its dependency are targets
        if job.rootId then
            local treeJobs = queueManager.getJobTree(job.rootId)
            for _, treeJob in ipairs(treeJobs) do
                if treeJob.recipe and treeJob.recipe.output and treeJob.id ~= job.id then
                    local childOutput = treeJob.recipe.output
                    queuedByItem[childOutput] = (queuedByItem[childOutput] or 0) + (treeJob.expectedOutput or 0)
                    logger.debug(string.format("processCraftTargets: child job #%d will produce %dx %s", 
                        treeJob.id, treeJob.expectedOutput or 0, childOutput))
                end
            end
        end
        
        -- Update stock to reflect materials reserved for this job
        -- This prevents creating jobs that can't be fulfilled
        for item, count in pairs(job.materials or {}) do
            stock[item] = (stock[item] or 0) - count
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
local craftTargetProcessInterval = 0.5  -- Minimum seconds between processCraftTargets calls

--- Handle network messages
local function messageHandler()
    while running do
        local message = comms.receive(1)
        if message then
            -- Handle crafter messages
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
            
            -- Handle worker messages
            local workerResult = workerManager.handleMessage(message)
            
            if workerResult then
                if workerResult.type == "work_complete" then
                    logger.debug(string.format("Worker %d completed task %s: produced %d",
                        workerResult.workerId, workerResult.taskId or "?", workerResult.produced or 0))
                    storageManager.invalidateCache()
                elseif workerResult.type == "work_failed" then
                    logger.warn(string.format("Worker %d failed task %s: %s",
                        workerResult.workerId, workerResult.taskId or "?", workerResult.reason or "unknown"))
                elseif workerResult.type == "worker_idle" then
                    -- Worker just became idle, check if there's work to dispatch
                    local stock = storageManager.getAllStock()
                    workerManager.dispatchWork(stock)
                end
            end
            
            -- Handle inventory requests from crafters/workers
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
                -- Crafter requesting item locations (from storage only)
                local locations = inventory.findItem(data.item, true)
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
                -- Crafter wants to clear specific slots (legacy method)
                logger.debug(string.format("REQUEST_CLEAR_SLOTS from %s: sourceInv=%s, slots=%s", 
                    tostring(sender), tostring(data.sourceInv), textutils.serialize(data.slots or {})))
                local cleared = storageManager.clearSlots(data.sourceInv, data.slots)
                logger.debug(string.format("REQUEST_CLEAR_SLOTS result: cleared=%d", cleared))
                comms.send(config.messageTypes.RESPONSE_CLEAR_SLOTS, {
                    cleared = cleared,
                }, sender)
                
            elseif msgType == config.messageTypes.REQUEST_PULL_SLOT then
                -- Crafter wants to pull a specific slot with known contents
                -- This is the preferred method for turtle clearing
                local slot = data.slot
                local itemName = data.itemName
                local itemCount = data.itemCount
                local itemNbt = data.itemNbt
                
                logger.debug(string.format("REQUEST_PULL_SLOT from %s: %s slot %d (%dx %s)", 
                    tostring(sender), tostring(data.sourceInv), slot, itemCount, itemName))
                
                local pulled, err = storageManager.pullSlot(data.sourceInv, slot, itemName, itemCount, itemNbt)
                
                comms.send(config.messageTypes.RESPONSE_PULL_SLOT, {
                    slot = slot,
                    pulled = pulled,
                    error = err,
                }, sender)
                
            elseif msgType == config.messageTypes.REQUEST_PULL_SLOTS_BATCH then
                -- Crafter wants to pull multiple slots in one batch (more efficient)
                local slotContents = data.slotContents or {}
                
                logger.debug(string.format("REQUEST_PULL_SLOTS_BATCH from %s: %s, %d slots", 
                    tostring(sender), tostring(data.sourceInv), #slotContents))
                
                local results, totalPulled = storageManager.pullSlotsBatch(data.sourceInv, slotContents)
                
                comms.send(config.messageTypes.RESPONSE_PULL_SLOTS_BATCH, {
                    results = results,
                    totalPulled = totalPulled,
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

--- Worker ping and dispatch loop
local function workerProcessLoop()
    local pingInterval = config.pingInterval or 30
    local checkInterval = 5  -- Check for work every 5 seconds
    local lastPing = 0
    
    while running do
        local now = os.clock()
        
        -- Ping workers periodically
        if now - lastPing >= pingInterval then
            workerManager.pingAll()
            lastPing = now
        end
        
        -- Dispatch work to idle workers
        local stock = storageManager.getAllStock()
        workerManager.dispatchWork(stock)
        
        sleep(checkInterval)
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

--- Furnace/smelting processing loop
local function furnaceProcessLoop()
    local furnaceInterval = config.furnaceCheckInterval or 5
    while running do
        if furnaceManager.needsCheck() then
            local stock = storageManager.getAllStock()
            local stats = furnaceManager.processSmelt(stock)
            
            -- Queue dried kelp block crafting if needed
            if stats.driedKelpProcessed and stats.driedKelpProcessed.blocksToQueue then
                local blocksToQueue = stats.driedKelpProcessed.blocksToQueue
                if blocksToQueue > 0 then
                    -- Check if there's already a pending job for dried kelp blocks
                    local allJobs = queueManager.getJobs()
                    local alreadyQueued = 0
                    for _, job in ipairs(allJobs) do
                        if job.status == "pending" or job.status == "assigned" or job.status == "crafting" then
                            if job.recipe and job.recipe.output == "minecraft:dried_kelp_block" then
                                alreadyQueued = alreadyQueued + (job.expectedOutput or 0)
                            end
                        end
                    end
                    
                    -- Only queue if we haven't already queued enough
                    local toQueue = blocksToQueue - alreadyQueued
                    if toQueue > 0 then
                        -- Refresh stock for accurate job creation
                        stock = storageManager.getAllStock()
                        -- Pass total blocks needed; createJobTree will account for current stock
                        local job, err = queueManager.addJob("minecraft:dried_kelp_block", blocksToQueue, stock)
                        if job then
                            logger.info(string.format("Dried kelp mode: queued %d dried kelp blocks", job.expectedOutput or 0))
                        elseif err then
                            logger.debug("Dried kelp mode: " .. err)
                        end
                    end
                end
            end
        end
        sleep(furnaceInterval)
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
                smeltTargets = furnaceConfig.getSmeltTargetsWithStock(stock),
                fuelSummary = furnaceManager.getFuelSummary(stock),
            })
        end
        sleep(config.monitorRefreshInterval or 5)
    end
end

--- Request processing loop
--- Monitors active requests, queues jobs, and delivers completed items
local function requestProcessLoop()
    local checkInterval = 2  -- Check every 2 seconds
    local reportInterval = 15000  -- Report status every 15 seconds (in ms)
    
    while running do
        local requests = requestManager.getActiveRequests()
        
        for _, req in ipairs(requests) do
            local stock = storageManager.getAllStock()
            local currentStock = stock[req.item] or 0
            
            -- Check request status and progress
            if req.status == requestManager.STATES.PENDING then
                -- Queue jobs for this request
                local needed = req.quantity - (req.produced or 0)
                if needed > 0 then
                    if req.isSmelt then
                        -- For smelt requests, check if we have input or need to craft it
                        local input = furnaceConfig.getSmeltInput(req.item)
                        if input then
                            local inputStock = stock[input] or 0
                            if inputStock >= needed then
                                -- Mark as smelting - furnace manager will pick it up
                                requestManager.updateRequest(req.id, requestManager.STATES.SMELTING)
                                logger.debug(string.format("Request #%d: starting smelt of %dx %s", 
                                    req.id, needed, req.item))
                            else
                                -- Not enough input material - try to craft it using job tree
                                -- Pass total needed; createJobTree will account for current stock
                                local job, err = queueManager.addJob(input, needed, stock, "request")
                                
                                if job then
                                    requestManager.updateRequest(req.id, requestManager.STATES.CRAFTING, {
                                        rootJobId = job.id,
                                        jobIds = {job.id},
                                        craftingInput = true,
                                    })
                                    logger.debug(string.format("Request #%d: queued job tree #%d for smelt input %dx %s", 
                                        req.id, job.id, needed, input))
                                else
                                    requestManager.updateRequest(req.id, requestManager.STATES.FAILED, {
                                        failReason = err or string.format("Cannot craft %s", input)
                                    })
                                end
                            end
                        else
                            requestManager.updateRequest(req.id, requestManager.STATES.FAILED, {
                                failReason = "No smelt recipe found"
                            })
                        end
                    else
                        -- For craft requests, use the queue manager's tree-based system
                        local job, err = requestManager.queueJob(req, stock)
                        
                        if not job then
                            -- Check if we already have enough in stock
                            if currentStock >= req.quantity then
                                requestManager.updateRequest(req.id, requestManager.STATES.READY, {
                                    produced = req.quantity
                                })
                            else
                                requestManager.updateRequest(req.id, requestManager.STATES.FAILED, {
                                    failReason = err or "Cannot queue job"
                                })
                            end
                        end
                    end
                else
                    -- Already have enough
                    requestManager.updateRequest(req.id, requestManager.STATES.READY, {
                        produced = req.quantity
                    })
                end
                
            elseif req.status == requestManager.STATES.QUEUED or 
                   req.status == requestManager.STATES.CRAFTING then
                -- Check if job tree is complete using the new tree-based system
                local complete, statusMsg = requestManager.checkComplete(req, stock)
                
                -- Update to crafting if jobs are active
                if req.status == requestManager.STATES.QUEUED and req.rootJobId then
                    local treeStatus = queueManager.getJobTreeStatus(req.rootJobId)
                    if treeStatus.assigned > 0 or treeStatus.crafting > 0 then
                        requestManager.updateRequest(req.id, requestManager.STATES.CRAFTING)
                    end
                end
                
                -- Check if we have enough stock now
                if complete or currentStock >= req.quantity then
                    requestManager.updateRequest(req.id, requestManager.STATES.READY, {
                        produced = req.quantity
                    })
                elseif statusMsg and statusMsg:find("Failed") then
                    requestManager.updateRequest(req.id, requestManager.STATES.FAILED, {
                        failReason = statusMsg
                    })
                end
                
            elseif req.status == requestManager.STATES.SMELTING then
                -- Check if input crafting is complete, then check smelt progress
                local input = furnaceConfig.getSmeltInput(req.item)
                local inputStock = input and (stock[input] or 0) or 0
                local needed = req.quantity - currentStock
                
                -- If we were crafting input, check if it's done
                if req.craftingInput and req.rootJobId then
                    local treeStatus = queueManager.getJobTreeStatus(req.rootJobId)
                    if treeStatus.completed == treeStatus.total then
                        -- Input crafting done, update state
                        requestManager.updateRequest(req.id, requestManager.STATES.SMELTING, {
                            craftingInput = false,
                        })
                    elseif treeStatus.failed > 0 then
                        requestManager.updateRequest(req.id, requestManager.STATES.FAILED, {
                            failReason = "Failed to craft input material"
                        })
                    end
                end
                
                -- Check smelt progress
                if currentStock >= req.quantity then
                    requestManager.updateRequest(req.id, requestManager.STATES.READY, {
                        produced = req.quantity
                    })
                elseif currentStock > (req.produced or 0) then
                    requestManager.updateRequest(req.id, requestManager.STATES.SMELTING, {
                        produced = currentStock
                    })
                end
                
            elseif req.status == requestManager.STATES.READY then
                -- Deliver items
                local toDeliver = math.min(req.quantity - (req.delivered or 0), currentStock)
                
                if toDeliver > 0 then
                    local delivered = 0
                    
                    if req.deliverTo == "storage" then
                        -- Items are already in storage, just mark as delivered
                        delivered = toDeliver
                    else
                        -- Deliver to player
                        if storageManager.hasManipulator() then
                            delivered = storageManager.withdrawToPlayer(req.item, toDeliver, req.deliverTo)
                            if delivered > 0 then
                                logger.info(string.format("Request #%d: delivered %dx %s to %s",
                                    req.id, delivered, req.item, req.deliverTo))
                            end
                        else
                            -- No manipulator, items stay in storage
                            logger.warn(string.format("Request #%d: no manipulator, items left in storage", req.id))
                            delivered = toDeliver
                        end
                    end
                    
                    if delivered > 0 then
                        requestManager.recordDelivered(req.id, delivered)
                        
                        -- Check if fully delivered
                        local totalDelivered = (req.delivered or 0) + delivered
                        if totalDelivered >= req.quantity then
                            requestManager.updateRequest(req.id, requestManager.STATES.DELIVERED)
                            logger.info(string.format("Request #%d completed: %dx %s", 
                                req.id, totalDelivered, req.item))
                            
                            -- Send completion message
                            if req.deliverTo ~= "storage" and chatboxAvailable then
                                chatTell(req.deliverTo, string.format("Request complete: %dx %s delivered!", 
                                    totalDelivered, req.item:gsub("minecraft:", "")))
                            end
                        end
                    end
                elseif (req.delivered or 0) >= req.quantity then
                    -- Already fully delivered
                    requestManager.updateRequest(req.id, requestManager.STATES.DELIVERED)
                end
            end
            
            -- Send periodic status reports for active requests
            if req.status ~= requestManager.STATES.DELIVERED and
               req.status ~= requestManager.STATES.FAILED and
               req.status ~= requestManager.STATES.CANCELLED then
                
                if requestManager.needsReport(req, reportInterval) then
                    local statusStr = requestManager.getStatusString(req)
                    logger.debug(string.format("Request #%d status: %s", req.id, statusStr))
                    
                    -- Send chatbox update for player requests
                    if req.deliverTo ~= "storage" and chatboxAvailable then
                        chatTell(req.deliverTo, string.format("Request #%d: %s - %s", 
                            req.id, req.item:gsub("minecraft:", ""), statusStr))
                    end
                    
                    requestManager.markReported(req.id)
                end
            end
        end
        
        sleep(checkInterval)
    end
end

--- Command definitions
local commands = {
    status = {
        description = "Show system status",
        category = "general",
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
        category = "queue",
        execute = function(args, ctx)
            local subCmd = args[1]
            
            if subCmd == "clear" then
                -- Clear all pending jobs from the queue
                local jobs = queueManager.getJobs()
                local pendingCount = 0
                for _, job in ipairs(jobs) do
                    if job.status == "pending" or job.status == "waiting" then
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
                
            elseif subCmd == "tree" then
                -- Show job tree for a specific root job
                local rootId = tonumber(args[2])
                if not rootId then
                    ctx.err("Usage: queue tree <root_job_id>")
                    return
                end
                
                local tree = queueManager.getJobTree(rootId)
                if #tree == 0 then
                    ctx.err("No jobs found for tree #" .. rootId)
                    return
                end
                
                local p = ctx.pager("=== Job Tree #" .. rootId .. " ===")
                local treeStatus = queueManager.getJobTreeStatus(rootId)
                
                p.setTextColor(colors.lightGray)
                p.print(string.format("Total: %d jobs | Complete: %d | Pending: %d | Waiting: %d",
                    treeStatus.total, treeStatus.completed, treeStatus.pending, treeStatus.waiting))
                p.print("")
                
                -- Sort by depth for display (parent first)
                table.sort(tree, function(a, b) return (a.depth or 0) < (b.depth or 0) end)
                
                for _, job in ipairs(tree) do
                    local output = job.recipe and job.recipe.output or "unknown"
                    output = output:gsub("minecraft:", "")
                    local indent = string.rep("  ", job.depth or 0)
                    
                    local status = job.status
                    local statusColor = colors.white
                    if status == "pending" then
                        statusColor = colors.yellow
                    elseif status == "waiting" then
                        statusColor = colors.orange
                    elseif status == "assigned" or status == "crafting" then
                        statusColor = colors.lime
                    elseif status == "completed" then
                        statusColor = colors.green
                    elseif status == "failed" then
                        statusColor = colors.red
                    end
                    
                    p.setTextColor(colors.lightGray)
                    p.write(indent .. "#" .. job.id .. " ")
                    p.setTextColor(colors.white)
                    p.write(string.format("%dx %s ", job.expectedOutput, output))
                    p.setTextColor(statusColor)
                    p.print("[" .. status .. "]")
                end
                
                p.show()
                return
            end
            
            -- Default: show queue
            local jobs = queueManager.getJobs()
            
            if #jobs == 0 then
                ctx.mess("Queue is empty")
                return
            end
            
            local stats = queueManager.getStats()
            local p = ctx.pager(string.format("=== Crafting Queue (%d jobs, %d root, %d child) ===", 
                #jobs, stats.rootJobs, stats.childJobs))
            
            for _, job in ipairs(jobs) do
                local output = job.recipe and job.recipe.output or "unknown"
                output = output:gsub("minecraft:", "")
                
                local status = job.status
                local statusColor = colors.white
                if status == "pending" then
                    statusColor = colors.yellow
                elseif status == "waiting" then
                    statusColor = colors.orange
                elseif status == "assigned" or status == "crafting" then
                    statusColor = colors.lime
                end
                
                -- Show indent for child jobs
                local indent = ""
                if job.parentId then
                    indent = "  "
                end
                
                p.setTextColor(colors.lightGray)
                p.write(indent .. "#" .. job.id .. " ")
                p.setTextColor(colors.white)
                p.write(string.format("%dx %s ", job.expectedOutput, output))
                p.setTextColor(statusColor)
                p.print("[" .. status .. "]")
            end
            p.print("")
            p.setTextColor(colors.lightBlue)
            p.print("Use 'queue clear' to clear all pending jobs")
            p.print("Use 'queue tree <id>' to view job tree details")
            p.show()
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"clear", "tree"}
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
        description = "Add item to auto-craft or auto-smelt list",
        category = "queue",
        execute = function(args, ctx)
            if #args < 2 then
                ctx.err("Usage: add <item> <quantity> [--smelt]")
                print("  Add --smelt flag to add to smelt targets instead of craft")
                return
            end
            
            -- Check for --smelt flag
            local isSmelt = false
            local filteredArgs = {}
            for _, arg in ipairs(args) do
                if arg == "--smelt" or arg == "-s" then
                    isSmelt = true
                else
                    table.insert(filteredArgs, arg)
                end
            end
            
            local item = filteredArgs[1]
            local quantity = tonumber(filteredArgs[2])
            
            if not quantity or quantity <= 0 then
                ctx.err("Quantity must be a positive number")
                return
            end
            
            -- Add minecraft: prefix if missing
            if not item:find(":") then
                item = "minecraft:" .. item
            end
            
            if isSmelt then
                -- Check if there's a smelting recipe that produces this item
                local input = furnaceManager.getSmeltInput(item)
                if not input then
                    ctx.err("No smelting recipe produces " .. item)
                    print("Use 'furnaces recipes' to see available smelting recipes")
                    return
                end
                
                furnaceConfig.setSmeltTarget(item, quantity)
                ctx.succ(string.format("Added smelt target: %s (target: %d)", item, quantity))
                print("  Input: " .. input:gsub("minecraft:", ""))
            else
                -- Check if recipe exists
                if not recipes.canCraft(item) then
                    -- Also check if it's a smelting output
                    local input = furnaceManager.getSmeltInput(item)
                    if input then
                        ctx.err("No crafting recipe found for " .. item)
                        print("  This can be smelted! Use: add " .. item:gsub("minecraft:", "") .. " " .. quantity .. " --smelt")
                        return
                    end
                    ctx.err("No recipe found for " .. item)
                    return
                end
                
                targets.set(item, quantity)
                ctx.succ(string.format("Added %s (target: %d)", item, quantity))
            end
        end,
        complete = function(args)
            if #args == 1 then
                -- Complete item names (handle empty string)
                local query = args[1] or ""
                if query == "" then return {} end
                -- Include both crafting recipes and smelting outputs
                local results = recipes.search(query)
                local completions = {}
                for _, r in ipairs(results) do
                    table.insert(completions, (r.output:gsub("minecraft:", "")))
                end
                -- Also add smelting outputs
                local smeltResults = furnaceManager.searchRecipes(query)
                for _, r in ipairs(smeltResults) do
                    local output = r.output:gsub("minecraft:", "")
                    -- Avoid duplicates
                    local found = false
                    for _, c in ipairs(completions) do
                        if c == output then found = true break end
                    end
                    if not found then
                        table.insert(completions, output)
                    end
                end
                return completions
            elseif #args == 3 then
                -- Complete flags
                local query = (args[3] or ""):lower()
                local smeltFlag = "--smelt"
                if query == "" or smeltFlag:find(query, 1, true) then
                    return {"--smelt"}
                end
            end
            return {}
        end
    },
    
    remove = {
        description = "Remove item from auto-craft or auto-smelt list",
        category = "queue",
        aliases = {"rm", "del"},
        execute = function(args, ctx)
            if #args < 1 then
                ctx.err("Usage: remove <item> [--smelt]")
                return
            end
            
            -- Check for --smelt flag
            local isSmelt = false
            local filteredArgs = {}
            for _, arg in ipairs(args) do
                if arg == "--smelt" or arg == "-s" then
                    isSmelt = true
                else
                    table.insert(filteredArgs, arg)
                end
            end
            
            local item = filteredArgs[1]
            if not item:find(":") then
                item = "minecraft:" .. item
            end
            
            if isSmelt then
                if not furnaceConfig.getSmeltTarget(item) then
                    ctx.err("Item not in smelt list: " .. item)
                    return
                end
                
                furnaceConfig.removeSmeltTarget(item)
                ctx.succ("Removed smelt target: " .. item)
            else
                if not targets.get(item) then
                    -- Check if it's in smelt targets
                    if furnaceConfig.getSmeltTarget(item) then
                        ctx.err("Item not in craft list: " .. item)
                        print("  This item is in the smelt list. Use: remove " .. item:gsub("minecraft:", "") .. " --smelt")
                        return
                    end
                    ctx.err("Item not in craft list: " .. item)
                    return
                end
                
                targets.remove(item)
                ctx.succ("Removed " .. item)
            end
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
                -- Also include smelt targets
                local smeltTargets = furnaceConfig.getAllSmeltTargets()
                for item in pairs(smeltTargets) do
                    if item:lower():find(query:lower(), 1, true) then
                        local display = item:gsub("minecraft:", "")
                        -- Avoid duplicates
                        local found = false
                        for _, c in ipairs(completions) do
                            if c == display then found = true break end
                        end
                        if not found then
                            table.insert(completions, display)
                        end
                    end
                end
                return completions
            elseif #args == 2 then
                -- Complete flags
                local query = (args[2] or ""):lower()
                local smeltFlag = "--smelt"
                if query == "" or smeltFlag:find(query, 1, true) then
                    return {"--smelt"}
                end
            end
            return {}
        end
    },
    
    list = {
        description = "List auto-craft and auto-smelt items",
        category = "queue",
        aliases = {"ls", "targets"},
        execute = function(args, ctx)
            local stock = storageManager.getAllStock()
            local craftTargets = targets.getWithStock(stock)
            local smeltTargets = furnaceConfig.getSmeltTargetsWithStock(stock)
            
            if #craftTargets == 0 and #smeltTargets == 0 then
                ctx.mess("No craft or smelt targets configured")
                return
            end
            
            local p = ctx.pager("=== Targets ===")
            
            if #craftTargets > 0 then
                p.setTextColor(colors.cyan)
                p.print("-- Craft Targets --")
                for _, target in ipairs(craftTargets) do
                    local item = target.item:gsub("minecraft:", "")
                    
                    if target.current >= target.target then
                        p.setTextColor(colors.lime)
                        p.write("+ ")
                    else
                        p.setTextColor(colors.orange)
                        p.write("* ")
                    end
                    
                    p.setTextColor(colors.white)
                    p.write(item .. " ")
                    p.setTextColor(colors.lightGray)
                    p.print(string.format("%d/%d", target.current, target.target))
                end
            end
            
            if #smeltTargets > 0 then
                if #craftTargets > 0 then
                    p.print("")
                end
                p.setTextColor(colors.cyan)
                p.print("-- Smelt Targets --")
                for _, target in ipairs(smeltTargets) do
                    local item = target.item:gsub("minecraft:", "")
                    local input = furnaceManager.getSmeltInput(target.item)
                    local inputDisplay = input and input:gsub("minecraft:", "") or "?"
                    
                    if target.current >= target.target then
                        p.setTextColor(colors.lime)
                        p.write("+ ")
                    else
                        p.setTextColor(colors.orange)
                        p.write("* ")
                    end
                    
                    p.setTextColor(colors.white)
                    p.write(item .. " ")
                    p.setTextColor(colors.lightGray)
                    p.print(string.format("%d/%d (from %s)", target.current, target.target, inputDisplay))
                end
            end
            p.show()
        end
    },
    
    request = {
        description = "Request a one-time craft/smelt (results go to storage)",
        category = "queue",
        aliases = {"req"},
        execute = function(args, ctx)
            local subCmd = args[1]
            
            -- Handle subcommands
            if subCmd == "list" or subCmd == "ls" then
                local requests = requestManager.getAllRequests()
                local active = {}
                local recent = {}
                
                for _, req in ipairs(requests) do
                    if req.status ~= requestManager.STATES.DELIVERED and
                       req.status ~= requestManager.STATES.FAILED and
                       req.status ~= requestManager.STATES.CANCELLED then
                        table.insert(active, req)
                    else
                        table.insert(recent, req)
                    end
                end
                
                if #active == 0 and #recent == 0 then
                    ctx.mess("No requests found")
                    return
                end
                
                local p = ctx.pager("=== Requests ===")
                
                if #active > 0 then
                    p.setTextColor(colors.cyan)
                    p.print("-- Active --")
                    for _, req in ipairs(active) do
                        local item = req.item:gsub("minecraft:", "")
                        local statusStr = requestManager.getStatusString(req)
                        
                        p.setTextColor(colors.yellow)
                        p.write(string.format("#%d ", req.id))
                        p.setTextColor(colors.white)
                        p.write(string.format("%dx %s ", req.quantity, item))
                        p.setTextColor(colors.lightGray)
                        p.print(string.format("-> %s [%s]", req.deliverTo, statusStr))
                    end
                end
                
                if #recent > 0 then
                    if #active > 0 then p.print("") end
                    p.setTextColor(colors.gray)
                    p.print("-- Recent --")
                    local shown = 0
                    for _, req in ipairs(recent) do
                        if shown >= 5 then break end
                        local item = req.item:gsub("minecraft:", "")
                        local statusStr = requestManager.getStatusString(req)
                        
                        p.setTextColor(colors.gray)
                        p.write(string.format("#%d ", req.id))
                        p.setTextColor(colors.lightGray)
                        p.print(string.format("%dx %s [%s]", req.quantity, item, statusStr))
                        shown = shown + 1
                    end
                end
                
                p.show()
                return
                
            elseif subCmd == "cancel" then
                local id = tonumber(args[2])
                if not id then
                    ctx.err("Usage: request cancel <id>")
                    return
                end
                
                if requestManager.cancelRequest(id) then
                    ctx.succ("Cancelled request #" .. id)
                else
                    ctx.err("Could not cancel request #" .. id)
                end
                return
                
            elseif subCmd == "status" then
                local id = tonumber(args[2])
                if not id then
                    ctx.err("Usage: request status <id>")
                    return
                end
                
                local req = requestManager.getRequest(id)
                if not req then
                    ctx.err("Request #" .. id .. " not found")
                    return
                end
                
                print("")
                ctx.mess("=== Request #" .. id .. " ===")
                print("  Item: " .. req.item:gsub("minecraft:", ""))
                print("  Quantity: " .. req.quantity)
                print("  Deliver to: " .. req.deliverTo)
                print("  Type: " .. (req.isSmelt and "Smelt" or "Craft"))
                print("  Status: " .. requestManager.getStatusString(req))
                print("  Produced: " .. (req.produced or 0))
                print("  Delivered: " .. (req.delivered or 0))
                
                -- Show job tree info if available
                if req.rootJobId then
                    local treeStatus = queueManager.getJobTreeStatus(req.rootJobId)
                    print("")
                    ctx.mess("--- Job Tree ---")
                    print(string.format("  Root Job: #%d", req.rootJobId))
                    print(string.format("  Total Jobs: %d", treeStatus.total))
                    print(string.format("  Completed: %d, Pending: %d, Waiting: %d", 
                        treeStatus.completed, treeStatus.pending, treeStatus.waiting))
                    if treeStatus.crafting > 0 or treeStatus.assigned > 0 then
                        print(string.format("  Active: %d (crafting: %d)", 
                            treeStatus.crafting + treeStatus.assigned, treeStatus.crafting))
                    end
                    if treeStatus.failed > 0 then
                        print(string.format("  Failed: %d", treeStatus.failed))
                    end
                    
                    -- Show items being crafted
                    if next(treeStatus.items) then
                        print("")
                        ctx.mess("--- Items ---")
                        for itemName, itemStatus in pairs(treeStatus.items) do
                            local shortName = itemName:gsub("minecraft:", "")
                            local status = itemStatus.pending > 0 
                                and string.format("%d/%d", itemStatus.done, itemStatus.total)
                                or "done"
                            print(string.format("  %s: %s", shortName, status))
                        end
                    end
                elseif req.jobIds and #req.jobIds > 0 then
                    print("  Jobs: " .. table.concat(req.jobIds, ", "))
                end
                return
                
            elseif subCmd == "help" then
                print("")
                ctx.mess("=== Request Commands ===")
                print("  request <item> <quantity> [--smelt]  - Create new request")
                print("  request list                         - List all requests")
                print("  request status <id>                  - View request details")
                print("  request cancel <id>                  - Cancel a request")
                return
            end
            
            -- Default: create a new request
            if #args < 2 then
                ctx.err("Usage: request <item> <quantity> [--smelt]")
                print("  Results will be stored in storage")
                print("  Use 'request help' for more commands")
                return
            end
            
            -- Check for --smelt flag
            local isSmelt = false
            local filteredArgs = {}
            for _, arg in ipairs(args) do
                if arg == "--smelt" or arg == "-s" then
                    isSmelt = true
                else
                    table.insert(filteredArgs, arg)
                end
            end
            
            local item = filteredArgs[1]
            local quantity = tonumber(filteredArgs[2])
            
            if not quantity or quantity <= 0 then
                ctx.err("Quantity must be a positive number")
                return
            end
            
            -- Add minecraft: prefix if missing
            if not item:find(":") then
                item = "minecraft:" .. item
            end
            
            -- Create the request (deliver to storage)
            local request, err = requestManager.createRequest(item, quantity, "storage", isSmelt)
            
            if not request then
                ctx.err(err or "Failed to create request")
                return
            end
            
            ctx.succ(string.format("Created request #%d: %dx %s", request.id, quantity, item:gsub("minecraft:", "")))
            if isSmelt then
                print("  Type: Smelt")
            end
            print("  Results will be stored in storage")
            print("  Use 'request status " .. request.id .. "' to check progress")
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"list", "status", "cancel", "help"}
                local matches = {}
                
                -- First check subcommands
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) then
                        table.insert(matches, opt)
                    end
                end
                
                -- Also complete item names
                local allRecipes = recipes.getAll()
                for output, _ in pairs(allRecipes) do
                    local shortName = output:gsub("minecraft:", "")
                    if shortName:find(query, 1, true) then
                        table.insert(matches, shortName)
                    end
                end
                
                return matches
            elseif #args == 2 then
                local firstArg = args[1]:lower()
                if firstArg == "status" or firstArg == "cancel" then
                    -- Complete with request IDs
                    local requests = requestManager.getActiveRequests()
                    local ids = {}
                    for _, req in ipairs(requests) do
                        table.insert(ids, tostring(req.id))
                    end
                    return ids
                end
            elseif #args == 3 then
                local query = (args[3] or ""):lower()
                if query:find("%-", 1, true) or query == "" then
                    return {"--smelt"}
                end
            end
            return {}
        end
    },
    
    force_queue = {
        description = "Force run processCraftTargets once",
        category = "queue",
        aliases = {"fq"},
        execute = function(args, ctx)
            local stock = storageManager.getAllStock()
            local needed = targets.getNeeded(stock)
            
            local beforeCount = #queueManager.getJobs()
            
            -- Create pager for output
            local p = ctx.pager("=== Force Queue Results ===")
            
            p.print("")
            p.print(string.format("Targets needing craft: %d", #needed))
            for i, target in ipairs(needed) do
                p.print(string.format("  %d. %s: need %d (have %d)", 
                    i, target.item:gsub("minecraft:", ""), target.needed, target.current))
            end
            p.print("")
            
            if #needed == 0 then
                p.setTextColor(colors.lightBlue)
                p.print("No targets need crafting")
                p.show()
                return
            end
            
            p.setTextColor(colors.lightBlue)
            p.print("Running processCraftTargets()...")
            p.setTextColor(colors.white)
            
            -- Call processCraftTargets
            processCraftTargets()
            
            -- Show results
            local allJobs = queueManager.getJobs()
            local afterCount = #allJobs
            local created = afterCount - beforeCount
            
            p.print("")
            if created > 0 then
                p.setTextColor(colors.green)
                p.print(string.format("Created %d new job(s), queue now has %d total", created, afterCount))
                p.setTextColor(colors.white)
                p.print("New jobs:")
                for i = math.max(1, #allJobs - created), #allJobs do
                    local job = allJobs[i]
                    p.print(string.format("  Job #%d: %dx %s (%s)", 
                        job.id, 
                        job.expectedOutput or 0,
                        (job.recipe and job.recipe.output or "?"):gsub("minecraft:", ""),
                        job.status))
                end
            else
                p.setTextColor(colors.yellow)
                p.print("No jobs were created")
                p.setTextColor(colors.white)
                p.print("This could mean:")
                p.print("  - Materials are missing")
                p.print("  - Jobs are already queued")
                p.print("  - Recipes are missing")
                p.print("Run 'why' for detailed diagnostics")
            end
            
            p.show()
        end
    },
    
    diagnose = {
        description = "Diagnose why targets are not being crafted/smelted",
        category = "queue",
        aliases = {"why", "diag"},
        execute = function(args, ctx)
            local stock = storageManager.getAllStock()
            local craftTargets = targets.getNeeded(stock)
            local smeltTargets = furnaceConfig.getNeededSmelt(stock)
            local craftingLib = require("lib.crafting")
            
            -- Get current job queue to check if items are already queued
            local allJobs = queueManager.getJobs()
            local queuedByItem = {}
            for _, job in ipairs(allJobs) do
                if job.recipe and job.recipe.output then
                    -- Include WAITING jobs too (matches processCraftTargets logic)
                    if job.status == "pending" or job.status == "waiting" or 
                       job.status == "assigned" or job.status == "crafting" then
                        local output = job.recipe.output
                        queuedByItem[output] = (queuedByItem[output] or 0) + (job.expectedOutput or 0)
                    end
                end
            end
            
            if #craftTargets == 0 and #smeltTargets == 0 then
                ctx.succ("All targets are satisfied!")
                return
            end
            
            local p = ctx.pager("=== Target Diagnostics ===")
            
            -- Analyze craft targets
            if #craftTargets > 0 then
                p.setTextColor(colors.cyan)
                p.print("-- Craft Target Issues --")
                p.print("")
                
                for _, target in ipairs(craftTargets) do
                    local item = target.item
                    local displayName = item:gsub("minecraft:", "")
                    local queued = queuedByItem[item] or 0
                    local stillNeeded = target.needed - queued
                    
                    p.setTextColor(colors.yellow)
                    p.print(displayName .. ":")
                    p.setTextColor(colors.lightGray)
                    p.print(string.format("  Target: %d | Have: %d | Need: %d", 
                        target.target, target.current, target.needed))
                    
                    if queued > 0 then
                        -- Show job status breakdown
                        local statusCounts = {pending=0, waiting=0, assigned=0, crafting=0}
                        for _, job in ipairs(allJobs) do
                            if job.recipe and job.recipe.output == item then
                                statusCounts[job.status] = (statusCounts[job.status] or 0) + 1
                            end
                        end
                        
                        p.setTextColor(colors.lime)
                        p.print(string.format("  Queued: %d items", queued))
                        p.setTextColor(colors.gray)
                        local statuses = {}
                        if statusCounts.waiting > 0 then table.insert(statuses, statusCounts.waiting .. " waiting") end
                        if statusCounts.pending > 0 then table.insert(statuses, statusCounts.pending .. " pending") end
                        if statusCounts.assigned > 0 then table.insert(statuses, statusCounts.assigned .. " assigned") end
                        if statusCounts.crafting > 0 then table.insert(statuses, statusCounts.crafting .. " crafting") end
                        if #statuses > 0 then
                            p.print("    (" .. table.concat(statuses, ", ") .. ")")
                        end
                        
                        if stillNeeded <= 0 then
                            p.setTextColor(colors.green)
                            p.print("  Status: Sufficient jobs queued")
                            p.print("")
                            goto nextCraftTarget
                        end
                    end
                    
                    -- Check if recipe exists
                    local recipe = recipes.getRecipeFor(item)
                    if not recipe then
                        p.setTextColor(colors.red)
                        p.print("  ERROR: No recipe found!")
                        p.setTextColor(colors.gray)
                        p.print("  Use 'recipe " .. displayName .. "' to check recipe status")
                        p.print("")
                        goto nextCraftTarget
                    end
                    
                    -- Check materials
                    local hasAll, missing = craftingLib.hasMaterials(recipe, stock, stillNeeded)
                    if hasAll then
                        -- Check if crafters are available
                        local crafterStats = crafterManager.getStats()
                        if crafterStats.online == 0 then
                            p.setTextColor(colors.orange)
                            p.print("  BLOCKED: No crafters online!")
                        elseif crafterStats.idle == 0 then
                            p.setTextColor(colors.orange)
                            p.print("  WAITING: All crafters busy")
                        else
                            p.setTextColor(colors.lime)
                            p.print("  READY: Materials available, should craft soon")
                        end
                    else
                        p.setTextColor(colors.red)
                        p.print("  MISSING MATERIALS:")
                        for _, m in ipairs(missing) do
                            local matName = m.item:gsub("minecraft:", "")
                            p.setTextColor(colors.orange)
                            p.write("    - " .. matName .. ": ")
                            p.setTextColor(colors.white)
                            p.print(string.format("need %d, have %d (short %d)", 
                                m.needed, m.have, m.short))
                            
                            -- Check if the missing material can be crafted
                            local matRecipe = recipes.getRecipeFor(m.item)
                            if matRecipe then
                                p.setTextColor(colors.gray)
                                p.print("      (can be crafted - add as target?)")
                            elseif furnaceManager.getSmeltInput(m.item) then
                                p.setTextColor(colors.gray)
                                p.print("      (can be smelted - add as smelt target?)")
                            end
                        end
                    end
                    p.print("")
                    
                    ::nextCraftTarget::
                end
            end
            
            -- Analyze smelt targets
            if #smeltTargets > 0 then
                if #craftTargets > 0 then
                    p.print("")
                end
                p.setTextColor(colors.cyan)
                p.print("-- Smelt Target Issues --")
                p.print("")
                
                local enabledFurnaces = furnaceConfig.getEnabled()
                local fuelStock = furnaceManager.getFuelSummary(stock)
                
                for _, target in ipairs(smeltTargets) do
                    local item = target.item
                    local displayName = item:gsub("minecraft:", "")
                    
                    p.setTextColor(colors.yellow)
                    p.print(displayName .. ":")
                    p.setTextColor(colors.lightGray)
                    p.print(string.format("  Target: %d | Have: %d | Need: %d", 
                        target.target, target.current, target.needed))
                    
                    -- Check furnaces
                    if #enabledFurnaces == 0 then
                        p.setTextColor(colors.red)
                        p.print("  ERROR: No furnaces configured!")
                        p.setTextColor(colors.gray)
                        p.print("  Use 'furnaces add' to add furnaces")
                        p.print("")
                        goto nextSmeltTarget
                    end
                    
                    -- Check input material
                    local input = furnaceManager.getSmeltInput(item)
                    if not input then
                        p.setTextColor(colors.red)
                        p.print("  ERROR: No smelting recipe found!")
                        p.print("")
                        goto nextSmeltTarget
                    end
                    
                    local inputStock = stock[input] or 0
                    local inputName = input:gsub("minecraft:", "")
                    if inputStock < target.needed then
                        p.setTextColor(colors.red)
                        p.print("  MISSING INPUT:")
                        p.setTextColor(colors.orange)
                        p.print(string.format("    - %s: need %d, have %d", 
                            inputName, target.needed, inputStock))
                        
                        -- Check if input can be crafted/smelted
                        local inputRecipe = recipes.getRecipeFor(input)
                        if inputRecipe then
                            p.setTextColor(colors.gray)
                            p.print("      (can be crafted - add as craft target?)")
                        end
                    else
                        p.setTextColor(colors.lime)
                        p.print(string.format("  Input OK: %s (%d available)", inputName, inputStock))
                    end
                    
                    -- Check fuel
                    if fuelStock.totalSmeltCapacity < target.needed then
                        p.setTextColor(colors.orange)
                        p.print(string.format("  LOW FUEL: Can smelt %d items, need %d", 
                            fuelStock.totalSmeltCapacity, target.needed))
                    else
                        p.setTextColor(colors.lime)
                        p.print(string.format("  Fuel OK: Can smelt %d items", fuelStock.totalSmeltCapacity))
                    end
                    p.print("")
                    
                    ::nextSmeltTarget::
                end
            end
            
            p.show()
        end
    },
    
    scan = {
        description = "Force inventory rescan",
        category = "storage",
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
        category = "storage",
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
        category = "storage",
        aliases = {"w", "get"},
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
        description = "Deposit items from player to storage (supports wildcards: cobble*, *dirt)",
        category = "storage",
        aliases = {"d", "put"},
        execute = function(args, ctx)
            if not storageManager.hasManipulator() then
                ctx.err("No manipulator available for player transfers")
                return
            end
            
            -- Parse args: deposit [item1] [item2] ... [--all] [--no-exclude]
            local items = {}
            local depositAll = false
            local useExcludes = true
            
            for _, arg in ipairs(args) do
                if arg == "--all" or arg == "-a" then
                    depositAll = true
                elseif arg == "--no-exclude" or arg == "-n" then
                    useExcludes = false
                else
                    -- Treat as item filter
                    local item = arg
                    if not item:find(":") then
                        item = "minecraft:" .. item
                    end
                    table.insert(items, item)
                end
            end
            
            -- Get excludes from settings
            local excludes = nil
            if useExcludes and (#items == 0 or depositAll) then
                excludes = settings.getDepositExcludes()
            end
            
            local itemFilter = nil
            if #items > 0 and not depositAll then
                itemFilter = #items == 1 and items[1] or items
            end
            
            local deposited, err = storageManager.depositFromPlayer("player", itemFilter, nil, excludes)
            if deposited > 0 then
                if itemFilter then
                    if type(itemFilter) == "table" then
                        ctx.succ(string.format("Deposited %d items (filtered) from player", deposited))
                    else
                        ctx.succ(string.format("Deposited %d %s from player", deposited, itemFilter:gsub("minecraft:", "")))
                    end
                else
                    ctx.succ(string.format("Deposited %d items from player", deposited))
                    if useExcludes and excludes and #excludes > 0 then
                        ctx.mess(string.format("(excluded %d item types - use --no-exclude to include all)", #excludes))
                    end
                end
            else
                ctx.mess("Nothing to deposit" .. (err and (": " .. err) or ""))
            end
        end,
        complete = function(args)
            local lastArg = args[#args] or ""
            if lastArg:sub(1, 1) == "-" then
                return {"--all", "--no-exclude"}
            end
            return {}
        end
    },
    
    excludes = {
        description = "Manage deposit excludes (items kept when depositing)",
        category = "storage",
        aliases = {"exclude"},
        execute = function(args, ctx)
            local subCmd = args[1]
            
            if not subCmd or subCmd == "list" then
                local excludes = settings.getDepositExcludes()
                if #excludes == 0 then
                    ctx.mess("No deposit excludes configured")
                    return
                end
                
                local p = ctx.pager("=== Deposit Excludes (" .. #excludes .. ") ===")
                p.setTextColor(colors.lightGray)
                p.print("These items are kept when depositing all:")
                p.print("")
                for _, item in ipairs(excludes) do
                    p.setTextColor(colors.white)
                    p.print("  " .. item:gsub("minecraft:", ""))
                end
                p.print("")
                p.setTextColor(colors.lightBlue)
                p.print("Use 'excludes add <item>' to add")
                p.print("Use 'excludes remove <item>' to remove")
                p.print("Use 'excludes reset' to restore defaults")
                p.show()
                return
            end
            
            if subCmd == "add" then
                local item = args[2]
                if not item then
                    ctx.err("Usage: excludes add <item>")
                    return
                end
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                settings.addDepositExclude(item)
                ctx.succ("Added to excludes: " .. item:gsub("minecraft:", ""))
                return
            end
            
            if subCmd == "remove" or subCmd == "rm" then
                local item = args[2]
                if not item then
                    ctx.err("Usage: excludes remove <item>")
                    return
                end
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                settings.removeDepositExclude(item)
                ctx.succ("Removed from excludes: " .. item:gsub("minecraft:", ""))
                return
            end
            
            if subCmd == "reset" then
                settings.set("depositExcludes", nil)  -- Clear to use defaults
                ctx.succ("Reset excludes to defaults")
                return
            end
            
            ctx.err("Unknown subcommand: " .. subCmd)
            ctx.mess("Available: list, add, remove, reset")
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"list", "add", "remove", "reset"}
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
    
    history = {
        description = "View job history (completed/failed)",
        category = "queue",
        aliases = {"hist"},
        execute = function(args, ctx)
            local historyType = args[1]  -- "completed", "failed", or nil for both
            
            local history = queueManager.getHistory(historyType)
            
            local p = ctx.pager("=== Job History ===")
            
            if historyType == "completed" or not historyType then
                local completed = historyType == "completed" and history or history.completed
                p.setTextColor(colors.lightBlue)
                p.print("Completed Jobs:")
                if #completed == 0 then
                    p.setTextColor(colors.white)
                    p.print("  No completed jobs")
                else
                    for _, job in ipairs(completed) do
                        local output = job.recipe and job.recipe.output or "unknown"
                        output = output:gsub("minecraft:", "")
                        p.setTextColor(colors.lime)
                        p.write("  #" .. job.id .. " ")
                        p.setTextColor(colors.white)
                        p.print(string.format("%dx %s", job.actualOutput or 0, output))
                    end
                end
                p.print("")
            end
            
            if historyType == "failed" or not historyType then
                local failed = historyType == "failed" and history or history.failed
                p.setTextColor(colors.lightBlue)
                p.print("Failed Jobs:")
                if #failed == 0 then
                    p.setTextColor(colors.white)
                    p.print("  No failed jobs")
                else
                    for _, job in ipairs(failed) do
                        local output = job.recipe and job.recipe.output or "unknown"
                        output = output:gsub("minecraft:", "")
                        p.setTextColor(colors.red)
                        p.write("  #" .. job.id .. " ")
                        p.setTextColor(colors.white)
                        p.write(output .. " - ")
                        p.setTextColor(colors.orange)
                        p.print(job.failReason or "Unknown")
                    end
                end
            end
            p.show()
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
        category = "crafters",
        execute = function(args, ctx)
            local allCrafters = crafterManager.getCrafters()
            
            if #allCrafters == 0 then
                ctx.mess("No crafters registered")
                return
            end
            
            local p = ctx.pager("=== Crafters (" .. #allCrafters .. ") ===")
            for _, crafter in ipairs(allCrafters) do
                local statusColor = colors.red
                if crafter.isOnline then
                    if crafter.status == "idle" then
                        statusColor = colors.lime
                    else
                        statusColor = colors.orange
                    end
                end
                
                p.setTextColor(colors.lightGray)
                p.write(string.format("#%d ", crafter.id))
                p.setTextColor(colors.white)
                p.write(crafter.label .. " ")
                p.setTextColor(statusColor)
                p.print("[" .. crafter.status .. "]")
            end
            p.show()
        end
    },
    
    workers = {
        description = "List and manage worker turtles",
        category = "workers",
        execute = function(args, ctx)
            local subCmd = args[1]
            
            if subCmd == "tasks" then
                -- List all worker tasks
                local tasks = workerConfig.getAllTasks()
                local taskCount = 0
                for _ in pairs(tasks) do taskCount = taskCount + 1 end
                
                if taskCount == 0 then
                    ctx.mess("No worker tasks configured")
                    print("")
                    ctx.mess("Use 'workers add <type> <item> [threshold] [target]' to add a task")
                    return
                end
                
                local stock = storageManager.getAllStock()
                local p = ctx.pager("=== Worker Tasks (" .. taskCount .. ") ===")
                
                for id, task in pairs(tasks) do
                    local currentStock = stock[task.item] or 0
                    local statusColor = colors.lime
                    local statusText = "OK"
                    
                    if currentStock < task.stockThreshold then
                        statusColor = colors.orange
                        statusText = "NEEDS WORK"
                    end
                    
                    if not task.enabled then
                        statusColor = colors.gray
                        statusText = "DISABLED"
                    end
                    
                    local typeInfo = workerConfig.TASK_TYPES[task.type]
                    local typeLabel = typeInfo and typeInfo.label or task.type
                    local dir = task.config and (task.config.breakDirection or task.config.farmDirection) or "front"
                    
                    p.setTextColor(colors.white)
                    p.write(id .. " ")
                    p.setTextColor(colors.lightGray)
                    p.write("(" .. typeLabel .. ") ")
                    p.setTextColor(colors.cyan)
                    p.write((task.item or "?"):gsub("minecraft:", "") .. " ")
                    p.setTextColor(colors.yellow)
                    p.write("[" .. dir .. "] ")
                    p.setTextColor(colors.lightGray)
                    p.write(string.format("%d/%d ", currentStock, task.stockThreshold))
                    p.setTextColor(statusColor)
                    p.print(statusText)
                end
                p.show()
                
            elseif subCmd == "add" then
                -- Add a new worker task
                local taskType = args[2]
                local item = args[3]
                local threshold = tonumber(args[4])
                local target = tonumber(args[5])
                local direction = args[6] or "front"
                
                if not taskType then
                    ctx.err("Usage: workers add <type> <item> [threshold] [target] [direction]")
                    print("")
                    print("Task types:")
                    for typeName, typeInfo in pairs(workerConfig.TASK_TYPES) do
                        print("  " .. typeName .. " - " .. typeInfo.description)
                    end
                    print("")
                    print("Directions: front, up, down")
                    return
                end
                
                -- Resolve type (handles legacy names)
                local resolvedType, typeInfo = workerConfig.resolveTaskType(taskType)
                if not typeInfo then
                    ctx.err("Unknown task type: " .. taskType)
                    return
                end
                
                -- Validate direction
                if direction ~= "front" and direction ~= "up" and direction ~= "down" then
                    ctx.err("Invalid direction: " .. direction .. " (use: front, up, down)")
                    return
                end
                
                -- For cobblegen, item is preset
                if resolvedType == "cobblegen" then
                    item = "minecraft:cobblestone"
                elseif resolvedType == "farming" then
                    -- Validate crop type
                    if not item then
                        ctx.err("Crop required for farming task (wheat, carrot, potato, beetroot, nether_wart)")
                        return
                    end
                    if not item:find(":") then
                        item = "minecraft:" .. item
                    end
                    local validCrops = typeInfo.validCrops
                    if not validCrops[item] then
                        ctx.err("Invalid crop: " .. item .. " (use: wheat, carrot, potato, beetroot, nether_wart)")
                        return
                    end
                elseif not item then
                    ctx.err("Item required for task type: " .. resolvedType)
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                -- Generate clean task ID
                local taskId = workerConfig.generateTaskId(resolvedType, item)
                
                -- Handle duplicate IDs by adding a number suffix
                local existingTasks = workerConfig.getAllTasks()
                if existingTasks[taskId] then
                    local counter = 2
                    while existingTasks[taskId .. "_" .. counter] do
                        counter = counter + 1
                    end
                    taskId = taskId .. "_" .. counter
                end
                
                local taskCfg = {
                    item = item,
                    stockThreshold = threshold or typeInfo.defaultThreshold,
                    stockTarget = target or typeInfo.defaultTarget,
                    config = {
                        breakDirection = direction,
                    },
                }
                
                -- For concrete, set the input item
                if resolvedType == "concrete" then
                    taskCfg.config.inputItem = item:gsub("_concrete$", "_concrete_powder")
                end
                
                -- For farming, set farm direction and seed info
                if resolvedType == "farming" then
                    local cropInfo = typeInfo.validCrops[item]
                    taskCfg.config.farmDirection = direction
                    taskCfg.config.seedItem = cropInfo.seed
                    taskCfg.config.breakDirection = nil  -- Not used for crop farming
                end
                
                if workerConfig.setTask(taskId, resolvedType, taskCfg) then
                    ctx.succ(string.format("Added task '%s': %s (dir: %s)", taskId, item:gsub("minecraft:", ""), direction))
                else
                    ctx.err("Failed to add task")
                end
                
            elseif subCmd == "edit" then
                -- Interactive FormUI editor for a worker task
                local taskId = args[2]
                
                if not taskId then
                    -- Show a select form to pick a task
                    local tasks = workerConfig.getAllTasks()
                    local taskIds = {}
                    local taskLabels = {}
                    for id, task in pairs(tasks) do
                        taskIds[#taskIds + 1] = id
                        local typeInfo = workerConfig.TASK_TYPES[task.type]
                        local typeLabel = typeInfo and typeInfo.label or task.type
                        taskLabels[#taskLabels + 1] = id .. " (" .. typeLabel .. " - " .. (task.item or "?"):gsub("minecraft:", "") .. ")"
                    end
                    
                    if #taskIds == 0 then
                        ctx.err("No worker tasks configured")
                        ctx.mess("Use 'workers add' to create a task first")
                        return
                    end
                    
                    local selectForm = FormUI.new("Select Task to Edit")
                    local taskField = selectForm:select("Task", taskLabels, 1)
                    selectForm:addSubmitCancel()
                    
                    local selectResult = selectForm:run()
                    if not selectResult then
                        ctx.mess("Cancelled")
                        return
                    end
                    
                    -- Find selected task ID from label
                    local selectedLabel = taskField()
                    for i, label in ipairs(taskLabels) do
                        if label == selectedLabel then
                            taskId = taskIds[i]
                            break
                        end
                    end
                end
                
                local task = workerConfig.getTask(taskId)
                if not task then
                    ctx.err("Unknown task: " .. taskId)
                    return
                end
                
                local typeInfo = workerConfig.TASK_TYPES[task.type]
                local typeLabel = typeInfo and typeInfo.label or task.type
                local isFarming = task.type == "farming"
                local isConcrete = task.type == "concrete"
                
                -- Build the form
                local form = FormUI.new("Edit Task: " .. taskId)
                form:label("Type: " .. typeLabel)
                
                local itemField = form:text("Item", (task.item or ""):gsub("minecraft:", ""))
                local thresholdField = form:number("Threshold", task.stockThreshold or 64)
                local targetField = form:number("Target", task.stockTarget or 256)
                
                -- Direction field
                local dirOptions = {"front", "up", "down"}
                local currentDir = task.config and (task.config.breakDirection or task.config.farmDirection) or "front"
                local dirDefault = 1
                for i, d in ipairs(dirOptions) do
                    if d == currentDir then dirDefault = i break end
                end
                local dirField = form:select(isFarming and "Farm Direction" or "Break Direction", dirOptions, dirDefault)
                
                -- Input item for concrete
                local inputField
                if isConcrete then
                    inputField = form:text("Input Item", (task.config.inputItem or ""):gsub("minecraft:", ""))
                end
                
                local enabledField = form:checkbox("Enabled", task.enabled ~= false)
                local priorityField = form:number("Priority", task.priority or 0)
                
                form:addSubmitCancel()
                
                local result = form:run()
                if not result then
                    ctx.mess("Cancelled")
                    return
                end
                
                -- Apply changes
                local newItem = itemField()
                if not newItem:find(":") then
                    newItem = "minecraft:" .. newItem
                end
                
                local newDir = dirField()
                
                task.item = newItem
                task.stockThreshold = thresholdField()
                task.stockTarget = targetField()
                task.enabled = enabledField()
                task.priority = priorityField()
                
                if isFarming then
                    task.config.farmDirection = newDir
                else
                    task.config.breakDirection = newDir
                end
                
                if isConcrete and inputField then
                    local newInput = inputField()
                    if not newInput:find(":") then
                        newInput = "minecraft:" .. newInput
                    end
                    task.config.inputItem = newInput
                end
                
                workerConfig.setTask(taskId, task.type, task)
                ctx.succ("Updated task: " .. taskId)
                print("  Item: " .. task.item:gsub("minecraft:", ""))
                print("  Threshold: " .. task.stockThreshold .. " / Target: " .. task.stockTarget)
                print("  Direction: " .. (task.config.breakDirection or task.config.farmDirection or "front"))
                print("  Enabled: " .. tostring(task.enabled))
                
            elseif subCmd == "remove" then
                local taskId = args[2]
                if not taskId then
                    ctx.err("Usage: workers remove <taskId>")
                    return
                end
                
                workerConfig.removeTask(taskId)
                ctx.succ("Removed task: " .. taskId)
                
            elseif subCmd == "enable" or subCmd == "disable" then
                local taskId = args[2]
                if not taskId then
                    ctx.err("Usage: workers " .. subCmd .. " <taskId>")
                    return
                end
                
                workerConfig.setTaskEnabled(taskId, subCmd == "enable")
                ctx.succ((subCmd == "enable" and "Enabled" or "Disabled") .. " task: " .. taskId)
                
            elseif subCmd == "label" then
                -- Set worker label
                local workerIdStr = args[2]
                local newLabel = args[3]
                
                if not workerIdStr or not newLabel then
                    ctx.err("Usage: workers label <workerId> <name>")
                    return
                end
                
                local workerId = tonumber(workerIdStr)
                if not workerId then
                    ctx.err("Worker ID must be a number")
                    return
                end
                
                -- Collect remaining args as label (allows spaces)
                local labelParts = {}
                for i = 3, #args do
                    labelParts[#labelParts + 1] = args[i]
                end
                newLabel = table.concat(labelParts, " ")
                
                workerConfig.registerWorker(workerId, newLabel)
                local liveWorker = workerManager.getWorker(workerId)
                if liveWorker then
                    liveWorker.label = newLabel
                end
                ctx.succ("Set worker #" .. workerId .. " label to '" .. newLabel .. "'")
                
            elseif subCmd == "config" then
                -- Interactive FormUI editor for a worker
                local workerIdStr = args[2]
                
                if not workerIdStr then
                    -- Show a select form to pick a worker
                    local allWorkers = workerManager.getWorkers()
                    if #allWorkers == 0 then
                        ctx.err("No workers registered")
                        return
                    end
                    
                    local workerNames = {}
                    for _, w in ipairs(allWorkers) do
                        workerNames[#workerNames + 1] = string.format("#%d %s", w.id, w.label)
                    end
                    
                    local selectForm = FormUI.new("Select Worker to Edit")
                    local workerField = selectForm:select("Worker", workerNames, 1)
                    selectForm:addSubmitCancel()
                    
                    local selectResult = selectForm:run()
                    if not selectResult then
                        ctx.mess("Cancelled")
                        return
                    end
                    
                    -- Select returns the option string like "#5 Worker 5", extract the ID
                    local selectedStr = workerField()
                    workerIdStr = selectedStr:match("#(%d+)")
                end
                
                local workerId = tonumber(workerIdStr)
                if not workerId then
                    ctx.err("Worker ID must be a number")
                    return
                end
                
                local workerData = workerConfig.getWorker(workerId)
                if not workerData then
                    ctx.err("Worker #" .. workerId .. " not found")
                    return
                end
                
                -- Build task type options list and default selections
                local taskTypeNames = {}
                local taskTypeLabels = {}
                for name, info in pairs(workerConfig.TASK_TYPES) do
                    taskTypeNames[#taskTypeNames + 1] = name
                end
                table.sort(taskTypeNames)
                
                for _, name in ipairs(taskTypeNames) do
                    local info = workerConfig.TASK_TYPES[name]
                    taskTypeLabels[#taskTypeLabels + 1] = name .. " (" .. info.label .. ")"
                end
                
                -- Determine which capabilities are currently selected
                local currentCaps = workerData.capabilities or {}
                local currentCapSet = {}
                for _, cap in ipairs(currentCaps) do
                    currentCapSet[cap] = true
                end
                
                local defaultIndices = {}
                for i, name in ipairs(taskTypeNames) do
                    if currentCapSet[name] then
                        defaultIndices[#defaultIndices + 1] = i
                    end
                end
                
                -- Build the form
                local form = FormUI.new("Edit Worker #" .. workerId)
                form:label("Worker ID: " .. workerId)
                local labelField = form:text("Label", workerData.label or ("Worker " .. workerId))
                local capsField = form:multiselect("Capabilities", taskTypeLabels, defaultIndices)
                -- Allow selecting none (worker just won't get tasks)
                form.fields[#form.fields].validate = nil
                form:addSubmitCancel()
                
                local result = form:run()
                if not result then
                    ctx.mess("Cancelled")
                    return
                end
                
                -- Apply label
                local newLabel = labelField()
                if newLabel and newLabel ~= "" then
                    workerConfig.registerWorker(workerId, newLabel)
                    local liveWorker = workerManager.getWorker(workerId)
                    if liveWorker then
                        liveWorker.label = newLabel
                    end
                end
                
                -- Apply capabilities from multiselect
                -- capsField() returns an array of selected label strings
                local selectedLabels = capsField()
                local newCaps = {}
                
                -- Map selected label strings back to task type names
                local labelToType = {}
                for i, name in ipairs(taskTypeNames) do
                    labelToType[taskTypeLabels[i]] = name
                end
                
                for _, label in ipairs(selectedLabels) do
                    local typeName = labelToType[label]
                    if typeName then
                        newCaps[#newCaps + 1] = typeName
                    end
                end
                
                workerConfig.setCapabilities(workerId, newCaps)
                local liveWorker = workerManager.getWorker(workerId)
                if liveWorker then
                    liveWorker.capabilities = newCaps
                    liveWorker.label = newLabel
                end
                
                -- Show summary
                ctx.succ("Updated worker #" .. workerId)
                print("  Label: " .. newLabel)
                if #newCaps > 0 then
                    local capDisplays = {}
                    for _, cap in ipairs(newCaps) do
                        local info = workerConfig.TASK_TYPES[cap]
                        capDisplays[#capDisplays + 1] = info and info.label or cap
                    end
                    print("  Capabilities: " .. table.concat(capDisplays, ", "))
                else
                    print("  Capabilities: none (will not receive tasks)")
                end
                
            else
                -- Default: list workers
                local allWorkers = workerManager.getWorkers()
                
                if #allWorkers == 0 then
                    ctx.mess("No workers registered")
                    print("")
                    ctx.mess("Workers will auto-register when they connect.")
                    ctx.mess("Use 'workers tasks' to view/manage worker tasks.")
                    return
                end
                
                local p = ctx.pager("=== Workers (" .. #allWorkers .. ") ===")
                local now = os.epoch("utc")
                
                for _, worker in ipairs(allWorkers) do
                    local statusColor = colors.red
                    if worker.isOnline then
                        if worker.status == "idle" then
                            statusColor = colors.lime
                        else
                            statusColor = colors.orange
                        end
                    end
                    
                    -- First line: ID, label, status
                    p.setTextColor(colors.lightGray)
                    p.write(string.format("#%d ", worker.id))
                    p.setTextColor(colors.white)
                    p.write(worker.label .. " ")
                    p.setTextColor(statusColor)
                    p.write("[" .. worker.status .. "]")
                    
                    if worker.taskId then
                        p.setTextColor(colors.cyan)
                        p.write(" (" .. worker.taskId .. ")")
                    end
                    p.print("")
                    
                    -- Capabilities line
                    local caps = worker.capabilities or {}
                    if #caps > 0 then
                        p.setTextColor(colors.gray)
                        p.write("     Can do: ")
                        p.setTextColor(colors.lightGray)
                        local capLabels = {}
                        for _, cap in ipairs(caps) do
                            local typeInfo = workerConfig.TASK_TYPES[cap]
                            capLabels[#capLabels + 1] = typeInfo and typeInfo.label or cap
                        end
                        p.print(table.concat(capLabels, ", "))
                    else
                        p.setTextColor(colors.red)
                        p.print("     No capabilities (use 'workers config " .. worker.id .. "')")
                    end
                    
                    -- Progress line (if working) or stats
                    p.setTextColor(colors.gray)
                    if worker.status == "working" and worker.progress then
                        local prog = worker.progress
                        local percent = prog.target > 0 and math.floor((prog.current / prog.target) * 100) or 0
                        local elapsed = prog.startTime > 0 and ((now - prog.startTime) / 1000) or 0
                        local rate = elapsed > 0 and (prog.current / elapsed) or 0
                        local eta = rate > 0 and ((prog.target - prog.current) / rate) or 0
                        
                        p.write("     Progress: ")
                        p.setTextColor(colors.yellow)
                        p.write(string.format("%d/%d (%d%%)", prog.current, prog.target, percent))
                        if rate > 0 then
                            p.setTextColor(colors.gray)
                            p.write(string.format(" | %.1f/s", rate))
                            if eta > 0 and eta < 3600 then
                                p.write(string.format(" | ETA: %ds", math.ceil(eta)))
                            end
                        end
                        p.print("")
                    elseif worker.stats then
                        local st = worker.stats
                        if st.sessionProduced and st.sessionProduced > 0 then
                            p.write("     Session: ")
                            p.setTextColor(colors.lightGray)
                            p.write(tostring(st.sessionProduced))
                            if st.lastProduced and st.lastProduced > 0 then
                                p.setTextColor(colors.gray)
                                p.write(" (last batch: " .. st.lastProduced .. ")")
                            end
                            p.print("")
                        end
                    end
                    
                    -- Show last seen for offline workers
                    if not worker.isOnline and worker.lastSeen > 0 then
                        local age = (now - worker.lastSeen) / 1000
                        p.setTextColor(colors.gray)
                        if age < 60 then
                            p.print(string.format("     Last seen: %ds ago", math.floor(age)))
                        elseif age < 3600 then
                            p.print(string.format("     Last seen: %dm ago", math.floor(age / 60)))
                        else
                            p.print(string.format("     Last seen: %.1fh ago", age / 3600))
                        end
                    end
                end
                p.print("")
                p.setTextColor(colors.lightBlue)
                p.print("Subcommands: tasks, add, edit, remove, enable, disable, config, cap, label")
                p.print("Use 'workers edit [taskId]' to edit a task, 'workers config [id]' for worker setup")
                p.show()
            end
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"tasks", "add", "edit", "remove", "enable", "disable", "config", "label"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) == 1 then
                        table.insert(matches, opt)
                    end
                end
                return matches
            elseif #args == 2 and args[1] == "add" then
                local query = (args[2] or ""):lower()
                local matches = {}
                for typeName, _ in pairs(workerConfig.TASK_TYPES) do
                    if typeName:find(query, 1, true) == 1 then
                        table.insert(matches, typeName)
                    end
                end
                return matches
            elseif #args == 2 and (args[1] == "edit" or args[1] == "remove" or args[1] == "enable" or args[1] == "disable") then
                -- Complete task IDs
                local query = (args[2] or ""):lower()
                local tasks = workerConfig.getAllTasks()
                local matches = {}
                for taskId, _ in pairs(tasks) do
                    if taskId:lower():find(query, 1, true) == 1 then
                        table.insert(matches, taskId)
                    end
                end
                return matches
            elseif #args == 2 and (args[1] == "config" or args[1] == "label") then
                -- Complete worker IDs
                local query = (args[2] or ""):lower()
                local allWorkers = workerManager.getWorkers()
                local matches = {}
                for _, w in ipairs(allWorkers) do
                    local idStr = tostring(w.id)
                    if idStr:find(query, 1, true) == 1 then
                        table.insert(matches, idStr)
                    end
                end
                return matches
            end
            return {}
        end
    },
    
    recipes = {
        description = "Recipe management - search, view, preferences, custom recipes",
        category = "recipes",
        aliases = {"recipe", "rp"},
        execute = function(args, ctx)
            local recipePrefs = require("config.recipes")
            local recipeOverrides = require("config.recipeoverrides")
            local subCmd = args[1]
            
            -- No args or search term: search recipes
            if not subCmd then
                -- Show help overview
                print("")
                ctx.mess("=== Recipe Management ===")
                term.setTextColor(colors.lightGray)
                print("  recipes <search>        - Search for recipes by name")
                print("  recipes view <item>     - View recipe details & variants")
                print("  recipes prefs           - Open recipe preferences menu")
                print("  recipes custom          - Open custom recipe builder")
                print("  recipes help            - Show all commands")
                term.setTextColor(colors.white)
                return
            end
            
            -- Check if it's a subcommand or a search query
            local subCommands = {"help", "view", "show", "prefs", "preferences", "prefer", 
                                 "enable", "disable", "clear", "clearall", "custom", 
                                 "add", "list", "status"}
            local isSubCmd = false
            for _, cmd in ipairs(subCommands) do
                if subCmd == cmd then
                    isSubCmd = true
                    break
                end
            end
            
            -- If not a subcommand, treat as search
            if not isSubCmd then
                local query = table.concat(args, " ")
                local results = recipes.search(query)
                
                if #results == 0 then
                    ctx.mess("No recipes found for: " .. query)
                    return
                end
                
                local p = ctx.pager("=== Recipes (" .. #results .. " found) ===")
                for _, r in ipairs(results) do
                    local output = r.output:gsub("minecraft:", "")
                    p.print("  " .. output)
                end
                p.print("")
                p.setTextColor(colors.lightGray)
                p.print("Use 'recipes view <item>' for details")
                p.show()
                return
            end
            
            -- Help command
            if subCmd == "help" then
                print("")
                ctx.mess("=== Recipe Commands ===")
                term.setTextColor(colors.white)
                print("")
                print("SEARCH & VIEW:")
                term.setTextColor(colors.lightGray)
                print("  recipes <search>          - Search recipes by name")
                print("  recipes view <item>       - View recipe details & all variants")
                print("  recipes list prefs        - List items with custom preferences")
                print("  recipes list custom       - List custom recipes")
                term.setTextColor(colors.white)
                print("")
                print("PREFERENCES (choose which variant to use):")
                term.setTextColor(colors.lightGray)
                print("  recipes prefs             - Open interactive preferences menu")
                print("  recipes prefer <item> <#> - Set preferred recipe variant")
                print("  recipes enable <item> <#> - Enable a recipe variant")
                print("  recipes disable <item> <#> - Disable a recipe variant")
                print("  recipes clear <item>      - Clear preferences for an item")
                print("  recipes clearall prefs    - Clear ALL recipe preferences")
                term.setTextColor(colors.white)
                print("")
                print("CUSTOM RECIPES (add your own):")
                term.setTextColor(colors.lightGray)
                print("  recipes custom            - Open custom recipe builder")
                print("  recipes add               - Quick-add a custom recipe")
                print("  recipes status            - Show custom recipe system status")
                print("  recipes clearall custom   - Clear ALL custom recipes")
                term.setTextColor(colors.white)
                return
            end
            
            -- View recipe details
            if subCmd == "view" or subCmd == "show" then
                local item = args[2]
                if not item then
                    ctx.err("Usage: recipes view <item>")
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                local allRecipes = recipes.getRecipesSorted(item, true)
                local activeRecipe = recipes.getRecipeFor(item)
                
                if #allRecipes == 0 then
                    ctx.err("No recipe found for: " .. item)
                    return
                end
                
                local displayName = item:gsub("minecraft:", "")
                local p = ctx.pager("=== Recipe: " .. displayName .. " ===")
                
                if #allRecipes > 1 then
                    p.setTextColor(colors.lightGray)
                    p.print("  (" .. #allRecipes .. " variants - use 'recipes prefer' to choose)")
                end
                
                for i, recipe in ipairs(allRecipes) do
                    local isActive = activeRecipe and activeRecipe.source == recipe.source
                    local isDisabled = recipePrefs.isDisabled(item, recipe.source)
                    local isCustom = recipe.source and recipe.source:find("^custom:")
                    
                    if i > 1 then
                        p.print("")
                        local variantLabel = "--- Variant #" .. i
                        if isCustom then
                            variantLabel = variantLabel .. " (CUSTOM)"
                        end
                        if isDisabled then
                            variantLabel = variantLabel .. " (DISABLED)"
                        elseif isActive then
                            variantLabel = variantLabel .. " (ACTIVE)"
                        end
                        variantLabel = variantLabel .. " ---"
                        p.setTextColor(colors.lightBlue)
                        p.print(variantLabel)
                    else
                        if isCustom then
                            p.setTextColor(colors.cyan)
                            p.print("  [CUSTOM RECIPE]")
                        end
                        if isActive then
                            p.setTextColor(colors.lime)
                            p.print("  [ACTIVE - will be used for autocrafting]")
                        elseif isDisabled then
                            p.setTextColor(colors.red)
                            p.print("  [DISABLED]")
                        end
                    end
                    
                    -- Show output count
                    p.setTextColor(colors.lightGray)
                    p.write("  Output: ")
                    p.setTextColor(colors.lime)
                    p.print(recipe.outputCount .. "x " .. displayName)
                    
                    -- Show recipe type
                    p.setTextColor(colors.lightGray)
                    p.write("  Type: ")
                    p.setTextColor(colors.white)
                    p.print(recipe.type)
                    
                    -- Show ingredients
                    p.setTextColor(colors.lightGray)
                    p.print("  Ingredients:")
                    for _, ingredient in ipairs(recipe.ingredients) do
                        local ingName = ingredient.item:gsub("minecraft:", "")
                        if ingName:sub(1, 1) == "#" then
                            ingName = ingName:sub(2) .. " (tag)"
                        end
                        p.setTextColor(colors.yellow)
                        p.write("    " .. ingredient.count .. "x ")
                        p.setTextColor(colors.white)
                        p.print(ingName)
                    end
                    
                    -- Show crafting grid for shaped recipes
                    if recipe.type == "shaped" and recipe.pattern then
                        p.setTextColor(colors.lightGray)
                        p.print("  Pattern:")
                        for _, row in ipairs(recipe.pattern) do
                            p.setTextColor(colors.gray)
                            p.write("    [")
                            for c = 1, #row do
                                local char = row:sub(c, c)
                                if char == " " then
                                    p.setTextColor(colors.gray)
                                    p.write(" ")
                                else
                                    p.setTextColor(colors.cyan)
                                    p.write(char)
                                end
                            end
                            p.setTextColor(colors.gray)
                            p.print("]")
                        end
                        
                        -- Show key legend
                        p.setTextColor(colors.lightGray)
                        p.print("  Key:")
                        for char, keyItem in pairs(recipe.key) do
                            local keyName = keyItem:gsub("minecraft:", "")
                            if keyName:sub(1, 1) == "#" then
                                keyName = keyName:sub(2) .. " (tag)"
                            end
                            p.setTextColor(colors.cyan)
                            p.write("    " .. char .. " = ")
                            p.setTextColor(colors.white)
                            p.print(keyName)
                        end
                    end
                end
                p.show()
                return
            end
            
            -- List subcommand
            if subCmd == "list" then
                local listType = args[2]
                
                if listType == "prefs" or listType == "preferences" then
                    local items = recipePrefs.getCustomizedItems()
                    
                    if #items == 0 then
                        ctx.mess("No recipe preferences configured")
                        return
                    end
                    
                    local p = ctx.pager("=== Items with Recipe Preferences ===")
                    for _, itemId in ipairs(items) do
                        local summary = recipePrefs.getSummary(itemId)
                        p.setTextColor(colors.yellow)
                        p.write("  " .. itemId:gsub("minecraft:", ""))
                        p.setTextColor(colors.lightGray)
                        p.print(" - " .. summary)
                    end
                    p.show()
                    return
                    
                elseif listType == "custom" then
                    local customRecipes = recipeOverrides.getAll()
                    
                    if #customRecipes == 0 then
                        ctx.mess("No custom recipes defined")
                        ctx.mess("Use 'recipes custom' to add one")
                        return
                    end
                    
                    local p = ctx.pager("=== Custom Recipes (" .. #customRecipes .. ") ===")
                    for i, recipe in ipairs(customRecipes) do
                        local outputName = recipe.output:gsub("minecraft:", "")
                        p.setTextColor(colors.yellow)
                        p.write(string.format("  %d. ", i))
                        p.setTextColor(colors.white)
                        p.print(recipe.outputCount .. "x " .. outputName)
                        
                        -- Show ingredients summary
                        local ingList = {}
                        for _, ing in ipairs(recipe.ingredients) do
                            table.insert(ingList, ing.count .. "x " .. ing.item:gsub("minecraft:", ""))
                        end
                        p.setTextColor(colors.lightGray)
                        p.print("     <- " .. table.concat(ingList, ", "))
                    end
                    p.show()
                    return
                else
                    ctx.err("Usage: recipes list <prefs|custom>")
                    return
                end
            end
            
            -- Open preferences menu
            if subCmd == "prefs" or subCmd == "preferences" then
                local recipeprefsConfig = require("config.recipeprefs")
                recipeprefsConfig.showMenu()
                return
            end
            
            -- Open custom recipe builder
            if subCmd == "custom" then
                local customUI = require("config.recipeoverrides-ui")
                customUI.mainMenu()
                return
            end
            
            -- Quick add custom recipe
            if subCmd == "add" then
                local customUI = require("config.recipeoverrides-ui")
                customUI.quickAdd()
                return
            end
            
            -- Status of custom recipes
            if subCmd == "status" then
                print("")
                ctx.mess("=== Custom Recipe Status ===")
                term.setTextColor(colors.lightGray)
                print(string.format("  Custom recipes: %d", recipeOverrides.count()))
                print(string.format("  System status: %s", recipeOverrides.isEnabled() and "Enabled" or "Disabled"))
                term.setTextColor(colors.white)
                return
            end
            
            -- Prefer a recipe variant
            if subCmd == "prefer" then
                local item = args[2]
                local idx = tonumber(args[3])
                
                if not item or not idx then
                    ctx.err("Usage: recipes prefer <item> <variant#>")
                    ctx.mess("Use 'recipes view <item>' to see variant numbers")
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                local allRecipes = recipes.getRecipesFor(item, true)
                if idx < 1 or idx > #allRecipes then
                    ctx.err("Invalid variant number. Use 'recipes view " .. item:gsub("minecraft:", "") .. "' to see variants.")
                    return
                end
                
                local recipe = allRecipes[idx]
                recipePrefs.setPreferred(item, recipe.source)
                ctx.succ("Set variant #" .. idx .. " as preferred for " .. item:gsub("minecraft:", ""))
                return
            end
            
            -- Enable a recipe variant
            if subCmd == "enable" then
                local item = args[2]
                local idx = tonumber(args[3])
                
                if not item or not idx then
                    ctx.err("Usage: recipes enable <item> <variant#>")
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                local allRecipes = recipes.getRecipesFor(item, true)
                if idx < 1 or idx > #allRecipes then
                    ctx.err("Invalid variant number.")
                    return
                end
                
                local recipe = allRecipes[idx]
                recipePrefs.enable(item, recipe.source)
                ctx.succ("Enabled variant #" .. idx .. " for " .. item:gsub("minecraft:", ""))
                return
            end
            
            -- Disable a recipe variant
            if subCmd == "disable" then
                local item = args[2]
                local idx = tonumber(args[3])
                
                if not item or not idx then
                    ctx.err("Usage: recipes disable <item> <variant#>")
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                local allRecipes = recipes.getRecipesFor(item, true)
                if idx < 1 or idx > #allRecipes then
                    ctx.err("Invalid variant number.")
                    return
                end
                
                local recipe = allRecipes[idx]
                recipePrefs.disable(item, recipe.source)
                ctx.succ("Disabled variant #" .. idx .. " for " .. item:gsub("minecraft:", ""))
                return
            end
            
            -- Clear preferences for an item
            if subCmd == "clear" then
                local item = args[2]
                
                if not item then
                    ctx.err("Usage: recipes clear <item>")
                    return
                end
                
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                recipePrefs.clear(item)
                ctx.succ("Cleared recipe preferences for " .. item:gsub("minecraft:", ""))
                return
            end
            
            -- Clear all
            if subCmd == "clearall" then
                local clearType = args[2]
                
                if clearType == "prefs" or clearType == "preferences" then
                    recipePrefs.clearAll()
                    ctx.succ("Cleared all recipe preferences")
                    return
                elseif clearType == "custom" then
                    print("")
                    print("Are you sure you want to delete ALL custom recipes?")
                    print("Type 'yes' to confirm:")
                    local confirm = read()
                    if confirm == "yes" then
                        recipeOverrides.clear()
                        ctx.succ("Cleared all custom recipes")
                    else
                        ctx.mess("Clear cancelled")
                    end
                    return
                else
                    ctx.err("Usage: recipes clearall <prefs|custom>")
                    return
                end
            end
            
            -- Unknown subcommand - treat as search
            local query = table.concat(args, " ")
            local results = recipes.search(query)
            
            if #results == 0 then
                ctx.err("Unknown command or no recipes found: " .. query)
                ctx.mess("Use 'recipes help' to see all commands")
                return
            end
            
            local p = ctx.pager("=== Recipes (" .. #results .. " found) ===")
            for _, r in ipairs(results) do
                local output = r.output:gsub("minecraft:", "")
                p.print("  " .. output)
            end
            p.show()
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"view", "list", "prefs", "custom", "add", "prefer", "enable", "disable", "clear", "clearall", "status", "help"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) == 1 then
                        table.insert(matches, opt)
                    end
                end
                -- Also add recipe search completions
                if query ~= "" then
                    local results = recipes.search(query)
                    for _, r in ipairs(results) do
                        table.insert(matches, (r.output:gsub("minecraft:", "")))
                    end
                end
                return matches
            elseif #args == 2 then
                local sub = args[1]
                if sub == "view" or sub == "show" or sub == "prefer" or sub == "enable" or sub == "disable" or sub == "clear" then
                    local query = args[2] or ""
                    if query == "" then return {} end
                    local results = recipes.search(query)
                    local completions = {}
                    for _, r in ipairs(results) do
                        table.insert(completions, (r.output:gsub("minecraft:", "")))
                    end
                    return completions
                elseif sub == "list" or sub == "clearall" then
                    return {"prefs", "custom"}
                end
            end
            return {}
        end
    },
    
    settings = {
        description = "View/edit server settings",
        category = "config",
        aliases = {"cfg", "options"},
        execute = function(args, ctx)
            local subCmd = args[1]
            
            if subCmd == "reset" then
                print("")
                print("Are you sure you want to reset all settings to defaults?")
                print("Type 'yes' to confirm:")
                local confirm = read()
                if confirm == "yes" then
                    config.reset()
                    ctx.succ("Settings reset to defaults")
                    print("Restart the server for changes to take effect.")
                else
                    ctx.mess("Reset cancelled")
                end
                return
            end
            
            if subCmd == "show" or subCmd == "list" then
                -- Show current settings with default comparison
                local p = ctx.pager("=== Current Settings ===")
                for key, default in pairs(config.defaults) do
                    local current = config.get(key)
                    local isDefault = (current == default)
                    p.setTextColor(colors.white)
                    p.write(key .. ": ")
                    if isDefault then
                        p.setTextColor(colors.gray)
                    else
                        p.setTextColor(colors.lime)
                    end
                    if type(current) == "table" then
                        p.print(textutils.serialize(current, {compact = true}))
                    else
                        p.print(tostring(current))
                    end
                end
                p.print("")
                p.setTextColor(colors.lightBlue)
                p.print("Green = modified, Gray = default")
                p.show()
                return
            end
            
            if subCmd == "edit" or not subCmd then
                -- Interactive FormUI editor for settings using config.showSettingsForm()
                if config.showSettingsForm() then
                    ctx.succ("Settings saved!")
                    print("Restart the server for changes to take effect.")
                else
                    ctx.mess("Settings cancelled")
                end
                return
            end
            
            if subCmd == "get" then
                local key = args[2]
                if not key then
                    ctx.err("Usage: settings get <key>")
                    return
                end
                local value = config.get(key)
                if value == nil then
                    ctx.err("Unknown setting: " .. key)
                else
                    print(key .. " = " .. tostring(value))
                end
                return
            end
            
            if subCmd == "set" then
                local key = args[2]
                local value = args[3]
                if not key or not value then
                    ctx.err("Usage: settings set <key> <value>")
                    return
                end
                -- Parse value
                if value == "true" then value = true
                elseif value == "false" then value = false
                elseif tonumber(value) then value = tonumber(value)
                end
                config.set(key, value)
                ctx.succ("Set " .. key .. " = " .. tostring(value))
                print("Restart the server for changes to take effect.")
                return
            end
            
            -- Unknown subcommand, show help
            ctx.err("Unknown subcommand: " .. subCmd)
            print("Available: show, edit, get, set, reset")
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"show", "edit", "get", "set", "reset"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:lower():find(query, 1, true) then
                        table.insert(matches, opt)
                    end
                end
                return matches
            elseif #args == 2 and (args[1] == "get" or args[1] == "set") then
                local query = (args[2] or ""):lower()
                local matches = {}
                for key, _ in pairs(config.defaults) do
                    if key:lower():find(query, 1, true) then
                        table.insert(matches, key)
                    end
                end
                return matches
            end
            return {}
        end
    },
    
    stock = {
        description = "Search item stock",
        category = "storage",
        aliases = {"find", "search"},
        execute = function(args, ctx)
            local query = args[1] or ""
            local results = storageManager.searchItems(query)
            
            if #results == 0 then
                ctx.mess("No items found" .. (query ~= "" and " for: " .. query or ""))
                return
            end
            
            -- Get target information
            local craftTargets = targets.getAll()
            local smeltTargets = furnaceConfig.getAllSmeltTargets()
            local workerTasks = workerConfig.getAllTasks()
            
            -- Build worker target lookup by item
            local workerTargetsByItem = {}
            for taskId, task in pairs(workerTasks) do
                if task.item and task.enabled then
                    workerTargetsByItem[task.item] = task.stockTarget
                end
            end
            
            -- Get active jobs to show what's being crafted
            local allJobs = queueManager.getJobs()
            local jobsByItem = {}
            for _, job in ipairs(allJobs) do
                if job.recipe and job.recipe.output then
                    local output = job.recipe.output
                    if not jobsByItem[output] then
                        jobsByItem[output] = { count = 0, pending = 0, crafting = 0 }
                    end
                    jobsByItem[output].count = jobsByItem[output].count + (job.expectedOutput or 0)
                    if job.status == "pending" or job.status == "assigned" then
                        jobsByItem[output].pending = jobsByItem[output].pending + (job.expectedOutput or 0)
                    elseif job.status == "crafting" then
                        jobsByItem[output].crafting = jobsByItem[output].crafting + (job.expectedOutput or 0)
                    end
                end
            end
            
            local p = ctx.pager("=== Stock (" .. #results .. " items) ===")
            for _, item in ipairs(results) do
                local itemId = item.item
                local name = itemId:gsub("minecraft:", "")
                
                -- Get target info
                local craftTarget = craftTargets[itemId]
                local smeltTarget = smeltTargets[itemId]
                local workerTarget = workerTargetsByItem[itemId]
                local jobInfo = jobsByItem[itemId]
                
                -- Build target string
                local targetParts = {}
                if craftTarget then
                    table.insert(targetParts, "craft:" .. craftTarget)
                end
                if smeltTarget then
                    table.insert(targetParts, "smelt:" .. smeltTarget)
                end
                if workerTarget then
                    table.insert(targetParts, "worker:" .. workerTarget)
                end
                
                -- First line: item name and count
                p.setTextColor(colors.white)
                p.write("  " .. name .. " ")
                p.setTextColor(colors.lightGray)
                p.write("x" .. item.count)
                
                -- Show target if any
                if #targetParts > 0 then
                    p.setTextColor(colors.gray)
                    p.write(" (")
                    p.setTextColor(colors.yellow)
                    p.write(table.concat(targetParts, ", "))
                    p.setTextColor(colors.gray)
                    p.write(")")
                end
                
                -- Show job status if any
                if jobInfo then
                    p.write(" ")
                    p.setTextColor(colors.cyan)
                    if jobInfo.crafting > 0 then
                        p.write("[crafting " .. jobInfo.crafting .. "]")
                    elseif jobInfo.pending > 0 then
                        p.write("[queued " .. jobInfo.pending .. "]")
                    end
                end
                
                p.print("")
            end
            p.show()
        end
    },
    
    exports = {
        description = "Manage export inventories",
        category = "exports",
        aliases = {"export", "exp"},
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
                
                local p = ctx.pager("=== Export Inventories (" .. count .. ") ===")
                for name, cfg in pairs(all) do
                    local itemCount = #(cfg.slots or {})
                    local modeDisplay = cfg.mode
                    if cfg.mode == "empty" and itemCount == 0 then
                        modeDisplay = "drain all"
                    end
                    p.setTextColor(colors.lime)
                    p.write(cfg.mode == "stock" and "+" or "-")
                    p.setTextColor(colors.white)
                    p.write(" " .. name .. " ")
                    p.setTextColor(colors.lightGray)
                    if cfg.mode == "empty" and itemCount == 0 then
                        p.print(string.format("[%s]", modeDisplay))
                    else
                        p.print(string.format("[%s] %d items", modeDisplay, itemCount))
                    end
                end
                p.show()
                
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
                
                local p = ctx.pager("=== Items for " .. invName .. " ===")
                p.setTextColor(colors.lightBlue)
                p.print("Mode: " .. cfg.mode)
                p.print("")
                
                if #items == 0 then
                    if cfg.mode == "empty" then
                        p.setTextColor(colors.lime)
                        p.print("  (draining ALL items)")
                    else
                        p.setTextColor(colors.lightBlue)
                        p.print("No items configured")
                    end
                else
                    for i, item in ipairs(items) do
                        p.setTextColor(colors.white)
                        p.write(string.format("%d. %s ", i, item.item:gsub("minecraft:", "")))
                        p.setTextColor(colors.lightGray)
                        local details = ""
                        if item.slot then
                            details = string.format("x%d (slot %d)", item.quantity, item.slot)
                        elseif item.slotStart and item.slotEnd then
                            details = string.format("x%d (slots %d-%d)", item.quantity, item.slotStart, item.slotEnd)
                        else
                            details = string.format("x%d", item.quantity)
                        end
                        if item.nbtMode and item.nbtMode ~= "any" then
                            details = details .. " [nbt:" .. item.nbtMode .. "]"
                        end
                        if item.vacuum then
                            details = details .. " [vacuum]"
                        end
                        p.print(details)
                    end
                end
                p.print("")
                p.setTextColor(colors.lightBlue)
                p.print("Use 'exports edit <inv>' for FormUI editor")
                p.print("Use 'exports additem <inv> <item> <qty> [slot]' to add")
                p.print("Use 'exports rmitem <inv> <item>' to remove")
                if cfg.mode == "empty" then
                    p.print("Tip: Leave empty to drain ALL items from inventory")
                end
                p.show()
                
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
                        if display == "*" then display = "(vacuum)" end
                        
                        if item.slotStart and item.slotEnd then
                            display = display .. string.format(" x%d (slots %d-%d)", item.quantity, item.slotStart, item.slotEnd)
                        elseif item.slot then
                            display = display .. string.format(" x%d (slot %d)", item.quantity, item.slot)
                        else
                            display = display .. string.format(" x%d", item.quantity)
                        end
                        
                        if item.vacuum then
                            display = display .. " [vacuum]"
                        end
                        
                        -- Show NBT mode if not default
                        if item.nbtMode and item.nbtMode ~= "any" then
                            display = display .. " [nbt:" .. item.nbtMode .. "]"
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
                        form:button("Clear All Items", "clearall")
                    end
                    form:button("Change Mode", "mode")
                    form:label("")
                    form:label("-- Quick Setup --")
                    form:button("Fill All Slots (same item)", "fillall")
                    form:button("Multi-Item (one per slot)", "multiitem")
                    form:button("Split Fill (divide slots)", "splitfill")
                    form:label("")
                    form:label("-- Advanced --")
                    form:button("Add Slot Range", "addrange")
                    form:button("Add Vacuum Slots", "addvacuum")
                    form:button("Done", "done")
                    
                    local result = form:run()
                    if not result then
                        editing = false
                    else
                        -- Use _action for easy button detection
                        local action = result._action
                        
                        if action == "add" then
                            -- Calculate next open slot
                            local usedSlots = {}
                            for _, slotCfg in ipairs(items) do
                                if slotCfg.slot then
                                    usedSlots[slotCfg.slot] = true
                                end
                                if slotCfg.slotStart and slotCfg.slotEnd then
                                    for s = slotCfg.slotStart, slotCfg.slotEnd do
                                        usedSlots[s] = true
                                    end
                                end
                            end
                            
                            -- Find next open slot (start from 1)
                            local nextSlot = 1
                            while usedSlots[nextSlot] do
                                nextSlot = nextSlot + 1
                            end
                            
                            -- Form to add a new item
                            local addForm = FormUI.new("Add Item to Export")
                            local itemField = addForm:text("Item Name", "", nil, false)
                            local qtyField = addForm:number("Quantity", cfg.mode == "stock" and 64 or 0)
                            local useSlotField = addForm:checkbox("Use specific slot", true)
                            local slotField = addForm:number("Slot number", nextSlot)
                            local vacuumField = addForm:checkbox("Vacuum (remove non-matching)", false)
                            addForm:label("")
                            addForm:label("-- NBT Matching --")
                            local nbtModeField = addForm:select("NBT Mode", 
                                {"any (all variants)", "none (no NBT only)", "with (has NBT only)", "exact (specific NBT)"}, 1)
                            addForm:label("'any' = all variants of item")
                            addForm:label("'none' = only items WITHOUT NBT data")
                            addForm:label("'with' = only items WITH any NBT data")
                            addForm:label("'exact' = specific NBT hash (advanced)")
                            addForm:label("")
                            if cfg.mode == "stock" then
                                addForm:label("Quantity = amount to keep stocked per slot")
                            else
                                addForm:label("Quantity = amount to leave (0 = take all)")
                            end
                            addForm:label("Vacuum = deposits non-matching items to storage")
                            addForm:addSubmitCancel()
                            
                            local addResult = addForm:run()
                            if addResult then
                                local itemName = itemField()
                                local qty = qtyField()
                                local useSlot = useSlotField()
                                local slot = useSlot and slotField() or nil
                                local vacuum = vacuumField()
                                local nbtModeIdx = nbtModeField()
                                local nbtModes = {"any", "none", "with", "exact"}
                                local nbtMode = nbtModes[nbtModeIdx]
                                
                                -- For "exact" mode, we'd need additional NBT hash input
                                -- For now, just use the mode (exact without hash = no match)
                                local nbtHash = nil
                                
                                -- Add minecraft: prefix if missing
                                if itemName ~= "" and not itemName:find(":") then
                                    itemName = "minecraft:" .. itemName
                                end
                                
                                if itemName ~= "" then
                                    exportConfig.addItem(invName, itemName, qty, slot, nil, nil, vacuum, nbtMode, nbtHash)
                                    -- Refresh items list
                                    cfg = exportConfig.get(invName)
                                    items = cfg.slots or {}
                                end
                            end
                            
                        elseif action == "addrange" then
                            -- Form to add a slot range
                            local rangeForm = FormUI.new("Add Slot Range")
                            local itemField = rangeForm:text("Item Name", "", nil, false)
                            local qtyField = rangeForm:number("Quantity per slot", cfg.mode == "stock" and 64 or 0)
                            local startField = rangeForm:number("Start Slot", 1)
                            local endField = rangeForm:number("End Slot", 9)
                            local vacuumField = rangeForm:checkbox("Vacuum (remove non-matching)", true)
                            rangeForm:label("")
                            rangeForm:label("-- NBT Matching --")
                            local nbtModeField = rangeForm:select("NBT Mode",
                                {"any (all variants)", "none (no NBT only)", "with (has NBT only)", "exact (specific NBT)"}, 1)
                            rangeForm:label("")
                            rangeForm:label("Example: slots 1-9 with 64 coal each")
                            rangeForm:label("Vacuum removes non-matching items from slots")
                            rangeForm:addSubmitCancel()
                            
                            local rangeResult = rangeForm:run()
                            if rangeResult then
                                local itemName = itemField()
                                local qty = qtyField()
                                local slotStart = startField()
                                local slotEnd = endField()
                                local vacuum = vacuumField()
                                local nbtModeIdx = nbtModeField()
                                local nbtModes = {"any", "none", "with", "exact"}
                                local nbtMode = nbtModes[nbtModeIdx]
                                
                                -- Add minecraft: prefix if missing
                                if itemName ~= "" and not itemName:find(":") then
                                    itemName = "minecraft:" .. itemName
                                end
                                
                                if itemName ~= "" and slotStart <= slotEnd then
                                    exportConfig.addSlotRange(invName, itemName, qty, slotStart, slotEnd, vacuum, nbtMode, nil)
                                    -- Refresh items list
                                    cfg = exportConfig.get(invName)
                                    items = cfg.slots or {}
                                end
                            end
                            
                        elseif action == "addvacuum" then
                            -- Form to add vacuum-only slots
                            local vacuumForm = FormUI.new("Add Vacuum Slots")
                            vacuumForm:label("Vacuum slots automatically deposit")
                            vacuumForm:label("ANY items placed there to storage.")
                            vacuumForm:label("Great for 'drop-off' areas!")
                            vacuumForm:label("")
                            local startField = vacuumForm:number("Start Slot", 10)
                            local endField = vacuumForm:number("End Slot", 27)
                            vacuumForm:addSubmitCancel()
                            
                            local vacuumResult = vacuumForm:run()
                            if vacuumResult then
                                local slotStart = startField()
                                local slotEnd = endField()
                                
                                if slotStart <= slotEnd then
                                    exportConfig.addVacuumRange(invName, slotStart, slotEnd)
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
                                if display == "*" then display = "(vacuum)" end
                                if item.slotStart and item.slotEnd then
                                    display = display .. string.format(" (slots %d-%d)", item.slotStart, item.slotEnd)
                                elseif item.slot then
                                    display = display .. " (slot " .. item.slot .. ")"
                                end
                                if item.vacuum then
                                    display = display .. " [vacuum]"
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
                            
                        elseif action == "clearall" then
                            -- Clear all items from this export inventory
                            cfg.slots = {}
                            exportConfig.set(invName, cfg)
                            items = {}
                            
                        elseif action == "fillall" then
                            -- Fill all slots with the same item
                            local fillForm = FormUI.new("Fill All Slots")
                            fillForm:label("Fill entire chest with one item type.")
                            fillForm:label("Great for bulk export (e.g., wheat chest).")
                            fillForm:label("")
                            local itemField = fillForm:text("Item Name", "", nil, false)
                            local qtyField = fillForm:number("Quantity per slot", cfg.mode == "stock" and 64 or 0)
                            local startSlot = fillForm:number("Start Slot", 1)
                            local endSlot = fillForm:number("End Slot", 27)
                            local vacuumField = fillForm:checkbox("Vacuum (remove non-matching)", true)
                            fillForm:addSubmitCancel()
                            
                            local fillResult = fillForm:run()
                            if fillResult then
                                local itemName = itemField()
                                local qty = qtyField()
                                local slotStart = startSlot()
                                local slotEnd = endSlot()
                                local vacuum = vacuumField()
                                
                                if itemName ~= "" and not itemName:find(":") then
                                    itemName = "minecraft:" .. itemName
                                end
                                
                                if itemName ~= "" and slotStart <= slotEnd then
                                    exportConfig.addSlotRange(invName, itemName, qty, slotStart, slotEnd, vacuum)
                                    cfg = exportConfig.get(invName)
                                    items = cfg.slots or {}
                                end
                            end
                            
                        elseif action == "multiitem" then
                            -- Multi-item: different item in each slot
                            local multiForm = FormUI.new("Multi-Item Fill")
                            multiForm:label("Put a DIFFERENT item in each slot.")
                            multiForm:label("Enter items separated by commas.")
                            multiForm:label("Example: cobblestone,stone,dirt")
                            multiForm:label("")
                            local itemsField = multiForm:text("Items (comma-sep)", "", nil, false)
                            local qtyField = multiForm:number("Quantity per slot", cfg.mode == "stock" and 64 or 0)
                            local startSlot = multiForm:number("Starting Slot", 1)
                            local vacuumField = multiForm:checkbox("Vacuum (remove non-matching)", true)
                            multiForm:addSubmitCancel()
                            
                            local multiResult = multiForm:run()
                            if multiResult then
                                local itemsStr = itemsField()
                                local qty = qtyField()
                                local slotNum = startSlot()
                                local vacuum = vacuumField()
                                
                                -- Parse comma-separated items
                                for itemName in itemsStr:gmatch("[^,]+") do
                                    itemName = itemName:match("^%s*(.-)%s*$")  -- Trim whitespace
                                    if itemName ~= "" then
                                        if not itemName:find(":") then
                                            itemName = "minecraft:" .. itemName
                                        end
                                        exportConfig.addItem(invName, itemName, qty, slotNum, nil, nil, vacuum)
                                        slotNum = slotNum + 1
                                    end
                                end
                                
                                cfg = exportConfig.get(invName)
                                items = cfg.slots or {}
                            end
                            
                        elseif action == "splitfill" then
                            -- Split fill: divide slots among multiple items
                            local splitForm = FormUI.new("Split Fill")
                            splitForm:label("Divide slots equally among items.")
                            splitForm:label("Example: 1/3 cobblestone, 1/3 stone, 1/3 dirt")
                            splitForm:label("Enter items separated by commas.")
                            splitForm:label("")
                            local itemsField = splitForm:text("Items (comma-sep)", "", nil, false)
                            local qtyField = splitForm:number("Quantity per slot", cfg.mode == "stock" and 64 or 0)
                            local startSlot = splitForm:number("Start Slot", 1)
                            local endSlot = splitForm:number("End Slot", 27)
                            local vacuumField = splitForm:checkbox("Vacuum (remove non-matching)", true)
                            splitForm:addSubmitCancel()
                            
                            local splitResult = splitForm:run()
                            if splitResult then
                                local itemsStr = itemsField()
                                local qty = qtyField()
                                local slotStart = startSlot()
                                local slotEnd = endSlot()
                                local vacuum = vacuumField()
                                
                                -- Parse items
                                local itemList = {}
                                for itemName in itemsStr:gmatch("[^,]+") do
                                    itemName = itemName:match("^%s*(.-)%s*$")
                                    if itemName ~= "" then
                                        if not itemName:find(":") then
                                            itemName = "minecraft:" .. itemName
                                        end
                                        table.insert(itemList, itemName)
                                    end
                                end
                                
                                if #itemList > 0 and slotStart <= slotEnd then
                                    local totalSlots = slotEnd - slotStart + 1
                                    local slotsPerItem = math.floor(totalSlots / #itemList)
                                    local extraSlots = totalSlots % #itemList
                                    
                                    local currentSlot = slotStart
                                    for i, itemName in ipairs(itemList) do
                                        local slotsForThis = slotsPerItem
                                        -- Distribute extra slots to first items
                                        if i <= extraSlots then
                                            slotsForThis = slotsForThis + 1
                                        end
                                        
                                        if slotsForThis > 0 then
                                            local rangeEnd = currentSlot + slotsForThis - 1
                                            exportConfig.addSlotRange(invName, itemName, qty, currentSlot, rangeEnd, vacuum)
                                            currentSlot = rangeEnd + 1
                                        end
                                    end
                                    
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
    
    furnaces = {
        description = "Manage furnaces for smelting",
        category = "furnaces",
        aliases = {"furnace", "smelt"},
        execute = function(args, ctx)
            local subCmd = args[1]
            
            if not subCmd or subCmd == "help" then
                ctx.mess("=== Furnace Commands ===")
                print("  furnaces list - List configured furnaces")
                print("  furnaces discover - Auto-discover furnaces on network")
                print("  furnaces add <name> - Add a furnace by peripheral name")
                print("  furnaces remove <name> - Remove a furnace")
                print("  furnaces enable <name> - Enable a furnace")
                print("  furnaces disable <name> - Disable a furnace")
                print("  furnaces status - Show furnace status")
                print("  furnaces targets - List smelt targets")
                print("  furnaces recipes [search] - Search smelting recipes")
                print("  furnaces fuel - Show fuel config & stock")
                print("  furnaces fuel list - List preferred fuels")
                print("  furnaces fuel add <item> [pos] - Add fuel to list")
                print("  furnaces fuel remove <item> - Remove fuel from list")
                print("  furnaces lava - Show lava bucket config")
                print("  furnaces lava enable/disable - Toggle lava bucket")
                print("  furnaces lava input <chest> - Set lava input chest")
                print("  furnaces lava output <chest> - Set empty bucket chest")
                print("  furnaces kelp - Show dried kelp mode status")
                print("  furnaces kelp enable/disable - Toggle kelp mode")
                print("  furnaces kelp target <count> - Set kelp block target")
                return
            end
            
            if subCmd == "list" then
                local all = furnaceConfig.getAll()
                local count = 0
                for _ in pairs(all) do count = count + 1 end
                
                if count == 0 then
                    ctx.mess("No furnaces configured")
                    print("Use 'furnaces discover' to auto-discover furnaces")
                    return
                end
                
                local p = ctx.pager("=== Furnaces (" .. count .. ") ===")
                for name, furnace in pairs(all) do
                    local status = furnace.enabled and colors.lime or colors.red
                    p.setTextColor(status)
                    p.print(name)
                    p.setTextColor(colors.lightGray)
                    p.print("  Type: " .. furnace.type)
                    p.print("  Status: " .. (furnace.enabled and "Enabled" or "Disabled"))
                end
                p.show()
                return
            end
            
            if subCmd == "discover" then
                ctx.mess("Discovering furnaces on network...")
                local discovered = furnaceManager.autoDiscover()
                if discovered > 0 then
                    ctx.succ(string.format("Discovered %d new furnace(s)", discovered))
                else
                    ctx.mess("No new furnaces found")
                end
                return
            end
            
            if subCmd == "add" then
                local name = args[2]
                if not name then
                    ctx.err("Usage: furnaces add <peripheral-name>")
                    return
                end
                
                local p = peripheral.wrap(name)
                if not p then
                    ctx.err("Peripheral not found: " .. name)
                    return
                end
                
                furnaceConfig.add(name)
                ctx.succ("Added furnace: " .. name)
                return
            end
            
            if subCmd == "remove" then
                local name = args[2]
                if not name then
                    ctx.err("Usage: furnaces remove <name>")
                    return
                end
                
                if not furnaceConfig.get(name) then
                    ctx.err("Furnace not found: " .. name)
                    return
                end
                
                furnaceConfig.remove(name)
                ctx.succ("Removed furnace: " .. name)
                return
            end
            
            if subCmd == "enable" then
                local name = args[2]
                if not name then
                    ctx.err("Usage: furnaces enable <name>")
                    return
                end
                
                if not furnaceConfig.get(name) then
                    ctx.err("Furnace not found: " .. name)
                    return
                end
                
                furnaceConfig.setEnabled(name, true)
                ctx.succ("Enabled furnace: " .. name)
                return
            end
            
            if subCmd == "disable" then
                local name = args[2]
                if not name then
                    ctx.err("Usage: furnaces disable <name>")
                    return
                end
                
                if not furnaceConfig.get(name) then
                    ctx.err("Furnace not found: " .. name)
                    return
                end
                
                furnaceConfig.setEnabled(name, false)
                ctx.succ("Disabled furnace: " .. name)
                return
            end
            
            if subCmd == "status" then
                local status = furnaceManager.getStatus()
                
                if #status == 0 then
                    ctx.mess("No furnaces configured")
                    return
                end
                
                local p = ctx.pager("=== Furnace Status ===")
                for _, f in ipairs(status) do
                    local color = colors.white
                    if not f.connected then
                        color = colors.red
                    elseif not f.enabled then
                        color = colors.gray
                    elseif f.available then
                        color = colors.lime
                    else
                        color = colors.yellow
                    end
                    
                    p.setTextColor(color)
                    p.print(f.name .. " (" .. f.type .. ")")
                    
                    if f.connected then
                        p.setTextColor(colors.lightGray)
                        local inputStr = f.input and (f.input.count .. "x " .. f.input.name:gsub("minecraft:", "")) or "empty"
                        local fuelStr = f.fuel and (f.fuel.count .. "x " .. f.fuel.name:gsub("minecraft:", "")) or "empty"
                        local outputStr = f.output and (f.output.count .. "x " .. f.output.name:gsub("minecraft:", "")) or "empty"
                        p.print("  Input: " .. inputStr)
                        p.print("  Fuel: " .. fuelStr)
                        p.print("  Output: " .. outputStr)
                    else
                        p.setTextColor(colors.red)
                        p.print("  (not connected)")
                    end
                end
                p.show()
                return
            end
            
            if subCmd == "targets" then
                local stock = storageManager.getAllStock()
                local all = furnaceConfig.getSmeltTargetsWithStock(stock)
                
                if #all == 0 then
                    ctx.mess("No smelt targets configured")
                    print("Use 'add <item> <quantity> --smelt' to add smelt targets")
                    return
                end
                
                local p = ctx.pager("=== Smelt Targets ===")
                for _, target in ipairs(all) do
                    local displayName = target.item:gsub("minecraft:", "")
                    local color = colors.white
                    if target.current >= target.target then
                        color = colors.lime
                    elseif target.current > 0 then
                        color = colors.yellow
                    else
                        color = colors.red
                    end
                    p.setTextColor(color)
                    p.print(displayName)
                    p.setTextColor(colors.lightGray)
                    p.print(string.format("  %d/%d", target.current, target.target))
                end
                p.show()
                return
            end
            
            if subCmd == "recipes" then
                local query = args[2] or ""
                local results = furnaceManager.searchRecipes(query)
                
                if #results == 0 then
                    ctx.mess("No smelting recipes found" .. (query ~= "" and " for '" .. query .. "'" or ""))
                    return
                end
                
                local p = ctx.pager("=== Smelting Recipes (" .. #results .. ") ===")
                for _, r in ipairs(results) do
                    local input = r.input:gsub("minecraft:", "")
                    local output = r.output:gsub("minecraft:", "")
                    p.setTextColor(colors.white)
                    p.print(input .. " -> " .. output)
                    p.setTextColor(colors.lightGray)
                    p.print("  Type: " .. r.type)
                end
                p.show()
                return
            end
            
            if subCmd == "fuel" then
                local fuelCmd = args[2]
                local stock = storageManager.getAllStock()
                
                if not fuelCmd or fuelCmd == "list" or fuelCmd == "status" then
                    local summary = furnaceManager.getFuelSummary(stock)
                    local p = ctx.pager("=== Fuel Configuration ===")
                    
                    p.setTextColor(colors.yellow)
                    p.print("Preferred Fuels (in priority order):")
                    p.setTextColor(colors.white)
                    
                    for i, fuel in ipairs(summary.fuelStock) do
                        local name = fuel.item:gsub("minecraft:", "")
                        local stockColor = fuel.stock > 0 and colors.green or colors.red
                        p.setTextColor(colors.white)
                        p.write(string.format("  %d. %s", i, name))
                        p.setTextColor(stockColor)
                        p.write(string.format(" [%d]", fuel.stock))
                        p.setTextColor(colors.lightGray)
                        p.print(string.format(" (smelt x%.1f)", fuel.burnTime))
                    end
                    
                    p.print("")
                    p.setTextColor(colors.yellow)
                    p.print("Total Smelt Capacity: " .. math.floor(summary.totalSmeltCapacity) .. " items")
                    
                    p.setTextColor(colors.lightGray)
                    p.print("")
                    p.print("Lava Bucket: " .. (summary.config.enableLavaBucket and "Enabled" or "Disabled"))
                    if summary.config.lavaBucketInputChest then
                        p.print("  Input: " .. summary.config.lavaBucketInputChest)
                    end
                    if summary.config.lavaBucketOutputChest then
                        p.print("  Output: " .. summary.config.lavaBucketOutputChest)
                    end
                    
                    p.show()
                    return
                end
                
                if fuelCmd == "add" then
                    local item = args[3]
                    local pos = tonumber(args[4])
                    
                    if not item then
                        ctx.err("Usage: furnaces fuel add <item> [position]")
                        return
                    end
                    
                    -- Add minecraft: prefix if not present
                    if not item:find(":") then
                        item = "minecraft:" .. item
                    end
                    
                    furnaceConfig.addPreferredFuel(item, pos)
                    ctx.mess("Added " .. item .. " to preferred fuels" .. (pos and " at position " .. pos or ""))
                    return
                end
                
                if fuelCmd == "remove" then
                    local item = args[3]
                    
                    if not item then
                        ctx.err("Usage: furnaces fuel remove <item>")
                        return
                    end
                    
                    if not item:find(":") then
                        item = "minecraft:" .. item
                    end
                    
                    if furnaceConfig.removePreferredFuel(item) then
                        ctx.mess("Removed " .. item .. " from preferred fuels")
                    else
                        ctx.err("Fuel not found in preferred list: " .. item)
                    end
                    return
                end
                
                ctx.err("Unknown fuel subcommand: " .. fuelCmd)
                print("Use 'furnaces fuel list' to see current config")
                return
            end
            
            if subCmd == "lava" then
                local lavaCmd = args[2]
                
                if not lavaCmd then
                    local config = furnaceConfig.getFuelConfig()
                    ctx.mess("=== Lava Bucket Configuration ===")
                    print("  Status: " .. (config.enableLavaBucket and "Enabled" or "Disabled"))
                    print("  Input Chest: " .. (config.lavaBucketInputChest or "(not set)"))
                    print("  Output Chest: " .. (config.lavaBucketOutputChest or "(not set)"))
                    print("")
                    print("Use 'furnaces lava enable/disable' to toggle")
                    print("Use 'furnaces lava input <chest>' to set input")
                    print("Use 'furnaces lava output <chest>' to set output")
                    return
                end
                
                if lavaCmd == "enable" then
                    furnaceConfig.setLavaBucketEnabled(true)
                    ctx.mess("Enabled lava bucket fuel")
                    return
                end
                
                if lavaCmd == "disable" then
                    furnaceConfig.setLavaBucketEnabled(false)
                    ctx.mess("Disabled lava bucket fuel")
                    return
                end
                
                if lavaCmd == "input" then
                    local chest = args[3]
                    if not chest then
                        ctx.err("Usage: furnaces lava input <chest-name>")
                        print("Use 'clear' to remove the input chest")
                        return
                    end
                    
                    if chest == "clear" or chest == "none" then
                        furnaceConfig.setLavaBucketInputChest(nil)
                        ctx.mess("Cleared lava bucket input chest")
                        return
                    end
                    
                    -- Verify peripheral exists
                    if not peripheral.wrap(chest) then
                        ctx.err("Peripheral not found: " .. chest)
                        return
                    end
                    
                    furnaceConfig.setLavaBucketInputChest(chest)
                    ctx.mess("Set lava bucket input chest: " .. chest)
                    return
                end
                
                if lavaCmd == "output" then
                    local chest = args[3]
                    if not chest then
                        ctx.err("Usage: furnaces lava output <chest-name>")
                        print("Use 'clear' to remove the output chest")
                        return
                    end
                    
                    if chest == "clear" or chest == "none" then
                        furnaceConfig.setLavaBucketOutputChest(nil)
                        ctx.mess("Cleared lava bucket output chest")
                        return
                    end
                    
                    -- Verify peripheral exists
                    if not peripheral.wrap(chest) then
                        ctx.err("Peripheral not found: " .. chest)
                        return
                    end
                    
                    furnaceConfig.setLavaBucketOutputChest(chest)
                    ctx.mess("Set lava bucket output chest: " .. chest)
                    return
                end
                
                ctx.err("Unknown lava subcommand: " .. lavaCmd)
                return
            end
            
            if subCmd == "kelp" then
                local kelpCmd = args[2]
                local stock = storageManager.getAllStock()
                
                if not kelpCmd then
                    local status = furnaceManager.getDriedKelpStatus(stock)
                    ctx.mess("=== Dried Kelp Mode ===")
                    print("  Status: " .. (status.enabled and "Enabled" or "Disabled"))
                    print("  Target: " .. status.target .. " dried kelp blocks")
                    print("")
                    print("  Current Stock:")
                    print("    Kelp: " .. status.currentKelp)
                    print("    Dried Kelp: " .. status.currentDriedKelp)
                    print("    Dried Kelp Blocks: " .. status.currentBlocks)
                    print("")
                    if status.enabled and status.target > 0 then
                        print("  Blocks needed: " .. status.blocksNeeded)
                        print("  Can craft: " .. status.canCraftBlocks .. " blocks")
                    end
                    return
                end
                
                if kelpCmd == "enable" then
                    furnaceConfig.setDriedKelpModeEnabled(true)
                    ctx.mess("Enabled dried kelp mode")
                    return
                end
                
                if kelpCmd == "disable" then
                    furnaceConfig.setDriedKelpModeEnabled(false)
                    ctx.mess("Disabled dried kelp mode")
                    return
                end
                
                if kelpCmd == "target" then
                    local target = tonumber(args[3])
                    if not target then
                        ctx.err("Usage: furnaces kelp target <count>")
                        print("Current target: " .. furnaceConfig.getDriedKelpTarget())
                        return
                    end
                    
                    furnaceConfig.setDriedKelpTarget(target)
                    ctx.mess("Set dried kelp block target: " .. target)
                    return
                end
                
                ctx.err("Unknown kelp subcommand: " .. kelpCmd)
                print("Use 'furnaces kelp' to see status")
                return
            end
            
            ctx.err("Unknown subcommand: " .. subCmd)
            ctx.mess("Use 'furnaces help' for available commands")
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"list", "discover", "add", "remove", "enable", "disable", "status", "targets", "recipes", "fuel", "lava", "kelp", "help"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) then
                        table.insert(matches, opt)
                    end
                end
                return matches
            elseif #args == 2 and args[1] == "fuel" then
                local query = (args[2] or ""):lower()
                local options = {"list", "add", "remove", "status"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) then
                        table.insert(matches, opt)
                    end
                end
                return matches
            elseif #args == 2 and args[1] == "lava" then
                local query = (args[2] or ""):lower()
                local options = {"enable", "disable", "input", "output"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) then
                        table.insert(matches, opt)
                    end
                end
                return matches
            elseif #args == 2 and args[1] == "kelp" then
                local query = (args[2] or ""):lower()
                local options = {"enable", "disable", "target"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) then
                        table.insert(matches, opt)
                    end
                end
                return matches
            elseif #args == 3 and args[1] == "lava" and (args[2] == "input" or args[2] == "output") then
                -- Complete peripheral names for lava chest config
                local query = (args[3] or ""):lower()
                local matches = {}
                for _, name in ipairs(peripheral.getNames()) do
                    if name:lower():find(query, 1, true) then
                        table.insert(matches, name)
                    end
                end
                return matches
            elseif #args == 2 and (args[1] == "remove" or args[1] == "enable" or args[1] == "disable") then
                -- Complete furnace names
                local query = (args[2] or ""):lower()
                local all = furnaceConfig.getAll()
                local matches = {}
                for name in pairs(all) do
                    if name:lower():find(query, 1, true) then
                        table.insert(matches, name)
                    end
                end
                return matches
            elseif #args == 2 and args[1] == "add" then
                -- Complete peripheral names for furnaces
                local query = (args[2] or ""):lower()
                local furnaceTypes = {"minecraft:furnace", "minecraft:blast_furnace", "minecraft:smoker", "furnace", "blast_furnace", "smoker"}
                local matches = {}
                for _, name in ipairs(peripheral.getNames()) do
                    if name:lower():find(query, 1, true) then
                        local types = {peripheral.getType(name)}
                        for _, t in ipairs(types) do
                            for _, furnaceType in ipairs(furnaceTypes) do
                                if t == furnaceType then
                                    table.insert(matches, name)
                                    break
                                end
                            end
                        end
                    end
                end
                return matches
            end
            return {}
        end
    },
    
    -- recipeprefs command removed - functionality merged into 'recipes' command
    -- Use: recipes prefs, recipes prefer, recipes enable, recipes disable, etc.
    
    reboot = {
        description = "Reboot connected turtles (crafters/workers)",
        category = "general",
        aliases = {"restart"},
        execute = function(args, ctx)
            -- Get all connected crafters and workers
            local allCrafters = crafterManager.getCrafters()
            local allWorkers = workerManager.getWorkers()
            
            -- Filter to online ones
            local onlineCrafters = {}
            local onlineWorkers = {}
            
            for _, c in ipairs(allCrafters) do
                if c.isOnline then
                    table.insert(onlineCrafters, c)
                end
            end
            
            for _, w in ipairs(allWorkers) do
                if w.isOnline then
                    table.insert(onlineWorkers, w)
                end
            end
            
            local totalOnline = #onlineCrafters + #onlineWorkers
            
            if totalOnline == 0 then
                ctx.mess("No online turtles to reboot")
                return
            end
            
            -- Create FormUI
            local form = FormUI.new("Reboot Turtles")
            
            -- Add checkboxes for crafters
            local crafterFields = {}
            if #onlineCrafters > 0 then
                form:label("=== Crafters ===")
                for _, c in ipairs(onlineCrafters) do
                    local label = string.format("#%d %s [%s]", c.id, c.label or "Crafter", c.status or "unknown")
                    crafterFields[c.id] = form:checkbox(label, true)
                end
            end
            
            -- Add checkboxes for workers
            local workerFields = {}
            if #onlineWorkers > 0 then
                form:label("=== Workers ===")
                for _, w in ipairs(onlineWorkers) do
                    local label = string.format("#%d %s [%s]", w.id, w.label or "Worker", w.status or "unknown")
                    workerFields[w.id] = form:checkbox(label, true)
                end
            end
            
            form:label("")
            form:addSubmitCancel("Reboot Selected", "Cancel")
            
            local result = form:run()
            
            if not result then
                ctx.mess("Reboot cancelled")
                return
            end
            
            -- Count selected and send reboot commands
            local rebooted = 0
            
            for id, field in pairs(crafterFields) do
                if field() then
                    -- Find the crafter and send reboot
                    for _, c in ipairs(onlineCrafters) do
                        if c.id == id and c.networkName then
                            comms.send(config.messageTypes.REBOOT, {}, c.networkName)
                            rebooted = rebooted + 1
                        end
                    end
                end
            end
            
            for id, field in pairs(workerFields) do
                if field() then
                    -- Find the worker and send reboot
                    for _, w in ipairs(onlineWorkers) do
                        if w.id == id and w.networkName then
                            comms.send(config.messageTypes.REBOOT, {}, w.networkName)
                            rebooted = rebooted + 1
                        end
                    end
                end
            end
            
            if rebooted > 0 then
                ctx.succ(string.format("Sent reboot command to %d turtle(s)", rebooted))
            else
                ctx.mess("No turtles selected for reboot")
            end
        end
    },
    
    update = {
        description = "Update the autocrafter from disk",
        category = "general",
        execute = function(args, ctx)
            ctx.mess("Running update...")
            shell.run("disk/update")
            
            -- Reboot all connected crafters
            ctx.mess("Rebooting crafters...")
            comms.broadcast(config.messageTypes.REBOOT, {})
            sleep(0.5)
            
            ctx.succ("Update complete. Restarting server...")
            sleep(0.5)
            os.reboot()
        end
    },
}

-- Register log level commands (loglevel, log-level, ll aliases)
logger.registerCommands(commands)

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
            chatTell(user, "\\deposit [items...] - Store items (excludes tools/armor/food)")
            chatTell(user, "\\deposit --all - Store ALL items (no excludes)")
            chatTell(user, "\\request <item> <count> [--smelt] - Request items")
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
                    local item, stock, matches = storageManager.resolveItem(itemQuery)
                    
                    if matches and #matches > 1 then
                        -- Ambiguous - show possible matches
                        chatTell(user, "Multiple items match '" .. itemQuery .. "':", true)
                        local shown = 0
                        for _, m in ipairs(matches) do
                            if shown >= 5 then
                                chatTell(user, "  ... and " .. (#matches - 5) .. " more")
                                break
                            end
                            chatTell(user, "  " .. m.item:gsub("minecraft:", "") .. " x" .. m.count)
                            shown = shown + 1
                        end
                    elseif not item or stock == 0 then
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
                -- Parse args: deposit [item1] [item2] ... or deposit --all
                local items = {}
                local depositAll = false
                local useExcludes = true
                
                if args then
                    for _, arg in ipairs(args) do
                        if arg == "--all" or arg == "-a" then
                            depositAll = true
                        elseif arg == "--no-exclude" or arg == "-n" then
                            useExcludes = false
                        else
                            local item = arg
                            if not item:find(":") then
                                item = "minecraft:" .. item
                            end
                            table.insert(items, item)
                        end
                    end
                end
                
                -- Get excludes from settings if depositing all
                local excludes = nil
                if useExcludes and (#items == 0 or depositAll) then
                    excludes = settings.getDepositExcludes()
                end
                
                local itemFilter = nil
                if #items > 0 and not depositAll then
                    itemFilter = #items == 1 and items[1] or items
                end
                
                local deposited, err = storageManager.depositFromPlayer(user, itemFilter, nil, excludes)
                
                if deposited > 0 then
                    if itemFilter then
                        if type(itemFilter) == "table" then
                            chatTell(user, string.format("Deposited %d items (filtered)", deposited))
                        else
                            chatTell(user, string.format("Deposited %dx %s", deposited, itemFilter:gsub("minecraft:", "")))
                        end
                    else
                        local msg = string.format("Deposited %d items", deposited)
                        if useExcludes and excludes and #excludes > 0 then
                            msg = msg .. " (some items excluded)"
                        end
                        chatTell(user, msg)
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
                local originalQuery = item
                if not item:find(":") then
                    item = "minecraft:" .. item
                end
                
                local allRecipes = recipes.getRecipesSorted(item, false)
                local activeRecipe = recipes.getRecipeFor(item)
                
                -- Try fuzzy matching if no recipes found
                if #allRecipes == 0 then
                    local resolvedItem, _, matches = storageManager.resolveItem(originalQuery)
                    if matches and #matches > 1 then
                        -- Ambiguous - show possible matches
                        chatTell(user, "Multiple items match '" .. originalQuery .. "':", true)
                        local shown = 0
                        for _, m in ipairs(matches) do
                            if shown >= 5 then
                                chatTell(user, "  ... and " .. (#matches - 5) .. " more")
                                break
                            end
                            chatTell(user, "  " .. m.item:gsub("minecraft:", ""))
                            shown = shown + 1
                        end
                        goto recipe_done
                    elseif resolvedItem then
                        item = resolvedItem
                        allRecipes = recipes.getRecipesSorted(item, false)
                        activeRecipe = recipes.getRecipeFor(item)
                    end
                end
                
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
                ::recipe_done::
            end
            
        elseif command == "request" then
            -- Handle request subcommands
            local subCmd = args and args[1] or nil
            
            if subCmd == "list" or subCmd == "ls" then
                local requests = requestManager.getActiveRequests()
                
                if #requests == 0 then
                    chatTell(user, "No active requests")
                else
                    chatTell(user, "=== Active Requests ===")
                    for _, req in ipairs(requests) do
                        local item = req.item:gsub("minecraft:", "")
                        local statusStr = requestManager.getStatusString(req)
                        chatTell(user, string.format("#%d: %dx %s [%s]", 
                            req.id, req.quantity, item, statusStr))
                    end
                end
                
            elseif subCmd == "status" then
                local id = args[2] and tonumber(args[2])
                if not id then
                    chatTell(user, "Usage: \\request status <id>", true)
                else
                    local req = requestManager.getRequest(id)
                    if not req then
                        chatTell(user, "Request #" .. id .. " not found", true)
                    else
                        chatTell(user, string.format("Request #%d: %dx %s", req.id, req.quantity, req.item:gsub("minecraft:", "")))
                        chatTell(user, "Status: " .. requestManager.getStatusString(req))
                        chatTell(user, string.format("Produced: %d, Delivered: %d", req.produced or 0, req.delivered or 0))
                    end
                end
                
            elseif subCmd == "cancel" then
                local id = args[2] and tonumber(args[2])
                if not id then
                    chatTell(user, "Usage: \\request cancel <id>", true)
                else
                    if requestManager.cancelRequest(id) then
                        chatTell(user, "Cancelled request #" .. id)
                    else
                        chatTell(user, "Could not cancel request #" .. id, true)
                    end
                end
                
            elseif not subCmd or subCmd == "help" then
                chatTell(user, "=== Request Commands ===")
                chatTell(user, "\\request <item> <count> [--smelt] - Request items")
                chatTell(user, "\\request list - View active requests")
                chatTell(user, "\\request status <id> - View request details")
                chatTell(user, "\\request cancel <id> - Cancel a request")
                
            else
                -- Create a new request - items go to player inventory
                local item = subCmd
                local count = args[2] and tonumber(args[2])
                
                -- Check for --smelt flag
                local isSmelt = false
                if args then
                    for _, arg in ipairs(args) do
                        if arg == "--smelt" or arg == "-s" then
                            isSmelt = true
                        end
                    end
                end
                
                if not count or count <= 0 then
                    chatTell(user, "Usage: \\request <item> <count> [--smelt]", true)
                else
                    if not item:find(":") then
                        item = "minecraft:" .. item
                    end
                    
                    -- Check if we have enough in stock already
                    local stock = storageManager.getAllStock()
                    local currentStock = stock[item] or 0
                    
                    -- Try to resolve fuzzy item names
                    if currentStock == 0 then
                        local resolvedItem, resolvedStock, matches = storageManager.resolveItem(subCmd)
                        if matches and #matches > 1 then
                            -- Ambiguous - show possible matches
                            chatTell(user, "Multiple items match '" .. subCmd .. "':", true)
                            local shown = 0
                            for _, m in ipairs(matches) do
                                if shown >= 5 then
                                    chatTell(user, "  ... and " .. (#matches - 5) .. " more")
                                    break
                                end
                                chatTell(user, "  " .. m.item:gsub("minecraft:", "") .. " x" .. m.count)
                                shown = shown + 1
                            end
                            goto continue
                        elseif resolvedItem then
                            item = resolvedItem
                            currentStock = stock[item] or 0
                        end
                    end
                    
                    -- If we already have enough in stock, just deliver immediately
                    if currentStock >= count and not isSmelt then
                        if storageManager.hasManipulator() then
                            local delivered = storageManager.withdrawToPlayer(item, count, user)
                            if delivered > 0 then
                                chatTell(user, string.format("Delivered %dx %s (from stock)", 
                                    delivered, item:gsub("minecraft:", "")))
                            else
                                chatTell(user, "Failed to deliver items", true)
                            end
                        else
                            chatTell(user, "No manipulator - items ready in storage", true)
                        end
                    else
                        -- Create a request to craft/smelt
                        local request, err = requestManager.createRequest(item, count, user, isSmelt)
                        
                        if not request then
                            chatTell(user, err or "Failed to create request", true)
                        else
                            local typeStr = isSmelt and "smelt" or "craft"
                            chatTell(user, string.format("Request #%d created: %s %dx %s", 
                                request.id, typeStr, count, item:gsub("minecraft:", "")))
                            chatTell(user, "You'll be notified when items are ready")
                        end
                    end
                end
                ::continue::
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
    furnaceManager.beforeShutdown()
    
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
        workerProcessLoop,
        serverAnnounceLoop,
        staleJobCleanupLoop,
        monitorRefreshLoop,
        exportProcessLoop,
        furnaceProcessLoop,
        requestProcessLoop,
        chatboxHandler,
        function()
            cmd("AutoCrafter", VERSION, commands)
        end
    )
end

-- Run main with crash protection
local success, err = pcall(main)
if not success then
    -- Log the crash
    local crashMsg = "Server crashed: " .. tostring(err)
    logger.critical(crashMsg)
    logger.flush()
    
    -- Display crash info
    term.setTextColor(colors.red)
    print("")
    print("=== AUTOCRAFTER CRASH ===")
    print(crashMsg)
    print("")
    print("Check log/crash.txt for details.")
    print("Press any key to exit...")
    term.setTextColor(colors.white)
    
    os.pullEvent("key")
    error(err)
end
