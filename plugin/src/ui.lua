-- The tracker's interface, in two parts:
--   * a movable, resizable window (built with the PrettyUI library) listing
--     all 13 penguins and the bear;
--   * a compact summary in the Plugins sidebar (the ribbon icon), with a
--     button to show or hide the window.
-- After building, View.update() just changes text and colours in place.

local Clock = require("src/clock")
local Settings = require("src/settings")

local View = {}

local ITEM_COUNT = 13
local ROW_H = 44          -- height of a row whose location fits on one line
local LOC_RIGHT = 64      -- space kept right of the location for the age
local MAX_LOC_LINES = 4   -- longest a location is allowed to wrap
local TOP_H = 28       -- summary strip at the top of the window
local PAD = 6
local WINDOW_W, WINDOW_H = 480, 440
local OK_W, EDIT_W = 30, 40         -- confirm / edit buttons on line 1
local SAVE_W, CANCEL_W = 44, 56     -- save / cancel buttons while editing
local MIN_LEN, MAX_LEN = 4, 150     -- location length limits (same as the Alt1 app)

-- Colours (taken from the Alt1 app's dark brown theme).
local function hex(rgb, alpha)
    return Vector4.new(((rgb >> 16) & 0xFF) / 255, ((rgb >> 8) & 0xFF) / 255,
        (rgb & 0xFF) / 255, alpha or 1.0)
end
local C = {
    divider  = 0x2E2A20,
    name     = 0xE8D8A8, ghostName = 0xB8C8A8, bearName = 0xC8982E,
    num      = 0x7A6E4A, location = 0xA09060, age = 0x5C5238, summary = 0xC8B87C,
    error    = 0xCC5566,
    pts      = { [1] = 0x6A8C3A, [2] = 0x9E8E5C, [3] = 0xB8902E },
}
local SPIED_ALPHA = 0.32 -- spied rows fade out, like the Alt1 app

-- Points never change week to week: penguins 1-5 = 1, 6-10 and 12 = 2,
-- 11 (the ghost) = 3, bear = 1. Used when the API has no data.
local FIXED_POINTS = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 2, 1 }

local function pointsFor(n, entry)
    return (entry and tonumber(entry.points)) or FIXED_POINTS[n] or 0
end

local function defaultName(n)
    if n == 11 then return "Ghost penguin" end
    if n == 13 then return "Bear" end
    return "Penguin " .. n
end

-- Look up a font by name, falling back to one we know exists.
local function font(name)
    local ok, f = pcall(function() return id.Font[name] end)
    if ok and f then return f end
    return id.Font.MUSEO_SANS_15PT_REGULAR
end

-- The font object for measuring text (nil if the API doesn't offer it, in
-- which case long locations are simply cut off on one line).
local measureFont = nil
local function getMeasureFont()
    if measureFont == nil then
        local ok, f = pcall(function() return config.Font.MUSEO_SANS_11PT_REGULAR end)
        measureFont = (ok and f) or false
    end
    return measureFont or nil
end

-- Height in pixels needed to show text wrapped at width, or nil if unknown.
local function wrappedHeight(text, width)
    local f = getMeasureFont()
    if not f or width <= 0 then return nil end
    local ok, h, lines = pcall(function()
        return f:GetStringHeightAndLineCount(text, width, f.baseline)
    end)
    if not ok or type(h) ~= "number" then return nil end
    if lines and lines > MAX_LOC_LINES then
        h = h - (lines - MAX_LOC_LINES) * f.baseline
    end
    return h
end

local function newText(parent)
    local t = ui.Text.new(parent)
    t.font = font("MUSEO_SANS_11PT_REGULAR")
    t.maxLines = 1
    t:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.CENTRE)
    return t
end

local function newButton(parent, label, onPress)
    local b = ui.Button.new(parent)
    b.label = label
    b.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
    b:Subscribe(ui.Hook.ONBUTTONPRESSED, function() onPress() end)
    return b
end

-- Current interface parts (nil when not shown).
local win = nil      -- { window, summary, rows }
local handlers = nil -- callbacks given to openWindow
local editing = {}   -- [n] = { input, save, cancel } while a row is being edited
local busy = {}      -- [n] = true while a confirm/update request is in flight
local rowError = {}  -- [n] = message shown in place of the age after a failure
local sidebar = nil  -- { summary, toggle }

