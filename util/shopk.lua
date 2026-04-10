-- shopk.lua --
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
---local client = shopk({
---  privatekey = "testing123", -- keep this safe!
---})
---
---client.on("transaction", function(tx)
---  --if tx.to ~= client.address.address then return end -- uncomment to only process incoming transactions to the connected wallet
---  print(("%s -> %s : %.2f KRO"):format(tx.from, tx.to, tx.value))
---  if tx.hasMeta("test") then -- checks if there is a standalone value of the string,
---    -- i.e "unre=lated;test" would match but "unre=lated;test=ing" would not
---    tx.refund(tx.value, "Refunding full amount for test metadata", function(data)
---      if data.ok then
---        print("Refund successful!")
---      end
---    end)
---  end
---end)
---
---client.on("connected", function(isGuest, address)
---  if isGuest then
---    print("Connected! Logged in as guest.")
---  else
---    print(("Connected! Logged in as %s with %.2f KRO."):format(address.address, address.balance))
---  end
---end)
---
---client.on("error", function(err)
---  print(("Error [%s]: %s"):format(err.error, err.message))
---end)
---
----- The client has errored or disconnected and is starting to reconnect
---client.on("connecting", function()
---  print("Connecting...")
---end)
---
---client.on("closed", function()
---  print("Closed!")
---end)
---
---client.run()
---
---@version 1.0.3
-- @module shopk

local VERSION = "1.0.3"

---@class ShopkOptions
---@field syncNode? string The Kromer API endpoint URL (defaults to official endpoint)
---@field wsStart? string WebSocket start path (defaults to "ws/start")
---@field privatekey? string Private key for authenticated operations
---@field reconnectDelay? number Seconds to wait before reconnecting after an error (defaults to 30)
---@field sendDuration? number Time window in seconds for rate limiting sends (defaults to 60)
---@field sendLimit? number Maximum number of sends allowed within the sendDuration window (defaults to 20)
---@field onlyOwnTransactions? boolean If true, only receive transactions involving the authenticated wallet (requires privatekey)
---@field refundMessageTypeDefault? "message"|"msg"|"error"|"success" Default metadata key used by `tx.refund(...)` when messageType is omitted

---@class ShopkTransaction
---@field id number Transaction ID
---@field from string Sender address
---@field to string Recipient address
---@field value number Transaction amount
---@field time string Transaction timestamp
---@field name? string Transaction name
---@field metadata? string Raw metadata string
---@field meta ShopkMetadata Parsed metadata object
---@field refunded number Amount that has been refunded so far
---@field refund fun(amountOrData: number|ShopkRefundData, message?: string, cb?: function, messageType?: string): nil Refund using positional args or a table `{ amount, message, cb, messageType }`; calls cb with the result of the refund transaction
---@field hasMeta fun(meta: string, caseSensitive: boolean): boolean Check if the transaction metadata contains a specific standalone value (not part of a key=value pair), with optional case sensitivity (defaults to false)

---@class ShopkRefundData
---@field amount number Amount to refund
---@field message? string Refund message text
---@field cb? function Callback for refund result
---@field messageType? "message"|"msg"|"error"|"success" Metadata key for refund message (defaults to "message")

---@class ShopkMetadata
---@field keys table<string, string> Key-value pairs from metadata
---@field values string[] Bare values without keys

---@class ShopkSendData
---@field privatekey? string Private key (overrides options.privatekey)
---@field to string Recipient address
---@field amount number Amount to send
---@field metadata? string Transaction metadata

---@class ShopkAddress
---@field address string Wallet address
---@field balance number Wallet balance

---@class ShopkMeResponse
---@field is_guest boolean Whether this connection is guest-authenticated
---@field address ShopkAddress? Wallet details when authenticated

---@class ShopkError
---@field error string Machine-readable error code
---@field message string Human-readable error message

---@class ShopkModule
---@field _v string Version number
---@field state "connecting"|"connected"|"closed"|"error" The state of the websocket
---@field stateMessage string The human-readable message for the state of the websocket.
---@field lastError ShopkError? The last error recorded by shopk.
---@field isGuest boolean Whether the connection is authenticated; false when a valid privatekey is used
---@field address ShopkAddress? The authenticated wallet details, or nil if guest
---@field on fun(event: "connecting"|"connected"|"closed"|"error"|"transaction", listener: function): nil Register event listener. The "ready" listener receives (isGuest: boolean, address: string?); the "error" listener receives (err: ShopkError); "transaction" receives (tx: ShopkTransaction)
---@field run fun(): nil Start the WebSocket connection and event loop
---@field close fun(): nil Close the connection and stop reconnecting
---@field me fun(cb?: function): nil Get current wallet information
---@field send fun(data: ShopkSendData, cb?: function): nil Send a transaction
---@field addCheck fun(name: string, checkFn: function): nil Add a custom refund check function that runs before processing refunds
---@field removeCheck fun(name: string): nil Remove a previously added refund check by name

