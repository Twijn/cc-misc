local s = require("lib/s")
local tables = require("lib/tables")
local timeutil = require("lib/timeutil")
local config = require("config")

local modemBroadcast = s.number("modem.broadcast", 0, 65535, 70)
local modemReceive = s.number("modem.receive", 0, 65535, 69)
local modem = s.peripheral("modem.side", "modem", true)

local farmInterval = s.number("crop.farm-interval", 60, nil, 1200)

local turtleCount = s.number("crop.turtles-used", 1, nil, 9)

local turtles = {}

local crops = config.crops

local function getCropByIndex(index)
    local cropCount = tables.count(crops)
    if cropCount == 0 then
        error("No crops defined in config!")
    end

    local wrappedIndex = ((index - 1) % cropCount) + 1

    local i = 1
    for name, crop in pairs(crops) do
        if i == wrappedIndex then
            return crop
        end
        i = i + 1
    end
end

local function assignCrops()
    local oldTurtles = tables.recursiveCopy(turtles)

    -- Reset all crop counts to 0
    for _, crop in pairs(crops) do
        crop.count = 0
    end

    -- Get all crops in all inventories
    local inventories = table.pack(peripheral.find("inventory"))
    for i, chest in pairs(inventories) do
        if type(chest) == "table" and chest.list then
            for slot, item in pairs(chest.list()) do
                for _, crop in pairs(crops) do
                    if crop.cropName == item.name then
                        crop.count = crop.count + item.count
                        break
                    end
                end
            end
        end
    end

    -- Calculate fromTarget + totals
    local totalFromTarget = 0
    local totalTarget = 0
    for _, crop in pairs(crops) do
        crop.fromTarget = crop.target - crop.count
        totalFromTarget = totalFromTarget + math.max(crop.fromTarget, 0)
        totalTarget = totalTarget + crop.target
    end

    -- If close to target, make percent based on the weighted target
    -- If not, make percent based on distance from target
    if totalFromTarget < 100 then
        for i, crop in pairs(crops) do
            crop.percent = crop.target / totalTarget
            print(crop.name .. " " .. crop.percent)
        end
    else
        for i, crop in pairs(crops) do
            crop.percent = crop.fromTarget / totalFromTarget
        end
    end

    local turtleCount = tables.count(turtles)
    local turtlesLeft = turtleCount

    for i, crop in pairs(crops) do
        -- Assign proportional turtles, at least 1 if needed
        crop.turtleCount = math.floor(crop.percent * turtleCount + 0.5)
        -- Don't assign turtles if crop doesn't need any
        if crop.fromTarget <= 0 then
            crop.turtleCount = 0
        end
        -- If we over-assign, cap to turtles left
        if crop.turtleCount > turtlesLeft then
            crop.turtleCount = turtlesLeft
        end
        turtlesLeft = turtlesLeft - crop.turtleCount
    end

    -- If there are leftover turtles, assign them to crops with highest need
    local i = 1
    while turtlesLeft > 0 do
        local crop = getCropByIndex(i)
        crop.turtleCount = crop.turtleCount + 1
        turtlesLeft = turtlesLeft - 1
        i = i + 1
    end

    -- Now, assign actual turtles
    local turtleIndex = 1
    for key, crop in pairs(crops) do
        for i = 1, crop.turtleCount do
            if turtles[turtleIndex] then
                turtles[turtleIndex].crop = key
                turtleIndex = turtleIndex + 1
            else
                print("Turtle "..turtleIndex.." doesn't exist!")
            end
        end
    end

    for i, turt in pairs(turtles) do
        if not tables.recursiveEquals(turt, oldTurtles[i]) and turt.crop then
            print("Updating turtle " .. i .. " to crop " .. turt.crop)
            modem.transmit(turt.channel, modemReceive, {
                type = "settings",
                crops = crops,
                crop = turt.crop,
            })
        end
    end
end

local function sendSettings(channel)
    local data = {
        type = "settings",
        crops = crops,
    }
    if channel ~= modemBroadcast then
        for i, turt in pairs(turtles) do
            if turt.channel == channel and turt.crop then
                data.crop = turt.crop
                break
            end
        end
    end
    modem.transmit(channel, modemReceive, data)
end

local function startFarming()
    print("Sending farm command")
    modem.transmit(modemBroadcast, modemReceive, {
        type = "farm",
    })
end

local function identify()
    modem.transmit(modemBroadcast, modemReceive, {
        type = "identify",
    })
end

local function farm()
    print("Starting farm cycle...")
    identify()
    sleep(2)
    assignCrops()
    sleep(5)
    for i, turt in pairs(turtles) do
        turt.returned = false
    end
    startFarming()
    sleep(2)
    while true do
        identify()
        sleep(1)

        local quick = false
        local completed = true
        for i, turt in pairs(turtles) do
            quick = quick or turt.returned
            completed = completed and turt.returned
        end

        if completed then break end
        sleep(quick and 1 or 10)
        print("Waiting for turtles to return...")
    end

    print("Finished farming cycle!")
end

local interval = timeutil.every(farm, farmInterval, ".last-farm")

local function modemLoop()
    modem.open(modemReceive)
    sendSettings(modemBroadcast)
    identify()
    local assigned = false
    while true do
        local _, __, channel, replyChannel, msg = os.pullEvent("modem_message")
        if msg and type(msg) == "table" and msg.type then
            if msg.type == "identify" then
                if not turtles[msg.id] then
                    print("Identified turtle " .. msg.id)
                    turtles[msg.id] = {
                        returned = true,
                    }
                elseif not turtles[msg.id].returned then
                    print(string.format("Turtle %d returned after %s!", msg.id, interval.getTimeSinceRun(true)))
                    turtles[msg.id].returned = true
                end
                turtles[msg.id].channel = replyChannel

                if not assigned and tables.count(turtles) == turtleCount then
                    assigned = true
                    assignCrops()
                end
            elseif msg.type == "settings" then
                sendSettings(replyChannel)
            end
        end
    end
end

return {
    interval = interval,
    run = modemLoop,
    getTurtles = function()
        return turtles
    end,
    getCrops = function()
        return crops
    end,
}
