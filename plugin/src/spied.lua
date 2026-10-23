-- Reads which penguins (and the bear) you have spied this week from the game.
--
-- Everything comes from one player variable, PENG_SPY_SWITCH (VarPlayer 1408).
-- Its layout was worked out by logging the variable while spying:
--   bits 0-9    penguins 1-10 (penguin n is bit n-1)
--   bits 16-20  how many penguins you have spied this week (not the bear)
--   bits 21-25  unknown?
--   bit 26      the bear (item 13)
--   bit 27      penguin 11 (the ghost)
--   bit 28      penguin 12

local Spied = {}

Spied.VAR_NAME = "PENG_SPY_SWITCH"

-- Item number (as used by w60pengu.in) -> bit in PENG_SPY_SWITCH.
local BIT_FOR_ITEM = {
    [1] = 0, [2] = 1, [3] = 2, [4] = 3, [5] = 4,
    [6] = 5, [7] = 6, [8] = 7, [9] = 8, [10] = 9,
    [11] = 27, [12] = 28, [13] = 26,
}

Spied.POINTS_VAR_NAME = "PENG_SPY_PERM1"

-- Unspent penguin points (bits 16-23 of PENG_SPY_PERM1, VarPlayer 9543),
-- or nil if they can't be read yet.
function Spied.readPoints()
    local ok, value = pcall(function()
        return var.VarPlayer.PENG_SPY_PERM1.value
    end)
    if ok and type(value) == "number" then
        return (math.tointeger(value) >> 16) & 0xFF
    end
    return nil
end

-- Returns the raw variable value, or nil if it can't be read yet
-- (for example while logging in).
function Spied.readRaw()
    local ok, value = pcall(function()
        return var.VarPlayer.PENG_SPY_SWITCH.value
    end)
    if ok and type(value) == "number" then return value end
    return nil
end

-- The item numbers (1-13) whose spy flag is set in `bits`, e.g. the flags
-- that turned on between two values: Spied.itemsIn(new & ~old).
function Spied.itemsIn(bits)
    local items = {}
    for item, bit in pairs(BIT_FOR_ITEM) do
        if (bits >> bit) & 1 == 1 then items[#items + 1] = item end
    end
    table.sort(items)
    return items
end

-- Turns the raw value into { [item] = true/false }.
function Spied.decode(raw)
    local result = {}
    for item, bit in pairs(BIT_FOR_ITEM) do
        result[item] = (raw >> bit) & 1 == 1
    end
    return result
end

-- Current spy flags { [item] = true/false }, or nil if they can't be read yet.
function Spied.current()
    local raw = Spied.readRaw()
    return raw and Spied.decode(raw) or nil
end

-- All the item bits together, for spotting a newly spied item in an update.
Spied.ITEM_BITS = 0
for _, bit in pairs(BIT_FOR_ITEM) do Spied.ITEM_BITS = Spied.ITEM_BITS | (1 << bit) end

return Spied
