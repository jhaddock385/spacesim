local M = {}

local Button = require("src.ui.button")
local _state

local buttons = {}
local titleFont = nil
local bodyFont = nil

function M.onEnter()
    if not _state then _state = require("src.core.state") end
    if not titleFont then
        titleFont = love.graphics.newFont(32)
    end
    if not bodyFont then
        bodyFont = love.graphics.newFont(16)
    end

    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    local bw, bh = 220, 50
    local x = (W - bw) / 2
    local startY = H / 2 - 60
    local gap = 70

    buttons = {
        Button.new({
            x = x, y = startY, w = bw, h = bh,
            text = "Start Run",
            onClick = function() _state.set("play") end,
        }),
        Button.new({
            x = x, y = startY + gap, w = bw, h = bh,
            text = "Simulator",
            onClick = function() _state.set("simulator") end,
        }),
        Button.new({
            x = x, y = startY + gap * 2, w = bw, h = bh,
            text = "Options",
            onClick = function() _state.set("options") end,
        }),
        Button.new({
            x = x, y = startY + gap * 3, w = bw, h = bh,
            text = "Quit",
            onClick = function() love.event.quit() end,
        }),
    }
end

function M.onExit()
    buttons = {}
end

function M.update(dt)
    for _, btn in ipairs(buttons) do
        btn:update()
    end
end

function M.draw()
    local W = love.graphics.getWidth()

    -- Title
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 1, 1)
    local title = "Space Sim"
    local tw = titleFont:getWidth(title)
    love.graphics.print(title, (W - tw) / 2, 80)

    -- Buttons
    love.graphics.setFont(bodyFont)
    for _, btn in ipairs(buttons) do
        btn:draw()
    end
end

function M.mousepressed(x, y, btn)
    for _, b in ipairs(buttons) do
        b:mousepressed(x, y, btn)
    end
end

function M.mousereleased(x, y, btn)
    for _, b in ipairs(buttons) do
        b:mousereleased(x, y, btn)
    end
end

return M
