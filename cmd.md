# cmd

Command-line interface module for ComputerCraft that provides a REPL-style command processor with support for custom commands, autocompletion, and command history. Features: Built-in commands (clear, exit, help), command history navigation, tab autocompletion for commands and arguments, colored output for different message types, table pretty-printing functionality, and string utility functions (split, startsWith).

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

