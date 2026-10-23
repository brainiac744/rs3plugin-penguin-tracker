-- The locations window: a movable, resizable PrettyUI window listing all 13
-- penguins and the bear, with confirm/edit buttons for reporting locations.
--
-- The window is built once when opened; Window.update() then just changes
-- text and colours. It remembers its own position and size between sessions.

local Common = require("src/ui/common")
local Items = require("src/items")
local Clock = require("src/clock")
local Log = require("src/log")

local Window = {}

local C, PAD, hex = Common.C, Common.PAD, Common.hex
local newText, newButton = Common.newText, Common.newButton

local ROW_H = 44          -- height of a row whose location fits on one line
local HALF = ROW_H // 2   -- line 1 (name) / line 2 (location) split
local LOC_RIGHT = 64      -- space kept right of the location for the age
local MAX_LOC_LINES = 4   -- longest a location is allowed to wrap
local TOP_H = 28          -- summary strip at the top of the window
local WINDOW_W, WINDOW_H = 480, 440
local MIN_W, MIN_H = 300, 160
local REFRESH_W = 68
local OK_W, EDIT_W = 28, 28         -- confirm / edit buttons on line 1
local PTS_W = 40                    -- points, right of the buttons
local ICON = 16                     -- size of the icon on each button
local SAVE_W, CANCEL_W = 44, 56     -- save / cancel buttons while editing
local MIN_LEN, MAX_LEN = 4, 150     -- location length limits (enforced by the API)

-- Built-in game sprites for the buttons (names from the community catalogue
-- at github.com/sereselene/rsprite, checked in game).
local ICON_OK = "RS3_CONTEXTUAL_INPUT_GREEN_CHECK_MARK"
local ICON_EDIT = "RS3_MENU_BTN_EDIT_NORMAL"
local ICON_EDIT_OVER = "RS3_MENU_BTN_EDIT_OVER"

local GEOMETRY_KEY = "windowGeometry" -- PersistentDB: last position and size
local SAVE_DELAY_TICKS = 25           -- save half a second after it stops moving

-- State of the open window (win is nil when closed).
local win = nil       -- { window, frame, offset, summary, rows }
local handlers = nil  -- callbacks given to Window.open
local editing = {}    -- [n] = { input, save, cancel } while row n is being edited
local busy = {}       -- [n] = true while a confirm/update request is in flight
local rowError = {}   -- [n] = message shown in place of the age after a failure
local measuredWidth = nil -- width the rows were last measured at

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

