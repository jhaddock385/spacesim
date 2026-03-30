local M = {}

local Button = require("src.ui.button")
local _state

local bus = require("src.core.bus")
local store = require("src.core.store")
local clock = require("src.core.clock")
local sim = require("src.sim.init")
local ship = require("src.sim.ship.init")

local titleFont = nil
local labelFont = nil
local smallFont = nil
local backButton = nil
local allocButtons = {}   -- thruster name -> {add=Button, remove=Button}
local shipId = nil

-- Layout constants
local MAP_X = 20
local MAP_Y = 60
local MAP_W = 700
local MAP_H = 600
local PANEL_X = 740
local PANEL_Y = 60
local PANEL_W = 520
local EVENT_LOG_Y = 400
local EVENT_LOG_H = 260

-- Camera state
local camX = 0
local camY = 0
local camScale = 1.0    -- pixels per world unit

-- Convert world coordinates to screen coordinates for the map viewport
local function worldToScreen(wx, wy)
    local sx = MAP_X + MAP_W / 2 + (wx - camX) * camScale
    local sy = MAP_Y + MAP_H / 2 + (wy - camY) * camScale
    return sx, sy
end

local function drawSpatialMap()
    -- Map background
    love.graphics.setColor(0.05, 0.05, 0.1)
    love.graphics.rectangle("fill", MAP_X, MAP_Y, MAP_W, MAP_H)
    love.graphics.setColor(0.2, 0.2, 0.3)
    love.graphics.rectangle("line", MAP_X, MAP_Y, MAP_W, MAP_H)

    -- Grid lines
    love.graphics.setColor(0.1, 0.1, 0.15)
    local gridSpacing = 50 * camScale
    if gridSpacing > 10 then
        local startWX = camX - MAP_W / 2 / camScale
        local startWY = camY - MAP_H / 2 / camScale
        local gridSnap = 50
        local gx0 = math.floor(startWX / gridSnap) * gridSnap
        local gy0 = math.floor(startWY / gridSnap) * gridSnap

        for gx = gx0, gx0 + MAP_W / camScale + gridSnap, gridSnap do
            local sx, _ = worldToScreen(gx, 0)
            if sx >= MAP_X and sx <= MAP_X + MAP_W then
                love.graphics.line(sx, MAP_Y, sx, MAP_Y + MAP_H)
            end
        end
        for gy = gy0, gy0 + MAP_H / camScale + gridSnap, gridSnap do
            local _, sy = worldToScreen(0, gy)
            if sy >= MAP_Y and sy <= MAP_Y + MAP_H then
                love.graphics.line(MAP_X, sy, MAP_X + MAP_W, sy)
            end
        end
    end

    -- Origin marker
    local ox, oy = worldToScreen(0, 0)
    if ox >= MAP_X and ox <= MAP_X + MAP_W and oy >= MAP_Y and oy <= MAP_Y + MAP_H then
        love.graphics.setColor(0.2, 0.2, 0.3)
        love.graphics.circle("line", ox, oy, 4)
    end

    -- Scissor to map bounds
    love.graphics.setScissor(MAP_X, MAP_Y, MAP_W, MAP_H)

    -- Draw ship
    if shipId then
        local spatial = store.getComponent(shipId, "spatial")
        if spatial then
            local sx, sy = worldToScreen(spatial.x, spatial.y)
            local rot = spatial.rotation

            -- Triangle pointing in heading direction
            local size = 12
            love.graphics.setColor(0.3, 0.8, 1.0)
            love.graphics.push()
            love.graphics.translate(sx, sy)
            love.graphics.rotate(rot)
            love.graphics.polygon("fill",
                size, 0,                       -- nose
                -size * 0.6, -size * 0.5,      -- port wing
                -size * 0.6, size * 0.5        -- starboard wing
            )
            love.graphics.setColor(0.5, 0.9, 1.0)
            love.graphics.polygon("line",
                size, 0,
                -size * 0.6, -size * 0.5,
                -size * 0.6, size * 0.5
            )
            love.graphics.pop()

            -- Velocity vector
            local speed = math.sqrt(spatial.vx * spatial.vx + spatial.vy * spatial.vy)
            if speed > 0.5 then
                love.graphics.setColor(0.3, 0.6, 0.3, 0.6)
                local vScale = 2.0
                love.graphics.line(sx, sy,
                    sx + spatial.vx * vScale,
                    sy + spatial.vy * vScale)
            end
        end
    end

    love.graphics.setScissor()

    -- Map overlay: coordinates
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.5, 0.5, 0.5)
    if shipId then
        local spatial = store.getComponent(shipId, "spatial")
        if spatial then
            local speed = math.sqrt(spatial.vx * spatial.vx + spatial.vy * spatial.vy)
            local degRot = math.deg(spatial.rotation)
            love.graphics.print(
                string.format("pos: %.1f, %.1f  hdg: %.1f  spd: %.1f",
                    spatial.x, spatial.y, degRot, speed),
                MAP_X + 5, MAP_Y + MAP_H + 2)
        end
    end
