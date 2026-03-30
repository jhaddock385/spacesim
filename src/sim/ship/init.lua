local M = {}

local entities = require("src.sim.entities")
local spatial = require("src.sim.spatial")
local engineering = require("src.sim.ship.engineering")

-- Create a new ship entity with all subsystems initialized
-- config: {id=string|nil, x=number, y=number, rotation=number}
-- Returns the entity ID
function M.create(config)
    config = config or {}
    local id = entities.create("ship", config.id)

    -- Spatial component: position, velocity, physics
    spatial.init(id, {
        x = config.x or 0,
        y = config.y or 0,
        rotation = config.rotation or 0,
        mass = config.mass or 1,
    })

    -- Engineering component: warp core, power pips, thruster allocation
    engineering.init(id)

    return id
end

return M
