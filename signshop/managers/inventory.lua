--- SignShop Inventory Manager ---
--- Manages inventory scanning and item dispensing.
--- Includes aisle health checking before dispense operations.
---
---@version 1.6.0

local persist = require("lib.persist")
local logger = require("lib.log")
local errors = require("lib.errors")
local aisleManager = require("managers.aisle")

local detailCache = persist("detail-cache.json")
local stockCache = persist("stock-cache.json")

local manager = {}

local function getChests()
  return table.pack(peripheral.find("inventory"))
end

local function getItemKey(item)
  if item.nbt then
    return item.name .. "." .. item.nbt
  else
    return item.name
  end
end

--- Get all stock keys matching a given mod ID (for anyNbt products)
---@param name string The mod ID to match
---@return table Array of {key, count} pairs for all matching items
local function getMatchingStockKeys(name)
  local matches = {}
  local allStock = stockCache.getAll() or {}
  for key, count in pairs(allStock) do
    -- Check if the key starts with the mod ID
    if key == name or key:match("^" .. name:gsub("%.", "%%."):gsub("%-", "%%-") .. "%.(.+)$") then
      table.insert(matches, { key = key, count = count })
    end
  end
  return matches
end

function manager.rescan()
  local start = os.clock()
  local stock = {}
  local chests = getChests()
  for _, chest in ipairs(chests) do
    if chest and chest.list then
      local items = chest.list()
      if items then
        for slot, item in pairs(items) do
          local key = getItemKey(item)
          if not detailCache.get(key) then
            local detail = chest.getItemDetail(slot)
            detail.count = nil -- remove current count from it (will be overwritten in getItemDetail() with the current stock)
            detailCache.set(key, detail)
          end
          if not stock[key] then
            stock[key] = 0
          end
          stock[key] = stock[key] + item.count
        end
      end
    end
  end
  stockCache.setAll(stock)
  logger.info(string.format("Rescanned inventories in %.2f second(s)", os.clock() - start))
end

function manager.getItemStock(name, nbt, anyNbt)
  if anyNbt then
    -- Sum up all stock for items with this mod ID, regardless of NBT
    local matches = getMatchingStockKeys(name)
    local total = 0
    for _, match in ipairs(matches) do
      total = total + match.count
    end
    return total > 0 and total or nil
  else
    local key = getItemKey({
      name = name,
      nbt = nbt,
    })
    return stockCache.get(key)
  end
end

function manager.getItemDetail(name, nbt, anyNbt)
  if anyNbt then
    -- Get details for the first matching item found
    local matches = getMatchingStockKeys(name)
    if #matches > 0 then
      local detail = detailCache.get(matches[1].key)
      if detail then
        detail = textutils.unserialize(textutils.serialize(detail)) -- shallow copy
        -- Sum up total stock
        local total = 0
        for _, match in ipairs(matches) do
          total = total + match.count
        end
        detail.count = total
        return detail
      end
    end
    return nil
  else
    local key = getItemKey({
      name = name,
      nbt = nbt,
    })
    local detail = detailCache.get(key)
    if detail then
      detail.count = stockCache.get(key)
    end
    return detail
  end
end

local function decrementStock(name, nbt, count)
  local key = getItemKey({
    name = name,
    nbt = nbt,
  })
  local currentStock = stockCache.get(key)
  if currentStock then
    stockCache.set(key, currentStock - count)
  end
end

