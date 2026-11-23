local bit = require("bit")
local ppu = {}
ppu.ly = 0
ppu.mode = 2
ppu.cycles = 0
ppu.width = 160
ppu.height = 144
ppu.frame_ready = false
ppu.ram = nil
ppu.canvas = nil

ppu.palette = {
    {1, 1, 1},
    {0.66, 0.66, 0.66},
    {0.33, 0.33, 0.33},
    {0, 0, 0}
}
function ppu:setMode(mode)
    self.mode = mode

    local stat = self.ram:readb(0xFF41)
    stat = bit.band(stat, 0xFC)
    stat = bit.bor(stat, mode)

    self.ram:writeb(0xFF41, stat)
end
function ppu:init(ram)
    self.ram = ram

    self.canvas = love.graphics.newCanvas(
        self.width,
        self.height
    )

    self.ly = 0
    self.mode = 2
    self.cycles = 0

    self.ram:writeb(0xFF44, 0)

    local stat = self.ram:readb(0xFF41)
    stat = bit.band(stat, 0xFC)
    stat = bit.bor(stat, 2)
    self.ram:writeb(0xFF41, stat)
end

function ppu:getTilePixel(tile, x, y)
    local lcdc = self.ram:readb(0xFF40)
    local addr

    if bit.band(lcdc, 0x10) ~= 0 then
        addr = 0x8000 + tile * 16
    else
        if tile >= 128 then
            tile = tile - 256
        end

        addr = 0x9000 + tile * 16
    end

    addr = addr + y * 2

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

            local lcdc = self.ram:readb(0xFF40)

            local mapBase = 0x9800

            if bit.band(lcdc, 0x08) ~= 0 then
                mapBase = 0x9C00
            end

            local mapAddr = mapBase + tileY * 32 + tileX
            local tile = self.ram:readb(mapAddr)

            local color = self:getTilePixel(tile, pixelX, pixelY)

            -- Apply the background palette
            local bgp = self.ram:readb(0xFF47)
            local shade = bit.band(
                bit.rshift(bgp, color * 2),
                0x03
            )

            local rgb = self.palette[shade + 1]

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
function ppu:tick(cycles)
    self.cycles = self.cycles + cycles

    while true do
        if self.mode == 2 and self.cycles >= 80 then
            self.cycles = self.cycles - 80
            self:setMode(3)

        elseif self.mode == 3 and self.cycles >= 172 then
            self.cycles = self.cycles - 172
            self:setMode(0)

        elseif self.mode == 0 and self.cycles >= 204 then
            self.cycles = self.cycles - 204

            self.ly = self.ly + 1
            self.ram:writeb(0xFF44, self.ly)

            if self.ly == 144 then
                self:setMode(1)
                self.frame_ready = true

                local flags = self.ram:readb(0xFF0F)
                self.ram:writeb(0xFF0F, bit.bor(flags, 0x01))
            else
                self:setMode(2)
            end

        elseif self.mode == 1 and self.cycles >= 456 then
            self.cycles = self.cycles - 456

            self.ly = self.ly + 1

            if self.ly > 153 then
                self.ly = 0
                self.ram:writeb(0xFF44, 0)
                self:setMode(2)
            else
                self.ram:writeb(0xFF44, self.ly)
            end

        else
            break
        end
    end
end
return ppu
