-- Current Unix time in seconds, for "5m ago" labels.
--
-- The game variable CLOCK_TIME_DATE_MINUTES holds Unix time in minutes
-- (29873712 = 19 Oct 2026). It's only sent while the in-game clock is shown
-- (once a minute), so we don't rely on it arriving: from the last value we
-- received, we keep counting with the game's logic ticks (a fixed 50 a
-- second). One reading is enough; with none at all, the time is unknown and
-- the labels are left blank.

local Clock = {}

Clock.VAR_NAME = "CLOCK_TIME_DATE_MINUTES"

local TICKS_PER_SECOND = 50

local baseMinutes = nil -- last clock value, in Unix minutes
local baseTick = nil    -- logic tick when it was received
local latestTick = nil  -- most recent logic tick

-- Called from the Logic handler every tick.
function Clock.onLogic(tick)
    latestTick = tick
end

-- Called from the VarTransmit handler with the variable's new value.
function Clock.onMinute(value)
    if type(value) == "number" and value > 0 then
        baseMinutes, baseTick = value, latestTick
    end
end

-- At start-up, try reading the variable directly so the labels don't have
-- to wait for the next update (it may still hold the last value sent).
local function readNow()
    for _, domain in ipairs({ "VarClient", "VarPlayer" }) do
        local ok, v = pcall(function() return var[domain][Clock.VAR_NAME].value end)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return nil
end

-- Returns Unix seconds, or nil if the time isn't known.
function Clock.now()
    if baseMinutes == nil then
        local v = readNow()
        if v == nil then return nil end
        baseMinutes, baseTick = v, latestTick
    end
    local seconds = baseMinutes * 60
    if baseTick == nil then
        baseTick = latestTick -- got the value before the first tick
    elseif latestTick then
        seconds = seconds + (latestTick - baseTick) // TICKS_PER_SECOND
    end
    return seconds
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
