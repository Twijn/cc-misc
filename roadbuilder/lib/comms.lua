--- Wireless Communications Library for RBC
--- Handles all modem communication between turtles and controller
---
---@version 1.0.0
-- @module comms

local module = {}

-- Message types
module.MSG_TYPE = {
    -- Controller -> Turtle commands
    PING = "ping",
    COMMAND = "command",
    CONFIG = "config",
    STOP = "stop",
    
    -- Turtle -> Controller responses
    PONG = "pong",
    STATUS = "status",
    ACK = "ack",
    ERROR = "error",
    COMPLETE = "complete",
}

-- Command types
module.COMMANDS = {
    BUILD_FORWARD = "build_forward",
    BUILD_BACKWARD = "build_backward",
    MOVE_UP = "move_up",
    MOVE_DOWN = "move_down",
    TURN_LEFT = "turn_left",
    TURN_RIGHT = "turn_right",
    SET_WIDTH = "set_width",
    SET_BLOCK = "set_block",
    REFILL = "refill",
    DEPOSIT = "deposit",
    GO_HOME = "go_home",
    SET_HOME = "set_home",
}

-- Internal state
local modem = nil
local channel = 4521
local replyChannel = 4522
local deviceId = os.getComputerID()
local deviceLabel = os.getComputerLabel() or ("Device-" .. deviceId)
local isController = not turtle
local messageHandlers = {}
local connectedTurtles = {}

-- Debug mode - set to true to see all messages
module.DEBUG = false

local function debugLog(msg)
    if module.DEBUG then
        local timestamp = string.format("[%.2f]", os.epoch("utc") / 1000 % 1000)
        print(timestamp .. " [COMMS] " .. msg)
    end
end