local DEFAULT_OPTIONS = {
    syncNode = "https://kromer.reconnected.cc/api/krist/",
    wsStart = "ws/start",
    reconnectDelay = 30,
    sendDuration = 60,
    sendLimit = 20,
    refundMessageTypeDefault = "message",
    onlyOwnTransactions = false,
}

local ALLOWED_REFUND_MESSAGE_TYPES = {
    message = true,
    msg = true,
    error = true,
    success = true,
}

local function limiter(duration, limit)
    duration = duration * 1000
    local module = {
        history = {},
        duration = duration,
        limit = limit,
    }

    function module:clean()
        local newHistory = {}
        local now = os.epoch("utc")

        for _, v in pairs(self.history) do
            if now <= v + duration then
                table.insert(newHistory, v)
            end
        end

        self.history = newHistory
    end

    function module:hit()
        self:clean()
        if #self.history >= self.limit then
            return false, "Limit exceeded"
        end
        table.insert(self.history, os.epoch("utc"))
        return true
    end

    function module:get()
        self:clean()
        return #self.history
    end

    return module
end

local function applyDefaults(options, defaults)
    for k, v in pairs(defaults) do
        if options[k] == nil then
            options[k] = v
        end
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

---@param code string
---@param message string
---@return ShopkError
local function createError(code, message)
    return {
        error = code,
        message = message,
    }
end

---@param err any
---@param defaultCode string
---@param defaultMessage? string
---@return ShopkError
local function normalizeError(err, defaultCode, defaultMessage)
    if type(err) == "table" then
        local errorCode = err.error or defaultCode
        local message = err.message or defaultMessage or tostring(err.error or "Unknown error")
        return createError(errorCode, message)
    end

    if err == nil then
        return createError(defaultCode, defaultMessage or "Unknown error")
    end

    return createError(defaultCode, tostring(err))
end

