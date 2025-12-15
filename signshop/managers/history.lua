--- SignShop History Manager ---
--- Tracks changes to products for undo functionality.
---
--- Features: Records create/update/delete actions with before/after state,
--- provides undo capability for recent changes, persists history to disk,
--- limits history size to prevent unbounded growth.
---
---@version 1.6.0
-- @module signshop-history

local persist = require("lib.persist")
local logger = require("lib.log")
local s = require("lib.s")

local manager = {}

-- History configuration
local maxHistory = s.number("history.max_entries", 1, 500, 50)

-- History data storage
local historyData = persist("history.json", false)

-- Initialize defaults
historyData.setDefault("entries", {})
historyData.setDefault("nextId", 1)

---@class HistoryEntry
---@field id number Unique entry ID
---@field timestamp number Unix timestamp in milliseconds
---@field date string Human-readable date
---@field action string "create" | "update" | "delete"
---@field entityType string Type of entity (e.g., "product")
---@field entityId string Identifier for the entity (e.g., product meta)
---@field before table|nil State before change (nil for create)
---@field after table|nil State after change (nil for delete)
---@field undone boolean Whether this change has been undone

--- Record a change to history
---@param action string "create" | "update" | "delete"
---@param entityType string Type of entity (e.g., "product")
---@param entityId string Identifier for the entity
---@param before table|nil State before change (nil for create)
---@param after table|nil State after change (nil for delete)
---@return HistoryEntry The recorded entry
function manager.recordChange(action, entityType, entityId, before, after)
    local data = historyData.getAll()
    local entries = data.entries or {}
    local nextId = data.nextId or 1
    
    local entry = {
        id = nextId,
        timestamp = os.epoch("utc"),
        date = os.date("%Y-%m-%d %H:%M:%S"),
        action = action,
        entityType = entityType,
        entityId = entityId,
        before = before,
        after = after,
        undone = false,
    }
    
    -- Prepend new entry (most recent first)
    table.insert(entries, 1, entry)
    
    -- Trim history if exceeds max
    while #entries > maxHistory do
        table.remove(entries)
    end
    
    historyData.set("entries", entries)
    historyData.set("nextId", nextId + 1)
    
    logger.info(string.format("Recorded history: %s %s '%s'", action, entityType, entityId))
    
    return entry
end

--- Get recent history entries
---@param limit? number Maximum entries to return (default 20)
---@return HistoryEntry[] Array of history entries
function manager.getHistory(limit)
    limit = limit or 20
    local entries = historyData.get("entries") or {}
    local result = {}
    
    for i = 1, math.min(limit, #entries) do
        table.insert(result, entries[i])
    end
    
    return result
end

--- Get all history entries
---@return HistoryEntry[] Array of all history entries
function manager.getAllHistory()
    return historyData.get("entries") or {}
end

--- Get a specific history entry by ID
---@param entryId number The entry ID to find
---@return HistoryEntry|nil The entry or nil if not found
function manager.getEntry(entryId)
    local entries = historyData.get("entries") or {}
    for _, entry in ipairs(entries) do
        if entry.id == entryId then
            return entry
        end
    end
    return nil
end

--- Check if an entry can be undone
---@param entryId number The entry ID to check
---@return boolean canUndo Whether the entry can be undone
---@return string|nil reason Reason if cannot undo
function manager.canUndo(entryId)
    local entry = manager.getEntry(entryId)
    
    if not entry then
        return false, "Entry not found"
    end
    
    if entry.undone then
        return false, "Already undone"
    end
    
    -- For updates and deletes, we can always undo
    -- For creates, we can undo (delete the created item)
    
    return true, nil
end

--- Get list of changes that can be undone
---@param limit? number Maximum entries to return (default 10)
---@return HistoryEntry[] Array of undoable entries
function manager.getUndoableChanges(limit)
    limit = limit or 10
    local entries = historyData.get("entries") or {}
    local result = {}
    
    for _, entry in ipairs(entries) do
        if not entry.undone then
            table.insert(result, entry)
            if #result >= limit then
                break
            end
        end
    end
    
    return result
end

--- Undo a specific change
--- Note: This function performs the undo and fires appropriate events,
--- but it requires the product manager to be passed in to avoid circular deps.
---@param entryId number The entry ID to undo
---@param productManager table The product manager for product operations
---@return boolean success Whether the undo was successful
---@return string|nil error Error message if failed
function manager.undo(entryId, productManager)
    local canUndo, reason = manager.canUndo(entryId)
    if not canUndo then
        return false, reason
    end
    
    local entry = manager.getEntry(entryId)
    
    if entry.entityType == "product" then
        if entry.action == "create" then
            -- Undo create = delete the product
            local current = productManager.get(entry.entityId)
            if current then
                productManager.unset(entry.entityId)
                os.queueEvent("product_delete", current)
                logger.info(string.format("Undone: Deleted product '%s' (was created)", entry.entityId))
            else
                return false, "Product no longer exists"
            end
            
        elseif entry.action == "update" then
            -- Undo update = restore previous state
            if entry.before then
                productManager.set(entry.before.meta, entry.before)
                
                -- If meta changed, also remove the new meta
                if entry.after and entry.after.meta ~= entry.before.meta then
                    productManager.unset(entry.after.meta)
                end
                
                os.queueEvent("product_update", entry.before, entry.after)
                logger.info(string.format("Undone: Restored product '%s' to previous state", entry.entityId))
            else
                return false, "No previous state to restore"
            end
            
        elseif entry.action == "delete" then
            -- Undo delete = recreate the product
            if entry.before then
                productManager.set(entry.before.meta, entry.before)
                os.queueEvent("product_create", entry.before)
                logger.info(string.format("Undone: Restored deleted product '%s'", entry.entityId))
            else
                return false, "No previous state to restore"
            end
        end
    else
        return false, "Unknown entity type: " .. tostring(entry.entityType)
    end
    
    -- Mark entry as undone
    local entries = historyData.get("entries") or {}
    for i, e in ipairs(entries) do
        if e.id == entryId then
            entries[i].undone = true
            break
        end
    end
    historyData.set("entries", entries)
    
    os.queueEvent("history_undo", entry)
    
    return true, nil
end

--- Format a history entry for display
---@param entry HistoryEntry The entry to format
---@return string Formatted description
function manager.formatEntry(entry)
    local actionText = {
        create = "Created",
        update = "Updated",
        delete = "Deleted",
    }
    
    local action = actionText[entry.action] or entry.action
    local name = entry.entityId
    
    -- Try to get a better name for products
    if entry.entityType == "product" then
        local state = entry.after or entry.before
        if state and state.line1 then
            name = state.line1
            if state.line2 and #state.line2 > 0 then
                name = name .. " " .. state.line2
            end
        end
    end
    
    local status = entry.undone and " [UNDONE]" or ""
    
    return string.format("%s %s: %s%s", action, entry.entityType, name, status)
end

--- Force save history to disk (for shutdown)
function manager.beforeShutdown()
    -- Persist module saves automatically, but we can force a save by setting a value
    local entries = historyData.get("entries") or {}
    historyData.set("entries", entries)
    logger.info("History saved before shutdown")
end

--- Clear all history (use with caution!)
function manager.clearAll()
    historyData.set("entries", {})
    historyData.set("nextId", 1)
    logger.info("History cleared")
end

return manager
