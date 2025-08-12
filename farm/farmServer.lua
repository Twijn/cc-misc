local cropFarm = require("lib/cropFarm")
local breeder = require("lib/breeder")
local storage = require("lib/storage")
local monitor = require("lib/monitor")
local timeutil = require("lib/timeutil")

local modem = s.peripheral("modem.side", "modem", true)

local function printTimeTo(interval, name)
    print()
    print(string.format("%s last ran %s ago", name, interval.getTimeSinceRun(true)))
    print(string.format("%s will run again in %s", name, interval.getTimeUntilRun(true)))
end

local function printTimeToAll()
    printTimeTo(cropFarm.interval, "Crop farm")
    printTimeTo(breeder.interval, "Breeder")
end

local function commandLoop()
    printTimeToAll()
    while true do
        local command = read():lower()
        if command == "farm" then
            cropFarm.interval.forceExecute()
        elseif command == "empty" then
            print("Sending empty command")
            modem.transmit(modemBroadcast, modemReceive, {
                type = "empty"
            })
        elseif command == "update" then
            modem.transmit(modemBroadcast, modemReceive, {
                type = "update"
            })
            shell.run("update server")
        elseif command == "time" then
            printTimeToAll()
        elseif command == "breed" then
            breeder.interval.forceExecute()
        else
            print("Unknown command. Valid options: farm, breed, empty, update, time")
        end
    end
end

parallel.waitForAny(
        commandLoop,
        timeutil.run,
        cropFarm.run,
        breeder.run,
        monitor.run,
        storage.run
)
