local brewingStands = table.pack(peripheral.find("minecraft:brewing_stand"))

assert(brewingStands.n > 0, "No brewing stands found!")
print(string.format("Found %d brewing stands", brewingStands.n))

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
local shopsyncModem = s.peripheral("peripheral.shopsync", "modem")

local SHOPSYNC_CHANNEL = 9773

local BOT_NAME = "&9Twin&7Brewery"

-- declare some functions that we need sooner in the script (probably should just split into modules but im lazy)
local drawMonitor
local drawJobQueueUI
local getRecipeById
local getRecipeStock
local getRecipeCost
local addJob
local addJobs
local refundJob  -- refund function set by shopkLoop, used by job processor
local checkPendingRefunds  -- timer callback for batched refunds
local getPendingTimers  -- get pending timer mappings
local broadcastShopSync  -- ShopSync broadcast function

local client = nil
local kromerAddress = nil

-- ShopSync broadcast function
local function buildShopSyncData()
    if not kromerAddress then return nil end
    
    local items = {}
    
    -- Add all recipes as shop items
    for _, recipe in pairs(recipes) do
        if recipe.id ~= "water" then  -- Don't list water bottles
            local stock = getRecipeStock(recipe)
            local cost = getRecipeCost(recipe)
            
            -- Build potion item name based on type
            local itemName = "minecraft:potion"
            if recipe.potionType == "splash" then
                itemName = "minecraft:splash_potion"
            elseif recipe.potionType == "lingering" then
                itemName = "minecraft:lingering_potion"
            end
            
            table.insert(items, {
                prices = {
                    {
                        value = cost,
                        currency = "KRO",
                        address = kromerAddress,
                        requiredMeta = recipe.id,
                    }
                },
                item = {
                    name = itemName,
                    nbt = recipe.nbt,
                    displayName = recipe.displayName,
                    description = recipe.potionType ~= "normal" and (recipe.potionType .. " potion") or nil,
                },
                dynamicPrice = false,
                stock = math.floor(stock / 3) * 3,  -- Stock in terms of actual potions (batches of 3)
                madeOnDemand = true,  -- Potions are brewed on demand
                requiresInteraction = false,
            })
        end
    end

    local location = nil
    local x, y, z = gps.locate(2)  -- 2 second timeout
    if x then
        location = {
            coordinates = { math.floor(x), math.floor(y), math.floor(z) },
            dimension = "overworld",
        }
    end
    
    return {
        type = "ShopSync",
        version = 1,
        info = {
            name = "Twijn Brewery",
            description = "Automated potion brewery",
            owner = "Twijn",
            computerID = os.getComputerID(),
            multiShop = nil,
            software = {
                name = "cc-misc/brewery.lua",
                version = "1.0.0",
            },
            location = location,
        },
        items = items,
    }
end

