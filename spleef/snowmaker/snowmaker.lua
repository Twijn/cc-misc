local s = require("lib.s")
local config = require("lib.config")

local modem = config.wirelessModem

local status = "waiting"

os.setComputerLabel("Spleef Snowmaker #" .. config.id)
print("Starting snowmaker")

local function listen()
    modem.open(config.channel.broadcast)
    while true do
        local e, _, chnl, rChnl, msg = os.pullEvent("modem_message")
        if type(msg) == "table" and msg.type then
            if msg.type == "update" then
                print("Updating")
                shell.run("/update snowmaker")
            elseif msg.type == "sm-ping" then
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
