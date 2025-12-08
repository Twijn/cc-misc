--- RBC Controller Program
--- Pocket computer / computer interface for controlling RBC turtles
---
---@version 1.2.0
---@usage
--- wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/roadbuilder/install.lua
--- Then run: controller
---

local CONTROLLER_VERSION = "1.2.0"
local CONTROLLER_UPDATE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main/roadbuilder/controller.lua"

-- Set up library path
if not package.path:find("lib") then
    package.path = package.path .. ";lib/?.lua;lib/?/init.lua"
end

-- Load libraries
local log = require("log")
local comms = require("comms")

-- Debug mode (enabled with --debug flag)
local DEBUG = false

local function debugLog(level, msg)
    if DEBUG then
        if level == "info" then
            log.info(msg)
        elseif level == "warn" then
            log.warn(msg)
        elseif level == "error" then
            log.error(msg)
        end
    end
end

-- Optional libraries
local formUILoaded, FormUI = pcall(require, "formui")
local updaterLoaded, updater = pcall(require, "updater")

-- Load configuration
local configLoaded, config = pcall(require, "config")
if not configLoaded then
    config = {
        NETWORK = { CHANNEL = 4521, REPLY_CHANNEL = 4522, GPS_TIMEOUT = 2, HEARTBEAT_INTERVAL = 5 },
        ROAD = { DEFAULT_WIDTH = 3, MINE_HEIGHT = 5 },
        DISPLAY = { COLORS = true, REFRESH_RATE = 1, SHOW_DETAILS = true },
    }
end

-- ======= State =======
local running = true
local selectedTurtle = nil
local turtles = {}
local lastRefresh = 0
local currentView = "main" -- main, turtle_list, turtle_detail, command

-- Screen dimensions
local screenW, screenH = term.getSize()
local isPocket = pocket ~= nil

-- Input mode (prevents display refresh during prompts)
local inputMode = false

-- ======= UI Helpers =======

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function setColor(fg, bg)
    if config.DISPLAY.COLORS then
        term.setTextColor(fg or colors.white)
        term.setBackgroundColor(bg or colors.black)
    end
end

