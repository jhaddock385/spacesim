local M = {}

local store = require("src.core.store")
local stations = require("src.data.stations")
local json = require("lib.json")

-- Behavioral framing: how all crew members should behave
local CREW_FRAMING = [[
You are a bridge officer aboard a starship. You respond to the captain's orders.

Rules:
- Execute orders using the tools available to you. You may call multiple tools in sequence.
- Always respond verbally to the captain — acknowledge orders, report what you're doing, flag problems.
- Keep verbal responses concise and professional. One to three sentences.
- If an order is unclear, ask for clarification rather than guessing.
- If an order is impossible (not enough power, system offline, etc.), explain why and suggest alternatives.
- If an order falls outside your station's responsibilities, say so and suggest which station handles it.
- Never invent or hallucinate ship state. Only reference information provided in your current state readout.
- You may call tools and speak in the same response. Always speak — never respond with only tool calls.
]]

-- Build the system prompt for a crew member
-- crewDef: {station=string, name=string, rank=string}
-- shipId: entity ID to read state from
function M.buildSystemPrompt(crewDef, shipId)
    local station = stations.get(crewDef.station)
    if not station then
        error("unknown station: " .. tostring(crewDef.station))
    end

    local parts = {}

    -- Identity
    table.insert(parts, string.format(
        "You are %s %s, %s aboard the ship.\n",
        crewDef.rank or "Officer", crewDef.name or "Unknown", station.role))

    -- Behavioral framing
    table.insert(parts, CREW_FRAMING)

    -- Working knowledge
    local knowledge = M._loadKnowledge(crewDef.station)
    if knowledge then
        table.insert(parts, "## Ship Systems Knowledge\n")
        table.insert(parts, knowledge)
        table.insert(parts, "")
    end

    -- Current state snapshot
    table.insert(parts, "## Current Ship State (Your Console)\n")
    table.insert(parts, M._buildStateSnapshot(station, shipId))

    return table.concat(parts, "\n")
end

-- Build the tools array for the Claude API from station actions
function M.buildTools(crewDef)
    local station = stations.get(crewDef.station)
    if not station then return {} end

    local tools = {}

    for _, action in ipairs(station.actions) do
        local properties = {}
        local required = {}

        for _, param in ipairs(action.parameters) do
            properties[param.name] = {
                type = param.type,
                description = param.description,
            }
            if param.enum then
                properties[param.name].enum = param.enum
            end
            table.insert(required, param.name)
        end

        table.insert(tools, {
            name = action.name,
            description = action.description,
            input_schema = {
                type = "object",
                properties = properties,
                required = required,
            },
        })
    end

    -- Add query tools
    if station.queries then
        for _, query in ipairs(station.queries) do
            table.insert(tools, {
                name = query.name,
                description = query.description,
                input_schema = {
                    type = "object",
                    properties = {},
                    required = json.emptyArray(),
                },
            })
        end
    end

    return tools
end

-- Load working knowledge for a station
function M._loadKnowledge(stationName)
    local ok, knowledgeModule = pcall(require, "src.data.knowledge." .. stationName)
    if ok and knowledgeModule and knowledgeModule.knowledge then
        return knowledgeModule.knowledge
    end
    return nil
end

-- Build a state snapshot string from a station's visible_state definition
function M._buildStateSnapshot(station, shipId)
    local lines = {}

    for _, block in ipairs(station.visible_state) do
        local comp = store.getComponent(shipId, block.component)
        if comp then
            for _, key in ipairs(block.keys) do
                local value = comp[key]
                if value ~= nil then
                    local display = value
                    -- Format rotation as degrees for readability
                    if key == "rotation" then
                        display = string.format("%.1f degrees", math.deg(value))
                    elseif type(value) == "number" then
                        if value == math.floor(value) then
                            display = tostring(value)
                        else
                            display = string.format("%.2f", value)
                        end
                    end
                    table.insert(lines, string.format("- %s.%s: %s",
                        block.component, key, tostring(display)))
                end
            end
        end
    end

    if #lines == 0 then
        return "No state data available.\n"
    end

    return table.concat(lines, "\n") .. "\n"
end

-- Resolve a tool call from the API response into a bus event
-- Returns: {event_type, event_data} or nil if not found
function M.resolveToolCall(crewDef, toolName, toolInput)
    local station = stations.get(crewDef.station)
    if not station then return nil end

    for _, action in ipairs(station.actions) do
        if action.name == toolName then
            return {
                event_type = action.event_type,
                event_data = action.event_data(toolInput),
            }
        end
    end

    -- Check queries
    if station.queries then
        for _, query in ipairs(station.queries) do
            if query.name == toolName then
                return { query = true, name = toolName }
            end
        end
    end

    return nil
end

-- Execute a query and return a result string
function M.executeQuery(crewDef, queryName, shipId)
    local station = stations.get(crewDef.station)
    if not station then return "Unknown station." end

    if queryName == "read_navigation" then
        return M._buildStateSnapshot(station, shipId)
    end

    return "Query not implemented: " .. queryName
end

return M
