local recipes = require("/data/recipes")
local prices = require("/data/prices")

local function filter(tbl, checkFunc)
    local result = {}
    for i,v in pairs(tbl) do
        if checkFunc(v) then
            table.insert(result, v)
        end
    end
    return result
end

local function count(tbl, checkFunc)
    return #filter(tbl, checkFunc)
end

local function checkCraft(recipe, iteration)
    if type(iteration) ~= "number" then iteration = 0 end
    if recipe.id == "water" then return iteration end

    local basePotions = filter(recipes, function(r) return r.id == recipe.basePotionId end)
    assert(#basePotions ~= 0, "can not craft " .. recipe.id)

    local ingredientPrices = filter(prices, function(p) return p.name == recipe.ingredient end)
    assert(#ingredientPrices ~= 0, "ingredient " .. recipe.ingredient .. " has no price for recipe " .. recipe.id)

    return checkCraft(basePotions[1], iteration + 1)
end

local maxIterations = 0
for i, recipe in pairs(recipes) do
    -- Ensure required properties exist
    assert(recipe.id ~= nil, "id is nil for index " .. i)
    assert(recipe.potion ~= nil, "potion is nil for id " .. recipe.id)
    assert(recipe.basePotionId ~= nil or recipe.id == "water", "basePotionId is nil for id " .. recipe.id)
    assert(recipe.ingredient ~= nil or recipe.id == "water", "ingredient is nil for id " .. recipe.id)
    assert(recipe.displayName ~= nil, "displayName is nil for id " .. recipe.id)
    assert(recipe.potionType ~= nil, "potionType is nil for id " .. recipe.id)
    assert(recipe.splash ~= nil, "splash is nil for id " .. recipe.id)

    -- Check if there are more than one with that ID
    local idCount = count(recipes, function(r) return r.id == recipe.id end)
    if idCount > 1 then
        error("More than one item with id ".. recipe.id .." exists!")
    end

    -- Confirm item is craftable
    local iterations = checkCraft(recipe)
    maxIterations = math.max(maxIterations, iterations)
end

print("Check completed. Max iterations: " .. maxIterations)
