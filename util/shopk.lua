-- shopk.lua --
--  v0.0.4   --
-- by Twijn  --

--- A Kromer cryptocurrency API client for ComputerCraft that provides real-time transaction
--- monitoring and wallet operations through WebSocket connections.
---
--- Features: Real-time transaction monitoring via WebSocket, automatic reconnection on connection loss,
--- transaction sending with metadata support, wallet information retrieval, metadata parsing for structured data,
--- and event-driven architecture.
---
---@usage
---local shopk = require("shopk")
---
---local client = shopk({ privatekey = "your_key" })
---
---client.on("ready", function()
---  print("Connected!")
---  client.me(function(data)
---    print("Balance:", data.balance)
---  end)
---end)
---
---client.on("transaction", function(tx)
---  print("Received:", tx.value, "from", tx.from)
---end)
---
---client.run()
---
---@version 0.0.4
-- @module shopk

local VERSION = "0.0.4"

---@class ShopkOptions
---@field syncNode? string The Kromer API endpoint URL (defaults to official endpoint)
---@field wsStart? string WebSocket start path (defaults to "ws/start")
---@field privatekey? string Private key for authenticated operations

---@class ShopkTransaction
---@field id number Transaction ID
---@field from string Sender address
---@field to string Recipient address
---@field value number Transaction amount
---@field time string Transaction timestamp
---@field name? string Transaction name
---@field metadata? string Raw metadata string
---@field meta ShopkMetadata Parsed metadata object

---@class ShopkMetadata
---@field keys table<string, string> Key-value pairs from metadata
---@field values string[] Bare values without keys

---@class ShopkSendData
---@field privatekey? string Private key (overrides options.privatekey)
---@field to string Recipient address
---@field amount number Amount to send
---@field metadata? string Transaction metadata

---@class ShopkModule
---@field _v string Version number
---@field on fun(event: "ready"|"transaction"|"transactions", listener: function): nil Register event listener
---@field run fun(): nil Start the WebSocket connection and event loop
---@field close fun(): nil Close the connection and stop reconnecting
---@field me fun(cb?: function): nil Get current wallet information
---@field send fun(data: ShopkSendData, cb?: function): nil Send a transaction

local v = "0.0.4"
local DEFAULT_SYNCNODE = "https://kromer.reconnected.cc/api/krist/"
local DEFAULT_WS_START = "ws/start"

