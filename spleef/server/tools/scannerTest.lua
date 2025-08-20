local p = peripheral.find("manipulator")

assert(p ~= nil, "a manipulator is required")

while true do
    for i,entity in pairs(p.sense()) do
        if entity.key == "minecraft:player" and entity.name == "Twijn" then
            print("Sending message to " .. entity.name)
            chatbox.tell(entity.name, string.format("(%.2f, %.2f, %.2f)", entity.x, entity.y, entity.z))
        end
    end
    sleep(1)
end
