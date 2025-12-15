--- AutoCrafter Communications Library
--- Handles network communication between server and crafters.
---
---@version 1.0.0

local VERSION = "1.0.0"

local comms = {}

local modem = nil
local channel = 4200
local computerId = os.getComputerID()

---Find and open a modem
---@param preferWireless? boolean Prefer wireless modem
---@return boolean success Whether a modem was found
function comms.init(preferWireless)
    -- Find modems
    local modems = {peripheral.find("modem")}
    
    if #modems == 0 then
        return false
    end
    
    -- Pick the preferred type
    for _, m in ipairs(modems) do
        if preferWireless and m.isWireless() then
            modem = m
            break
        elseif not preferWireless and not m.isWireless() then
            modem = m
            break
        end
    end
    
    -- Fall back to any modem
    if not modem then
        modem = modems[1]
    end
    
    modem.open(channel)
    return true
end

---Set the communication channel
---@param ch number The channel to use
function comms.setChannel(ch)
    if modem and modem.isOpen(channel) then
        modem.close(channel)
    end
    channel = ch
    if modem then
        modem.open(channel)
    end
end

---Get the current channel
---@return number channel The current channel
function comms.getChannel()
    return channel
end

---Send a message
---@param msgType string The message type
---@param data? table Optional message data
---@param target? number Optional target computer ID (nil for broadcast)
function comms.send(msgType, data, target)
    if not modem then return end
    
    local message = {
        type = msgType,
        sender = computerId,
        target = target,
        data = data or {},
        timestamp = os.epoch("utc"),
    }
    
    modem.transmit(channel, channel, message)
end

---Wait for a message
---@param timeout? number Timeout in seconds
---@param filter? string Optional message type filter
---@return table|nil message The received message or nil on timeout
function comms.receive(timeout, filter)
    local timer = nil
    if timeout then
        timer = os.startTimer(timeout)
    end
    
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "modem_message" then
            local side, senderChannel, replyChannel, message, distance = p1, p2, p3, p4, p5
            
            if senderChannel == channel and type(message) == "table" then
                -- Check if message is for us
                if not message.target or message.target == computerId then
                    -- Check filter
                    if not filter or message.type == filter then
                        return message
                    end
                end
            end
        elseif event == "timer" and p1 == timer then
            return nil
        end
    end
end

---Send and wait for response
---@param msgType string The message type to send
---@param data? table The message data
---@param target? number Target computer ID
---@param responseType string Expected response type
---@param timeout? number Timeout in seconds (default 5)
---@return table|nil response The response or nil on timeout
function comms.request(msgType, data, target, responseType, timeout)
    timeout = timeout or 5
    comms.send(msgType, data, target)
    return comms.receive(timeout, responseType)
end

---Broadcast a message to all listeners
---@param msgType string The message type
---@param data? table The message data
function comms.broadcast(msgType, data)
    comms.send(msgType, data, nil)
end

---Check if modem is connected
---@return boolean connected Whether a modem is available
function comms.isConnected()
    return modem ~= nil
end

---Get modem info
---@return table|nil info Modem information
function comms.getModemInfo()
    if not modem then return nil end
    
    return {
        isWireless = modem.isWireless(),
        channel = channel,
    }
end

---Close the modem connection
function comms.close()
    if modem and modem.isOpen(channel) then
        modem.close(channel)
    end
end

comms.VERSION = VERSION

return comms
