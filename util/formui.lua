-- Dynamic Form UI for CC:Tweaked by Twijn
local version = "0.0.3"

local FormUI = { _v = version }
FormUI.__index = FormUI

FormUI.validation = {
    modem_wireless = function(v, f)
        return peripheral.call(f.options[v], "isWireless"), "Modem must be wireless!"
    end,
    modem_wired = function(v, f)
        print(v)
        print(f.options[v])
        return not peripheral.call(f.options[v], "isWireless"), "Modem must be wired!"
    end,
    number_positive = function(v)
        return v > 0, "Must be a positive number!"
    end,
    number_range = function(min, max)
        return function(v)
            return (v >= min and v <= max),
            ("Must be between %d and %d"):format(min, max)
        end
    end,
    number_integer = function(v)
        return math.floor(v) == v, "Must be an integer!"
    end,
    string_nonempty = function(v)
        return v and v ~= "", "This field cannot be empty!"
    end,
    string_length = function(min, max)
        return function(v)
            local len = #v
            return len >= min and len <= max,
            ("Text length must be between %d and %d"):format(min, max)
        end
    end,
    string_pattern = function(pattern, msg)
        return function(v)
            return string.match(v, pattern), msg or ("Must match pattern: " .. pattern)
        end
    end,
}

local function centerText(y, text, termW)
    local x = math.floor((termW - #text) / 2)
    term.setCursorPos(x, y)
    term.write(text)
end

local function truncate(text, width)
    if #text <= width then return text end
    return text:sub(1, width - 3) .. "..."
end

local function findPeripheralsOfType(pType)
    local results = {}
    for _, name in ipairs(peripheral.getNames()) do
        if not pType or peripheral.getType(name) == pType then
            table.insert(results, name)
        end
    end
    return results
end

-- Constructor
function FormUI.new(title)
    local self = setmetatable({}, FormUI)
    self.title = title or "Form"
    self.fields = {}
    self.selected = 1
    self.errors = {}
    return self
end

-- Field helpers
function FormUI:addField(field)
    table.insert(self.fields, field)
end

function FormUI:text(label, default, validator)
    self:addField({
        type = "text",
        label = label,
        value = default or "",
        validate = validator or function(v)
            return v ~= nil and v ~= "", "Text cannot be empty"
        end
    })
end

function FormUI:number(label, default, validator)
    self:addField({
        type = "number",
        label = label,
        value = default or 0,
        validate = validator or function(v)
            return type(v) == "number", "Must be a valid number"
        end
    })
end

function FormUI:select(label, options, defaultIndex, validator)
    self:addField({
        type = "select",
        label = label,
        options = options or {},
        value = defaultIndex or 1,
        validate = validator or function(v, f)
            return f.options[v] ~= nil, "Must select a valid option"
        end
    })
end

function FormUI:peripheral(label, filterType, validator)
    local options = findPeripheralsOfType(filterType)
    self:addField({
        type = "peripheral",
        label = label,
        filter = filterType,
        options = options,
        value = (#options > 0) and 1 or 0,
        validate = validator or function(v, f)
            return f.options[v] ~= nil, "No valid peripheral selected"
        end
    })
end

-- Validation
function FormUI:validateField(i)
    local f = self.fields[i]
    if not f then return false, "Invalid field index" end
    if type(f.validate) == "function" then
        local ok, msg = f.validate(f.value, f)
        return ok, msg
    end
    return true
end

function FormUI:isValid()
    local errors = {}
    for i, f in ipairs(self.fields) do
        local ok, msg = self:validateField(i)
        if not ok then
            errors[f.label] = msg
        end
    end
    self.errors = errors
    return next(errors) == nil
end

function FormUI:get(label)
    for _, f in ipairs(self.fields) do
        if f.label == label then
            return (f.options and f.options[f.value]) or f.value
        end
    end
    return nil
end

-- Draw
function FormUI:draw()
    local w, h = term.getSize()
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.gray)
    term.clear()
    centerText(1, "» " .. self.title .. " «", w)

    term.setCursorPos(1, 4)
    for i, f in ipairs(self.fields) do
        local prefix = (i == self.selected) and "> " or "  "
        local display = ""

        if f.type == "text" or f.type == "number" then
            display = tostring(f.value)
        elseif f.type == "select" or f.type == "peripheral" then
            local opts = f.options or {}
            display = (#opts > 0) and tostring(opts[f.value]) or "(none)"
        end

        if self.errors[f.label] then
            term.setTextColor(colors.red)
        elseif i == self.selected then
            term.setTextColor(colors.yellow)
        else
            term.setTextColor(colors.white)
        end
        print(prefix .. f.label .. ": " .. display)

        -- Display error below field if selected or error exists
        if self.errors[f.label] then
            term.setTextColor(colors.red)
            print("! " .. self.errors[f.label])
        end
    end

    term.setCursorPos(1, h-2)
    term.setTextColor(colors.lightGray)
    print("^ / v - Navigate")
    print("Enter - Edit | Q - Quit")
    write("Ctrl+Enter Submit")
end

-- Edit a field
function FormUI:edit(index)
    local f = self.fields[index]
    if not f then return end
    term.setCursorPos(1, #self.fields + 5)
    term.setTextColor(colors.white)
    term.clearLine()

    self.errors[f.label] = nil

    if f.type == "text" or f.type == "number" then
        print("Enter value for " .. f.label .. ": ")
        local input = read()
        if input and input ~= "" then
            if f.type == "number" then
                input = tonumber(input)
                if input then
                    f.value = input
                else
                    term.setTextColor(colors.red)
                    print("Input must be a number!")
                    sleep(1)
                end
            else
                f.value = input
            end
        end
    elseif f.type == "select" or f.type == "peripheral" then
        local opts = f.options or {}
        if #opts == 0 then
            term.setTextColor(colors.red)
            print("No options available.")
            sleep(1)
        else
            local sel = f.value
            while true do
                term.clear()
                local w, _ = term.getSize()
                term.setTextColor(colors.lightGray)
                centerText(1, "Select Option", w)
                term.setTextColor(colors.white)
                centerText(2, f.label, w)
                for i, v in ipairs(opts) do
                    term.setCursorPos(4, 3 + i)
                    term.setTextColor(i == sel and colors.yellow or colors.white)
                    term.write(v)
                end
                local e, k = os.pullEvent("key")
                if k == keys.up then sel = (sel > 1) and sel - 1 or #opts
                elseif k == keys.down then sel = (sel < #opts) and sel + 1 or 1
                elseif k == keys.enter then f.value = sel; break
                elseif k == keys.q or k == keys.leftCtrl then break
                end
            end
        end
    end
end

-- Run the main loop
function FormUI:run()
    local w, h = term.getSize()
    local keysHeld = {}
    self:draw()

    while true do
        local e, k = os.pullEvent()
        if e == "key" then
            if k == keys.down then
                self.selected = (self.selected < #self.fields) and self.selected + 1 or 1
            elseif k == keys.up then
                self.selected = (self.selected > 1) and self.selected - 1 or #self.fields
            elseif k == keys.enter then
                if keysHeld[keys.leftCtrl] then
                    -- Try submission
                    if self:isValid() then
                        break
                    end
                else
                    self:edit(self.selected)
                end
            elseif k == keys.leftCtrl then
                keysHeld[k] = true
            elseif k == keys.q then
                return nil
            end
        elseif e == "key_up" then
            keysHeld[k] = nil
        end
        self:draw()
    end

    -- Return data
    local result = {}
    for _, f in ipairs(self.fields) do
        result[f.label] = (f.options and f.options[f.value]) or f.value
    end
    return result
end

return FormUI
