local attach = require("lib.attach") -- replace with your module path

-- ======= Test Utilities =======
local passCount, failCount = 0, 0

local function wait()
    print("\nPress Enter to continue...")
    read()
end

local function printHeader(title)
    local w = term.getSize()
    print("\n" .. string.rep("=", w))
    print("  " .. title)
    print(string.rep("=", w))
end

local function printSubHeader(title)
    print("\n--- " .. title .. " ---")
end

local function test(description, condition)
    if condition then
        print("[PASS] " .. description)
        passCount = passCount + 1
    else
        print("[FAIL] " .. description)
        failCount = failCount + 1
    end
end

local function testResult(description, success, message)
    if success then
        print("[PASS] " .. description)
        passCount = passCount + 1
    else
        print("[FAIL] " .. description .. (message and (" - " .. message) or ""))
        failCount = failCount + 1
    end
    return success
end

local function showEquipped()
    local left = turtle.getEquippedLeft()
    local right = turtle.getEquippedRight()
    print("  Left:  " .. (left and left.name or "(empty)"))
    print("  Right: " .. (right and right.name or "(empty)"))
end

local function showInventorySummary()
    local items = {}
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            items[#items + 1] = string.format("Slot %d: %s x%d", slot, item.name, item.count)
        end
    end
    if #items == 0 then
        print("  (inventory empty)")
    else
        for _, line in ipairs(items) do
            print("  " .. line)
        end
    end
end

-- ======= Module Info =======
printHeader("Attach Module Test Suite")
print("Module version: " .. (attach.VERSION or "unknown"))
print("\nCurrent equipped tools:")
showEquipped()
print("\nInventory:")
showInventorySummary()
wait()

-- ======= Test: API Passthrough =======
printHeader("API Passthrough Tests")
test("Module has dig function", type(attach.dig) == "function")
test("Module has digUp function", type(attach.digUp) == "function")
test("Module has digDown function", type(attach.digDown) == "function")
test("Module has attack function", type(attach.attack) == "function")
test("Module has forward function", type(attach.forward) == "function")
test("Module has turnLeft function", type(attach.turnLeft) == "function")
test("Module has select function", type(attach.select) == "function")
test("Module has wrap function", type(attach.wrap) == "function")
test("Module has find function", type(attach.find) == "function")
test("Module has setDefaultEquipped function", type(attach.setDefaultEquipped) == "function")
test("Module has setAlwaysEquipped function", type(attach.setAlwaysEquipped) == "function")
wait()

-- ======= Test: Unsafe Blocks =======
printHeader("Unsafe Block Protection Tests")
printSubHeader("Inspecting blocks around turtle")

local function testUnsafeBlock(direction, inspectFunc, digFunc, label)
    local success, data = inspectFunc()
    if success then
        print("  " .. label .. ": " .. data.name)
        local isUnsafe = false
        for _, unsafe in ipairs(attach._unsafeBlocks) do
            if data.name == unsafe then
                isUnsafe = true
                break
            end
        end
        if isUnsafe then
            local digSuccess, digMsg = digFunc()
            testResult(label .. " blocked unsafe dig", not digSuccess and digMsg == "Unsafe block")
        else
            print("  (not an unsafe block, skipping dig test)")
        end
    else
        print("  " .. label .. ": (no block)")
    end
end

testUnsafeBlock("front", turtle.inspect, attach.dig, "Front")
testUnsafeBlock("up", turtle.inspectUp, attach.digUp, "Up")
testUnsafeBlock("down", turtle.inspectDown, attach.digDown, "Down")
wait()

-- ======= Test: Tool Equipping =======
printHeader("Tool Equipping Tests")

printSubHeader("Testing dig (should equip pickaxe/axe/shovel)")
print("Before dig:")
showEquipped()
attach.dig()
print("After dig:")
showEquipped()
wait()

printSubHeader("Testing attack (should equip sword)")
print("Before attack:")
showEquipped()
attach.attack()
print("After attack:")
showEquipped()
wait()

-- ======= Test: Default/Always Equipped =======
printHeader("Default & Always Equipped Tests")

printSubHeader("Setting default equipped tools")
print("Setting left=minecraft:diamond_pickaxe, right=minecraft:diamond_shovel")
attach.setDefaultEquipped("minecraft:diamond_pickaxe", "minecraft:diamond_shovel")
test("Default equipped left set", attach._defaultEquipped.left == "minecraft:diamond_pickaxe")
test("Default equipped right set", attach._defaultEquipped.right == "minecraft:diamond_shovel")

printSubHeader("Setting always equipped tool")
print("Setting alwaysEquipped=minecraft:diamond_sword")
attach.setAlwaysEquipped("minecraft:diamond_sword")
test("Always equipped set", attach._alwaysEquipped == "minecraft:diamond_sword")

print("\nTriggering dig to test equip behavior:")
showEquipped()
attach.dig()
print("After dig:")
showEquipped()
wait()

-- Reset configuration
attach.setDefaultEquipped(nil, nil)
attach.setAlwaysEquipped(nil)

-- ======= Test: Modem Protection =======
printHeader("Modem Protection Tests")

local left = turtle.getEquippedLeft()
local right = turtle.getEquippedRight()
local hasModemEquipped = (left and left.name:lower():find("modem")) or
                         (right and right.name:lower():find("modem"))

if hasModemEquipped then
    print("Modem detected in equipped slot")
    print("Testing that modem is not replaced during equip operations...")
    
    local modemSide = (left and left.name:lower():find("modem")) and "left" or "right"
    local modemName = modemSide == "left" and left.name or right.name
    
    -- Try various operations that might trigger equipping
    attach.dig()
    attach.attack()
    
    local afterLeft = turtle.getEquippedLeft()
    local afterRight = turtle.getEquippedRight()
    local stillHasModem = (modemSide == "left" and afterLeft and afterLeft.name == modemName) or
                          (modemSide == "right" and afterRight and afterRight.name == modemName)
    
    testResult("Modem preserved after dig/attack operations", stillHasModem)
else
    print("No modem currently equipped, skipping modem protection test")
    print("(Equip a modem to test this functionality)")
end
wait()

-- ======= Test: Peripheral Functions =======
printHeader("Peripheral Tests")

printSubHeader("Scanning for peripherals")
local foundPeripherals = {}
for _, side in ipairs({"left", "right", "front", "back", "top", "bottom"}) do
    if peripheral.isPresent(side) then
        local pType = peripheral.getType(side)
        print("  " .. side .. ": " .. pType)
        foundPeripherals[#foundPeripherals + 1] = {side = side, type = pType}
    end
end

if #foundPeripherals == 0 then
    print("  (no peripherals found)")
else
    printSubHeader("Testing wrap on found peripherals")
    for _, p in ipairs(foundPeripherals) do
        local wrapped = attach.wrap(p.type, p.side)
        testResult("Wrap " .. p.type .. " on " .. p.side, wrapped ~= nil)
    end
end
wait()

printSubHeader("Testing find('modem')")
local modem = attach.find("modem")
if modem then
    testResult("Found and wrapped modem", true)
    print("  Modem methods: " .. table.concat((function()
        local methods = {}
        for k, _ in pairs(modem) do methods[#methods + 1] = k end
        return methods
    end)(), ", "):sub(1, 60) .. "...")
else
    print("No modem found in peripherals or inventory")
end
wait()

-- ======= Test: Movement (Optional) =======
printHeader("Movement Tests (Optional)")
print("These tests will move the turtle. Skip? (y/n)")
local skip = read():lower() == "y"

if not skip then
    printSubHeader("Testing forward/back")
    local fwdSuccess = attach.forward()
    testResult("Forward movement", fwdSuccess)
    if fwdSuccess then
        local backSuccess = attach.back()
        testResult("Back movement", backSuccess)
    end
    
    printSubHeader("Testing turn")
    testResult("Turn left", attach.turnLeft())
    testResult("Turn right", attach.turnRight())
    testResult("Turn right (return to original)", attach.turnRight())
    testResult("Turn left (return to original)", attach.turnLeft())
end
wait()

-- ======= Test Summary =======
printHeader("Test Summary")
print(string.format("Passed: %d", passCount))
print(string.format("Failed: %d", failCount))
print(string.format("Total:  %d", passCount + failCount))

if failCount == 0 then
    print("\n*** All tests passed! ***")
else
    print("\n*** Some tests failed. Review output above. ***")
end

print("\n=== Test Complete ===")