broadcastShopSync = function()
    if not shopsyncModem then return end
    if not kromerAddress then return end
    
    local data = buildShopSyncData()
    if not data then return end
    
    shopsyncModem.open(SHOPSYNC_CHANNEL)
    shopsyncModem.transmit(SHOPSYNC_CHANNEL, os.getComputerID() % 65536, data)
    log.debug("Broadcasted ShopSync data with " .. #data.items .. " items")
end

-- shopk

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

    local function refund(address, amount, reason, originalTx)
        if amount <= 0 then return end
        local meta = "error=" .. reason
        if originalTx then
            meta = ("ref=%d;type=refund;original=%.03f;message=%s"):format(originalTx.id, originalTx.value, reason)
        end
        log.info(string.format("Refunding %.03f KRO to %s: %s", amount, address, reason))
        client.send({
            to = address,
            amount = amount,
            metadata = meta,
        })
    end

    -- Pending refunds batched by transaction ID
    local pendingRefunds = {}  -- { [txId] = { address, amount, reason, tx, timerId } }
    local pendingTimers = {}   -- { [timerId] = txId } - maps timer IDs to transaction IDs
    local REFUND_BATCH_DELAY = 3  -- seconds to wait before sending batched refund

    local function processPendingRefund(txId)
        local pending = pendingRefunds[txId]
        if pending and pending.amount > 0 then
            refund(pending.address, pending.amount, pending.reason, pending.tx)
        end
        -- Clean up timer mapping if it exists
        if pending and pending.timerId then
            pendingTimers[pending.timerId] = nil
        end
        pendingRefunds[txId] = nil
    end

    -- Expose refund for job processor to use on failures (batches refunds from same tx)
    refundJob = function(job, reason)
        if not job or not job.tx or not job.meta or not job.meta.payer then
            log.warn("Cannot refund job: missing transaction or payer info")
            return
        end
        local costPerBatch = getRecipeCost(job.recipe)
        local txId = job.tx.id

        -- Add to pending refunds for this transaction
        if not pendingRefunds[txId] then
            local timerId = os.startTimer(REFUND_BATCH_DELAY)
            pendingRefunds[txId] = {
                address = job.meta.payer,
                amount = 0,
                reason = reason or "Brewing failed",
                tx = job.tx,
                timerId = timerId,
            }
            pendingTimers[timerId] = txId
        end
        pendingRefunds[txId].amount = pendingRefunds[txId].amount + costPerBatch
        -- Update reason to show count if multiple
        local batchCount = math.floor(pendingRefunds[txId].amount / costPerBatch + 0.5)
        if batchCount > 1 then
            pendingRefunds[txId].reason = string.format("%s (%d batches)", reason or "Brewing failed", batchCount)
        end
    end

    -- Process a specific timer's refund (exposed globally)
    checkPendingRefunds = function(timerId)
        if timerId and pendingTimers[timerId] then
            local txId = pendingTimers[timerId]
            processPendingRefund(txId)
        end
    end

    -- Get the pending timers table (exposed for the timer loop)
    getPendingTimers = function()
        return pendingTimers
    end

    local function sendChange(address, amount, originalTx)
        if amount <= 0 then return end
        local meta = ("ref=%d;type=change;original=%.03f"):format(originalTx.id, originalTx.value)
        log.info(string.format("Sending %.03f KRO change to %s", amount, address))
        client.send({
            to = address,
            amount = amount,
            metadata = meta,
        })
    end

    client.on("transaction", function(tx)
        if tx.to ~= kromerAddress then return end
        if tx.value == 0 or tx.from == tx.to then return end -- catch the weird things somehow still allowed by Kromer

        -- Find the first valid recipe in metadata
        local recipe = nil
        for _, meta in pairs(tx.meta.values) do
            recipe = getRecipeById(meta)
            if recipe then break end
        end

        -- No valid recipe found in metadata
        if not recipe then
            local attemptedMeta = tx.meta.values[1] or "(none)"
            log.warn(string.format("Invalid recipe '%s' in transaction from %s, refunding %.03f KRO", attemptedMeta, tx.from, tx.value))
            refund(tx.from, tx.value, "Invalid potion type: " .. attemptedMeta, tx)
            return
        end

        -- Calculate cost and batches
        -- Add small epsilon to handle floating point precision issues (e.g., 0.150 / 0.150 = 0.9999999)
        local costPerBatch = getRecipeCost(recipe)
        local batches = math.floor((tx.value / costPerBatch) + 0.0001)

        -- Insufficient payment for even one batch
        if batches <= 0 then
            log.warn(string.format("Insufficient payment from %s: %.03f KRO for %s (min %.03f KRO)", tx.from, tx.value, recipe.displayName, costPerBatch))
            refund(tx.from, tx.value, string.format("Insufficient: need %.03f KRO for %s", costPerBatch, recipe.displayName), tx)
            return
        end

        -- Check stock availability
        local availableStock = getRecipeStock(recipe)
        local maxBatches = math.floor(availableStock / 3) -- Each batch produces 3 potions

        if maxBatches <= 0 then
            log.warn(string.format("Out of stock for %s, refunding %s", recipe.displayName, tx.from))
            refund(tx.from, tx.value, "Out of stock: " .. recipe.displayName, tx)
            return
        end

        -- Limit batches to available stock
        if batches > maxBatches then
            local excessBatches = batches - maxBatches
            local excessAmount = excessBatches * costPerBatch
            batches = maxBatches
            log.info(string.format("Limited order to %d batches due to stock, refunding %.03f KRO", maxBatches, excessAmount))
            refund(tx.from, excessAmount, string.format("Partial stock: only %d batches available", maxBatches), tx)
        end

        -- Calculate change
        local totalCost = batches * costPerBatch
        local change = tx.value - totalCost

        -- Add individual jobs for each batch (allows parallel brewing)
        log.info(string.format("Received payment of %.03f KRO from %s for %d batch(es) of %s", tx.value, tx.from, batches, recipe.displayName))
        addJobs(recipe, tx, batches, { payer = tx.from })

        -- Send change if any
        if change > 0.001 then -- Small threshold to avoid dust
            sendChange(tx.from, change, tx)
        end
    end)

    client.on("ready", function()
        log.debug("Connected to Kromer websocket. Finding self...")
        client.me(function(data)
            if data.is_guest or not data.address then
                error("you may not log in as guest! return a privatekey from data/config.lua")
            end
            kromerAddress = data.address.address
            log.info("Connected to Kromer as " .. kromerAddress)
            drawMonitor()
            -- ShopSync will broadcast from stockMaintenanceLoop after 10 sec delay
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

function getRecipeById(id)
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

function getRecipeCost(recipe, carriedCost)
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

-- Get the minecraft item name for a potion based on its type
local function getPotionItemName(potionType)
    if potionType == "splash" then
        return "minecraft:splash_potion"
    elseif potionType == "lingering" then
        return "minecraft:lingering_potion"
    else
        return "minecraft:potion"
    end
end

local cachedItems = nil
local function getAllItems(forceRefresh)
    if cachedItems and not forceRefresh then return cachedItems end

    local items = {}
    for _, chest in ipairs(table.pack(peripheral.find("inventory"))) do
        for slot, item in pairs(chest.list()) do
            local key = item.name

            -- Handle all potion types (normal, splash, lingering)
            if item.name == "minecraft:potion" or item.name == "minecraft:splash_potion" or item.name == "minecraft:lingering_potion" then
                local detail = chest.getItemDetail(slot)
                if detail and detail.potion then
                    -- Determine potionType from item name
                    local potionType = "normal"
                    if item.name == "minecraft:splash_potion" then
                        potionType = "splash"
                    elseif item.name == "minecraft:lingering_potion" then
                        potionType = "lingering"
                    end
                    key = getPotionKey(detail.potion, potionType)
                end
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

function getRecipeStock(recipe, maxStock)
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

local JOB_STATUS = {
    PENDING = "pending",
    BREWING = "brewing",
    DISPENSING = "dispensing",
    COMPLETE = "complete",
    FAILED = "failed",
}

function addJob(recipe, tx, meta)
    local id = nextId
    jobQueue[id] = {
        id = id,
        recipe = recipe,
        tx = tx,
        lock = nil,
        status = JOB_STATUS.PENDING,
        statusMessage = "Waiting...",
        meta = meta or {},
        createdAt = os.epoch("utc"),
    }

    nextId = nextId + 1
    return id
end

-- Helper to add multiple jobs (one per batch) and update monitor once
addJobs = function(recipe, tx, quantity, meta)
    local ids = {}
    for i = 1, quantity do
        local id = addJob(recipe, tx, meta)
        table.insert(ids, id)
    end
    drawMonitor()
    return ids
end

local function updateJobStatus(id, status, message)
    if jobQueue[id] then
        jobQueue[id].status = status
        if message then
            jobQueue[id].statusMessage = message
        end
        drawMonitor()
    end
end

local function deleteJob(id)
    jobQueue[id] = nil
    drawMonitor()
end

local function getJobCount()
    local count = 0
    for _ in pairs(jobQueue) do
        count = count + 1
    end
    return count
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
local showingJobQueue = false  -- Must be declared before drawMonitor references it

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

    -- Show job queue UI when toggled on
    if showingJobQueue then
        drawJobQueueUI()
        return
    end

    -- Reset toggle when no jobs
    if getJobCount() == 0 then
        showingJobQueue = false
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
        local costStr = tostring(cost) .. " KRO"
        local quantityStr = "x" .. tostring(quantity)
        mon.setCursorPos(startX + 1, sy + 2)
        mon.write(quantityStr .. string.rep(".", columnWidth - #costStr - #quantityStr - 2) .. costStr)
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

    -- Show job queue indicator if there are active jobs
    local jobCount = getJobCount()
    if jobCount > 0 then
        setColor(colors.orange, colors.white)
        local jobIndicator = string.format(" %d Job%s Active - Touch to View ", jobCount, jobCount > 1 and "s" or "")
        mon.setCursorPos(1, 1)
        mon.write(jobIndicator)
    end
end

-- Job Queue UI Drawing
drawJobQueueUI = function()
    if not kromerAddress then return end

    setColor(colors.black)
    mon.setTextScale(0.9)
    mon.clear()
    mx, my = mon.getSize()

    -- Header
    setColor(colors.blue, colors.white)
    for x = 1, mx do
        mon.setCursorPos(x, 1)
        mon.write(" ")
        mon.setCursorPos(x, 2)
        mon.write(" ")
    end
    mon.setCursorPos(2, 1)
    mon.write("Job Queue - " .. getJobCount() .. " active job(s)")
    mon.setCursorPos(2, 2)
    mon.setTextColor(colors.lightGray)
    mon.write("Touch anywhere to return to menu")

    -- Column headers
    setColor(colors.gray, colors.white)
    for x = 1, mx do
        mon.setCursorPos(x, 3)
        mon.write(" ")
    end
    mon.setCursorPos(2, 3)
    mon.write("ID")
    mon.setCursorPos(7, 3)
    mon.write("Potion")
    mon.setCursorPos(24, 3)
    mon.write("Status")

    -- Job list
    local row = 4
    local sortedJobs = {}
    for _, job in pairs(jobQueue) do
        table.insert(sortedJobs, job)
    end
    table.sort(sortedJobs, function(a, b) return a.id < b.id end)

    for _, job in ipairs(sortedJobs) do
        if row > my - 1 then break end

        local bgColor = colors.black
        local statusColor = colors.white

        if job.status == JOB_STATUS.BREWING then
            bgColor = colors.blue
            statusColor = colors.yellow
        elseif job.status == JOB_STATUS.DISPENSING then
            bgColor = colors.purple
            statusColor = colors.lime
        elseif job.status == JOB_STATUS.COMPLETE then
            bgColor = colors.green
            statusColor = colors.white
        elseif job.status == JOB_STATUS.FAILED then
            bgColor = colors.red
            statusColor = colors.white
        end

        setColor(bgColor, colors.white)
        for x = 1, mx do
            mon.setCursorPos(x, row)
            mon.write(" ")
        end

        mon.setCursorPos(2, row)
        mon.write(string.format("#%d", job.id))

        mon.setCursorPos(7, row)
        local potionName = job.recipe.displayName or "Unknown"
        if #potionName > 15 then
            potionName = potionName:sub(1, 13) .. ".."
        end
        mon.write(potionName)

        mon.setCursorPos(24, row)
        mon.setTextColor(statusColor)
        mon.write(job.statusMessage or job.status)

        row = row + 1
    end

    -- Footer with return hint
    if getJobCount() == 0 then
        setColor(colors.black, colors.gray)
        mon.setCursorPos(math.floor(mx / 2) - 8, math.floor(my / 2))
        mon.write("No active jobs")
    end

    -- Address display at bottom
    setColor(colors.lightBlue, colors.black)
    for x = 1, mx do
        mon.setCursorPos(x, my)
        mon.write(" ")
    end
    mon.setCursorPos(2, my)
    mon.write("Pay to: " .. (kromerAddress or "loading..."))
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

        -- If showing job queue, touch returns to menu (if no jobs, or anywhere)
        if showingJobQueue then
            showingJobQueue = false
            drawMonitor()
        else
            -- Check if touching the job indicator (top row when jobs exist)
            local jobCount = getJobCount()
            if jobCount > 0 and y == 1 then
                showingJobQueue = true
                drawMonitor()
            else
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

local storageTypes = {
    "sc-goodies:diamond_barrel",
    "sc-goodies:shulker_box_diamond",
    "ender_storage",
}

local function isStorageType(name)
    local types = table.pack(peripheral.getType(name))
    for _, t1 in ipairs(types) do
        for __, t2 in pairs(storageTypes) do
            if t1 == t2 then return true end
        end
    end
    return false
end

local function getStorageInventories()
    local inventories = {}
    for _, name in pairs(peripheral.getNames()) do
        if isStorageType(name) then
            table.insert(inventories, peripheral.wrap(name))
        end
    end
    return inventories
end

local outputChest = s.peripheral("peripheral.output", "inventory")
-- Output chest for dispensing finished potions
local function getOutputInventory()
    return outputChest
end

local function brewJob(name, stand)
    -- Brewing stand slots:
    -- Slot 5: Blaze powder (fuel)
    -- Slot 4: Ingredient
    -- Slots 1, 2, 3: Potion bottles
    local FUEL_SLOT = 5
    local INGREDIENT_SLOT = 4
    local POTION_SLOTS = {1, 2, 3}

    local function itemsOut(fromSlot)
        for _, inv in ipairs(getStorageInventories()) do
            local moved = inv.pullItems(name, fromSlot)
            if moved and moved > 0 then
                if not stand.getItemDetail(fromSlot) then
                    return true
                end
            end
        end
        return not stand.getItemDetail(fromSlot)
    end

    local function itemsIn(toSlot, itemName, itemNbt, count)
        local remainingCount = count or 1

        local detail = stand.getItemDetail(toSlot)
        if detail then
            if detail.name == itemName and (not itemNbt or detail.nbt == itemNbt) then
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
                    local moved = inv.pushItems(name, slot, remainingCount, toSlot)
                    remainingCount = remainingCount - moved
                    if remainingCount <= 0 then
                        return true
                    end
                end
            end
        end

        return false, remainingCount
    end

    local function ensureFuel()
        -- Check if there's already blaze powder in the fuel slot
        local detail = stand.getItemDetail(FUEL_SLOT)
        if detail then
            -- If there's blaze powder, we're good (brewing stand has internal fuel meter)
            if detail.name == "minecraft:blaze_powder" then
                return true
            end
            -- If something else is in the fuel slot (shouldn't happen), remove it
            itemsOut(FUEL_SLOT)
        end

        -- Slot is empty, try to add blaze powder from storage
        for _, inv in ipairs(getStorageInventories()) do
            for slot, item in pairs(inv.list()) do
                if item.name == "minecraft:blaze_powder" then
                    local moved = inv.pushItems(name, slot, 1, FUEL_SLOT)
                    if moved and moved > 0 then
                        return true
                    end
                end
            end
        end

        -- Check if the slot now has blaze powder (in case it was already there)
        detail = stand.getItemDetail(FUEL_SLOT)
        if detail and detail.name == "minecraft:blaze_powder" then
            return true
        end

        return false
    end

    local function waitForBrewing()
        -- Wait for brewing to complete by checking if ingredient is consumed
        sleep(0.5) -- Initial delay
        local maxWait = 30 -- 30 seconds max
        local waited = 0
        while waited < maxWait do
            local ingredient = stand.getItemDetail(INGREDIENT_SLOT)
            if not ingredient then
                -- Brewing complete (ingredient consumed)
                sleep(0.5) -- Small delay to ensure potions are ready
                return true
            end
            sleep(0.5)
            waited = waited + 0.5
        end
        return false
    end

    local function clearPotionSlots()
        for _, slot in ipairs(POTION_SLOTS) do
            itemsOut(slot)
        end
    end

    local function loadBasePotions(recipe)
        -- Get the full recipe chain to find the base potion
        local baseRecipe = getRecipeById(recipe.basePotionId)
        if not baseRecipe then
            error("Cannot find base recipe: " .. tostring(recipe.basePotionId))
        end

        -- Determine the correct item name based on base recipe's potion type
        local potionName = getPotionItemName(baseRecipe.potionType)
        local potionNbt = baseRecipe.nbt

        -- Load 3 base potions into the brewing stand
        for _, slot in ipairs(POTION_SLOTS) do
            local success, remaining = itemsIn(slot, potionName, potionNbt, 1)
            if not success then
                return false, "Missing base potion: " .. baseRecipe.displayName
            end
        end
        return true
    end

    local function loadIngredient(recipe)
        local success, remaining = itemsIn(INGREDIENT_SLOT, recipe.ingredient, nil, 1)
        if not success then
            return false, "Missing ingredient: " .. getIngredientDisplayName(recipe.ingredient)
        end
        return true
    end

    -- Dispense to output chest (for customer purchases)
    local function dispenseToOutput()
        local outputInv, outputName = getOutputInventory()
        if not outputInv then
            log.warn("No output inventory found, storing in regular storage")
            clearPotionSlots()
            return true
        end

        for _, slot in ipairs(POTION_SLOTS) do
            local detail = stand.getItemDetail(slot)
            if detail then
                local moved = outputInv.pullItems(name, slot)
                if not moved or moved == 0 then
                    -- Fallback to regular storage
                    itemsOut(slot)
                end
            end
        end
        return true
    end

    -- Dispense to storage (for stock maintenance jobs)
    local function dispenseToStorage()
        clearPotionSlots()
        return true
    end

    local function buildRecipeChain(recipe)
        -- Build the chain of recipes needed to brew this potion
        local chain = {}
        local current = recipe
        while current and current.id ~= "water" do
            table.insert(chain, 1, current) -- Insert at beginning
            current = getRecipeById(current.basePotionId)
        end
        return chain
    end

    local function brewSingleStep(recipe, jobId, skipLoadBase)
        updateJobStatus(jobId, JOB_STATUS.BREWING, "Loading " .. recipe.displayName)

        -- Ensure we have fuel
        if not ensureFuel() then
            return false, "No blaze powder available"
        end

        -- Load base potions (skip if continuing a chain - potions already in stand)
        if not skipLoadBase then
            local success, err = loadBasePotions(recipe)
            if not success then
                return false, err
            end
        end

        -- Load ingredient
        local success, err = loadIngredient(recipe)
        if not success then
            return false, err
        end

        updateJobStatus(jobId, JOB_STATUS.BREWING, "Brewing " .. recipe.displayName)

        -- Wait for brewing to complete
        if not waitForBrewing() then
            return false, "Brewing timed out"
        end

        return true
    end

    local function brewChain(recipe, jobId)
        -- Build the full chain of recipes to brew
        local chain = buildRecipeChain(recipe)

        -- We need to check if we already have intermediate potions
        -- Start from the earliest step we don't have stock for
        -- But we must always brew the FINAL step (the requested recipe)
        local startIndex = 1
        for i = #chain - 1, 1, -1 do  -- Don't skip the final recipe
            local r = chain[i]
            local _, onHand = getRecipeStock(r)
            if onHand >= 3 then
                startIndex = i + 1
                break
            end
        end

        -- Clear potion slots first
        clearPotionSlots()

        -- If we can start from an intermediate step, load those potions
        if startIndex > 1 and startIndex <= #chain then
            local prevRecipe = chain[startIndex - 1]
            local potionName = getPotionItemName(prevRecipe.potionType)
            for _, slot in ipairs(POTION_SLOTS) do
                itemsIn(slot, potionName, prevRecipe.nbt, 1)
            end
        elseif startIndex == 1 then
            -- Load water bottles as the base
            local waterRecipe = getRecipeById("water")
            for _, slot in ipairs(POTION_SLOTS) do
                itemsIn(slot, "minecraft:potion", waterRecipe.nbt, 1)
            end
        end

        -- Brew each step in the chain
        for i = startIndex, #chain do
            local stepRecipe = chain[i]
            -- Skip loading base potions if this isn't the first step we're brewing
            -- (potions are already in the stand from previous step)
            local skipLoadBase = (i > startIndex)
            local success, err = brewSingleStep(stepRecipe, jobId, skipLoadBase)
            if not success then
                return false, err
            end

            -- If not the last step, leave potions in stand for next step
            if i < #chain then
                sleep(0.5) -- Brief pause between steps
            end
        end

        return true
    end

    local function processJob(id, job)
        job.stand = stand

        updateJobStatus(id, JOB_STATUS.BREWING, "Brewing...")

        local success, err = brewChain(job.recipe, id)
        if not success then
            updateJobStatus(id, JOB_STATUS.FAILED, err or "Brew failed")
            log.error("Job #" .. id .. " failed: " .. (err or "unknown error"))

            -- Queue refund for this batch (will be batched with others from same tx)
            if refundJob then
                refundJob(job, err or "Brewing failed")
            end

            sleep(2) -- Show failure status briefly
            deleteJob(id)
            return
        end

        updateJobStatus(id, JOB_STATUS.DISPENSING, "Dispensing...")
        
        -- Stock maintenance jobs go to storage, customer jobs go to output
        if job.meta and job.meta.isStockJob then
            dispenseToStorage()
        else
            dispenseToOutput()
        end

        -- Refresh item cache after brewing
        getAllItems(true)

        updateJobStatus(id, JOB_STATUS.COMPLETE, "Complete!")
        sleep(1) -- Show completion status briefly
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

-- Timer loop for processing batched refunds
local function refundTimerLoop()
    while true do
        local _, timerId = os.pullEvent("timer")
        -- Only process if this is one of our refund timers
        if checkPendingRefunds and getPendingTimers then
            local pendingTimers = getPendingTimers()
            if pendingTimers and pendingTimers[timerId] then
                checkPendingRefunds(timerId)
            end
        end
    end
end

-- Stock maintenance loop - keeps intermediate potions stocked
local STOCK_CHECK_INTERVAL = 30  -- seconds between stock checks

-- Count how many jobs are queued for a specific recipe (for stock maintenance calculations)
local function getQueuedBatchesForRecipe(recipeId)
    local count = 0
    for _, job in pairs(jobQueue) do
        if job.recipe and job.recipe.id == recipeId then
            count = count + 1
        end
    end
    return count
end

local function stockMaintenanceLoop()
    sleep(10)  -- Initial delay to let everything initialize
    
    while true do
        -- Refresh inventory cache
        getAllItems(true)
        
        -- Broadcast ShopSync data (also happens on inventory changes)
        broadcastShopSync()
        
        -- Check each recipe for keep requirements
        for _, recipe in pairs(recipes) do
            if recipe.keep and recipe.keep > 0 then
                local currentStock = getBrewedPotionStock(recipe.potion, recipe.potionType)
                
                -- Account for batches already in queue (each batch = 3 potions)
                local queuedBatches = getQueuedBatchesForRecipe(recipe.id)
                local pendingPotions = queuedBatches * 3
                local effectiveStock = currentStock + pendingPotions
                
                local deficit = recipe.keep - effectiveStock
                
                if deficit > 0 then
                    -- Calculate how many batches needed (each batch = 3 potions)
                    local batchesNeeded = math.ceil(deficit / 3)
                    
                    -- Check if we have the ingredients to brew
                    local canBrew = true
                    if recipe.ingredient then
                        local ingredientStock = getIngredientStock(recipe.ingredient)
                        if ingredientStock < batchesNeeded then
                            batchesNeeded = ingredientStock
                            if batchesNeeded == 0 then
                                canBrew = false
                            end
                        end
                    end
                    
                    if canBrew and batchesNeeded > 0 then
                        log.info(string.format("Stock maintenance: Queuing %d batch(es) of %s (current: %d, queued: %d, keep: %d)",
                            batchesNeeded, recipe.displayName, currentStock, queuedBatches, recipe.keep))
                        
                        -- Add stock jobs (no transaction, no payer - these are internal)
                        for i = 1, batchesNeeded do
                            addJob(recipe, nil, { isStockJob = true })
                        end
                        drawMonitor()
                    end
                end
            end
        end
        
        sleep(STOCK_CHECK_INTERVAL)
    end
end

parallel.waitForAll(
    safe(drawMonitorLoop, "drawMonitorLoop", 1),
    safe(calcStockLoop, "calcStockLoop", 1),
    safe(monitorTouchLoop, "monitorTouchLoop", 1),
    safe(shopkLoop, "shopkLoop", 5),
    safe(startBrewJobs, "startBrewJobs", 1),
    safe(refundTimerLoop, "refundTimerLoop", 1),
    safe(stockMaintenanceLoop, "stockMaintenanceLoop", 1)
)

shopkClose()
