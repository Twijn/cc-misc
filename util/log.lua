--- A logging utility module for ComputerCraft that provides colored console output
--- and automatic file logging with daily log rotation.
---
--- Features: Color-coded console output (red for errors, yellow for warnings, blue for info),
--- automatic daily log file creation and rotation, persistent log storage in log/ directory,
--- timestamped log entries, buffered writes for performance, configurable log levels,
--- and automatic cleanup of old log files when disk space is low.
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
---@version 1.5.0
-- @module log

local VERSION = "1.5.0"

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

-- Disk space management
local minFreeSpace = 10000  -- Minimum free bytes before cleanup (10KB)
local lastDiskCheck = 0
local diskCheckInterval = 60  -- Check disk space every 60 seconds
local maxLogAgeDays = 30  -- Delete logs older than 30 days

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

---Get all log files recursively from a directory
---@param dir string The directory to scan
---@param files? table The accumulator table for files (optional)
---@return table files Array of {path, size} tables
local function getLogFiles(dir, files)
    files = files or {}
    
    if not fs.exists(dir) or not fs.isDir(dir) then
        return files
    end
    
    for _, name in ipairs(fs.list(dir)) do
        local path = dir .. "/" .. name
        if fs.isDir(path) then
            getLogFiles(path, files)
        elseif name:match("%.txt$") then
            local size = fs.getSize(path)
            table.insert(files, {path = path, size = size})
        end
    end
    
    return files
end

---Parse date from log file path (log/YYYY/MM/DD.txt)
---@param path string The log file path
---@return number|nil timestamp Unix timestamp or nil if can't parse
local function getLogFileDate(path)
    local year, month, day = path:match("log/(%d%d%d%d)/(%d%d)/(%d%d)%.txt$")
    if year and month and day then
        -- Create approximate timestamp (days since epoch for comparison)
        return tonumber(year) * 10000 + tonumber(month) * 100 + tonumber(day)
    end
    return nil
end

---Get current date as comparable number (YYYYMMDD)
---@return number date Current date as number
local function getCurrentDateNumber()
    local year, month, day = os.date("%Y"), os.date("%m"), os.date("%d")
    return tonumber(year) * 10000 + tonumber(month) * 100 + tonumber(day)
end

---Check if disk space is low and clean up old logs if needed
---@return boolean cleaned Whether any cleanup was performed
local function checkAndCleanupDiskSpace()
    local now = os.clock()
    
    -- Don't check too frequently
    if now - lastDiskCheck < diskCheckInterval then
        return false
    end
    lastDiskCheck = now
    
    -- Get free space
    local freeSpace = fs.getFreeSpace("/")
    
    -- If we have enough space, no cleanup needed
    if freeSpace > minFreeSpace then
        return false
    end
    
    -- Get all log files
    local logFiles = getLogFiles("log")
    
    if #logFiles == 0 then
        return false
    end
    
    -- Sort by date (oldest first)
    table.sort(logFiles, function(a, b)
        local dateA = getLogFileDate(a.path) or 0
        local dateB = getLogFileDate(b.path) or 0
        return dateA < dateB
    end)
    
    local currentDate = getCurrentDateNumber()
    local cleaned = false
    
    -- Delete old logs until we have enough space
    for _, file in ipairs(logFiles) do
        local fileDate = getLogFileDate(file.path)
        
        -- Don't delete today's log
        if fileDate and fileDate < currentDate then
            -- Calculate approximate age in days
            local ageDays = (currentDate - fileDate)
            -- This is a rough calculation - exact would need proper date math
            -- For YYYYMMDD format, this gives a reasonable approximation
            if currentDate % 100 < fileDate % 100 then
                -- Month wrap
                ageDays = ageDays - 70  -- Adjust for month encoding
            end
            
            -- Delete if old or if we really need space
            if ageDays > maxLogAgeDays or freeSpace < minFreeSpace / 2 then
                fs.delete(file.path)
                cleaned = true
                
                -- Check if parent directories are now empty and remove them
                local parentDir = file.path:match("(.+)/[^/]+$")
                if parentDir and fs.exists(parentDir) and fs.isDir(parentDir) then
                    local contents = fs.list(parentDir)
                    if #contents == 0 then
                        fs.delete(parentDir)
                        -- Check grandparent too
                        local grandParent = parentDir:match("(.+)/[^/]+$")
                        if grandParent and fs.exists(grandParent) and fs.isDir(grandParent) then
                            contents = fs.list(grandParent)
                            if #contents == 0 then
                                fs.delete(grandParent)
                            end
                        end
                    end
                end
                
                -- Recheck free space
                freeSpace = fs.getFreeSpace("/")
                if freeSpace > minFreeSpace then
                    break
                end
            end
        end
    end
    
    return cleaned
