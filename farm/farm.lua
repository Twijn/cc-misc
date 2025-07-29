local modemSend = 69
local modemBroadcast = 70
local modemReceive = tonumber(1000 .. settings.get("farm.id"))

print(string.format("Modem settings: (s%d) (b%d) (r%d)", modemSend, modemBroadcast, modemReceive))

local tables = require("tables")

-- Return back "home" if the block underneath is not a chest
local blockFound, block = turtle.inspectDown()
if not blockFound or block.name ~= "minecraft:chest" then
    while turtle.back() do end
    while turtle.down() do end
end

local modem = peripheral.wrap("back")

if not modem then
    error("modem not found")
end

local crops = nil
local crop = nil

local function empty()
    if not crop then
        print("Can't empty now: Need a crop to harvest!")
        return
    end

    for slot = tables.count(crops)+1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            turtle.select(slot)
            turtle.dropDown()
        end
    end

    if turtle.getFuelLevel() < 100 then
        print("Refueling!")
        turtle.suckDown(8)
        for slot = 1, 16 do
            turtle.select(slot)
            turtle.refuel(8)
        end
    end
    turtle.select(1)
end

local function harvest()
    turtle.digDown()
    for slot = 1,16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == crop.seedName then
            if slot > tables.count(crops) or detail.count > 1 then
                turtle.select(slot)
                turtle.placeDown()
                break
            end
        end
        if slot == 16 then
            print("No seeds found :(")
            return false
        end
    end
    turtle.select(1)
    return true
end

local function harvestRow()
    repeat
        local found, block = turtle.inspectDown()
        if not found then
            if not harvest() then break end
        elseif crops[block.name] then
            local harvestCrop = crops[block.name]

            if harvestCrop.grownAge and block.state.age >= harvestCrop.grownAge then
                if not harvest() then break end
            end
        end
    until not turtle.forward()

    while turtle.back() do end
end

local function harvestAll()
    -- Harvest the first (starting) row
    harvestRow()
    repeat
        local b, blo = turtle.inspect()
        if b and blo.name == "minecraft:farmland" then
            if turtle.up() and turtle.up() then
                harvestRow()
            end
        end
    until not turtle.up()
    while turtle.down() do end
    empty()
end

local function requestSettings()
    modem.transmit(modemSend, modemReceive, {
        type = "settings"
    })
end

local function identify()
    modem.transmit(modemSend, modemReceive, {
        type = "identify",
        id = settings.get("farm.id"),
    })
end

local function modemLoop()
    modem.open(modemReceive)
    modem.open(modemBroadcast)

    requestSettings()
    while true do
        local e, side, channel, replyChannel, msg = os.pullEvent("modem_message")
        if msg and type(msg) == "table" and msg.type then
            if msg.type == "identify" then
                identify()
            elseif msg.type == "settings" then
                if msg.settings then
                    for name, value in pairs(msg.settings) do
                        print(string.format("Setting %s = %s", name, value))
                        settings.set(name, value)
                    end
                    settings.save()
                end
                if msg.crops then
                    crops = msg.crops
                end
                if msg.crop then
                    crop = crops[msg.crop]
                    print("Using crop " .. crop.name)
                    empty()
                end
            elseif msg.type == "farm" then
                if crops and crop then
                    print("Now farming!")
                    harvestAll()
                else
                    print("Unable to farm because server didn't send me crops >:( requesting now!")
                    requestSettings()
                end
            elseif msg.type == "empty" then
                print("Emptying by command")
                empty()
            elseif msg.type == "update" then
                shell.run("update turtle")
            end
        end
    end
end

modemLoop()
