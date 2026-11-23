local cpu = {}
cpu.ram = require("ram")
local bit = require("bit")
cpu.ime = false
cpu.ei_pending = false
cpu.regs = {
    a = 0x00,
    b = 0x00,
    c = 0x00,
    d = 0x00,
    e = 0x00,
    f = 0x00,
    h = 0x00,
    l = 0x00,
    sp = 0x0000,
    pc = 0x0100
}
regslookup = {
    [0] = "a",
    [1] = "b",
    [2] = "c",
    [3] = "d",
    [4] = "e",
    [5] = "f",
    [6] = "h",
    [7] = "l",
    [8] = "sp",
    [9] = "pc",
}
--16 grouped af bc de hl

function cpu.regs:setreg(reg,val) -- 0-9 a-pc 11-14 af-hl
    if reg == 5 then
    self.f = val % 256 - (val % 16)
    return
    end
    if reg < 9 then
    self[regslookup[reg]] = val
    self[regslookup[reg]] = self[regslookup[reg]] % 256
    elseif reg < 11 then      
    self[regslookup[reg]] = val
    self[regslookup[reg]] = self[regslookup[reg]] % 65536
    else
        local lb = val % 256
        local hb = math.floor(val / 256) % 256
        if reg == 11 then
            self:setreg(0,hb)
            self:setreg(5,lb)
        elseif reg == 12 then
            self:setreg(1,hb)
            self:setreg(2,lb)
        elseif reg == 13 then
            self:setreg(3,hb)
            self:setreg(4,lb)
        elseif reg == 14 then
            self:setreg(6,hb)
            self:setreg(7,lb)
        end
    end
end

local FZ = 0x80
local FN = 0x40
local FH = 0x20
local FC = 0x10

function cpu.regs:getflag(mask)
    return math.floor(self.f / mask) % 2 == 1
end

function cpu.regs:setflag(mask, value)
    local current = self.f
    if self:getflag(mask) then
        current = current - mask
    end
    if value then
        current = current + mask
    end
    self.f = current % 256
end

function cpu:fetch8()
    local val = self.ram:readb(self.regs["pc"])
    self.regs["pc"] = (self.regs["pc"] + 1) % 65536
    return val
end

cpu.opcodes = {
    [0x00] = function (self)
        local pc = self.regs["pc"]
        return 4
    end,
    [0x05] = function (self)
        local b  = self.regs.b
        self.regs:setreg(1, b-1)
        self.regs:setflag(FZ, b-1 % 256 == 0)
        self.regs:setflag(FN, true)
        self.regs:setflag(FH, (b % 16) == 0)
        return 4
    end,
    [0x06] = function (self)
        local v = self:fetch8()
        self.regs:setreg(1, v)
        return 8
    end,
    [0x0d] = function (self)
        local c  = self.regs.c
        self.regs:setreg(2, c-1)
        self.regs:setflag(FZ, c-1 % 256 == 0)
        self.regs:setflag(FN, true)
        self.regs:setflag(FH, (c % 16) == 0)
        return 4
    end,
    [0x0e] = function (self)
        local v = self:fetch8()
        self.regs:setreg(2, v)
        return 8
    end,
    [0x20] = function (self)
        local offset = self:fetch8()
        if not cpu.regs:getflag(FZ) then
            if offset > 127 then
                offset = offset - 256
            end
            cpu.regs:setreg(9, cpu.regs.pc + offset)
            return 12
        end
        return 8
    end,
    [0x21] = function (self)
        local l = self:fetch8()
        local h = self:fetch8()
        self.regs:setreg(14, h*256+l)
        return 12
    end,
    [0x32] = function (self)
        local hl = (self.regs["h"] * 256) + self.regs["l"]
        local a = self.regs.a
        self.ram:writeb(hl,a)
        self.regs:setreg(14,hl-1)
        return 8
    end,
    [0x3e] = function (self)
        local v = self:fetch8()
        self.regs:setreg(0, v)
        return 8
    end,
    [0x80] = function(self)
        local a = self.regs.a
        local b = self.regs.b

        local result = a + b

        self.regs:setflag(FZ, result % 256 == 0)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, (a % 16) + (b % 16) > 15)
        self.regs:setflag(FC, result > 255)

        self.regs.a = result % 256

        return 4
    end,
    [0xaf] = function (self)
        self.regs:setreg(0,0)
        self.regs:setflag(FZ, true)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, false)
        self.regs:setflag(FC, false)

        return 4
    end,
    [0xc3] = function (self)
        local pc = self.regs["pc"]
        local l = self.ram:readb(pc)
        local h = self.ram:readb(pc+1)
        local naddr = (h * 256) + l
        self.regs:setreg(9,naddr)
        return 16
    end,
    [0xf3] = function (self)
        self.ime = false
        return 4
    end,
    [0xfb] = function (self)
        self.ime = true
        return 4
    end,

}

function cpu:dump()
    return "error " .. self.fb0 .. " " .. self.fb1 .. " at" .. self.fpc
end


function cpu:init()
    cpu.ram:init()
    cpu.ram:ldrom("tetris.gb")
end

cpu:handint()
    local ints = bit.band(self.ram:readb(0xff0f), self.ram:readb(0xffff))
end

local cpf = 70224
function cpu:runit()
    local tcycles = 0
    while tcycles < 70224 do
        local pc = self.regs["pc"]
        local b0 = self:fetch8()
        self.fpc = pc
        self.fb0 = b0
        self.fb1 = self.ram:readb(pc+1)
        tcycles = tcycles + cpu.opcodes[b0](self)
    end
    return
end
return cpu