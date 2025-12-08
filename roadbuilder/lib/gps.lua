--- GPS and Position Management Library for RBC
--- Provides GPS location, facing detection, and position tracking
---
---@version 1.0.0
-- @module gps

local module = {}

-- Direction constants
module.DIRECTIONS = {
    NORTH = 0, -- -Z
    EAST = 1,  -- +X
    SOUTH = 2, -- +Z
    WEST = 3,  -- -X
}

module.DIRECTION_NAMES = {
    [0] = "North",
    [1] = "East",
    [2] = "South",
    [3] = "West",
}

-- Direction vectors for movement
module.DIRECTION_VECTORS = {
    [0] = {x = 0, z = -1},  -- North (-Z)
    [1] = {x = 1, z = 0},   -- East (+X)
    [2] = {x = 0, z = 1},   -- South (+Z)
    [3] = {x = -1, z = 0},  -- West (-X)
}

-- Internal state
local position = {x = 0, y = 0, z = 0}
local facing = 0
local hasGPS = false
local gpsTimeout = 2

---Set the GPS timeout
---@param timeout number Timeout in seconds
function module.setTimeout(timeout)
    gpsTimeout = timeout
end

---Get the current GPS position
---@return number|nil x, number|nil y, number|nil z GPS coordinates or nil if unavailable
function module.locate()
    local x, y, z = gps.locate(gpsTimeout)
    if x then
        hasGPS = true
        position.x = x
        position.y = y
        position.z = z
        return x, y, z
    end
    return nil, nil, nil
end

---Detect facing direction by moving and comparing GPS positions
---@return number|nil facing Direction (0-3) or nil if unable to detect
function module.detectFacing()
    local startX, startY, startZ = module.locate()
    if not startX then
        return nil
    end
    
    -- Try moving forward to detect facing
    if turtle and turtle.forward() then
        local newX, newY, newZ = module.locate()
        if newX then
            -- Calculate direction based on movement
            local dx = newX - startX
            local dz = newZ - startZ
            
            -- Move back to original position
            turtle.back()
            
            if dz < 0 then
                facing = module.DIRECTIONS.NORTH
            elseif dx > 0 then
                facing = module.DIRECTIONS.EAST
            elseif dz > 0 then
                facing = module.DIRECTIONS.SOUTH
            elseif dx < 0 then
                facing = module.DIRECTIONS.WEST
            end
            
            return facing
        end
        -- Move back even if GPS failed
        turtle.back()
    end
    
    return nil
end

---Get the current position
---@return table position {x, y, z}
function module.getPosition()
    return {x = position.x, y = position.y, z = position.z}
end

---Set the current position manually (for relative tracking)
---@param x number X coordinate
---@param y number Y coordinate
---@param z number Z coordinate
function module.setPosition(x, y, z)
    position.x = x
    position.y = y
    position.z = z
end

---Get the current facing direction
---@return number facing Direction (0-3)
function module.getFacing()
    return facing
end

---Set the current facing direction manually
---@param dir number Direction (0-3)
function module.setFacing(dir)
    facing = dir % 4
end

---Get the facing direction name
---@return string name Direction name (e.g., "North")
function module.getFacingName()
    return module.DIRECTION_NAMES[facing] or "Unknown"
end

---Check if GPS is available
---@return boolean hasGPS True if GPS signal was acquired
function module.hasGPSSignal()
    return hasGPS
end

---Update position after moving forward
function module.updateForward()
    local dir = module.DIRECTION_VECTORS[facing]
    position.x = position.x + dir.x
    position.z = position.z + dir.z
end

---Update position after moving backward
function module.updateBack()
    local dir = module.DIRECTION_VECTORS[facing]
    position.x = position.x - dir.x
    position.z = position.z - dir.z
end

---Update position after moving up
function module.updateUp()
    position.y = position.y + 1
end

---Update position after moving down
function module.updateDown()
    position.y = position.y - 1
end

---Update facing after turning left
function module.updateTurnLeft()
    facing = (facing - 1) % 4
end

---Update facing after turning right
function module.updateTurnRight()
    facing = (facing + 1) % 4
end

---Calculate the facing required to move from one position to another
---@param fromX number Starting X
---@param fromZ number Starting Z
---@param toX number Target X
---@param toZ number Target Z
---@return number|nil facing Direction to face, or nil if same position
function module.getFacingTowards(fromX, fromZ, toX, toZ)
    local dx = toX - fromX
    local dz = toZ - fromZ
    
    if dx == 0 and dz == 0 then
        return nil
    end
    
    -- Determine primary direction
    if math.abs(dx) > math.abs(dz) then
        if dx > 0 then
            return module.DIRECTIONS.EAST
        else
            return module.DIRECTIONS.WEST
        end
    else
        if dz > 0 then
            return module.DIRECTIONS.SOUTH
        else
            return module.DIRECTIONS.NORTH
        end
    end
end

---Calculate turns needed to face a target direction
---@param currentFacing number Current facing (0-3)
---@param targetFacing number Target facing (0-3)
---@return string action "left", "right", "around", or "none"
function module.getTurnAction(currentFacing, targetFacing)
    local diff = (targetFacing - currentFacing) % 4
    if diff == 0 then
        return "none"
    elseif diff == 1 then
        return "right"
    elseif diff == 2 then
        return "around"
    else
        return "left"
    end
end

---Calculate distance between two positions
---@param x1 number First X
---@param y1 number First Y
---@param z1 number First Z
---@param x2 number Second X
---@param y2 number Second Y
---@param z2 number Second Z
---@return number distance Euclidean distance
function module.distance(x1, y1, z1, x2, y2, z2)
    return math.sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2)
end

---Calculate Manhattan distance (block distance) between two positions
---@param x1 number First X
---@param y1 number First Y
---@param z1 number First Z
---@param x2 number Second X
---@param y2 number Second Y
---@param z2 number Second Z
---@return number distance Manhattan distance
function module.manhattanDistance(x1, y1, z1, x2, y2, z2)
    return math.abs(x2-x1) + math.abs(y2-y1) + math.abs(z2-z1)
end

---Serialize position and facing for network transmission
---@return table data Position and facing data
function module.serialize()
    return {
        x = position.x,
        y = position.y,
        z = position.z,
        facing = facing,
        facingName = module.DIRECTION_NAMES[facing],
        hasGPS = hasGPS,
    }
end

---Deserialize position and facing from network data
---@param data table Position and facing data
function module.deserialize(data)
    if data.x then position.x = data.x end
    if data.y then position.y = data.y end
    if data.z then position.z = data.z end
    if data.facing then facing = data.facing end
    if data.hasGPS ~= nil then hasGPS = data.hasGPS end
end

module.VERSION = "1.0.0"
return module
