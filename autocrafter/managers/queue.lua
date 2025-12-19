--- AutoCrafter Queue Manager
--- Manages the crafting job queue.
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")
local recipes = require("lib.recipes")
local craftingLib = require("lib.crafting")

local manager = {}

local queueData = persist("queue.json")
local jobHistory = persist("job-history.json")

-- Queue states
local STATES = {
    PENDING = "pending",
    ASSIGNED = "assigned",
    CRAFTING = "crafting",
    COMPLETED = "completed",
    FAILED = "failed",
}

manager.STATES = STATES

---Initialize the queue manager
function manager.init()
    queueData.setDefault("jobs", {})
    queueData.setDefault("nextId", 1)
    jobHistory.setDefault("completed", {})
    jobHistory.setDefault("failed", {})
    logger.info("Queue manager initialized")
end

---Add a job to the queue
---@param output string The output item to craft
---@param quantity number How many to craft
---@param stockLevels table Current stock levels
---@return table|nil job The created job or nil
---@return string|nil error Error message if failed
function manager.addJob(output, quantity, stockLevels)
    local recipe = recipes.getRecipeFor(output)
    if not recipe then
        return nil, "No recipe found for " .. output
    end
    
    local job, missing = craftingLib.createJob(recipe, quantity, stockLevels)
    if not job then
        local missingStr = ""
        for _, m in ipairs(missing or {}) do
            missingStr = missingStr .. string.format("\n  %s: need %d, have %d", m.item, m.needed, m.have)
        end
        return nil, "Missing materials:" .. missingStr
    end
    
    -- Assign sequential ID
    local nextId = queueData.get("nextId") or 1
    job.id = nextId
    queueData.set("nextId", nextId + 1)
    
    -- Add to queue
    local jobs = queueData.get("jobs") or {}
    table.insert(jobs, job)
    queueData.set("jobs", jobs)
    
    logger.info(string.format("Added job #%d: craft %dx %s", job.id, job.expectedOutput, output))
    
    return job
end

---Get the next pending job
---@return table|nil job The next pending job or nil
function manager.getNextJob()
    local jobs = queueData.get("jobs") or {}
    
    for _, job in ipairs(jobs) do
        if job.status == STATES.PENDING then
            return job
        end
    end
    
    return nil
end

---Assign a job to a crafter
---@param jobId number The job ID
---@param crafterId number The crafter computer ID
---@return boolean success Whether the job was assigned
function manager.assignJob(jobId, crafterId)
    local jobs = queueData.get("jobs") or {}
    
    for i, job in ipairs(jobs) do
        if job.id == jobId and job.status == STATES.PENDING then
            jobs[i].status = STATES.ASSIGNED
            jobs[i].assignedTo = crafterId
            jobs[i].assignedAt = os.epoch("utc")
            queueData.set("jobs", jobs)
            
            logger.info(string.format("Job #%d assigned to crafter %d", jobId, crafterId))
            return true
        end
    end
    
    return false
end

---Update job status to crafting
---@param jobId number The job ID
function manager.startCrafting(jobId)
    local jobs = queueData.get("jobs") or {}
    
    for i, job in ipairs(jobs) do
        if job.id == jobId then
            jobs[i].status = STATES.CRAFTING
            jobs[i].startedAt = os.epoch("utc")
            queueData.set("jobs", jobs)
            return
        end
    end
end

---Mark a job as completed
---@param jobId number The job ID
---@param actualOutput? number Actual items crafted
function manager.completeJob(jobId, actualOutput)
    local jobs = queueData.get("jobs") or {}
    local completed = jobHistory.get("completed") or {}
    
    for i, job in ipairs(jobs) do
        if job.id == jobId then
            job.status = STATES.COMPLETED
            job.completedAt = os.epoch("utc")
            job.actualOutput = actualOutput or job.expectedOutput
            
            -- Move to history
            table.insert(completed, 1, job)
            -- Keep last 100 completed jobs
            while #completed > 100 do
                table.remove(completed)
            end
            
            -- Remove from queue
            table.remove(jobs, i)
            
            -- Use batch mode for multiple file writes
            queueData.beginBatch()
            queueData.setBatch("jobs", jobs)
            queueData.endBatch()
            
            jobHistory.beginBatch()
            jobHistory.setBatch("completed", completed)
            jobHistory.endBatch()
            
            logger.info(string.format("Job #%d completed: crafted %d items", jobId, job.actualOutput))
            return
        end
    end
    
    -- Job not found - log warning
    logger.warn(string.format("Job #%d not found in queue for completion", jobId))