---Create a new Shopk client instance for interacting with the Kromer network
---@param options? ShopkOptions Configuration options
---@return ShopkModule # New Shopk client instance
return function(options)
    if not options then options = {} end
    if not options.syncNode then
        options.syncNode = DEFAULT_SYNCNODE
    end
    if not options.wsStart then
        options.wsStart = DEFAULT_WS_START
    end

    local module = {
        _v = v,
    }

    local readyListeners = {}
    local transactionListeners = {}

    local replyHandlers = {}

    local reconnect = true
    local wsUri = nil
    local ws = nil
    local nextId = 1

    ---Establish WebSocket connection to the Kromer API
    local function connect()
        if ws then
            ws.close()
            ws = nil
        end

        local body = "{}"

        if options.privatekey then
            body = textutils.serializeJSON({
                privatekey = options.privatekey,
            })
        end

        local uri = options.syncNode .. options.wsStart
        local getWS, err = http.post(uri, body, {
            ["Content-Type"] = "application/json"
        })

        if not getWS or getWS.getResponseCode() ~= 200 then
            if not err then err = "Unknown Error" end
            error("Failed "..uri..": " .. err)
        end

        local data = textutils.unserializeJSON(getWS.readAll())
        wsUri = data.url

        if not wsUri then
            error("Unable to extract ws uri")
        end

        http.websocketAsync(wsUri)
    end

    ---Send a request through the WebSocket with optional callback
    ---@param data table Request data to send
    ---@param cb? function Optional callback for response
    local function request(data, cb)
        if not ws then
            error("WS has not been initialized yet! Make sure you try to send data after shopk.on(\"ready\") has been called.")
        end

        data.id = nextId
        ws.send(textutils.serializeJSON(data))
        if cb then
            replyHandlers[nextId] = cb
        end
        nextId = nextId + 1
    end

    ---Fire an event to all registered listeners
    ---@param event string Event name to fire
    ---@param ... any Arguments to pass to listeners
    local function fire(event, ...)
        local args = {...}
        local listeners = {}
        if event == "transaction" or event == "transactions" then
            listeners = transactionListeners
        elseif event == "ready" then
            listeners = readyListeners
        end
        for _, listener in pairs(listeners) do
            listener(table.unpack(args))
        end
    end

    ---Parse transaction metadata string into structured format
    ---@param str string Raw metadata string (semicolon-separated key=value pairs)
    ---@return ShopkMetadata # Parsed metadata with keys and values
    local function parseMetadata(str)
        local result = {
            keys = {},   -- key/value pairs
            values = {}  -- bare values (no '=')
        }

        for token in string.gmatch(str, "([^;]+)") do
            local key, value = token:match("([^=]+)=([^=]+)")
            if key and value then
                result.keys[key] = value
            else
                table.insert(result.values, token)
            end
        end

        return result
    end

    ---Register an event listener
    ---@param event "ready"|"transaction"|"transactions" Event type to listen for
    ---@param listener function Function to call when event occurs
    function module.on(event, listener)
        event = event:lower()
        if not reconnect then error("this shopk.lua instance has closed") end
        if event == "transaction" or event == "transactions" then
            table.insert(transactionListeners, listener)
        elseif event == "ready" then
            table.insert(readyListeners, listener)
        end
    end

    ---Start the WebSocket connection and enter the main event loop
    ---This function blocks until the connection is closed
    function module.run()
        connect()
        while reconnect do
            local e, url, msg = os.pullEvent()

            if url and url == wsUri then
                if e == "websocket_message" then
                    local data = textutils.unserializeJSON(msg)
                    if data then
                        if data.id then
                            if replyHandlers[data.id] then
                                replyHandlers[data.id](data)
                                replyHandlers[data.id] = nil
                            end
                        elseif data.type == "hello" then -- ws is ready
                            fire("ready")
                            request({
                                type = "subscribe",
                                event = "transactions"
                            })
                        elseif data.type == "event" and data.event == "transaction" then
                            local transaction = data.transaction
                            transaction.meta = parseMetadata(transaction.metadata or "")
                            fire("transaction", transaction)
                        end
                    end
                elseif e == "websocket_success" then
                    ws = msg
                elseif e == "websocket_failure" then
                    error(msg)
                elseif e == "websocket_closed" and reconnect then
                    connect()
                end
            end
        end
    end

    ---Close the WebSocket connection and stop reconnecting
    function module.close()
        reconnect = false
        if ws then
            ws.close()
            ws = nil
        end
    end

    ---Get information about the current wallet
    ---@param cb? function Optional callback to receive wallet data
    function module.me(cb)
        request({
            type = "me"
        }, cb)
    end

    ---Send a Kromer transaction
    ---@param data ShopkSendData Transaction details
    ---@param cb? function Optional callback to receive transaction result
    function module.send(data, cb)
        local privatekey = data.privatekey and data.privatekey or options.privatekey
        local to = data.to
        local amount = data.amount
        local metadata = data.metadata

        if not privatekey then
            error("You must either supply a private key when starting shopk.lua or in your #.send() request!")
        end

        assert(type(to) == "string", "You must supply a to address (string)!")
        assert(type(amount) == "number", "You must supply an amount (number)!")
        assert(type(metadata) == "nil" or type(metadata) == "string", "Metadata must be a string or nil!")

        request({
            type = "make_transaction",
            privatekey = privatekey,
            to = to,
            amount = amount,
            metadata = metadata
        }, cb)
    end

    return module
end
