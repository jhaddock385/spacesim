local M = {}

local state = require("src.core.state")
local input = require("src.core.input")

-- Register all screens
state.register("menu",      require("src.screens.menu"))
state.register("play",      require("src.screens.play"))
state.register("simulator", require("src.screens.simulator"))
state.register("options",   require("src.screens.options"))

-- Global: escape returns to menu, or quits from menu
input.bindKey("*", "escape", function()
    if state.get() == "menu" then
        love.event.quit()
    else
        state.set("menu")
    end
end)

function M.load()
    -- Load and run tests if --test flag is present
    local tests = require("tests")
    tests.load()
    tests.handleCLI()  -- exits if --test flag found

    state.set("menu")
end

function M.update(dt)
    state.update(dt)
end

function M.draw()
    state.draw()
end

function M.keypressed(key)
    input.keypressed(key)
end

function M.mousepressed(x, y, button)
    input.mousepressed(x, y, button)
end

function M.mousereleased(x, y, button)
    input.mousereleased(x, y, button)
end

function M.wheelmoved(x, y)
    local screen = state.getScreen()
    if screen and screen.wheelmoved then
        screen.wheelmoved(x, y)
    end
end

function M.textinput(t)
    local screen = state.getScreen()
    if screen and screen.textinput then
        screen.textinput(t)
    end
end

return M