-- Builds one row. Line 1: number, name, [OK] [Edit] buttons, points.
-- Line 2: location and age. The buttons only show for items the API lets
-- players update.
local function buildRow(parent, n, y)
    local row = ui.Layer.new(parent)
    row:SetPos(0, y)
    row:SetSize(0, ROW_H, 1.0, 0)

    local r = { layer = row, y = y }

    r.divider = ui.Rectangle.new(row)
    r.divider:SetPos(0, ROW_H - 1)
    r.divider:SetSize(0, 1, 1.0, 0)
    r.divider.fill = true
    r.divider.colour = hex(C.divider)
    r.height = ROW_H

    local half = ROW_H // 2
    local rightOfName = PAD + 40 + 4 + EDIT_W + 4 + OK_W + 4

    r.num = newText(row)
    r.num:SetPos(PAD, 0)
    r.num:SetSize(20, half)
    r.num.content = tostring(n)

    r.name = newText(row)
    r.name:SetPos(PAD + 20, 0)
    r.name:SetSize(-(PAD + 20 + rightOfName), half, 1.0, 0)

    r.ok = newButton(row, "OK", function() handlers.confirm(n) end)
    r.ok:SetPos(-(PAD + 40 + 4 + EDIT_W + 4 + OK_W), 1, 1.0, 0)
    r.ok:SetSize(OK_W, half - 2)

    r.edit = newButton(row, "Edit", function() View.startEdit(n) end)
    r.edit:SetPos(-(PAD + 40 + 4 + EDIT_W), 1, 1.0, 0)
    r.edit:SetSize(EDIT_W, half - 2)

    r.pts = newText(row)
    r.pts:SetPos(-(PAD + 40), 0, 1.0, 0)
    r.pts:SetSize(40, half)
    r.pts:AlignTo(ui.AlignMode.BOTTOMRIGHT, ui.AlignMode.CENTRE)

    -- The location may wrap onto several lines; View.relayout() sets its
    -- height. It's top-aligned so extra lines grow downwards.
    r.location = newText(row)
    r.location.maxLines = MAX_LOC_LINES
    r.location:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.TOPLEFT)
    r.location:SetPos(PAD + 20, half + 3)
    r.location:SetSize(-(PAD + 20 + LOC_RIGHT), ROW_H - half - 3, 1.0, 0)

    r.age = newText(row)
    r.age:SetPos(-(PAD + 60), half + 3, 1.0, 0)
    r.age:SetSize(60, ROW_H - half - 3)
    r.age:AlignTo(ui.AlignMode.BOTTOMRIGHT, ui.AlignMode.TOPLEFT)

    return r
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

-- Two references to the same UI component? (The API may hand back different
-- Lua objects for one component, so compare its IDs too.)
local function sameComponent(a, b)
    if rawequal(a, b) then return true end
    local ok, same = pcall(function()
        return a.interfaceID == b.interfaceID and a.staticID == b.staticID
            and a.dynamicID == b.dynamicID
    end)
    return ok and same
end

-- The window's outermost component: walk up from its content until the
-- parent is the game area. Its x, y, width and height are the window's.
local function findFrame(window, gameArea)
    local c = window.content
    for _ = 1, 12 do
        local parent = c and c.parent
        if parent == nil then return nil end
        if sameComponent(parent, gameArea) then return c end
        c = parent
    end
    return nil
end

local function toInt(v)
    return math.tointeger(math.floor(tonumber(v) or 0)) or 0
end

-- Keeps a saved position/size on screen (the game window may have changed
-- size since it was saved).
local function clampGeometry(g, gameArea)
    local gw, gh = 0, 0
    pcall(function() gw, gh = gameArea.width, gameArea.height end)
    local w = math.max(300, toInt(g.width))
    local h = math.max(160, toInt(g.height))
    local x, y = toInt(g.x), toInt(g.y)
    if gw > 0 and gh > 0 then
        w = math.min(w, gw)
        h = math.min(h, gh)
        x = math.max(0, math.min(x, gw - w)) -- keep the whole window on screen
        y = math.max(0, math.min(y, gh - h))
    end
    return { x = x, y = y, width = w, height = h }
end

