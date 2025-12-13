--- Hierarchical Router Module for CC:Tweaked
--- Provides a modular routing system for apartment complex networks
---
--- Features: Hierarchical addressing (1xx/2xx/3xx), message forwarding,
--- configurable ports per side, hop tracking, and final router execution.
---
---@version 1.0.0
-- @module router

local VERSION = "1.0.0"

local log = require("lib.log")
local tables = require("lib.tables")

---@class Router
---@field id number Router ID (3-digit hierarchical format)
---@field isFinal boolean Whether this router executes messages or forwards them
---@field ports table<string, number[]> Port mappings per modem side
---@field routes table<number, string> Routing table: destination prefix -> modem side
---@field filters table<string, boolean> Protocol filters (true = blocked)
---@field portFilters table<number, boolean> Port filters (true = blocked)
---@field handlers table<string, function> Protocol handlers for final routers
---@field modems table<string, table> Wrapped modem peripherals by side

local Router = {}
Router.__index = Router

-- Constants
local PROTOCOL = "hierarchical_router"
local DEFAULT_PORT = 4800
local MAX_HOPS = 64

---@class Message
---@field origin number Sending router ID
---@field destination number Target router ID
---@field protocol string Message protocol type
---@field port number Numeric port
---@field payload table Data payload
---@field hops number[] List of visited router IDs
---@field distance number Cumulative hop count

---Create a new router instance
---@param id number Router ID in hierarchical format (e.g., 101, 201, 301)
---@param isFinal? boolean Whether this router executes messages (default: false)
---@return Router
function Router.new(id, isFinal)
    local self = setmetatable({}, Router)
    
    self.id = id
    self.isFinal = isFinal or false
    self.ports = {}
    self.routes = {}
    self.filters = {}
    self.portFilters = {}
    self.handlers = {}
    self.modems = {}
    self.openPorts = {}
    
    log.info(string.format("Router %d initialized (final: %s)", id, tostring(self.isFinal)))
    
    return self
end

---Get the hierarchy level of a router ID (1xx=1, 2xx=2, etc.)
---@param id number Router ID
---@return number level Hierarchy level (1-9)
function Router.getLevel(id)
    return math.floor(id / 100)
end

---Get the parent router ID for hierarchical forwarding
---@param id number Router ID
---@return number|nil parentId Parent router ID or nil if at top level
function Router.getParentId(id)
    local level = Router.getLevel(id)
    if level <= 1 then
        return nil -- Already at top level
    end
    local suffix = id % 100
    return (level - 1) * 100 + suffix
end

---Attach a modem on a specific side
---@param side string Modem side (top, bottom, left, right, front, back, or peripheral name)
---@return boolean success
function Router:attachModem(side)
    local modem = peripheral.wrap(side)
    if not modem or not modem.isWireless then
        -- Try wired modem
        if modem and modem.open then
            self.modems[side] = modem
            self.ports[side] = {}
            self.openPorts[side] = {}
            log.info(string.format("Attached wired modem on %s", side))
            return true
        end
        log.error(string.format("No valid modem found on %s", side))
        return false
    end
    
    self.modems[side] = modem
    self.ports[side] = {}
    self.openPorts[side] = {}
    log.info(string.format("Attached modem on %s", side))
    return true
end

---Open a port on a specific modem side
---@param side string Modem side
---@param port number Port number to open
---@return boolean success
function Router:openPort(side, port)
    local modem = self.modems[side]
    if not modem then
        log.error(string.format("No modem on side %s", side))
        return false
    end
    
    if modem.isOpen(port) then
        log.warn(string.format("Port %d already open on %s", port, side))
        return true
    end
    
    modem.open(port)
    table.insert(self.ports[side], port)
    self.openPorts[side][port] = true
    log.info(string.format("Opened port %d on %s", port, side))
    return true
end

---Close a port on a specific modem side
---@param side string Modem side
---@param port number Port number to close
---@return boolean success
function Router:closePort(side, port)
    local modem = self.modems[side]
    if not modem then
        log.error(string.format("No modem on side %s", side))
        return false
    end
    
    if not modem.isOpen(port) then
        return true
    end
    
    modem.close(port)
    self.openPorts[side][port] = nil
    
    -- Remove from ports list
    for i, p in ipairs(self.ports[side]) do
        if p == port then
            table.remove(self.ports[side], i)
            break
        end
    end
    
    log.info(string.format("Closed port %d on %s", port, side))
    return true
end

---Add a route for a destination prefix
---@param prefix number Destination prefix (e.g., 2 for all 2xx routers)
---@param side string Modem side to forward to
function Router:addRoute(prefix, side)
    self.routes[prefix] = side
    log.info(string.format("Added route: %dxx -> %s", prefix, side))
