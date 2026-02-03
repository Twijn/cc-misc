local config = require("config")
local items = require("items")
local shopk = require("lib.shopk")
local lamp = peripheral.wrap(config.lamp)
local monitors = {}
local dropper = peripheral.wrap(config.dropper)
local dropperRelay = peripheral.wrap(config.dropperRelay)
local modem = peripheral.wrap("modem_1290")
modem.open(54237)
monitors["left"] = peripheral.wrap(config.leftMonitor)
monitors["right"] = peripheral.wrap(config.rightMonitor)

local timer = -1
local xSize, ySize = monitors["right"].getSize()
local window1 = window.create(monitors["right"],1,1,xSize/2,ySize-1,false)
local window3 = window.create(monitors["right"],1,1,xSize/2,ySize-1,false)
local window2 = window.create(monitors["right"],xSize/2+1,1,xSize/2,ySize-1)

local state = {}
state.currentUser = nil
state.cart = {}
state.items = {}
state.cartData = {}
state.turtleStatus = nil
state.enabled = {}

local userData = settings.get("store.userData",{})

femRewardsDB = {}

-- libs
local mf = require("morefonts")
mf.setDefaultFontOptions({
    condense = true,
    font = "fonts/Scientifica-Bold",
})
local ail = require("abstractInvLib")
local DiscordHook = require("DiscordHook")
local success, hook = DiscordHook.createWebhook("https://discord.com/api/webhooks/1465747512303292447/_E4sRa_ogwp736StiaGHhMS4CnKs8i0ICBL6zMXo1Xda4rcSodLZiaFX2ZSty1kToEas")

local inv = ail({peripheral.find("inventory")})

local function saveData()
  settings.set("store.userData",userData)
  settings.save()
end

local function broadcastShopSync()
  local packet = {}
  packet.type = "ShopSync"
  packet.version = 1
  packet.info = {}
  packet.info.name = "OmniStore"
  packet.info.description = "Bulk purchase store that packages multiple types of items into shulkers."
  packet.info.owner = "Femcorp"
  packet.info.computerID = os.getComputerID()
  packet.info.software = {}
  packet.info.software.name = "OmniStore Software"

  packet.info.location = {}
  packet.info.location.coordinates = {129,65,-22}
  packet.info.location.description = "Northern spawn road, on the right"
  packet.info.location.dimension = "overworld"

  packet.items = {}

  for itemName,itemData in pairs(state.items) do
    local entry = {}
    entry.prices = {}
    entry.prices[1] = {}
    entry.prices[1].value = itemData.price
    entry.prices[1].currency = "KRO"
    entry.prices[1].address = "kfemstoreo"

    entry.item = {}
    entry.item.name = itemName
    entry.item.displayName = itemData.displayName

    entry.dynamicPrice = false
    entry.stock = itemData.count
    entry.madeOnDemand = true
    entry.requiresInteraction = true
    table.insert(packet.items,entry)
  end
  print("Transmitting shopsync")
  local h = fs.open("shopsync.lua","w")
  h.write(textutils.serialiseJSON(packet))
  h.close()
  modem.transmit(9773,os.getComputerID() % 65536,packet)
end

local function lightBlinkLoop()
  while true do
    for i=1,8 do
      lamp.setAnalogueOutput("front",i^1.3 - 1)
      sleep(0.05)
    end
    sleep(1)
    for i=1,4 do
      i = 5 - i
      lamp.setAnalogueOutput("front",i^2 - 1)
      sleep(0.05)
    end
    sleep(0.5)
  end
end

local function logout()
  state.currentUser = nil
  state.cartData = {}
  state.cart = {}
end

local function initiatePurchase()
  hook.send("Purchase started for " .. state.currentUser .. ". They have " .. state.cartData.shulkers .. " shulkers. Total price: " .. state.cartData.totalPrice)
  local publicModem = modem
  modem.transmit(54238,54237,{user = state.currentUser, action = "add",amount = math.floor(state.cartData.totalPrice * 10)})
  local modem = peripheral.wrap("top")
  --window1.setDisplay(false)
  modem.transmit(1,1,"shulker")
  userData[state.currentUser].shulkerCount = userData[state.currentUser].shulkerCount + 1
  saveData()
  sleep(0.5)
  --if state.turtleStatus == "OK" then
    local usedSlots = 0
    state.cartData.remainingShulkers = state.cartData.shulkers
    for itemName,item in pairs(state.cart) do
      print(itemName)
      repeat
        if usedSlots == 54 then
          modem.transmit(1,1,"dig")
          sleep(1)
          dropper.pullItems(config.fillTurtle,1)
          modem.transmit(1,1,"shulker")
          userData[state.currentUser].shulkerCount = userData[state.currentUser].shulkerCount + 1
          saveData()
          usedSlots = 0
          sleep(1)
          print("new shulker")
        end
        local toPush = 64
        if item.count < 64 then
          toPush = item.count
        end
        local count = inv.pushItems(config.fillTurtle,itemName,toPush)
        usedSlots = usedSlots + 1
        modem.transmit(1,1,"drop")
        item.count = item.count - count
        sleep(0.4)
      until item.count == 0
    end
  sleep(1)
  print("done, grabbing final shulker")
  modem.transmit(1,1,"dig")
  sleep(1)
  dropper.pullItems(config.fillTurtle,1)
  for i=1,state.cartData.shulkers do
    dropperRelay.setOutput("top",true)
    sleep(0.1)
    dropperRelay.setOutput("top",false)
    sleep(0.1)
  end
  logout()
  broadcastShopSync()
  inv.refreshStorage()
 -- end
