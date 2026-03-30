-- Station definitions: what each station can see, do, and query.
-- Used by the prompt builder to construct AI crew prompts and
-- to enforce boundaries on what actions a crew member can take.

local M = {}

M.helm = {
    name = "Helm",
    role = "Helm Officer",
    description = "Controls ship navigation, heading, and thruster power allocation.",

    -- Store paths this station can read (for state snapshots in prompts)
    visible_state = {
        { component = "spatial", keys = {"x", "y", "vx", "vy", "rotation", "rotVel"} },
        { component = "engineering", keys = {
            "pip_pool", "max_pip_pool", "pip_gen_rate",
            "thruster_main", "thruster_port", "thruster_starboard",
        }},
    },

    -- Actions this station can take (become Claude API tools)
    actions = {
        {
            name = "allocate_thruster",
            description = "Move a power pip from the pool to a thruster. Each pip increases that thruster's output.",
            parameters = {
                {
                    name = "thruster",
                    type = "string",
                    description = "Which thruster to power: 'main' (forward thrust), 'port' (rotates ship starboard/clockwise), or 'starboard' (rotates ship port/counter-clockwise).",
                    enum = {"main", "port", "starboard"},
                },
            },
            -- Maps to this bus event
            event_type = "engineering.allocate",
            event_data = function(params)
                return { thruster = params.thruster }
            end,
        },
        {
            name = "deallocate_thruster",
            description = "Remove a power pip from a thruster and return it to the pool.",
            parameters = {
                {
                    name = "thruster",
                    type = "string",
                    description = "Which thruster to depower: 'main', 'port', or 'starboard'.",
                    enum = {"main", "port", "starboard"},
                },
            },
            event_type = "engineering.deallocate",
            event_data = function(params)
                return { thruster = params.thruster }
            end,
        },
    },

    -- Queries this station can run (read-only, return formatted info)
    queries = {
        {
            name = "read_navigation",
            description = "Get current navigation status: position, heading, speed, and thruster power allocation.",
        },
    },
}

-- Look up a station by name
function M.get(stationName)
    return M[stationName]
end

-- Get the list of all station names
function M.all()
    local names = {}
    for k, v in pairs(M) do
        if type(v) == "table" and v.name then
            table.insert(names, k)
        end
    end
    return names
end

return M
