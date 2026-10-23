-- Penguin Tracker
-- Shows this week's penguin and bear locations from w60pengu.in and marks the
-- ones you have already spied, read automatically from the game. Optionally
-- draws a box around disguised penguins near you, and warns when your
-- penguin points are near the cap.
--
-- Open the locations from the plugin's ribbon icon in the Plugins panel.
-- Settings: Plugin Hub > Manage > the plugin's settings icon.
--
-- This file wires everything together; the pieces are in src/:
--   spied.lua      reads spy progress and points from game variables
--   locations.lua  talks to the w60pengu.in API
--   highlight.lua  optional boxes around nearby penguins
--   menu.lua       optionally keeps Spy-on off the left click near the cap
--   settings.lua   saved settings
--   ui/            the locations window, Plugins panel and settings page

local Spied = require("src/spied")
local Locations = require("src/locations")
local Clock = require("src/clock")
local Highlight = require("src/highlight")
local Settings = require("src/settings")
local Menu = require("src/menu")
local Log = require("src/log")
local Common = require("src/ui/common")
local Window = require("src/ui/window")
local Sidebar = require("src/ui/sidebar")
local SettingsPage = require("src/ui/settings_page")

local EVENT_KEY = "penguin-tracker"
local REFRESH_TICKS = 50 * 30 -- Logic runs 50 times a second: 30 seconds
local OPEN_KEY = "windowOpen" -- PersistentDB: whether the window was open

local items = nil          -- latest locations from the API, keyed by item number
local status = ""          -- shown in the summary, e.g. a fetch error
local fetching = false     -- avoid overlapping requests
local lastFetchTick = nil  -- Logic tick of the last fetch (nil = never)
local currentTick = nil    -- latest Logic tick seen

-- Whether the player wants the window open; saved between sessions.
local wantOpen = false
pcall(function() wantOpen = PersistentDB:GetBool(OPEN_KEY) == true end)

local function setWantOpen(value)
    wantOpen = value
    pcall(function() PersistentDB:SetBool(OPEN_KEY, value) end)
end

-- Refresh everything shown from the current game state and locations.
local function redraw()
    local spied = Spied.current()
    local points = Spied.readPoints()
    Highlight.setSpied(spied)
    Highlight.setPoints(points)
    local summary = Common.summary(items, spied, points, status)
    Window.update(items, spied, summary)
    Sidebar.update(summary, Window.isOpen())
end

-- A setting changed: refresh what's shown, and look for penguins straight
-- away if the highlight was just turned on.
Settings.onChange(function(name, value)
    if name == "highlight" and value then Highlight.scan() end
    redraw()
end)

-- Fetch fresh locations, then redraw.
local function refresh()
    if fetching then return end
    fetching = true
    lastFetchTick = currentTick -- the Refresh button restarts the 30 second count
    status = "updating..."
    redraw()
    Locations.fetch(function(newItems, err)
        fetching = false
        if newItems then
            items = newItems
            status = ""
        else
            status = "update failed"
            Log.problem("location update failed: " .. tostring(err))
        end
        redraw()
    end)
end

-- After a confirm or update: show the change straight away on success.
local function afterRequest(n, ok, err, what, changes)
    if ok and items and items[n] then
        for k, v in pairs(changes) do items[n][k] = v end
        items[n].lastUpdated = Clock.now() or items[n].lastUpdated
    end
    if not ok then Log.problem(what .. " #" .. n .. " failed: " .. tostring(err)) end
    Window.requestState(n, ok, err)
    redraw()
end

-- OK pressed: tell the API the location is still right.
local function confirmLocation(n)
    Window.requestState(n, nil)
    redraw()
    Locations.confirm(n, function(ok, err) afterRequest(n, ok, err, "confirm", {}) end)
end

-- A new location was entered: send it.
local function submitLocation(n, text)
    Window.requestState(n, nil)
    redraw()
    Locations.update(n, text, function(ok, err)
        afterRequest(n, ok, err, "update", { location = text })
    end)