end

local function afkTimer()
  while true do
    timer = timer - 1
    if timer == 0 then
      chatbox.tell(state.currentUser,"You have been automatically logged out due to inactivity",config.botName)
      logout()
    end
    sleep(1)
  end
end

local function chatboxLoop()
  while true do
    local event, user, command, args = os.pullEvent("command")

    if command == "omni" then
      if not userData[user] then
        userData[user] = {}
        userData[user].shulkerCount = 0
        saveData()
      end
      if args[1] == "test" and user == "ivcr" then
        initiatePurchase()
      elseif args[1] == "start" then
        if not state.enabled then
          chatbox.tell(user,"Sorry, OmniStore is currently unavailable due to a lack of shulkers. We are sorry for the inconvenience.",config.botName)
          hook.send("AAA we're out of shulkers pls help bwaaah :3 (you lost a customer btw)")
        elseif not state.currentUser then
          state.currentUser = user
          chatbox.tell(user,"You're logged in!",config.botName)
          timer = 120
        else
          chatbox.tell(user,"Another user is currently logged in, please wait!",config.botName)
        end
      elseif args[1] == "exit" then
        if state.currentUser == user then
          logout()
          chatbox.tell(user,"You have been logged out, thanks for checking us out!",config.botName)
        else
          chatbox.tell(user,"You need to be logged in to be able to exit the session",config.botName)
        end
      elseif args[1] == "select" then
        if state.currentUser == user then
          timer = 120
          if args[2] then
            local selected = false
            for itemName,item in pairs(state.items) do

              if item.selectName == args[2] then
                if args[3] and tonumber(args[3]) then

                  state.cart[itemName] = {}
                  state.cart[itemName] = item
                  if state.items[itemName].count >= tonumber(args[3]) then
                    state.cart[itemName].count = tonumber(args[3])
                    chatbox.tell(user,"Added " .. state.cart[itemName].count .. "x " .. state.cart[itemName].displayName .. " to cart!",config.botName)
                  else
                    chatbox.tell(user,"You cannot purchase more than is available",config.botName)
                  end
                  selected = true

                else
                  chatbox.tell(user,"Please select an amount",config.botName)
                end
              end
            end
            if not selected then
              chatbox.tell(user,"Please select a valid item",config.botName)
            end
          else
            chatbox.tell(user,"Please select a valid item",config.botName)
          end
        else
          chatbox.tell(user,"You need to be logged in to be able to select items",config.botName)
        end
      elseif args[1] == "scan" then
        chatbox.tell(user,"Rescanning!",config.botName)
        inv.refreshStorage()
        sleep(math.random(0,1))
        chatbox.tell(user,"Rescanning done.",config.botName)
      elseif args[1] == "info" then
        chatbox.tell(user,"Account info\nShulkers in balance: " .. userData[user].shulkerCount .. " shulkers.",config.botName)
      else
        chatbox.tell(user,"A Twijn and Femcorp Store\n\\omni start - Starts your session\n\\omni select (item) (amount) - Adds the item to your cart\n\\omni info - Shows info about your account\n\\omni scan - Rescans the inventory",config.botName)
      end
    end
  end
end

local function scanLoop()
  while true do
    for _,item in pairs(items) do
      state.items[item.name] = {}
      state.items[item.name].count = inv.getCount(item.name)
      state.items[item.name].price = item.price
      state.items[item.name].displayName = item.displayName
      state.items[item.name].selectName = item.selectName
    end

    if inv.getCount("sc-goodies:shulker_box_iron") < 9 then
      if state.enabled then
        hook.send("AAA we're out of shulkers pls help bwaaah :3")
      end
      state.enabled = false
    else
      state.enabled = true
    end
    broadcastShopSync()
    sleep(60)
  end
