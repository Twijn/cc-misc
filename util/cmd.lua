--- Command-line interface module for ComputerCraft that provides a REPL-style command processor
--- with support for custom commands, autocompletion, and command history.
---
--- Features: Built-in commands (clear, exit, help), command history navigation,
--- tab autocompletion for commands and arguments, colored output for different message types,
--- table pretty-printing functionality, pager for long output, string utility functions,
--- command categories for organized help display, and proper alias handling.
---
---@usage
---local cmd = require("cmd")
---
---local customCommands = {
---  hello = {
---    description = "Say hello to someone",
---    category = "general",
---    aliases = {"hi", "greet"},
---    execute = function(args, context)
---      local name = args[1] or "World"
---      context.succ("Hello, " .. name .. "!")
---    end
---  },
---  longlist = {
---    description = "Show a long list with pagination",
---    category = "utilities",
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
---@version 1.2.0
-- @module cmd

local VERSION = "1.2.0"
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
---@field category? string Optional category for grouping in help (e.g., "storage", "queue", "config")
---@field aliases? string[] Optional list of alias names for this command

---@class CommandContext
---@field name string The name of the command processor
---@field version string The version of the command processor
---@field commands table<string, CommandDefinition> All available commands
---@field printTable fun(tbl: table, iteration?: number) Function to pretty-print tables
---@field err fun(txt: string) Function to print error messages
---@field mess fun(txt: string) Function to print informational messages
---@field succ fun(txt: string) Function to print success messages
---@field pager fun(title?: string): table Create a pager for displaying long output

--- Category display order and colors
local CATEGORY_ORDER = {
    "general", "storage", "queue", "crafters", "furnaces",
    "config", "exports", "recipes", "system", "other"
}
local CATEGORY_COLORS = {
    general = colors.white,
    storage = colors.yellow,
    queue = colors.lime,
    crafters = colors.cyan,
    furnaces = colors.orange,
    config = colors.lightBlue,
    exports = colors.magenta,
    recipes = colors.green,
    system = colors.lightGray,
    other = colors.white,
}

-- === Commands ===
---@type table<string, CommandDefinition>
local defaultCommands = {
  -- Clear Command
  clear = {
    description = "Clear the screen",
    category = "system",
    execute = function()
        term.setCursorPos(1,1)
        term.clear()
    end
  },
  -- Exit Command
  exit = {
    description = "Exit the command interface",
    category = "system",
    aliases = {"quit", "q"},
    execute = function()
      err("Exiting")
      running = false
    end
  },
}

--- Build a deduplicated list of commands grouped by category
--- Identifies primary command names vs aliases by checking reference equality
---@param commands table<string, CommandDefinition> The commands table
---@return table # {category = {{name=string, cmd=CommandDefinition, aliases={string...}}...}...}
local function buildCommandIndex(commands)
    local seen = {}  -- Map command object -> primary name
    local aliasMap = {}  -- Map command object -> list of alias names
    local cmdList = {}  -- List of {name, cmd, category} for primary commands only
    
    -- First pass: find all names for each unique command object
    local allNames = {}
    for name in pairs(commands) do
        table.insert(allNames, name)
    end
    table.sort(allNames)
    
    for _, name in ipairs(allNames) do
        local cmd = commands[name]
        if not seen[cmd] then
            -- First time seeing this command object
            -- Check if it has declared aliases - if so, use the non-alias name as primary
            local isPrimary = true
            if cmd.aliases then
                for _, alias in ipairs(cmd.aliases) do
                    if name == alias then
                        isPrimary = false
                        break
                    end
                end
            end
            
            if isPrimary then
                seen[cmd] = name
                aliasMap[cmd] = {}
                table.insert(cmdList, {
                    name = name,
                    cmd = cmd,
                    category = cmd.category or "other"
                })
            else
                -- This name matches a declared alias, skip for now
                -- Will be found when we see the primary command
            end
        else
            -- This is an alias (same command object seen before)
            table.insert(aliasMap[cmd], name)
        end
    end
    
    -- Handle commands where we only saw aliases first
    for _, name in ipairs(allNames) do
        local cmd = commands[name]
        if not seen[cmd] then
            -- We haven't found a primary yet, use this as primary
            seen[cmd] = name
            aliasMap[cmd] = {}
            table.insert(cmdList, {
                name = name,
                cmd = cmd,
                category = cmd.category or "other"
            })
        end
    end
    
    -- Also capture declared aliases that might exist
    for _, entry in ipairs(cmdList) do
        local cmd = entry.cmd
        if cmd.aliases then
            for _, alias in ipairs(cmd.aliases) do
                -- Only add if it exists in commands table and not already in aliasMap
                if commands[alias] == cmd then
                    local found = false
                    for _, existing in ipairs(aliasMap[cmd]) do
                        if existing == alias then
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(aliasMap[cmd], alias)
                    end
                end
            end
        end
    end
    
    -- Group by category
    local byCategory = {}
    for _, entry in ipairs(cmdList) do
        local cat = entry.category
        if not byCategory[cat] then
            byCategory[cat] = {}
        end
        table.insert(byCategory[cat], {
            name = entry.name,
            cmd = entry.cmd,
            aliases = aliasMap[entry.cmd] or {}
        })
    end
    
    return byCategory
end

defaultCommands.help = {
  description = "Show available commands",
  category = "system",
  aliases = {"?", "commands"},
  execute = function(args, d)
    local filter = args[1] and args[1]:lower() or nil
    local byCategory = buildCommandIndex(d.commands)
    
    -- If filter provided, check if it's a category or command name
    local showCategory = nil
    local showCommand = nil
    if filter then
        -- Check if it matches a category
        for cat in pairs(byCategory) do
            if cat:lower() == filter then
                showCategory = cat
                break
            end
        end
        -- Check if it matches a command
        if not showCategory and d.commands[filter] then
            showCommand = filter
        end
    end
    
    -- Show single command help
    if showCommand then
        local cmd = d.commands[showCommand]
        local p = pager.create("=== Command: " .. showCommand .. " ===")
        p.setTextColor(colors.white)
        p.print(cmd.description or "No description")
        if cmd.category then
            p.setTextColor(colors.lightGray)
            p.print("Category: " .. cmd.category)
        end
        -- Find aliases for this command
        local aliases = {}
        for name, c in pairs(d.commands) do
            if c == cmd and name ~= showCommand then
                table.insert(aliases, name)
            end
        end
        if #aliases > 0 then
            table.sort(aliases)
            p.setTextColor(colors.gray)
            p.print("Aliases: " .. table.concat(aliases, ", "))
        end
        p.show()
        return
    end
    
    -- Build display title
    local title = "=== Available Commands ==="
    if showCategory then
        title = "=== " .. showCategory:sub(1,1):upper() .. showCategory:sub(2) .. " Commands ==="
    end
    
    local p = pager.create(title)
    
    -- Determine category order
    local orderedCats = {}
    local catSet = {}
    
    -- Add categories in preferred order if they have commands
    for _, cat in ipairs(CATEGORY_ORDER) do
        if byCategory[cat] and (not showCategory or showCategory == cat) then
            table.insert(orderedCats, cat)
            catSet[cat] = true
        end
    end
    
    -- Add any remaining categories not in the order list
    for cat in pairs(byCategory) do
        if not catSet[cat] and (not showCategory or showCategory == cat) then
            table.insert(orderedCats, cat)
        end
    end
    
    -- Display commands grouped by category
    local firstCat = true
    for _, cat in ipairs(orderedCats) do
        local cmds = byCategory[cat]
        if cmds and #cmds > 0 then
            if not firstCat then
                p.print("")
            end
            firstCat = false
            
            -- Category header
            local catColor = CATEGORY_COLORS[cat] or colors.white
            p.setTextColor(catColor)
            local catTitle = cat:sub(1,1):upper() .. cat:sub(2)
            p.print("-- " .. catTitle .. " --")
            
            -- Sort commands within category
            table.sort(cmds, function(a, b) return a.name < b.name end)
            
            for _, entry in ipairs(cmds) do
                p.setTextColor(colors.blue)
                p.write("  " .. entry.name)
                
                -- Show aliases inline (compact)
                if #entry.aliases > 0 then
                    table.sort(entry.aliases)
                    p.setTextColor(colors.gray)
                    p.write(" (" .. table.concat(entry.aliases, ", ") .. ")")
                end
                
                p.setTextColor(colors.lightGray)
                p.write(" - ")
                p.setTextColor(colors.white)
                p.print(entry.cmd.description or "No description")
            end
        end
    end
    
    -- Footer with tips
    p.print("")
    p.setTextColor(colors.lightGray)
    p.print("Tip: help <command> for details, help <category> to filter")
    
    p.show()
  end,
  complete = function(args)
    -- Complete with command names and category names
    if #args == 1 then
        local completions = {}
        local query = (args[1] or ""):lower()
        
        -- This will be called with access to commands via closure in main function
        -- For now, return category suggestions
        for _, cat in ipairs(CATEGORY_ORDER) do
            if cat:find(query, 1, true) == 1 then
                table.insert(completions, cat)
            end
        end
        return completions
    end
    return {}
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
  local commands = {}
  
  -- Copy default commands
  for cmdName, cmd in pairs(defaultCommands) do
    commands[cmdName] = cmd
  end

  -- Add custom commands
  for cmdName, cmd in pairs(customCommands) do
    assert(type(cmdName) == "string", "Custom commands must have only string keys!")
    assert(type(cmd) == "table", "Custom command data must be a table!")
    assert(type(cmd.description) == "string", "Custom command data must have a string description!")
    assert(type(cmd.execute) == "function", "Custom command data must have an execute function!")

    commands[cmdName] = cmd
  end
  
  -- Register aliases for all commands (after all commands added)
  for cmdName, cmd in pairs(commands) do
    if cmd.aliases then
      for _, alias in ipairs(cmd.aliases) do
        if not commands[alias] then
          commands[alias] = cmd
        end
      end
    end
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