end

---Remove a route
---@param prefix number Destination prefix to remove
function Router:removeRoute(prefix)
    self.routes[prefix] = nil
    log.info(string.format("Removed route: %dxx", prefix))
end

---Add a protocol filter (block messages with this protocol)
---@param protocol string Protocol to block
function Router:blockProtocol(protocol)
    self.filters[protocol] = true
    log.info(string.format("Blocked protocol: %s", protocol))
end

---Remove a protocol filter
---@param protocol string Protocol to unblock
function Router:unblockProtocol(protocol)
    self.filters[protocol] = nil
    log.info(string.format("Unblocked protocol: %s", protocol))
end

---Add a port filter (block messages on this port)
---@param port number Port to block
function Router:blockPort(port)
    self.portFilters[port] = true
    log.info(string.format("Blocked port: %d", port))
end

---Remove a port filter
---@param port number Port to unblock
function Router:unblockPort(port)
    self.portFilters[port] = nil
    log.info(string.format("Unblocked port: %d", port))
end

---Register a handler for a protocol (only used by final routers)
---@param protocol string Protocol name
---@param handler function Handler function(message, router)
function Router:registerHandler(protocol, handler)
    self.handlers[protocol] = handler
    log.info(string.format("Registered handler for protocol: %s", protocol))
end

---Create a new message
---@param destination number Target router ID
---@param protocol string Message protocol
---@param payload table Message payload
---@param port? number Port number (default: DEFAULT_PORT)
---@return Message
function Router:createMessage(destination, protocol, payload, port)
    return {
        origin = self.id,
        destination = destination,
        protocol = protocol,
        port = port or DEFAULT_PORT,
        payload = payload or {},
        hops = {},
        distance = 0,
    }
end

---Check if a message should be filtered
---@param message Message
---@return boolean blocked, string? reason
function Router:shouldFilter(message)
    if self.filters[message.protocol] then
        return true, "protocol blocked"
    end
    if self.portFilters[message.port] then
        return true, "port blocked"
    end
    return false, nil
end

---Determine the next hop for a message
---@param message Message
---@return string|nil side Modem side to forward to, or nil if no route
function Router:getNextHop(message)
    local destLevel = Router.getLevel(message.destination)
    local myLevel = Router.getLevel(self.id)
    
    -- Check if we have a direct route to this destination prefix
    if self.routes[destLevel] then
        return self.routes[destLevel]
    end
    
    -- Hierarchical routing: go up if we need to reach a different branch
    if destLevel ~= myLevel then
        -- Find the route to go up the hierarchy
        local parentLevel = myLevel - 1
        if parentLevel >= 1 and self.routes[parentLevel] then
            return self.routes[parentLevel]
        end
    end
    
    -- Fallback: try to find any route
    for prefix, side in pairs(self.routes) do
        return side
    end
    
    return nil
end

---Send a message to a destination
---@param message Message
---@param side? string Specific side to send on (optional, auto-routes if nil)
---@return boolean success
function Router:send(message, side)
    -- Add ourselves to hops
    table.insert(message.hops, self.id)
    message.distance = message.distance + 1
    
    -- Check for routing loops
    local hopCount = {}
    for _, hop in ipairs(message.hops) do
        hopCount[hop] = (hopCount[hop] or 0) + 1
        if hopCount[hop] > 2 then
            log.error(string.format("Routing loop detected! Message from %d to %d", 
                message.origin, message.destination))
            return false
        end
    end
    
    -- Check max hops
    if message.distance > MAX_HOPS then
        log.error(string.format("Max hops exceeded! Message from %d to %d", 
            message.origin, message.destination))
        return false
    end
    
    -- Determine which side to send on
    local targetSide = side or self:getNextHop(message)
    if not targetSide then
        log.error(string.format("No route to %d", message.destination))
        return false
    end
    
    local modem = self.modems[targetSide]
    if not modem then
        log.error(string.format("No modem on side %s", targetSide))
        return false
    end
    
    -- Ensure port is open
    if not modem.isOpen(message.port) then
        self:openPort(targetSide, message.port)
    end
    
    -- Transmit
    modem.transmit(message.port, message.port, {
        protocol = PROTOCOL,
        data = message,
    })
    
    log.info(string.format("Sent message: %d -> %d (port %d, hops: %d)", 
        message.origin, message.destination, message.port, message.distance))
    
    return true
end

---Forward a received message to the next hop
---@param message Message
---@return boolean success
function Router:forward(message)
    local blocked, reason = self:shouldFilter(message)
    if blocked then
        log.warn(string.format("Blocked message from %d: %s", message.origin, reason))
        return false
    end
    
    log.info(string.format("Forwarding message: %d -> %d (distance: %d)", 
        message.origin, message.destination, message.distance))
    
    return self:send(message)
