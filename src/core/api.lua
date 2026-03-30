local M = {}

local json = require("lib.json")

local apiKey = nil
local backend = nil  -- "luasocket" or "curl"

-- Load API key from secrets.lua
local function loadKey()
    if apiKey then return true end

    local ok, secrets = pcall(require, "secrets")
    if ok and secrets and secrets.anthropic_api_key then
        apiKey = secrets.anthropic_api_key
        return true
    end

    return false, "secrets.lua not found or missing anthropic_api_key"
end

-- Try to set up luasocket + luasec
local function tryLuasocket()
    local ok1, http = pcall(require, "ssl.https")
    local ok2, ltn12 = pcall(require, "ltn12")
    if ok1 and ok2 then
        backend = "luasocket"
        return true
    end
    return false
end

-- Check if curl is available
local function tryCurl()
    local handle = io.popen("which curl 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        if result and #result > 0 then
            backend = "curl"
            return true
        end
    end
    return false
end

-- Initialize: load key and detect backend
function M.init()
    local ok, err = loadKey()
    if not ok then
        return false, err
    end

    if tryLuasocket() then
        return true, "using luasocket"
    elseif tryCurl() then
        return true, "using curl"
    else
        return false, "no HTTP backend available (need luasocket+luasec or curl)"
    end
end

-- Send a message to Claude API via luasocket
local function sendLuasocket(requestBody)
    local https = require("ssl.https")
    local ltn12 = require("ltn12")

    local requestJson = json.encode(requestBody)
    local responseChunks = {}

    local result, statusCode, headers = https.request({
        url = "https://api.anthropic.com/v1/messages",
        method = "POST",
        headers = {
            ["content-type"] = "application/json",
            ["x-api-key"] = apiKey,
            ["anthropic-version"] = "2023-06-01",
            ["content-length"] = tostring(#requestJson),
        },
        source = ltn12.source.string(requestJson),
        sink = ltn12.sink.table(responseChunks),
    })

    if not result then
        return nil, "request failed: " .. tostring(statusCode)
    end

    local responseJson = table.concat(responseChunks)
    local ok, response = pcall(json.decode, responseJson)
    if not ok then
        return nil, "failed to parse response: " .. tostring(response)
    end

    return response, nil
end

-- Send a message to Claude API via curl
local function sendCurl(requestBody)
    local requestJson = json.encode(requestBody)

    -- Write request to temp file to avoid shell escaping issues
    local tmpPath = os.tmpname()
    local tmpFile = io.open(tmpPath, "w")
    if not tmpFile then
        return nil, "could not create temp file"
    end
    tmpFile:write(requestJson)
    tmpFile:close()

    local cmd = string.format(
        'curl -s https://api.anthropic.com/v1/messages '
        .. '-H "content-type: application/json" '
        .. '-H "x-api-key: %s" '
        .. '-H "anthropic-version: 2023-06-01" '
        .. '-d @%s 2>&1',
        apiKey, tmpPath)

    local handle = io.popen(cmd)
    if not handle then
        os.remove(tmpPath)
        return nil, "could not execute curl"
    end

    local responseJson = handle:read("*a")
    handle:close()
    os.remove(tmpPath)

    if not responseJson or #responseJson == 0 then
        return nil, "empty response from curl"
    end

    local ok, response = pcall(json.decode, responseJson)
    if not ok then
        return nil, "failed to parse response: " .. tostring(response)
    end

    return response, nil
end

-- Send a message to the Claude API
-- messages: {{role="user", content="..."}, ...}
-- options: {model=string, max_tokens=number, system=string}
-- Returns: response table or nil, error string
function M.send(messages, options)
    options = options or {}

    local requestBody = {
        model = options.model or "claude-sonnet-4-20250514",
        max_tokens = options.max_tokens or 256,
        messages = messages,
    }
    if options.system then
        requestBody.system = options.system
    end

    if backend == "luasocket" then
        return sendLuasocket(requestBody)
    elseif backend == "curl" then
        return sendCurl(requestBody)
    else
        return nil, "no backend initialized (call api.init() first)"
    end
end

-- Extract the text content from a Claude API response
function M.getResponseText(response)
    if not response then return nil end
    if response.error then
        return nil, response.error.message or "API error"
    end
    if response.content then
        for _, block in ipairs(response.content) do
            if block.type == "text" then
                return block.text
            end
        end
    end
    return nil, "no text content in response"
end

-- Get which backend is in use
function M.getBackend()
    return backend
end

return M
