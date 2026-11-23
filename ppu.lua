local bit = require("bit")
local ppu = {}

ppu.width = 160
ppu.height = 144

ppu.ram = nil
ppu.canvas = nil

ppu.palette = {
    {1, 1, 1},
    {0.66, 0.66, 0.66},
    {0.33, 0.33, 0.33},
    {0, 0, 0}
}

function ppu:init(ram)
    self.ram = ram

    self.canvas = love.graphics.newCanvas(
        self.width,
        self.height
    )
end

function ppu:getTilePixel(tile, x, y)

    local addr = 0x8000 + tile * 16 + y * 2

    local lo = self.ram:readb(addr)
    local hi = self.ram:readb(addr + 1)

    local bit1 = bit.band(bit.rshift(lo, 7 - x), 1)
    local bit2 = bit.band(bit.rshift(hi, 7 - x), 1)

    return bit1 + bit2 * 2
end

function ppu:render()

    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(1, 1, 1, 1)

    for y = 0, 143 do
        for x = 0, 159 do

            local tileX = math.floor(x / 8)
            local tileY = math.floor(y / 8)

            local pixelX = x % 8
            local pixelY = y % 8

            local mapAddr =
                0x9800 + tileY * 32 + tileX

            local tile = self.ram:readb(mapAddr)

            local color = self:getTilePixel(
                tile,
                pixelX,
                pixelY
            )

            local rgb = self.palette[color + 1]

            love.graphics.setColor(
                rgb[1],
                rgb[2],
                rgb[3],
                1
            )

            love.graphics.rectangle(
                "fill",
                x,
                y,
                1,
                1
            )
        end
    end

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
end
function ppu:draw()

    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.draw(
        self.canvas,
        0,
        0,
        0,
        4,
        4
    )
end

return ppu
