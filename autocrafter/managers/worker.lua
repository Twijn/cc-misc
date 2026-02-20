--- AutoCrafter Worker Manager
--- Manages connected worker turtles for miscellaneous resource generation tasks.
--- Workers are similar to crafters but perform simple block-breaking tasks.
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")
local comms = require("lib.comms")
local config = require("config")
local workerConfig = require("config.workers")

local manager = {}

-- Live worker state (not persisted, rebuilt from heartbeats)
local workers = {}
local workerTimeout = 60

---Initialize the worker manager
function manager.init()
    workerTimeout = config.crafterTimeout or 60  -- Reuse crafter timeout setting
    
    -- Load registered workers
    local registered = workerConfig.getAllWorkers()
    for id, data in pairs(registered) do
        workers[tonumber(id)] = {
            id = tonumber(id),
            label = data.label,
            taskId = data.taskId,
            capabilities = data.capabilities or {},
            status = "offline",
            lastSeen = 0,
            stats = {},
        }
    end
    
    logger.info("Worker manager initialized")
end

---Update worker status
---@param workerId number Worker's computer ID
---@param status string The new status (idle, working, offline)
---@param stats? table Optional statistics from worker
---@param progress? table Optional progress info from worker
function manager.updateStatus(workerId, status, stats, progress)
    if workers[workerId] then
        workers[workerId].status = status
        workers[workerId].lastSeen = os.epoch("utc")
        if stats then
            workers[workerId].stats = stats
        end
        if progress then
            workers[workerId].progress = progress
        else
            workers[workerId].progress = nil
        end
    else
        -- Auto-register unknown workers (with no capabilities by default)
        workerConfig.registerWorker(workerId)
        workers[workerId] = {
            id = workerId,
            label = "Worker " .. workerId,
            taskId = nil,
            capabilities = {},
            status = status,
            lastSeen = os.epoch("utc"),
            stats = stats or {},
            progress = progress,
        }
    end
end

---Get an idle worker that has a specific capability
---@param taskType? string Required task type capability (nil = any idle worker)
---@return table|nil worker An idle worker with the capability, or nil
function manager.getIdleWorker(taskType)
    local now = os.epoch("utc")
    
    for _, worker in pairs(workers) do
        if worker.status == "idle" then
            local age = (now - worker.lastSeen) / 1000
            if age < workerTimeout then
                -- If no task type filter, return any idle worker
                if not taskType then
                    return worker
                end
                
                -- Check if worker has the required capability
                local caps = worker.capabilities or {}
                for _, cap in ipairs(caps) do
                    if cap == taskType then
                        return worker
                    end
                end
            end
        end
    end
    
    return nil
end

---Get all workers
---@return table[] workers Array of worker info
function manager.getWorkers()
    local result = {}
    local now = os.epoch("utc")
    
    for _, worker in pairs(workers) do
        local age = (now - worker.lastSeen) / 1000
        local status = worker.status
        
        if age >= workerTimeout then
            status = "offline"
        end
        
        table.insert(result, {
            id = worker.id,
            label = worker.label,
            taskId = worker.taskId,
            capabilities = worker.capabilities or {},
            status = status,
            lastSeen = worker.lastSeen,
            stats = worker.stats,
            progress = worker.progress,
            isOnline = age < workerTimeout,
        })
    end
    
    table.sort(result, function(a, b)
        return a.id < b.id
    end)
    
    return result
end

---Get worker by ID
---@param workerId number The worker ID
---@return table|nil worker The worker info or nil
function manager.getWorker(workerId)
    return workers[workerId]
end

---Send a work request to a worker
---@param workerId number The worker ID
---@param task table The task to perform
---@param quantity number How many items to generate
---@return boolean sent Whether the request was sent
function manager.sendWorkRequest(workerId, task, quantity)
    if not comms.isConnected() then
        logger.error("Cannot send work request: no modem")
        return false
    end
    
    comms.send(config.messageTypes.WORK_REQUEST, {
        task = task,
        quantity = quantity,
    }, workerId)
    
    logger.debug(string.format("Sent work request for task %s to worker %d (qty: %d)", 
        task.id, workerId, quantity))
    return true