-- Places an icon centred on a button at (x, y) with size (w, h), where x is
-- measured from the right edge (like the buttons' own SetPos).
local function placeIcon(icon, x, y, w, h)
    if not icon then return end
    icon:SetPos(x + (w - ICON) // 2, y + (h - ICON) // 2, 1.0, 0)
    icon:SetSize(ICON, ICON)
end

-- Shows/hides and enables/disables a row's OK and Edit buttons and icons.
local function setRowButtons(r, visible, enabled)
    for _, part in ipairs({ r.ok, r.edit }) do
        part.hidden = not visible
        if enabled ~= nil then part.enabled = enabled end
    end
    for _, icon in ipairs({ r.okIcon, r.editIcon }) do
        if icon then
            icon.hidden = not visible
            if enabled ~= nil then icon.alpha = enabled and 1.0 or 0.4 end
        end
    end
end

-- Builds one row. Line 1: number, name, [OK] [Edit] buttons, points.
-- Line 2: location (may wrap) and age.
local function buildRow(parent, n, y)
    local row = ui.Layer.new(parent)
    row:SetPos(0, y)
    row:SetSize(0, ROW_H, 1.0, 0)

    local r = { layer = row, y = y, height = ROW_H }

    r.divider = ui.Rectangle.new(row)
    r.divider:SetPos(0, ROW_H - 1)
    r.divider:SetSize(0, 1, 1.0, 0)
    r.divider.fill = true
    r.divider.colour = hex(C.divider)

    r.num = newText(row)
    r.num:SetPos(PAD, 0)
    r.num:SetSize(20, HALF)
    r.num.content = tostring(n)
    r.num.colour = hex(C.num)

    -- Right-hand side of line 1, from the edge inwards: points, Edit, OK.
    local editX = -(PAD + PTS_W + 4 + EDIT_W)
    local okX = editX - 4 - OK_W
    local by, bh = 1, HALF - 2

    r.name = newText(row)
    r.name:SetPos(PAD + 20, 0)
    r.name:SetSize(okX - 4 - (PAD + 20), HALF, 1.0, 0)

    r.ok, r.okIcon = Common.newIconButton(row, "OK", ICON_OK, nil, function() handlers.confirm(n) end)
    r.ok:SetPos(okX, by, 1.0, 0)
    r.ok:SetSize(OK_W, bh)
    placeIcon(r.okIcon, okX, by, OK_W, bh)

    r.edit, r.editIcon = Common.newIconButton(row, "Edit", ICON_EDIT, ICON_EDIT_OVER,
        function() Window.startEdit(n) end)
    r.edit:SetPos(editX, by, 1.0, 0)
    r.edit:SetSize(EDIT_W, bh)
    placeIcon(r.editIcon, editX, by, EDIT_W, bh)

    r.pts = newText(row)
    r.pts:SetPos(-(PAD + PTS_W), 0, 1.0, 0)
    r.pts:SetSize(PTS_W, HALF)
    r.pts:AlignTo(ui.AlignMode.BOTTOMRIGHT, ui.AlignMode.CENTRE)

    -- Top-aligned, so extra wrapped lines grow downwards (see relayout).
    r.location = newText(row)
    r.location.maxLines = MAX_LOC_LINES
    r.location:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.TOPLEFT)
    r.location:SetPos(PAD + 20, HALF + 3)
    r.location:SetSize(-(PAD + 20 + LOC_RIGHT), ROW_H - HALF - 3, 1.0, 0)
    r.location.colour = hex(C.location)

    r.age = newText(row)
    r.age:SetPos(-(PAD + 60), HALF + 3, 1.0, 0)
    r.age:SetSize(60, ROW_H - HALF - 3)
    r.age:AlignTo(ui.AlignMode.BOTTOMRIGHT, ui.AlignMode.TOPLEFT)

    return r
end

local function titleCase(s)
    return (tostring(s):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

local finishEdit -- forward declaration (editing section below)

-- Fills one row from its API entry (may be nil) and spy state.
local function updateRow(r, n, entry, isSpied)
    local kind = (entry and entry.type)
        or (n == Items.GHOST and "ghost") or (n == Items.BEAR and "bear") or "penguin"
    local pts = Items.points(n, entry)

    r.pts.content = pts .. "pt"
    r.pts.colour = hex(C.pts[pts] or C.pts[2])

    local name = entry and tostring(entry.name or Items.defaultName(n)) or Items.defaultName(n)
    if entry and kind ~= "ghost" and entry.disguise and entry.disguise ~= "" then
        name = name .. " - " .. titleCase(entry.disguise)
    end
    -- "(spied)" as well as the colour, so it doesn't rely on colour alone.
    if isSpied then name = name .. "  (spied)" end
    r.name.content = name
    r.name.colour = hex(isSpied and C.spied
        or kind == "ghost" and C.ghostName or kind == "bear" and C.bearName or C.name)

    local loc = "No location data"
    if entry then
        loc = tostring(entry.location or "Unknown")
        r.locationText = entry.location and tostring(entry.location) or ""
        if entry.confinedTo and entry.confinedTo ~= entry.location then
            loc = loc .. "  (" .. tostring(entry.confinedTo) .. ")"
        end
    end
    r.location.content = loc

    if rowError[n] then
        r.age.content = "failed"
        r.age.colour = hex(C.error)
    else
        r.age.content = entry and Clock.ago(entry.lastUpdated) or ""
        r.age.colour = hex(C.age)
    end

    -- Confirm/edit only for items the API accepts updates for.
    local canEdit = entry ~= nil and entry.updatesAllowed == true
    setRowButtons(r, canEdit and editing[n] == nil, not busy[n])
    if not canEdit and editing[n] then finishEdit(n) end
end

---------------------------------------------------------------------------
-- Wrapping: each row is as tall as its location text needs
---------------------------------------------------------------------------

-- Height in pixels to show text wrapped at width (at most MAX_LOC_LINES).
local function wrappedHeight(text, width)
    local f = Common.MEASURE_FONT
    local h, lines = f:GetStringHeightAndLineCount(text, width, f.baseline)
    if lines > MAX_LOC_LINES then h = h - (lines - MAX_LOC_LINES) * f.baseline end
    return h
end

-- Width available to the location text at the window's current size.
local function locationWidth()
    win.window.content:UpdateLayout()
    return win.window.content.width - (PAD + 20 + LOC_RIGHT)
end

-- Gives each row the height its location needs and stacks the rows.
local function relayout()
    local ok, err = pcall(function()
        local width = locationWidth()
        measuredWidth = width
        local y = TOP_H
        for n = 1, Items.COUNT do
            local r = win.rows[n]
            local bottomH = ROW_H - HALF
            if width > 0 then
                bottomH = math.max(bottomH, wrappedHeight(r.location.content or "", width) + 4)
            end
            local h = HALF + bottomH
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
    if not ok then Log.problem("layout failed: " .. tostring(err)) end
end

---------------------------------------------------------------------------
-- Position and size, saved between sessions
---------------------------------------------------------------------------

local savedGeometry = nil -- { x, y, width, height } relative to the game area
pcall(function()
    local g = PersistentDB:GetStructuredData(GEOMETRY_KEY)
    if type(g) == "table" and g.width and g.height and g.x and g.y then savedGeometry = g end
end)
local lastSeen = nil      -- geometry at the last check
local changedTick = nil   -- when it last changed (nil = nothing unsaved)

-- Two references to the same UI component? (The API may hand back different
-- Lua objects for one component, so compare IDs.)
local function sameComponent(a, b)
    return rawequal(a, b) or (a.interfaceID == b.interfaceID
        and a.staticID == b.staticID and a.dynamicID == b.dynamicID)
end

-- PrettyUI has no position getter, so find the window's outermost
-- component (the child of the game area) and read x, y, width, height there.
local function findFrame(window, gameArea)
    local c = window.content
    for _ = 1, 12 do
        local parent = c.parent
        if parent == nil then return nil end
        if sameComponent(parent, gameArea) then return c end
        c = parent
    end
    return nil
end

local function toInt(v)
    return math.tointeger(math.floor(tonumber(v) or 0)) or 0
end

-- Keeps a saved position/size on screen (the game window may be smaller
-- than when it was saved).
local function clampGeometry(g, gameArea)
    local gw, gh = gameArea.width, gameArea.height
    local w = math.max(MIN_W, toInt(g.width))
    local h = math.max(MIN_H, toInt(g.height))
    local x, y = toInt(g.x), toInt(g.y)
    if gw > 0 and gh > 0 then
        w, h = math.min(w, gw), math.min(h, gh)
        x = math.max(0, math.min(x, gw - w))
        y = math.max(0, math.min(y, gh - h))
    end
    return { x = x, y = y, width = w, height = h }
end

-- The window's position and size in the values Window.open expects.
local function currentGeometry()
    if not win or not win.frame then return nil end
    local ok, g = pcall(function()
        local f, o = win.frame, win.offset
        if f.width <= 0 then return nil end
        return { x = f.x - o.x, y = f.y - o.y, width = f.width - o.width, height = f.height - o.height }
    end)
    return ok and g or nil
end

local function sameGeometry(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height
end

local function saveGeometry()
    local g = currentGeometry()
    if g and not sameGeometry(g, savedGeometry) then
        savedGeometry = g
        pcall(function() PersistentDB:SetStructuredData(GEOMETRY_KEY, g) end)
    end
    changedTick = nil
end

-- Saves shortly after the player stops dragging/resizing, not on every move.
local function trackGeometry(tick)
    local g = currentGeometry()
    if g == nil then return end
    if not sameGeometry(g, lastSeen) then
        lastSeen, changedTick = g, tick
    elseif changedTick and tick - changedTick >= SAVE_DELAY_TICKS then
        saveGeometry()
    end
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

-- Opens the window. h is a table of callbacks:
--   h.refresh()        Refresh button pressed
--   h.closed()         the player closed the window with its X
--   h.confirm(n)       OK pressed on row n
--   h.submit(n, text)  a new location was entered for row n
-- Returns true on success, or false plus a reason.
function Window.open(h)
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

    -- The saved spot, or centred the first time.
    local place
    if savedGeometry then
        local g = clampGeometry(savedGeometry, gameArea)
        place = { x = g.x, y = g.y, xAnchor = 0, yAnchor = 0, width = g.width, height = g.height }
    else
        place = { x = -WINDOW_W // 2, y = -WINDOW_H // 2, xAnchor = 0.5, yAnchor = 0.5,
                  width = WINDOW_W, height = WINDOW_H }
    end

    local window = prettyui.Window.new(gameArea, {
        title = "Penguin Tracker",
        width = place.width, height = place.height,
        x = place.x, y = place.y, xAnchor = place.xAnchor, yAnchor = place.yAnchor,
        minWidth = MIN_W, minHeight = MIN_H,
        resizable = true,
        scrollable = true,
        contentHeight = TOP_H + Items.COUNT * ROW_H,
        destroyOnClose = true,
        onClose = function()
            saveGeometry() -- while the window can still report where it is
            win, editing, measuredWidth = nil, {}, nil
            h.closed()     -- then, with it gone (so the sidebar says "Show")
        end,
    })

    local content = window.content
    local w = { window = window, rows = {} }

    -- Summary strip with the refresh button.
    local top = ui.Layer.new(content)
    top:SetPos(0, 0)
    top:SetSize(0, TOP_H, 1.0, 0)

    w.summary = newText(top)
    w.summary:SetPos(PAD, 0)
    w.summary:SetSize(-(PAD + REFRESH_W + 8), TOP_H, 1.0, 0)
    w.summary.colour = hex(C.summary)

    local refresh = newButton(top, "Refresh", function() h.refresh() end)
    refresh:SetPos(-(PAD + REFRESH_W), 3, 1.0, 0)
    refresh:SetSize(REFRESH_W, TOP_H - 6)

    for n = 1, Items.COUNT do
        w.rows[n] = buildRow(content, n, TOP_H + (n - 1) * ROW_H)
    end
    window:SetContentHeight(TOP_H + Items.COUNT * ROW_H)
    window:Show()

    -- PrettyUI's sizes might not match the frame exactly (e.g. if the title
    -- bar is counted differently), so note the difference now and allow for
    -- it when saving; otherwise the window would creep on every reopen.
    w.frame = findFrame(window, gameArea)
    w.offset = { x = 0, y = 0, width = 0, height = 0 }
    if w.frame then
        w.frame:UpdateLayout()
        if w.frame.width > 0 then
            w.offset.width = w.frame.width - place.width
            w.offset.height = w.frame.height - place.height
            if place.xAnchor == 0 then
                w.offset.x, w.offset.y = w.frame.x - place.x, w.frame.y - place.y
            end
        end
    else
        Log.problem("can't find the window's frame; its position won't be remembered")
    end

    win = w
    return true
end

-- Closes the window (without reporting it as closed by the player).
function Window.close()
    if not win then return end
    saveGeometry()
    local w = win
    win, editing, measuredWidth = nil, {}, nil
    pcall(function() w.window:Destroy() end)
end

function Window.isOpen()
    return win ~= nil
end

-- Called regularly from the plugin's Logic handler (10 times a second).
-- Re-measures wrapped rows when the width changes, and saves the position
-- once the player stops moving the window. The width is checked here because
-- the resize event can arrive before the new width is readable.
function Window.tick(tick)
    if not win then return end
    local ok, width = pcall(locationWidth)
    if ok and width ~= measuredWidth then relayout() end
    trackGeometry(tick)
end

---------------------------------------------------------------------------
-- Editing a location
---------------------------------------------------------------------------

-- Replaces row n's location with a text box (Enter saves, Esc cancels).
function Window.startEdit(n)
    if not win or editing[n] or busy[n] then return end
    local r = win.rows[n]

    -- The box sits slightly higher than the location line so it gets the
    -- full height of the bottom half of the row.
    local boxY, boxH = HALF - 2, ROW_H - HALF
    local e = {}
    e.input = ui.InputField.new(r.layer)
    e.input.stylesheetID = id.StyleSheet.INPUT_DEFAULT
    e.input:Setup(ui.TextContentVisibilityMode.VISIBLE, ui.InputFieldFilterMode.NONE, MAX_LEN)
    e.input.content = r.locationText or ""
    e.input.emptyText = "New location... (at least " .. MIN_LEN .. " characters)"
    e.input:SetPos(PAD + 20, boxY)
    e.input:SetSize(-(PAD + 20 + 4 + SAVE_W + 4 + CANCEL_W + PAD), boxH, 1.0, 0)
    -- The input style's default font is too big for the box; use the rows'.
    e.input.text.font = Common.FONT
    e.input.text.alignVertical = ui.AlignMode.CENTRE
    e.input.contentMargin = ui.Margin.new(4, 0, 4, 0)
    e.input:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, cause, newContents)
        if cause == ui.InputFieldActionResult.SUBMIT then
            Window.saveEdit(n, newContents)
        elseif cause == ui.InputFieldActionResult.SUBMIT_ON_ESCAPE then
            finishEdit(n)
        end
    end)

    e.save = newButton(r.layer, "Save", function() Window.saveEdit(n, e.input.content) end)
    e.save:SetPos(-(PAD + CANCEL_W + 4 + SAVE_W), boxY, 1.0, 0)
    e.save:SetSize(SAVE_W, boxH)

    e.cancel = newButton(r.layer, "Cancel", function() finishEdit(n) end)
    e.cancel:SetPos(-(PAD + CANCEL_W), boxY, 1.0, 0)
    e.cancel:SetSize(CANCEL_W, boxH)

    r.location.hidden = true
    r.age.hidden = true
    setRowButtons(r, false)
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
        local r = win.rows[n]
        r.location.hidden = false
        r.age.hidden = false
        setRowButtons(r, true) -- only editable rows can be edited
    end
end

-- Checks the text and hands it to the plugin to send.
function Window.saveEdit(n, text)
    local e = editing[n]
    if not e then return end
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if #text < MIN_LEN then
        -- The hint only shows in an empty box, so clear the few characters typed.
        e.input.emptyText = "Too short - at least " .. MIN_LEN .. " characters"
        e.input.content = ""
        return
    end
    e.save.enabled = false
    e.cancel.enabled = false
    handlers.submit(n, text)
end

-- Called by the plugin when a confirm/update request starts (ok == nil) or
-- finishes (ok true/false, message on failure).
function Window.requestState(n, ok, message)
    if ok == nil then
        busy[n], rowError[n] = true, nil
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
            e.save.enabled = true
            e.cancel.enabled = true
        end
    end
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

-- Refreshes everything shown. items may be nil (no data yet); spied is
-- { [n] = bool } or nil if spy progress can't be read; summary is the
-- header line (see Common.summary).
function Window.update(items, spied, summary)
    if not win then return end
    local ok, err = pcall(function()
        win.summary.content = summary
        for n = 1, Items.COUNT do
            updateRow(win.rows[n], n, items and items[n], spied ~= nil and spied[n] == true)
        end
    end)
    if ok then
        relayout()
    else
        Log.problem("window update failed: " .. tostring(err))
        Window.close()
    end
end

return Window
