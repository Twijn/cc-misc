local brewingStands = table.pack(peripheral.find("minecraft:brewing_stand"))

assert(brewingStands.n > 0, "No brewing stands found!")
print(string.format("Found %d brewing stands", brewingStands.n))

local ignoredStorageChests = {
    "minecraft:chest_368",
}

local recipes = require("/data/recipes")
local prices = require("/data/prices")

local navigation = {"water", "awkward"} -- auto-go to "awkward" potions as it's likely the most common
local currentRecipe = nil
local jobQueue = {}

---------------------------------------------------------
-- Auto-install and require libraries ccmisc.twijn.dev --
---------------------------------------------------------

local libs = {"s", "tables", "shopk"}
local libDir = (fs.exists("disk") and "disk/lib/" or "/lib/")
local allExist = true

for _, lib in ipairs(libs) do
    if not fs.exists(libDir .. lib .. ".lua") then
        allExist = false
        break
    end
end

if not allExist then
    shell.run("wget", "run", "https://raw.githubusercontent.com/Twijn/cc-misc/main/util/installer.lua", table.unpack(libs))
end

-- Add to path
if not package.path:find("disk/lib") then
    package.path = package.path .. ";/disk/lib/?.lua;/lib/?.lua"
end
-- INSTALL LIB END


local tables = require("tables")
local s = require("s")
local shopk = require("shopk")
local log = require("log")

local config = require("data.config")

local mon = s.peripheral("peripheral.monitor", "monitor")

local BOT_NAME = "&9Twin&7Brewery"

-- declare some functions that we need sooner in the script (probably should just split into modules but im lazy)
local drawMonitor

-- shopk
local client = nil
local kromerAddress = nil

local function shopkClose()
    if client and client.close then
        client.close()
        client = nil
    end
end

local function shopkLoop()
    shopkClose()

    client = shopk({
        privatekey = config.privatekey,
        syncNode = config.syncNode,
    })

    client.on("ready", function()
        log.debug("Connected to Kromer websocket. Finding self...")
        client.me(function(data)
            if data.is_guest or not data.address then
                error("you may not log in as guest! return a privatekey from data/config.lua")
            end
            kromerAddress = data.address.address
            log.info("Connected to Kromer as " .. kromerAddress)
            drawMonitor()
        end)
    end)

    client.run()
end

-- Recipe utility functions
local function getRecipesWithBase(baseId)
    local result = {}
    for i,v in pairs(recipes) do
        if v.basePotionId == baseId then
            table.insert(result, v)
        end
    end
    return result
end

local function getRecipeById(id)
    for i,v in pairs(recipes) do
        if v.id == id then
            return v
        end
    end
end

-- Price calculation
local function getIngredientDisplayName(name)
    for i,v in pairs(prices) do
        if v.name == name then
            return v.displayName
        end
    end
    return "unknown"
end

local function getIngredientCost(name)
    for i,v in pairs(prices) do
        if v.name == name then
            return v.cost
        end
    end
    return 0
end

local function getWaterCost()
    for i,v in pairs(prices) do
        if v.name == "minecraft:potion" and v.potion == "minecraft:water" then
            return v.cost * 3
        end
    end
    return 0
end

local function getRecipeCost(recipe, carriedCost)
    if recipe.cost then return recipe.cost end
    if not carriedCost then carriedCost = 0 end

    if recipe.id == "water" then return getWaterCost() end

    carriedCost = carriedCost + getIngredientCost(recipe.ingredient)
    carriedCost = carriedCost + getRecipeCost(getRecipeById(recipe.basePotionId))

    recipe.cost = carriedCost

    return carriedCost
end

-- Stock calculation
local function getPotionKey(potion, potionType)
    return string.format("%s-%s", potion, potionType)
end

