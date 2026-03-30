local M = {}

local Button = require("src.ui.button")
local TextInput = require("src.ui.textinput")
local _state

local bus = require("src.core.bus")
local store = require("src.core.store")
local clock = require("src.core.clock")
local api = require("src.core.api")
local log = require("src.core.log")
local sim = require("src.sim.init")
local ship = require("src.sim.ship.init")
local prompt = require("src.agents.prompt")
local json = require("lib.json")

local titleFont = nil
local labelFont = nil
local smallFont = nil
local backButton = nil
local modeButton = nil
local allocButtons = {}   -- thruster name -> {add=Button, remove=Button}
local shipId = nil
local commandInput = nil

-- Mode: "direct" (manual +/- buttons) or "comms" (AI crew)
local mode = "direct"

-- Comms state
local dialogueLog = {}    -- {speaker, text, color}
local MAX_DIALOGUE = 50
local conversationHistory = {}  -- API messages for multi-turn context
local MAX_HISTORY = 20          -- max message pairs to keep
local crewDef = {
    station = "helm",
    name = "Kim",
    rank = "Lieutenant",
}
local apiProcessing = false

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
local camScale = 1.0

local function addDialogue(speaker, text, color)
    table.insert(dialogueLog, {
        speaker = speaker,
        text = text,
        color = color or {0.8, 0.8, 0.8},
    })
    if #dialogueLog > MAX_DIALOGUE then
        table.remove(dialogueLog, 1)
    end
end

-- Process a single API response: extract speech, execute actions/queries
-- Returns list of tool_result messages if there are tool calls that need continuation
local function handleResponse(response)
    local toolResults = {}

    -- Extract speech
    local speechText = api.getResponseText(response)
    if speechText then
        addDialogue(crewDef.rank .. " " .. crewDef.name, speechText, {0.8, 0.8, 0.2})
    end

    -- Execute tool calls
    local toolCalls = api.getToolCalls(response)
    for _, call in ipairs(toolCalls) do
        local resolved = prompt.resolveToolCall(crewDef, call.name, call.input)
        if resolved then
            if resolved.query then
                -- Query: execute and prepare result for continuation
                local queryResult = prompt.executeQuery(crewDef, resolved.name, shipId)
                addDialogue("System",
                    crewDef.name .. " checked " .. resolved.name,
                    {0.5, 0.5, 0.5})
                log.write("CREW", crewDef.name .. " queried: " .. resolved.name)
                table.insert(toolResults, {
                    type = "tool_result",
                    tool_use_id = call.id,
                    content = queryResult,
                })
            else
                -- Action: emit as bus event
                bus.emit({
                    type = resolved.event_type,
                    target = shipId,
                    data = resolved.event_data,
                    source = "crew:" .. crewDef.station,
                })
                addDialogue("System",
                    crewDef.name .. " executed: " .. call.name
                    .. "(" .. formatToolInput(call.input) .. ")",
                    {0.4, 0.7, 0.4})
                log.write("CREW", crewDef.name .. " executed: " .. call.name)
                table.insert(toolResults, {
                    type = "tool_result",
                    tool_use_id = call.id,
                    content = "OK",
                })
            end
        else
            addDialogue("System",
                "Unknown action: " .. call.name,
                {1.0, 0.5, 0.3})
            log.write("ERROR", "Unknown action from crew: " .. call.name)
            table.insert(toolResults, {
                type = "tool_result",
                tool_use_id = call.id,
                content = "Error: unknown action",
                is_error = true,
            })
        end
    end

    return toolResults
end

-- Async state for the multi-turn API conversation
local asyncTurn = 0
local asyncSystemPrompt = nil
local asyncTools = nil
local MAX_TURNS = 5

