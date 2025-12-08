--- SignShop Aisle Manager ---
--- Handles communication with aisle turtles via modem.
---
---@version 1.4.0

local s = require("lib.s")
local logger = require("lib.log")
local persist = require("lib.persist")

-- Check if this is first run or settings are missing
local needsSetup = not settings.get("modem.side")

local modem, broadcastChannel, receiveChannel, pingFrequency

if needsSetup then
    -- Use form-based setup for new installations
    local form = s.useForm("Aisle Manager Setup")
    
    local modemField = form.peripheral("modem.side", "modem", true)
    local broadcastField = form.number("modem.broadcast", 0, 65535, 8698)
    local receiveField = form.number("modem.receive", 0, 65535, 9698)
    local pingField = form.number("aisle.ping-frequency-sec", 1, 30, 3)
    
    if not form.submit() then
        error("Setup cancelled. Aisle manager requires configuration.")
    end
    
    modem = modemField()
    broadcastChannel = broadcastField()
    receiveChannel = receiveField()
    pingFrequency = pingField()
else
    -- Use existing settings
    modem = s.peripheral("modem.side", "modem", true)
    broadcastChannel = s.number("modem.broadcast", 0, 65535, 8698)
    receiveChannel = s.number("modem.receive", 0, 65535, 9698)
    pingFrequency = s.number("aisle.ping-frequency-sec", 1, 30, 3)
end

local manager = {}

local aisles = persist("aisles.json")

local function listenLoop()
    modem.open(receiveChannel)
    while true do
        local e, side, chnl, rChnl, msg = os.pullEvent("modem_message")
        if type(msg) == "table" and msg.type then
            if msg.type == "pong" and msg.aisle and msg.self then
                msg.lastSeen = os.epoch("utc")
                aisles.set(msg.aisle, msg)
            end
        end
    end
end

local function pingLoop()
    local redstone = true
    while true do
        modem.transmit(broadcastChannel, receiveChannel, {
            type = "ping",
            redstone = redstone,
        })
        redstone = not redstone
        sleep(pingFrequency)
    end
end

manager.getAisles = function()
    aisles.reload()  -- Reload from disk in case server updated
    return aisles.getAll()
end

manager.getAisle = function(name)
    aisles.reload()  -- Reload from disk in case server updated
    return aisles.get(name)
end

manager.updateAisles = function()
    logger.info("Broadcasting update command to all aisles...")
    modem.transmit(broadcastChannel, receiveChannel, {
        type = "update",
    })
end

manager.run = function()
    parallel.waitForAll(listenLoop, pingLoop)
end

for _, turtle in ipairs(table.pack(peripheral.find("turtle"))) do
    if not turtle.isOn() then
        turtle.turnOn()
    end
end

return manager
