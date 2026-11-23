
local cpu = require("cpu")
local ppu = require("ppu")

function love.load()
    cpu:init()
    ppu:init(cpu.ram)
    love.window.setMode(640, 576)
end

function love.update(dt)
    local success, result = xpcall(function()
        cpu:runit()
    end, function(err)
        return cpu:dump(err)
    end)
    if not success then
        error(result, 0)
    end
    ppu:render()
end

function love.draw()
    love.graphics.clear(0, 0, 0)
    ppu:draw()
end
