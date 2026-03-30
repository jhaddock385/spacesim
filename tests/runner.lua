local M = {}

local suites = {}  -- {name, category, suite}
local results = {} -- populated after a run

-- Register a test suite
-- name: display name
-- category: "unit" or "integration"
-- suite: table with test functions (testXxx pattern) or a run(t) function
function M.registerSuite(name, category, suite)
    table.insert(suites, {
        name = name,
        category = category,
        suite = suite,
    })
end

-- Assertions — all take (expected, actual, message) or (condition, message)

function M.assert(condition, message)
    if not condition then
        error(message or "assertion failed", 2)
    end
end

function M.assertEqual(expected, actual, message)
    if expected ~= actual then
        local msg = (message or "assertEqual failed")
            .. "\n  expected: " .. tostring(expected)
            .. "\n  actual:   " .. tostring(actual)
        error(msg, 2)
    end
end

function M.assertNotEqual(expected, actual, message)
    if expected == actual then
        error((message or "assertNotEqual failed") .. ": " .. tostring(actual), 2)
    end
end

function M.assertNotNil(value, message)
    if value == nil then
        error(message or "expected non-nil value", 2)
    end
end

function M.assertNil(value, message)
    if value ~= nil then
        error((message or "expected nil") .. ", got: " .. tostring(value), 2)
    end
end

function M.assertGreaterThan(threshold, actual, message)
    if actual <= threshold then
        error((message or "assertGreaterThan failed")
            .. "\n  expected > " .. tostring(threshold)
            .. "\n  actual:    " .. tostring(actual), 2)
    end
end

function M.assertLessThan(threshold, actual, message)
    if actual >= threshold then
        error((message or "assertLessThan failed")
            .. "\n  expected < " .. tostring(threshold)
            .. "\n  actual:    " .. tostring(actual), 2)
    end
end

function M.assertInRange(min, max, actual, message)
    if actual < min or actual > max then
        error((message or "assertInRange failed")
            .. "\n  expected: " .. tostring(min) .. " - " .. tostring(max)
            .. "\n  actual:   " .. tostring(actual), 2)
    end
end

function M.assertThrows(fn, message)
    local ok, _ = pcall(fn)
    if ok then
        error(message or "expected function to throw", 2)
    end
end

-- Reset simulation state between tests
-- Clears bus, store, clock, and entities so each test starts clean
function M.resetSim()
    local bus = require("src.core.bus")
    local store = require("src.core.store")
    local clock = require("src.core.clock")
    local entities = require("src.sim.entities")
    bus.clear()
    store.clear()
    clock.clear()
    entities.clear()
end

-- Run all registered suites (or filtered by category)
-- Returns {passed=n, failed=n, errors=n, details={...}}
function M.run(category)
    results = {
        passed = 0,
        failed = 0,
        errors = 0,
        details = {},
    }

    for _, entry in ipairs(suites) do
        if not category or entry.category == category then
            M._runSuite(entry)
        end
    end

    return results
end

-- Run a single suite
function M._runSuite(entry)
    local suite = entry.suite
    local suiteResults = {
        name = entry.name,
        category = entry.category,
        tests = {},
    }

    -- Collect test functions (testXxx pattern)
    local testNames = {}
    for name, fn in pairs(suite) do
        if type(fn) == "function" and name:sub(1, 4) == "test" then
            table.insert(testNames, name)
        end
    end
    table.sort(testNames)

    for _, testName in ipairs(testNames) do
        -- Setup
        if suite.setup then
            local ok, err = pcall(suite.setup)
            if not ok then
                table.insert(suiteResults.tests, {
                    name = testName,
                    status = "error",
                    message = "setup failed: " .. tostring(err),
                })
                results.errors = results.errors + 1
                goto continue
            end
        end

        -- Run test
        local ok, err = pcall(suite[testName])
        if ok then
            table.insert(suiteResults.tests, {
                name = testName,
                status = "pass",
            })
            results.passed = results.passed + 1
        else
            table.insert(suiteResults.tests, {
                name = testName,
                status = "fail",
                message = tostring(err),
            })
            results.failed = results.failed + 1
        end

        -- Teardown
        if suite.teardown then
            pcall(suite.teardown)
        end

        ::continue::
    end

    table.insert(results.details, suiteResults)
end

-- Format results as a string for display/logging
function M.formatResults(res)
    res = res or results
    local lines = {}

    table.insert(lines, string.format(
        "Tests: %d passed, %d failed, %d errors, %d total",
        res.passed, res.failed, res.errors,
        res.passed + res.failed + res.errors))
    table.insert(lines, "")

    for _, suite in ipairs(res.details) do
        local suitePass = 0
        local suiteFail = 0
        for _, t in ipairs(suite.tests) do
            if t.status == "pass" then suitePass = suitePass + 1
            else suiteFail = suiteFail + 1 end
        end

        local icon = suiteFail == 0 and "PASS" or "FAIL"
        table.insert(lines, string.format(
            "[%s] %s (%s) — %d/%d",
            icon, suite.name, suite.category,
            suitePass, suitePass + suiteFail))

        -- Show failures
        for _, t in ipairs(suite.tests) do
            if t.status ~= "pass" then
                table.insert(lines, string.format(
                    "  %s %s: %s",
                    t.status == "fail" and "FAIL" or "ERR ",
                    t.name, t.message or ""))
            end
        end
    end

    return table.concat(lines, "\n")
end

-- Get the list of registered suites (for inspection)
function M.getSuites()
    return suites
end

-- Get last run results
function M.getResults()
    return results
end

return M
