local shopk = require("shopk")({
    privatekey = "testing123"
})

-- this will print all transactions received
-- shop.on will parse transaction metadata for you:
-- transaction.meta.values = all non-key values, useful for shops
-- transaction.meta.keys = all key-value pairs, useful for retrieving
-- "useruuid", "username", "return", and more
shopk.on("transaction", function(transaction)
    if transaction.to == "kquarryree" then
        -- do something!
    end
    print(textutils.serialize(transaction))
end)

-- send a message when ready!
shopk.on("ready", function()
    print("shopk.lua is ready!")

    shopk.send({
        to = "ks0d5iqb6p",
        amount = 0.02,
        metadata = "message=Test Transaction",
    }, function(d)
        -- handle output
        print(textutils.serialize(d))
    end)
end)

-- YOU MUST CALL RUN()!
-- This is where it listens to websocket events!
shopk.run()
