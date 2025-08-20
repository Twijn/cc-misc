local s = require("lib.s")
local config = require("lib.config")

local modem = config.wirelessModem

local status = "waiting"

os.setComputerLabel("Spleef Snowmaker #" .. config.id)

local function listen()
    modem.open(config.channel.broadcast)
    while true do
        local e, _, chnl, rChnl, msg = os.pullEvent("modem_message")
        if type(msg) == "table" and msg.type then
            if msg.type == "sm-ping" then
                print("Responding to ping")
                modem.transmit(rChnl, chnl, {
                    type = "sm-pong",
                    id = config.id,
                    status = status,
                })
            end
        end
    end
end

listen()
