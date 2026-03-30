local M = {}

local Button = require("src.ui.button")
local _state

local backButton = nil
local titleFont = nil
local bodyFont = nil

function M.onEnter()
    if not _state then _state = require("src.core.state") end
    if not titleFont then
        titleFont = love.graphics.newFont(28)
    end
    if not bodyFont then
        bodyFont = love.graphics.newFont(16)
    end

    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    backButton = Button.new({
        x = (W - 160) / 2, y = H - 120, w = 160, h = 44,
        text = "Back to Menu",
        onClick = function() _state.set("menu") end,
    })
end

function M.onExit()
    backButton = nil
end

function M.update(dt)
    if backButton then backButton:update() end
end

function M.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 1, 1)
    local title = "Game Run"
    love.graphics.print(title, (W - titleFont:getWidth(title)) / 2, 80)

    love.graphics.setFont(bodyFont)
    love.graphics.setColor(0.7, 0.7, 0.7)
    local desc = "This is where the game will be played."
    love.graphics.print(desc, (W - bodyFont:getWidth(desc)) / 2, H / 2 - 10)

    love.graphics.setFont(bodyFont)
    if backButton then backButton:draw() end
end

function M.mousepressed(x, y, btn)
    if backButton then backButton:mousepressed(x, y, btn) end
end

function M.mousereleased(x, y, btn)
    if backButton then backButton:mousereleased(x, y, btn) end
end

return M
