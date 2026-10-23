-- Near the points cap, stops "Spy-on" being the left-click option on
-- penguins, so you don't spy (and lose the points) by accident. The option
-- is still there in the right-click menu. Off unless the player turns it on.
--
-- Uses Event.MiniMenuReady, where entries can be reordered with Swap. The
-- entries list is in reverse of the visible menu: the last entry is the top
-- of the right-click menu and the left-click option (checked in game).

local Settings = require("src/settings")
local Highlight = require("src/highlight")
local Log = require("src/log")

local Menu = {}

local EVENT_KEY = "penguin-tracker-menu"

local function isSpyOnPenguin(entry)
    return Highlight.spyOnTarget(entry) ~= nil
end

local function onReady(e)
    if not (Settings.get("capSwapSpy") and Highlight.nearCap()) then return end
    local ok, err = pcall(function()
        local menu = e.miniMenu
        local entries = menu.entries
        local count = #entries
        if count < 2 or not isSpyOnPenguin(entries[count]) then return end

        -- Swap in the nearest entry below that isn't Spy-on on a penguin
        -- (usually "Walk here"). With several penguins under the mouse,
        -- swapping with the next entry would just put another Spy-on on top.
        for i = count - 1, 1, -1 do
            if not isSpyOnPenguin(entries[i]) then
                menu:Swap(count, i)
                Log.debug("near the points cap: Spy-on is no longer the left-click option")
                return
            end
        end
    end)
    if not ok then Log.problem("menu swap failed: " .. tostring(err)) end
end

function Menu.start()
    Event.MiniMenuReady.Subscribe(EVENT_KEY, onReady)
end

function Menu.stop()
    Event.MiniMenuReady.Unsubscribe(EVENT_KEY)
end

return Menu