local cachedItems = nil
local function getAllItems(forceRefresh)
    if cachedItems and not forceRefresh then return cachedItems end

    local items = {}
    for _, chest in ipairs(table.pack(peripheral.find("inventory"))) do
        for slot, item in pairs(chest.list()) do
            local key = item.name

            if item.name == "minecraft:potion" then
                local detail = chest.getItemDetail(slot)
                key = getPotionKey(detail.potion, detail.potionType)
            elseif item.nbt then
                key = string.format("%s-%s", key, item.nbt)
            end

            if not items[key] then
                items[key] = 0
            end
            items[key] = items[key] + item.count
        end
    end
    cachedItems = items
    return items
end

local function getIngredientStock(ingredientName)
    local items = getAllItems()

    if items[ingredientName] then
        return items[ingredientName]
    end

    return 0
end

local function getBrewedPotionStock(potion, potionType)
    local items = getAllItems()
    local key = getPotionKey(potion, potionType)

    if items[key] then
        return items[key]
    end

    return 0
end

local function getWaterStock()
    return getBrewedPotionStock("minecraft:water", "normal")
end

local function getRecipeStock(recipe, maxStock)
    if recipe.id == "water" then
        local stock = getWaterStock()
        -- return 10^10, 0 -- use this sometimes to see total stock levels
        return stock, stock
    end

    if not maxStock then maxStock = 10^10 end -- just a large number since it will be limited by getWaterStock anyways

    maxStock = math.min(maxStock, getIngredientStock(recipe.ingredient) * 3)

    local baseRecipe = getRecipeById(recipe.basePotionId)
    local totalBaseStock = getRecipeStock(baseRecipe, maxStock)
    local brewableFromBase = math.min(maxStock, totalBaseStock)

    local onHand = getBrewedPotionStock(recipe.potion, recipe.potionType)

    return brewableFromBase + onHand, onHand
end

-------------------------------------------------
-- Job Queue
-------------------------------------------------

local nextId = 1

local function addJob(recipe, tx, quantity)
    quantity = quantity or 1

    local id = nextId
    jobQueue[id] = {
        id = id,
        recipe = recipe,
        tx = tx,
        batchesRemaining = quantity,
        lock = nil
    }

    nextId = nextId + 1
end

local function deleteJob(id)
    jobQueue[id] = nil
end

local function popNextJob(workerName)
    for id, job in pairs(jobQueue) do
        if not job.lock then
            job.lock = workerName
            return id, job
        end
    end
end

local function calcStockLoop()
    while true do
        sleep(120)
        getAllItems(true)
    end
end

-- Monitor drawing
local mx, my = mon.getSize()
local columnWidth = 10

local function setColor(bgColor, txtColor)
    if not txtColor then txtColor = colors.white end

    mon.setBackgroundColor(bgColor)
    mon.setTextColor(txtColor)
end

