--- SignShop Error Handling Library ---
--- Provides standardized error handling patterns across all managers.
---
--- Features: Structured error types, success/error result wrappers,
--- error checking utilities, and function wrapping for error handling.
---
---@usage
---local errors = require("lib.errors")
---
---local result = errors.success({ dispensed = 5 })
---if errors.isError(result) then
---    print(result.message)
---end
---
---@version 1.6.0
-- @module errors

local VERSION = "1.5.0"

local errors = {}

--- Error type constants for consistent error categorization
errors.types = {
    AISLE_OFFLINE = "AISLE_OFFLINE",
    AISLE_DEGRADED = "AISLE_DEGRADED",
    AISLE_NOT_FOUND = "AISLE_NOT_FOUND",
    PRODUCT_NOT_FOUND = "PRODUCT_NOT_FOUND",
    INSUFFICIENT_STOCK = "INSUFFICIENT_STOCK",
    KRIST_ERROR = "KRIST_ERROR",
    PERIPHERAL_NOT_FOUND = "PERIPHERAL_NOT_FOUND",
    INVALID_CONFIG = "INVALID_CONFIG",
    DISPENSE_FAILED = "DISPENSE_FAILED",
    HISTORY_ERROR = "HISTORY_ERROR",
    MONITOR_ERROR = "MONITOR_ERROR",
    INTERNAL_ERROR = "INTERNAL_ERROR",
    UNKNOWN = "UNKNOWN",
}

--- Create a structured error object
---@param type string Error type from errors.types
---@param message string Human-readable error message
---@param details? table Additional error context
---@return table Structured error object
function errors.create(type, message, details)
    return {
        error = true,
        type = type or errors.types.UNKNOWN,
        message = message or "An unknown error occurred",
        details = details or {},
        timestamp = os.epoch("utc"),
    }
end

--- Create a success result wrapper
---@param data any The successful result data
---@return table Success result object
function errors.success(data)
    return {
        error = false,
        data = data,
    }
end

--- Check if a result is an error
---@param result any The result to check
---@return boolean True if result is a structured error
function errors.isError(result)
    return type(result) == "table" and result.error == true
end

--- Check if a result is successful
---@param result any The result to check
---@return boolean True if result is a success wrapper
function errors.isSuccess(result)
    return type(result) == "table" and result.error == false
end

--- Get error message from a result, or nil if not an error
---@param result any The result to extract message from
---@return string|nil Error message or nil
function errors.getMessage(result)
    if errors.isError(result) then
        return result.message
    end
    return nil
end

--- Get error type from a result, or nil if not an error
---@param result any The result to extract type from
---@return string|nil Error type or nil
function errors.getType(result)
    if errors.isError(result) then
        return result.type
    end
    return nil
end

--- Unwrap a successful result, or return default value on error
---@param result any The result to unwrap
---@param default? any Default value to return on error
---@return any The unwrapped data or default value
function errors.unwrap(result, default)
    if errors.isSuccess(result) then
        return result.data
    end
    return default
end

--- Wrap a function to catch errors and return structured result
--- If the function throws, it's caught and returned as a structured error.
--- If the function returns normally, the result is passed through.
---@param fn function The function to wrap
---@return function Wrapped function that catches errors
function errors.wrap(fn)
    return function(...)
        local ok, result = pcall(fn, ...)
        if not ok then
            return errors.create(errors.types.UNKNOWN, tostring(result))
        end
        return result
    end
end

--- Convert legacy error format (false, "message") to structured error
--- Useful for migrating old code incrementally
---@param success boolean The success flag from legacy format
---@param message? string The error message from legacy format
---@param type? string Optional error type
---@return table Structured result (success or error)
function errors.fromLegacy(success, message, type)
    if success then
        return errors.success(message)
    else
        return errors.create(type or errors.types.UNKNOWN, message or "Unknown error")
    end
end

--- Format an error for logging
---@param result table The error result to format
---@return string Formatted error string
function errors.format(result)
    if not errors.isError(result) then
        return "Not an error"
    end
    local str = string.format("[%s] %s", result.type, result.message)
    if result.details and next(result.details) then
        str = str .. " (" .. textutils.serialize(result.details):gsub("\n", " ") .. ")"
    end
    return str
end

return errors
