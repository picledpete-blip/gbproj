local ram = {}
ram.memory = {
    rom = {}, --0x0000 - 0x7fff 32kb
    vram = {}, --0x8000 - 0x9fff 8kb
    wram = {}, --0xc0000 - 0xdfff 8kb
    hram = {}, --0xff80 - 0xfffe
}
ram.intflag = 0x00 --0-4 vblank lcd timer serial joypad
ram.inten = 0x00
function ram:init()
    for addr = 0x8000, 0x9FFF do
        self.memory.vram[addr] = 0
    end
    for addr = 0xC000, 0xDFFF do
        self.memory.wram[addr] = 0
    end
    for addr = 0xFF80, 0xFFFE do
        self.memory.hram[addr] = 0
    end
end

function ram:ldrom(path)
    local file, err = io.open(path, "rb")

    local data = file:read("*a")
    file:close()
    local maxBytes = math.min(#data, 0x8000)
    for i = 1, maxBytes do
        self.memory.rom[i - 1] = string.byte(data, i)
    end
end



function ram:readb(addr)
    if addr >= 0x0000 and addr <= 0x7FFF then
        return self.memory.rom[addr] or 0xFF
    elseif addr >= 0x8000 and addr <= 0x9FFF then
        return self.memory.vram[addr]
    elseif addr >= 0xC000 and addr <= 0xDFFF then
        return self.memory.wram[addr]
    elseif addr >= 0xE000 and addr <= 0xFDFF then
        return self.memory.wram[addr - 0x2000]
    elseif addr == 0xff0f then
        return self.intflag
    elseif addr >= 0xFF80 and addr <= 0xFFFE then
        return self.hram[addr]
    elseif addr == 0xffff then
        return self.inten
    end
    return 0xFF
end

function ram:writeb(addr, val)
    val = val % 256

    if addr >= 0x8000 and addr <= 0x9FFF then
        self.memory.vram[addr] = val
    elseif addr >= 0xC000 and addr <= 0xDFFF then
        self.memory.wram[addr] = val
    elseif addr >= 0xE000 and addr <= 0xFDFF then
        self.memory.wram[addr - 0x2000] = val
    elseif addr == 0xff0f then
        self.intflag = val
    elseif addr >= 0xFF80 and addr <= 0xFFFE then
        self.memory.hram[addr] = val
    elseif addr == 0xffff then
        self.inten = val
    end
end

return ram