end

local function openWindow()
    local ok, err = Window.open({
        refresh = refresh,
        closed = function()
            setWantOpen(false)
            redraw()
        end,
        confirm = confirmLocation,
        submit = submitLocation,
    })
    if not ok then
        Log.problem("could not open window: " .. tostring(err))
        return
    end
    setWantOpen(true)
    redraw()
end

local function toggleWindow()
    if Window.isOpen() then
        Window.close()
        setWantOpen(false)
        redraw()
    else
        openWindow()
    end
end

-- Plugins panel opened (ribbon icon): summary and Show/Hide locations.
Event.ContentLayerReady.Subscribe(EVENT_KEY, function(e)
    local ok, err = pcall(Sidebar.build, e.component, toggleWindow)
    if not ok then
        Log.problem("could not build the Plugins panel: " .. tostring(err))
        return
    end
    redraw()
end)

-- Settings page opened.
Event.SettingsLayerReady.Subscribe(EVENT_KEY, function(e)
    SettingsPage.build(e.component)
end)

-- Logging out or changing worlds removes our interface; reopen the window
-- on return if it was open before.
Event.GameStateChanged.Subscribe(EVENT_KEY, function(e)
    if e.newState == GameState.GAME then
        if wantOpen and not Window.isOpen() then openWindow() end
    else
        Window.close()
        Sidebar.close()
        SettingsPage.close()
        Highlight.reset()
    end
end)

-- Game variables: spy progress, points and the clock.
Event.VarTransmit.Subscribe(EVENT_KEY, function(e)
    local name = e.var and e.var.configName
    if name == Spied.VAR_NAME then
        redraw() -- also updates the spy flags the highlight uses
        -- A newly set flag means a penguin (or the bear) was just spied.
        local old, new = math.tointeger(e.oldValue), math.tointeger(e.newValue)
        local newBits = old and new and (new & ~old & Spied.ITEM_BITS) or 0
        if newBits ~= 0 then Highlight.onSpied(Spied.itemsIn(newBits)) end
    elseif name == Spied.POINTS_VAR_NAME then
        redraw() -- points changed (spied, or turned in)
    elseif name == Clock.VAR_NAME then
        Clock.onMinute(e.newValue)
        redraw()
    end
end)

Event.Logic.Subscribe(EVENT_KEY, function(e)
    local tick = e.logicTick
    currentTick = tick
    Clock.onLogic(tick)
    if tick % 5 == 0 then Window.tick(tick) end     -- 10 times a second
    if tick % 10 == 0 then Highlight.scan() end     -- 5 times a second
    -- Locations are only shown in the window, so only fetch while it's open:
    -- every 30 seconds, and straight away when it's opened after longer.
    if Window.isOpen() and (lastFetchTick == nil or tick - lastFetchTick >= REFRESH_TICKS) then
        refresh()
    end
end)

-- Menu actions (left-click or right-click menu): the highlight remembers
-- which penguin you clicked Spy-on on, to tell which one you then spied.
Event.MiniMenuEntrySelected.Subscribe(EVENT_KEY, function(e)
    Highlight.onSelected(e.entry)
end)

-- The penguin boxes are redrawn every frame (shapes only last one frame).
Event.Draw.Subscribe(EVENT_KEY, function()
    Highlight.draw()
end)

Menu.start()

-- If we were enabled while already in game, restore the window now.
if wantOpen then openWindow() end

Log.debug("started")

function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe(EVENT_KEY)
    Event.SettingsLayerReady.Unsubscribe(EVENT_KEY)
    Event.GameStateChanged.Unsubscribe(EVENT_KEY)
    Event.VarTransmit.Unsubscribe(EVENT_KEY)
    Event.Logic.Unsubscribe(EVENT_KEY)
    Event.MiniMenuEntrySelected.Unsubscribe(EVENT_KEY)
    Event.Draw.Unsubscribe(EVENT_KEY)
    Menu.stop()
    Window.close()
    Sidebar.close()
    SettingsPage.close()
end
