--- A logging utility module for ComputerCraft that provides colored console output
--- and automatic file logging with daily log rotation.
---
--- Features: Color-coded console output (red for errors, yellow for warnings, blue for info),
--- automatic daily log file creation and rotation, persistent log storage in log/ directory,
--- timestamped log entries, buffered writes for performance, and configurable log levels.
---
---@usage
---local log = require("log")
---
---log.debug("This is a debug message")
---log.info("Server started")
---log.warn("High memory usage detected")
---log.error("Failed to connect to database")
---
---log.setLevel("debug")  -- Show all messages including debug
---log.setLevel("warn")   -- Show only warnings and errors
---
---@version 1.4.1
-- @module log

local VERSION = "1.4.1"

local module = {}

-- Log level definitions (higher = more verbose)
local LEVELS = {
    error = 1,
    warn = 2,
    info = 3,
    debug = 4,
}

-- Aliases for level names
local LEVEL_ALIASES = {
    err = "error",
    warning = "warn",
    information = "info",
    dbg = "debug",
}

-- Current log level (default: info - shows error, warn, info but not debug)
local currentLevel = LEVELS.info

-- Log buffering for performance
local logBuffer = {}
local logBufferSize = 0
local maxBufferSize = 10  -- Flush after this many entries
local lastFlush = os.clock()
local flushInterval = 5   -- Flush at least every 5 seconds

---Generate a file-safe date string for log filenames
---@return string # Date string in YYYY/MM/DD format
local function fileDate()
    return os.date("%Y/%m/%d")
end

---Generate a human-readable timestamp for log entries
---@return string # Timestamp string in YYYY-MM-DD HH:MM:SS format
local function displayDate()
    return os.date("%F %T")
end

---Get the full log file path and ensure directory exists
---@return string path The full log file path
local function getLogPath()
    local path = "log/" .. fileDate() .. ".txt"
    -- Extract directory from path and create it
    local dir = path:match("(.+)/[^/]+$")
    if dir then
        fs.makeDir(dir)
    end
    return path
end

---Flush the log buffer to disk
local function flushBuffer()
    if logBufferSize == 0 then return end
    
    local path = getLogPath()
    local f = fs.open(path, "a")
    if f then
        for _, entry in ipairs(logBuffer) do
            f.writeLine(entry)
        end
        f.close()
    end
    
    logBuffer = {}
    logBufferSize = 0
    lastFlush = os.clock()
end

---Write a log entry to the buffer (flushed periodically)
---@param level string The log level (info, warn, error)
---@param msg string The message to log
local function writeLog(level, msg)
    local entry = string.format("%s [%s]: %s", displayDate(), level, msg)
    table.insert(logBuffer, entry)
    logBufferSize = logBufferSize + 1
    
    -- Flush if buffer is full, if enough time passed, or if it's an error
    local now = os.clock()
    if logBufferSize >= maxBufferSize or (now - lastFlush) >= flushInterval or level == "error" then
        flushBuffer()
    end
end

---Internal logging function that handles both console and file output
---@param level string The log level (debug, info, warn, error)
---@param msg string The message to log
local function log(level, msg)
    -- Check if this level should be shown based on current log level setting
    local levelNum = LEVELS[level] or LEVELS.info
    if levelNum > currentLevel then
        -- Still write to file, but don't show in console
        writeLog(level, msg)
        return
    end
    
    if level == "error" then
        term.setTextColor(colors.red)
    elseif level == "warn" then
        term.setTextColor(colors.yellow)
    elseif level == "info" then
        term.setTextColor(colors.blue)
    elseif level == "debug" then
        term.setTextColor(colors.gray)
    end
    write("["..level.."] ")
    term.setTextColor(colors.white)
    print(msg)
    writeLog(level, msg)
end

---Log a debug message in gray (only to file, not console by default)
---@param msg string The message to log
function module.debug(msg)
    log("debug", msg)
end

---Log an informational message in blue
---@param msg string The message to log
function module.info(msg)
    log("info", msg)
end

---Log a warning message in yellow
---@param msg string The message to log
function module.warn(msg)
    log("warn", msg)
