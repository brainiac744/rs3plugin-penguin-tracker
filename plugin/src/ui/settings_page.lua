-- The settings page (Plugin Hub > Manage > the plugin's settings icon),
-- built with PrettyUI. The game hands us an empty layer each time it's shown
-- (Event.SettingsLayerReady). Changes are saved straight away via Settings.
--
-- The game doesn't say when the page goes away, and colour picker windows
-- live outside it (see build), so they'd stay on screen after the Plugin Hub
-- closes. SettingsPage.tick watches for the page's interface unloading and
-- then destroys the view, which also destroys its pickers and their windows.

local Settings = require("src/settings")
local Log = require("src/log")

local SettingsPage = {}

local view = nil        -- the PrettyUI view while shown
local interfaceID = nil -- the interface the page was built in
local pendingThreshold = nil -- typed in the threshold box, not applied yet

local function build(parent, width, height)
    local v = prettyui.SimpleView.new(parent, { x = 0, y = 0, width = width, height = height })

    -- Colour pickers open a small window of their own, which must sit above
    -- the Plugin Hub or the Hub hides it: the plugin build layer is drawn
    -- above most game and interface components.
    local pickerParent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        or parent

    local function checkbox(label, key, tooltip)
        v:AddCheckboxButton({
            { text = label, value = key, selected = Settings.get(key) == true, tooltip = tooltip },
        }, {
            onChange = function(_, _, _, selected) Settings.set(key, selected == true) end,
        })
    end

    local function colourRow(label, key)
        -- leave room on the right for the swatch and the scrollbar
        v:AddText({ text = label, width = math.max(80, width - 110) })
        v:AddColourPicker({
            value = Settings.get(key),
            alphaSlider = true,
            inline = true,
            windowTitle = label,
            windowParent = pickerParent,
            onChange = function(_, colour) Settings.set(key, colour) end,
        })
    end

    v:AddTitle("Highlight")
    checkbox("Highlight penguins near you", "highlight", "Draws a box around disguised penguins nearby")
    colourRow("Not spied colour", "colourUnspied")
    colourRow("Spied colour", "colourSpied")

    v:AddTitle("Points Warning")
    checkbox("Warn when points are over", "capWarning",
        "Unspied penguins use the warning colour when spying could waste points")
    -- The threshold is applied on Enter, when the box loses focus, or when
    -- the page closes - not on every keystroke, where typing 245 would
    -- briefly set 2 and then 24 (flashing the warning colour).
    local function applyThreshold(field, text)
        local n = Settings.clampThreshold(text)
        pendingThreshold = nil
        Settings.set("capThreshold", n)
        field:SetText(tostring(n), false)
    end
    v:AddTextField({
        text = tostring(Settings.get("capThreshold")),
        placeholder = tostring(Settings.get("capThreshold")),
        maxLength = 3,
        filterMode = ui.InputFieldFilterMode.NUMERIC,
        onChange = function(field, reason, text)
            if reason == ui.InputFieldActionResult.SUBMIT_ON_FOCUS_LOSS then
                applyThreshold(field, text)
            elseif reason == ui.InputFieldActionResult.CONTENT_CHANGE then
                pendingThreshold = text
            end
        end,
        onSubmit = applyThreshold, -- Enter
    })
    colourRow("Warning colour", "colourCap")
    checkbox("Hide Spy-on option on penguins", "capSwapSpy",
        "Over the threshold, left-clicking a penguin won't spy on it (right-click still can)")
    return v
end

-- Builds the page in the given layer.
function SettingsPage.build(root)
    SettingsPage.close()
    if prettyui == nil then
        Log.problem("settings need the PrettyUI plugin enabled")
        return
    end
    root:UpdateLayout()
    local ok, result = pcall(build, root, root.width, root.height)
    if ok then
        view = result
        interfaceID = root.interfaceID
    else
        Log.problem("could not build settings: " .. tostring(result))
    end
end

function SettingsPage.close()
    -- A threshold typed without pressing Enter still counts.
    if tonumber(pendingThreshold) then
        Settings.set("capThreshold", Settings.clampThreshold(pendingThreshold))
    end
    pendingThreshold = nil
    if view then
        local ok, err = pcall(function() view:Destroy() end)
        if not ok then Log.problem("could not close settings: " .. tostring(err)) end
        view = nil
    end
end

-- Called regularly from the plugin's Logic handler. Closes the page once
-- its interface has been unloaded (the same check PrettyUI uses).
function SettingsPage.tick()
    if not view then return end
    local ok, loaded = pcall(function()
        return ui.Interfaces:GetInterface(interfaceID) ~= nil
    end)
    if not ok then
        Log.problem("can't tell if the settings page is still open: " .. tostring(loaded))
    elseif not loaded then
        Log.debug("settings page closed")
        SettingsPage.close()
    end
end

return SettingsPage
