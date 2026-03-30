-- Space Sim - A Love2D Game

function love.load()
    love.window.setTitle("Space Sim")
    love.window.setMode(1280, 720, {resizable = true})
end

function love.update(dt)
end

function love.draw()
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end
