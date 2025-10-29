local module = {}

function module.includes(table, object)
    for i,v in pairs(table) do
        if v == object then return true end
    end
    return false
end

function module.count(table)
    local count = 0
    for i,v in pairs(table) do
        count = count + 1
    end
    return count
end

function module.recursiveCopy(table)
    local newTable = {}
    for i,v in pairs(table) do
        if type(v) == "table" then
            newTable[i] = module.recursiveCopy(v)
        else
            newTable[i] = v
        end
    end
    return newTable
end

function module.recursiveEquals(t1, t2)
    for i,v1 in pairs(t1) do
        local v2 = t2[i]
        if type(v1) == "table" then
            if type(v2) == "table" then
                if not table.equals(v1, v2) then
                    return false
                end
            else
                return false
            end
        elseif v1 ~= v2 then
            return false
        end
    end
    return true
end

return module
