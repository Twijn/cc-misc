-- Dynamic Form UI for CC:Tweaked by Twijn
--- A dynamic form user interface library for ComputerCraft that provides interactive forms
--- with various field types, validation, and peripheral detection.
---
--- Features: Text and number input fields, select dropdowns and peripheral selection,
--- checkbox/toggle fields, multi-select dropdowns, list fields with item management,
--- built-in validation system, labels and buttons, real-time peripheral detection,
--- keyboard navigation with arrow keys, and form submission and cancellation.
---
---@usage
---local FormUI = require("formui")
---local form = FormUI.new("Configuration")
---
---local nameField = form:text("Name", "default")
---local portField = form:number("Port", 8080)
---local modemField = form:peripheral("Modem", "modem")
---local enabledField = form:checkbox("Enabled", true)
---local featuresField = form:multiselect("Features", {"feature1", "feature2", "feature3"})
---local itemsField = form:list("Items", {"item1", "item2"}, "string")
---
---form:addSubmitCancel()
---local result = form:run()
---if result then
---  print("Name:", nameField())
---  print("Port:", portField())
---  print("Enabled:", enabledField())
---  print("Features:", table.concat(featuresField(), ", "))
---end
---
---@version 0.5.3
-- @module formui

---@class FormField
---@field type string The field type: "text", "number", "select", "peripheral", "checkbox", "multiselect", "list", "label", "button", "color"
---@field label string The field label/name
---@field value any The current field value
---@field validate? fun(value: any, field: FormField): boolean, string? Validation function
---@field options? string[] Available options for select/peripheral fields
---@field filter? string Peripheral type filter for peripheral fields
---@field text? string Display text for labels and buttons
---@field action? string Action identifier for buttons
---@field itemType? string Type of items in list fields ("string" or "number")

---@class FormResult
---@field [string] any Field values indexed by label

---@alias ValidationFunction fun(value: any, field?: FormField): boolean, string?

local VERSION = "0.5.3"
local FormUI = { _v = VERSION }

-- ComputerCraft color names and their values
local COLOR_NAMES = {
    "white", "orange", "magenta", "lightBlue",
    "yellow", "lime", "pink", "gray",
    "lightGray", "cyan", "purple", "blue",
    "brown", "green", "red", "black"
}

local COLOR_VALUES = {
    white = colors.white,
    orange = colors.orange,
    magenta = colors.magenta,
    lightBlue = colors.lightBlue,
    yellow = colors.yellow,
    lime = colors.lime,
    pink = colors.pink,
    gray = colors.gray,
    lightGray = colors.lightGray,
    cyan = colors.cyan,
    purple = colors.purple,
    blue = colors.blue,
    brown = colors.brown,
    green = colors.green,
    red = colors.red,
    black = colors.black
}

-- Reverse lookup: color value to name
local COLOR_VALUE_TO_NAME = {}
for name, value in pairs(COLOR_VALUES) do
    COLOR_VALUE_TO_NAME[value] = name
end
FormUI.__index = FormUI

---@class FormValidation
---Built-in validation functions for common use cases
FormUI.validation = {
    ---Validate that a selected modem is wireless
    ---@type ValidationFunction
    modem_wireless = function(v, f)
        return peripheral.call(f.options[v], "isWireless"), "Modem must be wireless!"
    end,
    ---Validate that a selected modem is wired
    ---@type ValidationFunction
    modem_wired = function(v, f)
        return not peripheral.call(f.options[v], "isWireless"), "Modem must be wired!"
    end,
    ---Validate that a number is positive
    ---@type ValidationFunction
    number_positive = function(v)
        return v > 0, "Must be a positive number!"
    end,
    ---Create a validator for numbers within a specific range
    ---@param min number Minimum allowed value
    ---@param max number Maximum allowed value
    ---@return ValidationFunction
    number_range = function(min, max)
        return function(v)
            return (v >= min and v <= max),
                ("Must be between %d and %d"):format(min, max)
        end
    end,
    ---Validate that a number is an integer
    ---@type ValidationFunction
    number_integer = function(v)
        return math.floor(v) == v, "Must be an integer!"
    end,
    ---Validate that a string is not empty
    ---@type ValidationFunction
    string_nonempty = function(v)
        return v and v ~= "", "This field cannot be empty!"
    end,
    ---Create a validator for string length within a range
    ---@param min number Minimum string length
    ---@param max number Maximum string length
    ---@return ValidationFunction
    string_length = function(min, max)
        return function(v)
            local len = #v
            return len >= min and len <= max,
                ("Text length must be between %d and %d"):format(min, max)
        end
    end,
    ---Create a validator that checks if string matches a pattern
    ---@param pattern string Lua pattern to match against
    ---@param msg? string Custom error message
    ---@return ValidationFunction
    string_pattern = function(pattern, msg)
        return function(v)
            return string.match(v, pattern), msg or ("Must match pattern: " .. pattern)
        end
    end,
}

