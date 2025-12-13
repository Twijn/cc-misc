--- Hierarchical Router Main Program
--- Entry point for running a router node in the apartment network
---
---@usage
---router
---
---@version 1.0.0

local VERSION = "1.0.0"

-- Setup package path
if not package.path:find("lib") then
    package.path = package.path .. ";/lib/?.lua"
end

local log = require("lib.log")
local s = require("lib.s")
local router = require("lib.router")
local config = require("config")

-- ======= Configuration =======

local function configure()
    term.clear()
    term.setCursorPos(1, 1)
    
    print("================================")
    print("  Hierarchical Router v" .. VERSION)
    print("================================")
    print("")
    
    -- Get router ID
    local routerId = s.number("router.id", 100, 999, nil)
    
    -- Get final status
    local isFinal = s.boolean("router.is_final")
    
    return routerId, isFinal
end

-- ======= Modem Detection =======

local function detectModems()
    local modems = {}
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    
    for _, side in ipairs(sides) do
        local p = peripheral.wrap(side)
        if p and p.open then
            table.insert(modems, side)
            log.info(string.format("Found modem on %s", side))
        end
    end
    
    -- Also check for named peripherals (wired network)
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        local p = peripheral.wrap(name)
        if p and p.open and not p.isWireless then
            -- Only add if not already in list
            local found = false
            for _, existing in ipairs(modems) do
                if existing == name then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(modems, name)
                log.info(string.format("Found wired modem: %s", name))
            end
        end
    end
    
    return modems
end

-- ======= Route Configuration =======

local function configureRoutes(r)
    -- Check if routes are configured in settings
    local routeCount = settings.get("router.route_count") or 0
    
    if routeCount == 0 then
        print("")
        print("No routes configured.")
        print("Would you like to add routes now? (y/n)")
        
        local resp = read():lower()
        if resp == "y" then
            while true do
                print("")
                print("Enter destination prefix (1-9, or 0 to finish):")
                local prefix = tonumber(read())
                
                if not prefix or prefix == 0 then
                    break
                end
                
                if prefix >= 1 and prefix <= 9 then
                    print(string.format("Enter modem side for %dxx destinations:", prefix))
                    local side = read()
                    
                    if r.modems[side] then
                        r:addRoute(prefix, side)
                        routeCount = routeCount + 1
                        settings.set("router.route." .. prefix, side)
                        settings.set("router.route_count", routeCount)
                        settings.save()
                        print(string.format("Added route: %dxx -> %s", prefix, side))
                    else
                        print("Invalid modem side!")
                    end
                end
            end
        end
    else
        -- Load saved routes
        for prefix = 1, 9 do
            local side = settings.get("router.route." .. prefix)
            if side and r.modems[side] then
                r:addRoute(prefix, side)
            end
        end
    end
end

-- ======= Default Protocol Handlers =======

local function registerDefaultHandlers(r)
    -- Ping handler
    r:registerHandler(config.PROTOCOLS.PING, function(message, router)
        log.info(string.format("Received PING from %d", message.origin))
        
        local response = router:createMessage(
            message.origin,
            config.PROTOCOLS.PONG,
            {
                timestamp = os.epoch("utc"),
                routerId = router.id,
            }
        )
        router:send(response)
    end)
    
    -- Status request handler
    r:registerHandler(config.PROTOCOLS.STATUS_REQUEST, function(message, router)
        log.info(string.format("Received STATUS_REQUEST from %d", message.origin))
        
        local status = router:getStatus()
        local response = router:createMessage(
            message.origin,
            config.PROTOCOLS.STATUS_RESPONSE,
            status
        )
        router:send(response)
    end)
    
    -- Command handler
    r:registerHandler(config.PROTOCOLS.COMMAND, function(message, router)
        log.info(string.format("Received COMMAND from %d: %s", 
            message.origin, message.payload.command or "unknown"))
        
        local result = {success = false, error = "Unknown command"}
        local cmd = message.payload.command
        
        if cmd == "status" then
            result = {success = true, data = router:getStatus()}
        elseif cmd == "reboot" then
            result = {success = true, data = "Rebooting..."}
            -- Schedule reboot after sending response
            os.startTimer(1)
        elseif cmd == "log" then
            result = {success = true, data = message.payload.message or "No message"}
            log.info("Remote log: " .. tostring(message.payload.message))
        end
        
        local response = router:createMessage(
            message.origin,
            config.PROTOCOLS.COMMAND_RESPONSE,
            result
        )
        router:send(response)
        
        if cmd == "reboot" then
            os.sleep(0.5)
            os.reboot()
        end
    end)
    
    -- Discovery handler
    r:registerHandler(config.PROTOCOLS.DISCOVER, function(message, router)
        log.info(string.format("Received DISCOVER from %d", message.origin))
        
        local response = router:createMessage(
            message.origin,
            config.PROTOCOLS.ANNOUNCE,
            {
                id = router.id,
                level = router.getLevel(router.id),
                isFinal = router.isFinal,
                label = os.getComputerLabel() or ("Router-" .. router.id),
            }
        )
        router:send(response)
    end)
end

-- ======= Main =======

local function main()
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Configure router
    local routerId, isFinal = configure()
    
    print("")
    log.info(string.format("Starting Router %d (Level %d, Final: %s)", 
        routerId, router.getLevel(routerId), tostring(isFinal)))
    
    -- Create router instance
    local r = router.new(routerId, isFinal)
    
    -- Detect and attach modems
    local modemSides = config.MODEMS.SIDES or detectModems()
    
    if #modemSides == 0 then
        log.error("No modems found! Please attach a modem.")
        return
    end
    
    for _, side in ipairs(modemSides) do
        r:attachModem(side)
        
        -- Open default ports
        for _, port in ipairs(config.PORTS.DEFAULT_PORTS) do
            r:openPort(side, port)
        end
    end
    
    -- Configure routes
    configureRoutes(r)
    
    -- Apply filters from config
    for protocol, blocked in pairs(config.FILTERS.BLOCKED_PROTOCOLS) do
        if blocked then
            r:blockProtocol(protocol)
        end
    end
    
    for port, blocked in pairs(config.FILTERS.BLOCKED_PORTS) do
        if blocked then
            r:blockPort(port)
        end
    end
    
    -- Register handlers for final routers
    if isFinal then
        registerDefaultHandlers(r)
    end
    
    -- Log status
    r:logStatus()
    
    print("")
    log.info("Router is running. Press Ctrl+T to terminate.")
    print("")
    
    -- Run the router
    r:run()
end

-- Run main with error handling
local success, err = pcall(main)
if not success then
    log.error("Router crashed: " .. tostring(err))
end
