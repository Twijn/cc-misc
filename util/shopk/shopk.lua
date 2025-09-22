-- shopk.lua --
--  v0.0.1   --
-- by Twijn  --

local v = "0.0.1"
local DEFAULT_SYNCNODE = "https://kromer.reconnected.cc/api/krist/"
local DEFAULT_WS_START = "ws/start"

return function(options)
    if not options then options = {} end
    if not options.syncNode then
        options.syncNode = DEFAULT_SYNCNODE
    end
    if not options.wsStart then
        options.wsStart = DEFAULT_WS_START
    end

    local module = {}

    local readyListeners = {}
    local transactionListeners = {}

    local replyHandlers = {}

    local reconnect = true
    local wsUri = nil
    local ws = nil
    local nextId = 1

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
        local getWS, err = http.post(uri, body)

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

    local function request(data, cb)
        data.id = nextId
        ws.send(textutils.serializeJSON(data))
        if cb then
            replyHandlers[nextId] = cb
        end
        nextId = nextId + 1
    end

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

    function module.on(event, listener)
        event = event:lower()
        if not reconnect then error("this shopk.lua instance has closed") end
        if event == "transaction" or event == "transactions" then
            table.insert(transactionListeners, listener)
        elseif event == "ready" then
            table.insert(readyListeners, listener)
        end
    end

    function module.run()
        connect()
        while true do
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

    function module.close()
        reconnect = false
        if ws then
            ws.close()
            ws = nil
        end
    end

    function module.send(data, cb)
        if not ws then
            error("WS has not been initialized yet! Make sure you try to send data after shopk.on(\"ready\") has been called.")
        end

        local privatekey = data.privatekey and data.privatekey or options.privatekey
        local to = data.to
        local amount = data.amount
        local metadata = data.metadata

        if not privatekey then
            error("You must either supply a private key when starting shopk.lua or in your #.send() request!")
        end

        if type(to) ~= "string" then error("You must supply a to address (string)!") end
        if type(amount) ~= "number" then error("You must supply an amount (number)!") end
        if type(metadata) ~= "nil" and type(metadata) ~= "string" then error("Metadata must be a string or nil!") end

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
