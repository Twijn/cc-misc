local args = {...}

if #args < 0 or (args[1] ~= "server" and args[1] ~= "turtle" and args[1] ~= "breeder") then
    print("Improper usage: expected 'server' | 'turtle' | 'breeder'")
    return
end

-- LEGACY CODE for when tables was at root
fs.delete("tables.lua")

local time = os.epoch("utc")

local libs = {
    ["lib/s.lua"] = "wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/s.lua?v="..time,
    ["lib/tables.lua"] = "wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/tables.lua?v="..time,
    ["lib/timeutil.lua"] = "wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/timeutil.lua?v="..time,
    ["lib/breeder.lua"] = "wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/lib/breeder.lua?v="..time,
    ["lib/cropFarm.lua"] = "wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/lib/cropFarm.lua?v="..time,
    ["lib/monitor.lua"] = "wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/lib/monitor.lua?v="..time,
    ["lib/storage.lua"] = "wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/lib/storage.lua?v="..time,
}
local requiredLibs = {
    "lib/s.lua", "lib/tables.lua", "lib/timeutil.lua"
}

local function addLibs(...)
    local newLibs = { ... }
    for _, name in pairs(newLibs) do
        table.insert(requiredLibs, name)
    end
end

fs.makeDir("lib")

fs.delete("update.lua")
shell.run("wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/install.lua?v="..time.." update.lua")

if args[1] == "server" then
    fs.delete("farmServer.lua")
    shell.run("wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/farmServer.lua?v="..time)
    if not fs.exists("startup.lua") then
        local startup = fs.open("startup.lua", "w")
        startup.write('shell.run("farmServer")')
    end
    if not fs.exists("config.lua") then
        shell.run("wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/config.lua?v="..time)
    end
    addLibs("lib/breeder.lua", "lib/cropFarm.lua", "lib/monitor.lua", "lib/storage.lua")
elseif args[1] == "turtle" then
    fs.delete("startup.lua")
    shell.run("wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/client/farm.lua?v="..time.." startup.lua")
    if not settings.get("farm.id") then
        while true do
            print("Enter a numerical number to use for the turtle ID (1-99). Must be unique!")
            local id = tonumber(read())
            if id and id > 0 and id < 100 then
                settings.set("farm.id", math.floor(id))
                settings.save()
                print("ID set")
                break
            else
                print("Must be a number between 1 and 99!")
            end
        end
    end
elseif args[1] == "breeder" then
    fs.delete("startup.lua")
    shell.run("wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/client/breeder.lua?v="..time.." startup.lua")
end

for _, file in pairs(requiredLibs) do
    local wget = libs[file]
    if not wget then error("could not find required library " .. file) end
    fs.delete(file)
    shell.run(string.format("%s %s", wget, file))
end

os.reboot()