local function centerText(y, text)
    local x = math.floor((screenW - #text) / 2) + 1
    term.setCursorPos(x, y)
    term.write(text)
end

local function drawHeader(title)
    setColor(colors.white, colors.blue)
    term.setCursorPos(1, 1)
    term.clearLine()
    centerText(1, title)
    setColor(colors.white, colors.black)
end

local function drawFooter(text)
    setColor(colors.lightGray, colors.gray)
    term.setCursorPos(1, screenH)
    term.clearLine()
    term.write(text:sub(1, screenW))
    setColor(colors.white, colors.black)
end

local function drawStatusBar(turtle)
    if not turtle then return end
    
    setColor(colors.black, colors.lightGray)
    term.setCursorPos(1, 2)
    term.clearLine()
    
    local status = string.format(" %s | Fuel: %d", 
        turtle.label or ("Turtle-" .. turtle.id),
        turtle.data and turtle.data.fuel or 0
    )
    term.write(status:sub(1, screenW))
    setColor(colors.white, colors.black)
end

local function truncate(text, maxLen)
    if #text <= maxLen then return text end
    return text:sub(1, maxLen - 2) .. ".."
end

-- ======= Turtle Management =======

local function refreshTurtles()
    turtles = comms.getConnectedTurtles()
    lastRefresh = os.epoch("utc")
end

local function getTurtleList()
    local list = {}
    for id, turtle in pairs(turtles) do
        table.insert(list, turtle)
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function selectTurtle(turtle)
    selectedTurtle = turtle
    currentView = "turtle_detail"
end

-- ======= Command Functions =======

local function sendTurtleCommand(command, params)
    if not selectedTurtle then
        debugLog("warn", "No turtle selected!")
        return false
    end
    
    return comms.sendCommand(selectedTurtle.id, command, params)
end

local function buildForward(distance, width)
    return sendTurtleCommand(comms.COMMANDS.BUILD_FORWARD, {
        distance = distance,
        width = width,
    })
end

local function buildBackward(distance)
    return sendTurtleCommand(comms.COMMANDS.BUILD_BACKWARD, {
        distance = distance,
    })
end

local function moveUp(count)
    return sendTurtleCommand(comms.COMMANDS.MOVE_UP, { count = count })
end

local function moveDown(count)
    return sendTurtleCommand(comms.COMMANDS.MOVE_DOWN, { count = count })
end

local function turnLeft()
    return sendTurtleCommand(comms.COMMANDS.TURN_LEFT, {})
end

local function turnRight()
    return sendTurtleCommand(comms.COMMANDS.TURN_RIGHT, {})
end

local function setRoadWidth(width)
    return sendTurtleCommand(comms.COMMANDS.SET_WIDTH, { width = width })
end

local function setBlockType(blockType)
    return sendTurtleCommand(comms.COMMANDS.SET_BLOCK, { blockType = blockType })
end

local function refill()
    return sendTurtleCommand(comms.COMMANDS.REFILL, {})
end

local function deposit()
    return sendTurtleCommand(comms.COMMANDS.DEPOSIT, {})
end

local function goHome()
    return sendTurtleCommand(comms.COMMANDS.GO_HOME, {})
end

local function setHome()
    return sendTurtleCommand(comms.COMMANDS.SET_HOME, {})
end

local function stopTurtle()
    if selectedTurtle then
        comms.send(comms.MSG_TYPE.STOP, {}, selectedTurtle.id)
    end
end

-- ======= Update Functions =======

--- Update all connected turtles
local function updateAllTurtles()
    local turtleList = getTurtleList()
    for _, turtle in ipairs(turtleList) do
        comms.sendCommand(turtle.id, comms.COMMANDS.UPDATE, {})
    end
    return #turtleList
end

--- Update controller and restart
local function updateController()
    clearScreen()
    drawHeader("Updating Controller")
    
    term.setCursorPos(2, 4)
    term.write("Downloading update...")
    
    -- Run the update script headlessly
    local success = shell.run("wget", "run", config.UPDATER.BASE_URL .. "update.lua")
    
    if success then
        term.setCursorPos(2, 6)
        setColor(colors.lime)
        term.write("Update complete! Restarting...")
        setColor(colors.white)
        sleep(1)
        os.reboot()
    else
        term.setCursorPos(2, 6)
        setColor(colors.red)
        term.write("Update failed!")
        setColor(colors.white)
        sleep(2)
    end
end

--- Build with all turtles - each turtle builds one lane
---@param distance number Distance to build
local function buildWithAllTurtles(distance)
    local turtleList = getTurtleList()
    if #turtleList == 0 then
        return false
    end
    
    -- Send build command to all turtles with width=1 (each turtle is one lane)
    for _, turtle in ipairs(turtleList) do
        comms.sendCommand(turtle.id, comms.COMMANDS.BUILD_FORWARD, {
            distance = distance,
            width = 1, -- Each turtle only builds 1 lane (its own)
        })
    end
    
    return #turtleList
end

-- ======= Views =======

local function drawMainMenu()
    clearScreen()
    
    if isPocket then
        drawHeader("RBC v" .. CONTROLLER_VERSION)
    else
        drawHeader("RBC Controller v" .. CONTROLLER_VERSION)
    end
    
    local turtleList = getTurtleList()
    local y = 3
    
    if #turtleList == 0 then
        setColor(colors.yellow)
        centerText(y + 1, "No turtles")
        setColor(colors.lightGray)
        centerText(y + 2, "Searching...")
        setColor(colors.white)
    else
        setColor(colors.lime)
        term.setCursorPos(1, y)
        if isPocket then
            term.write(" Turtles: " .. #turtleList)
        else
            term.write(" Connected Turtles: " .. #turtleList)
        end
        setColor(colors.white)
        y = y + 1
        
        -- Calculate max turtles we can show
        local maxTurtles = isPocket and (screenH - 7) or (screenH - 8)
        
        for i, turtle in ipairs(turtleList) do
            if i > maxTurtles then break end
            
            local label = turtle.label or ("T-" .. turtle.id)
            local status = ""
            
            if turtle.data then
                if turtle.data.currentTask then
                    status = isPocket and "*" or "[Busy]"
                    setColor(colors.yellow)
                else
                    status = isPocket and "" or "[Idle]"
                    setColor(colors.lime)
                end
            else
                status = "?"
                setColor(colors.gray)
            end
            
            term.setCursorPos(1, y)
            if isPocket then
                -- Compact format for pocket: "1.Label *"
                local maxLabelLen = screenW - 4 - #status
                term.write(string.format(" %d.%s%s", i, truncate(label, maxLabelLen), status))
            else
                term.write(string.format(" %d. %s %s", i, truncate(label, screenW - 15), status))
            end
            setColor(colors.white)
            y = y + 1
        end
    end
    
    -- Draw menu options - adapt to pocket
    if isPocket then
        y = screenH - 4
        setColor(colors.lightBlue)
        term.setCursorPos(1, y)
        term.write(" 1-9:Sel A:All R:Rfsh")
        term.setCursorPos(1, y + 1)
        term.write(" U:Upd C:UpdCtrl Q:Quit")
        setColor(colors.white)
    else
        y = screenH - 6
        setColor(colors.lightBlue)
        term.setCursorPos(2, y)
        term.write("[1-9] Select turtle  [A] Build All")
        term.setCursorPos(2, y + 1)
        term.write("[R] Refresh  [P] Ping all")
        term.setCursorPos(2, y + 2)
        term.write("[U] Update All  [C] Update Controller")
        term.setCursorPos(2, y + 3)
        term.write("[Q] Quit")
        setColor(colors.white)
    end
    
    if isPocket then
        drawFooter(" T:" .. #turtleList .. " " .. os.date("%H:%M"))
    else
        drawFooter(" Turtles: " .. #turtleList .. " | " .. os.date("%H:%M:%S"))
    end
end

local function drawTurtleDetail()
    if not selectedTurtle then
        currentView = "main"
        return
    end
    
    clearScreen()
    local label = selectedTurtle.label or ("Turtle-" .. selectedTurtle.id)
    drawHeader(truncate(label, screenW - 2))
    
    local data = selectedTurtle.data or {}
    local y = 3
    
    if isPocket then
        -- Compact layout for pocket
        -- Position on one line
        if data.position then
            term.setCursorPos(1, y)
            setColor(colors.lightBlue)
            term.write(" Pos:")
            setColor(colors.white)
            term.write(string.format("%.0f,%.0f,%.0f", 
                data.position.x or 0, 
                data.position.y or 0, 
                data.position.z or 0))
            y = y + 1
            
            term.setCursorPos(1, y)
            term.write(" " .. (data.facingName or "?"))
            if data.hasGPS then
                setColor(colors.lime)
                term.write(" GPS")
                setColor(colors.white)
            end
        else
            term.setCursorPos(1, y)
            term.write(" Pos: Unknown")
        end
        y = y + 1
        
        -- Fuel and blocks on same line
        term.setCursorPos(1, y)
        setColor(colors.lightBlue)
        term.write(" F:")
        setColor(colors.white)
        term.write(tostring(data.fuel or 0))
        if data.inventory then
            term.write(" B:" .. (data.inventory.roadBlockCount or 0))
        end
        y = y + 1
        
        -- Task if running
        if data.currentTask then
            term.setCursorPos(1, y)
            setColor(colors.yellow)
            local taskStr = truncate(data.currentTask, screenW - 2)
            if data.taskTotal > 0 then
                taskStr = string.format("%s %d/%d", 
                    truncate(data.currentTask, screenW - 10),
                    data.taskProgress or 0, data.taskTotal)
            end
            term.write(" " .. taskStr)
            setColor(colors.white)
            y = y + 1
        end
        y = y + 1
        
        -- Road settings
        term.setCursorPos(1, y)
        setColor(colors.lightBlue)
        term.write(" W:")
        setColor(colors.white)
        term.write(tostring(data.roadWidth or 3))
        term.write(" H:" .. (data.mineHeight or 5))
        y = y + 1
        
        if data.roadBlockType then
            term.setCursorPos(1, y)
            local blockName = data.roadBlockType:gsub("minecraft:", ""):gsub("_", " ")
            term.write(" " .. truncate(blockName, screenW - 2))
        end
        
        -- Compact menu for pocket
        local menuY = screenH - 4
        setColor(colors.lightBlue)
        term.setCursorPos(1, menuY)
        term.write(" F:Fwd B:Bck U/D L/R")
        term.setCursorPos(1, menuY + 1)
        term.write(" W:Wid H:Home S:Stop")
        term.setCursorPos(1, menuY + 2)
        term.write(" I:Fill O:Dep <-:Back")
        setColor(colors.white)
    else
        -- Full layout for computer
        -- Position info
        setColor(colors.lightBlue)
        term.setCursorPos(2, y)
        term.write("Position:")
        setColor(colors.white)
        y = y + 1
        
        if data.position then
            term.setCursorPos(3, y)
            term.write(string.format("X:%.0f Y:%.0f Z:%.0f", 
                data.position.x or 0, 
                data.position.y or 0, 
                data.position.z or 0))
            y = y + 1
            term.setCursorPos(3, y)
            term.write("Facing: " .. (data.facingName or "Unknown"))
            if data.hasGPS then
                setColor(colors.lime)
                term.write(" [GPS]")
                setColor(colors.white)
            end
        else
            term.setCursorPos(3, y)
            term.write("Unknown")
        end
        y = y + 2
        
        -- Status info
        setColor(colors.lightBlue)
        term.setCursorPos(2, y)
        term.write("Status:")
        setColor(colors.white)
        y = y + 1
        
        term.setCursorPos(3, y)
        local fuelPct = 0
        if data.fuelLimit and data.fuelLimit > 0 then
            fuelPct = math.floor((data.fuel or 0) / data.fuelLimit * 100)
        end
        term.write(string.format("Fuel: %d (%d%%)", data.fuel or 0, fuelPct))
        y = y + 1
        
        if data.inventory then
            term.setCursorPos(3, y)
            term.write(string.format("Blocks: %d", data.inventory.roadBlockCount or 0))
            y = y + 1
        end
        
        if data.currentTask then
            term.setCursorPos(3, y)
            setColor(colors.yellow)
            term.write("Task: " .. data.currentTask)
            if data.taskTotal > 0 then
                term.write(string.format(" (%d/%d)", data.taskProgress or 0, data.taskTotal))
            end
            setColor(colors.white)
            y = y + 1
        end
        y = y + 1
        
        -- Road settings
        setColor(colors.lightBlue)
        term.setCursorPos(2, y)
        term.write("Road Settings:")
        setColor(colors.white)
        y = y + 1
        
        term.setCursorPos(3, y)
        term.write(string.format("Width: %d  Height: %d", 
            data.roadWidth or 3, 
            data.mineHeight or 5))
        y = y + 1
        
        if data.roadBlockType then
            term.setCursorPos(3, y)
            local blockName = data.roadBlockType:gsub("minecraft:", ""):gsub("_", " ")
            term.write("Block: " .. truncate(blockName, screenW - 10))
        end
        
        -- Full menu for computer
        local menuY = screenH - 6
        setColor(colors.lightBlue)
        term.setCursorPos(2, menuY)
        term.write("[F] Build Forward  [B] Build Backward")
        term.setCursorPos(2, menuY + 1)
        term.write("[U] Move Up        [D] Move Down")
        term.setCursorPos(2, menuY + 2)
        term.write("[L] Turn Left      [R] Turn Right")
        term.setCursorPos(2, menuY + 3)
        term.write("[W] Set Width      [T] Set Block Type")
        term.setCursorPos(2, menuY + 4)
        term.write("[H] Go Home [G] Set Home [I] Refill [O] Deposit")
        term.setCursorPos(2, menuY + 5)
        term.write("[S] Stop  [Backspace] Back")
        setColor(colors.white)
    end
    
    if isPocket then
        drawFooter(" " .. truncate(label, screenW - 8) .. " " .. os.date("%H:%M"))
    else
        drawFooter(" " .. label .. " | " .. os.date("%H:%M:%S"))
    end
end

local function promptNumber(prompt, default)
    inputMode = true
    clearScreen()
    
    if isPocket then
        drawHeader("Enter Value")
        setColor(colors.white)
        term.setCursorPos(1, 3)
        term.write(" " .. truncate(prompt, screenW - 2))
        term.setCursorPos(1, 4)
        term.write(" Def:" .. tostring(default or 0))
        term.setCursorPos(1, 5)
        setColor(colors.lightGray)
        term.write(" Enter=OK Q=Cancel")
        term.setCursorPos(1, 7)
        setColor(colors.white)
        term.write(" > ")
    else
        drawHeader("Enter Value")
        setColor(colors.white)
        term.setCursorPos(2, 4)
        term.write(prompt)
        term.setCursorPos(2, 6)
        term.write("Default: " .. tostring(default or 0))
        term.setCursorPos(2, 7)
        setColor(colors.lightGray)
        term.write("(Press Enter for default, Q to cancel)")
        term.setCursorPos(2, 9)
        setColor(colors.white)
        term.write("> ")
    end
    
    setColor(colors.yellow)
    term.setCursorBlink(true)
    
    local input = ""
    local cursorX = isPocket and 4 or 4
    local cursorY = isPocket and 7 or 9
    
    while true do
        term.setCursorPos(cursorX, cursorY)
        local event, param = os.pullEvent()
        
        if event == "char" then
            -- Only allow numbers and minus sign
            if param:match("[0-9%-]") then
                input = input .. param
                term.write(param)
                cursorX = cursorX + 1
            end
        elseif event == "key" then
            if param == keys.enter or param == keys.numPadEnter then
                break
            elseif param == keys.backspace then
                if #input > 0 then
                    input = input:sub(1, -2)
                    cursorX = cursorX - 1
                    term.setCursorPos(cursorX, cursorY)
                    term.write(" ")
                end
            elseif param == keys.q then
                term.setCursorBlink(false)
                setColor(colors.white)
                inputMode = false
                return nil
            end
        end
    end
    
    term.setCursorBlink(false)
    setColor(colors.white)
    inputMode = false
    
    local num = tonumber(input)
    if num then
        return num
    end
    return default
end

local function promptString(prompt, default)
    inputMode = true
    clearScreen()
    
    if isPocket then
        drawHeader("Enter Value")
        setColor(colors.white)
        term.setCursorPos(1, 3)
        term.write(" " .. truncate(prompt, screenW - 2))
        if default then
            term.setCursorPos(1, 4)
            term.write(" Def:" .. truncate(tostring(default), screenW - 6))
        end
        term.setCursorPos(1, 5)
        setColor(colors.lightGray)
        term.write(" Enter=OK Q=Cancel")
        term.setCursorPos(1, 7)
        setColor(colors.white)
        term.write(" > ")
    else
        drawHeader("Enter Value")
        setColor(colors.white)
        term.setCursorPos(2, 4)
        term.write(prompt)
        if default then
            term.setCursorPos(2, 6)
            term.write("Default: " .. tostring(default))
        end
        term.setCursorPos(2, 7)
        setColor(colors.lightGray)
        term.write("(Press Enter to confirm, Q to cancel)")
        term.setCursorPos(2, 9)
        setColor(colors.white)
        term.write("> ")
    end
    
    setColor(colors.yellow)
    term.setCursorBlink(true)
    
    local input = ""
    local cursorX = isPocket and 4 or 4
    local cursorY = isPocket and 7 or 9
    
    while true do
        term.setCursorPos(cursorX, cursorY)
        local event, param = os.pullEvent()
        
        if event == "char" then
            input = input .. param
            term.write(param)
            cursorX = cursorX + 1
        elseif event == "key" then
            if param == keys.enter or param == keys.numPadEnter then
                break
            elseif param == keys.backspace then
                if #input > 0 then
                    input = input:sub(1, -2)
                    cursorX = cursorX - 1
                    term.setCursorPos(cursorX, cursorY)
                    term.write(" ")
                end
            elseif param == keys.q then
                term.setCursorBlink(false)
                setColor(colors.white)
                inputMode = false
                return nil
            end
        end
    end
    
    term.setCursorBlink(false)
    setColor(colors.white)
    inputMode = false
    
    if #input > 0 then
        return input
    end
    return default
end

-- ======= Event Handlers =======

local function handleMainMenuKey(key)
    local turtleList = getTurtleList()
    
    if key >= keys.one and key <= keys.nine then
        local index = key - keys.one + 1
        if turtleList[index] then
            selectTurtle(turtleList[index])
        end
    elseif key == keys.r then
        comms.ping()
        refreshTurtles()
    elseif key == keys.p then
        comms.ping()
    elseif key == keys.a then
        -- Build with all turtles
        if #turtleList > 0 then
            local distance = promptNumber("Enter distance (all " .. #turtleList .. " turtles):", 10)
            if distance and distance > 0 then
                local count = buildWithAllTurtles(distance)
                if count > 0 then
                    clearScreen()
                    drawHeader("Building")
                    setColor(colors.lime)
                    centerText(6, "Building " .. distance .. " blocks with " .. count .. " turtles")
                    setColor(colors.lightGray)
                    centerText(8, "(Width = " .. count .. " total)")
                    setColor(colors.white)
                    sleep(2)
                end
            end
        end
    elseif key == keys.u then
        -- Update all turtles
        clearScreen()
        drawHeader("Updating Turtles")
        term.setCursorPos(2, 4)
        term.write("Sending update command to all turtles...")
        local count = updateAllTurtles()
        term.setCursorPos(2, 6)
        setColor(colors.lime)
        term.write("Update sent to " .. count .. " turtle(s)")
        setColor(colors.lightGray)
        term.setCursorPos(2, 8)
        term.write("Turtles will restart after updating.")
        setColor(colors.white)
        sleep(3)
    elseif key == keys.c then
        -- Update controller
        updateController()
    elseif key == keys.q then
        running = false
    end
end

local function handleTurtleDetailKey(key)
    if key == keys.backspace then
        selectedTurtle = nil
        currentView = "main"
        
    elseif key == keys.f then
        -- Build forward
        local distance = promptNumber("Enter distance (blocks):", 10)
        if distance and distance > 0 then
            buildForward(distance)
        end
        
    elseif key == keys.b then
        -- Build backward
        local distance = promptNumber("Enter distance (blocks):", 10)
        if distance and distance > 0 then
            buildBackward(distance)
        end
        
    elseif key == keys.u then
        -- Move up
        local count = promptNumber("Enter height:", 1)
        if count and count > 0 then
            moveUp(count)
        end
        
    elseif key == keys.d then
        -- Move down
        local count = promptNumber("Enter depth:", 1)
        if count and count > 0 then
            moveDown(count)
        end
        
    elseif key == keys.l then
        turnLeft()
        
    elseif key == keys.r then
        turnRight()
        
    elseif key == keys.w then
        -- Set width
        local width = promptNumber("Enter road width:", 3)
        if width and width > 0 then
            setRoadWidth(width)
        end
        
    elseif key == keys.t then
        -- Set block type - show current inventory blocks
        local blockType = promptString("Enter block ID (e.g. minecraft:stone):", nil)
        if blockType and #blockType > 0 then
            setBlockType(blockType)
        end
        
    elseif key == keys.h then
        goHome()
        
    elseif key == keys.g then
        setHome()
        
    elseif key == keys.i then
        refill()
        
    elseif key == keys.o then
        deposit()
        
    elseif key == keys.s then
        stopTurtle()
    end
end

local function handleKey(key)
    if currentView == "main" then
        handleMainMenuKey(key)
    elseif currentView == "turtle_detail" then
        handleTurtleDetailKey(key)
    end
end

-- ======= Message Handlers =======

local function handleStatus(message, senderId, senderLabel)
    -- Refresh our local turtle list from comms module
    debugLog("info", "Received STATUS from turtle #" .. senderId .. " (" .. (senderLabel or "unnamed") .. ")")
    refreshTurtles()
    
    -- Update selected turtle if it's this one
    if selectedTurtle and selectedTurtle.id == senderId then
        selectedTurtle = turtles[senderId]
    end
end

local function handlePong(message, senderId, senderLabel)
    -- Refresh turtle list when we get a pong
    debugLog("info", "Received PONG from turtle #" .. senderId .. " (" .. (senderLabel or "unnamed") .. ")")
    refreshTurtles()
end

local function handleComplete(message, senderId, senderLabel)
    local cmd = message.data.command or "?"
    debugLog("info", "Command complete: " .. cmd .. " from " .. (senderLabel or senderId))
end

local function handleError(message, senderId, senderLabel)
    local err = message.data.error or "Unknown error"
    debugLog("error", "Error from " .. (senderLabel or senderId) .. ": " .. err)
end

-- ======= Main Loop =======

local function displayLoop()
    while running do
        if not inputMode then
            refreshTurtles()
            
            if currentView == "main" then
                drawMainMenu()
            elseif currentView == "turtle_detail" then
                drawTurtleDetail()
            end
        end
        
        sleep(config.DISPLAY.REFRESH_RATE)
    end
end

local function inputLoop()
    while running do
        local event, key = os.pullEvent("key")
        handleKey(key)
    end
end

local function messageLoop()
    while running do
        local message = comms.receive(0.5)
        -- Messages are handled by registered handlers
    end
end

local function main(args)
    clearScreen()
    
    print("================================")
    print("  RBC Controller")
    print("  Version " .. CONTROLLER_VERSION)
    print("================================")
    print("")
    
    -- Check for updates
    if updater and config.UPDATER and config.UPDATER.CHECK_ON_STARTUP then
        print("Checking for updates...")
    end
    
    -- Check for debug flag
    args = args or {}
    if args[1] == "--debug" or args[1] == "-d" then
        DEBUG = true
        comms.DEBUG = true
        print("Debug mode enabled")
    end
    
    -- Initialize communications
    print("Initializing wireless modem...")
    if not comms.init(config.NETWORK) then
        setColor(colors.red)
        print("ERROR: No wireless modem found!")
        print("Please attach an ender modem or wireless modem.")
        setColor(colors.white)
        return
    end
    print("Modem ready on channel " .. config.NETWORK.CHANNEL .. " (reply: " .. config.NETWORK.REPLY_CHANNEL .. ")")
    print("Controller ID: " .. os.getComputerID())
    
    -- Register message handlers
    comms.onMessage(comms.MSG_TYPE.STATUS, handleStatus)
    comms.onMessage(comms.MSG_TYPE.PONG, handlePong)
    comms.onMessage(comms.MSG_TYPE.COMPLETE, handleComplete)
    comms.onMessage(comms.MSG_TYPE.ERROR, handleError)
    
    print("")
    print("Searching for turtles...")
    comms.ping()
    
    -- Wait for responses while actively receiving messages
    local searchEndTime = os.epoch("utc") + 2000 -- 2 seconds
    while os.epoch("utc") < searchEndTime do
        comms.receive(0.1)
    end
    
    refreshTurtles()
    local turtleList = getTurtleList()
    print("Found " .. #turtleList .. " turtle(s)")
    
    sleep(1)
    
    -- Main loop
    parallel.waitForAny(
        displayLoop,
        inputLoop,
        messageLoop
    )
    
    comms.close()
    clearScreen()
    print("RBC Controller stopped")
end

main({...})
