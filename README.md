# CC-Misc Utilities

> Yes, a lot of the docs here are AI generated. Sorry.

**The missing standard library for ComputerCraft: Tweaked**

A professional collection of utility modules for ComputerCraft that makes building complex programs easier, cleaner, and more maintainable.

[![Documentation](https://img.shields.io/badge/docs-ccmisc.twijn.dev-blue)](https://ccmisc.twijn.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CC: Tweaked](https://img.shields.io/badge/CC%3A%20Tweaked-compatible-green)](https://tweaked.cc/)

---

## Quick Start

Install any library with a single command:

```lua
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installer.lua
```

This launches an interactive installer where you can:
- ✨ Browse all available libraries
- 📖 View detailed information (press RIGHT arrow)
- 🔗 Automatically resolve dependencies
- 📦 Install to your computer

Or install specific libraries directly:

```lua
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installer.lua formui persist log
```

---

## Core Libraries

### 🎨 [FormUI](https://ccmisc.twijn.dev/formui.html) - Interactive Form Builder
*Stop wrestling with terminal I/O - create beautiful UIs in seconds*

```lua
local FormUI = require("formui")
local form = FormUI.new("Server Config")

local nameField = form:text("Server Name", "MyServer")
local portField = form:number("Port", 8080)
local enabledField = form:checkbox("Enabled", true)
local modemField = form:peripheral("Modem", "modem")

form:addSubmitCancel()
local result = form:run()
```

**Features:** Text/number/select fields, checkboxes, multi-select, lists, validation, peripheral detection, keyboard navigation

---

### 💾 [Persist](https://ccmisc.twijn.dev/persist.html) - Data Persistence
*Save and load data with zero boilerplate*

```lua
local persist = require("persist")
local config = persist("config.json")

config.setDefault("port", 8080)
config.set("name", "MyServer")
print(config.get("port")) -- 8080
```

**Features:** JSON/Lua serialization, auto-save, deep copy, automatic file creation

---

### 📝 [Log](https://ccmisc.twijn.dev/log.html) - Logging System
*Professional logging with color-coded output and daily rotation*

```lua
local log = require("log")

log.info("Server started")
log.warn("High memory usage")
log.error("Connection failed")
```

**Features:** Color-coded console output, daily log files, timestamped entries

---

### ⏱️ [TimeUtil](https://ccmisc.twijn.dev/timeutil.html) - Interval Management
*Run tasks on schedules that persist across reboots*

```lua
local timeutil = require("timeutil")

timeutil.every(function()
  print("Running backup...")
end, 600, "backup_last_run")

timeutil.run()
```

**Features:** Absolute and runtime-based intervals, persistent state, pretty formatting

---

### 🔧 [Tables](https://ccmisc.twijn.dev/tables.html) - Table Utilities
*Common table operations you always end up reimplementing*

```lua
local tables = require("tables")

tables.includes(myTable, value)
tables.recursiveCopy(myTable)
tables.recursiveEquals(table1, table2)
```

---

### ⚙️ [Settings (s)](https://ccmisc.twijn.dev/s.html) - Interactive Settings
*User-friendly configuration with validation and peripheral detection*

```lua
local s = require("s")

local modem = s.peripheral("modem", "modem", true)
local port = s.number("port", 1, 65535, 8080)
local name = s.string("server_name", "MyServer")
```

---

### 🖥️ [CMD](https://ccmisc.twijn.dev/cmd.html) - Command Interface
*Build REPL-style command processors with history and autocompletion*

```lua
local cmd = require("cmd")

local commands = {
  hello = {
    description = "Say hello",
    execute = function(args, context)
      context.succ("Hello, " .. (args[1] or "World") .. "!")
    end
  }
}

cmd("MyApp", "1.0.0", commands)
```

---

### 💰 [ShopK](https://ccmisc.twijn.dev/shopk.html) - Kromer API Client
*WebSocket client for Kromer cryptocurrency integration*

```lua
local shopk = require("shopk")
local client = shopk({ privatekey = "your_key" })

client.on("transaction", function(tx)
  print("Received:", tx.value)
end)

client.run()
```

---

### 🔄 [Updater](https://ccmisc.twijn.dev/updater.html) - Package Management
*Keep your libraries up to date programmatically*

```lua
local updater = require("updater")

-- Check for updates
local updates = updater.checkUpdates()

-- Update all packages
updater.updateAll()
```

---

## 🎯 Why CC-Misc?

### Problem: Building CC programs is tedious
- Writing terminal UIs is painful
- Data persistence requires boilerplate
- No standard library for common tasks
- Managing dependencies manually
- Updating code across multiple computers

### Solution: Professional utilities
- ✅ **One-line installation** - wget and go
- ✅ **Dependency resolution** - Installer handles it automatically
- ✅ **Beautiful UIs** - FormUI makes it easy
- ✅ **Professional docs** - Full API reference with examples
- ✅ **Version management** - Update with a single command
- ✅ **Battle-tested** - Used in production servers

---

## 📖 Documentation

Full documentation with API references, examples, and guides:

**🔗 [ccmisc.twijn.dev](https://ccmisc.twijn.dev)**

Each library includes:
- Detailed API documentation
- Function signatures with types
- Usage examples
- Version information
- Dependency information

---

## 🛠️ Installation Methods

### Method 1: Interactive Installer (Recommended)
```lua
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installer.lua
```

### Method 2: Pre-select Libraries
```lua
wget run https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installer.lua formui persist log
```

### Method 3: Direct Download
```lua
wget https://raw.githubusercontent.com/Twijn/cc-misc/main/util/formui.lua formui.lua
```

### Method 4: Programmatic Installation
```lua
local updater = require("updater")
updater.install("formui")
```

---

## 🔄 Updating

### Update All Libraries
```lua
local updater = require("updater")
updater.updateAll()
```

### Update Specific Library
```lua
local updater = require("updater")
updater.update("formui")
```

### Check for Updates
```lua
local updater = require("updater")
local updates = updater.checkUpdates()
for _, update in ipairs(updates) do
  print(update.name .. ": " .. update.current .. " -> " .. update.latest)
end
```

---

## 🎓 Examples

### Example 1: Server Configuration Tool
Combine formui, persist, and log for a complete configuration system:

```lua
local FormUI = require("formui")
local persist = require("persist")
local log = require("log")

-- Load existing config
local config = persist("server_config.json")

-- Create configuration form
local form = FormUI.new("Server Configuration")

local nameField = form:text("Server Name", config.get("name") or "MyServer")
local portField = form:number("Port", config.get("port") or 8080)
local enabledField = form:checkbox("Auto-start", config.get("autostart") or true)

form:addSubmitCancel()

-- Run form and save results
local result = form:run()
if result then
  config.set("name", nameField())
  config.set("port", portField())
  config.set("autostart", enabledField())
  
  log.info("Configuration saved: " .. nameField() .. " on port " .. portField())
  print("Configuration saved!")
else
  log.warn("Configuration cancelled")
end
```

### Example 2: Scheduled Task Manager
Use timeutil and log for automated tasks:

```lua
local timeutil = require("timeutil")
local log = require("log")

-- Backup every 10 minutes
timeutil.every(function()
  log.info("Running backup...")
  -- Your backup code here
  log.info("Backup complete")
end, 600, "backup_timer")

-- Status report every hour
timeutil.every(function()
  log.info("System status: OK")
end, 3600, "status_timer")

log.info("Task manager started")
timeutil.run()
```

### Example 3: Interactive Admin Panel
Build a command-line admin interface:

```lua
local cmd = require("cmd")
local log = require("log")

local commands = {
  status = {
    description = "Show server status",
    execute = function(args, context)
      context.succ("Server running on port 8080")
    end
  },
  restart = {
    description = "Restart the server",
    execute = function(args, context)
      log.warn("Server restart requested")
      context.mess("Restarting...")
      os.reboot()
    end
  }
}

cmd("Admin Panel", "1.0.0", commands)
```

---

## 🏗️ Project Structure

```
cc-misc/
├── util/                    # Core utility libraries
│   ├── formui.lua          # Form builder
│   ├── persist.lua         # Data persistence
│   ├── log.lua             # Logging system
│   ├── timeutil.lua        # Interval management
│   ├── tables.lua          # Table utilities
│   ├── s.lua               # Settings management
│   ├── cmd.lua             # Command interface
│   ├── shopk.lua           # Kromer API client
│   ├── installer.lua       # Interactive installer
│   └── updater.lua         # Update manager
├── farm/                   # Example: Farming automation
├── brewery/                # Example: Brewery management
├── signshop/               # Example: Sign shop system
├── spleef/                 # Example: Spleef game server
└── docs/                   # Generated documentation
```

---

## 🤝 Contributing

Contributions are welcome! Please feel free to:

- 🐛 Report bugs
- 💡 Suggest new features
- 📝 Improve documentation
- 🔧 Submit pull requests

---

## 📜 License

MIT License - see [LICENSE](LICENSE) for details

Copyright (c) 2025 Tyler Twining

---

## 🔗 Links

- **Documentation**: [ccmisc.twijn.dev](https://ccmisc.twijn.dev)
- **GitHub**: [github.com/Twijn/cc-misc](https://github.com/Twijn/cc-misc)
- **Issues**: [github.com/Twijn/cc-misc/issues](https://github.com/Twijn/cc-misc/issues)

---

## 🌟 Star this project if you find it useful!

**Made with ❤️ for the ComputerCraft community**
