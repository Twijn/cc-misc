--- SignShop Product Manager ---
--- Manages product definitions and metadata.
---
---@version 1.0.0

local persist = require("lib.persist")
local logger = require("lib.log")

local products = persist("products.json")

local function findItem(name)
  -- strip modid from search name if given
  local search = name:match(":(.+)$") or name

  for _, chest in ipairs(table.pack(peripheral.find("inventory"))) do
    for slot, item in pairs(chest.list()) do
      -- strip modid from item name
      local itemName = item.name:match(":(.+)$") or item.name
      if itemName == search then
        return chest.getItemDetail(slot)
      end
    end
  end
end

function products:createProductFromSign(meta, line1, line2, cost, aisleName)
  local item = findItem(meta)

  local modid
  if item then
    modid = item.name
  else
    logger.warn("Could not find item for " ..meta)
    print("Enter mod ID:")
    modid = read()
  end

  local product = {
    meta = meta,
    line1 = line1,
    line2 = line2,
    cost = cost,
    aisleName = aisleName,
    modid = modid
  }
  self.set(meta, product)
  os.queueEvent("product_create", product)
  return product
end

function products:updateItem(product, newProduct)
  for key, value in pairs(product) do
    local newValue = newProduct[key]
    if type(value) ~= type(newValue) then
      return false, "Key " .. key .. " must be of type " .. type(value)
    end
  end

  -- If the meta has changed, remove the old meta instance
  if product.meta ~= newProduct.meta then
    products.unset(product.meta)
  end

  products.set(newProduct.meta, newProduct)

  logger.info("Updated item " .. products.getName(newProduct))
  os.queueEvent("product_update", newProduct, product)

  return newProduct
end

local function trim(s)
  s = s
    :gsub("^%s+", "") -- Remove leading whitespace
    :gsub("%s+$", "") -- Remove trailing whitespace
  return s
end

function products.getName(product)
  return trim(product.line1 .. " " .. product.line2)
end

function products.run()
  while true do
    -- Updating products is often done using cmd (a different process), so catch this event too and update our own cache
    local _, newProduct, oldProduct = os.pullEvent("product_update")
    logger.info("Handling product update event for " .. products.getName(newProduct))
    products.set(newProduct.meta, newProduct)
    if newProduct.meta ~= oldProduct.meta then
      products.unset(oldProduct.meta)
    end
  end
end

return products
