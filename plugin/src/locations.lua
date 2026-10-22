-- Talks to the w60pengu.in API (the same one the Alt1 app uses):
--   GET  /locations        current locations for all 13 items
--   POST /locationConfirm  {"key": n}                 "still there"
--   POST /locationUpdate   {"key": n, "location": s}  report a new location
-- Needs the httpAccess permission and the "pengu" URL declared in plugin.json.

local json = require("src/json")

local Locations = {}

local function noPermission()
    return not Plugin.HasPermission(PluginPermissions.httpAccess)
end

-- Short reason for a failed request.
local function failure(req)
    if req.timedOut then return "timed out" end
    if req.cancelled then return "cancelled" end
    local msg = "HTTP " .. tostring(req.responseCode)
    if req.data and req.data ~= "" then msg = msg .. " " .. tostring(req.data):sub(1, 80) end
    if req.errorInfo and req.errorInfo ~= "" then msg = msg .. " " .. tostring(req.errorInfo) end
    return msg
end

-- Calls onDone(items) on success, or onDone(nil, message) on failure.
-- items is { [itemNumber] = entry }, where entry has the API's fields: name,
-- disguise, points, location, lastUpdated, updatesAllowed, type, confinedTo.
function Locations.fetch(onDone)
    if noPermission() then
        onDone(nil, "httpAccess permission not granted (try: ppr penguin-tracker)")
        return
    end

    local request = HTTPRequest.new(Plugin.urls.pengu, "/locations")
    request:Get(function(req)
        if not req.successful then
            onDone(nil, failure(req))
            return
        end

        local data, err = json.decode(req.data)
        if type(data) ~= "table" then
            onDone(nil, err or "unexpected response")
            return
        end

        -- The response is an object keyed "1".."13" plus "runedate".
        local items = {}
        for key, entry in pairs(data) do
            local n = tonumber(key)
            if n and type(entry) == "table" then items[n] = entry end
        end
        onDone(items)
    end)
end

-- Sends a JSON body to one of the POST endpoints; onDone(ok, message).
local function post(path, body, onDone)
    if noPermission() then
        onDone(false, "httpAccess permission not granted")
        return
    end
    local request = HTTPRequest.new(Plugin.urls.pengu, path)
    request:AddHeader("Content-Type", "application/json")
    request:Post(json.encode(body), function(req)
        if req.successful then
            onDone(true)
        else
            onDone(false, failure(req))
        end
    end)
end

-- Confirms item n is still at its listed location.
function Locations.confirm(n, onDone)
    post("/locationConfirm", { key = n }, onDone)
end

-- Reports a new location for item n.
function Locations.update(n, location, onDone)
    post("/locationUpdate", { key = n, location = location }, onDone)
end

return Locations