end

---Handle incoming messages from workers
---@param message table The received message
---@return table|nil result Action result if any
function manager.handleMessage(message)
    if not message or not message.type or not message.sender then
        return nil
    end
    
    local workerId = message.sender
    local data = message.data or {}
    
    if message.type == config.messageTypes.WORKER_PONG then
        -- Worker responding to ping
        local newStatus = data.status or "idle"
        local wasIdle = workers[workerId] and workers[workerId].status == "idle"
        manager.updateStatus(workerId, newStatus, data.stats, data.progress)
        
        -- Update task assignment if provided
        if data.taskId and workers[workerId] then
            workers[workerId].taskId = data.taskId
        end
        
        -- Signal if worker just became idle
        if newStatus == "idle" and not wasIdle then
            return { type = "worker_idle", workerId = workerId }
        end
        
    elseif message.type == config.messageTypes.WORKER_STATUS then
        -- Status update from worker
        local newStatus = data.status or "idle"
        local wasIdle = workers[workerId] and workers[workerId].status == "idle"
        manager.updateStatus(workerId, newStatus, data.stats, data.progress)
        
        if newStatus == "idle" and not wasIdle then
            return { type = "worker_idle", workerId = workerId }
        end
        
    elseif message.type == config.messageTypes.WORK_COMPLETE then
        -- Work completed
        manager.updateStatus(workerId, "idle", data.stats)
        return {
            type = "work_complete",
            workerId = workerId,
            taskId = data.taskId,
            produced = data.produced,
        }
        
    elseif message.type == config.messageTypes.WORK_FAILED then
        -- Work failed
        manager.updateStatus(workerId, "idle", data.stats)
        return {
            type = "work_failed",
            workerId = workerId,
            taskId = data.taskId,
            reason = data.reason,
        }
    end
    
    return nil
end

---Get worker statistics
---@return table stats Worker statistics
function manager.getStats()
    local total = 0
    local online = 0
    local idle = 0
    local busy = 0
    local now = os.epoch("utc")
    
    for _, worker in pairs(workers) do
        total = total + 1
        local age = (now - worker.lastSeen) / 1000
        
        if age < workerTimeout then
            online = online + 1
            if worker.status == "idle" then
                idle = idle + 1
            else
                busy = busy + 1
            end
        end
    end
    
    return {
        total = total,
        online = online,
        offline = total - online,
        idle = idle,
        busy = busy,
    }
end

---Ping all workers
function manager.pingAll()
    if comms.isConnected() then
        comms.broadcast(config.messageTypes.WORKER_PING, {})
    end
end

---Dispatch work to idle workers based on stock levels
---Only dispatches tasks to workers that have the matching capability
---@param stockLevels table Current stock levels
---@return number dispatched Number of work requests dispatched
function manager.dispatchWork(stockLevels)
    local tasksNeedingWork = workerConfig.getTasksNeedingWork(stockLevels)
    local dispatched = 0
    
    for _, taskInfo in ipairs(tasksNeedingWork) do
        -- Find an idle worker that has the capability for this task type
        local worker = manager.getIdleWorker(taskInfo.task.type)
        if not worker then
            -- No worker with this capability is idle, skip this task
            goto nextTask
        end
        
        -- Calculate batch size (don't request more than needed)
        local batchSize = math.min(taskInfo.needed, 64)  -- Max 64 per batch
        
        if manager.sendWorkRequest(worker.id, taskInfo.task, batchSize) then
            workers[worker.id].status = "working"
            workers[worker.id].taskId = taskInfo.task.id
            dispatched = dispatched + 1
            
            logger.debug(string.format("Dispatched %s to worker %d (need %d, batch %d)",
                taskInfo.task.id, worker.id, taskInfo.needed, batchSize))
        end
        
        ::nextTask::
    end
    
    return dispatched
end

---Remove a worker
---@param workerId number The worker ID
function manager.removeWorker(workerId)
    workers[workerId] = nil
    workerConfig.unregisterWorker(workerId)
    logger.info(string.format("Removed worker %d", workerId))
end

---Shutdown handler
function manager.beforeShutdown()
    logger.info("Worker manager shutting down")
end

return manager
