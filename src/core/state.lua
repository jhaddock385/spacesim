local M = {}

local screens = {}   -- name -> screen module
local current = nil  -- current state name

function M.register(name, screen)
    screens[name] = screen
end

function M.set(name)
    if not screens[name] then
        error("Unknown state: " .. name)
    end
    local prev = current
    if current and screens[current].onExit then
        screens[current].onExit()
    end
    current = name
    if screens[current].onEnter then
        screens[current].onEnter(prev)
    end
end

function M.get()
    return current
end

function M.getScreen()
    if current then
        return screens[current]
    end
    return nil
end

function M.update(dt)
    if current and screens[current].update then
        screens[current].update(dt)
    end
end

function M.draw()
    if current and screens[current].draw then
        screens[current].draw()
    end
end

return M