---Center text horizontally on the terminal at a specific line
---@param y number The line number to write on
---@param text string The text to center
---@param termW number The terminal width
local function centerText(y, text, termW)
    local x = math.floor((termW - #text) / 2)
    term.setCursorPos(x, y)
    term.write(text)
end

---Truncate text to fit within a specified width
---@param text string The text to truncate
---@param width number Maximum width
---@return string # Truncated text with "..." if needed
local function truncate(text, width)
    if #text <= width then return text end
    return text:sub(1, width - 3) .. "..."
end

---Find all peripherals of a specific type
---@param pType? string The peripheral type to filter by (nil for all)
---@return string[] # Array of peripheral names
local function findPeripheralsOfType(pType)
    local results = {}
    for _, name in ipairs(peripheral.getNames()) do
        if not pType or peripheral.getType(name) == pType then
            table.insert(results, name)
        end
    end
    return results
end

---Create a new FormUI instance
---@param title? string The form title (defaults to "Form")
---@return FormUI # New FormUI instance
function FormUI.new(title)
    local self = setmetatable({}, FormUI)
    self.title = title or "Form"
    self.fields = {}
    self.selected = 1
    self.errors = {}
    return self
end

---Add a field to the form and return a getter function
---@param field FormField The field definition to add
---@return fun(): any # Function that returns the field's final value after form submission
function FormUI:addField(field)
    table.insert(self.fields, field)
    return function()
        if not self.result or self.result[field.label] == nil then
            error("Could not get value for field " .. field.label)
        end
        return self.result[field.label]
    end
end

---Add a text input field
---@param label string The field label
---@param default? string Default value
---@param validator? ValidationFunction Custom validation function
---@param allowEmpty? boolean Whether empty values are allowed (default: false)
---@return fun(): string # Function to get the field value after submission
function FormUI:text(label, default, validator, allowEmpty)
    local allowEmptyValue = allowEmpty == true
    return self:addField({
        type = "text",
        label = label,
        value = default or "",
        allowEmpty = allowEmptyValue,
        validate = validator or function(v)
            if allowEmptyValue then
                return true
            end
            return v ~= nil and v ~= "", "Text cannot be empty"
        end
    })
end

---Add a number input field
---@param label string The field label
---@param default? number Default value
---@param validator? ValidationFunction Custom validation function
---@return fun(): number # Function to get the field value after submission
function FormUI:number(label, default, validator)
    return self:addField({
        type = "number",
        label = label,
        value = default or 0,
        validate = validator or function(v)
            return type(v) == "number", "Must be a valid number"
        end
    })
end

---Add a select dropdown field
---@param label string The field label
---@param options? string[] Available options
---@param defaultIndex? number Index of default selection (1-based)
---@param validator? ValidationFunction Custom validation function
---@return fun(): string # Function to get the selected option after submission
function FormUI:select(label, options, defaultIndex, validator)
    return self:addField({
        type = "select",
        label = label,
        options = options or {},
        value = defaultIndex or 1,
        validate = validator or function(v, f)
            return f.options[v] ~= nil, "Must select a valid option"
        end
    })
end

---Add a peripheral selector field that automatically detects peripherals
---@param label string The field label
---@param filterType? string Peripheral type to filter by (e.g., "modem", "monitor")
---@param validator? ValidationFunction Custom validation function
---@param defaultValue? string|number Default peripheral (name or index)
---@return fun(): string # Function to get the selected peripheral name after submission
function FormUI:peripheral(label, filterType, validator, defaultValue)
    local options = findPeripheralsOfType(filterType)
    local value = (#options > 0) and 1 or 0
    if defaultValue then
        if type(defaultValue) == "number" then
            value = defaultValue
        elseif type(defaultValue) == "string" then
            for index, opt in pairs(options) do
                if opt == defaultValue then
                    value = index
                    break
                end
            end
        end
    end
    return self:addField({
        type = "peripheral",
        label = label,
        filter = filterType,
        options = options,
        value = value,
        validate = validator or function(v, f)
            return f.options[v] ~= nil, "No valid peripheral selected"
        end
    })
end

---Add a non-interactive label for display purposes
---@param text string The label text to display
---@return fun(): string # Function to get the label text (always returns the same text)
function FormUI:label(text)
    return self:addField({
        type = "label",
        label = text,
        text = text,
        value = text,
        validate = function() return true end -- Labels are always valid
    })
end

---Add a button that can trigger actions
---@param text string The button text
---@param action? string Action identifier (defaults to lowercase text)
---@return fun(): string # Function to get the button text
function FormUI:button(text, action)
    return self:addField({
        type = "button",
        label = text,
        text = text,
        action = action or text:lower(),      -- Default action is lowercase text
        value = text,
        validate = function() return true end -- Buttons are always valid
    })
end

---Add a checkbox/toggle field
---@param label string The field label
---@param default? boolean Default value (true/false)
---@return fun(): boolean # Function to get the field value after submission
function FormUI:checkbox(label, default)
    return self:addField({
        type = "checkbox",
        label = label,
        value = default == nil and false or default,
        validate = function(v)
            return type(v) == "boolean", "Must be true or false"
        end
    })
end

---Add a color selector field
---@param label string The field label
---@param default? number Default color value (e.g., colors.white)
---@return fun(): number # Function to get the selected color value after submission
function FormUI:color(label, default)
    local defaultIndex = 1
    if default then
        local defaultName = COLOR_VALUE_TO_NAME[default]
        if defaultName then
            for i, name in ipairs(COLOR_NAMES) do
                if name == defaultName then
                    defaultIndex = i
                    break
                end
            end
        end
    end
    return self:addField({
        type = "color",
        label = label,
        options = COLOR_NAMES,
        value = defaultIndex,
        validate = function(v, f)
            return f.options[v] ~= nil, "Must select a valid color"
        end
    })
end

---Add a multi-select dropdown field
---@param label string The field label
---@param options string[] Available options
---@param defaultIndices? number[] Indices of default selections (1-based)
---@param validator? fun(v: boolean[], f: table): boolean, string # Custom validation function
---@return fun(): string[] # Function to get selected options after submission
function FormUI:multiselect(label, options, defaultIndices, validator)
    local selected = {}
    if defaultIndices then
        for _, idx in ipairs(defaultIndices) do
            selected[idx] = true
        end
    end
    return self:addField({
        type = "multiselect",
        label = label,
        options = options or {},
        value = selected,
        validate = function(v, f)
            local any = false
            for i = 1, #(f.options or {}) do
                if v[i] then
                    any = true
                    break
                end
            end
            if not any then
                return false, "Must select at least one option"
            end
            if validator then
                return validator(v, f)
            end
            return true
        end
    })
end

---Add a list field (string or number list, with item reordering)
---@param label string The field label
---@param default? table Default list value
---@param itemType? string "string" or "number"
---@return fun(): table # Function to get the list after submission
function FormUI:list(label, default, itemType)
    return self:addField({
        type = "list",
        label = label,
        value = default or {},
        itemType = itemType or "string",
        validate = function(v, f)
            if type(v) ~= "table" then return false, "List must be a table" end
            for _, item in ipairs(v) do
                if f.itemType == "number" and type(item) ~= "number" then
                    return false, "All items must be numbers"
                elseif f.itemType == "string" and type(item) ~= "string" then
                    return false, "All items must be strings"
                end
            end
            return true
        end
    })
end

---Add standard Submit and Cancel buttons to the form
function FormUI:addSubmitCancel()
    self:button("Submit", "submit")
    self:button("Cancel", "cancel")
end

---Validate a specific field by index
---@param i number The field index to validate
---@return boolean success Whether validation passed
---@return string? error Error message if validation failed
function FormUI:validateField(i)
    local f = self.fields[i]
    if not f then return false, "Invalid field index" end
    if type(f.validate) == "function" then
        local ok, msg = f.validate(f.value, f)
        return ok, msg
    end
    return true
end

---Validate all fields in the form
---@return boolean # True if all fields are valid
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

---Get the current value of a field by label
---@param label string The field label
---@return any # The field's current value, or nil if not found
function FormUI:get(label)
    for _, f in ipairs(self.fields) do
        if f.label == label then
            if f.type == "color" then
                local colorName = f.options[f.value]
                return colorName and COLOR_VALUES[colorName] or colors.white
            elseif f.type == "select" or f.type == "peripheral" then
                return f.options[f.value]
            elseif f.type == "multiselect" then
                local selected = {}
                for idx, isSelected in pairs(f.value) do
                    if isSelected and f.options[idx] then
                        table.insert(selected, f.options[idx])
                    end
                end
                return selected
            else
                return f.value
            end
        end
    end
    return nil
end

local function centeredWindow(parent, title, width, height, footer)
    local w, h = parent.getSize()

    -- set width and height to defaults
    width = width or (w - 4)
    height = height or (h - 2)

    -- ensure symmetry
    if w % 2 ~= width % 2 then width = width + 1 end
    if h % 2 ~= height % 2 then height = height + 1 end

    -- calculate position
    local x = math.ceil((w - width) / 2) + 1
    local y = math.ceil((h - height) / 2) + 1

    -- create frame
    local frame = window.create(parent, x, y, width, height)

    frame.setBackgroundColor(colors.gray)
    frame.clear()

    frame.setBackgroundColor(colors.blue)
    frame.setTextColor(colors.white)
    frame.setCursorPos(2, 1)
    frame.clearLine()
    frame.write(title)

    frame.setBackgroundColor(colors.black)

    if footer then
        if type(footer) == "string" then footer = { footer } end

        frame.setBackgroundColor(colors.gray)
        frame.setTextColor(colors.lightGray)
        for i = 1, #footer do
            frame.setCursorPos(2, height - #footer + i)
            frame.write(footer[i])
        end
    end

    local innerWin = window.create(frame, 1, 2, width, height - 1 - (type(footer) == "table" and #footer or 0))
    return innerWin, frame
end

---Set the value of a field by label
---@param label string The field label
---@param value any The new value to set
---@return boolean # True if field was found and updated, false otherwise
function FormUI:setValue(label, value)
    for _, f in ipairs(self.fields) do
        if f.label == label then
            if f.type == "color" then
                -- For color fields, value can be color value or color name
                if type(value) == "number" then
                    local colorName = COLOR_VALUE_TO_NAME[value]
                    if colorName then
                        for i, name in ipairs(f.options) do
                            if name == colorName then
                                f.value = i
                                return true
                            end
                        end
                    end
                elseif type(value) == "string" then
                    for i, name in ipairs(f.options) do
                        if name == value then
                            f.value = i
                            return true
                        end
                    end
                end
                return false
            elseif f.type == "select" or f.type == "peripheral" then
                -- For select/peripheral fields, find the index of the option
                if type(value) == "string" and f.options then
                    for i, opt in ipairs(f.options) do
                        if opt == value then
                            f.value = i
                            return true
                        end
                    end
                elseif type(value) == "number" then
                    -- Direct index setting
                    f.value = value
                    return true
                end
            elseif f.type == "checkbox" then
                -- For checkbox fields, set boolean value
                f.value = not not value -- Coerce to boolean
                return true
            elseif f.type == "multiselect" then
                -- For multiselect fields, value can be a table of indices or a boolean map
                if type(value) == "table" then
                    local selected = {}
                    local isIndexList = true

                    for key, item in pairs(value) do
                        if type(key) ~= "number" or type(item) ~= "number" then
                            isIndexList = false
                            break
                        end

                        if type(item) ~= "number" then
                            isIndexList = false
                            break
                        end
                    end

                    if isIndexList then
                        for _, idx in ipairs(value) do
                            if type(idx) == "number" and f.options and f.options[idx] then
                                selected[idx] = true
                            end
                        end
                    else
                        for idx, isSelected in pairs(value) do
                            if type(idx) == "number" and isSelected and f.options and f.options[idx] then
                                selected[idx] = true
                            end
                        end
                    end

                    f.value = selected
                    return true
                end
            elseif f.type == "list" then
                -- For list fields, set the table value directly
                if type(value) == "table" then
                    f.value = value
                    return true
                end
            else
                -- For text, number, label, and button fields, set directly
                f.value = value
                return true
            end
        end
    end
    return false
end

---Draw the form to the terminal
function FormUI:draw()
    local term = self.win or term.current() -- use window if provided
    local w, h = term.getSize()

    local function getFieldDisplayText(f, prefix)
        if f.type == "label" then
            return f.text
        elseif f.type == "button" then
            return "[ " .. f.text .. " ]"
        end

        local display = ""
        if f.type == "text" or f.type == "number" then
            display = tostring(f.value)
        elseif f.type == "select" or f.type == "peripheral" or f.type == "color" then
            local opts = f.options or {}
            display = (#opts > 0 and opts[f.value] ~= nil) and tostring(opts[f.value]) or "(none)"
        elseif f.type == "checkbox" then
            display = f.value and "[X]" or "[ ]"
        elseif f.type == "multiselect" then
            local opts = f.options or {}
            local sel = {}
            for idx, value in ipairs(opts) do
                if f.value[idx] then
                    table.insert(sel, value)
                end
            end
            display = (#sel > 0) and table.concat(sel, ", ") or "(none)"
        elseif f.type == "list" then
            display = (#(f.value or {}) > 0) and ("[" .. table.concat(f.value, ", ") .. "]") or "(empty)"
        else
            display = tostring(f.value or "")
        end

        return (prefix or "") .. f.label .. ": " .. display
    end

    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.gray)
    term.clear()

    -- Layout config
    local headerLines = 1
    local availableLines = h - headerLines
    local baseY = headerLines + 1

    -- Init scroll
    self.scrollOffset = self.scrollOffset or 0

    -- Calculate field heights
    local fieldLines = {}
    local totalLines = 0

    for i, f in ipairs(self.fields) do
        local displayText
        if f.type == "label" or f.type == "button" then
            displayText = getFieldDisplayText(f)
        else
            displayText = getFieldDisplayText(f, "> ")
        end

        local lines = math.max(1, math.ceil(#displayText / (w - 2)))

        if f.label and self.errors[f.label] then
            lines = lines + math.ceil(#("! " .. self.errors[f.label]) / (w - 2))
        end

        fieldLines[i] = lines
        totalLines = totalLines + lines
    end

    -- Scroll logic
    local selectedStart = 0
    for i = 1, self.selected - 1 do
        selectedStart = selectedStart + fieldLines[i]
    end

    local selectedEnd = selectedStart + fieldLines[self.selected]

    if selectedStart < self.scrollOffset then
        self.scrollOffset = selectedStart
    end

    if selectedEnd > self.scrollOffset + availableLines then
        self.scrollOffset = selectedEnd - availableLines
    end

    self.scrollOffset = math.max(0,
        math.min(self.scrollOffset, math.max(0, totalLines - availableLines))
    )

    -- DRAW FIELDS
    local currentLine = 0

    for i, f in ipairs(self.fields) do
        local startLine = currentLine
        local endLine = currentLine + fieldLines[i]

        if endLine >= self.scrollOffset and startLine < self.scrollOffset + availableLines then
            local y = baseY + (currentLine - self.scrollOffset)

            local prefix = (i == self.selected) and "> " or "  "

            local function wrapText(text, width)
                local lines = {}
                local i = 1
                while i <= #text do
                    table.insert(lines, text:sub(i, i + width - 1))
                    i = i + width
                end
                return lines
            end

            local function drawLine(text, color)
                if y >= baseY and y < baseY + availableLines then
                    term.setCursorPos(2, y)
                    term.clearLine()
                    term.setTextColor(color or colors.white)
                    term.write(text)
                end
                y = y + 1
            end

            if f.type == "label" then
                for _, line in ipairs(wrapText(f.text, w - 2)) do
                    drawLine(line, colors.lightBlue)
                end
            elseif f.type == "button" then
                if i == self.selected then
                    term.setBackgroundColor(colors.white)
                    drawLine("[ " .. f.text .. " ]", colors.black)
                    term.setBackgroundColor(colors.gray)
                else
                    drawLine("[ " .. f.text .. " ]", colors.lightBlue)
                end
            else
                local color = colors.white
                if f.label and self.errors[f.label] then
                    color = colors.red
                elseif i == self.selected then
                    color = colors.yellow
                end

                local fullText = getFieldDisplayText(f, prefix)
                for _, line in ipairs(wrapText(fullText, w - 2)) do
                    drawLine(line, color)
                end
            end

            -- Error line
            if f.label and self.errors[f.label] then
                drawLine("! " .. self.errors[f.label], colors.red)
            end
        end

        currentLine = currentLine + fieldLines[i]
    end

    -- Scroll indicators
    term.setTextColor(colors.white)
    if self.scrollOffset > 0 then
        term.setCursorPos(w, baseY)
        term.write("^")
    end

    if self.scrollOffset + availableLines < totalLines then
        term.setCursorPos(w, h)
        term.write("v")
    end
end

---Edit a field at the specified index
---@param index number The field index to edit
---@return string? action Action identifier if a button was pressed
function FormUI:edit(index)
    local f = self.fields[index]
    if not f then return end

    -- Labels are not editable
    if f.type == "label" then return end

    -- Handle button actions
    if f.type == "button" then
        return f.action
    end

    self.errors[f.label] = nil

    local function openPrompt(title, height, footer)
        local previous = term.current()
        local parent = previous

        if self._nativeTerm and self.frame and previous == self._nativeTerm then
            parent = self.frame
        end

        local parentW, parentH = parent.getSize()
        local promptWidth = math.max(math.floor(parentW * 0.8), 26)
        local promptHeight = math.max(height or 4, 4)
        if parentH > 2 then
            promptHeight = math.min(promptHeight, parentH - 2)
        end

        local promptWin, promptFrame = centeredWindow(parent, title, promptWidth, promptHeight, footer)
        term.redirect(promptWin)
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.clear()
        return previous, promptFrame, parent
    end

    local function closePrompt(previous, promptFrame, parent)
        if promptFrame and promptFrame.setVisible then
            promptFrame.setVisible(false)
        end
        term.redirect(previous)
        if parent and parent.redraw then
            parent.redraw()
        elseif self.frame and self.frame.redraw then
            self.frame.redraw()
        elseif previous and previous.redraw then
            previous.redraw()
        end
    end

    local function writeCenteredLine(y, text, textColor, backgroundColor)
        local w, _ = term.getSize()
        local display = truncate(tostring(text or ""), w)
        term.setBackgroundColor(backgroundColor or colors.lightGray)
        term.setCursorPos(1, y)
        term.clearLine()
        term.setTextColor(textColor or colors.black)
        term.setCursorPos(math.max(1, math.floor((w - #display) / 2) + 1), y)
        term.write(display)
    end

    local function cloneArray(values)
        local copy = {}
        for i, value in ipairs(values or {}) do
            copy[i] = value
        end
        return copy
    end

    local function cloneMap(values)
        local copy = {}
        for key, value in pairs(values or {}) do
            copy[key] = value
        end
        return copy
    end

    local function promptInput(label, currentValue, validate, transform)
        local previous, promptFrame, parent = openPrompt(label, 5)
        local w, _ = term.getSize()
        local errorMessage = nil
        currentValue = currentValue or ""

        while true do
            term.setBackgroundColor(colors.lightGray)
            term.clear()
            term.setCursorPos(2, 2)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.write(string.rep(" ", math.max(1, w - 2)))

            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.red)
            term.setCursorPos(2, 3)
            term.clearLine()
            if errorMessage then
                term.write(truncate(tostring(errorMessage), math.max(1, w - 2)))
            end

            term.setCursorPos(2, 2)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            currentValue = read(nil, nil, nil, currentValue)

            if not validate then
                closePrompt(previous, promptFrame, parent)
                return currentValue
            end

            local value = transform and transform(currentValue) or currentValue
            local valid, err = validate(value)
            if valid then
                closePrompt(previous, promptFrame, parent)
                return currentValue
            end

            errorMessage = err or "Invalid input"
        end
    end

    local function renderScrollableOptions(opts, selectedIndex, renderOption)
        local w, h = term.getSize()
        term.setBackgroundColor(colors.lightGray)
        term.clear()

        if #opts == 0 then
            writeCenteredLine(math.max(1, math.ceil(h / 2)), "(empty)", colors.gray, colors.lightGray)
            return
        end

        local centerRow = math.ceil(h / 2)
        local maxStart = math.max(1, #opts - h + 1)
        local startIndex = math.max(1, math.min(selectedIndex - centerRow + 1, maxStart))

        for row = 1, h do
            local optionIndex = startIndex + row - 1
            if optionIndex <= #opts then
                local isSelected = optionIndex == selectedIndex
                local bg = isSelected and colors.gray or colors.lightGray
                local fg = isSelected and colors.white or colors.black
                writeCenteredLine(row, renderOption(optionIndex, opts[optionIndex]), fg, bg)
            else
                term.setBackgroundColor(colors.lightGray)
                term.setCursorPos(1, row)
                term.clearLine()
            end
        end

        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.gray)
        if startIndex > 1 then
            term.setCursorPos(w, 1)
            term.write("^")
        end
        if startIndex + h - 1 < #opts then
            term.setCursorPos(w, h)
            term.write("v")
        end
    end

    local function selectInput(label, opts, currentValue)
        local previous, promptFrame, parent = openPrompt(label, 12, {
            "Up/Down: move | Enter: select",
            "Q/Ctrl: cancel",
        })

        local sel = tonumber(currentValue) or 1
        if sel < 1 or sel > #opts then
            sel = 1
        end

        while true do
            renderScrollableOptions(opts, sel, function(_, option)
                return tostring(option)
            end)

            local _, key = os.pullEvent("key")
            if key == keys.up then
                sel = (sel > 1) and (sel - 1) or #opts
            elseif key == keys.down then
                sel = (sel < #opts) and (sel + 1) or 1
            elseif key == keys.enter then
                closePrompt(previous, promptFrame, parent)
                return sel
            elseif key == keys.q or key == keys.leftCtrl then
                closePrompt(previous, promptFrame, parent)
                return nil
            end
        end
    end

    local function multiselectInput(label, opts, currentValue)
        local previous, promptFrame, parent = openPrompt(label, 12, {
            "Up/Down: move | Space: toggle",
            "Enter: save | Q/Ctrl: cancel",
        })

        local selected = cloneMap(currentValue)
        local cur = 1
        if #opts > 0 then
            for i = 1, #opts do
                if selected[i] then
                    cur = i
                    break
                end
            end
        end

        while true do
            renderScrollableOptions(opts, cur, function(optionIndex, option)
                return (selected[optionIndex] and "[X] " or "[ ] ") .. tostring(option)
            end)

            local _, key = os.pullEvent("key")
            if key == keys.up then
                cur = (cur > 1) and (cur - 1) or #opts
            elseif key == keys.down then
                cur = (cur < #opts) and (cur + 1) or 1
            elseif key == keys.space then
                selected[cur] = not selected[cur]
            elseif key == keys.enter then
                closePrompt(previous, promptFrame, parent)
                return selected
            elseif key == keys.q or key == keys.leftCtrl then
                closePrompt(previous, promptFrame, parent)
                return nil
            end
        end
    end

    local function listInput(label, currentList, itemType)
        local previous, promptFrame, parent = openPrompt(label .. " (" .. itemType .. ")", 14, {
            "Up/Down: move | A: add | E: edit | D: delete",
            "M: move item | Enter: save | Q/Ctrl: cancel",
        })

        local list = cloneArray(currentList)
        local cur = (#list > 0) and 1 or 1

        local function validateListItem(value)
            if value == nil or value == "" then
                return false, "Item cannot be empty"
            end
            if itemType == "number" and tonumber(value) == nil then
                return false, "Item must be a valid number"
            end
            return true
        end

        local function parseListItem(value)
            if itemType == "number" then
                return tonumber(value)
            end
            return value
        end

        while true do
            local w, h = term.getSize()
            term.setBackgroundColor(colors.lightGray)
            term.clear()

            if #list == 0 then
                writeCenteredLine(math.max(1, math.ceil(h / 2)), "(empty list)", colors.gray, colors.lightGray)
            else
                renderScrollableOptions(list, cur, function(optionIndex, option)
                    return tostring(optionIndex) .. ". " .. tostring(option)
                end)
            end

            local _, key = os.pullEvent("key")
            if key == keys.up and #list > 0 then
                cur = (cur > 1) and (cur - 1) or #list
            elseif key == keys.down and #list > 0 then
                cur = (cur < #list) and (cur + 1) or 1
            elseif key == keys.a then
                local input = promptInput("Add item to " .. label, "", validateListItem)
                if input and input ~= "" then
                    table.insert(list, parseListItem(input))
                    cur = #list
                end
            elseif key == keys.e and #list > 0 then
                local input = promptInput("Edit item " .. cur, tostring(list[cur]), validateListItem)
                if input and input ~= "" then
                    list[cur] = parseListItem(input)
                end
            elseif key == keys.d and #list > 0 then
                table.remove(list, cur)
                if #list == 0 then
                    cur = 1
                else
                    cur = math.max(1, math.min(cur, #list))
                end
            elseif key == keys.m and #list > 1 then
                local input = promptInput(
                    "Move item " .. cur .. " to position",
                    tostring(cur),
                    function(value)
                        local pos = tonumber(value)
                        return pos ~= nil and pos >= 1 and pos <= #list,
                            "Position must be between 1 and " .. #list
                    end
                )
                local pos = tonumber(input)
                if pos and pos >= 1 and pos <= #list then
                    local item = table.remove(list, cur)
                    table.insert(list, pos, item)
                    cur = pos
                end
            elseif key == keys.enter then
                closePrompt(previous, promptFrame, parent)
                return list
            elseif key == keys.q or key == keys.leftCtrl then
                closePrompt(previous, promptFrame, parent)
                return nil
            end
        end
    end

    if f.type == "text" or f.type == "number" then
        local currentValue = tostring(f.value)
        local validate = f.validate
        local transform = (f.type == "number") and tonumber or nil
        local input = promptInput("Enter value for " .. f.label, currentValue, validate, transform)

        if f.type == "number" then
            local num = tonumber(input)
            if num then
                f.value = num
            end
        else
            if input == "" and f.allowEmpty then
                f.value = ""
            elseif input ~= "" then
                f.value = input
            end
        end
    elseif f.type == "select" or f.type == "peripheral" or f.type == "color" then
        local opts = f.options or {}
        if #opts == 0 then
            term.setTextColor(colors.red)
            print("No options available.")
            sleep(1)
        else
            local selected = selectInput(f.label, opts, f.value)
            if selected then
                f.value = selected
            end
        end
    elseif f.type == "checkbox" then
        f.value = not f.value
    elseif f.type == "multiselect" then
        local opts = f.options or {}
        if #opts == 0 then
            term.setTextColor(colors.red)
            print("No options available.")
            sleep(1)
        else
            local selected = multiselectInput(f.label, opts, f.value)
            if selected then
                f.value = selected
            end
        end
    elseif f.type == "list" then
        local list = listInput(f.label, f.value, f.itemType)
        if list then
            f.value = list
        end
    end
end

---Find the next selectable field index (skips labels)
---@param from number Starting field index
---@return number # Next selectable field index (wraps around)
function FormUI:nextSelectableField(from)
    for i = from + 1, #self.fields do
        if self.fields[i].type ~= "label" then
            return i
        end
    end
    -- Wrap around to the beginning
    for i = 1, from do
        if self.fields[i].type ~= "label" then
            return i
        end
    end
    return from -- fallback if no selectable fields
end

---Find the previous selectable field index (skips labels)
---@param from number Starting field index
---@return number # Previous selectable field index (wraps around)
function FormUI:prevSelectableField(from)
    for i = from - 1, 1, -1 do
        if self.fields[i].type ~= "label" then
            return i
        end
    end
    -- Wrap around to the end
    for i = #self.fields, from, -1 do
        if self.fields[i].type ~= "label" then
            return i
        end
    end
    return from -- fallback if no selectable fields
end

---Run the form's main input loop
---@return FormResult? result Table of field values indexed by label, or nil if cancelled
function FormUI:run()
    local native = term.current()
    self._nativeTerm = native

    local keysHeld = {}

    local formWindow, formFrame = centeredWindow(term.current(), self.title, nil, nil, {
        "Arrows: navigate | Enter: edit",
        "Ctrl+Enter: submit",
    })

    self.win = formWindow
    self.frame = formFrame

    -- Find the first selectable field
    self.selected = 1
    if self.fields[1] and self.fields[1].type == "label" then
        self.selected = self:nextSelectableField(0)
    end

    local function close()
        formWindow.setVisible(false)
        self._nativeTerm = nil
        term.redirect(native)
        if native and native.redraw then
            native.redraw()
        else
            term.clear()
            term.setCursorPos(1, 1)
        end
        sleep()
    end

    term.redirect(formWindow)
    self:draw()
    term.redirect(native)

    while true do
        local e = table.pack(os.pullEvent())
        local event = e[1]
        if event == "key" then
            local k = e[2]
            if k == keys.down then
                self.selected = self:nextSelectableField(self.selected)
            elseif k == keys.up then
                self.selected = self:prevSelectableField(self.selected)
            elseif k == keys.enter then
                if keysHeld[keys.leftCtrl] then
                    if self:isValid() then break end
                else
                    local editResult = self:edit(self.selected)
                    -- Handle button actions
                    if editResult == "submit" then
                        if self:isValid() then break end
                    elseif editResult == "cancel" then
                        close()
                        return nil
                    elseif editResult then
                        -- Any other button action - return immediately with action info
                        -- Build result with all field values plus the action
                        local result = {}
                        for _, f in ipairs(self.fields) do
                            if f.type == "color" then
                                local colorName = f.options[f.value]
                                result[f.label] = colorName and COLOR_VALUES[colorName] or colors.white
                            elseif f.type == "select" or f.type == "peripheral" then
                                result[f.label] = f.options[f.value]
                            elseif f.type == "multiselect" then
                                local selected = {}
                                for idx, isSelected in pairs(f.value) do
                                    if isSelected and f.options[idx] then
                                        table.insert(selected, f.options[idx])
                                    end
                                end
                                result[f.label] = selected
                            elseif f.type == "button" then
                                -- Mark pressed button as true, others as false
                                result[f.label] = (f.action == editResult)
                            else
                                result[f.label] = f.value
                            end
                        end
                        result._action = editResult -- Store the action for easy access
                        self.result = result

                        close()
                        return result
                    end
                end
            elseif k == keys.leftCtrl then
                keysHeld[k] = true
            elseif k == keys.q then
                close()
                return nil
            end
        elseif event == "key_up" then
            keysHeld[e[2]] = nil
        elseif event == "peripheral" then
            local side = e[2]
            for _, field in pairs(self.fields) do
                if field.type == "peripheral" and peripheral.hasType(side, field.filter) then
                    -- prevent duplicates
                    local exists = false
                    for _, name in ipairs(field.options) do
                        if name == side then
                            exists = true
                            break
                        end
                    end
                    if not exists then
                        table.insert(field.options, side)
                        if field.value == 0 then
                            self.errors[field.label] = nil
                            field.value = #field.options
                        end
                    end
                end
            end
        elseif event == "peripheral_detach" then
            local side = e[2]
            for _, field in pairs(self.fields) do
                if field.type == "peripheral" then
                    local removedIndex
                    for i, name in ipairs(field.options) do
                        if name == side then
                            removedIndex = i
                            break
                        end
                    end
                    if removedIndex then
                        table.remove(field.options, removedIndex)
                        if field.value == removedIndex then
                            field.value = 0
                        elseif field.value > removedIndex then
                            field.value = field.value - 1
                        end
                    end
                end
            end
        end

        term.redirect(formWindow)
        self:draw()
        term.redirect(native)
    end

    local result = {}
    for _, f in ipairs(self.fields) do
        if f.type == "color" then
            local colorName = f.options[f.value]
            result[f.label] = colorName and COLOR_VALUES[colorName] or colors.white
        elseif f.type == "select" or f.type == "peripheral" then
            result[f.label] = f.options[f.value]
        elseif f.type == "multiselect" then
            local selected = {}
            for idx, isSelected in pairs(f.value) do
                if isSelected and f.options[idx] then
                    table.insert(selected, f.options[idx])
                end
            end
            result[f.label] = selected
        else
            result[f.label] = f.value
        end
    end
    self.result = result

    close()
    return result
end

-- Expose color constants for external use
FormUI.COLOR_NAMES = COLOR_NAMES
FormUI.COLOR_VALUES = COLOR_VALUES
FormUI.COLOR_VALUE_TO_NAME = COLOR_VALUE_TO_NAME

return FormUI
