-- Minimal JSON encoder/decoder for API communication
-- Handles: strings, numbers, booleans, nil/null, arrays, objects
-- Does NOT handle: unicode escapes, deeply nested edge cases
-- Good enough for Claude API request/response payloads

local M = {}

-- Sentinel value: assign to a table to force it to encode as a JSON array
-- Usage: local t = {}; t[json.ARRAY_MARKER] = true
-- Or use json.emptyArray() for convenience
M.ARRAY_MARKER = newproxy()  -- unique lightuserdata

function M.emptyArray()
    local t = {}
    t[M.ARRAY_MARKER] = true
    return t
end

-- Encode a Lua value to a JSON string
function M.encode(value)
    local t = type(value)

    if value == nil then
        return "null"
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "number" then
        if value ~= value then return "null" end  -- NaN
        if value == math.huge or value == -math.huge then return "null" end
        return tostring(value)
    elseif t == "string" then
        -- Escape special characters
        local escaped = value:gsub('\\', '\\\\')
            :gsub('"', '\\"')
            :gsub('\n', '\\n')
            :gsub('\r', '\\r')
            :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    elseif t == "table" then
        -- Detect array vs object
        -- Array: consecutive integer keys starting at 1
        local isArray = true
        local maxIdx = 0
        for k, _ in pairs(value) do
            if type(k) == "number" and k == math.floor(k) and k > 0 then
                if k > maxIdx then maxIdx = k end
            else
                isArray = false
                break
            end
        end
        if maxIdx == 0 then
            -- Check for explicit array marker
            if rawget(value, M.ARRAY_MARKER) then
                return "[]"
            end
            isArray = false
        end
        -- Check for gaps
        if isArray then
            for i = 1, maxIdx do
                if value[i] == nil then
                    isArray = false
                    break
                end
            end
        end

        if isArray then
            local parts = {}
            for i = 1, maxIdx do
                table.insert(parts, M.encode(value[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(value) do
                if type(k) == "string" then
                    table.insert(parts, M.encode(k) .. ":" .. M.encode(v))
                end
                -- Skip ARRAY_MARKER and non-string keys
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end

    return "null"
end

-- Decode a JSON string to a Lua value
function M.decode(str)
    local pos = 1

    local function skipWhitespace()
        while pos <= #str do
            local c = str:byte(pos)
            if c == 32 or c == 9 or c == 10 or c == 13 then
                pos = pos + 1
            else
                break
            end
        end
    end

    local function parseString()
        pos = pos + 1  -- skip opening quote
        local start = pos
        local result = {}

        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '\\' then
                table.insert(result, str:sub(start, pos - 1))
                pos = pos + 1
                local esc = str:sub(pos, pos)
                if esc == '"' then table.insert(result, '"')
                elseif esc == '\\' then table.insert(result, '\\')
                elseif esc == '/' then table.insert(result, '/')
                elseif esc == 'n' then table.insert(result, '\n')
                elseif esc == 'r' then table.insert(result, '\r')
                elseif esc == 't' then table.insert(result, '\t')
                elseif esc == 'u' then
                    -- Skip unicode escapes (just output ?)
                    pos = pos + 4
                    table.insert(result, '?')
                end
                pos = pos + 1
                start = pos
            elseif c == '"' then
                table.insert(result, str:sub(start, pos - 1))
                pos = pos + 1
                return table.concat(result)
            else
                pos = pos + 1
            end
        end
        error("unterminated string at position " .. start)
    end

    local function parseNumber()
        local start = pos
        if str:sub(pos, pos) == '-' then pos = pos + 1 end
        while pos <= #str and str:byte(pos) >= 48 and str:byte(pos) <= 57 do
            pos = pos + 1
        end
        if pos <= #str and str:sub(pos, pos) == '.' then
            pos = pos + 1
            while pos <= #str and str:byte(pos) >= 48 and str:byte(pos) <= 57 do
                pos = pos + 1
            end
        end
        if pos <= #str and (str:sub(pos, pos) == 'e' or str:sub(pos, pos) == 'E') then
            pos = pos + 1
            if pos <= #str and (str:sub(pos, pos) == '+' or str:sub(pos, pos) == '-') then
                pos = pos + 1
            end
            while pos <= #str and str:byte(pos) >= 48 and str:byte(pos) <= 57 do
                pos = pos + 1
            end
        end
        return tonumber(str:sub(start, pos - 1))
    end

    local parseValue  -- forward declaration

    local function parseArray()
        pos = pos + 1  -- skip [
        skipWhitespace()
        local arr = {}
        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return arr
        end
        while true do
            skipWhitespace()
            table.insert(arr, parseValue())
            skipWhitespace()
            if str:sub(pos, pos) == ',' then
                pos = pos + 1
            elseif str:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            else
                error("expected ',' or ']' at position " .. pos)
            end
        end
    end

    local function parseObject()
        pos = pos + 1  -- skip {
        skipWhitespace()
        local obj = {}
        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return obj
        end
        while true do
            skipWhitespace()
            if str:sub(pos, pos) ~= '"' then
                error("expected string key at position " .. pos)
            end
            local key = parseString()
            skipWhitespace()
            if str:sub(pos, pos) ~= ':' then
                error("expected ':' at position " .. pos)
            end
            pos = pos + 1
            skipWhitespace()
            obj[key] = parseValue()
            skipWhitespace()
            if str:sub(pos, pos) == ',' then
                pos = pos + 1
            elseif str:sub(pos, pos) == '}' then
                pos = pos + 1
                return obj
            else
                error("expected ',' or '}' at position " .. pos)
            end
        end
    end

    parseValue = function()
        skipWhitespace()
        local c = str:sub(pos, pos)
        if c == '"' then return parseString()
        elseif c == '{' then return parseObject()
        elseif c == '[' then return parseArray()
        elseif c == 't' then
            pos = pos + 4; return true
        elseif c == 'f' then
            pos = pos + 5; return false
        elseif c == 'n' then
            pos = pos + 4; return nil
        elseif c == '-' or (c >= '0' and c <= '9') then
            return parseNumber()
        else
            error("unexpected character '" .. c .. "' at position " .. pos)
        end
    end

    local value = parseValue()
    return value
end

return M
