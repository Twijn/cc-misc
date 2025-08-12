local s = require("lib/s")

local timeutil = require("lib/timeutil")

local modemBroadcast = s.number("modem.broadcast", 0, 65535, 70)
local modemReceive = s.number("modem.receive", 0, 65535, 69)

local breedInterval = s.number("cow.breed-interval", 30, nil, 600)

local babyCowMaxY = s.number("cow.cow-pit-max-y", nil, nil, -1.5)
local maximumBabies = s.number("cow.maximum-babies", -1, nil, 20)

local cowManipulator = s.peripheral("cow.entity-sensor", "manipulator")

local modem = s.peripheral("modem.side", "modem", true)

local function breed()
    print("Starting breed cycle...")
    modem.transmit(modemBroadcast, modemReceive, {
        type = "breed",
    })
end

local function burn()
    print("Burning adult cows!")
    modem.transmit(modemBroadcast, modemReceive, {
        type = "burn",
    })
end

local cowCounts = {}

local interval = timeutil.every(function()
    sleep(1)
    if cowCounts.babies and cowCounts.babies <= maximumBabies then
        breed()
    elseif cowCounts.babies then
        print(string.format("Skipping breed. Too many cows (%d/%d)!", cowCounts.babies, maximumBabies))
    end
end, breedInterval, ".last-bred")

local function countCows()
    local entities = cowManipulator.sense()

    local newCowCounts = {
        babies = 0,
        adults = 0,
    }

    local herdSize = 2  -- Group cows into 2x2 block cells

    for _, cow in pairs(entities) do
        if cow.key == "minecraft:cow" then
            if cow.y > babyCowMaxY then
                local x = math.floor(cow.x / herdSize)
                local z = math.floor(cow.z / herdSize)

                if not newCowCounts[x] then
                    newCowCounts[x] = {}
                end

                newCowCounts[x][z] = newCowCounts[x][z] and newCowCounts[x][z] + 1 or 1
            else
                local entityData = cowManipulator.getMetaByID(cow.id)
                if entityData then
                    if entityData.isChild then
                        newCowCounts.babies = newCowCounts.babies + 1
                    else
                        newCowCounts.adults = newCowCounts.adults + 1
                    end
                end
            end
        end
    end

    cowCounts = newCowCounts

    if cowCounts.adults > 2 then
        burn()
        sleep(15)
    elseif cowCounts.adults + cowCounts.babies < maximumBabies then
        interval.forceExecute()
        sleep(60)
    end

    local f = fs.open(".cowCount", "w")
    f.write(textutils.serialize(cowCounts))
    f.close()
end

local function countCowLoop()
    while true do
        countCows()
        sleep(5)
    end
end

return {
    interval = interval,
    run = countCowLoop,
    getCowCounts = function()
        return cowCounts
    end,
}
