-- The 13 things to spy each week: penguins 1-12 and the polar bear (13).
-- Numbering matches w60pengu.in and the spy device in game.

local Items = {}

Items.COUNT = 13
Items.GHOST = 11 -- the ghost penguin
Items.BEAR = 13

-- Points never change week to week: penguins 1-5 = 1, 6-10 and 12 = 2,
-- 11 (the ghost) = 3, bear = 1.
local POINTS = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 2, 1 }

-- Points for item n: from the API entry if it has them, else the fixed rule.
function Items.points(n, entry)
    return (entry and tonumber(entry.points)) or POINTS[n] or 0
end

-- Name to show when there's no location data.
function Items.defaultName(n)
    if n == Items.GHOST then return "Ghost penguin" end
    if n == Items.BEAR then return "Bear" end
    return "Penguin " .. n
end

return Items
