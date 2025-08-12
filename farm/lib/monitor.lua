local s = require("lib/s")
local breeder = require("lib/breeder")
local cropFarm = require("lib/cropFarm")

local m = s.peripheral("monitor.monitor_name", "monitor")

local maximumBabies = s.number("cow.maximum-babies", -1, nil, 20)

local function setColor(backgroundColor, textColor)
    if not backgroundColor then backgroundColor = colors.black end
    if not textColor then textColor = colors.white end
    m.setBackgroundColor(backgroundColor)
    m.setTextColor(textColor)
end

local function drawTable(startX, startY, data)
    local columnData = {}
    local removeFirst = false
    for rowNum, rowData in ipairs(data) do
        for columnNum, cellText in ipairs(rowData) do
            if rowNum == 1 then
                if cellText == "left" or cellText == "right" then
                    removeFirst = true
                    columnData[columnNum] = {
                        align = cellText,
                        width = 2,
                    }
                else
                    columnData[columnNum] = {
                        align = "left",
                        width = #cellText + 2,
                    }
                end
            else
                columnData[columnNum].width = math.max(columnData[columnNum].width, #cellText + 2)
            end
        end
    end

    if removeFirst then
        table.remove(data, 1)
    end

    local tableWidth = 0
    for _, columnData in pairs(columnData) do
        tableWidth = tableWidth + columnData.width
    end

    if startX < 0 then
        local monX = m.getSize()
        startX = monX + startX - tableWidth
    end

    for rowNum, rowData in ipairs(data) do
        m.setCursorPos(startX, startY + rowNum - 1)
        setColor(rowNum % 2 == 1 and colors.blue or colors.lightBlue, colors.white)
        m.write(" ")
        for columnNum, cellText in ipairs(rowData) do
            if columnData[columnNum].align == "right" then
                m.write(string.rep(" ", columnData[columnNum].width - #cellText))
            end
            m.write(cellText)
            if columnData[columnNum].align == "left" then
                m.write(string.rep(" ", columnData[columnNum].width - #cellText))
            end
        end
        m.write(" ")
    end
end

local function redraw()
    setColor()
    m.clear()
    m.setCursorPos(2,2)
    m.write("Crop Farm")

    local cropTurtleData = {
        {"left", "right"},
        {"Turtle", "Crop"},
    }
    for id, turt in pairs(cropFarm.getTurtles()) do
        local crop = cropFarm.getCrops()[turt.crop]
        table.insert(cropTurtleData, {
            "#" .. id,
            crop and crop.name or "None",
        })
    end

    drawTable(2, 4, cropTurtleData)

    local cropCounts = {
        {"left", "right"},
        {"Crop", "Count"},
    }
    for _, crop in pairs(cropFarm.getCrops()) do
        table.insert(cropCounts, {
            crop.name,
            string.format("%d/%d", crop.count and crop.count or 0, crop.target),
        })
    end

    drawTable(-2, 4, cropCounts)

    setColor()

    local lastRan = string.format("Last ran %s ago", cropFarm.interval.getTimeSinceRun(true))
    local timeUntil = string.format("Next run in %s", cropFarm.interval.getTimeUntilRun(true))

    local _, y = m.getCursorPos()
    local monX, monY = m.getSize()

    m.setCursorPos(monX - #lastRan - 2, y + 2)
    m.write(lastRan)
    m.setCursorPos(monX - #timeUntil - 2, y + 3)
    m.write(timeUntil)

    m.setCursorPos(3, 15)
    m.write("Cow Breeder")

    setColor(colors.red)
    local x = 6
    local cowCount = breeder.getCowCounts()
    for rx, zVals in pairs(cowCount) do
        local y = 17
        if type(rx) == "number" then
            for rz, count in pairs(zVals) do
                m.setCursorPos(x, y)
                m.write((count < 10 and " " or "") .. count)
                y = y + 2
            end
        end
        x = x + 3
    end

    local babies = cowCount.babies and cowCount.babies or 0
    _, y = m.getCursorPos()

    setColor(colors.black, babies > maximumBabies and colors.red or colors.green)

    m.setCursorPos(2, y + 2)
    m.write(string.format("Babies: %d/%d", babies, maximumBabies))

    setColor()

    lastRan = string.format("Last ran %s ago", breeder.interval.getTimeSinceRun(true))
    timeUntil = string.format("Next run in %s", breeder.interval.getTimeUntilRun(true))

    m.setCursorPos(monX - #lastRan - 2, monY - 2)
    m.write(lastRan)
    m.setCursorPos(monX - #timeUntil - 2, monY - 1)
    m.write(timeUntil)
end

local function run()
    while true do
        redraw()
        sleep(3)
    end
end

return {
    run = run,
}
