-- Optional in-world highlight: draws a box around every disguised penguin
-- near you (NPCs whose config name starts with PENG_SPY_, e.g.
-- PENG_SPY_PUMPKIN, PENG_SPY_BARREL, PENG_SPY_SHADOW_PENGUIN).
--
-- NPCs don't carry their penguin number (all pumpkin penguins share one
-- config), so "already spied" is worked out like this: when your spy count
-- goes up, the penguin closest to you is the one you just spied, and it is
-- drawn faded from then on. That memory lasts while the NPC stays loaded.

local Highlight = {}

local PREFIX = "PENG_SPY_"
local COLOUR_UNSPIED = 0xFFC832FF -- gold
local COLOUR_SPIED = 0x8C8C8C60   -- faint grey
local LINE_WIDTH = 3.0

-- The 12 edges of a box, as pairs of corner indices (0-based).
local BOX_LINES = {
    0, 1, 1, 3, 3, 2, 2, 0, -- bottom
    4, 5, 5, 7, 7, 6, 6, 4, -- top
    0, 4, 1, 5, 2, 6, 3, 7, -- sides
}

-- Prints each distinct problem once, so failures show in the console
-- without flooding it every frame.
local reported = {}
local function report(what, err)
    local msg = "[penguins] highlight " .. what .. ": " .. tostring(err)
    if not reported[msg] then
        reported[msg] = true
        print(msg)
    end
end

local lastCount = nil -- penguins found by the last scan, to report changes

local enabled = false
local penguins = {}    -- NPCEntity list from the last scan
local spiedUIDs = {}   -- [uid] = true for penguins spied while loaded

local function isPenguin(npc)
    local ok, yes = pcall(function()
        local name = npc.config and npc.config.configName or ""
        if name:sub(1, #PREFIX) == PREFIX then return true end
        local parent = npc.parentConfig and npc.parentConfig.configName or ""
        return parent:sub(1, #PREFIX) == PREFIX
    end)
    if not ok then report("NPC check failed", yes) end
    return ok and yes
end

function Highlight.setEnabled(value)
    enabled = value == true
    if not enabled then penguins = {} end
    lastCount = nil
    print("[penguins] highlight " .. (enabled and "on" or "off"))
end

function Highlight.isEnabled()
    return enabled
end

-- Refreshes the list of nearby penguins. Called a few times a second rather
-- than every frame, because listing all NPCs is relatively expensive.
function Highlight.scan()
    if not enabled then return end
    local ok, all = pcall(NPCList.All)
    if not ok or type(all) ~= "table" then
        report("NPC list failed", all)
        return
    end
    local found = {}
    for _, npc in ipairs(all) do
        if isPenguin(npc) then found[#found + 1] = npc end
    end
    penguins = found
    if #found ~= lastCount then
        lastCount = #found
        print(string.format("[penguins] highlight: %d penguin(s) nearby (of %d NPCs)", #found, #all))
    end
end

-- Your character's world position (x, z), trying the ways the API might
-- expose it. Returns nil plus the reason if none work.
local function myPosition()
    local attempts = {
        function() return Player.GetEntity().position end,
        function() return PlayerList.Self().position end,
        function() return Player.GetEntity().aabb.centre end,
    }
    local lastErr = "no position available"
    for _, get in ipairs(attempts) do
        local ok, p = pcall(get)
        if ok and p and p.x and p.z then return p end
        if not ok then lastErr = p end
    end
    return nil, lastErr
end

-- Called when the spy count goes up: remember the nearest penguin as spied.
-- Works even with the highlight off, so turning it on later still knows.
function Highlight.onSpied()
    local me, why = myPosition()
    if not me then
        report("can't find your position", why)
        return
    end
    local ok, err = pcall(function()
        local bestUID, bestDist = nil, math.huge
        for _, npc in ipairs(NPCList.All()) do
            if isPenguin(npc) and npc.isValid then
                local p = npc.position
                local dx, dz = p.x - me.x, p.z - me.z
                local d = dx * dx + dz * dz
                if d < bestDist then bestUID, bestDist = npc.uid, d end
            end
        end
        if bestUID then
            spiedUIDs[bestUID] = true
            print(string.format("[penguins] highlight: marked the penguin %.1f tiles away as spied",
                math.sqrt(bestDist) / 512))
        else
            print("[penguins] highlight: spied, but no penguin NPC was in view to mark")
        end
    end)
    if not ok then report("marking spied penguin failed", err) end
end

-- Draws the boxes. Must be called from Event.Draw (every frame), because
-- ShapeList.Draw only lasts for the frame it's called in.
function Highlight.draw()
    if not enabled then return end
    for _, npc in ipairs(penguins) do
        local ok, err = pcall(function()
            if not npc.isValid then return end
            local b = npc.aabb
            local x0, y0, z0, x1, y1, z1 = b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ
            ShapeList.Draw({
                shapePositions = {
                    Vector3.new(x0, y0, z0), Vector3.new(x1, y0, z0),
                    Vector3.new(x0, y0, z1), Vector3.new(x1, y0, z1),
                    Vector3.new(x0, y1, z0), Vector3.new(x1, y1, z0),
                    Vector3.new(x0, y1, z1), Vector3.new(x1, y1, z1),
                },
                shapeLines = BOX_LINES,
                colour = spiedUIDs[npc.uid] and COLOUR_SPIED or COLOUR_UNSPIED,
                lineWidth = LINE_WIDTH,
                ignoreDepth = true, -- visible through walls and scenery
            })
        end)
        if not ok then report("draw failed", err) end
    end
end

-- Forget NPCs, e.g. after logout or world hop (their UIDs no longer apply).
function Highlight.reset()
    penguins = {}
    spiedUIDs = {}
end

return Highlight