local function drawRecipe(recipe, gridX, gridY, bgColor, contColor)
    if not bgColor then bgColor = colors.blue end
    if not contColor then contColor = colors.lightBlue end

    local stock = getRecipeStock(recipe)

    if stock == 0 then
        bgColor = colors.red
        contColor = colors.pink
    end

    local description = string.format("x%d %s", stock, recipe.potionType)

    local startX = (gridX - 1) * columnWidth + 1
    local startY = gridY * 3

    mon.setCursorPos(startX + 1, startY)
    setColor(bgColor)
    mon.write(string.rep(" ", columnWidth - 2))
    local name = recipe.displayName
    mon.setCursorPos(startX + math.floor((columnWidth / 2) - (#name / 2)), startY)
    mon.write(name)

    local descColor = colors.black
    if recipe.potionType == "splash" then
        descColor = colors.blue
    elseif recipe.potionType == "lingering" then
        descColor = colors.purple
    end

    setColor(contColor, descColor)

    if currentRecipe and currentRecipe.id == recipe.id then
        mon.setCursorPos(startX + 1, startY + 1)
        mon.write(string.rep(" ", columnWidth - 2))
    end

    mon.setCursorPos(startX + 2, startY + 1)
    mon.write(string.rep(" ", columnWidth - 4))
    mon.setCursorPos(startX + math.floor((columnWidth / 2) - (#description / 2)), startY + 1)
    mon.write(description)
end

function drawMonitor()
    if not kromerAddress then
        return
    end

    getAllItems()
    setColor(colors.black)
    mon.setTextScale(.9)
    mon.clear()

    mx, my = mon.getSize()
    columnWidth = math.floor(mx / 6)

    setColor(colors.white, colors.black)

    local startX = mx - columnWidth
    for i = 4, my do
        mon.setCursorPos(startX, i)
        mon.write(string.rep(" ", columnWidth + 1))
    end

    setColor(colors.lightBlue, colors.black)

    for i = 1, 3 do
        mon.setCursorPos(startX, i)
        mon.write(string.rep(" ", columnWidth + 1))
    end

    mon.setCursorPos(startX + 1, 2)
    mon.write("Ingredients")

    setColor(colors.white, colors.black)

    for col, recipeId in pairs(navigation) do
        for num, recipe in pairs(getRecipesWithBase(recipeId)) do
            drawRecipe(recipe, col, num)
        end
    end

    setColor(colors.white, colors.black)

    for i, recipeId in pairs(navigation) do
        local recipe = getRecipeById(recipeId)
        local cost, quantity, stock = 0, 1, 0

        local displayName = "Water Bottle"
        if recipe.id == "water" then
            cost = getWaterCost()
            quantity = 3
            stock = getWaterStock()
        else
            displayName = getIngredientDisplayName(recipe.ingredient)
            cost = getIngredientCost(recipe.ingredient)
            stock = getIngredientStock(recipe.ingredient)
        end

        local sy = i * 3 + 2

        mon.setTextColor(colors.black)
        mon.setCursorPos(startX + 1, sy)
        mon.write("> " .. displayName)

        local stockColor = colors.blue
        if stock == 0 then
            stockColor = colors.red
        elseif stock < 3 then
            stockColor = colors.yellow
        end

        mon.setCursorPos(startX + 1, sy + 1)
        mon.write("| ")
        mon.setTextColor(stockColor)
        mon.write("available: " .. stock)

        mon.setTextColor(colors.gray)
        cost = cost .. " KRO"
        quantity = "x" .. quantity
        mon.setCursorPos(startX + 1, sy + 2)
        mon.write(quantity .. string.rep(".", columnWidth - #cost - #quantity - 2) .. cost)
    end

    setColor(colors.blue, colors.white)

    local confY = my - 7
    for y = confY, confY + 4 do
        mon.setCursorPos(startX, y)
        mon.write(string.rep(" ", columnWidth + 5))

        if currentRecipe then
            mon.setCursorPos(startX, y)
            if y == confY + 1 then
                mon.write(" " .. currentRecipe.displayName)
            elseif y == confY + 2 then
                mon.setTextColor(colors.lightGray)
                mon.write(" " .. currentRecipe.potionType)
            elseif y == confY + 3 then
                mon.setTextColor(colors.gray)
                mon.write(" 3 pots for " .. getRecipeCost(currentRecipe) .. " KRO")
            end
        elseif y == confY + 2 then
            mon.setCursorPos(startX, y)
            mon.write(" Select an item")
        end
    end

    local checkoutText = "Checkout"
    local command = ("/pay %s <amt> "):format(kromerAddress or "loading")
    local commandArg = ""

    if currentRecipe then
        commandArg = currentRecipe.id
    end

    setColor(currentRecipe and colors.red or colors.gray, colors.white)
    mon.setCursorPos(startX, my - 2)
    mon.write("      " .. checkoutText .. string.rep(" ", 40))
    mon.setCursorPos(startX, my - 1)
    mon.write(command .. string.rep(" ", 40))
    mon.setCursorPos(startX, my)
    mon.write(string.rep(" ", 40))
    mon.setCursorPos(mx - #commandArg + 1, my)
    mon.write(commandArg)
end

local function drawMonitorLoop()
    while true do
        drawMonitor()
        sleep(120)
    end
end

local function monitorTouchLoop()
    while true do
        local e, side, x, y = os.pullEvent("monitor_touch")

        local gridX, gridY = math.floor(x / columnWidth) + 1, math.floor(y / 3)

        local newNavigation = {}
        for i = 1, gridX do
            table.insert(newNavigation, navigation[i])
        end

        local possibleRecipes = getRecipesWithBase(navigation[gridX])
        local newRecipe = possibleRecipes[gridY]

        if newRecipe then
            table.insert(newNavigation, newRecipe.id)
            currentRecipe = newRecipe
        end

        navigation = newNavigation

        drawMonitor()
    end
end

mon.setBackgroundColor(colors.black)
mon.setTextColor(colors.white)
mon.setTextScale(1.5)
mon.setCursorPos(4,2)
mon.clear()
mon.write("Loading...")

local function safe(fn, name, restartDelay)
    restartDelay = restartDelay or 1

    return function(...)
        while true do
            local ok, err = pcall(fn, ...)
            if ok or err == "Terminated" then
                -- function exited normally or is terminating; stop restarting
                return
            end

            printError(("[%s crashed: %s]"):format(name or "thread", err))
            sleep(restartDelay)
            print(("[%s restarting...]"):format(name or "thread"))
        end
    end
end

local function getStorageInventories()
    return table.pack(peripheral.find("sc-goodies:diamond_barrel"))
end

local function brewJob(name, stand)
    local function itemsOut(fromSlot)
        for _, inv in ipairs(getStorageInventories()) do
            inv.pullItems(name, fromSlot)
            if not stand.getItemDetail(fromSlot) then
                return true
            end
        end
        return false
    end

    local function itemsIn(toSlot, itemName, itemNbt, count)
        local remainingCount = count or 1

        local detail = stand.getItemDetail(toSlot)
        if detail then
            if detail.name == itemName and detail.nbt == itemNbt then
                return true
            else
                if not itemsOut(toSlot) then
                    error(("unable to clear slot %d to move items to!"):format(toSlot))
                end
            end
        end

        for _, inv in ipairs(getStorageInventories()) do
            for slot, item in pairs(inv.list()) do
                if item.name == itemName and (not itemNbt or item.nbt == itemNbt) then
                    remainingCount = remainingCount - inv.pushItems(name, slot, remainingCount, toSlot)
                    if remainingCount == 0 then
                        return true
                    end
                end
            end
        end

        return false, reaminingCount
    end

    local function brewPotion(job)
        if not job.basePotionId then error("no base potion for recipe " .. job.id) end

        local baseRecipe = getRecipeById(job.basePotionId)

        brewChain(stand, job.recipe)
        dispenseOrStore(job)
    end

    local function processJob(id, job)
        job.stand = stand

        while job.batchesRemaining > 0 do
            brewPotion(job)
            job.batchesRemaining = job.batchesRemaining - 1
        end

        deleteJob(id)
    end

    return function()
        while true do
            local id, job = popNextJob(name)

            if job then
                processJob(id, job)
            else
                sleep(0.5)
            end
        end
    end
end

local function startBrewJobs()
    local jobFuncs = {}

    for i, stand in ipairs(brewingStands) do
        local name = peripheral.getName(stand)

        table.insert(jobFuncs,
            safe(brewJob(name, stand),
                ("brewJob[%s]"):format(name),
                1
            )
        )
    end

    parallel.waitForAll(table.unpack(jobFuncs))
end

parallel.waitForAll(
    safe(drawMonitorLoop, "drawMonitorLoop", 1),
    safe(calcStockLoop, "calcStockLoop", 1),
    safe(monitorTouchLoop, "monitorTouchLoop", 1),
    safe(shopkLoop, "shopkLoop", 5),
    safe(startBrewJobs, "startBrewJobs", 1)
)

shopkClose()
