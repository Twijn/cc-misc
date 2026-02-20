--- AutoCrafter Worker Configuration
--- Manages miscellaneous worker turtles for resource generation tasks.
--- Supports cobblestone generation, concrete generation, and other automated tasks.
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")

local workers = persist("worker-config.json")

workers.setDefault("workers", {})
workers.setDefault("tasks", {})

local module = {}

---@class WorkerTask
---@field id string Unique task identifier
---@field type string Task type (cobblegen, concrete, farming, blockbreak)
---@field enabled boolean Whether the task is active
---@field item string The item being generated
---@field stockTarget number Target stock level (generate when below this)
---@field stockThreshold number Start generating when stock falls below this threshold
---@field priority number Task priority (higher = more important)
---@field config table Additional task-specific configuration

---Worker task types and their default configurations
module.TASK_TYPES = {
    cobblegen = {
        label = "Cobblestone Generator",
        description = "Mines cobblestone from a generator",
        item = "minecraft:cobblestone",
        defaultThreshold = 1000,
        defaultTarget = 2000,
        -- breakDirection: front, up, down
        configFields = {"breakDirection"},
    },
    concrete = {
        label = "Concrete Maker",
        description = "Converts concrete powder to concrete via water",
        -- item: the concrete color to make (e.g., "minecraft:white_concrete")
        -- inputItem: the powder (e.g., "minecraft:white_concrete_powder")
        defaultThreshold = 64,
        defaultTarget = 256,
        configFields = {"inputItem", "breakDirection"},
    },
    farming = {
        label = "Crop Farm",
        description = "Grows and harvests crops (wheat, carrots, potatoes, beetroot, nether wart)",
        -- item: the crop to farm (e.g., "minecraft:wheat", "minecraft:carrot", "minecraft:potato")
        -- Uses bonemeal from storage to grow crops instantly on a single block
        -- Note: Nether wart cannot be bonemealed and must grow naturally
        defaultThreshold = 256,
        defaultTarget = 512,
        -- farmDirection: where the crop is planted (front, up, down - default: down)
        configFields = {"farmDirection"},
        -- Crop definitions contain: seed (plant item), block (planted block name),
        -- drop (harvested item), maxAge (mature age), canBonemeal (whether bonemeal works)
        validCrops = {
            -- Standard overworld crops (max age 7)
            ["minecraft:wheat"] = {
                seed = "minecraft:wheat_seeds",
                block = "minecraft:wheat",
                drop = "minecraft:wheat",
                maxAge = 7,
                canBonemeal = true,
            },
            ["minecraft:carrot"] = {
                seed = "minecraft:carrot",
                block = "minecraft:carrots",
                drop = "minecraft:carrot",
                maxAge = 7,
                canBonemeal = true,
            },
            ["minecraft:potato"] = {
                seed = "minecraft:potato",
                block = "minecraft:potatoes",
                drop = "minecraft:potato",
                maxAge = 7,
                canBonemeal = true,
            },
            -- Beetroot has max age 3
            ["minecraft:beetroot"] = {
                seed = "minecraft:beetroot_seeds",
                block = "minecraft:beetroots",
                drop = "minecraft:beetroot",
                maxAge = 3,
                canBonemeal = true,
            },
            -- Nether wart (grows on soul sand, no bonemeal)
            ["minecraft:nether_wart"] = {
                seed = "minecraft:nether_wart",
                block = "minecraft:nether_wart",
                drop = "minecraft:nether_wart",
                maxAge = 3,
                canBonemeal = false,
            },
        },
    },
    blockbreak = {
        label = "Block Breaker",
        description = "Generic block-breaking task for any block",
        defaultThreshold = 64,
        defaultTarget = 256,
        configFields = {"item", "breakDirection"},
    },
}

--- Legacy task type aliases (old name -> new name)
--- Used for backward compatibility when loading existing configs
module.TASK_TYPE_ALIASES = {
    cobblestone = "cobblegen",
    crop_farm = "farming",
    custom = "blockbreak",
    -- concrete stays the same
}

---Get all task types
---@return table taskTypes
function module.getTaskTypes()
    return module.TASK_TYPES
end

---Resolve a task type name, handling legacy aliases
---@param typeName string Task type name (may be legacy)
---@return string resolvedName The current task type name
---@return table|nil typeInfo The task type info, or nil if unknown
function module.resolveTaskType(typeName)
    local resolved = module.TASK_TYPE_ALIASES[typeName] or typeName
    return resolved, module.TASK_TYPES[resolved]
end

