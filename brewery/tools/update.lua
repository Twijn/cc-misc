local files = {
    ["/data/prices.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/brewery/data/prices.lua",
    ["/data/recipes.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/brewery/data/recipes.lua",
    ["/tools/check.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/brewery/tools/check.lua",
    ["/tools/update.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/brewery/tools/update.lua",
    ["/brewery.lua"] = "https://raw.githubusercontent.com/Twijn/cc-misc/refs/heads/main/brewery/brewery.lua",
}

fs.makeDir("/data")
fs.makeDir("/tools")

local function getFile(path, url)
    local resp, err = http.get(url)
    assert(resp ~= nil, string.format("Failed to get file %s: %s", path, err))
    local code = resp.readAll()
    assert(code ~= nil, "failed to parse response for path " .. path)
    resp.close()
    local f = fs.open(path, "w")
    f.write(code)
    f.close()
end

for filePath, fileUrl in pairs(files) do
    print("Getting file " .. filePath)
    getFile(filePath, fileUrl)
    print("Retrieved file " .. filePath)
end
