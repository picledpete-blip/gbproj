
local cpu = require("cpu")
local ppu = require("ppu")

function love.load()
    cpu:init()
    ppu:init(cpu.ram)
    cpu.ppu = ppu
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

    if ppu.frame_ready then
        ppu.frame_ready = false
        ppu:render()
    end
end

function love.draw()
    love.graphics.clear(0, 0, 0)
    ppu:draw()
end
