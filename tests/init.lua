local M = {}

local runner = require("tests.runner")

-- Load all test suites
function M.load()
    -- Unit tests
    runner.registerSuite("bus", "unit", require("tests.unit.bus_test"))
    runner.registerSuite("store", "unit", require("tests.unit.store_test"))
    runner.registerSuite("clock", "unit", require("tests.unit.clock_test"))
    runner.registerSuite("entities", "unit", require("tests.unit.entities_test"))
    runner.registerSuite("spatial", "unit", require("tests.unit.spatial_test"))
    runner.registerSuite("engineering", "unit", require("tests.unit.engineering_test"))
    runner.registerSuite("helm", "unit", require("tests.unit.helm_test"))
end

-- Handle --test CLI flag
-- Run all tests, print results, save to file, quit with exit code
function M.handleCLI()
    local args = arg or {}
    local runTests = false
    for _, a in ipairs(args) do
        if a == "--test" then
            runTests = true
            break
        end
    end

    if not runTests then return end

    local results = runner.run()
    local output = runner.formatResults(results)

    -- Print to stdout
    print(output)

    -- Save to file via Love2D filesystem
    local savePath = "test_results.txt"
    love.filesystem.write(savePath, output)
    local fullPath = love.filesystem.getSaveDirectory() .. "/" .. savePath
    print("\nResults saved to: " .. fullPath)

    -- Exit with appropriate code
    if results.failed > 0 or results.errors > 0 then
        love.event.quit(1)
    else
        love.event.quit(0)
    end
end

return M