end

local function drawSystemPanel()
    love.graphics.setFont(labelFont)

    -- Panel background
    love.graphics.setColor(0.08, 0.08, 0.12)
    love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_W, 320)
    love.graphics.setColor(0.2, 0.2, 0.3)
    love.graphics.rectangle("line", PANEL_X, PANEL_Y, PANEL_W, 320)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Ship Systems", PANEL_X + 10, PANEL_Y + 8)

    if not shipId then return end

    local eng = store.getComponent(shipId, "engineering")
    if not eng then return end

    -- Warp core / pip pool
    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.8, 0.8, 0.2)
    love.graphics.print(
        string.format("Warp Core: generating %.1f pips/sec", eng.pip_gen_rate),
        PANEL_X + 10, PANEL_Y + 35)

    -- Pip pool visualization
    love.graphics.setColor(0.6, 0.6, 0.6)
    love.graphics.print("Power Pool:", PANEL_X + 10, PANEL_Y + 55)

    local pipStartX = PANEL_X + 100
    for i = 1, eng.max_pip_pool do
        if i <= eng.pip_pool then
            love.graphics.setColor(0.2, 0.8, 0.2)
        else
            love.graphics.setColor(0.2, 0.2, 0.2)
        end
        love.graphics.rectangle("fill", pipStartX + (i - 1) * 16, PANEL_Y + 54, 12, 12)
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.rectangle("line", pipStartX + (i - 1) * 16, PANEL_Y + 54, 12, 12)
    end

    -- Thruster allocations
    local thrusters = {
        {name = "main", label = "Main Thruster", color = {0.3, 0.8, 1.0}},
        {name = "port", label = "Port Thruster", color = {1.0, 0.5, 0.3}},
        {name = "starboard", label = "Stbd Thruster", color = {0.3, 1.0, 0.5}},
    }

    for i, t in ipairs(thrusters) do
        local y = PANEL_Y + 80 + (i - 1) * 60

        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.print(t.label .. ":", PANEL_X + 10, y + 5)

        local pips = eng["thruster_" .. t.name] or 0

        -- Pip visualization for this thruster
        for p = 1, 10 do
            if p <= pips then
                love.graphics.setColor(t.color[1], t.color[2], t.color[3])
            else
                love.graphics.setColor(0.15, 0.15, 0.15)
            end
            love.graphics.rectangle("fill", PANEL_X + 120 + (p - 1) * 16, y + 4, 12, 12)
            love.graphics.setColor(0.3, 0.3, 0.3)
            love.graphics.rectangle("line", PANEL_X + 120 + (p - 1) * 16, y + 4, 12, 12)
        end

        -- Draw +/- buttons
        if allocButtons[t.name] then
            -- Pip count text
            love.graphics.setColor(0.8, 0.8, 0.8)
            love.graphics.print(tostring(pips), PANEL_X + 300, y + 5)

            allocButtons[t.name].add:draw()
            allocButtons[t.name].remove:draw()
        end

        -- Thruster description
        love.graphics.setColor(0.4, 0.4, 0.4)
        local desc = ""
        if t.name == "main" then
            desc = "Forward thrust"
        elseif t.name == "port" then
            desc = "Rotates starboard (clockwise)"
        elseif t.name == "starboard" then
            desc = "Rotates port (counter-clockwise)"
        end
        love.graphics.print(desc, PANEL_X + 120, y + 22)
    end
end

