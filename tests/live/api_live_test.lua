local runner = require("tests.runner")
local api = require("src.core.api")
local M = {}

function M.testApiLiveCall()
    local ok, msg = api.init()
    if not ok then
        error("API init failed: " .. tostring(msg))
    end

    local response, err = api.send(
        {{ role = "user", content = "Respond with exactly the word 'pong'. Nothing else." }},
        { max_tokens = 10 }
    )
    runner.assertNil(err, "API call should not error: " .. tostring(err))
    runner.assertNotNil(response, "should get a response")

    local text, textErr = api.getResponseText(response)
    runner.assertNotNil(text, "should extract text: " .. tostring(textErr))
    runner.assertGreaterThan(0, #text, "response text should not be empty")
end

return M
