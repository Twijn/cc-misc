# shopk

A Kromer cryptocurrency API client for ComputerCraft that provides real-time transaction monitoring and wallet operations through WebSocket connections. Features: Real-time transaction monitoring via WebSocket, automatic reconnection on connection loss, transaction sending with metadata support, wallet information retrieval, metadata parsing for structured data, and event-driven architecture.

## Examples

```lua
local shopk = require("shopk")

local client = shopk({
 privatekey = "testing123", -- keep this safe!
})

client.on("transaction", function(tx)
 print(("%s -> %s : %.2f KRO"):format(tx.from, tx.to, tx.value))
 if tx.hasMeta("test") then -- checks if there is a standalone value of the string,
   -- i.e "unre=lated;test" would match but "unre=lated;test=ing" would not
   tx.refund(tx.value, "Refunding full amount for test metadata", function(data)
     if data.ok then
       print("Refund successful!")
     end
   end)
 end
end)

client.on("connected", function(isGuest, address)
 if isGuest then
   print("Connected! Logged in as guest.")
 else
   print(("Connected! Logged in as %s with %.2f KRO."):format(address.address, address.balance))
 end
end)

client.on("error", function(err)
 print("Error: " .. tostring(err))
end)

-- The client has errored or disconnected and is starting to reconnect
client.on("connecting", function()
 print("Connecting...")
end)

client.on("closed", function()
 print("Closed!")
end)

client.run()

```

## Functions

### `module.on(event, listener)`

Register an event listener Starting in 1.0.0, "ready" was renamed to "connected", and additional state management events have been added. "connected" now also calls with (isGuest: boolean, address: table?) when the connection is established.

**Parameters:**

- `event` ("transaction"|"connecting"|"connected"|"closed"|"error"): Event type to listen for.
- `listener` (function): Function to call when the event occurs.

### `module.run()`

Start the WebSocket connection and enter the main event loop This function blocks until the connection is closed

### `module.close()`

Close the WebSocket connection and stop reconnecting

### `module.me(cb?)`

Get information about the current wallet Starting in 1.0.0, this data is passed by the "connected" event for easy access

**Parameters:**

- `cb?` (function): Optional callback to receive wallet data

### `module.send(data, cb?)`

Send a Kromer transaction

**Parameters:**

- `data` (ShopkSendData): Transaction details
- `cb?` (function): Optional callback to receive transaction result

