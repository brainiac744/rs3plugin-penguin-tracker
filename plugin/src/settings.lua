-- Player settings, saved between sessions with PersistentDB.
-- Colours are RGBA integers (0xRRGGBBAA), the format both ShapeList and
-- PrettyUI's colour picker use. They're saved as hex text ("C864FFFF"):
-- stored numbers come back as floats, which can't hold an 8-digit colour
-- exactly - the last byte (the alpha) can be rounded away.

local Settings = {}

local KEY = "settings"
local POINTS_CAP = 250 -- the game's limit on unspent penguin points

Settings.POINTS_CAP = POINTS_CAP

local DEFAULTS = {
    highlight = false,          -- boxes around nearby penguins
    colourUnspied = 0xFFC832FF, -- gold
    colourSpied = 0x8C8C8C60,   -- faint grey
    colourCap = 0xE03C3CFF,     -- red: spying now could waste points
    capWarning = true,          -- use colourCap when points are over the threshold
    capThreshold = 245,         -- "over this many points" counts as near the cap
    capSwapSpy = false,         -- near the cap, make Spy-on not the left-click option
}

local values = {}
for k, v in pairs(DEFAULTS) do values[k] = v end

-- Load saved values; older saves just miss newer keys, which keep defaults.
pcall(function()
    local saved = PersistentDB:GetStructuredData(KEY)
    if type(saved) ~= "table" then return end
    for k, default in pairs(DEFAULTS) do
        local v = saved[k]
        if type(default) == "boolean" and type(v) == "boolean" then
            values[k] = v
        elseif type(default) == "number" and type(v) == "string" then
            values[k] = tonumber(v, 16) or default -- colours, saved as hex
        elseif type(default) == "number" and type(v) == "number" then
            -- numbers come back from storage as floats
            values[k] = math.tointeger(math.floor(v)) or default
        end
    end
end)

local listeners = {}

function Settings.get(name)
    return values[name]
end

-- What gets stored: colours as hex text, everything else as is.
local function forStorage()
    local out = {}
    for k, v in pairs(values) do
        if k:sub(1, 6) == "colour" then
            out[k] = string.format("%08X", v & 0xFFFFFFFF)
        else
            out[k] = v
        end
    end
    return out
end

function Settings.set(name, value)
    if DEFAULTS[name] == nil or values[name] == value then return end
    values[name] = value
    pcall(function() PersistentDB:SetStructuredData(KEY, forStorage()) end)
    for _, fn in ipairs(listeners) do pcall(fn, name, value) end
end

-- fn(name, value) is called after any setting changes.
function Settings.onChange(fn)
    listeners[#listeners + 1] = fn
end

-- Clamp a typed threshold to something sensible.
function Settings.clampThreshold(n)
    n = math.tointeger(math.floor(tonumber(n) or DEFAULTS.capThreshold))
    return math.max(0, math.min(POINTS_CAP, n))
end

return Settings
