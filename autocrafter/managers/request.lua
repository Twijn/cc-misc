--- AutoCrafter Request Manager
--- Manages one-time crafting/smelting requests with status tracking.
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")
local recipes = require("lib.recipes")
local queueManager = require("managers.queue")

local manager = {}

local requestData = persist("requests.json")

-- Request states
local STATES = {
    PENDING = "pending",      -- Request created, waiting for jobs to be queued
    QUEUED = "queued",        -- Jobs have been queued
    CRAFTING = "crafting",    -- Jobs are being processed
    SMELTING = "smelting",    -- Smelting in progress (for smelt requests)
    READY = "ready",          -- Items are ready for delivery
    DELIVERED = "delivered",  -- Items delivered to player/storage
    FAILED = "failed",        -- Request failed
    CANCELLED = "cancelled",  -- Request was cancelled
}

manager.STATES = STATES

---Initialize the request manager
function manager.init()
    requestData.setDefault("requests", {})
    requestData.setDefault("nextId", 1)
    logger.info("Request manager initialized")
end

---Create a new request
---@param item string The item to craft/smelt
---@param quantity number How many to produce
---@param deliverTo string "storage" or player username
---@param isSmelt? boolean Whether this is a smelt request
---@return table|nil request The created request or nil
---@return string|nil error Error message if failed
function manager.createRequest(item, quantity, deliverTo, isSmelt)
    -- Validate the request
    if isSmelt then
        -- Check if item can be smelted
        local furnaceConfig = require("config.furnaces")
        local input = furnaceConfig.getSmeltInput(item)
        if not input then
            return nil, "No smelting recipe found for " .. item
        end
    else
        -- Check if item can be crafted
        local recipe = recipes.getRecipeFor(item)
        if not recipe then
            return nil, "No crafting recipe found for " .. item
        end
    end
    
    local nextId = requestData.get("nextId") or 1
    
    local request = {
        id = nextId,
        item = item,
        quantity = quantity,
        deliverTo = deliverTo,
        isSmelt = isSmelt or false,
        status = STATES.PENDING,
        createdAt = os.epoch("utc"),
        jobIds = {},           -- Job IDs created for this request
        produced = 0,          -- Items produced so far
        delivered = 0,         -- Items delivered so far
        lastUpdate = os.epoch("utc"),
        lastReportAt = 0,      -- Last time we sent a status report
    }
    
    requestData.set("nextId", nextId + 1)
    
    local requests = requestData.get("requests") or {}
    table.insert(requests, request)
    requestData.set("requests", requests)
    
    logger.info(string.format("Created request #%d: %dx %s (deliver to: %s, smelt: %s)",
        request.id, quantity, item, deliverTo, tostring(isSmelt)))
    
    return request
end

---Get a request by ID
---@param requestId number The request ID
---@return table|nil request The request or nil
function manager.getRequest(requestId)
    local requests = requestData.get("requests") or {}
    for _, req in ipairs(requests) do
        if req.id == requestId then
            return req
        end
    end
    return nil
end

---Get all active requests (not delivered, failed, or cancelled)
---@return table requests Array of active requests
function manager.getActiveRequests()
    local requests = requestData.get("requests") or {}
    local active = {}
    for _, req in ipairs(requests) do
        if req.status ~= STATES.DELIVERED and 
           req.status ~= STATES.FAILED and 
           req.status ~= STATES.CANCELLED then
            table.insert(active, req)
        end
    end
    return active
end

---Get all requests
---@return table requests Array of all requests
function manager.getAllRequests()
    return requestData.get("requests") or {}
end

---Update a request's status
---@param requestId number The request ID
---@param status string The new status
---@param updates? table Additional fields to update
---@return boolean success Whether the update succeeded
function manager.updateRequest(requestId, status, updates)
    local requests = requestData.get("requests") or {}
    
    for i, req in ipairs(requests) do
        if req.id == requestId then
            requests[i].status = status
            requests[i].lastUpdate = os.epoch("utc")
            
            if updates then
                for k, v in pairs(updates) do
                    requests[i][k] = v
                end
            end
            
            requestData.set("requests", requests)
            logger.debug(string.format("Request #%d status updated to: %s", requestId, status))
            return true
        end
    end
    
    return false
end

---Add job ID to a request
---@param requestId number The request ID
---@param jobId number The job ID to add
function manager.addJobToRequest(requestId, jobId)
    local requests = requestData.get("requests") or {}
    
    for i, req in ipairs(requests) do
        if req.id == requestId then
            requests[i].jobIds = requests[i].jobIds or {}
            table.insert(requests[i].jobIds, jobId)
            requests[i].lastUpdate = os.epoch("utc")
            requestData.set("requests", requests)
            logger.debug(string.format("Added job #%d to request #%d", jobId, requestId))
            return
        end
    end
end

