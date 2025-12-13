--- SignShop Inventory Manager ---
--- Manages inventory scanning and item dispensing.
---
---@version 1.4.2

local persist = require("lib.persist")
local logger = require("lib.log")
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
    for slot, item in pairs(chest.list()) do
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

function manager.dispense(product, maxCount)
  local aisle = aisleManager.getAisle(product.aisleName)
  if not aisle then
    return false, string.format("Aisle %s not found!", product.aisleName)
  end

  peripheral.call(aisle.self, "turnOn")

  local dispensed = 0
  for _, chest in ipairs(getChests()) do
    for slot, item in pairs(chest.list()) do
      if dispensed >= maxCount then break end
      -- Match item: if anyNbt is true, match only by modid; otherwise match both modid and nbt
      local matches = item.name == product.modid
      if matches and not product.anyNbt then
        matches = item.nbt == product.itemnbt
      end
      if matches then
        local remaining = maxCount - dispensed
        local moved = chest.pushItems(aisle.self, slot, remaining)
        dispensed = dispensed + moved
        -- Decrement stock for the specific item that was dispensed
        decrementStock(item.name, item.nbt, moved)
        sleep()
      end
    end
  end

  return dispensed
end

function manager.run()
  while true do
    manager.rescan()
    sleep(300)
  end
end

return manager