-- Opens the window. h is a table of callbacks:
--   h.refresh()          Refresh button pressed
--   h.closing()          the player is closing the window (it still exists)
--   h.closed()           the player has closed the window
--   h.confirm(n)         OK pressed on row n
--   h.submit(n, text)    a new location was entered for row n
--   h.geometry           saved { x, y, width, height } to restore, or nil
-- Returns true on success, or false plus a reason.
function View.openWindow(h)
    handlers = h
    if win then
        win.window:Show()
        return true
    end
    if prettyui == nil then
        return false, "PrettyUI is not loaded (enable the PrettyUI plugin)"
    end
    local gameArea = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    if gameArea == nil then
        return false, "game area not available (not logged in?)"
    end

    -- Where to put it: the saved spot, or centred the first time.
    local place
    if h.geometry then
        local g = clampGeometry(h.geometry, gameArea)
        place = { x = g.x, y = g.y, xAnchor = 0, yAnchor = 0, width = g.width, height = g.height }
    else
        place = { x = -WINDOW_W // 2, y = -WINDOW_H // 2, xAnchor = 0.5, yAnchor = 0.5,
                  width = WINDOW_W, height = WINDOW_H }
    end

    local window = prettyui.Window.new(gameArea, {
        title = "Penguin Tracker",
        width = place.width, height = place.height,
        x = place.x, y = place.y, xAnchor = place.xAnchor, yAnchor = place.yAnchor,
        minWidth = 300, minHeight = 160,
        resizable = true,
        scrollable = true,
        contentHeight = TOP_H + ITEM_COUNT * ROW_H,
        onClose = function()
            h.closing() -- first, while the window can still report where it is
            win = nil
            editing = {}
            h.closed()  -- then, with the window gone (so the sidebar says "Show")
        end,
        destroyOnClose = true,
    })

    local content = window.content
    local w = { window = window, rows = {} }

    -- Summary strip with the refresh button.
    local top = ui.Layer.new(content)
    top:SetPos(0, 0)
    top:SetSize(0, TOP_H, 1.0, 0)

    local REFRESH_W = 68
    w.summary = newText(top)
    w.summary:SetPos(PAD, 0)
    w.summary:SetSize(-(PAD + REFRESH_W + 8), TOP_H, 1.0, 0)
    w.summary.colour = hex(C.summary)

    local refresh = newButton(top, "Refresh", function() h.refresh() end)
    refresh:SetPos(-(PAD + REFRESH_W), 3, 1.0, 0)
    refresh:SetSize(REFRESH_W, TOP_H - 6)

    for n = 1, ITEM_COUNT do
        w.rows[n] = buildRow(content, n, TOP_H + (n - 1) * ROW_H)
    end
    window:SetContentHeight(TOP_H + ITEM_COUNT * ROW_H)
    -- Narrower window = more wrapped lines, so re-measure on resize. The ID
    -- keeps PrettyUI's own resize handler in place.
    pcall(function()
        content:Subscribe(ui.Hook.ONRESIZE, "penguin-tracker", function() View.relayout() end)
    end)
    window:Show()

    -- Find the window's outer frame so we can read where it is later.
    -- PrettyUI's sizes might not match the frame exactly (e.g. if the title
    -- bar isn't counted), so note the difference now and allow for it when
    -- saving; otherwise the window would creep a little on every reopen.
    w.frame = findFrame(window, gameArea)
    w.offset = { x = 0, y = 0, width = 0, height = 0 }
    if w.frame then
        pcall(function()
            w.frame:UpdateLayout()
            if w.frame.width > 0 and place.xAnchor == 0 then
                w.offset = {
                    x = w.frame.x - place.x, y = w.frame.y - place.y,
                    width = w.frame.width - place.width, height = w.frame.height - place.height,
                }
            elseif w.frame.width > 0 then
                w.offset.width = w.frame.width - place.width
                w.offset.height = w.frame.height - place.height
            end
        end)
    end

    win = w
    return true
end

-- The window's current position and size in the values openWindow expects
-- (relative to the game area), or nil if it can't be read.
function View.geometry()
    if not win or not win.frame then return nil end
    local ok, g = pcall(function()
        local f, o = win.frame, win.offset
        if f.width <= 0 then return nil end
        return { x = f.x - o.x, y = f.y - o.y,
                 width = f.width - o.width, height = f.height - o.height }
    end)
    return ok and g or nil
end

-- Width the rows were last measured at, so View.checkResize() can tell when
-- the window has been resized.
local measuredWidth = nil

-- Width available to the location text, from the window's current size.
local function locationWidth()
    local w = nil
    pcall(function() win.window.content:UpdateLayout() end)
    pcall(function() w = win.window.content.width end)
    if not w or w <= 0 then pcall(function() w = win.window.contentWidth end) end
    if not w or w <= 0 then w = WINDOW_W - 24 end
    return w - (PAD + 20 + LOC_RIGHT)
end

