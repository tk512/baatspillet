-- src/json.lua
-- Tiny, dependency-free JSON encode/decode.
-- Only supports what the save system needs: tables, arrays, strings,
-- numbers, booleans, null. Good enough for a small save file and avoids
-- pulling in an external library (see CLAUDE.md: no external dependencies).

local json = {}

-- ── Encoding ────────────────────────────────────────────────────────────

local escape_map = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b',
    ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function escape_str(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
        return escape_map[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
end

-- Decide whether a table should be written as a JSON array or object.
local function is_array(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    return n == #t
end

local encode_value

local function encode_table(t, indent, level)
    local pad   = string.rep("  ", level + 1)
    local pad0  = string.rep("  ", level)
    local parts = {}

    if is_array(t) then
        if #t == 0 then return "[]" end
        for _, v in ipairs(t) do
            parts[#parts + 1] = pad .. encode_value(v, indent, level + 1)
        end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad0 .. "]"
    else
        -- Sort keys so the save file is stable + diff-friendly.
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        if #keys == 0 then return "{}" end
        for _, k in ipairs(keys) do
            parts[#parts + 1] = pad .. escape_str(tostring(k)) .. ": "
                .. encode_value(t[k], indent, level + 1)
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad0 .. "}"
    end
end

function encode_value(v, indent, level)
    local tv = type(v)
    if tv == "nil" then
        return "null"
    elseif tv == "boolean" then
        return tostring(v)
    elseif tv == "number" then
        -- Avoid scientific notation / trailing junk for integers.
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return string.format("%d", v)
        end
        return tostring(v)
    elseif tv == "string" then
        return escape_str(v)
    elseif tv == "table" then
        return encode_table(v, indent, level)
    end
    error("json: cannot encode value of type " .. tv)
end

function json.encode(value)
    return encode_value(value, true, 0)
end

-- ── Decoding ────────────────────────────────────────────────────────────

local function skip_ws(s, i)
    local _, j = s:find("^[ \t\r\n]*", i)
    return (j or i - 1) + 1
end

local decode_value

local function decode_string(s, i)
    i = i + 1 -- skip opening quote
    local buf = {}
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(buf), i + 1
        elseif c == '\\' then
            local n = s:sub(i + 1, i + 1)
            local map = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
                          b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
            if map[n] then
                buf[#buf + 1] = map[n]; i = i + 2
            elseif n == 'u' then
                local hex = s:sub(i + 2, i + 5)
                buf[#buf + 1] = string.char(tonumber(hex, 16) % 256)
                i = i + 6
            else
                error("json: bad escape \\" .. n)
            end
        else
            buf[#buf + 1] = c; i = i + 1
        end
    end
    error("json: unterminated string")
end

local function decode_number(s, i)
    local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
    return tonumber(num), i + #num
end

local function decode_array(s, i)
    local arr = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    while true do
        local v
        v, i = decode_value(s, i)
        arr[#arr + 1] = v
        i = skip_ws(s, i)
        local c = s:sub(i, i)
        if c == "]" then return arr, i + 1 end
        if c ~= "," then error("json: expected ',' or ']'") end
        i = skip_ws(s, i + 1)
    end
end

local function decode_object(s, i)
    local obj = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
        i = skip_ws(s, i)
        if s:sub(i, i) ~= '"' then error("json: expected string key") end
        local key
        key, i = decode_string(s, i)
        i = skip_ws(s, i)
        if s:sub(i, i) ~= ":" then error("json: expected ':'") end
        local v
        v, i = decode_value(s, skip_ws(s, i + 1))
        obj[key] = v
        i = skip_ws(s, i)
        local c = s:sub(i, i)
        if c == "}" then return obj, i + 1 end
        if c ~= "," then error("json: expected ',' or '}'") end
        i = i + 1
    end
end

function decode_value(s, i)
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == '"' then return decode_string(s, i)
    elseif c == '{' then return decode_object(s, i)
    elseif c == '[' then return decode_array(s, i)
    elseif c == '-' or c:match("%d") then return decode_number(s, i)
    elseif s:sub(i, i + 3) == "true"  then return true, i + 4
    elseif s:sub(i, i + 4) == "false" then return false, i + 5
    elseif s:sub(i, i + 3) == "null"  then return nil, i + 4
    end
    error("json: unexpected character '" .. c .. "' at position " .. i)
end

function json.decode(str)
    local ok, value = pcall(function()
        local v = decode_value(str, 1)
        return v
    end)
    if not ok then return nil, value end
    return value
end

return json
