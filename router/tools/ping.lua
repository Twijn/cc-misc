--- Router Ping Tool
--- Send a ping to a router and measure response time
---
---@usage
---tools/ping <router_id>
---tools/ping 201
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

if #args < 1 then
    print("Usage: ping <router_id>")
    print("Example: ping 201")
    return
end

local targetId = tonumber(args[1])
if not targetId then
    print("Error: Invalid router ID")
    return
end

-- Get our router ID from settings
local myId = settings.get("router.id")
if not myId then
    print("Error: Router not configured. Run 'router' first.")
    return
end

-- Create a temporary router for pinging
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

-- Also check named peripherals
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

-- Register pong handler
local pongReceived = false
local pongData = nil

r:registerHandler(config.PROTOCOLS.PONG, function(message, rtr)
    pongReceived = true
    pongData = message
end)

-- Send ping
print(string.format("Pinging router %d...", targetId))
local startTime = os.epoch("utc")

local message = r:createMessage(targetId, config.PROTOCOLS.PING, {
    timestamp = startTime,
})

if not r:send(message) then
    print("Error: Failed to send ping")
    return
end

-- Wait for response with timeout
local timeout = 5
local timer = os.startTimer(timeout)

while not pongReceived do
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

if pongReceived then
    local endTime = os.epoch("utc")
    local latency = endTime - startTime
    
    print("")
    term.setTextColor(colors.lime)
    print(string.format("Reply from router %d", pongData.origin))
    term.setTextColor(colors.white)
    print(string.format("  Latency: %d ms", latency))
    print(string.format("  Distance: %d hops", pongData.distance))
    print(string.format("  Hop path: %s", table.concat(pongData.hops, " -> ")))
else
    print("")
    term.setTextColor(colors.red)
    print(string.format("Request timed out (no response from %d)", targetId))
    term.setTextColor(colors.white)
end
