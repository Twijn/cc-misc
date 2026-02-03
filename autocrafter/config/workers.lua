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
---@field type string Task type (cobblestone, concrete, custom)
---@field enabled boolean Whether the task is active
---@field item string The item being generated
---@field stockTarget number Target stock level (generate when below this)
---@field stockThreshold number Start generating when stock falls below this threshold
---@field priority number Task priority (higher = more important)
---@field config table Additional task-specific configuration

---Worker task types and their default configurations
module.TASK_TYPES = {
    cobblestone = {
        description = "Cobblestone Generator",
        item = "minecraft:cobblestone",
        defaultThreshold = 1000,
        defaultTarget = 2000,
        -- breakDirection: front, up, down
        configFields = {"breakDirection"},
    },
    concrete = {
        description = "Concrete Powder -> Concrete",
        -- item: the concrete color to make (e.g., "minecraft:white_concrete")
        -- inputItem: the powder (e.g., "minecraft:white_concrete_powder")
        defaultThreshold = 64,
        defaultTarget = 256,
        configFields = {"inputItem", "breakDirection"},
    },
    crop_farm = {
        description = "Crop Farm (wheat, carrots, potatoes, beetroot, nether wart)",
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
    custom = {
        description = "Custom block breaking task",
        defaultThreshold = 64,
        defaultTarget = 256,
        configFields = {"item", "breakDirection"},
    },
}

---Get all task types
---@return table taskTypes
function module.getTaskTypes()
    return module.TASK_TYPES
end

---Add or update a task
---@param taskId string Unique task ID
---@param taskType string Task type (cobblestone, concrete, custom)
---@param config table Task configuration
function module.setTask(taskId, taskType, config)
    local tasks = workers.get("tasks") or {}
    
    local taskTypeInfo = module.TASK_TYPES[taskType]
    if not taskTypeInfo then
        logger.warn("Unknown task type: " .. taskType)
        return false
    end
    
    tasks[taskId] = {
        id = taskId,
        type = taskType,
        enabled = config.enabled ~= false,
        item = config.item or taskTypeInfo.item,
        stockTarget = config.stockTarget or taskTypeInfo.defaultTarget,
        stockThreshold = config.stockThreshold or taskTypeInfo.defaultThreshold,
        priority = config.priority or 0,
        config = config.config or {},
    }
    
    workers.set("tasks", tasks)
    logger.info(string.format("Set task %s: %s (%s)", taskId, taskType, config.item or taskTypeInfo.item or "custom"))
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
            table.insert(result, {
                task = task,
                currentStock = currentStock,
                needed = task.stockTarget - currentStock,
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
function module.registerWorker(workerId, label, taskId)
    local workerList = workers.get("workers") or {}
    workerList[tostring(workerId)] = {
        id = workerId,
        label = label or ("Worker " .. workerId),
        taskId = taskId,
        registered = os.epoch("utc"),
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
