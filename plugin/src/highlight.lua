-- Optional in-world highlight: draws a box around every disguised penguin
-- near you (NPCs whose config name starts with PENG_SPY_, e.g.
-- PENG_SPY_PUMPKIN, PENG_SPY_BARREL, PENG_SPY_SHADOW_PENGUIN).
-- Colours come from Settings: unspied, spied, and a warning colour used for
-- unspied penguins when your points are near the cap (spying would waste some).
--
-- Which penguin is which: NPCs don't carry their penguin number (all pumpkin
-- penguins share one config), but each penguin NPC keeps the same UID. So we
-- keep a UID -> penguin number table, seeded with the UIDs observed in game,
-- and learn new ones: when you spy penguin n and no penguin in view is known
-- to be n, the nearest unrecognised penguin is taken to be n and saved.
-- A penguin's spied state then comes straight from the game's spy flags.

local Settings = require("src/settings")

local Highlight = {}

local PREFIX = "PENG_SPY_"
local LINE_WIDTH = 3.0
local MAP_KEY = "penguinUIDs"     -- PersistentDB key for learned UIDs

-- UIDs observed in game (Oct 2026). Learned entries override these.
local KNOWN_UIDS = {
    [82350] = 1, [82353] = 2, [82358] = 3, [82361] = 4, [82363] = 5, [82365] = 6,
    [82349] = 7, [82352] = 8, [82357] = 9, [82360] = 10, [82362] = 11, [82364] = 12,
}

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

local penguins = {}   -- NPCEntity list from the last scan
local lastCount = nil -- penguins found by the last scan, to report changes
local spied = {}      -- [penguin number] = true, from the game's spy flags
local points = nil    -- unspent penguin points, nil if unknown
local guessed = {}    -- [uid] = true: spied this session but number unknown

-- UID -> penguin number: the known table plus anything learned (saved).
local numberFor = {}
for uid, n in pairs(KNOWN_UIDS) do numberFor[uid] = n end
pcall(function()
    local learned = PersistentDB:GetStructuredData(MAP_KEY)
    if type(learned) == "table" then
        -- stored as { ["82350"] = 1, ... }; numbers come back as floats
        for k, v in pairs(learned) do
            local uid, n = math.tointeger(tonumber(k)), math.tointeger(tonumber(v))
            if uid and n then numberFor[uid] = n end
        end
    end
end)

local function saveLearned()
    local out = {}
    for uid, n in pairs(numberFor) do
        if KNOWN_UIDS[uid] ~= n then out[tostring(uid)] = n end
    end
    pcall(function() PersistentDB:SetStructuredData(MAP_KEY, out) end)
end

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

local function enabled()
    return Settings.get("highlight") == true
end

-- Turning the highlight off forgets the nearby list (scan refills it).
Settings.onChange(function(name, value)
    if name == "highlight" then
        if not value then penguins = {} end
        lastCount = nil
        print("[penguins] highlight " .. (value and "on" or "off"))
    end
end)

-- The game's spy flags, { [n] = bool } (nil if unknown). Called on redraw.
function Highlight.setSpied(flags)
    spied = flags or {}
end

-- Unspent penguin points (nil if unknown). Called on redraw.
function Highlight.setPoints(value)
    points = value
end

-- True when spying now could take you past the points cap.
function Highlight.nearCap()
    return Settings.get("capWarning") and points ~= nil
        and points > Settings.get("capThreshold")
end

-- Refreshes the list of nearby penguins. Called a few times a second rather
-- than every frame, because listing all NPCs is relatively expensive.
function Highlight.scan()
    if not enabled() then return end
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

-- Called with the penguin numbers whose spy flag just turned on. Makes sure
-- each one is linked to an NPC: if no penguin in view is known to be that
-- number, the nearest penguin we don't recognise yet is assumed to be it.
-- Works even with the highlight off, so the table keeps up to date.
function Highlight.onSpied(numbers)
    local ok, err = pcall(function()
        local inView = {}
        for _, npc in ipairs(NPCList.All()) do
            if npc.isValid and isPenguin(npc) then inView[#inView + 1] = npc end
        end
        for _, n in ipairs(numbers) do
            if n <= 12 then -- the bear (13) isn't a PENG_SPY_ NPC
                local known = false
                for _, npc in ipairs(inView) do
                    if numberFor[npc.uid] == n then known = true end
                end
                if not known then
                    -- Nearest penguin we don't recognise. Penguins we already
                    -- know are never reassigned, so a neighbour can't be mislabelled.
                    local me, why = myPosition()
                    if not me then
                        report("can't find your position", why)
                        return
                    end
                    local best, bestDist = nil, math.huge
                    for _, npc in ipairs(inView) do
                        if numberFor[npc.uid] == nil then
                            local p = npc.position
                            local d = (p.x - me.x) ^ 2 + (p.z - me.z) ^ 2
                            if d < bestDist then best, bestDist = npc, d end
                        end
                    end
                    if best then
                        -- Forget any other UID that claimed this number.
                        for uid, m in pairs(numberFor) do
                            if m == n then numberFor[uid] = nil end
                        end
                        numberFor[best.uid] = n
                        guessed[best.uid] = nil
                        saveLearned()
                        print(string.format("[penguins] highlight: learned penguin %d is NPC %d", n, best.uid))
                    else
                        print(string.format("[penguins] highlight: spied penguin %d, but couldn't tell which NPC it was", n))
                    end
                end
            end
        end
    end)
    if not ok then report("linking spied penguin failed", err) end
end

Highlight.isPenguin = isPenguin

local function isSpiedNPC(npc)
    local n = numberFor[npc.uid]
    if n then return spied[n] == true end
    return guessed[npc.uid] == true
end

-- Draws the boxes. Must be called from Event.Draw (every frame), because
-- ShapeList.Draw only lasts for the frame it's called in.
function Highlight.draw()
    if not enabled() then return end
    local colourSpied = Settings.get("colourSpied")
    local colourUnspied = Highlight.nearCap() and Settings.get("colourCap")
        or Settings.get("colourUnspied")
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
                colour = isSpiedNPC(npc) and colourSpied or colourUnspied,
                lineWidth = LINE_WIDTH,
                ignoreDepth = true, -- visible through walls and scenery
            })
        end)
        if not ok then report("draw failed", err) end
    end
end

-- Forget the NPC list, e.g. after logout or world hop. (The UID table is kept:
-- UIDs have stayed the same across logins.)
function Highlight.reset()
    penguins = {}
    guessed = {}
end

return Highlight
