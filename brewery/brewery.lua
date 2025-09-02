local brewingStands = table.pack(peripheral.find("minecraft:brewing_stand"))

assert(brewingStands.n > 0, "no brewing stands found!")
print(string.format("Found %d brewing stands", brewingStands.n))

local recipes = require("/data/recipes")
local prices = require("/data/prices")
