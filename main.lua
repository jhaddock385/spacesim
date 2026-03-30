local game = require("src.init")

function love.load()
    game.load()
end

function love.update(dt)
    game.update(dt)
end

function love.draw()
    game.draw()
end

function love.keypressed(key)
    game.keypressed(key)
end

function love.mousepressed(x, y, button)
    game.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    game.mousereleased(x, y, button)
end

function love.wheelmoved(x, y)
    game.wheelmoved(x, y)
end
