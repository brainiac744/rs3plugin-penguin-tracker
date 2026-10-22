-- The Plugins panel (opened from the plugin's ribbon icon): the summary line
-- and a button to show or hide the locations window. The game hands us an
-- empty layer each time the panel is shown (Event.ContentLayerReady).

local Common = require("src/ui/common")

local Sidebar = {}

local PAD = Common.PAD

local parts = nil -- { summary, toggle } while shown

-- Builds the panel in the given layer. onToggle: the button was pressed.
function Sidebar.build(root, onToggle)
    local s = {}
    s.summary = Common.newText(root)
    s.summary:SetPos(PAD, 4)
    s.summary:SetSize(-2 * PAD, 40, 1.0, 0)
    s.summary.maxLines = 2
    s.summary.colour = Common.hex(Common.C.summary)

    s.toggle = Common.newButton(root, "Show locations", onToggle)
    s.toggle:SetPos(PAD, 50)
    s.toggle:SetSize(-2 * PAD, 26, 1.0, 0)

    parts = s
end

-- Updates the summary and the button label.
function Sidebar.update(summary, windowOpen)
    if not parts then return end
    local ok = pcall(function()
        parts.summary.content = summary
        parts.toggle.label = windowOpen and "Hide locations" or "Show locations"
    end)
    if not ok then parts = nil end -- the panel was closed; rebuilt on next show
end

function Sidebar.close()
    parts = nil
end

return Sidebar
