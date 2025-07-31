local breedItem = "minecraft:wheat"

local redstoneSide = "bottom"

local modemSide = "bottom"
local modemBroadcast = 70

local breedTimeout = 5 * 1000 -- 5 seconds

local modem = peripheral.wrap(modemSide)
local sensor = peripheral.find("plethora:sensor")

if not modem then
    error("modem was not found!")
end

local function rep(func, iterations)
    for i=1, iterations do
        func()
    end
end

function redstone.pulse(side)
    redstone.setOutput(side, true)
    sleep(.1)
    redstone.setOutput(side, false)
end

local function breedSide()
    redstone.pulse(redstoneSide)
    local lastBreed = os.epoch("utc")
    while true do
        if turtle.place() then
            lastBreed = os.epoch("utc")
        end

        if os.epoch("utc") - lastBreed >= breedTimeout then break end

        sleep()
    end
    redstone.pulse(redstoneSide)
    sleep(1)
end

local function replenish()
    local item = turtle.getItemDetail(1)
    if item and item.count > 48 then return end

    local itemsNeeded = 64 - (item and item.count or 0)
    local chests = table.pack(peripheral.find("inventory"))
    for i, chest in pairs(chests) do
        if type(chest) == "table" and chest.list then
            for slot, item in pairs(chest.list()) do
                if item.name == breedItem then
                    itemsNeeded = itemsNeeded - chest.pushItems(modem.getNameLocal(), slot, itemsNeeded, 1)
                    if itemsNeeded == 0 then return end
                end
            end
        end
    end
end

local function breed()
    replenish()
    print("Breeding!")
    breedSide()
    rep(turtle.turnRight, 2)
    breedSide()
    rep(turtle.turnRight, 2)
    replenish()
end

local function modemLoop()
    modem.open(modemBroadcast)
    while true do
        local _, __, channel, replyChannel, msg = os.pullEvent("modem_message")

        if type(msg) == "table" and msg.type then
            if msg.type == "breed" then
                breed()
            elseif msg.type == "update" then
                shell.run("update breeder")
            end
        end
    end
end

turtle.select(1)
modemLoop()