end

---Mark a job as failed
---@param jobId number The job ID
---@param reason? string Failure reason
function manager.failJob(jobId, reason)
    local jobs = queueData.get("jobs") or {}
    local failed = jobHistory.get("failed") or {}
    
    for i, job in ipairs(jobs) do
        if job.id == jobId then
            job.status = STATES.FAILED
            job.failedAt = os.epoch("utc")
            job.failReason = reason or "Unknown error"
            
            -- Move to history
            table.insert(failed, 1, job)
            while #failed > 100 do
                table.remove(failed)
            end
            
            -- Remove from queue
            table.remove(jobs, i)
            
            -- Use batch mode for multiple file writes
            queueData.beginBatch()
            queueData.setBatch("jobs", jobs)
            queueData.endBatch()
            
            jobHistory.beginBatch()
            jobHistory.setBatch("failed", failed)
            jobHistory.endBatch()
            
            logger.warn(string.format("Job #%d failed: %s", jobId, reason or "Unknown"))
            return
        end
    end
    
    -- Job not found - log warning
    logger.warn(string.format("Job #%d not found in queue for failure marking", jobId))
end

---Get all jobs in queue
---@return table jobs Array of jobs
function manager.getJobs()
    return queueData.get("jobs") or {}
end

---Get job by ID
---@param jobId number The job ID
---@return table|nil job The job or nil
function manager.getJob(jobId)
    local jobs = queueData.get("jobs") or {}
    for _, job in ipairs(jobs) do
        if job.id == jobId then
            return job
        end
    end
    return nil
end

---Get queue statistics
---@return table stats Queue statistics
function manager.getStats()
    local jobs = queueData.get("jobs") or {}
    local completed = jobHistory.get("completed") or {}
    local failed = jobHistory.get("failed") or {}
    
    local stats = {
        pending = 0,
        assigned = 0,
        crafting = 0,
        total = #jobs,
        completedToday = 0,
        failedToday = 0,
    }
    
    for _, job in ipairs(jobs) do
        if job.status == STATES.PENDING then
            stats.pending = stats.pending + 1
        elseif job.status == STATES.ASSIGNED then
            stats.assigned = stats.assigned + 1
        elseif job.status == STATES.CRAFTING then
            stats.crafting = stats.crafting + 1
        end
    end
    
    -- Count today's jobs
    local today = os.epoch("utc") - (24 * 60 * 60 * 1000)
    for _, job in ipairs(completed) do
        if job.completedAt and job.completedAt > today then
            stats.completedToday = stats.completedToday + 1
        end
    end
    for _, job in ipairs(failed) do
        if job.failedAt and job.failedAt > today then
            stats.failedToday = stats.failedToday + 1
        end
    end
    
    return stats
end

---Clear all jobs from queue
function manager.clearQueue()
    queueData.set("jobs", {})
    logger.info("Queue cleared")
end

---Cancel a specific job
---@param jobId number The job ID
---@return boolean success Whether the job was cancelled
function manager.cancelJob(jobId)
    local jobs = queueData.get("jobs") or {}
    
    for i, job in ipairs(jobs) do
        if job.id == jobId and job.status == STATES.PENDING then
            table.remove(jobs, i)
            queueData.set("jobs", jobs)
            logger.info(string.format("Job #%d cancelled", jobId))
            return true
        end
    end
    
    return false
end

---Get job history
---@param historyType? string "completed" or "failed" (nil for both)
---@return table history Job history
function manager.getHistory(historyType)
    if historyType == "completed" then
        return jobHistory.get("completed") or {}
    elseif historyType == "failed" then
        return jobHistory.get("failed") or {}
    else
        return {
            completed = jobHistory.get("completed") or {},
            failed = jobHistory.get("failed") or {},
        }
    end
end

return manager
