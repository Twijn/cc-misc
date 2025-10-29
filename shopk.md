# shopk

A Kromer cryptocurrency API client for ComputerCraft that provides real-time transaction monitoring and wallet operations through WebSocket connections. Features: Real-time transaction monitoring via WebSocket, automatic reconnection on connection loss, transaction sending with metadata support, wallet information retrieval, metadata parsing for structured data, and event-driven architecture.

## Functions

### `module.on(event, listener)`

Register an event listener

**Parameters:**

- `event` ("ready"|"transaction"|"transactions"): Event type to listen for
- `listener` (function): Function to call when event occurs

### `module.run()`

Start the WebSocket connection and enter the main event loop This function blocks until the connection is closed

### `module.close()`

Close the WebSocket connection and stop reconnecting

### `module.me(cb?)`

Get information about the current wallet

**Parameters:**

- `cb?` (function): Optional callback to receive wallet data

### `module.send(data, cb?)`

Send a Kromer transaction

**Parameters:**

- `data` (ShopkSendData): Transaction details
- `cb?` (function): Optional callback to receive transaction result

