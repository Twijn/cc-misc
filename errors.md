# errors

SignShop Error Handling Library --- Provides standardized error handling patterns across all managers. Features: Structured error types, success/error result wrappers, error checking utilities, and function wrapping for error handling.

## Examples

```lua
local errors = require("lib.errors")
local result = errors.success({ dispensed = 5 })
if errors.isError(result) then
   print(result.message)
end
```

## Functions

### `errors.create(type, message, details?)`

Create a structured error object

**Parameters:**

- `type` (string): Error type from errors.types
- `message` (string): Human-readable error message
- `details?` (table): Additional error context

**Returns:** table Structured error object

### `errors.success(data)`

Create a success result wrapper

**Parameters:**

- `data` (any): The successful result data

**Returns:** table Success result object

### `errors.isError(result)`

Check if a result is an error

**Parameters:**

- `result` (any): The result to check

**Returns:** boolean True if result is a structured error

### `errors.isSuccess(result)`

Check if a result is successful

**Parameters:**

- `result` (any): The result to check

**Returns:** boolean True if result is a success wrapper

### `errors.getMessage(result)`

Get error message from a result, or nil if not an error

**Parameters:**

- `result` (any): The result to extract message from

**Returns:** string|nil Error message or nil

### `errors.getType(result)`

Get error type from a result, or nil if not an error

**Parameters:**

- `result` (any): The result to extract type from

**Returns:** string|nil Error type or nil

### `errors.unwrap(result, default?)`

Unwrap a successful result, or return default value on error

**Parameters:**

- `result` (any): The result to unwrap
- `default?` (any): Default value to return on error

**Returns:** any The unwrapped data or default value

### `errors.wrap(fn)`

Wrap a function to catch errors and return structured result If the function throws, it's caught and returned as a structured error. If the function returns normally, the result is passed through.

**Parameters:**

- `fn` (function): The function to wrap

**Returns:** function Wrapped function that catches errors

### `errors.fromLegacy(success, message?, type?)`

Convert legacy error format (false, "message") to structured error Useful for migrating old code incrementally

**Parameters:**

- `success` (boolean): The success flag from legacy format
- `message?` (string): The error message from legacy format
- `type?` (string): Optional error type

**Returns:** table Structured result (success or error)

### `errors.format(result)`

Format an error for logging

**Parameters:**

- `result` (table): The error result to format

**Returns:** string Formatted error string

