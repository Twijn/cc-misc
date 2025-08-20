local s = require("lib.s")
local module = {}

module.id = s.number("snowmaker.id", 1, 99)

while true do
    module.wirelessModem = s.peripheral("modem.wireless", "modem", true)
    if module.wirelessModem.isWireless() then break end
    print("Selected modem is not wireless!")
    sleep(1)
    settings.unset("modem.wireless")
end

module.modem = s.peripheral("modem.wired", "modem", true)

module.channel = {
    broadcast = s.number("modem.channel.broadcast", 0, 65535, 33993),
}

return module