---Generate a clean task ID from type and item
---@param taskType string Task type
---@param item string Item name
---@return string taskId Clean task ID
function module.generateTaskId(taskType, item)
    local shortName = item:gsub("minecraft:", "")
    
    -- For cobblegen, just use "cobblegen" since item is always cobblestone
    if taskType == "cobblegen" then
        return "cobblegen"
    end
    
    -- For farming, use "<crop>_farm" (e.g., "wheat_farm")
    if taskType == "farming" then
        return shortName .. "_farm"
    end
    
    -- For concrete, just use the concrete name (e.g., "white_concrete")
    if taskType == "concrete" then
        return shortName
    end
    
    -- For blockbreak, use the item name
    return shortName
end

---Add or update a task
---@param taskId string Unique task ID
---@param taskType string Task type (cobblegen, concrete, farming, blockbreak)
---@param config table Task configuration
function module.setTask(taskId, taskType, config)
    local tasks = workers.get("tasks") or {}
    
    -- Resolve legacy task type names
    local resolvedType, taskTypeInfo = module.resolveTaskType(taskType)
    if not taskTypeInfo then
        logger.warn("Unknown task type: " .. taskType)
        return false
    end
    
    local stockTarget = config.stockTarget or taskTypeInfo.defaultTarget
    local stockThreshold = config.stockThreshold or taskTypeInfo.defaultThreshold
    
    -- Ensure threshold does not exceed target to prevent negative dispatch quantities.
    -- If threshold > target, clamp threshold to target.
    if stockThreshold > stockTarget then
        logger.warn(string.format("Task %s: threshold (%d) > target (%d), clamping threshold to target",
            taskId, stockThreshold, stockTarget))
        stockThreshold = stockTarget
    end
    
    tasks[taskId] = {
        id = taskId,
        type = resolvedType,
        enabled = config.enabled ~= false,
        item = config.item or taskTypeInfo.item,
        stockTarget = stockTarget,
        stockThreshold = stockThreshold,
        priority = config.priority or 0,
        config = config.config or {},
    }
    
    workers.set("tasks", tasks)
    logger.info(string.format("Set task %s: %s (%s)", taskId, resolvedType, config.item or taskTypeInfo.item or "custom"))
    return true
end

---Remove a task
---@param taskId string Task ID to remove
function module.removeTask(taskId)
    local tasks = workers.get("tasks") or {}
    if tasks[taskId] then
        tasks[taskId] = nil
        workers.set("tasks", tasks)
        logger.info(string.format("Removed task: %s", taskId))
    end
end

---Get a task by ID
---@param taskId string Task ID
---@return WorkerTask|nil task
function module.getTask(taskId)
    local tasks = workers.get("tasks") or {}
    return tasks[taskId]
end

---Get all tasks
---@return table<string, WorkerTask> tasks
function module.getAllTasks()
    return workers.get("tasks") or {}
end

---Get enabled tasks sorted by priority
---@return WorkerTask[] tasks
function module.getEnabledTasks()
    local tasks = workers.get("tasks") or {}
    local result = {}
    
    for _, task in pairs(tasks) do
        if task.enabled then
            table.insert(result, task)
        end
    end
    
    -- Sort by priority (highest first)
    table.sort(result, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)
    
    return result
end

---Get tasks that need work based on current stock levels
---@param stockLevels table Current stock levels
---@return WorkerTask[] tasks Tasks that are below threshold
function module.getTasksNeedingWork(stockLevels)
    local enabledTasks = module.getEnabledTasks()
    local result = {}
    
    for _, task in ipairs(enabledTasks) do
        local currentStock = stockLevels[task.item] or 0
        if currentStock < task.stockThreshold then
            -- Clamp needed to at least 1 to prevent negative quantities
            -- (can happen when stockThreshold > stockTarget and stock exceeds target)
            local needed = math.max(1, task.stockTarget - currentStock)
            table.insert(result, {
                task = task,
                currentStock = currentStock,
                needed = needed,
            })
        end
    end
    
    return result
end

---Enable or disable a task
---@param taskId string Task ID
---@param enabled boolean Whether to enable
function module.setTaskEnabled(taskId, enabled)
    local tasks = workers.get("tasks") or {}
    if tasks[taskId] then
        tasks[taskId].enabled = enabled
        workers.set("tasks", tasks)
        logger.info(string.format("%s task: %s", enabled and "Enabled" or "Disabled", taskId))
    end
end

---Count tasks
---@return number count
function module.count()
    local tasks = workers.get("tasks") or {}
    local count = 0
    for _ in pairs(tasks) do
        count = count + 1
    end
    return count
end

---Clear all tasks
function module.clearTasks()
    workers.set("tasks", {})
    logger.info("Cleared all worker tasks")
end

