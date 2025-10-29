local module = {}

local tables = require("/lib/tables")

local sides = {"top","bottom","front","back","left","right"}

local function selectMenu(title, subtitle, options, selected)
    if not selected then selected = 1 end

    term.clear()
    term.setCursorPos(1,1)

    print(title)
    print(subtitle)

    local x, y = term.getCursorPos()

    term.setCursorPos(1, y + 2)
    for i, option in ipairs(options) do
        if selected == i then
            print("> " .. option)
        else
            print("  " .. option)
        end
    end

    while true do
        local e, key = os.pullEvent("key")
        if key == keys.up and selected > 1 then
            return selectMenu(title, subtitle, options, selected - 1)
        elseif key == keys.down and selected < #options then
            return selectMenu(title, subtitle, options, selected + 1)
        elseif key == keys.enter then
            return options[selected]
        end
    end
end

local function requestPeripheral(name, type, sideOnly)
    local filteredNames
    while true do
        local names = peripheral.getNames()

        filteredNames = {}
        for _,name in pairs(names) do
            if tables.includes(table.pack(peripheral.getType(name)), type) then
                if not sideOnly or tables.includes(sides, name) then
                    table.insert(filteredNames, name)
                end
            end
        end

        if #filteredNames == 0 then
            print(string.format("No peripherals of type %s exist for %s!", type, name))
            print("Press enter to refresh")
            read()
        else break end
    end

    local peripName = selectMenu("Select a Peripheral", string.format("for settings %s (type %s)", name, type), filteredNames)
    settings.set(name, peripName)
    settings.save()
    return peripName
end

function module.peripheral(name, type, sideOnly)
    local value = settings.get(name)

    if not value then
        value = requestPeripheral(name, type, sideOnly)
    end

    local p = peripheral.wrap(value)
    if p then
        return p
    else
        print(string.format("Peripheral %s (value %s) is missing. Would you like to select a new peripheral?", name, value))
        print("y = select new, (n) = restart computer")
        while true do
            local resp = read():lower()
            if resp == "y" then
                value = requestPeripheral(name, type, sideOnly)
                return peripheral.wrap(value)
            else
                os.reboot()
            end
        end
    end
end

function module.number(name, from, to, default)
    local value = settings.get(name)

    if not value then
        local rules = string.format("number (%s-%s)", from and from or "-inf", to and to or "inf")
        print(string.format("Enter value for %s %s", name, rules))
        if default then
            print(string.format("Leave blank for default (%d)", default))
        end
        while true do
            local strVal = read()

            if #strVal == 0 and default then
                value = default
                break
            end

            value = tonumber(strVal)
            if value and (not from or value >= from) and (not to or value <= to) then
                break
            end

            print("Invalid value")
        end
        settings.set(name, value)
        settings.save()
    end

    return value
end

function module.string(name, default)
    local value = settings.get(name)

    if not value then
        print(string.format("Enter value for %s", name))
        if default then
            print(string.format("Leave blank for default (%s)", default))
        end

        local strVal = read()

        if #strVal == 0 and default then
            value = default
        else
            value = strVal
        end
        settings.set(name, value)
        settings.save()
    end

    return value
end

function module.boolean(name)
    local value = settings.get(name)

    if type(value) ~= "boolean" then
        value = selectMenu("Set boolean value", "Set a value for " .. name, {"true", "false"}) == "true"
        settings.set(name, value)
        settings.save()
    end

    return value
end

return module
