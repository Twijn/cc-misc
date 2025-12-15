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
---@version 0.4.0
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

local VERSION = "0.4.0"
local FormUI = { _v = VERSION }

-- ComputerCraft color names and their values
local COLOR_NAMES = {
    "white", "orange", "magenta", "lightBlue",
    "yellow", "lime", "pink", "gray",
    "lightGray", "cyan", "purple", "blue",
    "brown", "green", "red", "black"
}

local COLOR_VALUES = {
    white = colors.white, orange = colors.orange, magenta = colors.magenta, lightBlue = colors.lightBlue,
    yellow = colors.yellow, lime = colors.lime, pink = colors.pink, gray = colors.gray,
    lightGray = colors.lightGray, cyan = colors.cyan, purple = colors.purple, blue = colors.blue,
    brown = colors.brown, green = colors.green, red = colors.red, black = colors.black
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
        validate = function() return true end  -- Labels are always valid
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
        action = action or text:lower(),  -- Default action is lowercase text
        value = text,
        validate = function() return true end  -- Buttons are always valid
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
---@return fun(): string[] # Function to get selected options after submission
function FormUI:multiselect(label, options, defaultIndices)
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
                if v[i] then any = true break end
            end
            return any, "Must select at least one option"
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
                f.value = not not value  -- Coerce to boolean
                return true
            elseif f.type == "multiselect" then
                -- For multiselect fields, value should be a table of indices or a table of booleans
                if type(value) == "table" then
                    f.value = value
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
    local w, h = term.getSize()
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.gray)
    term.clear()
    centerText(1, "> " .. self.title .. " <", w)

    -- Calculate available space for fields (accounting for header and footer)
    local headerLines = 3  -- Title and spacing
    local footerLines = 3  -- Help text
    local availableLines = h - headerLines - footerLines
    
    -- Initialize scroll offset if not set
    if not self.scrollOffset then
        self.scrollOffset = 0
    end
    
    -- Calculate how many lines each field takes (accounting for text wrapping)
    local fieldLines = {}
    local totalLines = 0
    for i, f in ipairs(self.fields) do
        local lines = 1  -- Base field line
        
        -- Calculate actual display text to determine wrapping
        local displayText = ""
        if f.type == "label" then
            displayText = "  " .. f.text
        elseif f.type == "button" then
            displayText = "[ " .. f.text .. " ]"
        else
            local display = ""
            if f.type == "text" or f.type == "number" then
                display = tostring(f.value)
            elseif f.type == "select" or f.type == "peripheral" or f.type == "color" then
                local opts = f.options or {}
                display = (#opts > 0) and tostring(opts[f.value]) or "(none)"
            elseif f.type == "checkbox" then
                display = f.value and "[X]" or "[ ]"
            elseif f.type == "multiselect" then
                local opts = f.options or {}
                local sel = {}
                for idx, v in ipairs(opts) do
                    if f.value[idx] then table.insert(sel, v) end
                end
                display = (#sel > 0) and table.concat(sel, ", ") or "(none)"
            elseif f.type == "list" then
                display = (#f.value > 0) and ("[" .. table.concat(f.value, ", ") .. "]") or "(empty)"
            end
            displayText = "> " .. f.label .. ": " .. display
            if display == "" then
                displayText = displayText .. "< no value >"
            end
        end
        
        -- Calculate how many lines this text will take
        lines = math.ceil(#displayText / w)
        if lines < 1 then lines = 1 end
        
        if f.label and self.errors[f.label] then
            local errorText = "! " .. self.errors[f.label]
            lines = lines + math.ceil(#errorText / w)
        end
        fieldLines[i] = lines
        totalLines = totalLines + lines
    end
    
    -- Adjust scroll offset to keep selected field visible
    local selectedLineStart = 0
    for i = 1, self.selected - 1 do
        selectedLineStart = selectedLineStart + fieldLines[i]
    end
    local selectedLineEnd = selectedLineStart + fieldLines[self.selected]
    
    -- Scroll up if selected field is above visible area
    if selectedLineStart < self.scrollOffset then
        self.scrollOffset = selectedLineStart
    end
    
    -- Scroll down if selected field is below visible area
    if selectedLineEnd > self.scrollOffset + availableLines then
        self.scrollOffset = selectedLineEnd - availableLines
    end
    
    -- Clamp scroll offset
    self.scrollOffset = math.max(0, math.min(self.scrollOffset, math.max(0, totalLines - availableLines)))
    
    -- Draw fields with scrolling
    term.setCursorPos(1, headerLines + 1)
    local currentLine = 0
    
    for i, f in ipairs(self.fields) do
        local prefix = (i == self.selected) and "> " or "  "
        local display = ""

        if f.type == "text" or f.type == "number" then
            display = tostring(f.value)
        elseif f.type == "select" or f.type == "peripheral" or f.type == "color" then
            local opts = f.options or {}
            display = (#opts > 0) and tostring(opts[f.value]) or "(none)"
        elseif f.type == "checkbox" then
            display = f.value and "[X]" or "[ ]"
        elseif f.type == "multiselect" then
            local opts = f.options or {}
            local sel = {}
            for idx, v in ipairs(opts) do
                if f.value[idx] then table.insert(sel, v) end
            end
            display = (#sel > 0) and table.concat(sel, ", ") or "(none)"
        elseif f.type == "list" then
            display = (#f.value > 0) and ("[" .. table.concat(f.value, ", ") .. "]") or "(empty)"
        elseif f.type == "label" then
            display = ""  -- Labels don't show a value, just the text
        elseif f.type == "button" then
            display = ""  -- Buttons don't show a value, just the text
        end
        
        -- Check if this field is in the visible area
        local fieldStartLine = currentLine
        local fieldEndLine = currentLine + fieldLines[i] - 1
        
        -- Only draw if at least part of the field is visible
        if fieldEndLine >= self.scrollOffset and fieldStartLine < self.scrollOffset + availableLines then
            local y = headerLines + 1 + (currentLine - self.scrollOffset)
            
            if f.type == "label" then
                -- Labels are shown in light gray and not selectable
                term.setTextColor(colors.lightGray)
                local labelText = "  " .. f.text
                -- Truncate to fit on one line
                labelText = truncate(labelText, w - 1)
                term.setCursorPos(1, y)
                term.clearLine()
                term.write(labelText)
            elseif f.type == "button" then
                -- Buttons are shown with special styling
                term.setCursorPos(1, y)
                term.clearLine()
                if i == self.selected then
                    term.setTextColor(colors.black)
                    term.setBackgroundColor(colors.white)
                    write("[ " .. f.text .. " ]")
                    term.setBackgroundColor(colors.gray)
                else
                    term.setTextColor(colors.lightBlue)
                    write("[ " .. f.text .. " ]")
                end
            else
                if f.label and self.errors[f.label] then
                    term.setTextColor(colors.red)
                elseif i == self.selected then
                    term.setTextColor(colors.yellow)
                else
                    term.setTextColor(colors.white)
                end
                
                local fullText = prefix .. f.label .. ": " .. display
                if display == "" then
                    local noValueColor = (term.getTextColor() == colors.white) and colors.lightGray or term.getTextColor()
                    fullText = prefix .. f.label .. ": "
                    -- Truncate main part
                    fullText = truncate(fullText, w - 12) -- Leave room for "< no value >"
                    term.setCursorPos(1, y)
                    term.clearLine()
                    term.write(fullText)
                    term.setTextColor(noValueColor)
                    term.write("< no value >")
                else
                    -- Truncate to fit on one line
                    fullText = truncate(fullText, w - 1)
                    term.setCursorPos(1, y)
                    term.clearLine()
                    term.write(fullText)
                end
            end
        end
        
        -- Account for the lines this field takes (using pre-calculated value, but capped at 1 for simplicity)
        currentLine = currentLine + 1
        
        -- Draw error message if visible
        if f.label and self.errors[f.label] then
            if currentLine >= self.scrollOffset and currentLine < self.scrollOffset + availableLines then
                local y = headerLines + 1 + (currentLine - self.scrollOffset)
                term.setCursorPos(1, y)
                term.clearLine()
                term.setTextColor(colors.red)
                local errorText = truncate("! " .. self.errors[f.label], w - 1)
                term.write(errorText)
            end
            currentLine = currentLine + 1
        end
    end
    
    -- Draw scroll indicators
    if self.scrollOffset > 0 then
        term.setCursorPos(w, headerLines + 1)
        term.setTextColor(colors.white)
        term.write("^")
    end
    if self.scrollOffset + availableLines < totalLines then
        term.setCursorPos(w, h - footerLines)
        term.setTextColor(colors.white)
        term.write("v")
    end

    term.setCursorPos(1, h - 2)
    term.setTextColor(colors.lightGray)
    print("^ / v - Navigate")
    print("Enter - Edit/Button | Q - Quit")
    write("Ctrl+Enter Submit")
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
        return f.action  -- Return the action to be handled by the caller
    end
    term.setCursorPos(1, #self.fields + 5)
    term.setTextColor(colors.white)
    term.clearLine()

    self.errors[f.label] = nil

    if f.type == "text" or f.type == "number" then
        local prompt = "Enter value for " .. f.label
        if f.allowEmpty then
            prompt = prompt .. " (empty to clear)"
        end
        term.setTextColor(colors.white)
        print(prompt .. ":")
        term.setTextColor(colors.lightGray)
        local currentValue = tostring(f.value)
        print("Current: " .. (currentValue ~= "" and currentValue or "(empty)"))
        print("(Press Enter to confirm, or type \\c to cancel)")
        term.setTextColor(colors.white)
        write("> ")
        local input = read()
        
        -- Check for cancel command
        if input == "\\c" or input == nil then
            return -- Keep existing value
        end
        
        if f.type == "number" then
            if input ~= "" then
                local num = tonumber(input)
                if num then
                    f.value = num
                else
                    term.setTextColor(colors.red)
                    print("Input must be a number!")
                    sleep(1)
                end
            elseif f.allowEmpty then
                f.value = 0 -- For numbers, empty means 0 if allowed
            end
            -- If input is "" and allowEmpty is false, keep existing value
        else
            -- For text fields, update value
            if input == "" and f.allowEmpty then
                f.value = ""
            elseif input ~= "" then
                f.value = input
            end
            -- If input is "" and allowEmpty is false, keep existing value
        end
    elseif f.type == "select" or f.type == "peripheral" or f.type == "color" then
        local opts = f.options or {}
        if #opts == 0 then
            term.setTextColor(colors.red)
            print("No options available.")
            sleep(1)
        else
            -- Ensure sel is valid (between 1 and #opts)
            local sel = f.value
            if sel < 1 or sel > #opts then
                sel = 1
            end
            
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
                    term.write(tostring(v))
                end
                local e, k = os.pullEvent("key")
                if k == keys.up then sel = (sel > 1) and sel - 1 or #opts
                elseif k == keys.down then sel = (sel < #opts) and sel + 1 or 1
                elseif k == keys.enter then f.value = sel; break
                elseif k == keys.q or k == keys.leftCtrl then break
                end
            end
        end
    elseif f.type == "checkbox" then
        -- Toggle the checkbox value
        f.value = not f.value
    elseif f.type == "multiselect" then
        local opts = f.options or {}
        if #opts == 0 then
            term.setTextColor(colors.red)
            print("No options available.")
            sleep(1)
        else
            local sel = f.value
            local cur = 1
            while true do
                term.clear()
                local w, _ = term.getSize()
                term.setTextColor(colors.lightGray)
                centerText(1, "Multi-Select", w)
                term.setTextColor(colors.white)
                centerText(2, f.label, w)
                for i, v in ipairs(opts) do
                    term.setCursorPos(4, 3 + i)
                    local checked = sel[i] and "[X]" or "[ ]"
                    term.setTextColor(i == cur and colors.yellow or colors.white)
                    term.write(checked .. " " .. tostring(v))
                end
                term.setCursorPos(1, #opts + 5)
                term.setTextColor(colors.lightGray)
                term.write("Space: toggle | Enter: done | Up/Down: move")
                local e, k = os.pullEvent("key")
                if k == keys.up then cur = (cur > 1) and cur - 1 or #opts
                elseif k == keys.down then cur = (cur < #opts) and cur + 1 or 1
                elseif k == keys.space then sel[cur] = not sel[cur]
                elseif k == keys.enter then break
                elseif k == keys.q or k == keys.leftCtrl then break
                end
            end
            f.value = sel
        end
    elseif f.type == "list" then
        local list = f.value
        local cur = math.min(1, #list > 0 and #list or 1)
        while true do
            term.clear()
            local w, _ = term.getSize()
            term.setTextColor(colors.lightGray)
            centerText(1, "Edit List", w)
            term.setTextColor(colors.white)
            centerText(2, f.label .. " (" .. f.itemType .. ")", w)
            
            if #list == 0 then
                term.setCursorPos(4, 4)
                term.setTextColor(colors.lightGray)
                term.write("(empty list)")
            else
                for i, v in ipairs(list) do
                    term.setCursorPos(4, 3 + i)
                    term.setTextColor(i == cur and colors.yellow or colors.white)
                    term.write(tostring(i) .. ". " .. tostring(v))
                end
            end
            
            term.setCursorPos(1, math.max(6, #list + 5))
            term.setTextColor(colors.lightGray)
            term.write("A: add | D: delete | M: move | E: edit")
            term.setCursorPos(1, math.max(7, #list + 6))
            term.write("Up/Down: navigate | Enter: done")
            
            local e, k = os.pullEvent("key")
            if k == keys.up and #list > 0 then 
                cur = (cur > 1) and cur - 1 or #list
            elseif k == keys.down and #list > 0 then 
                cur = (cur < #list) and cur + 1 or 1
            elseif k == keys.a then
                term.setCursorPos(1, math.max(8, #list + 7))
                term.setTextColor(colors.white)
                term.clearLine()
                term.write("Add item: ")
                local input = read()
                if input and input ~= "" then
                    if f.itemType == "number" then
                        local num = tonumber(input)
                        if num then
                            table.insert(list, num)
                            cur = #list
                        else
                            term.setTextColor(colors.red)
                            term.write(" Invalid number!")
                            sleep(1)
                        end
                    else
                        table.insert(list, input)
                        cur = #list
                    end
                end
            elseif k == keys.d and #list > 0 then
                table.remove(list, cur)
                cur = math.max(1, math.min(cur, #list))
            elseif k == keys.m and #list > 1 then
                term.setCursorPos(1, math.max(8, #list + 7))
                term.setTextColor(colors.white)
                term.clearLine()
                term.write("Move to position (1-" .. #list .. "): ")
                local input = read()
                local pos = tonumber(input)
                if pos and pos >= 1 and pos <= #list then
                    local item = table.remove(list, cur)
                    table.insert(list, pos, item)
                    cur = pos
                end
            elseif k == keys.e and #list > 0 then
                term.setCursorPos(1, math.max(8, #list + 7))
                term.setTextColor(colors.white)
                term.clearLine()
                term.write("Edit item " .. cur .. ": ")
                local input = read()
                if input and input ~= "" then
                    if f.itemType == "number" then
                        local num = tonumber(input)
                        if num then
                            list[cur] = num
                        else
                            term.setTextColor(colors.red)
                            term.write(" Invalid number!")
                            sleep(1)
                        end
                    else
                        list[cur] = input
                    end
                end
            elseif k == keys.enter then 
                break
            elseif k == keys.q or k == keys.leftCtrl then 
                break
            end
        end
        f.value = list
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
    local w, h = term.getSize()
    local keysHeld = {}
    
    -- Find the first selectable field
    self.selected = 1
    if self.fields[1] and self.fields[1].type == "label" then
        self.selected = self:nextSelectableField(0)
    end
    
    self:draw()

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
                    local result = self:edit(self.selected)
                    -- Handle button actions
                    if result == "submit" then
                        if self:isValid() then break end
                    elseif result == "cancel" then
                        return nil
                    end
                end
            elseif k == keys.leftCtrl then
                keysHeld[k] = true
            elseif k == keys.q then
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
        self:draw()
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
    term.clear()
    term.setCursorPos(1,1)
    return result
end

-- Expose color constants for external use
FormUI.COLOR_NAMES = COLOR_NAMES
FormUI.COLOR_VALUES = COLOR_VALUES
FormUI.COLOR_VALUE_TO_NAME = COLOR_VALUE_TO_NAME

return FormUI
