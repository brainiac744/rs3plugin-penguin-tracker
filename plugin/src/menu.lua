-- Near the points cap, stops "Spy-on" being the left-click option on
-- penguins, so you don't spy (and lose the points) by accident. The option
-- is still there in the right-click menu. Off unless the player turns it on.
--
-- Uses Event.MiniMenuReady, where entries can be reordered with Swap. The
-- left-click option is the highest-priority entry; to avoid depending on
-- which end of the list that is, we look at "Walk here", which is always
-- the lowest priority: the default is at the opposite end from it.

local Settings = require("src/settings")
local Highlight = require("src/highlight")

local Menu = {}

local EVENT_KEY = "penguin-tracker-menu"
local reported = {}

local function report(msg)
    if not reported[msg] then
        reported[msg] = true
        print("[penguins] " .. msg)
    end
end

local function textOf(entry)
    local ok, t = pcall(function() return tostring(entry.verbText or "") end)
    return ok and t or ""
end

local function isSpyOnPenguin(entry)
    local ok, yes = pcall(function()
        if not textOf(entry):find("Spy", 1, true) then return false end
        local npc = entry.npcData and entry.npcData.entity
        return npc ~= nil and Highlight.isPenguin(npc)
    end)
    return ok and yes
end

local function onReady(e)
    if not (Settings.get("capSwapSpy") and Highlight.nearCap()) then return end
    local ok, err = pcall(function()
        local menu = e.miniMenu
        local entries = menu.entries
        local count = #entries
        if count < 2 then return end

        local walk = nil
        for i, entry in ipairs(entries) do
            if textOf(entry):find("Walk here", 1, true) then walk = i end
        end
        local default = (walk == 1) and count or (walk == count and 1 or count)
        local inward = (default == count) and (count - 1) or 2

        if isSpyOnPenguin(entries[default]) then
            menu:Swap(default, inward)
            report("near the points cap: Spy-on is no longer the left-click option")
        end
    end)
    if not ok then report("menu swap failed: " .. tostring(err)) end
end

function Menu.start()
    Event.MiniMenuReady.Subscribe(EVENT_KEY, onReady)
end

function Menu.stop()
    Event.MiniMenuReady.Unsubscribe(EVENT_KEY)
end

return Menu
