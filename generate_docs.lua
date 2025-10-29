#!/usr/bin/env lua

---Simple documentation generator for EmmyLua annotated files
local function extractDocs(filePath)
    local file = io.open(filePath, "r")
    if not file then return nil end
    
    local content = file:read("*all")
    file:close()
    
    local docs = {
        classes = {},
        functions = {},
        examples = {}
    }
    
    -- Extract class definitions
    for class, description in content:gmatch("%-%-%-@class (%w+).-\n%-%-%-([^\n]*.-@example.-```lua.-```)", "ms") do
        docs.classes[class] = {
            description = description,
            methods = {}
        }
    end
    
    -- Extract function definitions
    for funcDef in content:gmatch("%-%-%-.-function[^\n]*") do
        table.insert(docs.functions, funcDef)
    end
    
    return docs
end

local function generateMarkdown(utilPath)
    local files = {
        "cmd.lua", "formui.lua", "persist.lua", "s.lua", 
        "tables.lua", "timeutil.lua", "shopk/shopk.lua"
    }
    
    local markdown = "# CC-Misc Utilities Documentation\n\n"
    
    for _, file in ipairs(files) do
        local fullPath = utilPath .. "/" .. file
        local docs = extractDocs(fullPath)
        if docs then
            markdown = markdown .. "## " .. file .. "\n\n"
            -- Add extracted documentation
        end
    end
    
    return markdown
end

-- Usage: lua generate_docs.lua
print("Generating documentation...")
local docs = generateMarkdown("util")
print("Documentation generated!")