end

---Execute a message (for final routers)
---@param message Message
---@return boolean success
function Router:execute(message)
    local handler = self.handlers[message.protocol]
    if not handler then
        log.warn(string.format("No handler for protocol: %s", message.protocol))
        return false
    end
    
    log.info(string.format("Executing message from %d (protocol: %s, distance: %d)", 
        message.origin, message.protocol, message.distance))
    
    local hopsStr = table.concat(message.hops, " -> ")
    log.info(string.format("Hop path: %s", hopsStr))
    
    local success, err = pcall(handler, message, self)
    if not success then
        log.error(string.format("Handler error: %s", tostring(err)))
        return false
    end
    
    return true
end

---Process a received message
---@param message Message
---@return boolean success
function Router:processMessage(message)
    local blocked, reason = self:shouldFilter(message)
    if blocked then
        log.warn(string.format("Filtered message from %d: %s", message.origin, reason))
        return false
    end
    
    -- Check if this message is for us
    if message.destination == self.id then
        if self.isFinal then
            return self:execute(message)
        else
            log.warn(string.format("Message for %d but not a final router", self.id))
            return false
        end
    end
    
    -- Not for us, forward it
    return self:forward(message)
end

---Listen for incoming messages (blocking)
---@param timeout? number Timeout in seconds (nil for indefinite)
---@return Message|nil message Received message or nil on timeout
---@return string|nil side Side the message was received on
function Router:receive(timeout)
    local timer = nil
    if timeout then
        timer = os.startTimer(timeout)
    end
    
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        
        if event == "modem_message" then
            local side, channel, replyChannel, rawMessage, distance = p1, p2, p3, p4, p5
            
            -- Validate message format
            if type(rawMessage) == "table" and rawMessage.protocol == PROTOCOL and rawMessage.data then
                local message = rawMessage.data
                
                -- Validate message structure
                if message.origin and message.destination and message.protocol then
                    return message, side
                end
            end
        elseif event == "timer" and p1 == timer then
            return nil, nil
        end
    end
end

---Main router loop (blocking)
---Continuously receives and processes messages
function Router:run()
    log.info(string.format("Router %d starting main loop", self.id))
    
    while true do
        local message, side = self:receive()
        if message then
            self:processMessage(message)
        end
    end
end

---Send a message and wait for a response
---@param destination number Target router ID
---@param protocol string Message protocol
---@param payload table Message payload
---@param responseProtocol string Expected response protocol
---@param timeout? number Timeout in seconds (default: 5)
---@return Message|nil response
function Router:sendAndReceive(destination, protocol, payload, responseProtocol, timeout)
    timeout = timeout or 5
    
    local message = self:createMessage(destination, protocol, payload)
    if not self:send(message) then
        return nil
    end
    
    local endTime = os.epoch("utc") + (timeout * 1000)
    
    while os.epoch("utc") < endTime do
        local remaining = (endTime - os.epoch("utc")) / 1000
        local response = self:receive(remaining)
        
        if response and response.origin == destination and response.protocol == responseProtocol then
            return response
        end
    end
    
    return nil
end

---Mark this router as final (executes messages instead of forwarding)
function Router:setFinal(isFinal)
    self.isFinal = isFinal
    log.info(string.format("Router %d set to final: %s", self.id, tostring(isFinal)))
end

---Get router status information
---@return table status
function Router:getStatus()
    local openPortsList = {}
    for side, ports in pairs(self.openPorts) do
        for port, _ in pairs(ports) do
            table.insert(openPortsList, {side = side, port = port})
        end
    end
    
    return {
        id = self.id,
        level = Router.getLevel(self.id),
        isFinal = self.isFinal,
        modems = tables.count(self.modems),
        routes = tables.count(self.routes),
        openPorts = openPortsList,
        protocols = tables.count(self.handlers),
    }
end

---Log router status
function Router:logStatus()
    local status = self:getStatus()
    log.info(string.format("Router %d Status:", status.id))
    log.info(string.format("  Level: %d, Final: %s", status.level, tostring(status.isFinal)))
    log.info(string.format("  Modems: %d, Routes: %d", status.modems, status.routes))
    log.info(string.format("  Open ports: %d", #status.openPorts))
end

-- Module exports
local module = {
    VERSION = VERSION,
    Router = Router,
    PROTOCOL = PROTOCOL,
    DEFAULT_PORT = DEFAULT_PORT,
    MAX_HOPS = MAX_HOPS,
    
    -- Convenience constructors
    new = Router.new,
    getLevel = Router.getLevel,
    getParentId = Router.getParentId,
}

return module