-- Gives each row the height its location needs and stacks the rows.
-- Called after the text changes and whenever the window is resized.
function View.relayout()
    if not win then return end
    local ok, err = pcall(function()
        local half = ROW_H // 2
        local width = locationWidth()
        measuredWidth = width
        local y = TOP_H
        for n = 1, ITEM_COUNT do
            local r = win.rows[n]
            local textH = wrappedHeight(r.location.content or "", width)
            local bottomH = ROW_H - half
            if textH then bottomH = math.max(bottomH, textH + 4) end
            local h = half + bottomH
            if h ~= r.height then
                r.height = h
                r.layer:SetSize(0, h, 1.0, 0)
                r.divider:SetPos(0, h - 1)
                r.location:SetSize(-(PAD + 20 + LOC_RIGHT), bottomH - 3, 1.0, 0)
            end
            if r.y ~= y then
                r.y = y
                r.layer:SetPos(0, y)
            end
            y = y + h
        end
        win.window:SetContentHeight(y)
    end)
    if not ok then print("[penguins] layout failed: " .. tostring(err)) end
end

-- Re-measures the rows if the window width has changed since last time.
-- Called regularly from the plugin's Logic handler, because the resize
-- event alone doesn't always arrive after the new width is known.
function View.checkResize()
    if not win then return end
    local ok, width = pcall(locationWidth)
    if ok and width ~= measuredWidth then View.relayout() end
end

-- Closes and destroys the window without reporting it as player-closed.
function View.destroyWindow()
    if win then
        local w = win
        win = nil
        editing = {}
        measuredWidth = nil
        pcall(function() w.window:Destroy() end)
    end
end

function View.isWindowOpen()
    return win ~= nil
end

---------------------------------------------------------------------------
-- Editing a location
---------------------------------------------------------------------------

local finishEdit -- forward declaration

-- Replaces row n's location with a text box (Enter saves, Esc cancels).
function View.startEdit(n)
    if not win or editing[n] or busy[n] then return end
    local r = win.rows[n]
    local half = ROW_H // 2

    local e = {}
    e.input = ui.InputField.new(r.layer)
    e.input.stylesheetID = id.StyleSheet.INPUT_DEFAULT
    e.input:Setup(ui.TextContentVisibilityMode.VISIBLE, ui.InputFieldFilterMode.NONE, MAX_LEN)
    e.input.content = r.locationText or ""
    e.input.emptyText = "New location... (at least " .. MIN_LEN .. " characters)"
    -- The box sits slightly higher than the location line so it gets the
    -- full height of the bottom half of the row.
    local boxY, boxH = half - 2, ROW_H - half
    e.input:SetPos(PAD + 20, boxY)
    e.input:SetSize(-(PAD + 20 + 4 + SAVE_W + 4 + CANCEL_W + PAD), boxH, 1.0, 0)
    -- Use the same small font as the rows, with slim inner padding, so a
    -- full line of text fits inside the box.
    pcall(function() e.input.text.font = font("MUSEO_SANS_11PT_REGULAR") end)
    pcall(function() e.input.text.alignVertical = ui.AlignMode.CENTRE end)
    pcall(function() e.input.contentMargin = ui.Margin.new(4, 0, 4, 0) end)
    e.input:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, cause, newContents)
        if cause == ui.InputFieldActionResult.SUBMIT then
            View.saveEdit(n, newContents)
        elseif cause == ui.InputFieldActionResult.SUBMIT_ON_ESCAPE then
            finishEdit(n)
        end
    end)

    e.save = newButton(r.layer, "Save", function() View.saveEdit(n, e.input.content) end)
    e.save:SetPos(-(PAD + CANCEL_W + 4 + SAVE_W), boxY, 1.0, 0)
    e.save:SetSize(SAVE_W, boxH)

    e.cancel = newButton(r.layer, "Cancel", function() finishEdit(n) end)
    e.cancel:SetPos(-(PAD + CANCEL_W), boxY, 1.0, 0)
    e.cancel:SetSize(CANCEL_W, boxH)

    r.location.hidden = true
    r.age.hidden = true
    r.ok.hidden = true
    r.edit.hidden = true
    editing[n] = e
end

-- Removes the text box and shows the location again.
function finishEdit(n)
    local e = editing[n]
    if not e then return end
    editing[n] = nil
    for _, part in ipairs({ e.input, e.save, e.cancel }) do
        pcall(function() part:Destroy() end)
    end
    if win then
        pcall(function()
            local r = win.rows[n]
            r.location.hidden = false
            r.age.hidden = false
            r.ok.hidden = false   -- only editable rows can be edited
            r.edit.hidden = false
        end)
    end
