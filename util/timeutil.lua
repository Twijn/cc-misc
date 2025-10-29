--- A timing utility module for ComputerCraft that provides persistent interval management
--- with two different timing modes: absolute time-based and accumulated runtime-based.
---
--- Features: Absolute time intervals (based on system time), accumulated time intervals (based on actual runtime),
--- persistent state across computer restarts, pretty-printed time formatting, manual execution control,
--- and automatic interval management with run loop.
---
--- @module timeutil

---@class TimeutilInterval
---@field cb function Callback function to execute
---@field intervalTime number Interval duration in seconds
---@field fileName string File to persist timing data
---@field lastRun number Last execution timestamp (for absolute intervals)
---@field elapsed number Accumulated elapsed time (for loaded intervals)
---@field lastTick number Last tick timestamp (for loaded intervals)
---@field getTimeSinceRun fun(pretty?: boolean): number|string Get time since last execution
---@field getTimeUntilRun fun(pretty?: boolean): number|string Get time until next execution
---@field forceExecute fun(): nil Force immediate execution
---@field execute fun(): boolean Execute if interval has elapsed

local module = {}

local intervals = {}

---Get current UTC timestamp in milliseconds
---@return number # Current timestamp in milliseconds
local function now()
    return os.epoch("utc")
end

---Create an absolute time-based interval that runs based on system time
---This type of interval will "catch up" if the computer was offline, running immediately
---if the interval time has passed since the last recorded execution.
---@param cb function Callback function to execute when interval triggers
---@param intervalTime number Interval duration in seconds
---@param fileName string File path to persist the last run timestamp
---@return TimeutilInterval # Interval object with control methods
function module.every(cb, intervalTime, fileName)
    local interval = {
        cb = cb,
        intervalTime = intervalTime,
        fileName = fileName,
        lastRun = 0,
    }

    if fs.exists(fileName) then
        local f = fs.open(fileName, "r")
        local lastRun = tonumber(f.readAll())
        f.close()
        if lastRun then
            interval.lastRun = lastRun
        end
    end

    local function saveNow()
        interval.lastRun = now()
        local f = fs.open(fileName, "w")
        f.write(interval.lastRun)
        f.close()
    end

    interval.getTimeSinceRun = function(pretty)
        local time = (now() - interval.lastRun) / 1000
        if pretty then
            return module.getRelativeTime(time)
        else
            return time
        end
    end

    interval.getTimeUntilRun = function(pretty)
        local time = math.max(interval.lastRun + (intervalTime * 1000) - now(), 0) / 1000
        if pretty then
            return module.getRelativeTime(time)
        else
            return time
        end
    end

    interval.forceExecute = function()
        interval.cb()
        saveNow()
    end

    interval.execute = function()
        if interval.getTimeSinceRun() >= intervalTime then
            interval.forceExecute()
            return true
        end
        return false
    end

    table.insert(intervals, interval)

    return interval
end

---Create a runtime-based interval that accumulates time only when the program is running
---This type of interval will NOT catch up after downtime, only counting actual runtime.
---Useful for operations that should happen after X seconds of actual program execution.
---@param cb function Callback function to execute when interval triggers
---@param intervalTime number Interval duration in seconds of actual runtime
---@param fileName string File path to persist the accumulated elapsed time
---@return TimeutilInterval # Interval object with control methods
function module.everyLoaded(cb, intervalTime, fileName)
    local interval = {
        cb = cb,
        intervalTime = intervalTime, -- seconds
        fileName = fileName,
        elapsed = 0,
        lastTick = os.clock(),
    }

    -- Load saved elapsed time
    if fs.exists(fileName) then
        local f = fs.open(fileName, "r")
        local saved = tonumber(f.readAll())
        f.close()
        if saved then
            interval.elapsed = saved
        end
    end

    local function saveElapsed()
        local f = fs.open(fileName, "w")
        f.write(tostring(interval.elapsed))
        f.close()
    end

    interval.getTimeSinceRun = function(pretty)
        if pretty then
            return module.getRelativeTime(interval.elapsed)
        else
            return interval.elapsed
        end
    end

    interval.getTimeUntilRun = function(pretty)
        local time = math.max(intervalTime - interval.elapsed, 0)
        if pretty then
            return module.getRelativeTime(time)
        else
            return time
        end
    end

    interval.forceExecute = function()
        interval.cb()
        interval.elapsed = 0
        saveElapsed()
    end

    interval.execute = function()
        local nowClock = os.clock()
        local dt = nowClock - interval.lastTick
        interval.lastTick = nowClock

        interval.elapsed = interval.elapsed + dt
        if interval.elapsed >= intervalTime then
            interval.forceExecute()
            return true
        else
            saveElapsed()
        end
        return false
    end

    table.insert(intervals, interval)

    return interval
end

---Start the main interval management loop
---This function blocks and continuously checks all registered intervals,
---executing them when their time has elapsed. Runs indefinitely until terminated.
function module.run()
    print("Starting timeutil tick")
    while true do
        for _, interval in pairs(intervals) do
            interval.execute()
        end
        sleep(2)
    end
end

---Format a duration in seconds into a human-readable relative time string
---@param sec number Duration in seconds
---@return string # Formatted time string (e.g., "5.2 minutes", "1 day", "30 seconds")
function module.getRelativeTime(sec)
    if sec >= 86400 then
        local val = math.floor(sec / 8640) / 10
        return val .. " day" .. (val == 1 and "" or "s")
    elseif sec >= 3600 then
        local val = math.floor(sec / 360) / 10
        return val .. " hour" .. (val == 1 and "" or "s")
    elseif sec >= 60 then
        local val = math.floor(sec / 6) / 10
        return val .. " minute" .. (val == 1 and "" or "s")
    else
        local val = math.floor(sec)
        return val .. " second" .. (val == 1 and "" or "s")
    end
end

---@class TimeutilModule
---@field every fun(cb: function, intervalTime: number, fileName: string): TimeutilInterval Create absolute time interval
---@field everyLoaded fun(cb: function, intervalTime: number, fileName: string): TimeutilInterval Create runtime-based interval
---@field run fun(): nil Start the interval management loop
---@field getRelativeTime fun(sec: number): string Format seconds into human-readable time

return module
