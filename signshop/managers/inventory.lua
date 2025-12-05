--- SignShop Inventory Manager ---
--- Manages inventory scanning and item dispensing.
---
---@version 1.0.0

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

function manager.getItemStock(name, nbt)
  local key = getItemKey({
    name = name,
    nbt = nbt,
  })
  return stockCache.get(key)
end

function manager.getItemDetail(name, nbt)
  local key = getItemKey({
    name = name,
    nbt = nbt,
  })
  local detail = detailCache.get(key)
  detail.count = stockCache.get(key)
  return detail
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
      if item.name == product.modid and item.nbt == product.itemnbt then
        local remaining = maxCount - dispensed
        local moved = chest.pushItems(aisle.self, slot, remaining)
        dispensed = dispensed + moved
        sleep()
      end
    end
  end

  decrementStock(product.modid, product.itemnbt, dispensed)

  return dispensed
end

function manager.run()
  while true do
    manager.rescan()
    sleep(300)
  end
end

return manager