end

-- Checks the text and hands it to the plugin to send.
function View.saveEdit(n, text)
    local e = editing[n]
    if not e then return end
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if #text < MIN_LEN then
        -- The hint only shows in an empty box, so clear the few characters typed.
        pcall(function()
            e.input.emptyText = "Too short - at least " .. MIN_LEN .. " characters"
            e.input.content = ""
        end)
        return
    end
    e.save.enabled = false
    e.cancel.enabled = false
    handlers.submit(n, text)
end

-- Called by the plugin when a confirm/update request starts (ok == nil) or
-- finishes (ok true/false, message on failure).
function View.requestState(n, ok, message)
    if ok == nil then
        busy[n] = true
        rowError[n] = nil
        return
    end
    busy[n] = nil
    if ok then
        rowError[n] = nil
        finishEdit(n)
    else
        rowError[n] = message or "failed"
        local e = editing[n]
        if e then
            pcall(function()
                e.save.enabled = true
                e.cancel.enabled = true
            end)
        end
    end
end

function View.isEditing(n)
    return editing[n] ~= nil
end

---------------------------------------------------------------------------
-- Sidebar (ribbon icon)
---------------------------------------------------------------------------

-- Builds the settings page (Plugin Hub > Manage > the plugin's settings
-- icon) as a scrolling PrettyUI view filling the given layer.
local function buildSettings(parent, top, width, height)
    local view = prettyui.SimpleView.new(parent, {
        x = 0, y = top, width = width, height = math.max(60, height - top),
    })

    -- Colour pickers open a small window of their own. It has to sit on a
    -- layer above the Plugin Hub, or the Hub hides it: the plugin build layer
    -- is drawn above most game and interface components. Failing that, use
    -- the settings page itself, which is at least above the settings view.
    local pickerParent = parent
    pcall(function()
        local top = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
        if top then pickerParent = top end
    end)

    local function checkbox(label, key, tooltip)
        view:AddCheckboxButton({
            { text = label, value = key, selected = Settings.get(key) == true, tooltip = tooltip },
        }, {
            onChange = function(_, _, _, selected) Settings.set(key, selected == true) end,
        })
    end

    local function colourRow(label, key)
        -- leave room on the right for the swatch and the scrollbar
        view:AddText({ text = label, width = math.max(80, width - 110) })
        view:AddColourPicker({
            value = Settings.get(key),
            alphaSlider = true,
            inline = true,
            windowTitle = label,
            windowParent = pickerParent,
            onChange = function(_, colour) Settings.set(key, colour) end,
        })
    end

    view:AddTitle("Highlight")
    checkbox("Box penguins near you", "highlight", "Draws a box around disguised penguins nearby")
    colourRow("Not spied", "colourUnspied")
    colourRow("Spied", "colourSpied")

    view:AddDivider({ marginTop = 4, marginBottom = 4 })
    view:AddTitle("Points cap (" .. Settings.POINTS_CAP .. ")")
    checkbox("Warn when points are over", "capWarning",
        "Unspied penguins use the warning colour when spying could waste points")
    view:AddTextField({
        text = tostring(Settings.get("capThreshold")),
        placeholder = tostring(Settings.get("capThreshold")),
        maxLength = 3,
        filterMode = ui.InputFieldFilterMode.NUMERIC,
        onChange = function(field, _, text)
            if tonumber(text) then Settings.set("capThreshold", Settings.clampThreshold(text)) end
        end,
        onSubmit = function(field, text)
            local n = Settings.clampThreshold(text)
            Settings.set("capThreshold", n)
            pcall(function() field:SetText(tostring(n), false) end)
        end,
    })
    colourRow("Warning colour", "colourCap")
    checkbox("Make Spy-on not the left-click option", "capSwapSpy",
        "Over the threshold, left-clicking a penguin won't spy on it (right-click still can)")
    return view
end

-- Builds the sidebar (the Plugins panel, via the ribbon icon) in the empty
-- layer the game gives us: a summary and a Show/Hide window button.
-- onToggle: the Show/Hide button was pressed.
function View.buildSidebar(root, onToggle)

    local s = {}
    s.summary = newText(root)
    s.summary:SetPos(PAD, 4)
    s.summary:SetSize(-2 * PAD, 40, 1.0, 0)
    s.summary.maxLines = 2
    s.summary.colour = hex(C.summary)

    s.toggle = newButton(root, "Show window", onToggle)
    s.toggle:SetPos(PAD, 50)
    s.toggle:SetSize(-2 * PAD, 26, 1.0, 0)

    sidebar = s
