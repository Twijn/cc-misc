# cmd

@class CmdModule
A command-line interface module for ComputerCraft that provides a REPL-style command processor
with support for custom commands, autocompletion, and command history.

This module provides:
Built-in commands: clear, exit, help
Command history navigation
Tab autocompletion for commands and arguments
Colored output for different message types
Table pretty-printing functionality
String utility functions (split, startsWith)

@usage
local cmd = require("cmd")

local customCommands = {
hello = {
description = "Say hello to someone",
execute = function(args, context)
local name = args[1] or "World"
context.succ("Hello, " .. name .. "!")
end
}
}

cmd("MyApp", "1.0.0", customCommands)

## Functions

### `err(txt)`

Print an error message in red color

**Parameters:**

- `txt` (string): The error message to display

### `mess(txt)`

Print an informational message in light blue color

**Parameters:**

- `txt` (string): The message to display

### `succ(txt)`

Print a success message in green color

**Parameters:**

- `txt` (string): The success message to display

### `printTable(tbl, iteration?)`

Pretty-print a table with proper indentation and color formatting

**Parameters:**

- `tbl` (table): The table to print
- `iteration?` (number): The current indentation level (used for recursion)

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

### `isolateCommands(str)`

Parse a command string into command name and arguments

**Parameters:**

- `str` (string): The input command string

**Returns:** string[] args The remaining arguments

### `complete(commands)`

Create an autocompletion function for the given commands

**Parameters:**

- `commands` (table<string,): CommandDefinition> The available commands

**Returns:** fun(line: string): string[] # Autocompletion function that returns suggestions

