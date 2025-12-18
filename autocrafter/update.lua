--- AutoCrafter Update Script
--- Updates all AutoCrafter components from the repository.
--- Config values are preserved during update.
---
---@version 1.1.0

local BASE_URL = "https://raw.githubusercontent.com/Twijn/cc-misc/main"

print("================================")
print("  AutoCrafter Updater")
print("================================")
print("")

-- Run the installer (it will auto-detect server vs crafter)
local installerPath = "/.autocrafter_update_temp.lua"
fs.delete(installerPath)

local installerUrl = BASE_URL .. "/autocrafter/install.lua"
shell.run("wget", installerUrl, installerPath)

if fs.exists(installerPath) then
    shell.run(installerPath)
    fs.delete(installerPath)
else
    term.setTextColor(colors.red)
    print("ERROR: Failed to download updater")
    term.setTextColor(colors.white)
end
