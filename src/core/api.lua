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

-- Send a message to Claude API via curl (blocking)
local function sendCurl(requestBody)
    local requestJson = json.encode(requestBody)

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

-- Send a message to Claude API via curl (non-blocking / async)
-- Launches curl in the background, returns immediately.
-- Call pollAsync() each frame to check for completion.
local asyncState = nil  -- {requestPath, responsePath, startTime}

local function sendCurlAsync(requestBody)
    if asyncState then
        return false, "async request already in progress"
    end

    local requestJson = json.encode(requestBody)

    local requestPath = os.tmpname()
    local responsePath = os.tmpname()
    os.remove(responsePath)  -- remove so we can detect when curl creates it

    local tmpFile = io.open(requestPath, "w")
    if not tmpFile then
        return false, "could not create temp file"
    end
    tmpFile:write(requestJson)
    tmpFile:close()

    local cmd = string.format(
        'curl -s https://api.anthropic.com/v1/messages '
        .. '-H "content-type: application/json" '
        .. '-H "x-api-key: %s" '
        .. '-H "anthropic-version: 2023-06-01" '
        .. '-d @%s '
        .. '-o %s 2>/dev/null &',
        apiKey, requestPath, responsePath)

    os.execute(cmd)

    asyncState = {
        requestPath = requestPath,
        responsePath = responsePath,
        startTime = love.timer.getTime(),
    }

    return true, nil
end

-- Send a message to the Claude API
-- messages: {{role="user", content="..."}, ...}
-- options: {model=string, max_tokens=number, system=string, tools=table}
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
    if options.tools and #options.tools > 0 then
        requestBody.tools = options.tools
    end

    if backend == "luasocket" then
        return sendLuasocket(requestBody)
    elseif backend == "curl" then
        return sendCurl(requestBody)
    else
        return nil, "no backend initialized (call api.init() first)"
    end
end

-- Send a message asynchronously (non-blocking)
-- Returns true if launched, false + error if not
function M.sendAsync(messages, options)
    options = options or {}

    local requestBody = {
        model = options.model or "claude-sonnet-4-20250514",
        max_tokens = options.max_tokens or 256,
        messages = messages,
    }
    if options.system then
        requestBody.system = options.system
    end
    if options.tools and #options.tools > 0 then
        requestBody.tools = options.tools
    end

    if backend == "curl" then
        return sendCurlAsync(requestBody)
    else
        -- Fallback: do blocking send and store result
        local response, err = M.send(messages, options)
        if response then
            asyncState = { done = true, response = response }
            return true, nil
        end
        return false, err
    end
end

-- Poll for async response completion
-- Returns: "pending", nil  (still waiting)
--          "done", response  (completed)
--          "error", message  (failed)
function M.pollAsync()
    if not asyncState then
        return "error", "no async request in progress"
    end

    -- Already resolved (non-curl fallback)
    if asyncState.done then
        local response = asyncState.response
        asyncState = nil
        return "done", response
    end

    -- Check if response file exists and has content
    local f = io.open(asyncState.responsePath, "r")
    if not f then
        -- Check timeout (30 seconds)
        if love.timer.getTime() - asyncState.startTime > 30 then
            os.remove(asyncState.requestPath)
            asyncState = nil
            return "error", "API request timed out"
        end
        return "pending", nil
    end

    local responseJson = f:read("*a")
    f:close()

    -- File might exist but be empty (curl still writing)
    if #responseJson == 0 then
        return "pending", nil
    end

    -- Try to parse — if it fails, curl might still be writing
    local ok, response = pcall(json.decode, responseJson)
    if not ok then
        -- Could be partial write, wait a bit more
        -- But if it's been a while, it's probably a real error
        if love.timer.getTime() - asyncState.startTime > 2 then
            -- Try once more next frame
            return "pending", nil
        end
        return "pending", nil
    end

    -- Success — clean up temp files
    os.remove(asyncState.requestPath)
    os.remove(asyncState.responsePath)
    asyncState = nil

    return "done", response
end

-- Check if an async request is in progress
function M.isAsyncPending()
    return asyncState ~= nil and not asyncState.done
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

-- Extract tool use calls from a Claude API response
-- Returns: list of {id, name, input} or empty list
function M.getToolCalls(response)
    local calls = {}
    if not response or not response.content then return calls end
    for _, block in ipairs(response.content) do
        if block.type == "tool_use" then
            table.insert(calls, {
                id = block.id,
                name = block.name,
                input = block.input or {},
            })
        end
    end
    return calls
end

-- Get which backend is in use
function M.getBackend()
    return backend
end

return M