---Record items produced for a request
---@param requestId number The request ID
---@param count number Number of items produced
function manager.recordProduced(requestId, count)
    local requests = requestData.get("requests") or {}
    
    for i, req in ipairs(requests) do
        if req.id == requestId then
            requests[i].produced = (requests[i].produced or 0) + count
            requests[i].lastUpdate = os.epoch("utc")
            requestData.set("requests", requests)
            return
        end
    end
end

---Record items delivered for a request
---@param requestId number The request ID
---@param count number Number of items delivered
function manager.recordDelivered(requestId, count)
    local requests = requestData.get("requests") or {}
    
    for i, req in ipairs(requests) do
        if req.id == requestId then
            requests[i].delivered = (requests[i].delivered or 0) + count
            requests[i].lastUpdate = os.epoch("utc")
            requestData.set("requests", requests)
            return
        end
    end
end

---Mark last report time for a request
---@param requestId number The request ID
function manager.markReported(requestId)
    local requests = requestData.get("requests") or {}
    
    for i, req in ipairs(requests) do
        if req.id == requestId then
            requests[i].lastReportAt = os.epoch("utc")
            requestData.set("requests", requests)
            return
        end
    end
end

---Check if a request needs a status report
---@param request table The request
---@param intervalMs number Minimum interval between reports in milliseconds
---@return boolean needsReport Whether a report should be sent
function manager.needsReport(request, intervalMs)
    local now = os.epoch("utc")
    local lastReport = request.lastReportAt or 0
    return (now - lastReport) >= intervalMs
end

---Cancel a request
---@param requestId number The request ID
---@return boolean success Whether the request was cancelled
function manager.cancelRequest(requestId)
    local requests = requestData.get("requests") or {}
    
    for i, req in ipairs(requests) do
        if req.id == requestId then
            if req.status == STATES.DELIVERED or req.status == STATES.CANCELLED then
                return false  -- Already complete or cancelled
            end
            
            requests[i].status = STATES.CANCELLED
            requests[i].lastUpdate = os.epoch("utc")
            requestData.set("requests", requests)
            
            -- Cancel associated jobs if possible
            for _, jobId in ipairs(req.jobIds or {}) do
                queueManager.cancelJob(jobId)
            end
            
            logger.info(string.format("Request #%d cancelled", requestId))
            return true
        end
    end
    
    return false
end

---Clean up old completed/failed/cancelled requests
---@param maxAge number Maximum age in milliseconds
function manager.cleanup(maxAge)
    local requests = requestData.get("requests") or {}
    local now = os.epoch("utc")
    local cleaned = {}
    local removedCount = 0
    
    for _, req in ipairs(requests) do
        local age = now - (req.lastUpdate or req.createdAt or 0)
        local isComplete = req.status == STATES.DELIVERED or 
                          req.status == STATES.FAILED or 
                          req.status == STATES.CANCELLED
        
        if not isComplete or age < maxAge then
            table.insert(cleaned, req)
        else
            removedCount = removedCount + 1
        end
    end
    
    if removedCount > 0 then
        requestData.set("requests", cleaned)
        logger.info(string.format("Cleaned up %d old requests", removedCount))
    end
end

---Get stats about requests
---@return table stats Request statistics
function manager.getStats()
    local requests = requestData.get("requests") or {}
    local stats = {
        total = #requests,
        pending = 0,
        queued = 0,
        crafting = 0,
        smelting = 0,
        ready = 0,
        delivered = 0,
        failed = 0,
        cancelled = 0,
    }
    
    for _, req in ipairs(requests) do
        if stats[req.status] then
            stats[req.status] = stats[req.status] + 1
        end
    end
    
    return stats
end

---Get request status as a human-readable string
---@param request table The request
---@return string status Human-readable status
function manager.getStatusString(request)
    local status = request.status
    local produced = request.produced or 0
    local quantity = request.quantity
    
    if status == STATES.PENDING then
        return "Pending"
    elseif status == STATES.QUEUED then
        return "Queued"
    elseif status == STATES.CRAFTING then
        return string.format("Crafting (%d/%d)", produced, quantity)
    elseif status == STATES.SMELTING then
        return string.format("Smelting (%d/%d)", produced, quantity)
    elseif status == STATES.READY then
        return string.format("Ready (%d items)", produced)
    elseif status == STATES.DELIVERED then
        return string.format("Delivered (%d items)", request.delivered or 0)
    elseif status == STATES.FAILED then
        return "Failed: " .. (request.failReason or "Unknown")
    elseif status == STATES.CANCELLED then
        return "Cancelled"
    else
        return status
    end
end

