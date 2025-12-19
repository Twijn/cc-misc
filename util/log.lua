--- A logging utility module for ComputerCraft that provides colored console output
--- and automatic file logging with daily log rotation.
---
--- Features: Color-coded console output (red for errors, yellow for warnings, blue for info),
--- automatic daily log file creation and rotation, persistent log storage in log/ directory,
--- timestamped log entries, and buffered writes for performance.
---
---@usage
---local log = require("log")
---
---log.debug("This is a debug message")
---log.info("Server started")
---log.warn("High memory usage detected")
---log.error("Failed to connect to database")
---
---@version 1.2.0
-- @module log

local VERSION = "1.2.0"

local module = {}

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

---Flush the log buffer to disk
local function flushBuffer()
    if logBufferSize == 0 then return end
    
    fs.makeDir("log")
    local f = fs.open("log/" .. fileDate() .. ".txt", "a")
    for _, entry in ipairs(logBuffer) do
        f.writeLine(entry)
    end
    f.close()
    
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

---Flush any pending log entries to disk
function module.flush()
    flushBuffer()
end

module.VERSION = VERSION

return module
