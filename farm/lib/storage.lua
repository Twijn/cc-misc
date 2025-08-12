local s = require("lib/s")
local config = require("config")
local tables = require("lib/tables")

local locations = config.chestLocations
local farmOutputChests = config.farmOutputChests
local outputChests = config.outputChests

for name, _ in pairs(farmOutputChests) do
    farmOutputChests[name] = peripheral.wrap(name)
    if not farmOutputChests[name] then
        return err("Could not find crop output chest " .. name)
    end
end

for name, _ in pairs(outputChests) do
    outputChests[name] = peripheral.wrap(name)
    if not outputChests[name] then
        return err("Could not find output chest " .. name)
    end
end

local function storeItem(chest, slot, item)
    local location = locations[item.name]
    if location and item.count - chest.pushItems(location, slot) == 0 then
        return
    end
    if locations.all then
        if item.count - chest.pushItems(locations.all, slot) > 0 then
            print(string.format("Unable to move %s in output %s", item.name, peripheral.getName(chest)))
        end
    else
        print(string.format("No location for %s in output %s", item.name, peripheral.getName(chest)))
    end
end

local function maintainOutputs()
    while true do
        for name, chest in pairs(farmOutputChests) do
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
                    storeItem(chest, slot, item)
                end
            end
        end
        for name, chest in pairs(outputChests) do
            for slot, item in pairs(chest.list()) do
                storeItem(chest, slot, item)
            end
        end
        sleep(10)
    end
end

return {
    run = maintainOutputs,
}
