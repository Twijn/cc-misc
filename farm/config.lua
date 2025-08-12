local s = require("lib/s")

-- These locations are where items will be sorted to
local chestLocations = {
    ["minecraft:wheat"] = "ender_storage_138",
    ["minecraft:wheat_seeds"] = "ender_storage_139",
    ["minecraft:beetroot"] = "ender_storage_140",
    ["minecraft:beetroot_seeds"] = "ender_storage_141",
    ["minecraft:carrot"] = "ender_storage_142",
    ["minecraft:potato"] = "ender_storage_143",
    ["minecraft:poisonous_potato"] = "ender_storage_144",
    ["minecraft:cooked_beef"] = "ender_storage_145",
    ["minecraft:leather"] = "ender_storage_146",
    ["minecraft:charcoal"] = settings.get("chest.fuel"),
    ["all"] = settings.get("chest.all"),
}

-- These locations are where items will be pulled from, and a stack of Charcoal
-- will be kept in the first slot for farming turtles to use
local farmOutputChests = {
    ["minecraft:chest_334"] = {},
    ["minecraft:chest_335"] = {},
    ["minecraft:chest_336"] = {},
    ["minecraft:chest_337"] = {},
    ["minecraft:chest_338"] = {},
}

-- These locations are where ALL items will be pulled from, good for
-- breeding inventories or other inventories you want cleaned.
local outputChests = {
    ["minecraft:hopper_65"] = {},
    ["minecraft:chest_362"] = {},
}

-- In general, you should NOT need to modify existing crop values below.
-- You may use this below to add more crops, if needed.
-- ["<name of the crop as it's placed down>"] = {
--  name = "Pretty Name",
--  cropName = "<name of the item crop that's given>",
--  seedName = "<name of the seed as an item>",
--  grownAge = "<value of the 'grown' state when fully grown>",
--  target = <target count to reach for the crop>
-- }
return {
    crops = {
        ["minecraft:wheat"] = {
            name = "Wheat",
            cropName = "minecraft:wheat",
            seedName = "minecraft:wheat_seeds",
            grownAge = 7,
            target = s.number("crop.target.wheat", 0, nil, 3072),
        },
        ["minecraft:beetroots"] = {
            name = "Beetroot",
            cropName = "minecraft:beetroot",
            seedName = "minecraft:beetroot_seeds",
            grownAge = 3,
            target = s.number("crop.target.beetroots", 0, nil, 512),
        },
        ["minecraft:carrots"] = {
            name = "Carrot",
            cropName = "minecraft:carrot",
            seedName = "minecraft:carrot",
            grownAge = 7,
            target = s.number("crop.target.carrot", 0, nil, 1024),
        },
        ["minecraft:potatoes"] = {
            name = "Potato",
            cropName = "minecraft:potato",
            seedName = "minecraft:potato",
            grownAge = 7,
            target = s.number("crop.target.potato", 0, nil, 2048),
        },
    },
    chestLocations = chestLocations,
    farmOutputChests = farmOutputChests,
    outputChests = outputChests,
}
