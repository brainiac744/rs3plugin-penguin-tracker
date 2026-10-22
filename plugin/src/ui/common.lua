-- Shared pieces for the plugin's interface: colours, fonts, and small
-- helpers for making text, buttons and icon buttons with the game's own
-- styles.

local Items = require("src/items")
local Settings = require("src/settings")

local Common = {}

Common.PAD = 6 -- gap between interface parts and the edges

-- Colours (from the Alt1 app's dark brown theme), as 0xRRGGBB.
Common.C = {
    divider  = 0x2E2A20,
    name     = 0xE8D8A8, ghostName = 0xB8C8A8, bearName = 0xC8982E,
    -- Spied penguins show their name in green, like a completed quest in the
    -- quest list. Rows stay at full brightness so they don't look disabled.
    spied    = 0x3FD24A,
    num      = 0x7A6E4A, location = 0xA09060, age = 0x5C5238, summary = 0xC8B87C,
    error    = 0xCC5566,
    pts      = { [1] = 0x6A8C3A, [2] = 0x9E8E5C, [3] = 0xB8902E },
}

-- 0xRRGGBB (plus optional alpha 0-1) to the Vector4 the UI uses.
function Common.hex(rgb, alpha)
    return Vector4.new(((rgb >> 16) & 0xFF) / 255, ((rgb >> 8) & 0xFF) / 255,
        (rgb & 0xFF) / 255, alpha or 1.0)
end

-- The small font used throughout, and the same font for measuring text.
Common.FONT = id.Font.MUSEO_SANS_11PT_REGULAR
Common.MEASURE_FONT = config.Font.MUSEO_SANS_11PT_REGULAR

-- A single-line text, left-aligned and vertically centred.
function Common.newText(parent)
    local t = ui.Text.new(parent)
    t.font = Common.FONT
    t.maxLines = 1
    t:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.CENTRE)
    return t
end

-- A standard game-styled button.
function Common.newButton(parent, label, onPress)
    local b = ui.Button.new(parent)
    b.label = label
    b.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
    b:Subscribe(ui.Hook.ONBUTTONPRESSED, function() onPress() end)
    return b
end

local function spriteID(name)
    local ok, v = pcall(function() return id.Sprite[name] end)
    if ok and v then return v end
    return nil
end

-- A standard button with a built-in game sprite drawn over its centre
-- instead of text. The icon lets clicks through to the button. hoverName,
-- if given, is shown while the mouse is over the button. If the sprite
-- name isn't known (e.g. renamed in a game update), the button keeps its
-- text label and no icon is returned.
function Common.newIconButton(parent, label, spriteName, hoverName, onPress)
    local button = Common.newButton(parent, label, onPress)
    local normal = spriteID(spriteName)
    if not normal then return button, nil end
    local hover = hoverName and spriteID(hoverName) or nil

    local icon = ui.Sprite.new(parent)
    icon.sprite = normal
    icon.clickthrough = true
    button.label = ""
    if hover then
        -- With an ID, so the button's own hover handling stays in place.
        button:Subscribe(ui.Hook.ONMOUSEOVER, "penguin-icon", function() icon.sprite = hover end)
        button:Subscribe(ui.Hook.ONMOUSELEAVE, "penguin-icon", function() icon.sprite = normal end)
    end
    return button, icon
end

-- The one-line summary shown in the window and the sidebar, e.g.
-- "5/13 spied - 8 pts this week - 170/250 banked".
function Common.summary(items, spied, points, status)
    local text
    if spied then
        local count, weekPts = 0, 0
        for n = 1, Items.COUNT do
            if spied[n] then
                count = count + 1
                weekPts = weekPts + Items.points(n, items and items[n])
            end
        end
        text = string.format("%d/%d spied - %d pts this week", count, Items.COUNT, weekPts)
    else
        text = "Spy progress unavailable"
    end
    if points then
        text = text .. string.format(" - %d/%d banked", points, Settings.POINTS_CAP)
    end
    if status and status ~= "" then text = text .. " - " .. status end
    return text
end

return Common
