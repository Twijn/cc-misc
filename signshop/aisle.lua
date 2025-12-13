--- SignShop Aisle ---
--- Turtle component that dispenses items and responds to server pings.
---
---@version 1.5.0
-- @module signshop-aisle

local VERSION = "1.5.0"

local dropFunc = turtle.dropUp

-- Adjust package path for disk-based installations
if not package.path:find("disk") then
    package.path = package.path .. ";/disk/?.lua;/disk/lib/?.lua"
end

local s = require("lib.s")
local logger = require("lib.log")

-- Check if this is first run or settings are missing
local needsSetup = not settings.get("modem.side") or not settings.get("aisle.name")

local modem, broadcastChannel, privateChannel, aisleName

if needsSetup then
    -- Use form-based setup for new installations
    local form = s.useForm("SignShop Aisle Setup")
    
    local modemField = form.peripheral("modem.side", "modem", true)
    local broadcastField = form.number("modem.broadcast", 0, 65535, 8698)
    local privateField = form.number("modem.private", 0, 65535, os.getComputerID())
    local aisleField = form.string("aisle.name")
    
    if not form.submit() then
        print("Setup cancelled.")
        return
    end
    
    modem = modemField()
    broadcastChannel = broadcastField()
    privateChannel = privateField()
    aisleName = aisleField()
else
    -- Use existing settings
    modem = s.peripheral("modem.side", "modem", true)
    broadcastChannel = s.number("modem.broadcast", 0, 65535, 8698)
    privateChannel = s.number("modem.private", 0, 65535, os.getComputerID())
    aisleName = s.string("aisle.name")
end

os.setComputerLabel("aisle-" .. aisleName)

logger.info(string.format("Started SignShop %s v%s", aisleName, VERSION))

local function empty()
    for slot = 1,16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            logger.info(string.format("Dispensed x%d %s", detail.count, detail.name))
            turtle.select(slot)
            dropFunc()
        end
    end
end

local function turtleInventoryUpdateLoop()
    while true do
        os.pullEvent("turtle_inventory")
        empty()
    end
end

local function timedLoop()
    while true do
        empty()
        sleep(5)
    end
end

local function transmit(rChnl, msg)
    modem.transmit(rChnl, privateChannel, msg)
end

local sides = {"top", "bottom", "left", "right", "front", "back"}
local function setRedstone(status)
    for _, side in pairs(sides) do
        redstone.setOutput(side, status)
    end
end

local function modemLoop()
    modem.open(broadcastChannel)
    modem.open(privateChannel)
    while true do
        local e, side, chnl, rChnl, msg, distance = os.pullEvent("modem_message")

        if type(msg) == "table" and msg.type then
            if msg.type == "ping" then
                if type(msg.redstone) == "boolean" then
                    setRedstone(msg.redstone)
                end
                transmit(rChnl, {
                    type = "pong",
                    aisle = aisleName,
                    self = modem.getNameLocal(),
                })
            elseif msg.type == "update" then
                shell.run("update")
                os.reboot()
            end
        end
    end
end

parallel.waitForAll(
        turtleInventoryUpdateLoop,
        timedLoop,
        modemLoop
)
