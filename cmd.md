# cmd

Command-line interface module for ComputerCraft that provides a REPL-style command processor with support for custom commands, autocompletion, and command history. Features: Built-in commands (clear, exit, help), command history navigation, tab autocompletion for commands and arguments, colored output for different message types, table pretty-printing functionality, pager for long output, string utility functions, command categories for organized help display, proper alias handling, and exit hooks.

## Examples

```lua
local cmd = require("cmd")

local customCommands = {
 hello = {
   description = "Say hello to someone",
   category = "general",
   aliases = {"hi", "greet"},
   execute = function(args, context)
     local name = args[1] or "World"
     context.succ("Hello, " .. name .. "!")
   end
 },
 longlist = {
   description = "Show a long list with pagination",
   category = "utilities",
   execute = function(args, context)
     local p = context.pager("My Long List")
     for i = 1, 100 do
       p.print("Item " .. i)
     end
     p.show()
   end
 }
}

-- Basic usage
cmd("MyApp", "1.0.0", customCommands)

-- With exit hooks via options
cmd("MyApp", "1.0.0", customCommands, {
 onExit = function(context)
   print("Goodbye!")
 end,
 exitHooks = {
   function() saveData() end,
   function() closeConnections() end,
 }
})

-- Or register hooks at runtime from within commands
execute = function(args, context)
 context.onExit(function()
   print("Cleanup complete!")
 end)
end

```

## Functions

### `string.split(self, sep?, plain?)`

Split a string into an array of substrings based on a separator

**Parameters:**

- `self` (string): The string to split
- `sep?` (string): The separator to split on (defaults to each character)
- `plain?` (boolean): Whether to treat separator as plain text (no pattern matching)

**Returns:** string[] # Array of split substrings

### `string.startsWith(self, target, caseSensitive?)`

Check if a string starts with a target substring

**Parameters:**

- `self` (string): The string to check
- `target` (string): The substring to look for at the beginning
- `caseSensitive?` (boolean): Whether the comparison should be case-sensitive (defaults to false)

**Returns:** boolean # True if the string starts with the target

