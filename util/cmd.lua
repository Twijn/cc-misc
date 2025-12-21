--- Command-line interface module for ComputerCraft that provides a REPL-style command processor
--- with support for custom commands, autocompletion, and command history.
---
--- Features: Built-in commands (clear, exit, help), command history navigation,
--- tab autocompletion for commands and arguments, colored output for different message types,
--- table pretty-printing functionality, pager for long output, and string utility functions.
---
---@usage
---local cmd = require("cmd")
---
---local customCommands = {
---  hello = {
---    description = "Say hello to someone",
---    execute = function(args, context)
---      local name = args[1] or "World"
---      context.succ("Hello, " .. name .. "!")
---    end
---  },
---  longlist = {
---    description = "Show a long list with pagination",
---    execute = function(args, context)
---      local p = context.pager("My Long List")
---      for i = 1, 100 do
---        p.print("Item " .. i)
---      end
---      p.show()
---    end
---  }
---}
---
---cmd("MyApp", "1.0.0", customCommands)
---
---@version 1.1.0
-- @module cmd

local VERSION = "1.1.0"
local pager = require("pager")

local history = {}
local running = true

---Print an error message in red color
---@param txt string The error message to display
local function err(txt)
  term.setTextColor(colors.red)
  print(txt)
end

---Print an informational message in light blue color
---@param txt string The message to display
local function mess(txt)
  term.setTextColor(colors.lightBlue)
  print(txt)
end

---Print a success message in green color
---@param txt string The success message to display
local function succ(txt)
             -- ^ lol
  term.setTextColor(colors.green)
  print(txt)
end

