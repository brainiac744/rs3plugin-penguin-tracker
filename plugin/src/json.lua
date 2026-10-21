-- Minimal JSON decoder and encoder, enough for the w60pengu.in API.
-- Objects become Lua tables keyed by string; arrays become 1-based lists;
-- JSON null becomes nil.

local json = {}

local escapes = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
    b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}

-- Returns the decoded value, or nil plus an error message.
function json.decode(text)
    local pos = 1

    local function fail(msg)
        error(string.format("JSON error at %d: %s", pos, msg), 0)
    end

    local function skipSpace()
        pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
    end

    local parseValue -- forward declaration

    local function parseString()
        pos = pos + 1 -- opening quote
        local parts = {}
        while true do
            local c = text:sub(pos, pos)
            if c == "" then fail("unterminated string") end
            if c == '"' then
                pos = pos + 1
                return table.concat(parts)
            elseif c == "\\" then
                local e = text:sub(pos + 1, pos + 1)
                if e == "u" then
                    local hex = text:sub(pos + 2, pos + 5)
                    local code = tonumber(hex, 16)
                    if not code then fail("bad \\u escape") end
                    pos = pos + 6
                    -- Combine a UTF-16 surrogate pair into one code point.
                    if code >= 0xD800 and code <= 0xDBFF and text:sub(pos, pos + 1) == "\\u" then
                        local low = tonumber(text:sub(pos + 2, pos + 5), 16)
                        if low and low >= 0xDC00 and low <= 0xDFFF then
                            code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                            pos = pos + 6
                        end
                    end
                    parts[#parts + 1] = utf8.char(code)
                elseif escapes[e] then
                    parts[#parts + 1] = escapes[e]
                    pos = pos + 2
                else
                    fail("bad escape")
                end
            else
                -- Copy a run of ordinary characters in one go.
                local stop = text:find('["\\]', pos) or (#text + 1)
                parts[#parts + 1] = text:sub(pos, stop - 1)
                pos = stop
            end
        end
    end

    local function parseNumber()
        local s, e = text:find("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        if not s then fail("bad number") end
        local n = tonumber(text:sub(s, e))
        if n == nil then fail("bad number") end
        pos = e + 1
        return n
    end

    local function parseObject()
        pos = pos + 1 -- {
        local obj = {}
        skipSpace()
        if text:sub(pos, pos) == "}" then pos = pos + 1; return obj end
        while true do
            skipSpace()
            if text:sub(pos, pos) ~= '"' then fail("expected key") end
            local key = parseString()
            skipSpace()
            if text:sub(pos, pos) ~= ":" then fail("expected ':'") end
            pos = pos + 1
            obj[key] = parseValue()
            skipSpace()
            local c = text:sub(pos, pos)
            pos = pos + 1
            if c == "}" then return obj end
            if c ~= "," then fail("expected ',' or '}'") end
        end
    end

    local function parseArray()
        pos = pos + 1 -- [
        local arr = {}
        skipSpace()
        if text:sub(pos, pos) == "]" then pos = pos + 1; return arr end
        while true do
            arr[#arr + 1] = parseValue()
            skipSpace()
            local c = text:sub(pos, pos)
            pos = pos + 1
            if c == "]" then return arr end
            if c ~= "," then fail("expected ',' or ']'") end
        end
    end

    function parseValue()
        skipSpace()
        local c = text:sub(pos, pos)
        if c == "{" then return parseObject()
        elseif c == "[" then return parseArray()
        elseif c == '"' then return parseString()
        elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
        elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
        else return parseNumber() end
    end

    local ok, result = pcall(function()
        local value = parseValue()
        skipSpace()
        if pos <= #text then fail("trailing characters") end
        return value
    end)
    if ok then return result end
    return nil, result
end

-- Minimal JSON encoder for the small request bodies we send: tables with
-- string keys become objects; strings, numbers and booleans are written as-is.
local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        if c == "\n" then return "\\n" end
        if c == "\r" then return "\\r" end
        if c == "\t" then return "\\t" end
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end

function json.encode(value)
    local t = type(value)
    if t == "string" then return encodeString(value) end
    if t == "number" then
        if math.type(value) == "integer" then return tostring(value) end
        return string.format("%.14g", value)
    end
    if t == "boolean" then return tostring(value) end
    if t == "table" then
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = tostring(k) end
        table.sort(keys) -- stable output
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = encodeString(k) .. ":" .. json.encode(value[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

return json
