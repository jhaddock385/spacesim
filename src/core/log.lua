local M = {}

local entries = {}
local sessionStarted = false

-- Start a new session log (clears previous)
function M.startSession()
    entries = {}
    sessionStarted = true
    M.write("SESSION", "Session started at " .. os.date("%Y-%m-%d %H:%M:%S"))
    M.flush()
end

-- Write a log entry
-- category: "API", "CREW", "ERROR", "SYSTEM", "SESSION", etc.
function M.write(category, message)
    local entry = string.format("[%.2f] [%s] %s",
        love.timer.getTime(), category, message)
    table.insert(entries, entry)

    -- Also print to stdout for console visibility
    print(entry)
end

-- Flush log to file (overwrites previous session log)
function M.flush()
    if not sessionStarted then return end
    local content = table.concat(entries, "\n") .. "\n"
    love.filesystem.write("session_log.txt", content)
end

-- Get the full path to the log file
function M.getPath()
    return love.filesystem.getSaveDirectory() .. "/session_log.txt"
end

-- Get all entries as a string
function M.getEntries()
    return entries
end

return M
