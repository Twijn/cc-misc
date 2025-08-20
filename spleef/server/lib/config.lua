local s = require("/lib.s")
local module = {}

while true do
    module.wirelessModem = s.peripheral("modem.wireless", "modem")
    if module.wirelessModem.isWireless() then break end
    print("Selected modem is not wireless!")
    sleep(1)
    settings.unset("modem.wireless")
end

module.channel = {
    broadcast = s.number("modem.channel.broadcast", 0, 65535, 33993),
    receive = s.number("modem.channel.receive", 0, 65535, math.random(33300, 35303)),
}

return module