--- Dispense items for a product to an aisle
--- Checks aisle health before attempting dispense.
---@param product table The product to dispense
---@param maxCount number Maximum number of items to dispense
---@return table Result object (use errors.isError to check, errors.unwrap to get data)
function manager.dispense(product, maxCount)
  logger.info(string.format("Starting dispense: %d x %s to aisle %s", maxCount, product.modid, product.aisleName))
  
  local aisle, aisleErr = aisleManager.getAisle(product.aisleName)
  if not aisle then
    local errType = errors.types.AISLE_NOT_FOUND
    local errMsg = string.format("Aisle %s not found!", product.aisleName)
    if errors.isError(aisleErr) then
      errType = aisleErr.type
      errMsg = aisleErr.message
    end
    logger.error(string.format("[%s] %s", errType, errMsg))
    return errors.create(errType, errMsg, { aisleName = product.aisleName })
  end

  -- Check aisle health
  local health = aisleManager.getAisleHealth(product.aisleName)
  
  if health == "offline" then
    local errMsg = string.format("Aisle %s is offline", product.aisleName)
    logger.error(string.format("[%s] %s", errors.types.AISLE_OFFLINE, errMsg))
    return errors.create(errors.types.AISLE_OFFLINE, errMsg, { 
      aisleName = product.aisleName,
      health = health 
    })
  elseif health == "degraded" then
    logger.warn(string.format("Aisle %s is degraded, attempting dispense anyway", product.aisleName))
  end

  -- Validate the aisle peripheral exists and is reachable
  if not aisle.self then
    local errMsg = string.format("Aisle %s has no peripheral name configured", product.aisleName)
    logger.error(string.format("[%s] %s", errors.types.AISLE_OFFLINE, errMsg))
    return errors.create(errors.types.AISLE_OFFLINE, errMsg, { aisleName = product.aisleName })
  end

  if not peripheral.isPresent(aisle.self) then
    local errMsg = string.format("Aisle %s peripheral '%s' is not reachable", product.aisleName, aisle.self)
    logger.error(string.format("[%s] %s", errors.types.AISLE_OFFLINE, errMsg))
    return errors.create(errors.types.AISLE_OFFLINE, errMsg, { 
      aisleName = product.aisleName,
      peripheral = aisle.self 
    })
  end

  peripheral.call(aisle.self, "turnOn")

  local dispensed = 0
  local chests = getChests()
  logger.info(string.format("Scanning %d chests for %s", #chests, product.modid))
  
  for i, chest in ipairs(chests) do
    local items = chest.list()
    logger.info("on chest " .. i)
    if not items then
      logger.warn(string.format("Chest %d returned nil from list(), skipping", i))
    else
    for slot, item in pairs(items) do
      if dispensed >= maxCount then break end
      -- Match item: if anyNbt is true, match only by modid; otherwise match both modid and nbt
      local matches = item.name == product.modid
      if matches and not product.anyNbt then
        matches = item.nbt == product.itemnbt
      end
      if matches then
        local remaining = maxCount - dispensed
        logger.info(string.format("Transferring %d %s from chest %d slot %d to aisle %s", remaining, product.modid, i, slot, product.aisleName))
        local moved = chest.pushItems(aisle.self, slot, remaining)
        if moved and moved > 0 then
          dispensed = dispensed + moved
          -- Decrement stock for the specific item that was dispensed
          decrementStock(item.name, item.nbt, moved)
        elseif moved == nil then
          -- Peripheral became unreachable mid-dispense
          logger.error(string.format("Lost connection to aisle %s during dispense", product.aisleName))
          break
        end
        sleep()
      end
    end
    end -- end items check
    if dispensed >= maxCount then break end
  end

  logger.info(string.format("Dispensed %d/%d items for product %s", dispensed, maxCount, product.meta))

  if dispensed == 0 and maxCount > 0 then
    local errMsg = string.format("Could not dispense any %s - insufficient stock", product.modid)
    logger.warn(errMsg)
    return errors.create(errors.types.INSUFFICIENT_STOCK, errMsg, {
      product = product.meta,
      requested = maxCount,
      dispensed = 0
    })
  end

  logger.info(string.format("Dispense complete: %d/%d %s", dispensed, maxCount, product.modid))
  return errors.success({ 
    dispensed = dispensed,
    requested = maxCount,
    aisle = product.aisleName
  })
end

--- Force save stock cache (for shutdown)
function manager.beforeShutdown()
  local stock = stockCache.getAll()
  stockCache.setAll(stock)
  logger.info("Stock cache saved before shutdown")
end

function manager.run()
  while true do
    manager.rescan()
    sleep(300)
  end
end

return manager
