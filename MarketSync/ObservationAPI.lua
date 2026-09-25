-- Public, versioned observation stream for companion addons.
MarketSync = MarketSync or {}
MarketSync.ObservationAPI = MarketSync.ObservationAPI or {}
local API = MarketSync.ObservationAPI
API.v1 = API.v1 or {}
local listeners = {}
local serial = 0

function API.v1.Register(callback)
    if type(callback) ~= "function" then return false end
    listeners[callback] = true
    return true
end

function API.v1.Unregister(callback)
    listeners[callback] = nil
end

function API.v1.HasListeners()
    return next(listeners) ~= nil
end

function API.v1.NewScanID(source)
    serial = serial + 1
    return string.format("%s-%d-%d", source or "local", time(), serial)
end

function API.v1.Emit(event)
    if type(event) ~= "table" then return end
    for callback in pairs(listeners) do
        local copy = {}
        for key, value in pairs(event) do copy[key] = value end
        local ok, err = pcall(callback, copy)
        if not ok and MarketSync.Debug then
            MarketSync.Debug("Observation callback failed: " .. tostring(err))
        end
    end
end