---Register a worker turtle
---@param workerId number Worker computer ID
---@param label? string Optional label
---@param taskId? string Optional assigned task
---@param capabilities? string[] Optional list of task types this worker can perform
function module.registerWorker(workerId, label, taskId, capabilities)
    local workerList = workers.get("workers") or {}
    local existing = workerList[tostring(workerId)]
    workerList[tostring(workerId)] = {
        id = workerId,
        label = label or (existing and existing.label) or ("Worker " .. workerId),
        taskId = taskId or (existing and existing.taskId),
        capabilities = capabilities or (existing and existing.capabilities) or {},
        registered = (existing and existing.registered) or os.epoch("utc"),
    }
    workers.set("workers", workerList)
    logger.info(string.format("Registered worker %d (%s)", workerId, label or ("Worker " .. workerId)))
end

---Unregister a worker turtle
---@param workerId number Worker computer ID
function module.unregisterWorker(workerId)
    local workerList = workers.get("workers") or {}
    workerList[tostring(workerId)] = nil
    workers.set("workers", workerList)
    logger.info(string.format("Unregistered worker %d", workerId))
end

---Get a worker by ID
---@param workerId number Worker computer ID
---@return table|nil worker
function module.getWorker(workerId)
    local workerList = workers.get("workers") or {}
    return workerList[tostring(workerId)]
end

---Get all workers
---@return table<string, table> workers
function module.getAllWorkers()
    return workers.get("workers") or {}
end

---Assign a task to a worker
---@param workerId number Worker computer ID
---@param taskId string Task ID to assign
function module.assignTask(workerId, taskId)
    local workerList = workers.get("workers") or {}
    if workerList[tostring(workerId)] then
        workerList[tostring(workerId)].taskId = taskId
        workers.set("workers", workerList)
        logger.info(string.format("Assigned task %s to worker %d", taskId, workerId))
    end
end

---Get a worker's capabilities
---@param workerId number Worker computer ID
---@return string[] capabilities List of task types this worker can perform
function module.getCapabilities(workerId)
    local workerList = workers.get("workers") or {}
    local worker = workerList[tostring(workerId)]
    if worker then
        return worker.capabilities or {}
    end
    return {}
end

---Set a worker's full capabilities list
---@param workerId number Worker computer ID
---@param capabilities string[] List of task types
function module.setCapabilities(workerId, capabilities)
    local workerList = workers.get("workers") or {}
    if workerList[tostring(workerId)] then
        workerList[tostring(workerId)].capabilities = capabilities
        workers.set("workers", workerList)
        logger.info(string.format("Set capabilities for worker %d: %s", workerId, table.concat(capabilities, ", ")))
    end
end

---Add a capability to a worker
---@param workerId number Worker computer ID
---@param taskType string Task type to add
---@return boolean added Whether it was added (false if already present)
function module.addCapability(workerId, taskType)
    local workerList = workers.get("workers") or {}
    local worker = workerList[tostring(workerId)]
    if not worker then return false end
    
    worker.capabilities = worker.capabilities or {}
    for _, cap in ipairs(worker.capabilities) do
        if cap == taskType then return false end
    end
    
    table.insert(worker.capabilities, taskType)
    workers.set("workers", workerList)
    logger.info(string.format("Added capability '%s' to worker %d", taskType, workerId))
    return true
end

---Remove a capability from a worker
---@param workerId number Worker computer ID
---@param taskType string Task type to remove
---@return boolean removed Whether it was removed
function module.removeCapability(workerId, taskType)
    local workerList = workers.get("workers") or {}
    local worker = workerList[tostring(workerId)]
    if not worker or not worker.capabilities then return false end
    
    for i, cap in ipairs(worker.capabilities) do
        if cap == taskType then
            table.remove(worker.capabilities, i)
            workers.set("workers", workerList)
            logger.info(string.format("Removed capability '%s' from worker %d", taskType, workerId))
            return true
        end
    end
    return false
end

---Check if a worker has a specific capability
---@param workerId number Worker computer ID
---@param taskType string Task type to check
---@return boolean hasCapability
function module.hasCapability(workerId, taskType)
    local caps = module.getCapabilities(workerId)
    for _, cap in ipairs(caps) do
        if cap == taskType then return true end
    end
    return false
end

---Get all workers that have a specific capability
---@param taskType string Task type to filter by
---@return table<string, table> workers Workers with this capability
function module.getWorkersWithCapability(taskType)
    local workerList = workers.get("workers") or {}
    local result = {}
    for id, worker in pairs(workerList) do
        local caps = worker.capabilities or {}
        for _, cap in ipairs(caps) do
            if cap == taskType then
                result[id] = worker
                break
            end
        end
    end
    return result
end

---Count workers
---@return number count
function module.countWorkers()
    local workerList = workers.get("workers") or {}
    local count = 0
    for _ in pairs(workerList) do
        count = count + 1
    end
    return count
end

return module