---Initialize the communications module
---@param config table Configuration with CHANNEL and REPLY_CHANNEL
---@return boolean success True if modem found and opened
function module.init(config)
    if config then
        channel = config.CHANNEL or channel
        replyChannel = config.REPLY_CHANNEL or replyChannel
    end
    
    debugLog("Initializing comms...")
    debugLog("Device ID: " .. deviceId .. ", Label: " .. deviceLabel)
    debugLog("Is controller: " .. tostring(isController))
    debugLog("Channel: " .. channel .. ", Reply: " .. replyChannel)
    
    -- Find wireless modem
    local allModems = {peripheral.find("modem")}
    debugLog("Found " .. #allModems .. " modem(s) total")
    
    for i, m in ipairs(allModems) do
        local name = peripheral.getName(m)
        local wireless = m.isWireless and m.isWireless() or false
        debugLog("  Modem " .. i .. ": " .. name .. " (wireless: " .. tostring(wireless) .. ")")
    end
    
    modem = peripheral.find("modem", function(name, wrapped)
        -- Check if it's a wireless modem
        if wrapped.isWireless then
            return wrapped.isWireless()
        end
        -- Fallback: assume it's wireless if we can't check
        return true
    end)
    
    -- If no modem found with filter, try finding any modem
    if not modem then
        debugLog("No wireless modem found, trying any modem...")
        modem = peripheral.find("modem")
    end
    
    if not modem then
        debugLog("ERROR: No modem found!")
        return false
    end
    
    local modemName = peripheral.getName(modem)
    local isWireless = modem.isWireless and modem.isWireless() or "unknown"
    debugLog("Using modem: " .. modemName .. " (wireless: " .. tostring(isWireless) .. ")")
    
    -- Open channels - both devices listen on both channels for reliability
    modem.open(channel)
    modem.open(replyChannel)
    debugLog("Opened channels " .. channel .. " and " .. replyChannel)
    
    return true
end

---Check if communications are ready
---@return boolean ready True if modem is available
function module.isReady()
    return modem ~= nil
end

---Get the modem peripheral
---@return table|nil modem The modem peripheral or nil
function module.getModem()
    return modem
end

---Get device ID
---@return number id Computer ID
function module.getDeviceId()
    return deviceId
end

---Get device label
---@return string label Computer label
function module.getDeviceLabel()
    return deviceLabel
end

---Send a message to all listeners
---@param msgType string Message type from MSG_TYPE
---@param data table Additional data to send
---@param targetId number|nil Specific target device ID (nil for broadcast)
function module.send(msgType, data, targetId)
    if not modem then 
        debugLog("SEND FAILED: No modem!")
        return false 
    end
    
    local message = {
        type = msgType,
        senderId = deviceId,
        senderLabel = deviceLabel,
        targetId = targetId,
        timestamp = os.epoch("utc"),
        data = data or {},
    }
    
    local targetChannel = isController and channel or replyChannel
    local sendChannel = isController and replyChannel or channel
    
    debugLog("SEND: " .. msgType .. " -> ch" .. targetChannel .. (targetId and (" to #" .. targetId) or " (broadcast)"))
    
    modem.transmit(targetChannel, sendChannel, message)
    return true
end

---Send a command to a specific turtle
---@param turtleId number Target turtle ID
---@param command string Command from COMMANDS
---@param params table|nil Command parameters
function module.sendCommand(turtleId, command, params)
    return module.send(module.MSG_TYPE.COMMAND, {
        command = command,
        params = params or {},
    }, turtleId)
end

---Send status update (turtle -> controller)
---@param status table Status data (position, fuel, inventory, etc.)
function module.sendStatus(status)
    return module.send(module.MSG_TYPE.STATUS, status)
end

---Send acknowledgment
---@param originalMsgType string The message type being acknowledged
---@param targetId number Target device ID
function module.sendAck(originalMsgType, targetId)
    return module.send(module.MSG_TYPE.ACK, {
        acknowledging = originalMsgType,
    }, targetId)
end

---Send error message
---@param errorMsg string Error description
---@param targetId number|nil Target device ID
function module.sendError(errorMsg, targetId)
    return module.send(module.MSG_TYPE.ERROR, {
        error = errorMsg,
    }, targetId)
end

---Send completion message
---@param command string Command that was completed
---@param result table|nil Result data
---@param targetId number|nil Target device ID
function module.sendComplete(command, result, targetId)
    return module.send(module.MSG_TYPE.COMPLETE, {
        command = command,
        result = result or {},
    }, targetId)
end

---Register a message handler
---@param msgType string Message type to handle
---@param handler function(message, senderId, senderLabel) Handler function
function module.onMessage(msgType, handler)
    if not messageHandlers[msgType] then
        messageHandlers[msgType] = {}
    end
    table.insert(messageHandlers[msgType], handler)
end

---Process a received message
---@param message table The received message
local function processMessage(message)
    -- Validate message structure
    if type(message) ~= "table" or not message.type then
        debugLog("RECV: Invalid message (not a table or no type)")
        debugLog("  -> Received type: " .. type(message))
        if type(message) == "string" then
            debugLog("  -> String content: " .. message:sub(1, 100))
        elseif type(message) == "table" then
            debugLog("  -> Table keys: " .. textutils.serialize(message):sub(1, 200))
        else
            debugLog("  -> Value: " .. tostring(message))
        end
        return
    end
    
    debugLog("RECV: " .. message.type .. " from #" .. (message.senderId or "?") .. " (" .. (message.senderLabel or "?") .. ")")
    
    -- Check if message is for us
    if message.targetId and message.targetId ~= deviceId then
        debugLog("  -> Ignored (target: #" .. message.targetId .. ", we are #" .. deviceId .. ")")
        return
    end
    
    -- Track connected turtles (for controller)
    if isController and message.senderId then
        debugLog("  -> Tracking turtle #" .. message.senderId)
        connectedTurtles[message.senderId] = {
            id = message.senderId,
            label = message.senderLabel,
            lastSeen = os.epoch("utc"),
            data = message.data,
        }
    end
    
    -- Call registered handlers
    local handlers = messageHandlers[message.type]
    if handlers then
        debugLog("  -> " .. #handlers .. " handler(s) for " .. message.type)
        for _, handler in ipairs(handlers) do
            handler(message, message.senderId, message.senderLabel)
        end
    else
        debugLog("  -> No handlers for " .. message.type)
    end
    
    -- Also call wildcard handlers
    local wildcardHandlers = messageHandlers["*"]
    if wildcardHandlers then
        for _, handler in ipairs(wildcardHandlers) do
            handler(message, message.senderId, message.senderLabel)
        end
    end
end

---Wait for a message with timeout
---@param timeout number|nil Timeout in seconds (nil for no timeout)
---@return table|nil message The received message or nil on timeout
function module.receive(timeout)
    local timer = nil
    if timeout then
        timer = os.startTimer(timeout)
    end
    
    while true do
        local event, side, senderChannel, replyTo, message, distance = os.pullEvent()
        
        if event == "modem_message" then
            debugLog("RAW MODEM: side=" .. tostring(side) .. " ch=" .. tostring(senderChannel) .. " reply=" .. tostring(replyTo) .. " dist=" .. tostring(distance))
            processMessage(message)
            return message
        elseif event == "timer" and side == timer then
            return nil
        end
    end
end

---Start listening for messages in the background
---@return function stopListener Function to call to stop listening
---@return function listener The listener coroutine function
function module.startListener()
    local running = true
    
    local function listener()
        while running do
            local event, side, senderChannel, replyChannel, message, distance = os.pullEvent("modem_message")
            processMessage(message)
        end
    end
    
    local function stopListener()
        running = false
    end
    
    -- Start listener in parallel (caller should use parallel.waitForAny)
    return stopListener, listener
end

---Get list of connected turtles (controller only)
---@return table turtles Map of turtle ID to turtle info
function module.getConnectedTurtles()
    -- Clean up old entries (older than 30 seconds)
    local now = os.epoch("utc")
    local timeout = 30000 -- 30 seconds in milliseconds
    
    for id, turtle in pairs(connectedTurtles) do
        if now - turtle.lastSeen > timeout then
            connectedTurtles[id] = nil
        end
    end
    
    return connectedTurtles
end

---Broadcast ping to discover turtles
function module.ping()
    return module.send(module.MSG_TYPE.PING, {})
end

---Send pong response to ping
---@param targetId number ID of the pinging device
function module.pong(targetId)
    return module.send(module.MSG_TYPE.PONG, {}, targetId)
end

---Close modem channels
function module.close()
    if modem then
        modem.close(channel)
        modem.close(replyChannel)
    end
end

module.VERSION = "1.0.0"
return module
