--- A utility module for table operations in ComputerCraft providing common table manipulation
--- functions like searching, counting, copying, and comparison operations.
---
--- Features: Element existence checking with includes(), table size counting for any table type,
--- deep recursive copying with nested table support, deep recursive equality comparison,
--- and works with both array-like and associative tables.
---
--- @module tables

local module = {}

---Check if a table contains a specific value
---@param table table The table to search in
---@param object any The value to search for
---@return boolean # True if the object is found in the table
function module.includes(table, object)
    for i,v in pairs(table) do
        if v == object then return true end
    end
    return false
end

---Count the number of elements in a table (works with both arrays and associative tables)
---@param table table The table to count elements in
---@return number # The number of key-value pairs in the table
function module.count(table)
    local count = 0
    for i,v in pairs(table) do
        count = count + 1
    end
    return count
end

---Create a deep copy of a table, recursively copying all nested tables
---@param table table The table to copy
---@return table # A new table with all values copied (nested tables are also copied)
function module.recursiveCopy(table)
    local newTable = {}
    for i,v in pairs(table) do
        if type(v) == "table" then
            newTable[i] = module.recursiveCopy(v)
        else
            newTable[i] = v
        end
    end
    return newTable
end

---Compare two tables for deep equality, recursively checking nested tables
---@param t1 table The first table to compare
---@param t2 table The second table to compare
---@return boolean # True if both tables have the same structure and values
function module.recursiveEquals(t1, t2)
    for i,v1 in pairs(t1) do
        local v2 = t2[i]
        if type(v1) == "table" then
            if type(v2) == "table" then
                if not module.recursiveEquals(v1, v2) then
                    return false
                end
            else
                return false
            end
        elseif v1 ~= v2 then
            return false
        end
    end
    return true
end

---@class TablesModule
---@field includes fun(table: table, object: any): boolean Check if table contains a value
---@field count fun(table: table): number Count elements in a table
---@field recursiveCopy fun(table: table): table Create a deep copy of a table
---@field recursiveEquals fun(t1: table, t2: table): boolean Compare tables for deep equality

return module
