local Button = {}
Button.__index = Button

function Button.new(config)
    return setmetatable({
        x = config.x,
        y = config.y,
        w = config.w,
        h = config.h,
        text = config.text or "",
        onClick = config.onClick,
        hover = false,
        pressed = false,
    }, Button)
end

function Button:containsPoint(px, py)
    return px >= self.x and px <= self.x + self.w
       and py >= self.y and py <= self.y + self.h
end

function Button:mousepressed(x, y, btn)
    if btn == 1 and self:containsPoint(x, y) then
        self.pressed = true
    end
end

function Button:mousereleased(x, y, btn)
    if btn == 1 and self.pressed then
        self.pressed = false
        if self:containsPoint(x, y) and self.onClick then
            self.onClick()
        end
    end
end

function Button:update()
    local mx, my = love.mouse.getPosition()
    self.hover = self:containsPoint(mx, my)
end

function Button:draw()
    -- Background
    if self.pressed then
        love.graphics.setColor(0.3, 0.3, 0.5)
    elseif self.hover then
        love.graphics.setColor(0.2, 0.2, 0.4)
    else
        love.graphics.setColor(0.15, 0.15, 0.3)
    end
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 6, 6)

    -- Border
    if self.hover then
        love.graphics.setColor(0.5, 0.5, 0.8)
    else
        love.graphics.setColor(0.3, 0.3, 0.5)
    end
    love.graphics.rectangle("line", self.x, self.y, self.w, self.h, 6, 6)

    -- Label (centered)
    love.graphics.setColor(1, 1, 1)
    local font = love.graphics.getFont()
    local tw = font:getWidth(self.text)
    local th = font:getHeight()
    love.graphics.print(self.text,
        self.x + (self.w - tw) / 2,
        self.y + (self.h - th) / 2)
end

function Button:reset()
    self.pressed = false
    self.hover = false
end

return Button
