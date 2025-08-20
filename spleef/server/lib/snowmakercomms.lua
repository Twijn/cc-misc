local config = require("/lib.config")
local persist = require("/lib.persist")
local tables = require("/lib.tables")

local modem = config.wirelessModem

local broadcastChannel = config.channel.broadcast
local receiveChannel = config.channel.receive

local snowmakers = persist("snowmakers.json")

local unresponsiveTime = 15 * 1000 -- 15 seconds

local module = {}

local function broadcast(type, data)
    data = data or {}
    data.type = type
    modem.transmit(broadcastChannel, receiveChannel, data)
end

function module.run()
    print("Now listening for snowmakers on port " .. receiveChannel)
    modem.open(receiveChannel)
    sleep(2)
    while true do
        print("broadcast")
        broadcast("sm-ping")
        os.startTimer(1)
        while true do
            local e, _, chnl, rChnl, msg = os.pullEvent()

            if e == "timer" then
                break
            elseif e == "modem_message" and type(msg) == "table" and msg.type == "sm-pong" and msg.id then
                local data = msg
                data.lastSeen = os.epoch("utc")
                snowmakers.set(data.id, data)
            end
        end
        print(string.format("Have %d total snowmakers (%d unresponsive)", module.getAllCount(), module.getUnresponsiveCount()))
        sleep(9)
    end
end

function module.getUnresponsive()
    local result = {}
    for _, snowmaker in pairs(module.getAll()) do
        if os.epoch("utc") - snowmaker.lastSeen >= unresponsiveTime then
            table.insert(result, snowmaker)
        end
    end
    return result
end

function module.getUnresponsiveCount()
    return tables.count(module.getUnresponsive())
end

function module.getAll()
    return snowmakers.getAll()
end

function module.getAllCount()
    return tables.count(module.getAll())
end

return module
