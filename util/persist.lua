--- A persistence module for ComputerCraft that provides automatic data serialization
--- and storage to files with support for both Lua serialization and JSON formats.
---
--- Features: Automatic file creation and loading, deep copy functionality to handle circular references,
--- support for both Lua serialize and JSON formats, error handling with fallback mechanisms,
--- array and object manipulation methods, and automatic saving on data changes.
---
---@usage
---local persist = require("persist")
---local config = persist("config.json", false) -- Set to "true" to use textutils.serialize() rather than serializeJSON
---
---config.setDefault("port", 8080)
---config.set("name", "MyServer")
---print(config.get("port")) -- 8080
---
---@version 1.0.0
-- @module persist

local VERSION = "1.0.0"

local dataDir = "data/"
fs.makeDir(dataDir)

---Create a new persistence module for a specific file
---@param fileName string The name of the file to persist data to (stored in data/ directory)
---@param useSerialize? boolean Whether to use Lua serialization (true) or JSON (false/nil)
---@return PersistModule # Persistence module instance
return function(fileName, useSerialize)
    fileName = dataDir .. fileName

    ---@class PersistModule
    ---@field setDefault fun(key: any, defaultValue: any): nil Set a default value if key doesn't exist
    ---@field push fun(value: any, prepend?: boolean): nil Add value to array (append or prepend)
    ---@field set fun(key: any, value: any): nil Set a key-value pair and save
    ---@field unset fun(key: any): nil Remove a key and save
    ---@field clear fun(): nil Clear all data and save
    ---@field setAll fun(obj: table): nil Replace all data with new object and save
    ---@field get fun(key: any): any Get value by key
    ---@field getAll fun(): table Get the entire data object
    local persistModule = {}
    local object = {}

    ---Create a deep copy of a table while avoiding circular references
    ---@param original any The value to copy
    ---@param seen? table<string, boolean> Internal tracking table for circular reference detection
    ---@return any # Deep copy of the original value
    local function deepCopy(original, seen)
        seen = seen or {}
        
        if type(original) ~= "table" then
            return original
        end
        
        -- Check if we've already processed this table
        local tableId = tostring(original)
        if seen[tableId] then
            return nil  -- Break circular reference
        end
        seen[tableId] = true
        
        local copy = {}
        for key, value in pairs(original) do
            -- Skip if key and value are identical strings (common cause of repeated entries)
            if type(key) == "string" and type(value) == "string" and key == value then
                -- Skip this entry to avoid repeated key-value pairs
                print("Warning: Skipping repeated entry where key=value: " .. key)
            else
                copy[key] = deepCopy(value, seen)
            end
        end
        
        return copy
    end

    ---Save the current object to disk with error handling and circular reference protection
    local function save()
        local f = fs.open(fileName, "w")
        -- Ensure object is never nil before serializing
        if object == nil then
            object = {}
        end
        
        -- Create a clean copy without circular references
        local cleanObject = deepCopy(object)
        
        -- Try to serialize, with fallback error handling
        local success, result = pcall(textutils[useSerialize and "serialize" or "serializeJSON"], cleanObject)
        if success then
            f.write(result)
        else
            print("Serialization error in " .. fileName .. ": " .. tostring(result))
            print("Attempting to save empty object as fallback...")
            f.write(textutils[useSerialize and "serialize" or "serializeJSON"]({}))
        end
        f.close()
    end

    if fs.exists(fileName) then
        local f = fs.open(fileName, "r")
        local fileContent = f.readAll()
        f.close()
        
        -- Try to unserialize, fallback to empty table if it fails
        local success, result = pcall(textutils[useSerialize and "unserialize" or "unserializeJSON"], fileContent)
        if success and result ~= nil then
            object = result
        else
            object = {}
        end
    else
        save()
    end

    ---Set a default value for a key if it doesn't already exist
    ---@param key any The key to check and set
    ---@param defaultValue any The default value to set if key is missing
    persistModule.setDefault = function(key, defaultValue)
        if not object[key] then
            object[key] = defaultValue
        end
    end

    ---Add a value to the object as an array element and save
    ---@param value any The value to add
    ---@param prepend? boolean If true, add to beginning; otherwise add to end
    persistModule.push = function(value, prepend)
        if prepend then
            table.insert(object, 1, value)
        else
            table.insert(object, value)
        end
        save()
    end

    ---Set a key-value pair and automatically save to disk
    ---@param key any The key to set
    ---@param value any The value to store
    persistModule.set = function(key, value)
        object[key] = value
        save()
    end

    ---Remove a key from the object and save
    ---@param key any The key to remove
    persistModule.unset = function(key)
        persistModule.set(key, nil)
    end

    ---Clear all data from the object and save empty state
    persistModule.clear = function()
        object = {}
        save()
    end

    ---Replace the entire object with a new one and save
    ---@param obj table The new object to store
    persistModule.setAll = function(obj)
        object = obj
        save()
    end

    ---Get the value associated with a key
    ---@param key any The key to look up
    ---@return any # The value associated with the key, or nil if not found
    persistModule.get = function(key)
        return object[key]
    end

    ---Get the entire stored object
    ---@return table # The complete stored data object
    persistModule.getAll = function()
        return object
    end
    
    ---Module version
    persistModule.VERSION = VERSION

    return persistModule
end
