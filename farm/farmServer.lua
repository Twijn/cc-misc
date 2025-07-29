local modemBroadcast = 70
local modemReceive = 69
local modemSide = "bottom"

local tables = require("tables")

local crops = {
    ["minecraft:wheat"] = {
        name = "Wheat",
        cropName = "minecraft:wheat",
        seedName = "minecraft:wheat_seeds",
        grownAge = 7,
        target = 3072,
    },
    ["minecraft:beetroots"] = {
        name = "Beetroot",
        cropName = "minecraft:beetroots",
        seedName = "minecraft:beetroot_seeds",
        grownAge = 3,
        target = 512,
    },
    ["minecraft:carrots"] = {
        name = "Carrot",
        cropName = "minecraft:carrot",
        seedName = "minecraft:carrot",
        grownAge = 7,
        target = 1024,
    },
}

local locations = {
    ["minecraft:wheat"] = "sc-goodies:iron_chest_43",
    ["minecraft:wheat_seeds"] = "sc-goodies:iron_chest_39",
    ["minecraft:beetroot"] = "sc-goodies:iron_chest_40",
    ["minecraft:beetroot_seeds"] = "sc-goodies:iron_chest_41",
    ["minecraft:carrot"] = "sc-goodies:iron_chest_42",
    ["minecraft:charcoal"] = settings.get("chest.fuel"),
}

local outputChests = {
    ["minecraft:chest_334"] = {},
    ["minecraft:chest_335"] = {},
    ["minecraft:chest_336"] = {},
    ["minecraft:chest_337"] = {},
    ["minecraft:chest_338"] = {},
}

local turtles = {}

local function err(message)
    term.setTextColor(colors.red)
    print(message)
    term.setTextColor(colors.white)
end

local modem = peripheral.wrap(modemSide)
if not modem then
    return err("Modem not found on side " .. modemSide)
end

for name, _ in pairs(outputChests) do
    outputChests[name] = peripheral.wrap(name)
    if not outputChests[name] then
        error("Could not find output chest " .. name)
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
        if crops[i].fromTarget > 0 then
            crops[i].turtleCount = crops[i].turtleCount + 1
            turtlesLeft = turtlesLeft - 1
        end
        i = i + 1
        if i > #crops then i = 1 end
    end

    -- Now, assign actual turtles
    local turtleIndex = 1
    for key, crop in pairs(crops) do
        for i = 1, crop.turtleCount do
            turtles[turtleIndex].crop = key
            turtleIndex = turtleIndex + 1
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

local function modemLoop()
    modem.open(modemReceive)
    sendSettings(modemBroadcast)
    while true do
        local _, __, channel, replyChannel, msg = os.pullEvent("modem_message")
        if msg and type(msg) == "table" and msg.type then
            if msg.type == "identify" then
                print("Identified turtle " .. msg.id)
                if not turtles[msg.id] then
                    turtles[msg.id] = {}
                end
                turtles[msg.id].channel = replyChannel
            elseif msg.type == "settings" then
                sendSettings(replyChannel)
            end
        end
    end
end

local function farm()
    identify()
    sleep(5)
    assignCrops()
    sleep(10)
    startFarming()
end

local function farmLoop()
    sleep(2)
    while true do
        sleep(2)
        identify()
        sleep(5)
        assignCrops()
        sleep(10)
        startFarming()
        sleep(500)
    end
end

local function maintainOutputs()
    while true do
        for name, chest in pairs(outputChests) do
            local list = chest.list()
            if not list or not list[1] or list[1].count < 64 then
                for slot, item in pairs(peripheral.call(settings.get("chest.fuel"), "list")) do
                    if not list[1] or list[1].name == item.name then
                        chest.pullItems(settings.get("chest.fuel"), slot, list[1] and 64 - list[1].count or 64)
                        if chest.getItemDetail(1).count == 64 then
                            break
                        end
                    end
                end
            end
            for slot, item in pairs(list) do
                if slot > 1 then
                    local location = locations[item.name]
                    if location then
                        chest.pushItems(location, slot)
                    else
                        print(string.format("No location for %s in output %s", item.name, name))
                    end
                end
            end
        end
        sleep(60)
    end
end

local function commandLoop()
    while true do
        local command = read():lower()
        if command == "farm" then
            startFarming()
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
        else
            print("Unknown command. Valid options: farm, empty, update")
        end
    end
end

parallel.waitForAny(modemLoop, farmLoop, commandLoop, maintainOutputs)