-- Kick off an async API call with the current conversation history
local function startAsyncCall()
    asyncTurn = asyncTurn + 1
    log.write("API", "Starting async call, turn " .. asyncTurn
        .. ", history messages: " .. #conversationHistory)

    local ok, err = api.sendAsync(
        conversationHistory,
        {
            system = asyncSystemPrompt,
            tools = asyncTools,
            max_tokens = 512,
        }
    )

    if not ok then
        log.write("ERROR", "Failed to start async call: " .. tostring(err))
        addDialogue("System", "API error: " .. tostring(err), {1.0, 0.3, 0.3})
        apiProcessing = false
        log.flush()
    end
end

-- Handle a completed async response
local function handleAsyncResponse(response)
    local success, errorMsg = pcall(function()
        -- Remove "processing..." message
        if #dialogueLog > 0 and dialogueLog[#dialogueLog].speaker == "System"
           and dialogueLog[#dialogueLog].text:find("processing") then
            table.remove(dialogueLog)
        end

        if response.error then
            local errMsg = tostring(response.error.message or response.error.type or "unknown")
            log.write("ERROR", "API returned error: " .. errMsg)
            addDialogue("System", "API error: " .. errMsg, {1.0, 0.3, 0.3})
            apiProcessing = false
            log.flush()
            return
        end

        -- Log response
        log.write("API", "Turn " .. asyncTurn .. " stop_reason: " .. tostring(response.stop_reason))
        if response.content then
            for _, block in ipairs(response.content) do
                if block.type == "text" then
                    log.write("API", "Response text: " .. block.text)
                elseif block.type == "tool_use" then
                    log.write("API", "Response tool_use: " .. block.name
                        .. " input=" .. json.encode(block.input))
                end
            end
        end

        -- Add assistant response to history
        table.insert(conversationHistory, {
            role = "assistant",
            content = response.content,
        })

        -- Handle the response (speech + actions/queries)
        local toolResults = handleResponse(response)

        -- If stop_reason is "end_turn" or we've hit max turns, we're done
        if response.stop_reason == "end_turn" or asyncTurn >= MAX_TURNS then
            apiProcessing = false
            -- Trim conversation history
            while #conversationHistory > MAX_HISTORY * 2 do
                table.remove(conversationHistory, 1)
            end
            log.flush()
            return
        end

        -- If stop_reason is "tool_use", send results back for continuation
        if response.stop_reason == "tool_use" and #toolResults > 0 then
            table.insert(conversationHistory, {
                role = "user",
                content = toolResults,
            })
            log.write("API", "Sending " .. #toolResults .. " tool results for continuation")
            addDialogue("System", crewDef.rank .. " " .. crewDef.name .. " is processing...",
                {0.5, 0.5, 0.5})
            startAsyncCall()
        else
            apiProcessing = false
            log.flush()
        end
    end)

    if not success then
        log.write("ERROR", "handleAsyncResponse crashed: " .. tostring(errorMsg))
        log.flush()
        addDialogue("System", "ERROR: " .. tostring(errorMsg), {1.0, 0.2, 0.2})
        apiProcessing = false
    end
end

-- Process a captain's command — kicks off the async API pipeline
local function processCommand(command)
    if apiProcessing then return end

    addDialogue("Captain", command, {0.3, 0.8, 1.0})

    local success, errorMsg = pcall(function()
        log.write("CREW", "Captain command: " .. command)

        local ok, err = api.init()
        if not ok then
            log.write("ERROR", "API init failed: " .. tostring(err))
            addDialogue("System", "API init failed: " .. tostring(err), {1.0, 0.3, 0.3})
            return
        end

        apiProcessing = true
        asyncTurn = 0

        -- Build prompt and tools
        asyncSystemPrompt = prompt.buildSystemPrompt(crewDef, shipId)
        asyncTools = prompt.buildTools(crewDef)

        -- Add user message to conversation history
        table.insert(conversationHistory, { role = "user", content = command })

        log.write("API", "System prompt length: " .. #asyncSystemPrompt)
        log.write("API", "Tools: " .. #asyncTools)

        addDialogue("System", crewDef.rank .. " " .. crewDef.name .. " is processing...",
            {0.5, 0.5, 0.5})

        startAsyncCall()
    end)

    if not success then
        log.write("ERROR", "processCommand crashed: " .. tostring(errorMsg))
        log.flush()
        addDialogue("System", "ERROR: " .. tostring(errorMsg), {1.0, 0.2, 0.2})
        apiProcessing = false
    end
end

-- Format tool input for display
function formatToolInput(input)
    local parts = {}
    for k, v in pairs(input) do
        table.insert(parts, k .. "=" .. tostring(v))
    end
    return table.concat(parts, ", ")
end

-- Convert world coordinates to screen coordinates for the map viewport
local function worldToScreen(wx, wy)
    local sx = MAP_X + MAP_W / 2 + (wx - camX) * camScale
    local sy = MAP_Y + MAP_H / 2 + (wy - camY) * camScale
    return sx, sy
end

local function drawSpatialMap()
    love.graphics.setColor(0.05, 0.05, 0.1)
    love.graphics.rectangle("fill", MAP_X, MAP_Y, MAP_W, MAP_H)
    love.graphics.setColor(0.2, 0.2, 0.3)
    love.graphics.rectangle("line", MAP_X, MAP_Y, MAP_W, MAP_H)

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

    local ox, oy = worldToScreen(0, 0)
    if ox >= MAP_X and ox <= MAP_X + MAP_W and oy >= MAP_Y and oy <= MAP_Y + MAP_H then
        love.graphics.setColor(0.2, 0.2, 0.3)
        love.graphics.circle("line", ox, oy, 4)
    end

    love.graphics.setScissor(MAP_X, MAP_Y, MAP_W, MAP_H)

    if shipId then
        local spatial = store.getComponent(shipId, "spatial")
        if spatial then
            local sx, sy = worldToScreen(spatial.x, spatial.y)
            local rot = spatial.rotation
            local size = 12

            love.graphics.setColor(0.3, 0.8, 1.0)
            love.graphics.push()
            love.graphics.translate(sx, sy)
            love.graphics.rotate(rot)
            love.graphics.polygon("fill",
                size, 0, -size * 0.6, -size * 0.5, -size * 0.6, size * 0.5)
            love.graphics.setColor(0.5, 0.9, 1.0)
            love.graphics.polygon("line",
                size, 0, -size * 0.6, -size * 0.5, -size * 0.6, size * 0.5)
            love.graphics.pop()

            local speed = math.sqrt(spatial.vx * spatial.vx + spatial.vy * spatial.vy)
            if speed > 0.5 then
                love.graphics.setColor(0.3, 0.6, 0.3, 0.6)
                love.graphics.line(sx, sy,
                    sx + spatial.vx * 2.0, sy + spatial.vy * 2.0)
            end
        end
    end

    love.graphics.setScissor()

    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.5, 0.5, 0.5)
    if shipId then
        local spatial = store.getComponent(shipId, "spatial")
        if spatial then
            local speed = math.sqrt(spatial.vx * spatial.vx + spatial.vy * spatial.vy)
            love.graphics.print(
                string.format("pos: %.1f, %.1f  hdg: %.1f  spd: %.1f",
                    spatial.x, spatial.y, math.deg(spatial.rotation), speed),
                MAP_X + 5, MAP_Y + MAP_H + 2)
        end
    end
end

local function drawSystemPanel()
    love.graphics.setFont(labelFont)

    love.graphics.setColor(0.08, 0.08, 0.12)
    love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_W, 320)
    love.graphics.setColor(0.2, 0.2, 0.3)
    love.graphics.rectangle("line", PANEL_X, PANEL_Y, PANEL_W, 320)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Ship Systems", PANEL_X + 10, PANEL_Y + 8)

    if not shipId then return end

    local eng = store.getComponent(shipId, "engineering")
    if not eng then return end

    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.8, 0.8, 0.2)
    love.graphics.print(
        string.format("Warp Core: generating %.1f pips/sec", eng.pip_gen_rate),
        PANEL_X + 10, PANEL_Y + 35)

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

        -- +/- buttons only in direct mode
        if mode == "direct" and allocButtons[t.name] then
            love.graphics.setColor(0.8, 0.8, 0.8)
            love.graphics.print(tostring(pips), PANEL_X + 300, y + 5)
            allocButtons[t.name].add:draw()
            allocButtons[t.name].remove:draw()
        elseif mode == "comms" then
            love.graphics.setColor(0.4, 0.4, 0.4)
            love.graphics.print(tostring(pips) .. " pips", PANEL_X + 280, y + 5)
        end

        love.graphics.setColor(0.4, 0.4, 0.4)
        local desc = ""
        if t.name == "main" then desc = "Forward thrust"
        elseif t.name == "port" then desc = "Rotates starboard (clockwise)"
        elseif t.name == "starboard" then desc = "Rotates port (counter-clockwise)"
        end
        love.graphics.print(desc, PANEL_X + 120, y + 22)
    end
end

local function drawEventLog()
    love.graphics.setColor(0.05, 0.05, 0.08)
    love.graphics.rectangle("fill", PANEL_X, EVENT_LOG_Y, PANEL_W, EVENT_LOG_H)
    love.graphics.setColor(0.2, 0.2, 0.3)
    love.graphics.rectangle("line", PANEL_X, EVENT_LOG_Y, PANEL_W, EVENT_LOG_H)

    love.graphics.setFont(labelFont)
    love.graphics.setColor(1, 1, 1)

    if mode == "direct" then
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
            love.graphics.print(
                timeStr .. " " .. evt.type .. srcStr .. tgtStr,
                PANEL_X + 5, y)
        end

        love.graphics.setScissor()

    else  -- comms mode: show dialogue log
        love.graphics.print("Bridge Comms", PANEL_X + 10, EVENT_LOG_Y + 5)

        love.graphics.setScissor(PANEL_X, EVENT_LOG_Y + 24, PANEL_W, EVENT_LOG_H - 64)
        love.graphics.setFont(smallFont)

        local lineH = 14
        local logH = EVENT_LOG_H - 64
        local maxLines = math.floor(logH / lineH)

        -- Word-wrap and render dialogue
        local lines = {}
        local maxTextW = PANEL_W - 20
        for _, entry in ipairs(dialogueLog) do
            local prefix = entry.speaker .. ": "
            local wrapped = wrapText(smallFont, prefix .. entry.text, maxTextW)
            for _, wline in ipairs(wrapped) do
                table.insert(lines, { text = wline, color = entry.color })
            end
        end

        local startIdx = math.max(1, #lines - maxLines + 1)
        for i = startIdx, #lines do
            local line = lines[i]
            local y = EVENT_LOG_Y + 24 + (i - startIdx) * lineH
            love.graphics.setColor(line.color[1], line.color[2], line.color[3], 0.9)
            love.graphics.print(line.text, PANEL_X + 5, y)
        end

        love.graphics.setScissor()

        -- Draw text input
        if commandInput then
            commandInput:draw()
        end
    end
end

-- Simple word wrap
function wrapText(font, text, maxWidth)
    local lines = {}
    local currentLine = ""

    for word in text:gmatch("%S+") do
        local test = currentLine == "" and word or (currentLine .. " " .. word)
        if font:getWidth(test) <= maxWidth then
            currentLine = test
        else
            if currentLine ~= "" then
                table.insert(lines, currentLine)
            end
            currentLine = word
        end
    end
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end
    if #lines == 0 then
        table.insert(lines, "")
    end
    return lines
end

function M.onEnter()
    if not _state then _state = require("src.core.state") end
    if not titleFont then titleFont = love.graphics.newFont(20) end
    if not labelFont then labelFont = love.graphics.newFont(14) end
    if not smallFont then smallFont = love.graphics.newFont(11) end

    log.startSession()
    log.write("SESSION", "Log file: " .. log.getPath())
    sim.setup()

    shipId = ship.create({
        id = "player_ship",
        x = 0, y = 0, rotation = 0,
    })

    camX = 0
    camY = 0
    camScale = 2.0
    mode = "direct"
    dialogueLog = {}
    conversationHistory = {}
    apiProcessing = false

    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    backButton = Button.new({
        x = W - 140, y = H - 40, w = 120, h = 30,
        text = "Back to Menu",
        onClick = function() _state.set("menu") end,
    })

    modeButton = Button.new({
        x = 130, y = 34, w = 120, h = 22,
        text = "Switch to Comms",
        onClick = function() M.toggleMode() end,
    })

    -- Thruster allocation buttons (direct mode)
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

    -- Command text input (comms mode)
    commandInput = TextInput.new({
        x = PANEL_X + 2,
        y = EVENT_LOG_Y + EVENT_LOG_H - 34,
        w = PANEL_W - 4,
        h = 30,
        placeholder = "Give an order to " .. crewDef.rank .. " " .. crewDef.name .. "...",
        font = smallFont,
        onSubmit = function(text)
            processCommand(text)
        end,
    })
end

function M.onExit()
    sim.clear()
    backButton = nil
    modeButton = nil
    allocButtons = {}
    commandInput = nil
    shipId = nil
    dialogueLog = {}
    conversationHistory = {}

    local entities = require("src.sim.entities")
    entities.clear()
    store.clear()
    clock.clear()
end

function M.toggleMode()
    if mode == "direct" then
        mode = "comms"
        modeButton.text = "Switch to Direct"
        commandInput:focus()
    else
        mode = "direct"
        modeButton.text = "Switch to Comms"
        commandInput:blur()
    end
end

function M.update(dt)
    sim.update(dt)

    -- Poll for async API responses
    if apiProcessing and api.isAsyncPending() then
        local status, result = api.pollAsync()
        if status == "done" then
            handleAsyncResponse(result)
        elseif status == "error" then
            log.write("ERROR", "Async poll error: " .. tostring(result))
            addDialogue("System", "API error: " .. tostring(result), {1.0, 0.3, 0.3})
            apiProcessing = false
            -- Remove "processing..." message
            if #dialogueLog > 0 and dialogueLog[#dialogueLog].speaker == "System"
               and dialogueLog[#dialogueLog].text:find("processing") then
                table.remove(dialogueLog)
            end
            log.flush()
        end
    end

    if backButton then backButton:update() end
    if modeButton then modeButton:update() end

    if mode == "direct" then
        for _, btns in pairs(allocButtons) do
            btns.add:update()
            btns.remove:update()
        end
    end

    if shipId then
        camX = store.get(shipId, "spatial", "x") or 0
        camY = store.get(shipId, "spatial", "y") or 0
    end
end

function M.draw()
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Simulator", 20, 10)

    love.graphics.setFont(smallFont)
    love.graphics.setColor(0.6, 0.6, 0.6)
    local timeStr = string.format("T: %.1f  %s  [%s]",
        clock.getSimTime(),
        clock.isFrozen() and "FROZEN" or "",
        mode == "direct" and "Direct Control" or "Comms: " .. crewDef.name)
    love.graphics.print(timeStr, 160, 14)

    if modeButton then modeButton:draw() end

    drawSpatialMap()
    drawSystemPanel()
    drawEventLog()

    if backButton then backButton:draw() end
end

function M.keypressed(key)
    if mode == "comms" and commandInput then
        if commandInput:keypressed(key) then return end
    end
end

function M.mousepressed(x, y, btn)
    if backButton then backButton:mousepressed(x, y, btn) end
    if modeButton then modeButton:mousepressed(x, y, btn) end

    if mode == "direct" then
        for _, btns in pairs(allocButtons) do
            btns.add:mousepressed(x, y, btn)
            btns.remove:mousepressed(x, y, btn)
        end
    elseif mode == "comms" and commandInput then
        commandInput:mousepressed(x, y, btn)
    end
end

function M.mousereleased(x, y, btn)
    if backButton then backButton:mousereleased(x, y, btn) end
    if modeButton then modeButton:mousereleased(x, y, btn) end

    if mode == "direct" then
        for _, btns in pairs(allocButtons) do
            btns.add:mousereleased(x, y, btn)
            btns.remove:mousereleased(x, y, btn)
        end
    end
end

function M.textinput(t)
    if mode == "comms" and commandInput then
        commandInput:textinput(t)
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
