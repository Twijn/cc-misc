local libs = {
    ["lib/s.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/s.lua",
    ["lib/tables.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/tables.lua",
    ["lib/log.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/log.lua",
}

local args = {...}
local type = #args >= 1 and args[1]:lower() or ""

if type == "server" then
    libs["lib/shopk.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/util/shopk/shopk.lua"
elseif type == "aisle" then
    libs["aisle.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/signshop/aisle.lua"
else
    error("usage: update [server/aisle]")
end

local function err(message)
    term.setTextColor(colors.red)
    print(message)
    term.setTextColor(colors.white)
end

local function download(url, file)
    print(url .. " -> " .. file)
    local get, err = http.get(url)
    if get and get.getResponseCode() == 200 then
        local f = fs.open(file, "w")
        f.write(get.readAll())
        f.close()
        get.close()
        print("Downloaded successfully!")
    else
        error(err and err or "unknown error")
    end
end

fs.makeDir("lib")

for file, url in pairs(libs) do
    if fs.exists(file) then
        fs.delete(file)
    end
    download(url, file)
end