end

local settingsPage = nil -- the PrettyUI view on the settings page, if shown

-- Builds the settings page in the empty layer the game gives us.
function View.buildSettingsPage(root)
    View.closeSettingsPage()
    if prettyui == nil then
        print("[penguins] settings need the PrettyUI plugin enabled")
        return
    end
    pcall(function() root:UpdateLayout() end)
    local ok, view = pcall(buildSettings, root, 0, root.width or 400, root.height or 400)
    if ok then
        settingsPage = view
    else
        print("[penguins] could not build settings: " .. tostring(view))
    end
end

function View.closeSettingsPage()
    if settingsPage then
        pcall(function() settingsPage:Destroy() end)
        settingsPage = nil
    end
end

function View.closeSidebar()
    sidebar = nil
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

local function titleCase(s)
    return (tostring(s):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- Fills one row from the API entry (may be nil) and spy state.
local function updateRow(r, n, entry, isSpied)
    local kind = (entry and entry.type) or (n == 11 and "ghost") or (n == 13 and "bear") or "penguin"
    local a = isSpied and SPIED_ALPHA or 1.0
    local pts = pointsFor(n, entry)

    r.num.colour = hex(C.num, a)
    r.pts.content = pts .. "pt"
    r.pts.colour = hex(C.pts[pts] or C.pts[2], a)

    local name = entry and tostring(entry.name or defaultName(n)) or defaultName(n)
    if entry and kind ~= "ghost" and entry.disguise and entry.disguise ~= "" then
        name = name .. " - " .. titleCase(entry.disguise)
    end
    if isSpied then name = name .. "  (spied)" end
    r.name.content = name
    r.name.colour = hex(kind == "ghost" and C.ghostName or kind == "bear" and C.bearName or C.name, a)

    local loc = "No location data"
    if entry then
        loc = tostring(entry.location or "Unknown")
        r.locationText = entry.location and tostring(entry.location) or ""
        if entry.confinedTo and entry.confinedTo ~= entry.location then
            loc = loc .. "  (" .. tostring(entry.confinedTo) .. ")"
        end
    end
    r.location.content = loc
    r.location.colour = hex(C.location, a)

    if rowError[n] then
        r.age.content = "failed"
        r.age.colour = hex(C.error)
    else
        r.age.content = entry and Clock.ago(entry.lastUpdated) or ""
        r.age.colour = hex(C.age, a)
    end

    -- Confirm/edit only for items the API accepts updates for.
    local canEdit = entry ~= nil and entry.updatesAllowed == true
    r.ok.hidden = not canEdit or editing[n] ~= nil
    r.edit.hidden = not canEdit or editing[n] ~= nil
    r.ok.enabled = not busy[n]
    r.edit.enabled = not busy[n]
    if not canEdit and editing[n] then finishEdit(n) end
end

-- Refreshes everything shown. items may be nil (no data yet); spied is
-- { [n] = bool } or nil if spy progress can't be read; status is extra text
-- (e.g. an error); points is the unspent points balance (nil if unknown).
function View.update(items, spied, status, points)
    local spiedCount, weekPts = 0, 0
    if spied then
        for n = 1, ITEM_COUNT do
            if spied[n] then
                spiedCount = spiedCount + 1
                weekPts = weekPts + pointsFor(n, items and items[n])
            end
        end
    end
    local summary = spied and string.format("%d/%d spied - %d pts this week",
        spiedCount, ITEM_COUNT, weekPts) or "Spy progress unavailable"
    if points then
        summary = summary .. string.format(" - %d/%d banked", points, Settings.POINTS_CAP)
    end
    if status and status ~= "" then summary = summary .. " - " .. status end

    if win then
        local ok, err = pcall(function()
            win.summary.content = summary
            for n = 1, ITEM_COUNT do
                updateRow(win.rows[n], n, items and items[n], spied ~= nil and spied[n] == true)
            end
        end)
        if ok then View.relayout() end
        if not ok then
            print("[penguins] window update failed: " .. tostring(err))
            View.destroyWindow()
        end
    end

    if sidebar then
        local ok = pcall(function()
            sidebar.summary.content = summary
            sidebar.toggle.label = win and "Hide window" or "Show window"
        end)
        if not ok then sidebar = nil end -- sidebar was closed; rebuilt on next show
    end
end

return View
