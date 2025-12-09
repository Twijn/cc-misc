--- A settings management module for ComputerCraft that provides interactive configuration
--- with automatic validation, peripheral detection, and persistent storage using CC settings.
---
--- Features: Interactive peripheral selection with type filtering, number input with range validation,
--- string input with default values, boolean selection with menu interface, automatic settings persistence,
--- peripheral availability checking and recovery, side-only peripheral filtering, and optional form UI integration.
---
---@usage
---local s = require("s")
---
---local modem = s.peripheral("modem", "modem", true)
---local port = s.number("port", 1, 65535, 8080)
---local name = s.string("server_name", "MyServer")
---local enabled = s.boolean("enabled")
---
---@version 2.0.2
-- @module s

local VERSION = "2.0.2"

local module = {}

local tables = require("lib.tables")

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

---Create a form-based settings interface using formui.lua
---Requires formui.lua to be installed. Returns a table with form-based versions of all s.lua functions.
---
---@usage
---local s = require("s")
---local form = s.useForm("My App Configuration")
---
---local modem = form.peripheral("modem", "modem", true)
---local port = form.number("port", 1, 65535, 8080)
---local name = form.string("server_name", "MyServer")
---local enabled = form.boolean("enabled")
---
---if form.submit() then
---  print("Settings saved!")
---  print("Modem:", modem())
---  print("Port:", port())
---end
---
---@param title? string The form title (defaults to "Settings")
---@return table # Form interface with peripheral, number, string, boolean, and submit functions
function module.useForm(title)
    local formui = require("formui")
    local form = formui.new(title or "Settings")
    
    local formInterface = {}
    
    ---Add a peripheral field to the form
    ---@param name string The setting name
    ---@param type string The peripheral type to filter for
    ---@param sideOnly? boolean If true, only show peripherals attached to computer sides
    ---@return function # Getter function that returns the peripheral name
    function formInterface.peripheral(name, type, sideOnly)
        local existingValue = settings.get(name)
        local field = form:peripheral(name, type, sideOnly and "side" or nil)
        if existingValue then
            -- Set the existing value if it exists and is valid
            local p = peripheral.wrap(existingValue)
            if p then
                field.value = existingValue
            end
        end
        return function()
            local value = field()
            if value then
                settings.set(name, value)
                settings.save()
            end
            return value and peripheral.wrap(value) or nil
        end
    end
    
    ---Add a number field to the form
    ---@param name string The setting name
    ---@param from? number Minimum allowed value
    ---@param to? number Maximum allowed value
    ---@param default? number Default value
    ---@return function # Getter function that returns the number value
    function formInterface.number(name, from, to, default)
        local existingValue = settings.get(name)
        local validator = nil
        if from or to then
            validator = formui.validation.number_range(from or -math.huge, to or math.huge)
        end
        local field = form:number(name, existingValue or default or 0, validator)
        return function()
            local value = field()
            if value then
                settings.set(name, value)
                settings.save()
            end
            return value
        end
    end
    
    ---Add a string field to the form
    ---@param name string The setting name
    ---@param default? string Default value
    ---@return function # Getter function that returns the string value
    function formInterface.string(name, default)
        local existingValue = settings.get(name)
        local field = form:text(name, existingValue or default or "")
        return function()
            local value = field()
            if value then
                settings.set(name, value)
                settings.save()
            end
            return value
        end
    end
    
    ---Add a boolean field to the form
    ---@param name string The setting name
    ---@return function # Getter function that returns the boolean value
    function formInterface.boolean(name)
        local existingValue = settings.get(name)
        local field = form:select(name, {"true", "false"}, existingValue == true and 1 or 2)
        return function()
            local value = field()
            if value then
                local boolValue = (value == "true")
                settings.set(name, boolValue)
                settings.save()
                return boolValue
            end
            return nil
        end
    end
    
    ---Add submit and cancel buttons, then run the form
    ---@return boolean # True if submitted, false if cancelled
    function formInterface.submit()
        form:addSubmitCancel()
        return form:run()
    end
    
    return formInterface
end

module.VERSION = VERSION

return module
