---@class SettingsModule
---A settings management module for ComputerCraft that provides interactive configuration
---with automatic validation, peripheral detection, and persistent storage using CC settings.
---
---Features:
--- - Interactive peripheral selection with type filtering
--- - Number input with range validation
--- - String input with default values
--- - Boolean selection with menu interface
--- - Automatic settings persistence
--- - Peripheral availability checking and recovery
--- - Side-only peripheral filtering
---
---@usage
---local s = require("s")
---
---local modem = s.peripheral("modem", "modem", true) -- Side-attached modems only
---local port = s.number("port", 1, 65535, 8080) -- Port 1-65535, default 8080
---local name = s.string("server_name", "MyServer") -- String with default
---local enabled = s.boolean("enabled") -- Boolean selection

local module = {}

local tables = require("/lib/tables")

local sides = {"top","bottom","front","back","left","right"}

---Display an interactive menu for selecting from a list of options
---@param title string The main title to display
---@param subtitle string The subtitle/description to display
---@param options string[] Array of selectable options
---@param selected? number Currently selected option index (defaults to 1)
---@return string # The selected option string
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

---Interactively request user to select a peripheral of a specific type
---@param name string The setting name to store the selection
---@param type string The peripheral type to filter for
---@param sideOnly? boolean If true, only show peripherals attached to computer sides
---@return string # The selected peripheral name
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

---Get or configure a peripheral setting with automatic validation and recovery
---@param name string The setting name to store/retrieve
---@param type string The required peripheral type (e.g., "modem", "monitor")
---@param sideOnly? boolean If true, only allow peripherals attached to computer sides
---@return table # The wrapped peripheral object
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

---Get or configure a number setting with range validation
---@param name string The setting name to store/retrieve
---@param from? number Minimum allowed value (nil for no minimum)
---@param to? number Maximum allowed value (nil for no maximum)
---@param default? number Default value if user provides empty input
---@return number # The configured number value
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

---Get or configure a string setting with optional default value
---@param name string The setting name to store/retrieve
---@param default? string Default value if user provides empty input
---@return string # The configured string value
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

---Get or configure a boolean setting using an interactive menu
---@param name string The setting name to store/retrieve
---@return boolean # The configured boolean value
function module.boolean(name)
    local value = settings.get(name)

    if type(value) ~= "boolean" then
        value = selectMenu("Set boolean value", "Set a value for " .. name, {"true", "false"}) == "true"
        settings.set(name, value)
        settings.save()
    end

    return value
end

---@class SettingsModule
---@field peripheral fun(name: string, type: string, sideOnly?: boolean): table
---@field number fun(name: string, from?: number, to?: number, default?: number): number
---@field string fun(name: string, default?: string): string
---@field boolean fun(name: string): boolean

return module
