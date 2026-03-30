local runner = require("tests.runner")
local api = require("src.core.api")
local json = require("lib.json")
local M = {}

function M.testJsonEncodeDecode()
    local data = { name = "test", value = 42, nested = { a = true } }
    local encoded = json.encode(data)
    local decoded = json.decode(encoded)
    runner.assertEqual("test", decoded.name)
    runner.assertEqual(42, decoded.value)
    runner.assertEqual(true, decoded.nested.a)
end

function M.testJsonArray()
    local data = { 1, 2, 3 }
    local encoded = json.encode(data)
    local decoded = json.decode(encoded)
    runner.assertEqual(3, #decoded)
    runner.assertEqual(2, decoded[2])
end

function M.testJsonString()
    local data = { text = 'hello "world"\nnewline' }
    local encoded = json.encode(data)
    local decoded = json.decode(encoded)
    runner.assertEqual('hello "world"\nnewline', decoded.text)
end

function M.testJsonNullAndBooleans()
    local decoded = json.decode('{"a":null,"b":true,"c":false}')
    runner.assertNil(decoded.a)
    runner.assertEqual(true, decoded.b)
    runner.assertEqual(false, decoded.c)
end

function M.testApiInit()
    local ok, msg = api.init()
    runner.assert(ok, "API init should succeed: " .. tostring(msg))
    runner.assertNotNil(api.getBackend(), "should have a backend")
end

return M
