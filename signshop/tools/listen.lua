--- SignShop Channel Listener ---
--- Monitors aisle communication channels and displays human-readable logs.

local BROADCAST_CHANNEL = 8698  -- Server -> Aisles
local RECEIVE_CHANNEL = 9698    -- Aisles -> Server

local modem = peripheral.find("modem")
if not modem then
    error("No modem found!")
end

modem.open(BROADCAST_CHANNEL)
modem.open(RECEIVE_CHANNEL)

local function timestamp()
    return os.date("%H:%M:%S")
end

local function formatMessage(channel, replyChannel, msg)
    local direction = channel == BROADCAST_CHANNEL and "SERVER->AISLE" or "AISLE->SERVER"
    local color = channel == BROADCAST_CHANNEL and colors.cyan or colors.lime
    
    term.setTextColor(colors.gray)
    write(string.format("[%s] ", timestamp()))
    term.setTextColor(color)
    write(string.format("[%s] ", direction))
    term.setTextColor(colors.white)
    
    if type(msg) ~= "table" then
        print(tostring(msg))
        return
    end
    
    local msgType = msg.type or "unknown"
    
    if msgType == "ping" then
        term.setTextColor(colors.yellow)
        print(string.format("PING (redstone=%s)", tostring(msg.redstone)))
    elseif msgType == "pong" then
        term.setTextColor(colors.green)
        print(string.format("PONG from '%s' (peripheral: %s)", msg.aisle or "?", msg.self or "?"))
    else
        term.setTextColor(colors.orange)
        print(string.format("MSG type=%s", msgType))
        for k, v in pairs(msg) do
            if k ~= "type" then
                term.setTextColor(colors.lightGray)
                print(string.format("  %s: %s", k, textutils.serialize(v):gsub("\n", " ")))
            end
        end
    end
    
    term.setTextColor(colors.white)
end

print("=== SignShop Channel Listener ===")
print(string.format("Listening on channels %d (broadcast) and %d (receive)", BROADCAST_CHANNEL, RECEIVE_CHANNEL))
print("Press Ctrl+T to stop\n")

while true do
    local event, side, channel, replyChannel, msg = os.pullEvent("modem_message")
    formatMessage(channel, replyChannel, msg)
end
