local dataDir = "data/"
fs.makeDir(dataDir)

return function(fileName)
    fileName = dataDir .. fileName

    local persistModule = {}
    local object = {}

    local function save()
        local f = fs.open(fileName, "w")
        f.write(textutils.serializeJSON(object))
        f.close()
    end

    if fs.exists(fileName) then
        local f = fs.open(fileName, "r")
        object = textutils.unserializeJSON(f.readAll())
        f.close()
    else
        save()
    end

    persistModule.set = function(key, value)
        object[key] = value
        save()
    end

    persistModule.unset = function(key)
        persistModule.set(key, nil)
    end

    persistModule.clear = function()
        object = {}
        save()
    end

    persistModule.setAll = function(obj)
        object = obj
        save()
    end

    persistModule.get = function(key)
        return object[key]
    end

    persistModule.getAll = function()
        return object
    end

    return persistModule
end
