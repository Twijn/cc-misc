-- SignShop Aisle --
-- Twijn version:
local v = "0.0.1"

local dropFunc = turtle.dropUp

local s = require("lib.s")
local logger = require("lib.log")

local modem = s.peripheral("modem.side", "modem", true)

local broadcastChannel = s.number("modem.broadcast", 0, 65535, 8698)
local privateChannel = s.number("modem.private", 0, 65535, os.getComputerID())

local aisleName = s.string("aisle.name")

os.setComputerLabel("aisle-"..aisleName)

logger.info(string.format("Started SignShop %s v%s", aisleName, v))

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
            end
        end
    end
end

parallel.waitForAll(
        turtleInventoryUpdateLoop,
        timedLoop,
        modemLoop
)
