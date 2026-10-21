-- Penguin Tracker
-- Shows this week's penguin and bear locations from w60pengu.in and marks the
-- ones you have already spied, read automatically from the game. Optionally
-- draws a box around disguised penguins near you, and warns when your
-- penguin points are near the cap. Settings: Plugin Hub > Manage > settings icon.
-- Open the window from the plugin's ribbon icon in the Plugins sidebar.

print("[penguins] starting")

local Spied = require("src/spied")
local Locations = require("src/locations")
local Clock = require("src/clock")
local View = require("src/ui")
local Highlight = require("src/highlight")
local Settings = require("src/settings")
local Menu = require("src/menu")

local EVENT_KEY = "penguin-tracker"
local CLOCK_VAR = "CLOCK_TIME_DATE_MINUTES" -- Unix time in minutes, sent once a minute
local REFRESH_TICKS = 50 * 30               -- Logic runs 50 times a second: 30 seconds
local OPEN_KEY = "windowOpen"               -- remembers whether the window was open
local GEOMETRY_KEY = "windowGeometry"       -- remembers where the window was and its size
local SAVE_DELAY_TICKS = 25                 -- save half a second after it stops moving
local ITEM_BITS = 0x1C0003FF                -- spy flags in PENG_SPY_SWITCH (see spied.lua)

local items = nil       -- latest locations from the API, keyed by item number
local status = ""       -- shown in the summary, e.g. a fetch error
local fetching = false  -- avoid overlapping requests
local lastFetchTick = nil

-- Whether the player wants the window open; saved between sessions.
local wantOpen = false
pcall(function() wantOpen = PersistentDB:GetBool(OPEN_KEY) == true end)

local function setWantOpen(value)
    wantOpen = value
    pcall(function() PersistentDB:SetBool(OPEN_KEY, value) end)
end

-- Last saved window position and size ({ x, y, width, height } or nil).
local savedGeometry = nil
pcall(function()
    local g = PersistentDB:GetStructuredData(GEOMETRY_KEY)
    if type(g) == "table" and g.width and g.height and g.x and g.y then savedGeometry = g end
end)

local lastSeen = nil     -- geometry at the last check
local changedTick = nil  -- when it last changed (nil = nothing unsaved)