end

---Flush the log buffer to disk
local function flushBuffer()
    if logBufferSize == 0 then return end
    
    -- Check disk space before writing and clean up if needed
    checkAndCleanupDiskSpace()
    
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
        -- Debug messages are never written to file (too verbose)
        -- Other levels below threshold are still written to file
        if level ~= "debug" then
            writeLog(level, msg)
        end
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
    
    -- Never write debug messages to file (too verbose, console-only)
    if level ~= "debug" then
        writeLog(level, msg)
    end
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

---Configure disk space management settings
---@param settings table Configuration table with optional fields:
---  - minFreeSpace: Minimum free bytes before cleanup (default: 10000)
---  - maxLogAgeDays: Delete logs older than this (default: 30)
---  - checkInterval: Seconds between disk space checks (default: 60)
function module.configureDiskManagement(settings)
    if settings.minFreeSpace then
        minFreeSpace = settings.minFreeSpace
    end
    if settings.maxLogAgeDays then
        maxLogAgeDays = settings.maxLogAgeDays
    end
    if settings.checkInterval then
        diskCheckInterval = settings.checkInterval
    end
end

---Get disk space statistics for the log directory
---@return table stats Statistics about log storage
function module.getDiskStats()
    local logFiles = getLogFiles("log")
    local totalSize = 0
    local fileCount = 0
    
    for _, file in ipairs(logFiles) do
        totalSize = totalSize + file.size
        fileCount = fileCount + 1
    end
    
    local freeSpace = fs.getFreeSpace("/")
    
    return {
        logFileCount = fileCount,
        totalLogSize = totalSize,
        freeSpace = freeSpace,
        minFreeSpace = minFreeSpace,
        maxLogAgeDays = maxLogAgeDays,
        isLowSpace = freeSpace < minFreeSpace,
    }
end

---Manually trigger cleanup of old log files
---@param maxAgeDays? number Optional max age in days (default: use configured value)
---@return number deleted Number of files deleted
function module.cleanupOldLogs(maxAgeDays)
    maxAgeDays = maxAgeDays or maxLogAgeDays
    
    local logFiles = getLogFiles("log")
    local currentDate = getCurrentDateNumber()
    local deleted = 0
    
    -- Sort by date (oldest first)
    table.sort(logFiles, function(a, b)
        local dateA = getLogFileDate(a.path) or 0
        local dateB = getLogFileDate(b.path) or 0
        return dateA < dateB
    end)
    
    for _, file in ipairs(logFiles) do
        local fileDate = getLogFileDate(file.path)
        
        if fileDate and fileDate < currentDate then
            local ageDays = currentDate - fileDate
            if currentDate % 100 < fileDate % 100 then
                ageDays = ageDays - 70
            end
            
            if ageDays > maxAgeDays then
                fs.delete(file.path)
                deleted = deleted + 1
                
                -- Clean up empty parent directories
                local parentDir = file.path:match("(.+)/[^/]+$")
                if parentDir and fs.exists(parentDir) and fs.isDir(parentDir) then
                    local contents = fs.list(parentDir)
                    if #contents == 0 then
                        fs.delete(parentDir)
                        local grandParent = parentDir:match("(.+)/[^/]+$")
                        if grandParent and fs.exists(grandParent) and fs.isDir(grandParent) then
                            contents = fs.list(grandParent)
                            if #contents == 0 then
                                fs.delete(grandParent)
                            end
                        end
                    end
                end
            end
        end
    end
    
    return deleted
end

module.VERSION = VERSION

return module
