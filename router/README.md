# Hierarchical Router System

A modular hierarchical routing system for CC:Tweaked, designed for apartment complex networks.

## Features

- **Hierarchical Addressing**: 3-digit router IDs (1xx, 2xx, 3xx) for layered network topology
- **Automatic Forwarding**: Messages route through the hierarchy until they reach their destination
- **Final Routers**: Designated endpoints that execute messages instead of forwarding
- **Configurable Ports**: Dynamic port management per modem side
- **Hop Tracking**: Full path logging with distance metrics
- **Protocol Filtering**: Block specific protocols or ports
- **Extensible Handlers**: Register custom protocol handlers for final routers

## Installation

```
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/router/install.lua
```

## Quick Start

1. Run `router` to start configuration
2. Enter your router ID (e.g., `101` for main layer, `201` for secondary)
3. Select if this is a "final" router (executes commands vs forwards)
4. Configure routes to other routers

## Network Topology

```
         [101] Main Server
           |
    +------+------+
    |             |
  [201]         [202]
    |             |
  +---+       +---+---+
  |   |       |   |   |
[301][302]  [303][304][305]
```

### Addressing Scheme

- `1xx` - Main server layer (central routing)
- `2xx` - Secondary layer (building/floor routers)
- `3xx` - Tertiary layer (apartment/room routers)

## Configuration

Edit `config.lua` to customize:

```lua
-- Router identity
config.ROUTER.ID = 101
config.ROUTER.IS_FINAL = true

-- Network settings
config.NETWORK.DEFAULT_PORT = 4800
config.NETWORK.MAX_HOPS = 64

-- Default ports to open
config.PORTS.DEFAULT_PORTS = {4800, 4801, 4802}

-- Routing table
config.ROUTES = {
    [2] = "top",    -- Route 2xx through top modem
    [3] = "back",   -- Route 3xx through back modem
}
```

## Message Structure

```lua
{
    origin = 301,              -- Sending router ID
    destination = 201,         -- Target router ID
    protocol = "my.protocol",  -- Message type
    port = 4800,               -- Network port
    payload = {},              -- Data payload
    hops = {301, 201},         -- Visited routers
    distance = 2,              -- Hop count
}
```

## API Usage

### Creating a Router

```lua
local router = require("lib.router")

-- Create a non-final router (forwards messages)
local r = router.new(201, false)

-- Create a final router (executes messages)
local r = router.new(301, true)
```

### Attaching Modems

```lua
r:attachModem("top")
r:attachModem("back")
r:openPort("top", 4800)
```

### Adding Routes

```lua
-- Route all 1xx destinations through "top" modem
r:addRoute(1, "top")

-- Route all 3xx destinations through "back" modem
r:addRoute(3, "back")
```

### Sending Messages

```lua
local message = r:createMessage(301, "my.protocol", {
    command = "status",
    data = "hello"
})

r:send(message)
```

### Registering Handlers (Final Routers)

```lua
r:registerHandler("my.protocol", function(message, router)
    print("Received:", message.payload.data)
    
    -- Send response
    local response = router:createMessage(
        message.origin,
        "my.protocol.response",
        {result = "success"}
    )
    router:send(response)
end)
```

### Filtering

```lua
-- Block a protocol
r:blockProtocol("debug")

-- Block a port
r:blockPort(9999)

-- Unblock
r:unblockProtocol("debug")
r:unblockPort(9999)
```

### Running the Router

```lua
-- Blocking main loop
r:run()

-- Or manual receive loop
while true do
    local message, side = r:receive(5)  -- 5 second timeout
    if message then
        r:processMessage(message)
    end
end
```

## Tools

### Ping

Test connectivity to a router:

```
tools/ping 201
```

### Discover

Find all routers on the network:

```
tools/discover
```

### Send

Send a custom message:

```
tools/send 201 router.command status
tools/send 301 router.command reboot
```

## Built-in Protocols

| Protocol | Description |
|----------|-------------|
| `router.ping` | Ping request |
| `router.pong` | Ping response |
| `router.status.request` | Status request |
| `router.status.response` | Status response |
| `router.command` | Execute command |
| `router.command.response` | Command result |
| `router.discover` | Discovery request |
| `router.announce` | Discovery response |

## File Structure

```
router/
├── router.lua          # Main program
├── config.lua          # Configuration
├── install.lua         # Installer
├── lib/
│   └── router.lua      # Router module
└── tools/
    ├── ping.lua        # Ping utility
    ├── discover.lua    # Discovery utility
    └── send.lua        # Send utility
```

## Dependencies

- `lib.log` - Logging utility
- `lib.tables` - Table utilities
- `lib.s` - Settings management

## License

MIT License - See LICENSE file in repository root.
