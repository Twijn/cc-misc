local module = {}

local function fileDate()
    return os.date("%Y/%m/%d")
end

local function displayDate()
    return os.date("%F %T")
end

local function writeLog(level, msg)
    fs.makeDir("log")
    local f = fs.open("log/" .. fileDate() .. ".txt", "a")
    f.writeLine(string.format("%s [%s]: %s", displayDate(), level, msg))
    f.close()
end

local function log(level, msg)
    if level == "error" then
        term.setTextColor(colors.red)
    elseif level == "warn" then
        term.setTextColor(colors.yellow)
    end
    print(msg)
    writeLog(level, msg)
end

function module.info(msg)
    log("info", msg)
end

function module.warn(msg)
    log("warn", msg)
end

function module.error(msg)
    log("error", msg)
end

return module
