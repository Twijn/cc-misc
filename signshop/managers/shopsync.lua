--- SignShop ShopSync Manager ---
--- Broadcasts shop data to the ShopSync network.
---
---@version 1.5.0

local s = require("lib.s")
local logger = require("lib.log")
local formui = require("lib.formui")

local inventoryManager = require("managers.inventory")
local productManager = require("managers.product")
local purchaseManager = require("managers.purchase")

-- Check if this is first run or settings are missing
local needsSetup = not settings.get("shopsync.modem")

local modem, channel

if needsSetup then
    -- Use form-based setup for new installations
    local form = s.useForm("ShopSync Setup")
    
    local modemField = form.peripheral("shopsync.modem", "modem")
    local channelField = form.number("shopsync.channel", 0, 65535, 9773)
    
    if not form.submit() then
        error("Setup cancelled. ShopSync manager requires configuration.")
    end
    
    modem = modemField()
    channel = channelField()
else
    modem = s.peripheral("shopsync.modem", "modem")
    channel = s.number("shopsync.channel", 0, 65535, 9773)
end

-- Validate modem is wireless
if not modem.isWireless() then
    settings.unset("shopsync.modem")
    settings.save()
    logger.error("Selected modem is not wireless! Please restart and set a new one.")
    return
end

local version = ssVersion and ssVersion() or "unknown"

if version == "unknown" then
    logger.warn("Version could not be determined. Are you running this manager outside of SignShop?")
end

local function getCoordinates()
    local x, y, z = gps.locate()
    if x then
        return { x, y, z }
    end
    return nil
end

-- Check if ShopSync info is already configured
local needsInfoSetup = not settings.get("shopsync.name")

local shopName, shopDescription, shopOwner, locationDescription, locationDimension

if needsInfoSetup then
    -- Use form-based setup for shop info
    local form = s.useForm("ShopSync Info Setup")
    
    local nameField = form.string("shopsync.name")
    local descField = form.string("shopsync.description")
    local ownerField = form.string("shopsync.owner")
    local locDescField = form.string("shopsync.location.description")
    local dimField = form.string("shopsync.location.dimension", "overworld")
    
    if not form.submit() then
        error("Setup cancelled. ShopSync info configuration is required.")
    end
    
    shopName = nameField()
    shopDescription = descField()
    shopOwner = ownerField()
    locationDescription = locDescField()
    locationDimension = dimField()
else
    shopName = s.string("shopsync.name")
    shopDescription = s.string("shopsync.description")
    shopOwner = s.string("shopsync.owner")
    locationDescription = s.string("shopsync.location.description")
    locationDimension = s.string("shopsync.location.dimension", "overworld")
end

-- Layout basic data for ShopSync
local data = {
    type = "ShopSync",
    version = 1,
    info = {
        name = shopName,
        description = shopDescription,
        owner = shopOwner,
        computerID = os.getComputerID(),
        software = {
            name = "SignShop",
            version = version,
        },
        location = {
            coordinates = getCoordinates(),
            description = locationDescription,
            dimension = locationDimension,
        },
    },
}

local manager = {}

local function sendShopSync()
    logger.info("Sending ShopSync data...")
    local items = {}

    for _, product in pairs(productManager.getAll()) do
        local name = productManager.getName(product)
        table.insert(items, {
            prices = {
                {
                    value = product.cost,
                    currency = "KRO",
                    address = purchaseManager.address,
                    requiredMeta = product.meta,
                }
            },
            item = {
                name = product.modid,
                nbt = product.anyNbt and "*" or product.itemnbt,  -- Use "*" to indicate any NBT
                displayName = name,
            },
            stock = inventoryManager.getItemStock(product.modid, product.itemnbt, product.anyNbt) or 0,
            dynamicPrice = false,
            madeOnDemand = false,
            requiresInteraction = false,
            shopBuysItem = false,
        })
    end

    data.items = items

    modem.transmit(channel, os.getComputerID(), data)
end

function manager.run()
    sleep(30)
    sendShopSync() -- send 30 seconds in after starting

    while true do
        os.pullEvent("purchase")
        sleep(5)
        sendShopSync() -- send 5 seconds after each purchase
    end
end

return manager
