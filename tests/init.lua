local M = {}

local runner = require("tests.runner")

-- Load all test suites
function M.load()
    -- Unit tests (no network, no cost)
    runner.registerSuite("bus", "unit", require("tests.unit.bus_test"))
    runner.registerSuite("store", "unit", require("tests.unit.store_test"))
    runner.registerSuite("clock", "unit", require("tests.unit.clock_test"))
    runner.registerSuite("entities", "unit", require("tests.unit.entities_test"))
    runner.registerSuite("spatial", "unit", require("tests.unit.spatial_test"))
    runner.registerSuite("engineering", "unit", require("tests.unit.engineering_test"))
    runner.registerSuite("helm", "unit", require("tests.unit.helm_test"))
    runner.registerSuite("api", "unit", require("tests.unit.api_test"))

    -- Live tests (hit external APIs, cost tokens)
    runner.registerSuite("api-live", "live", require("tests.live.api_live_test"))
end

-- Handle --test and --test-live CLI flags
-- --test       runs unit tests only
-- --test-live  runs live tests only (hits APIs, costs tokens)
-- --test-all   runs everything
function M.handleCLI()
    local args = arg or {}
    local mode = nil
    for _, a in ipairs(args) do
        if a == "--test" then mode = "unit"
        elseif a == "--test-live" then mode = "live"
        elseif a == "--test-all" then mode = "all"
        end
    end

    if not mode then return end

    local category = nil
    if mode == "unit" then category = "unit"
    elseif mode == "live" then category = "live"
    end
    -- mode == "all" leaves category nil, which runs everything

    local results = runner.run(category)
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
