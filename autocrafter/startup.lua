--- AutoCrafter Unified Startup Script
--- Detects the machine type and runs the appropriate program.
--- Supports: server, crafter, or falls back to local startup.lua for unassociated machines.
---
---@version 2.0.0

local VERSION = "2.0.0"
local diskPrefix = fs.exists("disk") and "disk/" or ""

-- Add lib to package path
if not package.path:find(diskPrefix .. "lib") then
    package.path = package.path .. ";" .. diskPrefix .. "?.lua;" .. diskPrefix .. "lib/?.lua"
end

local isTurtle = turtle ~= nil

-- Config is stored LOCALLY on each computer, not on the shared disk
-- This allows each machine to have its own role
local configPath = "autocrafter-config.json"

---Load client configuration
---@return table config The client configuration
local function loadConfig()
    if not fs.exists(configPath) then
        return {
            role = nil,
            hideSetup = false,
            serverId = nil,
        }
    end
    
    local file = fs.open(configPath, "r")
    local content = file.readAll()
    file.close()
    
    local success, data = pcall(textutils.unserializeJSON, content)
    if success and data then
        return data
    end
    
    return {
        role = nil,
        hideSetup = false,
        serverId = nil,
    }
end

---Save client configuration
---@param cfg table The configuration to save
local function saveConfig(cfg)
    local file = fs.open(configPath, "w")
    file.write(textutils.serializeJSON(cfg))
    file.close()
end

---Query for an active server on the network
---@return table|nil serverInfo Server information if found
local function findServer()
    -- Try to load comms library
    local success, comms = pcall(require, "lib.comms")
    if not success then
        return nil
    end
    
    -- Try to load config
    local configSuccess, config = pcall(require, "config")
    if not configSuccess then
        return nil
    end
    
    -- Initialize modem
    if not comms.init(false) then
        return nil
    end
    
    comms.setChannel(config.modemChannel)
    
    -- Broadcast server query
    comms.broadcast(config.messageTypes.SERVER_QUERY, {
        queryId = os.getComputerID(),
    })
    
    -- Wait for response (2 second timeout)
    local timeout = os.clock() + 2
    while os.clock() < timeout do
        local message = comms.receive(0.5)
        if message and message.type == config.messageTypes.SERVER_ANNOUNCE then
            comms.close()
            return message.data
        end
    end
    
    comms.close()
    return nil
end

---Display the setup menu
---@return string|nil choice The user's choice
local function showSetupMenu()
    term.clear()
    term.setCursorPos(1, 1)
    
    print("================================")
    print("   AutoCrafter Setup v" .. VERSION)
    print("================================")
    print("")
    
    -- Check for server on network
    print("Checking for server on network...")
    local serverInfo = findServer()
    
    if serverInfo then
        term.setTextColor(colors.lime)
        print("")
        print("Found server: " .. (serverInfo.serverLabel or "Unknown"))
        print("  ID: " .. (serverInfo.serverId or "?"))
        print("  Version: " .. (serverInfo.version or "?"))
        term.setTextColor(colors.white)
    else
        term.setTextColor(colors.yellow)
        print("")
        print("No server found on network.")
        term.setTextColor(colors.white)
    end
    
    print("")
    print("What would you like to do?")
    print("")
    
    if isTurtle then
        print("[1] Set up as Crafter Turtle")
        print("[2] Exit")
        print("[3] Exit and don't show again")
    else
        print("[1] Set up as Server")
        print("[2] Set up as Crafter (computer-based)")
        print("[3] Exit")
        print("[4] Exit and don't show again")
    end
    
    print("")
    write("Choice: ")
    
    local input = read()
    local choice = tonumber(input)
    
    if isTurtle then
        if choice == 1 then
            return "crafter"
        elseif choice == 2 then
            return "exit"
        elseif choice == 3 then
            return "exit_hide"
        end
    else
        if choice == 1 then
            return "server"
        elseif choice == 2 then
            return "crafter"
        elseif choice == 3 then
            return "exit"
        elseif choice == 4 then
            return "exit_hide"
        end
    end
    
    return nil
end

---Main startup logic
local function main()
    local clientConfig = loadConfig()
    
    -- Debug: show what we loaded
    -- print("DEBUG: configPath = " .. configPath)
    -- print("DEBUG: role = " .. tostring(clientConfig.role))
    
    -- Determine the role from local config
    local role = clientConfig.role
    
    -- Verify files exist for the role (on disk or local)
    if role == "server" and not fs.exists(diskPrefix .. "server.lua") then
        role = nil
    elseif role == "crafter" and not fs.exists(diskPrefix .. "crafter.lua") then
        role = nil
    end
    
    -- Execute based on role
    if role == "server" then
        -- Server: run as background tab, then run any local startup.lua
        print("Starting AutoCrafter Server...")
        
        if term.isColor and term.isColor() then
            -- Has multishell, run server in new tab
            local serverPath = diskPrefix .. "server"
            shell.openTab(serverPath)
            
            -- If there's a local startup.lua (not on disk), run it
            if fs.exists("startup.lua") and diskPrefix ~= "" then
                sleep(0.5)
                shell.run("startup.lua")
            end
        else
            -- No multishell, just run server directly
            shell.run(diskPrefix .. "server")
        end
        
    elseif role == "crafter" then
        -- Crafter: run crafter program (no local startup.lua)
        print("Starting AutoCrafter Crafter...")
        shell.run(diskPrefix .. "crafter")
        
    else
        -- Unknown role - need to configure
        
        -- Check if setup should be hidden
        if clientConfig.hideSetup then
            -- Just run local startup.lua if it exists (and we're on disk)
            if diskPrefix ~= "" and fs.exists("startup.lua") then
                shell.run("startup.lua")
            end
            return
        end
        
        -- Show setup menu (don't skip to local startup - we need configuration!)
        local choice = showSetupMenu()
        
        if choice == "server" then
            clientConfig.role = "server"
            saveConfig(clientConfig)
            print("")
            print("Configured as server. Rebooting...")
            sleep(1)
            os.reboot()
            
        elseif choice == "crafter" then
            clientConfig.role = "crafter"
            saveConfig(clientConfig)
            print("")
            print("Configured as crafter. Rebooting...")
            sleep(1)
            os.reboot()
            
        elseif choice == "exit_hide" then
            clientConfig.hideSetup = true
            saveConfig(clientConfig)
            print("")
            print("Setup will not show again.")
            print("To reset, delete: " .. configPath)
            
        elseif choice == "exit" then
            print("")
            print("Exiting setup.")
        else
            print("")
            print("Invalid choice. Exiting.")
        end
    end
end

main()
