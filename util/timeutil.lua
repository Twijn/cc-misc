local module = {}

local intervals = {}

local function now()
    return os.epoch("utc")
end

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

function module.run()
    print("Starting timeutil tick")
    while true do
        for _, interval in pairs(intervals) do
            interval.execute()
        end
        sleep(2)
    end
end

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

return module
