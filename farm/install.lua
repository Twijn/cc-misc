local args = {...}

if #args < 0 or (args[1] ~= "server" and args[1] ~= "turtle") then
    print("Improper usage: expected 'server' or 'turtle'")
    return
end

fs.delete("tables.lua")
fs.delete("update.lua")
shell.run("wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/tables.lua")
shell.run("wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/install.lua update.lua")

if args[1] == "server" then
    fs.delete("farmServer.lua")
    shell.run("wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/farmServer.lua")
    if not fs.exists("startup.lua") then
        local startup = fs.open("startup.lua", "w")
        startup.write('shell.run("farmServer")')
    end
else
    fs.delete("startup.lua")
    shell.run("wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/farm/farm.lua startup.lua")
    if not settings.get("farm.id") then
        while true do
            print("Enter a numerical number to use for the turtle ID (1-99). Must be unique!")
            local id = tonumber(read())
            if id and id > 0 and id < 100 then
                settings.set("farm.id", math.floor(id))
                settings.save()
                print("ID set")
            else
                print("Must be a number between 1 and 99!")
            end
        end
    end
end
os.reboot()
