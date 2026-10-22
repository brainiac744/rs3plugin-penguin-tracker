-- Console output. Problems always print (each distinct one only once, so a
-- failure inside a per-frame handler can't flood the console). Progress
-- messages only print when DEBUG is true.

local Log = {}

Log.DEBUG = false

local seen = {}

-- A problem worth knowing about; printed once per distinct message.
function Log.problem(message)
    local text = "[penguins] " .. tostring(message)
    if not seen[text] then
        seen[text] = true
        print(text)
    end
end

-- A progress message for development.
function Log.debug(message)
    if Log.DEBUG then print("[penguins] " .. tostring(message)) end
end

return Log
