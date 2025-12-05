--- SignShop Purchase Manager ---
--- Handles Krist transactions and item dispensing.
---
---@version 1.0.0

local s = require("lib.s")
local logger = require("lib.log")
local persist = require("lib.persist")

local productManager = require("managers.product")
local inventoryManager = require("managers.inventory")

-- Check if this is first run or settings are missing
local needsSetup = not settings.get("shopk.private")

local shopkConfig

if needsSetup then
    -- Use form-based setup for new installations
    local form = s.useForm("Krist Shop Setup")
    
    local syncNodeField = form.string("shopk.syncnode", "https://kromer.reconnected.cc/api/krist/")
    local privateKeyField = form.string("shopk.private")
    
    if not form.submit() then
        error("Setup cancelled. Purchase manager requires Krist configuration.")
    end
    
    shopkConfig = {
        syncNode = syncNodeField(),
        privatekey = privateKeyField(),
    }
else
    shopkConfig = {
        syncNode = s.string("shopk.syncnode", "https://kromer.reconnected.cc/api/krist/"),
        privatekey = s.string("shopk.private"),
    }
end

local shopk = require("lib.shopk")(shopkConfig)

local awaitingRefunds = persist("awaiting-refunds.txt", true)

local manager = {
  address = nil,
  shopk = shopk,
  run = shopk.run,
  awaitingRefunds = awaitingRefunds,
  close = function()
    logger.warn("Stopping shopk")
    shopk.close()
  end,
}

function manager.refundAwaiting()
  local currentRefunds = awaitingRefunds.getAll()
  for tid, details in pairs(currentRefunds) do
    logger.info(
      string.format(
        "Processing #%d from %s (%.03f KRO)",
        details.transactionId,
        details.address,
        details.amount
      )
    )
    shopk.send({
      to = details.address,
      amount = details.amount,
      metadata = string.format("message=Delayed refund from transaction #%d", details.transactionId),
    }, function(result)
      if result.ok then
        logger.info("Successfully sent refund! Transaction #" .. result.transaction.id)
        awaitingRefunds.unset(tid)
      else
        logger.error(result.error)
      end
    end)
    sleep(1)
  end
end

shopk.on("ready", function()
  logger.info(string.format("Shopk v%s is connected! Getting current address details...", shopk._v))
  shopk.me(function(result)
    if result.is_guest or not result.address then
      error("You may not log in as a guest! Make sure you set a valid private key using 'set shopk.private <key>'")
    end
    manager.address = result.address.address
    logger.info("Logged in as " .. manager.address)
  end)
end)

local function refund(toAddress, amount, message, type)
  type = type or "error"
  logger.info(string.format("Refunding %.03f to %s with message %s", amount, toAddress, message))
  shopk.send({
    to = toAddress,
    amount = amount,
    metadata = string.format("%s=%s", type, message),
  }, function(result)
    if result.ok then
      logger.info("Refund successful! Transaction #" .. result.transaction.id)
    else
      logger.error("Refund failed: " .. result.error)
    end
  end)
end

shopk.on("transaction", function(transaction)
  -- ignore anything that isn't to our address
  if transaction.to ~= manager.address then return end
  os.queueEvent("transaction", transaction)

  -- match a value to a product, if possible. return if a product is found
  for _, meta in pairs(transaction.meta.values) do
    local product = productManager.get(meta)
    if product then
      local purchased = math.floor(transaction.value / product.cost)
      logger.info(
        string.format(
          "Handling purchase for %d %s @ %.03f each from %s",
          purchased,
          product.modid,
          product.cost,
          transaction.from
        )
      )
      local dispensed = inventoryManager.dispense(product, purchased)
      local refundAmount = transaction.value - (product.cost * dispensed)

      local refundMessage = "Here is your refund for items that could not be dispensed!"
      if product.cost > transaction.value then
        refundMessage = string.format("You must purchase at least one of %s!", productManager.getName(product))
      elseif dispensed == 0 then
        refundMessage = string.format("Item %s is out of stock!", productManager.getName(product))
      end

      if refundAmount > 0 then
        refund(transaction.from, refundAmount, refundMessage)
      end

      if dispensed > 0 then
        os.queueEvent("purchase", product, dispensed, transaction, refundAmount)
      end
      return
    end
  end

  local keys = transaction.meta.keys
  if keys.message or keys.error then
    logger.error(
      string.format(
        "WILL NOT REFUND invalid transaction #%d as it has a message or error attribute!",
        transaction.id
      )
    )
    awaitingRefunds.set(transaction.id, {
      transactionId = transaction.id,
      address = transaction.from,
      amount = transaction.value,
      time = os.date(),
    })
    return
  end

  refund(transaction.from, transaction.value, "Invalid meta! Use /pay ktwijnmall <amt> <last line of sign, ex: glass>")
end)

return manager
