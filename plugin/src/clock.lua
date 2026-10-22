-- Current Unix time in seconds, for "5m ago" labels.
--
-- The game variable CLOCK_TIME_DATE_MINUTES holds Unix time in minutes
-- (29873712 = 19 Oct 2026) and is sent once a minute; the plugin passes each
-- new value to Clock.onMinute. At start-up we also try to read its current
-- value so the labels don't have to wait for the first update.

local Clock = {}

Clock.VAR_NAME = "CLOCK_TIME_DATE_MINUTES"

local lastMinutes = nil

-- Called from the VarTransmit handler with the variable's new value.
function Clock.onMinute(value)
    if type(value) == "number" then lastMinutes = value end
end

-- Read the variable directly (used once, at start-up).
local function readNow()
    for _, domain in ipairs({ "VarClient", "VarPlayer" }) do
        local ok, v = pcall(function() return var[domain][Clock.VAR_NAME].value end)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return nil
end

-- Returns Unix seconds, or nil if the time isn't known yet.
function Clock.now()
    if lastMinutes == nil then lastMinutes = readNow() end
    return lastMinutes and lastMinutes * 60 or nil
end

-- "45s ago", "12m ago", "3h ago", "2d ago", or "" if unknown.
function Clock.ago(timestamp)
    local now = Clock.now()
    if type(timestamp) ~= "number" or now == nil then return "" end
    local sec = math.max(0, math.floor(now - timestamp))
    if sec < 60 then return sec .. "s ago" end
    if sec < 3600 then return (sec // 60) .. "m ago" end
    if sec < 86400 then return (sec // 3600) .. "h ago" end
    return (sec // 86400) .. "d ago"
end

return Clock
