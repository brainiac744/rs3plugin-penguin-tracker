-- Current Unix time in seconds, for "5m ago" labels.
--
-- The game sends CLOCK_TIME_DATE_MINUTES once a minute; it holds Unix time in
-- minutes (29873712 minutes = 19 Oct 2026). We remember the latest value from
-- VarTransmit, and also try os.time() in case it is available.

local Clock = {}

local lastMinutes = nil

-- Called from the VarTransmit handler with the variable's new value.
function Clock.onMinute(value)
    if type(value) == "number" then lastMinutes = value end
end

-- Returns Unix seconds, or nil if no clock is available yet.
function Clock.now()
    local ok, t = pcall(function() return os.time() end)
    if ok and type(t) == "number" then return t end
    if lastMinutes then return lastMinutes * 60 end
    return nil
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