---Recursively queue jobs for an item and its dependencies
---@param item string The item to craft
---@param quantity number How many to produce
---@param stockLevels table Current stock levels (will be modified)
---@param requestId number The request ID to associate jobs with
---@param depth? number Current recursion depth (default 0)
---@param visited? table Items already being processed (to prevent cycles)
---@return table jobs Array of job IDs queued
---@return string|nil error Error message if failed
function manager.queueRecursive(item, quantity, stockLevels, requestId, depth, visited)
    depth = depth or 0
    visited = visited or {}
    
    local MAX_DEPTH = 10  -- Prevent infinite recursion
    if depth > MAX_DEPTH then
        return {}, "Maximum crafting depth exceeded"
    end
    
    -- Prevent circular dependencies
    if visited[item] then
        return {}, "Circular dependency detected for " .. item
    end
    visited[item] = true
    
    local jobs = {}
    local craftingLib = require("lib.crafting")
    
    -- Check current stock
    local currentStock = stockLevels[item] or 0
    local needed = quantity - currentStock
    
    if needed <= 0 then
        -- Already have enough in stock
        logger.debug(string.format("Request #%d: already have %d/%d %s", 
            requestId, currentStock, quantity, item))
        return jobs, nil
    end
    
    -- Get recipe for the item
    local recipe = recipes.getRecipeFor(item)
    if not recipe then
        return {}, "No recipe found for " .. item
    end
    
    -- Calculate how many crafts we need
    local outputCount = recipe.outputCount or 1
    local craftsNeeded = math.ceil(needed / outputCount)
    
    -- Check what materials we're missing
    local _, missing = craftingLib.hasMaterials(recipe, stockLevels, needed)
    
    -- Try to recursively craft any missing materials
    if missing and #missing > 0 then
        for _, m in ipairs(missing) do
            local missingItem = m.item
            local missingAmount = m.short
            
            -- Check if this material can be crafted
            local matRecipe = recipes.getRecipeFor(missingItem)
            if matRecipe then
                logger.debug(string.format("Request #%d: need to craft %dx %s for %s", 
                    requestId, missingAmount, missingItem, item))
                
                -- Recursively queue jobs for the missing material
                local subJobs, subErr = manager.queueRecursive(
                    missingItem, 
                    missingAmount, 
                    stockLevels, 
                    requestId, 
                    depth + 1,
                    visited
                )
                
                if subErr then
                    -- Can't craft this material
                    logger.debug(string.format("Request #%d: cannot craft %s: %s", 
                        requestId, missingItem, subErr))
                else
                    -- Add sub-jobs to our list
                    for _, jobId in ipairs(subJobs) do
                        table.insert(jobs, jobId)
                    end
                end
            else
                -- Material has no recipe, check if it can be smelted
                local furnaceConfig = require("config.furnaces")
                local smeltInput = furnaceConfig.getSmeltInput(missingItem)
                if smeltInput then
                    logger.debug(string.format("Request #%d: %s can be smelted from %s", 
                        requestId, missingItem, smeltInput))
                    -- Note: We don't queue smelt jobs here, furnace manager handles that
                    -- Just mark that we need smelting
                end
            end
        end
    end
    
    -- Now try to queue the main job with updated stock levels
    local job, err = queueManager.addJob(item, needed, stockLevels)
    if job then
        table.insert(jobs, job.id)
        manager.addJobToRequest(requestId, job.id)
        
        -- Update stock levels to reflect materials used
        for mat, count in pairs(job.materials or {}) do
            stockLevels[mat] = (stockLevels[mat] or 0) - count
        end
        
        -- Add expected output to stock (optimistically, for dependent items)
        stockLevels[item] = (stockLevels[item] or 0) + job.expectedOutput
        
        logger.debug(string.format("Request #%d: queued job #%d for %dx %s (depth %d)", 
            requestId, job.id, job.expectedOutput, item, depth))
    else
        -- Still can't craft - might need to wait for sub-jobs to complete
        if #jobs > 0 then
            logger.debug(string.format("Request #%d: queued %d sub-jobs, will retry %s later", 
                requestId, #jobs, item))
        else
            return {}, err or ("Cannot craft " .. item)
        end
    end
    
    -- Clear visited for this item so it can be crafted again if needed
    visited[item] = nil
    
    return jobs, nil
end

---Check if all jobs for a request are complete and queue more if needed
---@param request table The request to check
---@param stockLevels table Current stock levels
---@return boolean complete Whether all required items are ready
---@return string|nil status Status message
function manager.checkAndQueueMore(request, stockLevels)
    local currentStock = stockLevels[request.item] or 0
    
    -- If we have enough, we're done
    if currentStock >= request.quantity then
        return true, "Ready"
    end
    
    -- Check if there are pending/active jobs
    local pendingJobs = 0
    for _, jobId in ipairs(request.jobIds or {}) do
        local job = queueManager.getJob(jobId)
        if job then
            pendingJobs = pendingJobs + 1
        end
    end
    
    -- If no pending jobs but we don't have enough, try to queue more
    if pendingJobs == 0 then
        local needed = request.quantity - currentStock
        if needed > 0 then
            local jobs, err = manager.queueRecursive(
                request.item,
                needed,
                stockLevels,
                request.id,
                0,
                {}
            )
            
            if #jobs > 0 then
                return false, string.format("Queued %d more jobs", #jobs)
            elseif err then
                return false, err
            end
        end
    end
    
    return false, string.format("Waiting (%d jobs pending)", pendingJobs)
end

return manager