---Pretty-print a table with proper indentation and color formatting
---@param tbl table The table to print
---@param iteration? number The current indentation level (used for recursion)
local function printTable(tbl, iteration)
  local maxValue = 5
  for key in pairs(tbl) do
    maxValue = math.max(maxValue, #tostring(key))
  end
  if not iteration then iteration = 0 end
  for key, value in pairs(tbl) do
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightBlue)
    write(string.rep("..", iteration) .. key)
    write(string.rep(" ", maxValue - #tostring(key) + 2))
    if type(value) == "table" then
      term.setBackgroundColor(colors.lightGray)
      write("v")
      term.setBackgroundColor(colors.black)
      print("")
      printTable(value, iteration + 1)
    else
      term.setBackgroundColor(colors.blue)
      write(" ")
      term.setBackgroundColor(colors.black)
      write(" ")
      term.setTextColor(colors.white)
      print(tostring(value))
    end
  end
end

---@class CommandDefinition
---@field description string A description of what the command does
---@field execute fun(args: string[], context: CommandContext) The function to execute when the command is called
---@field complete? fun(args: string[]): string[] Optional autocompletion function

---@class CommandContext
---@field name string The name of the command processor
---@field version string The version of the command processor
---@field commands table<string, CommandDefinition> All available commands
---@field printTable fun(tbl: table, iteration?: number) Function to pretty-print tables
---@field err fun(txt: string) Function to print error messages
---@field mess fun(txt: string) Function to print informational messages
---@field succ fun(txt: string) Function to print success messages
---@field pager fun(title?: string): table Create a pager for displaying long output

-- === Commands ===
---@type table<string, CommandDefinition>
local defaultCommands = {
  -- Clear Command
  clear = {
    description = "Clear the screen",
    execute = function()
        term.setCursorPos(1,1)
        term.clear()
    end
  },
  -- Exit Command
  exit = {
    description = "Exit SignShop cmd",
    execute = function()
      err("Exiting")
      running = false
    end
  },
}

defaultCommands.help = {
  description = "Show this menu!",
  execute = function(args, d)
    -- Collect all command names and sort them
    local cmdNames = {}
    for cmdName in pairs(d.commands) do
      table.insert(cmdNames, cmdName)
    end
    table.sort(cmdNames)
    
    -- Use pager for displaying commands
    local p = pager.create("=== Available Commands ===")
    for _, cmdName in ipairs(cmdNames) do
      local cmd = d.commands[cmdName]
      p.setTextColor(colors.blue)
      p.write(cmdName)
      p.setTextColor(colors.lightGray)
      p.write(" - ")
      if cmd.description then
        p.setTextColor(colors.white)
        p.print(cmd.description)
      else
        p.print("No Description")
      end
    end
    p.show()
  end,
}

-- === String helpers ===
---Split a string into an array of substrings based on a separator
---@param self string The string to split
---@param sep? string The separator to split on (defaults to each character)
---@param plain? boolean Whether to treat separator as plain text (no pattern matching)
---@return string[] # Array of split substrings
function string.split(self, sep, plain)
  local out = {}
  if not sep or sep == "" then
    for i = 1, #self do out[#out+1] = self:sub(i, i) end
    return out
  end
  local i = 1
  while true do
    local s, e = self:find(sep, i, plain == true)
    if not s then
      out[#out+1] = self:sub(i)
      break
    end
    out[#out+1] = self:sub(i, s - 1)
    i = e + 1
  end
  return out
end

---Check if a string starts with a target substring
---@param self string The string to check
---@param target string The substring to look for at the beginning
---@param caseSensitive? boolean Whether the comparison should be case-sensitive (defaults to false)
---@return boolean # True if the string starts with the target
function string.startsWith(self, target, caseSensitive)
  if #self < #target then return false end
  if not caseSensitive then
    self = self:lower()
    target = target:lower()
  end
  return self:sub(1, #target) == target
end

-- === Command isolation ===
---Parse a command string into command name and arguments
---@param str string The input command string
---@return string cmd The command name (lowercase)
---@return string[] args The remaining arguments
local function isolateCommands(str)
  local args = str:split(" ")
  local cmd = args[1] and args[1]:lower() or ""
  table.remove(args, 1)
  return cmd, args
end

-- === Autocompletion ===
---Create an autocompletion function for the given commands
---@param commands table<string, CommandDefinition> The available commands
---@return fun(line: string): string[] # Autocompletion function that returns suggestions
local function complete(commands)
  return function(line)
    if #line == 0 then return {} end

    -- Figure out command + current args
    local cmd, args = isolateCommands(line)

    -- If the user hasn't typed anything yet or only part of a command:
    if cmd == "" then
      local suggestions = {}
      for name in pairs(commands) do table.insert(suggestions, name) end
      return suggestions
    end

    -- If still typing the first command (no space typed yet):
    if not line:find(" ") then
      local suggestions = {}
      for name in pairs(commands) do
        if name:startsWith(cmd) then
          table.insert(suggestions, name:sub(#cmd + 1))
        end
      end
      return suggestions
    end

    -- If it's a known command, delegate to its own completion
    local cmdObj = commands[cmd]
    if cmdObj and cmdObj.complete then
      local opts = cmdObj.complete(args)
      local lastArg = args[#args] or ""
      local matches = {}
      for _, opt in ipairs(opts) do
        if opt:startsWith(lastArg) then
          table.insert(matches, opt:sub(#lastArg + 1))
        end
      end
      return matches
    end

    return {}
  end
end

---Create and start a command-line interface
---@param name string The name of the application/system
---@param version string The version of the application/system
---@param customCommands table<string, CommandDefinition> Custom commands to add to the default set
---@return nil # This function runs until the user exits
return function(name, version, customCommands)
  local commands = defaultCommands

  for name, cmd in pairs(customCommands) do
    assert(type(name) == "string", "Custom commands must have only string keys!")
    assert(type(cmd) == "table", "Custom command data must be a table!")
    assert(type(cmd.description) == "string", "Custom command data must have a string description!")
    assert(type(cmd.execute) == "function", "Custom command data must have an execute function!")

    commands[name] = cmd
  end

  -- === Main REPL loop ===
  while running do
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightBlue)
    write(name .. "@" .. version)
    term.setTextColor(colors.blue)
    write("> ")
    term.setTextColor(colors.white)

    local str = read(nil, history, complete(commands))
    local cmd, args = isolateCommands(str)

    if commands[cmd] then
      commands[cmd].execute(args, {
        name = name,
        version = version,
        commands = commands,
        printTable = printTable,
        err = err,
        mess = mess,
        succ = succ,
        pager = pager.create,
      })
      table.insert(history, str)
    elseif str ~= "" then
      err("No such command")
    end
  end
end