local function drawEventLog()
    -- Event log panel
    love.graphics.setColor(0.05, 0.05, 0.08)
    love.graphics.rectangle("fill", PANEL_X, EVENT_LOG_Y, PANEL_W, EVENT_LOG_H)
    love.graphics.setColor(0.2, 0.2, 0.3)
    love.graphics.rectangle("line", PANEL_X, EVENT_LOG_Y, PANEL_W, EVENT_LOG_H)

    love.graphics.setFont(labelFont)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Event Log", PANEL_X + 10, EVENT_LOG_Y + 5)

    love.graphics.setScissor(PANEL_X, EVENT_LOG_Y + 24, PANEL_W, EVENT_LOG_H - 28)
    love.graphics.setFont(smallFont)

    local history = bus.getHistory()
    local lineH = 14
    local maxLines = math.floor((EVENT_LOG_H - 28) / lineH)
    local startIdx = math.max(1, #history - maxLines + 1)

    for i = startIdx, #history do
        local evt = history[i]
        local y = EVENT_LOG_Y + 24 + (i - startIdx) * lineH

        -- Color by event type
        if evt.type:find("^engineering") then
            love.graphics.setColor(0.8, 0.8, 0.2, 0.8)
        elseif evt.type:find("^spatial") then
            love.graphics.setColor(0.3, 0.8, 1.0, 0.8)
        elseif evt.type:find("^entity") then
            love.graphics.setColor(0.5, 0.5, 0.5, 0.8)
        elseif evt.type:find("^bus") then
            love.graphics.setColor(1.0, 0.3, 0.3, 0.8)
        else
            love.graphics.setColor(0.6, 0.6, 0.6, 0.8)
        end

        local timeStr = string.format("%.2f", evt.time or 0)
        local srcStr = evt.source and (" src:" .. evt.source) or ""
        local tgtStr = evt.target and (" tgt:" .. evt.target) or ""
        local line = timeStr .. " " .. evt.type .. srcStr .. tgtStr

        love.graphics.print(line, PANEL_X + 5, y)
    end

    love.graphics.setScissor()
end

function M.onEnter()
    if not _state then _state = require("src.core.state") end
    if not titleFont then
        titleFont = love.graphics.newFont(20)
    end
    if not labelFont then
        labelFont = love.graphics.newFont(14)
    end
    if not smallFont then
        smallFont = love.graphics.newFont(11)
    end

    -- Set up simulation systems
    sim.setup()

    -- Create the player ship at center of world
    shipId = ship.create({
        id = "player_ship",
        x = 0,
        y = 0,
        rotation = 0,
    })

    camX = 0
    camY = 0
    camScale = 2.0

    -- Back button
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    backButton = Button.new({
        x = W - 140, y = H - 40, w = 120, h = 30,
        text = "Back to Menu",
        onClick = function() _state.set("menu") end,
    })

    -- Thruster allocation buttons
    local thrusters = {"main", "port", "starboard"}
    allocButtons = {}
    for i, name in ipairs(thrusters) do
        local btnY = PANEL_Y + 80 + (i - 1) * 60
        allocButtons[name] = {
            add = Button.new({
                x = PANEL_X + 240, y = btnY, w = 30, h = 30,
                text = "+",
                onClick = function()
                    bus.emit({
                        type = "engineering.allocate",
                        target = shipId,
                        data = { thruster = name },
                    })
                end,
            }),
            remove = Button.new({
                x = PANEL_X + 280, y = btnY, w = 30, h = 30,
                text = "-",
                onClick = function()
                    bus.emit({
                        type = "engineering.deallocate",
                        target = shipId,
                        data = { thruster = name },
                    })
                end,
            }),
        }
    end
end

function M.onExit()
    sim.clear()
    backButton = nil
    allocButtons = {}
    shipId = nil

    local entities = require("src.sim.entities")
    entities.clear()
    store.clear()
    clock.clear()
end

function M.update(dt)
    sim.update(dt)

    if backButton then backButton:update() end
    for _, btns in pairs(allocButtons) do
        btns.add:update()
        btns.remove:update()
    end

    -- Camera follows ship
    if shipId then
        local sx = store.get(shipId, "spatial", "x") or 0
        local sy = store.get(shipId, "spatial", "y") or 0
        camX = sx
        camY = sy
    end
end

function M.draw()
    -- Title bar
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Simulator", 20, 10)

    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.6, 0.6, 0.6)
    local timeStr = string.format("T: %.1f  %s",
        clock.getSimTime(),
        clock.isFrozen() and "[FROZEN]" or "")
    love.graphics.print(timeStr, 160, 14)

    drawSpatialMap()
    drawSystemPanel()
    drawEventLog()

    if backButton then backButton:draw() end
end

function M.mousepressed(x, y, btn)
    if backButton then backButton:mousepressed(x, y, btn) end
    for _, btns in pairs(allocButtons) do
        btns.add:mousepressed(x, y, btn)
        btns.remove:mousepressed(x, y, btn)
    end
end

function M.mousereleased(x, y, btn)
    if backButton then backButton:mousereleased(x, y, btn) end
    for _, btns in pairs(allocButtons) do
        btns.add:mousereleased(x, y, btn)
        btns.remove:mousereleased(x, y, btn)
    end
end

function M.wheelmoved(x, y)
    if y > 0 then
        camScale = math.min(camScale * 1.2, 20)
    elseif y < 0 then
        camScale = math.max(camScale / 1.2, 0.1)
    end
end

return M
