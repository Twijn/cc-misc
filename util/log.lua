--- A logging utility module for ComputerCraft that provides colored console output
--- and automatic file logging with daily log rotation.
---
--- Features: Color-coded console output (red for errors, yellow for warnings, blue for info),
--- automatic daily log file creation and rotation, persistent log storage in log/ directory,
--- and timestamped log entries.
---
---@usage
---local log = require("log")
---
---log.info("Server started")
---log.warn("High memory usage detected")
---log.error("Failed to connect to database")
---
---@version 1.0.0
-- @module log

local VERSION = "1.0.0"

local module = {}

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

---Write a log entry to the daily log file
---@param level string The log level (info, warn, error)
---@param msg string The message to log
local function writeLog(level, msg)
    fs.makeDir("log")
    local f = fs.open("log/" .. fileDate() .. ".txt", "a")
    f.writeLine(string.format("%s [%s]: %s", displayDate(), level, msg))
    f.close()
end

---Internal logging function that handles both console and file output
---@param level string The log level (info, warn, error)
---@param msg string The message to log
local function log(level, msg)
    if level == "error" then
        term.setTextColor(colors.red)
    elseif level == "warn" then
        term.setTextColor(colors.yellow)
    elseif level == "info" then
        term.setTextColor(colors.blue)
    end
    write("["..level.."] ")
    term.setTextColor(colors.white)
    print(msg)
    writeLog(level, msg)
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

return module
