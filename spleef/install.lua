local args = {...}

assert(#args > 0 and (args[1] == "server" or args[1] == "snowmaker"), "usage: install <server/snowmaker>")

fs.makeDir("lib")

local files = {
    -- Global files
    ["lib/s.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/s.lua",
    ["lib/tables.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/tables.lua",
    ["lib/persist.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/persist.lua",
    ["update.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/spleef/install.lua",
    -- Server files
    ["lib/snowmakercomms.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/spleef/server/lib/snowmakercomms.lua",
    ["tools/buildPlatform.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/spleef/server/tools/buildPlatform.lua",
    ["tools/scannerTest.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/spleef/server/tools/scannerTest.lua",
    -- Snowmaker files
    ["snowmaker.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/spleef/snowmaker/snowmaker.lua"
}
local installFiles = {
    "lib/s.lua", "lib/tables.lua", "lib/persist.lua", "update.lua"
}

if fs.exists("lib/config.lua") then
    fs.delete("lib/config.lua")
end

shell.run(string.format("wget https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/spleef/%s/lib/config.lua lib/config.lua", args[1]))

if args[1] == "server" then
    table.insert(installFiles, "lib/snowmakercomms.lua")
    table.insert(installFiles, "tools/buildPlatform.lua")
    table.insert(installFiles, "tools/scannerTest.lua")
elseif args[1] == "snowmaker" then
    table.insert(installFiles, "snowmaker.lua")
end

for _, fileName in pairs(installFiles) do
    local url = files[fileName]
    assert(url ~= nil, "unknown file name: " .. fileName)
    if fs.exists(fileName) then
        fs.delete(fileName)
    end
    shell.run("wget", url, fileName)
end

os.reboot()
