local config = require("/lib/config")

config.wirelessModem.transmit(
    config.channel.broadcast,
    config.channel.receive,
    {
        type = "update"
    }
)

shell.run("/update server")