local function sameGeometry(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height
end

-- Saves the window's position and size now, if they're known.
local function saveGeometry()
    local g = View.geometry()
    if g and not sameGeometry(g, savedGeometry) then
        savedGeometry = g
        pcall(function() PersistentDB:SetStructuredData(GEOMETRY_KEY, g) end)
    end
    changedTick = nil
end

-- Called regularly: saves shortly after the player stops dragging/resizing,
-- rather than on every movement.
local function trackGeometry(tick)
    local g = View.geometry()
    if g == nil then return end
    if not sameGeometry(g, lastSeen) then
        lastSeen = g
        changedTick = tick
    elseif changedTick and tick - changedTick >= SAVE_DELAY_TICKS then
        saveGeometry()
    end
end

-- Current spy flags, or nil if they can't be read yet.
local function currentSpied()
    local raw = Spied.readRaw()
    if raw == nil then return nil end
    return (Spied.decode(raw))
end

local function redraw()
    local spiedNow = currentSpied()
    local points = Spied.readPoints()
    Highlight.setSpied(spiedNow)
    Highlight.setPoints(points)
    View.update(items, spiedNow, status, points)
end

-- Settings changed in the sidebar: refresh what's shown, and look for
-- penguins straight away if the highlight was just turned on.
Settings.onChange(function(name, value)
    if name == "highlight" and value then Highlight.scan() end
    redraw()
end)

-- Fetch fresh locations, then redraw.
local function refresh()
    if fetching then return end
    fetching = true
    status = "updating..."
    redraw()
    Locations.fetch(function(newItems, _, err)
        fetching = false
        if newItems then
            items = newItems
            status = ""
        else
            status = "update failed"
            print("[penguins] location update failed: " .. tostring(err))
        end
        redraw()
    end)
end

-- OK pressed: tell the API the location is still right.
local function confirmLocation(n)
    View.requestState(n, nil)
    redraw()
    Locations.confirm(n, function(ok, err)
        if ok and items and items[n] then
            items[n].lastUpdated = Clock.now() or items[n].lastUpdated
        end
        if not ok then print("[penguins] confirm #" .. n .. " failed: " .. tostring(err)) end
        View.requestState(n, ok, err)
        redraw()
    end)
end

-- A new location was entered: send it, then show it straight away.
local function submitLocation(n, text)
    View.requestState(n, nil)
    redraw()
    Locations.update(n, text, function(ok, err)
        if ok and items and items[n] then
            items[n].location = text
            items[n].lastUpdated = Clock.now() or items[n].lastUpdated
        end
        if not ok then print("[penguins] update #" .. n .. " failed: " .. tostring(err)) end
        View.requestState(n, ok, err)
        redraw()
    end)
end

local function openWindow()
    local ok, err = View.openWindow({
        refresh = refresh,
        -- the player closed it with the window's close button
        closing = saveGeometry,
        closed = function()
            setWantOpen(false)
            redraw()
        end,
        confirm = confirmLocation,
        submit = submitLocation,
        geometry = savedGeometry,
    })
    if not ok then
        print("[penguins] could not open window: " .. tostring(err))
        return
    end
    setWantOpen(true)
    redraw()
end

local function toggleWindow()
    if View.isWindowOpen() then
        saveGeometry()
        View.destroyWindow()
        setWantOpen(false)
        redraw()
    else
        openWindow()
    end
end

-- Sidebar (ribbon icon) opened: build the summary and Show/Hide button.
Event.ContentLayerReady.Subscribe(EVENT_KEY, function(e)
    local ok, err = pcall(View.buildSidebar, e.component, toggleWindow)
    if not ok then
        print("[penguins] could not build sidebar: " .. tostring(err))
        return
    end
    redraw()
end)

-- Settings page opened (Plugin Hub > Manage > settings icon).
Event.SettingsLayerReady.Subscribe(EVENT_KEY, function(e)
    View.buildSettingsPage(e.component)
end)

-- Logging out or changing worlds removes the window; reopen it on return
-- if it was open before.
Event.GameStateChanged.Subscribe(EVENT_KEY, function(e)
    if e.newState == GameState.GAME then
        if wantOpen and not View.isWindowOpen() then openWindow() end
    else
        saveGeometry()
        View.destroyWindow()
        View.closeSidebar()
        View.closeSettingsPage()
        Highlight.reset()
    end
end)

-- Redraw when spy progress changes; keep the clock for "ago" labels.
Event.VarTransmit.Subscribe(EVENT_KEY, function(e)
    local name = e.var and e.var.configName
    if name == Spied.VAR_NAME then
        -- A new spy flag means a penguin (or the bear) was just spied.
        local old, new = math.tointeger(e.oldValue), math.tointeger(e.newValue)
        redraw() -- updates the spy flags the highlight uses
        if old and new and (new & ~old & ITEM_BITS) ~= 0 then
            Highlight.onSpied(Spied.itemsIn(new & ~old))
        end
    elseif name == Spied.POINTS_VAR_NAME then
        redraw() -- points changed (spied, or turned in)
    elseif name == CLOCK_VAR then
        Clock.onMinute(e.newValue)
        redraw()
    end
end)

-- Refresh locations every 30 seconds. Ten times a second, also keep wrapped
-- rows in step with the window width and note if the window has moved.
Event.Logic.Subscribe(EVENT_KEY, function(e)
    local tick = e.logicTick
    if tick % 5 == 0 then
        View.checkResize()
        trackGeometry(tick)
    end
    if tick % 10 == 0 then Highlight.scan() end -- nearby penguins, 5 times a second
    if lastFetchTick == nil or tick - lastFetchTick >= REFRESH_TICKS then
        lastFetchTick = tick
        refresh()
    end
end)

-- Draw the penguin boxes every frame (shapes only last one frame).
Event.Draw.Subscribe(EVENT_KEY, function()
    Highlight.draw()
end)

-- Near the points cap, optionally keep Spy-on off the left click.
Menu.start()

-- If we were enabled while already in game, restore the window now.
if wantOpen then openWindow() end

function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe(EVENT_KEY)
    Event.SettingsLayerReady.Unsubscribe(EVENT_KEY)
    Event.GameStateChanged.Unsubscribe(EVENT_KEY)
    Event.VarTransmit.Unsubscribe(EVENT_KEY)
    Event.Logic.Unsubscribe(EVENT_KEY)
    Event.Draw.Unsubscribe(EVENT_KEY)
    Menu.stop()
    saveGeometry()
    View.destroyWindow()
    View.closeSidebar()
    View.closeSettingsPage()
end
