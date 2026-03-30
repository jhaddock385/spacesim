local TextInput = {}
TextInput.__index = TextInput

function TextInput.new(config)
    return setmetatable({
        x = config.x,
        y = config.y,
        w = config.w,
        h = config.h,
        text = "",
        cursor = 0,
        focused = config.focused or false,
        onSubmit = config.onSubmit,
        placeholder = config.placeholder or "",
        font = config.font,
        maxLength = config.maxLength or 500,
    }, TextInput)
end

function TextInput:focus()
    self.focused = true
    love.keyboard.setTextInput(true)
end

function TextInput:blur()
    self.focused = false
    love.keyboard.setTextInput(false)
end

function TextInput:textinput(t)
    if not self.focused then return end
    if #self.text >= self.maxLength then return end

    self.text = self.text:sub(1, self.cursor) .. t .. self.text:sub(self.cursor + 1)
    self.cursor = self.cursor + #t
end

function TextInput:keypressed(key)
    if not self.focused then return false end

    if key == "return" or key == "kpenter" then
        if #self.text > 0 and self.onSubmit then
            local submitted = self.text
            self.text = ""
            self.cursor = 0
            self.onSubmit(submitted)
        end
        return true
    elseif key == "backspace" then
        if self.cursor > 0 then
            self.text = self.text:sub(1, self.cursor - 1) .. self.text:sub(self.cursor + 1)
            self.cursor = self.cursor - 1
        end
        return true
    elseif key == "delete" then
        if self.cursor < #self.text then
            self.text = self.text:sub(1, self.cursor) .. self.text:sub(self.cursor + 2)
        end
        return true
    elseif key == "left" then
        self.cursor = math.max(0, self.cursor - 1)
        return true
    elseif key == "right" then
        self.cursor = math.min(#self.text, self.cursor + 1)
        return true
    elseif key == "home" then
        self.cursor = 0
        return true
    elseif key == "end" then
        self.cursor = #self.text
        return true
    end

    return false
end

function TextInput:mousepressed(x, y, btn)
    if btn ~= 1 then return end
    if x >= self.x and x <= self.x + self.w
       and y >= self.y and y <= self.y + self.h then
        self:focus()
    else
        self:blur()
    end
end

function TextInput:draw()
    local font = self.font or love.graphics.getFont()

    -- Background
    if self.focused then
        love.graphics.setColor(0.12, 0.12, 0.18)
    else
        love.graphics.setColor(0.08, 0.08, 0.12)
    end
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 4, 4)

    -- Border
    if self.focused then
        love.graphics.setColor(0.4, 0.4, 0.7)
    else
        love.graphics.setColor(0.2, 0.2, 0.3)
    end
    love.graphics.rectangle("line", self.x, self.y, self.w, self.h, 4, 4)

    -- Text or placeholder
    love.graphics.setScissor(self.x + 4, self.y, self.w - 8, self.h)
    love.graphics.setFont(font)

    local textY = self.y + (self.h - font:getHeight()) / 2

    if #self.text == 0 and not self.focused then
        love.graphics.setColor(0.3, 0.3, 0.4)
        love.graphics.print(self.placeholder, self.x + 8, textY)
    else
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(self.text, self.x + 8, textY)
    end

    -- Cursor
    if self.focused then
        local cursorX = self.x + 8 + font:getWidth(self.text:sub(1, self.cursor))
        love.graphics.setColor(0.8, 0.8, 1.0, math.abs(math.sin(love.timer.getTime() * 3)))
        love.graphics.rectangle("fill", cursorX, self.y + 4, 1, self.h - 8)
    end

    love.graphics.setScissor()
end

function TextInput:clear()
    self.text = ""
    self.cursor = 0
end

return TextInput
