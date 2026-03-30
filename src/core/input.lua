local M = {}

local _state  -- lazy load to avoid circular require

local keyBindings = {}          -- state -> key -> handler
local mousePressBindings = {}   -- state -> button -> handler
local mouseReleaseBindings = {} -- state -> button -> handler

local function getState()
    if not _state then _state = require("src.core.state") end
    return _state
end

-- Bind a key handler for a specific state (or "*" for global)
function M.bindKey(stateName, key, handler)
    if not keyBindings[stateName] then
        keyBindings[stateName] = {}
    end
    keyBindings[stateName][key] = handler
end

-- Bind a mouse press handler for a specific state (or "*" for global)
function M.bindMousePress(stateName, btn, handler)
    if not mousePressBindings[stateName] then
        mousePressBindings[stateName] = {}
    end
    mousePressBindings[stateName][btn] = handler
end

-- Bind a mouse release handler for a specific state (or "*" for global)
function M.bindMouseRelease(stateName, btn, handler)
    if not mouseReleaseBindings[stateName] then
        mouseReleaseBindings[stateName] = {}
    end
    mouseReleaseBindings[stateName][btn] = handler
end

function M.keypressed(key)
    local st = getState()
    local s = st.get()
    -- State-specific binding first
    if keyBindings[s] and keyBindings[s][key] then
        keyBindings[s][key](key)
        return
    end
    -- Global fallback
    if keyBindings["*"] and keyBindings["*"][key] then
        keyBindings["*"][key](key)
        return
    end
    -- Delegate to current screen
    local screen = st.getScreen()
    if screen and screen.keypressed then
        screen.keypressed(key)
    end
end

function M.mousepressed(x, y, btn)
    local st = getState()
    local s = st.get()
    -- Explicit binding first
    if mousePressBindings[s] and mousePressBindings[s][btn] then
        mousePressBindings[s][btn](x, y, btn)
        return
    end
    -- Delegate to current screen
    local screen = st.getScreen()
    if screen and screen.mousepressed then
        screen.mousepressed(x, y, btn)
    end
end

function M.mousereleased(x, y, btn)
    local st = getState()
    local s = st.get()
    -- Explicit binding first
    if mouseReleaseBindings[s] and mouseReleaseBindings[s][btn] then
        mouseReleaseBindings[s][btn](x, y, btn)
        return
    end
    -- Delegate to current screen
    local screen = st.getScreen()
    if screen and screen.mousereleased then
        screen.mousereleased(x, y, btn)
    end
end

return M