---Create a new Shopk client instance for interacting with the Kromer network
---@param options? ShopkOptions Configuration options
---@return ShopkModule # New Shopk client instance
return function(options)
    options = options or {}
    applyDefaults(options, DEFAULT_OPTIONS)

    assert(type(options.refundMessageTypeDefault) == "string", "refundMessageTypeDefault must be a string")
    local defaultRefundMessageType = options.refundMessageTypeDefault:lower()
    assert(
        ALLOWED_REFUND_MESSAGE_TYPES[defaultRefundMessageType],
        "refundMessageTypeDefault must be one of: message, msg, error, success"
    )

    if options.syncNode and options.syncNode:sub(-1) ~= "/" then
        options.syncNode = options.syncNode .. "/"
    end

    ---@type ShopkModule
    local module = {
        _v = VERSION,
        _sendLimiter = limiter(
            options.sendDuration,
            options.sendLimit
        ),
        _refundChecks = {
            -- These checks are performed before attempting a refund to prevent unnecessary transactions and potential abuse. They can be customized or extended as needed.
            {
                name = "Positive Amount",
                check = function(transaction, amount)
                    return amount > 0, "Refund amount must be greater than zero"
                end
            },
            {
                name = "No Message/Errors in Original Transaction",
                check = function(transaction)
                    if transaction.meta.msg or transaction.meta.message or transaction.meta.error then
                        return false, "Refunds are not allowed for transactions with message or error metadata"
                    end
                    return true
                end
            },
            {
                name = "Transaction does not reference another transaction",
                check = function(transaction)
                    if transaction.meta.ref then
                        return false, "Refunds are not allowed for transactions that reference another transaction"
                    end
                    return true
                end
            },
            {
                name = "Refund Amount Does Not Exceed Remaining Value",
                check = function(transaction, amount)
                    if transaction.refunded + amount > transaction.value then
                        return false, "Refund amount exceeds remaining transaction value"
                    end
                    return true
                end
            },
        },
        state = "connecting",
        stateMessage = "Connecting",
        isGuest = true,
        address = nil,
        on = function() end,
        run = function() end,
        close = function() end,
        me = function() end,
        send = function() end,
        addCheck = function() end,
        removeCheck = function() end,
    }

    local listeners = {
        transaction = {},
        connecting = {},
        connected = {}, -- ready
        closed = {},
        error = {},
    }

    local replyHandlers = {}

    local wsUri
    ---@type any?
    local ws = nil
    local nextId = 1

    ---Fire an event to all registered listeners
    ---@param event string Event name to fire
    ---@param ... any Arguments to pass to listeners
    local function fire(event, ...)
        local args = {...}
        local l = listeners[event]
        if not l then
            error(("event %s not found"):format(event))
        end
        for _, listener in pairs(l) do
            listener(table.unpack(args))
        end
    end

    local function sanitizeMetadataValue(value)
        -- Remove metadata separators to prevent key/value injection via message content.
        return value:gsub("[;=]", "")
    end

    local function wrapTransaction(transaction)
        transaction.meta = parseMetadata(transaction.metadata or "")
        transaction.refunded = 0

        transaction.refund = function(amountOrData, message, cb, messageType)
            local amount = amountOrData
            if type(amountOrData) == "table" then
                amount = amountOrData.amount
                message = amountOrData.message
                cb = amountOrData.cb
                messageType = amountOrData.messageType
            end

            assert(type(amount) == "number", "Refund amount must be a number")
            assert(type(message) == "nil" or type(message) == "string", "Refund message must be a string or nil")
            assert(type(messageType) == "nil" or type(messageType) == "string", "Refund messageType must be a string or nil")

            local function cbErr(err, code)
                if cb then cb(normalizeError(err, code or "refund_failed")) end
            end

            local normalizedMessageType = (messageType or defaultRefundMessageType):lower()
            if not ALLOWED_REFUND_MESSAGE_TYPES[normalizedMessageType] then
                cbErr(
                    "Refund messageType must be one of: message, msg, error, success",
                    "invalid_refund_message_type"
                )
                return
            end

            local sanitizedMessage = sanitizeMetadataValue(message or "")

            -- Run refund checks
            for _, v in pairs(module._refundChecks) do
                local ok, err = v.check(transaction, amount)
                if not ok then
                    cbErr(err, "refund_check_failed")
                    return
                end
            end

            -- Optimistically update refunded to prevent race conditions
            transaction.refunded = transaction.refunded + amount

            module.send({
                to = transaction.from,
                amount = amount,
                metadata = ("ref=%d;type=refund;original=%.5f;%s=%s"):format(transaction.id, transaction.value, normalizedMessageType, sanitizedMessage)
            }, function(data)
                if not data.ok then
                    -- Rollback on failure
                    transaction.refunded = transaction.refunded - amount
                end
                if cb then cb(data) end
            end)
        end

        transaction.hasMeta = function(meta, caseSensitive)
            for _, v in pairs(transaction.meta.values) do
                if (caseSensitive and v == meta) or (not caseSensitive and v:lower() == meta:lower()) then
                    return true
                end
            end
            return false
        end
    end

    local function setState(state, stateError)
        module.state = state
        if state == "connecting" then
            module.stateMessage = "Connecting"
        elseif state == "connected" then
            module.stateMessage = "Connected"
        elseif state == "closed" then
            module.stateMessage = "Closed"
        elseif state == "error" then
            module.stateMessage = "Error"
        end
        local normalizedStateError = nil
        if stateError then
            normalizedStateError = normalizeError(stateError, "unknown_error")
            module.lastError = normalizedStateError
        end

        if state == "connected" then
            module.me(function(data)
                fire(state, data.is_guest, data.address)
            end)
        else
            fire(state, normalizedStateError)
        end
    end

    ---Establish WebSocket connection to the Kromer API
    local function internalConnect()
        if ws then
            ws.close()
            ws = nil
        end

        setState("connecting")

        local body = "{}"

        if options.privatekey then
            body = textutils.serializeJSON({
                privatekey = options.privatekey,
            })
        end

        local uri = options.syncNode .. options.wsStart
        local getWS, err = http.post(uri, body, {
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "shopk.lua/" .. VERSION,
        })

        if not getWS or getWS.getResponseCode() ~= 200 then
            if not err then err = "Unknown Error" end
            error(createError("websocket_start_failed", "Failed " .. uri .. ": " .. tostring(err)))
        end

        local data = textutils.unserializeJSON(getWS.readAll())
        wsUri = data.url

        if not wsUri then
            error(createError("invalid_websocket_start_response", "Unable to extract ws uri"))
        end

        http.websocketAsync(wsUri)
    end

    local function connect()
        local ok, err = pcall(internalConnect)
        if not ok then
            setState("error", normalizeError(err, "connection_failed"))
        end
    end

    ---Send a request through the WebSocket with optional callback
    ---@param data table Request data to send
    ---@param cb? function Optional callback for response
    local function request(data, cb)
        if not ws then
            error("WS has not been initialized yet! Make sure you try to send data after shopk.on(\"connected\") has been called.")
        end

        data.id = nextId
        ws.send(textutils.serializeJSON(data))
        if cb then
            replyHandlers[nextId] = cb
        end
        nextId = nextId + 1
    end

    ---Register an event listener
    ---Starting in 1.0.1, "ready" was renamed to "connected", and additional state management events have been added.
    ---"connected" now also calls with (isGuest: boolean, address: table?) when the connection is established.
    ---@param event string Event type to listen for.
    ---@param listener function Function to call when the event occurs.
    function module.on(event, listener)
        if module.state == "closed" then error("This shopk.lua instance has closed") end
        event = event:lower()
        if event == "transactions" then event = "transaction" end
        if event == "ready" then event = "connected" end

        if listeners[event] then
            table.insert(listeners[event], listener)
        end
    end

    ---Start the WebSocket connection and enter the main event loop
    ---This function blocks until the connection is closed
    function module.run()
        connect()
        while module.state ~= "closed" do
            local e, url, msg = os.pullEvent()

            if url and url == wsUri then
                if e == "websocket_message" then
                    local data = textutils.unserializeJSON(msg)
                    if data then
                        if data.error and data.message and data.ok == nil then
                            data.ok = false
                        end
                        if data.id then
                            if replyHandlers[data.id] then
                                replyHandlers[data.id](data)
                                replyHandlers[data.id] = nil
                            end
                        elseif data.type == "hello" then -- ws is ready
                            setState("connected")
                            request({
                                type = "subscribe",
                                event = (options.onlyOwnTransactions and options.privatekey) and "ownTransactions" or "transactions"
                            })
                        elseif data.type == "event" and data.event == "transaction" then
                            local transaction = data.transaction
                            wrapTransaction(transaction)
                            fire("transaction", transaction)
                        end
                    end
                elseif e == "websocket_success" then
                    ws = msg
                elseif e == "websocket_failure" then
                    setState("error", createError("websocket_connection_failed", "WebSocket connection failed: " .. tostring(msg)))
                    ws = nil
                elseif e == "websocket_closed" and module.state ~= "closed" then
                    -- this could be the server closing the connection or a network error, so we should attempt to reconnect after a delay
                    setState("error", createError("websocket_closed", "WebSocket connection closed"))
                    ws = nil
                end
            end

            if not ws and module.state == "error" then
                sleep(options.reconnectDelay)
                connect()
            end
        end
    end

    ---Close the WebSocket connection and stop reconnecting
    function module.close()
        setState("closed")
        if ws then
            ws.close()
            ws = nil
        end
    end

    ---@type ShopkMeResponse?
    local meResponse = nil
    ---Get information about the current wallet
    ---Starting in 1.0.1, this data is passed by the "connected" event for easy access
    ---@param cb? function Optional callback to receive wallet data
    function module.me(cb)
        if meResponse then
            if cb then cb(meResponse) end
            return
        end
        request({
            type = "me"
        }, function(data)
            meResponse = data
            module.isGuest = data.is_guest
            module.address = data.address
            if cb then cb(data) end
        end)
    end

    ---Send a Kromer transaction
    ---@param data ShopkSendData Transaction details
    ---@param cb? function Optional callback to receive transaction result
    function module.send(data, cb)
        -- rate limit transaction events to prevent potential infinite loops or spam from the server
        if not module._sendLimiter:hit() then
            if cb then
                cb(createError("rate_limit_exceeded", "Rate limit exceeded for outgoing transactions"))
            end
            return
        end

        local privatekey = data.privatekey and data.privatekey or options.privatekey
        local to = data.to
        local amount = data.amount
        local metadata = data.metadata

        if not privatekey then
            error("You must either supply a privatekey when starting shopk.lua or in your #.send() request!")
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

    ---Add a custom check function that runs before processing a refund. This can be used to implement additional safeguards or restrictions on refunds, such as checking against an external database or applying custom business logic. The check function should return `true` if the refund is allowed, or `false` and an error message if it should be blocked.
    ---@param name string A unique name for the check (used for management and debugging)
    ---@param checkFn function A function that takes a transaction and refund amount as arguments and returns `true` if the refund is allowed, or `false` and an error message if it should be blocked
    function module.addCheck(name, checkFn)
        table.insert(module._refundChecks, {
            name = name,
            check = checkFn,
        })
    end

    ---Remove a previously added refund check by name
    ---@param name string The name of the check to remove
    function module.removeCheck(name)
        for i, v in pairs(module._refundChecks) do
            if v.name == name then
                table.remove(module._refundChecks, i)
                return
            end
        end
    end

    return module
end
