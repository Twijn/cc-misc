--- AutoCrafter Queue Manager
--- Manages the crafting job queue with dependency tree support.
--- Jobs can have child jobs (dependencies) that must complete before the parent can start.
---
---@version 2.0.0

local persist = require("lib.persist")
local logger = require("lib.log")
local recipes = require("lib.recipes")
local craftingLib = require("lib.crafting")

local manager = {}

local queueData = persist("queue.json")
local jobHistory = persist("job-history.json")

-- Queue states
local STATES = {
    PENDING = "pending",      -- Ready to be assigned (no unfinished children)
    WAITING = "waiting",      -- Waiting for child jobs to complete
    ASSIGNED = "assigned",    -- Assigned to a crafter
    CRAFTING = "crafting",    -- Currently being crafted
    COMPLETED = "completed",  -- Successfully completed
    FAILED = "failed",        -- Failed to craft
}

manager.STATES = STATES

-- Maximum recursion depth for dependency resolution
local MAX_DEPTH = 10

---Get the next ID and increment
---@return number id The next available ID
local function getNextId()
    local nextId = queueData.get("nextId") or 1
    queueData.set("nextId", nextId + 1)
    return nextId
end

---Update waiting jobs to pending if their children are complete
function manager.updateWaitingJobs()
    local jobs = queueData.get("jobs") or {}
    local modified = false
    local jobsById = {}
    
    -- Index jobs by ID for fast lookup
    for _, job in ipairs(jobs) do
        jobsById[job.id] = job
    end
    
    -- Check completed jobs in history
    local completed = jobHistory.get("completed") or {}
    local completedIds = {}
    for _, job in ipairs(completed) do
        completedIds[job.id] = true
    end
    
    -- Check each waiting job
    for i, job in ipairs(jobs) do
        if job.status == STATES.WAITING then
            local allChildrenDone = true
            local anyChildFailed = false
            
            for _, childId in ipairs(job.childIds or {}) do
                local child = jobsById[childId]
                if child then
                    -- Child still in queue
                    if child.status ~= STATES.COMPLETED then
                        allChildrenDone = false
                    end
                    if child.status == STATES.FAILED then
                        anyChildFailed = true
                    end
                elseif not completedIds[childId] then
                    -- Child not in queue and not in completed history
                    -- Check failed history
                    local failed = jobHistory.get("failed") or {}
                    for _, fj in ipairs(failed) do
                        if fj.id == childId then
                            anyChildFailed = true
                            break
                        end
                    end
                    if not anyChildFailed then
                        allChildrenDone = completedIds[childId]
                    end
                end
            end
            
            if anyChildFailed then
                -- Mark this job as failed too
                jobs[i].status = STATES.FAILED
                jobs[i].failReason = "Child job failed"
                modified = true
                logger.warn(string.format("Job #%d failed: child job failed", job.id))
            elseif allChildrenDone then
                -- All children complete, this job can proceed
                jobs[i].status = STATES.PENDING
                modified = true
                logger.info(string.format("Job #%d ready: all %d children completed", 
                    job.id, #(job.childIds or {})))
            end
        end
    end
    
    if modified then
        queueData.set("jobs", jobs)
    end
end

---Initialize the queue manager
function manager.init()
    queueData.setDefault("jobs", {})
    queueData.setDefault("nextId", 1)
    jobHistory.setDefault("completed", {})
    jobHistory.setDefault("failed", {})
    
    -- Clean up any jobs with missing recipe data (can happen after server restart)
    local jobs = queueData.get("jobs") or {}
    local validJobs = {}
    local removedCount = 0
    
    for _, job in ipairs(jobs) do
        if job.recipe and job.recipe.output and job.recipe.ingredients then
            table.insert(validJobs, job)
        else
            logger.warn(string.format("Removing invalid job #%d (missing recipe data)", job.id or 0))
            removedCount = removedCount + 1
        end
    end
    
    if removedCount > 0 then
        queueData.set("jobs", validJobs)
        logger.info(string.format("Cleaned up %d invalid jobs from queue", removedCount))
    end
    
    -- Update any waiting jobs that may now be ready
    manager.updateWaitingJobs()
    
    logger.info("Queue manager initialized (v2.0 with dependency trees)")
end

---Create a job object (internal, doesn't save)
---@param recipe table The recipe
---@param quantity number How many to craft
---@param stockLevels table Current stock levels
---@param parentId? number Parent job ID if this is a child job
---@param rootId? number Root job ID for the entire tree
---@param depth? number Current depth in the tree
---@return table|nil job The job object or nil
---@return table|nil missing Missing materials if job can't be created
local function createJobObject(recipe, quantity, stockLevels, parentId, rootId, depth)
    depth = depth or 0
    
    local job, missing = craftingLib.createJob(recipe, quantity, stockLevels)
    if not job then
        return nil, missing
    end
    
    -- Add tree tracking fields
    job.id = getNextId()
    job.parentId = parentId
    job.rootId = rootId or job.id  -- Root jobs reference themselves
    job.childIds = {}
    job.depth = depth
    job.status = STATES.PENDING
    
    return job
end

---Recursively create jobs for an item and its dependencies
---@param output string The output item to craft
---@param quantity number How many to craft
---@param stockLevels table Current stock levels (modified in place)
---@param parentId? number Parent job ID
---@param rootId? number Root job ID
---@param depth? number Current recursion depth
---@param visited? table Items being processed (cycle detection)
---@return table|nil rootJob The root job of the created tree, or nil
---@return string|nil error Error message if failed
---@return table|nil allJobs All jobs created (for batch saving)
function manager.createJobTree(output, quantity, stockLevels, parentId, rootId, depth, visited)
    depth = depth or 0
    visited = visited or {}
    
    -- Check recursion limit
    if depth > MAX_DEPTH then
        return nil, "Maximum crafting depth exceeded for " .. output
    end
    
    -- Check for circular dependencies
    if visited[output] then
        return nil, "Circular dependency detected for " .. output
    end
    visited[output] = true
    
    -- Check if we already have enough in stock
    local currentStock = stockLevels[output] or 0
    local needed = quantity - currentStock
    if needed <= 0 then
        logger.debug(string.format("Already have %d/%d %s in stock", currentStock, quantity, output))
        visited[output] = nil
        return nil, nil  -- Not an error, just not needed
    end
    
    -- Get recipe
    local recipe = recipes.getRecipeFor(output)
    if not recipe then
        visited[output] = nil
        return nil, "No recipe found for " .. output
    end
    
    -- Check what materials we have and what's missing
    local hasMats, missing = craftingLib.hasMaterials(recipe, stockLevels, needed)
    
    local allJobs = {}
    local childIds = {}
    
    -- If missing materials, try to create child jobs for them
    if not hasMats and missing then
        for _, m in ipairs(missing) do
            local matItem = m.item
            local matNeeded = m.short
            
            -- Check if this material can be crafted
            local matRecipe = recipes.getRecipeFor(matItem)
            if matRecipe then
                logger.debug(string.format("Creating child job for %dx %s (needed by %s)", 
                    matNeeded, matItem, output))
                
                -- Recursively create jobs for the missing material
                local childJob, childErr, childJobs = manager.createJobTree(
                    matItem, 
                    matNeeded, 
                    stockLevels, 
                    nil,  -- parentId set after we create parent
                    rootId,
                    depth + 1,
                    visited
                )
                
                if childErr then
                    logger.debug(string.format("Cannot craft dependency %s: %s", matItem, childErr))
                    -- Continue - maybe we can still craft with what we have
                elseif childJob then
                    -- Add child jobs to our collection
                    for _, cj in ipairs(childJobs or {}) do
                        table.insert(allJobs, cj)
                    end
                    table.insert(childIds, childJob.id)
                    
                    -- Update stock optimistically with expected output
                    stockLevels[matItem] = (stockLevels[matItem] or 0) + childJob.expectedOutput
                end
            else
                -- Check if it can be smelted (for future support)
                logger.debug(string.format("No recipe for dependency %s", matItem))
            end
        end
    end
    
    -- Now try to create the main job with (hopefully) updated stock
    local job, stillMissing = createJobObject(recipe, needed, stockLevels, parentId, rootId, depth)
    
    if not job then
        -- Still can't create the job
        if #childIds > 0 then
            -- We created child jobs, so create a "waiting" job that will become ready later
            -- Force create with partial materials - the actual crafting happens after children complete
            job = {
                id = getNextId(),
                recipe = recipe,
                crafts = math.ceil(needed / (recipe.outputCount or 1)),
                expectedOutput = math.ceil(needed / (recipe.outputCount or 1)) * (recipe.outputCount or 1),
                materials = {},
                resolvedItems = {},
                status = STATES.WAITING,
                created = os.epoch("utc"),
                parentId = parentId,
                rootId = rootId,
                childIds = childIds,
                depth = depth,
                waitingFor = {},  -- Track what we're waiting for
            }
            
            -- Calculate required materials
            for _, ingredient in ipairs(recipe.ingredients) do
                local item = ingredient.item
                job.materials[item] = (job.materials[item] or 0) + (ingredient.count * job.crafts)
            end
            
            -- Track what materials we're waiting for
            for _, m in ipairs(stillMissing or {}) do
                table.insert(job.waitingFor, {item = m.item, needed = m.short})
            end
        else
            -- No children and still missing materials - this is a real failure
            local missingStr = ""
            for _, m in ipairs(stillMissing or {}) do
                missingStr = missingStr .. string.format("\n  %s: need %d, have %d", m.item, m.needed, m.have)
            end
            visited[output] = nil
            return nil, "Missing materials:" .. missingStr
        end
    else
        -- Job created successfully
        job.childIds = childIds
        if #childIds > 0 then
            job.status = STATES.WAITING
        end
    end
    
    -- Set rootId if this is the root
    if not rootId then
        job.rootId = job.id
        -- Update all child jobs with correct rootId
        for _, cj in ipairs(allJobs) do
            cj.rootId = job.id
        end
    end
    
    -- Update parent references in children
    for _, cj in ipairs(allJobs) do
        for _, childId in ipairs(childIds) do
            if cj.id == childId then
                cj.parentId = job.id
            end
        end
    end
    
    -- Reserve materials from stock
    for mat, count in pairs(job.materials or {}) do
        stockLevels[mat] = (stockLevels[mat] or 0) - count
        if stockLevels[mat] < 0 then stockLevels[mat] = 0 end
    end
    
    -- Add optimistic output
    stockLevels[output] = (stockLevels[output] or 0) + job.expectedOutput
    
    -- Add this job to the collection
    table.insert(allJobs, job)
    
    visited[output] = nil
    return job, nil, allJobs
end

---Add a job to the queue with automatic dependency resolution
---@param output string The output item to craft
---@param quantity number How many to craft
---@param stockLevels table Current stock levels
---@param source? string Source of the request (e.g., "target", "request", "manual")
---@return table|nil job The root job or nil
---@return string|nil error Error message if failed
function manager.addJob(output, quantity, stockLevels, source)
    -- Create a copy of stock levels so we don't modify the original
    local stockCopy = {}
    for k, v in pairs(stockLevels) do stockCopy[k] = v end
    
    -- Create the job tree
    local rootJob, err, allJobs = manager.createJobTree(output, quantity, stockCopy)
    
    if not rootJob then
        return nil, err
    end
    
    -- Ensure allJobs is valid
    allJobs = allJobs or {rootJob}
    
    -- Add source tracking
    rootJob.source = source or "manual"
    
    -- Save all jobs to queue
    local jobs = queueData.get("jobs") or {}
    for _, job in ipairs(allJobs) do
        table.insert(jobs, job)
    end
    queueData.set("jobs", jobs)
    
    local childCount = #allJobs - 1
    if childCount > 0 then
        logger.info(string.format("Added job #%d: craft %dx %s (with %d dependency jobs)", 
            rootJob.id, rootJob.expectedOutput, output, childCount))
    else
        logger.info(string.format("Added job #%d: craft %dx %s", 
            rootJob.id, rootJob.expectedOutput, output))
    end
    
    return rootJob
end

---Get the next pending job (no waiting children)
---@return table|nil job The next pending job or nil
function manager.getNextJob()
    -- First, update any waiting jobs that may be ready
    manager.updateWaitingJobs()
    
    local jobs = queueData.get("jobs") or {}
    
    for _, job in ipairs(jobs) do
        if job.status == STATES.PENDING then
            -- Validate job has required recipe data before returning
            if job.recipe and job.recipe.output and job.recipe.ingredients then
                return job
            else
                logger.warn(string.format("Skipping job #%d with invalid recipe data", job.id or 0))
            end
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
            
            -- Check if any waiting jobs can now proceed
            manager.updateWaitingJobs()
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
            
            -- Update waiting jobs (parent might fail too)
            manager.updateWaitingJobs()
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

---Get job by ID (checks both queue and history)
---@param jobId number The job ID
---@return table|nil job The job or nil
function manager.getJob(jobId)
    local jobs = queueData.get("jobs") or {}
    for _, job in ipairs(jobs) do
        if job.id == jobId then
            return job
        end
    end
    
    -- Check completed history
    local completed = jobHistory.get("completed") or {}
    for _, job in ipairs(completed) do
        if job.id == jobId then
            return job
        end
    end
    
    -- Check failed history
    local failed = jobHistory.get("failed") or {}
    for _, job in ipairs(failed) do
        if job.id == jobId then
            return job
        end
    end
    
    return nil
end

---Get all jobs for a root job (the entire tree)
---@param rootId number The root job ID
---@return table jobs Array of jobs in the tree
function manager.getJobTree(rootId)
    local jobs = queueData.get("jobs") or {}
    local tree = {}
    
    for _, job in ipairs(jobs) do
        if job.rootId == rootId or job.id == rootId then
            table.insert(tree, job)
        end
    end
    
    -- Also check history
    local completed = jobHistory.get("completed") or {}
    for _, job in ipairs(completed) do
        if job.rootId == rootId or job.id == rootId then
            table.insert(tree, job)
        end
    end
    
    local failed = jobHistory.get("failed") or {}
    for _, job in ipairs(failed) do
        if job.rootId == rootId or job.id == rootId then
            table.insert(tree, job)
        end
    end
    
    -- Sort by depth (children first)
    table.sort(tree, function(a, b) return (a.depth or 0) > (b.depth or 0) end)
    
    return tree
end

---Get job tree status summary
---@param rootId number The root job ID
---@return table status Status summary
function manager.getJobTreeStatus(rootId)
    local tree = manager.getJobTree(rootId)
    local status = {
        total = #tree,
        pending = 0,
        waiting = 0,
        assigned = 0,
        crafting = 0,
        completed = 0,
        failed = 0,
        items = {},  -- Items being crafted and their status
    }
    
    for _, job in ipairs(tree) do
        local s = job.status
        if s == STATES.PENDING then status.pending = status.pending + 1
        elseif s == STATES.WAITING then status.waiting = status.waiting + 1
        elseif s == STATES.ASSIGNED then status.assigned = status.assigned + 1
        elseif s == STATES.CRAFTING then status.crafting = status.crafting + 1
        elseif s == STATES.COMPLETED then status.completed = status.completed + 1
        elseif s == STATES.FAILED then status.failed = status.failed + 1
        end
        
        -- Track items
        local output = job.recipe and job.recipe.output or "unknown"
        status.items[output] = status.items[output] or {pending = 0, done = 0, total = 0}
        status.items[output].total = status.items[output].total + (job.expectedOutput or 0)
        if s == STATES.COMPLETED then
            status.items[output].done = status.items[output].done + (job.actualOutput or job.expectedOutput or 0)
        else
            status.items[output].pending = status.items[output].pending + (job.expectedOutput or 0)
        end
    end
    
    return status
end

---Get human-readable status for a job tree
---@param rootId number The root job ID
---@return string status Status string
function manager.getJobTreeStatusString(rootId)
    local status = manager.getJobTreeStatus(rootId)
    
    if status.total == 0 then
        return "No jobs"
    end
    
    if status.failed > 0 then
        return string.format("Failed (%d/%d jobs)", status.failed, status.total)
    end
    
    if status.completed == status.total then
        return "Complete"
    end
    
    local active = status.assigned + status.crafting
    local waiting = status.waiting + status.pending
    
    if active > 0 then
        return string.format("Crafting (%d/%d done, %d active)", 
            status.completed, status.total, active)
    elseif waiting > 0 then
        return string.format("Queued (%d/%d done, %d pending)", 
            status.completed, status.total, waiting)
    else
        return string.format("In progress (%d/%d done)", status.completed, status.total)
    end
end

---Get queue statistics
---@return table stats Queue statistics
function manager.getStats()
    local jobs = queueData.get("jobs") or {}
    local completed = jobHistory.get("completed") or {}
    local failed = jobHistory.get("failed") or {}
    
    local stats = {
        pending = 0,
        waiting = 0,
        assigned = 0,
        crafting = 0,
        total = #jobs,
        completedToday = 0,
        failedToday = 0,
        rootJobs = 0,
        childJobs = 0,
    }
    
    for _, job in ipairs(jobs) do
        if job.status == STATES.PENDING then
            stats.pending = stats.pending + 1
        elseif job.status == STATES.WAITING then
            stats.waiting = stats.waiting + 1
        elseif job.status == STATES.ASSIGNED then
            stats.assigned = stats.assigned + 1
        elseif job.status == STATES.CRAFTING then
            stats.crafting = stats.crafting + 1
        end
        
        if job.parentId then
            stats.childJobs = stats.childJobs + 1
        else
            stats.rootJobs = stats.rootJobs + 1
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

---Cancel a specific job (and its children)
---@param jobId number The job ID
---@param cancelChildren? boolean Whether to cancel child jobs too (default: true)
---@return boolean success Whether the job was cancelled
function manager.cancelJob(jobId, cancelChildren)
    if cancelChildren == nil then cancelChildren = true end
    
    local jobs = queueData.get("jobs") or {}
    local cancelled = false
    
    -- Find the job to cancel
    local jobToCancel = nil
    for i, job in ipairs(jobs) do
        if job.id == jobId and (job.status == STATES.PENDING or job.status == STATES.WAITING) then
            jobToCancel = job
            break
        end
    end
    
    if not jobToCancel then
        return false
    end
    
    -- Cancel children first if requested
    if cancelChildren and jobToCancel.childIds then
        for _, childId in ipairs(jobToCancel.childIds) do
            manager.cancelJob(childId, true)
        end
        -- Reload jobs after cancelling children
        jobs = queueData.get("jobs") or {}
    end
    
    -- Find and remove this job (index may have changed)
    for j, jj in ipairs(jobs) do
        if jj.id == jobId then
            table.remove(jobs, j)
            cancelled = true
            break
        end
    end
    
    if cancelled then
        queueData.set("jobs", jobs)
        logger.info(string.format("Job #%d cancelled", jobId))
    end
    
    return cancelled
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

---Reset stale assigned or crafting jobs back to pending
---@param timeoutMs number Timeout in milliseconds
---@return number count Number of jobs reset
function manager.resetStaleJobs(timeoutMs)
    local jobs = queueData.get("jobs") or {}
    local now = os.epoch("utc")
    local resetCount = 0
    local modified = false
    
    for i, job in ipairs(jobs) do
        if job.status == STATES.ASSIGNED or job.status == STATES.CRAFTING then
            local assignedAt = job.assignedAt or job.startedAt or 0
            local age = now - assignedAt
            
            if age > timeoutMs then
                logger.warn(string.format("Resetting stale job #%d (status: %s, age: %.1fs)", 
                    job.id, job.status, age / 1000))
                jobs[i].status = STATES.PENDING
                jobs[i].assignedTo = nil
                jobs[i].assignedAt = nil
                jobs[i].startedAt = nil
                resetCount = resetCount + 1
                modified = true
            end
        end
    end
    
    if modified then
        queueData.set("jobs", jobs)
    end
    
    return resetCount
end

return manager