end

local client = nil
local function purchaseChecker()
  local address = "kfemstoreo"
  local running = true

  client = shopk({
    privatekey = config.pkey,
  })

  local function refund(to, amount, message, origTx)
    local metadata = "message=" .. message
    if origTx and origTx.id and origTx.value then
      metadata = string.format(
        "ref=%d;type=refund;original=%.2f;message=%s",
        origTx.id,
        origTx.value,
        message
      )
    end

    client.send({
      to = to,
      amount = amount,
      metadata = metadata,
    })
  end

  client.on("ready", function()
    client.me(function(result)
      if result.is_guest or not result.address then
        error("Invalid shopk login - guest account detected")
      end
      address = result.address.address
      print("ShopK logged in as " .. address)
    end)
  end)

  client.on("transaction", function(tx)
    if tx.to ~= address then return end
    if not state.cartData.totalPrice then return end

    print(string.format(
      "TX from %s: %.2f (need %.2f)",
      tx.from,
      tx.value,
      state.cartData.totalPrice
    ))

    if tx.value < state.cartData.totalPrice then
      refund(tx.from, tx.value, "Insufficient payment", tx)
      return
    end

    if tx.value > state.cartData.totalPrice then
      refund(tx.from, tx.value - state.cartData.totalPrice, "Change", tx)
    end

    initiatePurchase()
  end)

  client.run()
end

local function modemLoop()
  while true do
    local event, side, ch, rch, msg, dist = os.pullEvent("modem_message")
    if ch == 54237 and rch == 999 and math.floor(dist) == config.dbDistance then
      femRewardsDB = msg
    elseif ch == 1 and side == "top" then
      state.turtleStatus = msg
    end
  end
end

