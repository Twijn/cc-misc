--- AutoCrafter Crafter Coordination Manager
--- Manages connected crafter turtles.
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")
local comms = require("lib.comms")
local config = require("config")

local manager = {}

local crafterData = persist("crafters.json")
local crafters = {}
local crafterTimeout = 60

---Initialize the crafter manager
function manager.init()
    crafterData.setDefault("registered", {})
    crafterTimeout = config.crafterTimeout or 60
    
    -- Load registered crafters
    local registered = crafterData.get("registered") or {}
    for id, data in pairs(registered) do
        crafters[tonumber(id)] = {
            id = tonumber(id),
            label = data.label,
            status = "offline",
            lastSeen = 0,
            currentJob = nil,
        }
    end
    
    logger.info("Crafter manager initialized")
end

---Register a new crafter
---@param crafterId number The crafter's computer ID
---@param label? string Optional label
function manager.register(crafterId, label)
    crafters[crafterId] = {
        id = crafterId,
        label = label or ("Crafter " .. crafterId),
        status = "idle",
        lastSeen = os.epoch("utc"),
        currentJob = nil,
    }
    
    -- Save to persistent storage
    local registered = crafterData.get("registered") or {}
    registered[tostring(crafterId)] = {
        label = label or ("Crafter " .. crafterId),
    }
    crafterData.set("registered", registered)
    
    logger.info(string.format("Registered crafter %d (%s)", crafterId, crafters[crafterId].label))
end

---Update crafter status
---@param crafterId number The crafter's computer ID
---@param status string The new status
---@param jobId? number Optional current job ID
function manager.updateStatus(crafterId, status, jobId)
    if crafters[crafterId] then
        crafters[crafterId].status = status
        crafters[crafterId].lastSeen = os.epoch("utc")
        crafters[crafterId].currentJob = jobId
    else
        -- Auto-register unknown crafters
        manager.register(crafterId)
        manager.updateStatus(crafterId, status, jobId)
    end
end

---Get an idle crafter
---@return table|nil crafter An idle crafter or nil
function manager.getIdleCrafter()
    local now = os.epoch("utc")
    
    for _, crafter in pairs(crafters) do
        -- Check if crafter is online and idle
        if crafter.status == "idle" then
            local age = (now - crafter.lastSeen) / 1000
            if age < crafterTimeout then
                return crafter
            end
        end
    end
    
    return nil
end

---Get all crafters
---@return table crafters Array of crafter info
function manager.getCrafters()
    local result = {}
    local now = os.epoch("utc")
    
    for _, crafter in pairs(crafters) do
        local age = (now - crafter.lastSeen) / 1000
        local status = crafter.status
        
        -- Mark as offline if not seen recently
        if age >= crafterTimeout then
            status = "offline"
        end
        
        table.insert(result, {
            id = crafter.id,
            label = crafter.label,
            status = status,
            lastSeen = crafter.lastSeen,
            currentJob = crafter.currentJob,
            isOnline = age < crafterTimeout,
        })
    end
    
    table.sort(result, function(a, b)
        return a.id < b.id
    end)
    
    return result
end

---Get crafter by ID
---@param crafterId number The crafter ID
---@return table|nil crafter The crafter info or nil
function manager.getCrafter(crafterId)
    return crafters[crafterId]
end

---Send a craft request to a crafter
---@param crafterId number The crafter ID
---@param job table The crafting job
---@return boolean sent Whether the request was sent
function manager.sendCraftRequest(crafterId, job)
    if not comms.isConnected() then
        logger.error("Cannot send craft request: no modem")
        return false
    end
    
    comms.send(config.messageTypes.CRAFT_REQUEST, {
        job = job,
    }, crafterId)
    
    logger.debug(string.format("Sent craft request for job #%d to crafter %d", job.id, crafterId))
    return true
end

---Remove a crafter
---@param crafterId number The crafter ID
function manager.removeCrafter(crafterId)
    crafters[crafterId] = nil
    
    local registered = crafterData.get("registered") or {}
    registered[tostring(crafterId)] = nil
    crafterData.set("registered", registered)
    
    logger.info(string.format("Removed crafter %d", crafterId))
end

---Get crafter statistics
---@return table stats Crafter statistics
function manager.getStats()
    local total = 0
    local online = 0
    local idle = 0
    local busy = 0
    local now = os.epoch("utc")
    
    for _, crafter in pairs(crafters) do
        total = total + 1
        local age = (now - crafter.lastSeen) / 1000
        
        if age < crafterTimeout then
            online = online + 1
            if crafter.status == "idle" then
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

---Handle incoming messages from crafters
---@param message table The received message
function manager.handleMessage(message)
    if not message or not message.type or not message.sender then
        return
    end
    
    local crafterId = message.sender
    local data = message.data or {}
    
    if message.type == config.messageTypes.PONG then
        -- Crafter responding to ping
        local newStatus = data.status or "idle"
        local wasIdle = crafters[crafterId] and crafters[crafterId].status == "idle"
        manager.updateStatus(crafterId, newStatus, data.currentJob)
        -- Signal if crafter just became idle
        if newStatus == "idle" and not wasIdle then
            return { type = "crafter_idle", crafterId = crafterId }
        end
        
    elseif message.type == config.messageTypes.STATUS then
        -- Status update from crafter
        local newStatus = data.status or "idle"
        local wasIdle = crafters[crafterId] and crafters[crafterId].status == "idle"
        manager.updateStatus(crafterId, newStatus, data.currentJob)
        -- Signal if crafter just became idle
        if newStatus == "idle" and not wasIdle then
            return { type = "crafter_idle", crafterId = crafterId }
        end
        
    elseif message.type == config.messageTypes.CRAFT_COMPLETE then
        -- Crafting completed
        manager.updateStatus(crafterId, "idle", nil)
        return {
            type = "craft_complete",
            jobId = data.jobId,
            actualOutput = data.actualOutput,
        }
        
    elseif message.type == config.messageTypes.CRAFT_FAILED then
        -- Crafting failed
        manager.updateStatus(crafterId, "idle", nil)
        return {
            type = "craft_failed",
            jobId = data.jobId,
            reason = data.reason,
        }
    end
    
    return nil
end

---Send ping to all crafters
function manager.pingAll()
    if comms.isConnected() then
        comms.broadcast(config.messageTypes.PING, {})
    end
end

---Shutdown handler
function manager.beforeShutdown()
    logger.info("Crafter manager shutting down")
end

return manager
