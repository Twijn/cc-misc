--- SignShop Sign Manager ---
--- Manages shop signs and updates them with product/stock information.
---
---@version 1.5.0

local logger = require("lib.log")
local persist = require("lib.persist")
local aisleManager = require("managers.aisle")
local productManager = require("managers.product")
local inventoryManager = require("managers.inventory")

local productSigns = persist("product-signs.json")

local manager = {}

local function splitBySpaces(str)
    local result = {}
    for word in str:gmatch("%S+") do
        table.insert(result, word)
    end
    return result
end

local function createSignIfProduct(sign)
  local data = sign.getSignText()
  local line1 = data[1]
  local line2 = data[2]
  local splitLine3 = splitBySpaces(data[3])
  local meta = data[4]
  if #splitLine3 == 2 then
    local cost = tonumber(splitLine3[1])
    local aisleName = splitLine3[2]

    if cost then
      if aisleManager.getAisle(aisleName) then
        return productManager:createProductFromSign(meta, line1, line2, cost, aisleName)
      else
        logger.warn("Can't find aisle "..aisleName.." for " ..meta)
      end
    else
      logger.warn("Improper cost for product " ..meta)
    end
  else
    logger.warn("Improper data for missing product "..meta..": line 3 is missing cost or aisle name")
  end
end

local function formatStock(stock)
  if stock >= 1000 then
    return math.floor(stock / 100) / 10 .. "K"
  else
    return stock
  end
end

local function updateSign(sign, product)
  local stock = inventoryManager.getItemStock(product.modid, product.itemnbt, product.anyNbt) or 0
  sign.setSignText(
    product.line1,
    product.line2,
    string.format("%.03f KRO | %s", product.cost, formatStock(stock)),
    product.meta
  )
end

manager.updateAll = function()
  local start = os.clock()
  local signData = {}
  local signs = table.pack(peripheral.find("minecraft:sign"))
  for _, sign in ipairs(signs) do
    local data = sign.getSignText()
    local meta = data[4]
    local product = productManager.get(meta)

    if not product and #meta > 0 then
      logger.warn(string.format("Did not find product for sign %s. Attempting to create!", meta))
      product = createSignIfProduct(sign)
    end

    if product then
      updateSign(sign, product)
      if not signData[product.meta] then
        signData[product.meta] = {}
      end
      table.insert(signData[product.meta], peripheral.getName(sign))
    end
  end
  productSigns.setAll(signData)
  logger.info(string.format("Updated %d signs in %.02f seconds", #signs, os.clock() - start))
end

local function getSigns(meta)
  local signNames = productSigns.get(meta)
  if not signNames or #signNames == 0 then
    logger.warn("Could not find product signs for " .. meta)
  end

  local signs = {}
  for i,v in pairs(signNames) do
    local sign = peripheral.wrap(v)
    if sign then
      table.insert(signs, sign)
    else
      logger.warn(string.format("Could not find sign %s for product %s", v, meta))
    end
  end
  return signs
end

local function updateSigns(signs, ...)
  for _, sign in pairs(signs) do
    sign.setSignText(...)
  end
end

manager.itemPurchase = function(product)
  local signs = getSigns(product.meta)
  if #signs > 0 then
    for i = 1,15 do
      local bars = string.rep("-", i)
      updateSigns(signs, bars, "Thank you for", "your purchase!", product.meta)
      bars = bars:sub(1, #bars - 1)
      sleep(.2)
    end
    manager.updateItemSigns(product)
  end
end

manager.updateItemSigns = function(product, oldMeta) -- TODO: maybe make item/product consistent here, idk
  local signs = getSigns(oldMeta or product.meta)
  logger.info(string.format("Updating %d sign(s) for item %s", #signs, productManager.getName(product)))
  for _, sign in pairs(signs) do
    updateSign(sign, product)
  end
end

manager.run = function()
  manager.updateAll()
  while true do
    local e = table.pack(os.pullEvent())
    local event = e[1]
    if event == "purchase" then
      manager.itemPurchase(e[2])
    elseif event == "product_update" then
      manager.updateItemSigns(e[2], e[3].meta)
    end
  end
end

return manager
