--- Router Discover Tool
--- Discover all routers on the network
---
---@usage
---tools/discover
---
---@version 1.0.0

-- Setup package path
if not package.path:find("lib") then
    package.path = package.path .. ";/lib/?.lua"
end

local router = require("lib.router")
local config = require("config")
local log = require("lib.log")

-- Get our router ID from settings
local myId = settings.get("router.id")
if not myId then
    print("Error: Router not configured. Run 'router' first.")
    return
end

-- Create a temporary router for discovery
local r = router.new(myId, true)

-- Find and attach all modems
local sides = {"top", "bottom", "left", "right", "front", "back"}
local modemCount = 0

for _, side in ipairs(sides) do
    local p = peripheral.wrap(side)
    if p and p.open then
        r:attachModem(side)
        r:openPort(side, config.NETWORK.DEFAULT_PORT)
        modemCount = modemCount + 1
    end
end

-- Also check named peripherals
local names = peripheral.getNames()
for _, name in ipairs(names) do
    local p = peripheral.wrap(name)
    if p and p.open then
        local alreadyAttached = false
        for _, side in ipairs(sides) do
            if side == name then
                alreadyAttached = true
                break
            end
        end
        if not alreadyAttached then
            r:attachModem(name)
            r:openPort(name, config.NETWORK.DEFAULT_PORT)
            modemCount = modemCount + 1
        end
    end
end

if modemCount == 0 then
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

-- Track discovered routers
local discovered = {}

-- Register announce handler
r:registerHandler(config.PROTOCOLS.ANNOUNCE, function(message, rtr)
    local info = message.payload
    discovered[info.id] = {
        id = info.id,
        level = info.level,
        isFinal = info.isFinal,
        label = info.label,
        distance = message.distance,
        hops = message.hops,
    }
end)

-- Send discovery broadcast to all possible router levels
print("Discovering routers on the network...")
print("")

-- Broadcast to common router IDs
for level = 1, 3 do
    for suffix = 1, 9 do
        local targetId = level * 100 + suffix
        if targetId ~= myId then
            local message = r:createMessage(targetId, config.PROTOCOLS.DISCOVER, {
                timestamp = os.epoch("utc"),
            })
            -- Try to send (may fail if no route)
            pcall(function() r:send(message) end)
        end
    end
end

-- Wait for responses
local timeout = 3
local endTime = os.epoch("utc") + (timeout * 1000)

print("Waiting for responses...")

while os.epoch("utc") < endTime do
    local remaining = (endTime - os.epoch("utc")) / 1000
    local timer = os.startTimer(0.1)
    
    local event, p1, p2, p3, p4, p5 = os.pullEvent()
    
    if event == "modem_message" then
        local side, channel, replyChannel, rawMessage, distance = p1, p2, p3, p4, p5
        
        if type(rawMessage) == "table" and rawMessage.protocol == router.PROTOCOL and rawMessage.data then
            local msg = rawMessage.data
            if msg.destination == myId then
                r:processMessage(msg)
            end
        end
    end
end

-- Display results
print("")
print("================================")
print("  Discovered Routers")
print("================================")
print("")

local count = 0
for id, info in pairs(discovered) do
    count = count + 1
    
    local levelColor = colors.white
    if info.level == 1 then levelColor = colors.lime
    elseif info.level == 2 then levelColor = colors.yellow
    elseif info.level == 3 then levelColor = colors.orange
    end
    
    term.setTextColor(levelColor)
    print(string.format("Router %d (%s)", info.id, info.label))
    term.setTextColor(colors.white)
    print(string.format("  Level: %d, Final: %s", info.level, tostring(info.isFinal)))
    print(string.format("  Distance: %d hops", info.distance))
    if #info.hops > 0 then
        print(string.format("  Path: %s", table.concat(info.hops, " -> ")))
    end
    print("")
end

if count == 0 then
    term.setTextColor(colors.yellow)
    print("No routers discovered.")
    print("Make sure other routers are running and routes are configured.")
    term.setTextColor(colors.white)
else
    print(string.format("Total: %d router(s) discovered", count))
end
