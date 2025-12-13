--- Router Send Tool
--- Send a message to a specific router
---
---@usage
---tools/send <router_id> <protocol> [message]
---tools/send 201 router.command status
---
---@version 1.0.0

-- Setup package path
if not package.path:find("lib") then
    package.path = package.path .. ";/lib/?.lua"
end

local router = require("lib.router")
local config = require("config")
local log = require("lib.log")

local args = {...}

if #args < 2 then
    print("Usage: send <router_id> <protocol> [payload...]")
    print("")
    print("Examples:")
    print("  send 201 router.ping")
    print("  send 201 router.command status")
    print("  send 301 router.command reboot")
    print("")
    print("Protocols:")
    print("  router.ping           - Ping a router")
    print("  router.status.request - Request status")
    print("  router.command        - Execute a command")
    print("  router.discover       - Discovery request")
    return
end

local targetId = tonumber(args[1])
if not targetId then
    print("Error: Invalid router ID")
    return
end

local protocol = args[2]

-- Build payload from remaining arguments
local payload = {}
if #args >= 3 then
    payload.command = args[3]
    payload.message = table.concat(args, " ", 4)
    payload.args = {}
    for i = 4, #args do
        table.insert(payload.args, args[i])
    end
end

-- Get our router ID from settings
local myId = settings.get("router.id")
if not myId then
    print("Error: Router not configured. Run 'router' first.")
    return
end

-- Create a temporary router
local r = router.new(myId, true)

-- Find and attach a modem
local sides = {"top", "bottom", "left", "right", "front", "back"}
local modemFound = false

for _, side in ipairs(sides) do
    local p = peripheral.wrap(side)
    if p and p.open then
        r:attachModem(side)
        r:openPort(side, config.NETWORK.DEFAULT_PORT)
        modemFound = true
        break
    end
end

if not modemFound then
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        local p = peripheral.wrap(name)
        if p and p.open then
            r:attachModem(name)
            r:openPort(name, config.NETWORK.DEFAULT_PORT)
            modemFound = true
            break
        end
    end
end

if not modemFound then
    print("Error: No modem found")
    return
end

-- Load routes from settings
for prefix = 1, 9 do
    local side = settings.get("router.route." .. prefix)
    if side and r.modems[side] then
        r:addRoute(prefix, side)
    end
end

-- Track response
local responseReceived = false
local responseData = nil

-- Register response handlers
local responseProtocols = {
    [config.PROTOCOLS.PING] = config.PROTOCOLS.PONG,
    [config.PROTOCOLS.STATUS_REQUEST] = config.PROTOCOLS.STATUS_RESPONSE,
    [config.PROTOCOLS.COMMAND] = config.PROTOCOLS.COMMAND_RESPONSE,
    [config.PROTOCOLS.DISCOVER] = config.PROTOCOLS.ANNOUNCE,
}

local expectedResponse = responseProtocols[protocol]

-- Generic response handler
local function handleResponse(message, rtr)
    responseReceived = true
    responseData = message
end

-- Register handlers for all possible responses
r:registerHandler(config.PROTOCOLS.PONG, handleResponse)
r:registerHandler(config.PROTOCOLS.STATUS_RESPONSE, handleResponse)
r:registerHandler(config.PROTOCOLS.COMMAND_RESPONSE, handleResponse)
r:registerHandler(config.PROTOCOLS.ANNOUNCE, handleResponse)

-- Send message
print(string.format("Sending %s to router %d...", protocol, targetId))

local message = r:createMessage(targetId, protocol, payload)

if not r:send(message) then
    print("Error: Failed to send message")
    return
end

-- Wait for response
local timeout = 5
local timer = os.startTimer(timeout)

while not responseReceived do
    local event, p1, p2, p3, p4, p5 = os.pullEvent()
    
    if event == "modem_message" then
        local side, channel, replyChannel, rawMessage, distance = p1, p2, p3, p4, p5
        
        if type(rawMessage) == "table" and rawMessage.protocol == router.PROTOCOL and rawMessage.data then
            local msg = rawMessage.data
            if msg.destination == myId then
                r:processMessage(msg)
            end
        end
    elseif event == "timer" and p1 == timer then
        break
    end
end

-- Display response
print("")
if responseReceived and responseData then
    term.setTextColor(colors.lime)
    print("Response received!")
    term.setTextColor(colors.white)
    print(string.format("  From: Router %d", responseData.origin))
    print(string.format("  Protocol: %s", responseData.protocol))
    print(string.format("  Distance: %d hops", responseData.distance))
    print(string.format("  Hops: %s", table.concat(responseData.hops, " -> ")))
    print("")
    print("Payload:")
    
    -- Pretty print payload
    local function printTable(t, indent)
        indent = indent or "  "
        for k, v in pairs(t) do
            if type(v) == "table" then
                print(indent .. tostring(k) .. ":")
                printTable(v, indent .. "  ")
            else
                print(indent .. tostring(k) .. ": " .. tostring(v))
            end
        end
    end
    
    printTable(responseData.payload)
else
    term.setTextColor(colors.yellow)
    print("No response received (timeout)")
    term.setTextColor(colors.white)
    print("The message may have been delivered but no response was sent.")
end