local function drawLoop()
  while true do
    local mon = monitors["left"]
    mon.setBackgroundColor(colors.black)
    mon.setTextScale(0.5)
    mon.setTextColor(colors.white)
    mon.clear()

    local xSize, ySize = mon.getSize()
    mon.setCursorPos(1,ySize)
    mon.setBackgroundColor(colors.orange)
    mon.clearLine()
    mon.write("Shulkers in stock: " .. inv.getCount("sc-goodies:shulker_box_iron"))

    mon.setBackgroundColor(colors.black)
    mf.writeOn(mon,"OmniStore",nil,2,{scale = 2, font = "fonts/BoldBash"})

    mf.writeOn(mon,"A Twijn and Femcorp Store",nil,7,{font = "fonts/BoldBash"})

    mf.writeOn(mon,"How it works",2,11,{font = mf.ccfont})
    mon.setCursorPos(2,15)
    mon.write("1. Start your session with ")
    mon.setTextColor(colors.blue)
    mon.write("\\omni start")
    mon.setTextColor(colors.gray)
    mon.setCursorPos(5,16)
    mon.write(" (note: you will be logged out when you leave the shop)")
    mon.setTextColor(colors.white)

    mon.setCursorPos(2,18)
    mon.write("2. Select your items using chatbox. They can be found on the right monitor.")

    mon.setCursorPos(5,19)
    mon.write("Use ")
    mon.setTextColor(colors.blue)
    mon.write("\\omni select (itemname) (amount)")
    mon.setTextColor(colors.white)
    mon.write(" to buy a specific item.")
    mon.setTextColor(colors.gray)

    mon.setCursorPos(5,20)
    mon.write(" (note: you can run the command again in order to select a different amount)")
    mon.setTextColor(colors.white)

    mon.setCursorPos(2,22)
    mon.write("3. Confirm and finalize your cart by paying the amount on screen to ")
    mon.setTextColor(colors.orange)
    mon.write("kfemstoreo")
    mon.setTextColor(colors.white)
    mon.write(".")

    mon.setCursorPos(2,24)
    mon.write("4. Your items will be packaged into shulkers and dispensed above the carpet.")

    mon.setCursorPos(2,26)
    mon.write("5. You can get your packaging fee back by returning the shulkers at the store.")
    -- RIGHT MONITOR --
    local mon = monitors["right"]
    mon.setBackgroundColor(colors.black)
    mon.setTextScale(0.5)
    mon.setTextColor(colors.white)
    mon.clear()

    local xSize, ySize = mon.getSize()
    mon.setCursorPos(1,ySize)
    mon.setBackgroundColor(colors.orange)
    mon.clearLine()

    if state.currentUser then
      window1.clear()
      mf.writeOn(window1,"Items in cart ",2,1)
      window1.setCursorPos(32,3)
      window1.write("Logged in as " .. state.currentUser)

      window1.setCursorPos(2,4)
      local i = 4

      local subtotal = 0
      local slots = 0
      for name,item in pairs(state.cart) do
        i = i + 1
        window1.setCursorPos(2,i)
        window1.write(item.count .. "x")
        window1.setCursorPos(10,i)
        window1.write(item.displayName)
        window1.setCursorPos(40,i)
        window1.write(item.price * item.count .. " KRO")
        subtotal = subtotal + item.price * item.count
        slots = slots + math.floor(item.count / 64 + 1)
        -- DO NOT ADD STUFF THAT STACKS LESS THAN 64 THE SLOT CALC WILL BREAK
      end
      state.cartData.subtotal = subtotal
      state.cartData.slots = slots
      state.cartData.shulkers = math.floor(slots / 54 + 1)

      state.cartData.bulkDiscount = math.floor(slots * 10) / 1000

      window1.setVisible(true)

      local xSize, ySize = window1.getSize()



      for i=2,50 do
        window1.setCursorPos(i,ySize-13)
        window1.write("-")
      end
      window1.setCursorPos(10,ySize-12)
      window1.write("Subtotal")
      window1.setCursorPos(40,ySize-12)
      window1.write(state.cartData.subtotal .. " KRO")

      window1.setCursorPos(2,ySize-11)
      window1.write(state.cartData.shulkers .."x")
      window1.setCursorPos(10,ySize-11)
      window1.write("Shulker ")
      window1.setTextColor(colors.gray)
      if state.cartData.slots == 1 then
        window1.write("(" .. state.cartData.slots .. " slot)")
      else
        window1.write("(" .. state.cartData.slots .. " slots)")
      end
      window1.setTextColor(colors.white)
      window1.setCursorPos(40,ySize-11)
      window1.write(state.cartData.shulkers * config.shulkerPrice .. " KRO")

      for i=2,50 do
        window1.setCursorPos(i,ySize-10)
        window1.write("-")
      end
      window1.setCursorPos(10,ySize-9)
      window1.write("Discounts")
      window1.setCursorPos(10,ySize-7)
      window1.write("Bulk Discount")
      window1.setCursorPos(40,ySize-7)
      window1.write(state.cartData.bulkDiscount .. " KRO")

      local interPrice = state.cartData.subtotal + state.cartData.shulkers * config.shulkerPrice - state.cartData.bulkDiscount
      local femRewardsDiscount = 0
      if femRewardsDB and femRewardsDB[state.currentUser] then
        window1.setCursorPos(10,ySize-6)
        window1.write("Femcorp Rewards ")
        window1.setTextColor(colors.gray)
        window1.write("(" .. femRewardsDB[state.currentUser].discount * 100 .. "%)")
        window1.setTextColor(colors.white)
        window1.setCursorPos(40,ySize-6)
        femRewardsDiscount = math.floor(femRewardsDB[state.currentUser].discount * interPrice * 100) / 100
        window1.write(femRewardsDiscount .. " KRO")
      end
      state.cartData.totalPrice = math.floor((interPrice - femRewardsDiscount) * 100) / 100
      for i=2,50 do
        window1.setCursorPos(i,ySize-5)
        window1.write("-")
      end
      window1.setCursorPos(10,ySize-4)
      window1.write("Total")
      window1.setCursorPos(40,ySize-4)
      window1.write(state.cartData.totalPrice .. " KRO")
      window1.setCursorPos(10,ySize-2)
      window1.write("/pay kfemstoreo " .. state.cartData.totalPrice)
    end

    window2.setVisible(false)
    window2.clear()


    mf.writeOn(window2,"Available items",2,1)
    window2.setCursorPos(2,4)
    local i = 4
    for name,item in pairs(state.items) do
      i = i + 1
      window2.setCursorPos(2,i)
      window2.write(item.count .. "x")
      window2.setCursorPos(10,i)
      window2.write(item.displayName)
      window2.setCursorPos(39,i)
      window2.write(item.price .. " KRO")

      window2.setCursorPos(49,i)
      window2.write(item.selectName)
    end

    window2.setVisible(true)
    sleep(0.2)
  end
end

local function closeLoop()
  term.setTextColor(colors.yellow)
  print("Press Q to exit!")
  term.setTextColor(colors.white)
  while true do
    local e, key = os.pullEvent("key_up")
    if key == keys.q then
      if client and client.close then
        client.close()
      end
      break
    end
  end
end

parallel.waitForAny(lightBlinkLoop,drawLoop,chatboxLoop,scanLoop,modemLoop,purchaseChecker,afkTimer,closeLoop)