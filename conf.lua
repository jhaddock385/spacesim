function love.conf(t)
    t.identity = "spacesim"
    t.version = "11.4"

    t.window.title = "Space Sim"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.vsync = 1

    t.modules.joystick = false
    t.modules.physics = false
end