end

---Log an error message in red
---@param msg string The message to log
function module.error(msg)
    log("error", msg)
end

---Log a critical/crash message in red
---This is always logged both to console and file, and immediately flushed
---@param msg string The message to log
function module.critical(msg)
    -- Critical messages bypass all level filtering
    term.setTextColor(colors.red)
    write("[CRITICAL] ")
    term.setTextColor(colors.white)
    print(msg)
    
    -- Write immediately to log file
    local path = getLogPath()
    local f = fs.open(path, "a")
    if f then
        f.writeLine(string.format("%s [CRITICAL]: %s", displayDate(), msg))
        f.close()
    end
    
    -- Also write to dedicated crash log
    fs.makeDir("log")
    local crashFile = fs.open("log/crash.txt", "a")
    if crashFile then
        crashFile.writeLine(string.format("%s [CRITICAL]: %s", displayDate(), msg))
        crashFile.close()
    end
end

---Flush any pending log entries to disk
function module.flush()
    flushBuffer()
end

---Set the current log level
---Messages with levels more verbose than this will only be written to file, not console
---@param level string|number The log level: "error", "warn", "info", "debug" (or 1-4)
---@return boolean success True if level was set successfully
---@return string? error Error message if failed
function module.setLevel(level)
    if type(level) == "number" then
        if level >= 1 and level <= 4 then
            currentLevel = level
            return true
        end
        return false, "Invalid level number (must be 1-4)"
    end
    
    if type(level) == "string" then
        level = level:lower()
        -- Check for aliases
        if LEVEL_ALIASES[level] then
            level = LEVEL_ALIASES[level]
        end
        if LEVELS[level] then
            currentLevel = LEVELS[level]
            return true
        end
        return false, "Unknown level: " .. level
    end
    
    return false, "Level must be string or number"
end

---Get the current log level name
---@return string levelName The current log level name
function module.getLevel()
    for name, num in pairs(LEVELS) do
        if num == currentLevel then
            return name
        end
    end
    return "info"
end

---Get all available log levels
---@return table levels Table with level names as keys and numbers as values
function module.getLevels()
    return {
        error = LEVELS.error,
        warn = LEVELS.warn,
        info = LEVELS.info,
        debug = LEVELS.debug,
    }
end

---Register log level commands with a cmd command table
---This adds "loglevel" command with aliases "log-level" and "ll"
---@param commands table The commands table to add the log level command to
---@return table commands The modified commands table (also modifies in place)
function module.registerCommands(commands)
    local logLevelCommand = {
        description = "View or set the console log level",
        category = "system",
        aliases = {"log-level", "ll"},
        execute = function(args, ctx)
            if #args == 0 then
                -- Show current level
                local level = module.getLevel()
                local levels = module.getLevels()
                ctx.mess("Current log level: " .. level)
                print("")
                print("Available levels (least to most verbose):")
                local ordered = {"error", "warn", "info", "debug"}
                for _, name in ipairs(ordered) do
                    local marker = (name == level) and "> " or "  "
                    local color = (name == level) and colors.lime or colors.lightGray
                    term.setTextColor(color)
                    print(marker .. name .. " (" .. levels[name] .. ")")
                end
                term.setTextColor(colors.white)
                print("")
                ctx.mess("Usage: loglevel <level>")
            else
                local newLevel = args[1]:lower()
                local success, err = module.setLevel(newLevel)
                if success then
                    ctx.succ("Log level set to: " .. module.getLevel())
                else
                    ctx.err(err or "Failed to set log level")
                end
            end
        end,
        complete = function(args)
            if #args == 1 then
                local query = (args[1] or ""):lower()
                local options = {"error", "warn", "info", "debug"}
                local matches = {}
                for _, opt in ipairs(options) do
                    if opt:find(query, 1, true) == 1 then
                        table.insert(matches, opt)
                    end
                end
                return matches
            end
            return {}
        end
    }
    
    -- Register primary command (aliases handled automatically by cmd.lua)
    commands["loglevel"] = logLevelCommand
    
    return commands
end

module.VERSION = VERSION

return module
