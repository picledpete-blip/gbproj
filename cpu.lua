local cpu = {}
cpu.ram = require("ram")
local bit = require("bit")
cpu.halt = false
cpu.ime = false
cpu.eipend = 0
cpu.regs = {
    a = 0x00,
    b = 0x00,
    c = 0x00,
    d = 0x00,
    e = 0x00,
    f = 0x00,
    h = 0x00,
    l = 0x00,
    sp = 0xfffe,
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
    if reg < 8 then
        self[regslookup[reg]] = val % 256
    elseif reg < 10 then
        self[regslookup[reg]] = val % 65536
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
    local val = self.ram:readb(self.regs.pc)
    if self.halt_bug then
        self.halt_bug = false
    else
        self.regs.pc = (self.regs.pc + 1) % 65536
    end
    return val
end
local cbregs = {
    "b", "c", "d", "e", "h", "l", nil, "a"
}

function cpu:cbread(target)
    if target == 6 then
        local hl = self.regs.h * 256 + self.regs.l
        return self.ram:readb(hl)
    end

    return self.regs[cbregs[target + 1]]
end

function cpu:cbwrite(target, value)
    value = value % 256

    if target == 6 then
        local hl = self.regs.h * 256 + self.regs.l
        self.ram:writeb(hl, value)
    else
        self.regs:setreg(target == 7 and 0 or target + 1, value)
    end
end
cpu.cbopcodes = {}

for opcode = 0x40, 0xFF do
    local group = math.floor(opcode / 64)
    local bitnum = math.floor((opcode % 64) / 8)
    local target = opcode % 8

    cpu.cbopcodes[opcode] = function(self)
        local val = self:cbread(target)
        local mask = 2 ^ bitnum

        if group == 1 then
            self.regs:setflag(FZ, bit.band(val, mask) == 0)
            self.regs:setflag(FN, false)
            self.regs:setflag(FH, true)

            return target == 6 and 12 or 8

        elseif group == 2 then
            self:cbwrite(target, bit.band(val, bit.bnot(mask)))

        elseif group == 3 then
            self:cbwrite(target, bit.bor(val, mask))
        end

        return target == 6 and 16 or 8
    end
end
for opcode = 0x00, 0x3F do
    local operation = math.floor(opcode / 8)
    local target = opcode % 8

    cpu.cbopcodes[opcode] = function(self)
        local val = self:cbread(target)
        local carry = false
        local result = 0

        if operation == 0 then
            -- RLC
            carry = bit.band(val, 0x80) ~= 0
            result = bit.band(bit.lshift(val, 1), 0xFF)
            if carry then result = result + 1 end

        elseif operation == 1 then
            -- RRC
            carry = bit.band(val, 1) ~= 0
            result = bit.rshift(val, 1)
            if carry then result = result + 128 end

        elseif operation == 2 then
            -- RL
            local oldcarry = self.regs:getflag(FC)
            carry = bit.band(val, 0x80) ~= 0
            result = bit.band(bit.lshift(val, 1), 0xFF)
            if oldcarry then result = result + 1 end

        elseif operation == 3 then
            -- RR
            local oldcarry = self.regs:getflag(FC)
            carry = bit.band(val, 1) ~= 0
            result = bit.rshift(val, 1)
            if oldcarry then result = result + 128 end

        elseif operation == 4 then
            -- SLA
            carry = bit.band(val, 0x80) ~= 0
            result = bit.band(bit.lshift(val, 1), 0xFF)

        elseif operation == 5 then
            -- SRA
            carry = bit.band(val, 1) ~= 0
            result = bit.bor(
                bit.rshift(val, 1),
                bit.band(val, 0x80)
            )

        elseif operation == 6 then
            -- SWAP
            result = bit.bor(
                bit.lshift(bit.band(val, 0x0F), 4),
                bit.rshift(bit.band(val, 0xF0), 4)
            )

        elseif operation == 7 then
            -- SRL
            carry = bit.band(val, 1) ~= 0
            result = bit.rshift(val, 1)
        end

        self:cbwrite(target, result)

        self.regs:setflag(FZ, result == 0)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, false)
        self.regs:setflag(FC, carry)

        return target == 6 and 16 or 8
    end
end

cpu.opcodes = {
    [0x00] = function (self)
        local pc = self.regs["pc"]
        return 4
    end,
    [0x01] = function (self)
        local l = self:fetch8()
        local h = self:fetch8()
        self.regs:setreg(12,h*256 + l)
        return 12
    end,
    [0x05] = function (self)
        local b  = self.regs.b
        self.regs:setreg(1, b-1)
        self.regs:setflag(FZ, b == 1)
        self.regs:setflag(FN, true)
        self.regs:setflag(FH, (b % 16) == 0)
        return 4
    end,
    [0x06] = function (self)
        local v = self:fetch8()
        self.regs:setreg(1, v)
        return 8
    end,
    [0x0b] = function (self)
        local b = self.regs.b
        local c = self.regs.c
        self.regs:setreg(12,b*256+c-1)
        return 8
    end,
    [0x0c] = function (self)
        local c  = self.regs.c
        self.regs:setreg(2, c+1)
        self.regs:setflag(FZ, c == 0xff)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, (c % 0x10) == 0x0f)
        return 4
    end,
    [0x0d] = function (self)
        local c  = self.regs.c
        self.regs:setreg(2, c-1)
        self.regs:setflag(FZ, c == 1)
        self.regs:setflag(FN, true)
        self.regs:setflag(FH, (c % 16) == 0)
        return 4
    end,
    [0x0e] = function (self)
        local v = self:fetch8()
        self.regs:setreg(2, v)
        return 8
    end,
    [0x11] = function (self)
        local val = self:fetch8() * 256 + self:fetch8()
        self.regs:setreg(13,val)
        return 12 
    end,
    [0x12] = function (self)
        local de = self.regs.d * 256 + self.regs.e
        self.ram:writeb(de,self.regs.a)
        return 8
    end,
    [0x13] = function (self)
        local de = self.regs.d * 256 + self.regs.e
        self.regs:setreg(13,de+1)
        return 8
    end,
    [0x16] = function (self)
        local val = self:fetch8()
        self.regs:setreg(3,val)
        return 8
    end,
    [0x19] = function (self)
        local hl = self.regs.h * 256 + self.regs.l
        local de = self.regs.d * 256 + self.regs.e
        self.regs:setreg(14,hl+de)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, (bit.band(hl, 0x0FFF) + bit.band(de, 0x0FFF)) > 0x0FFF)
        self.regs:setflag(FC, hl+de > 0xffff)
        return 8    
    end,
    [0x1a] = function (self)
        local de = self.regs.d * 256 + self.regs.e
        self.regs:setreg(0,self.ram:readb(de))
        return 8
    end,
    [0x1c] = function (self)
        local e = self.regs.e
        self.regs:setreg(2, e+1)
        self.regs:setflag(FZ, e == 0xff)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, (e % 0x10) == 0x0f)
        return 4
    end,
    [0x20] = function (self)
        
        local offset = self:fetch8()
        if not self.regs:getflag(FZ) then
            if offset > 127 then
                offset = offset - 256
            end
            self.regs:setreg(9, self.regs.pc + offset)
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
    [0x22] = function (self)
        local hl = self.regs.h * 256 + self.regs.l
        self.ram:writeb(hl, self.regs.a)
        self.regs:setreg(14,hl+1)
        return 8
    end,
    [0x23] = function (self)
        local hl = self.regs.h * 256 + self.regs.l
        self.regs:setreg(14,hl+1)
        return 8
    end,
    [0x28] = function (self)
        
        local offset = self:fetch8()
        if self.regs:getflag(FZ) then
            if offset > 127 then
                offset = offset - 256
            end
            self.regs:setreg(9, self.regs.pc + offset)
            return 12
        end
        return 8
    end,
    [0x2a] = function (self)
        local hl = self.regs.h * 256 + self.regs.l
        local val = self.ram:readb(hl)
        self.regs:setreg(0,val)
        self.regs:setreg(14,hl+1)
        return 8
    end,
    [0x2f] = function (self)
        
        self.regs:setreg(0,bit.bnot(self.regs.a))
        self.regs:setflag(FN, true)
        self.regs:setflag(FH, true)
        return 4
    end,
    [0x30] = function (self)
        
        local offset = self:fetch8()
        if not self.regs:getflag(FC) then
            if offset > 127 then
                offset = offset - 256
            end
            self.regs:setreg(9, self.regs.pc + offset)
            return 12
        end
        return 8
    end,
    [0x31] = function (self)
        local l = self:fetch8()
        local h = self:fetch8()
        self.regs:setreg(8, h*256+l)
        return 12
    end,
    [0x32] = function (self)
        local hl = (self.regs.h * 256) + self.regs.l
        local a = self.regs.a
        self.ram:writeb(hl,a)
        self.regs:setreg(14,hl-1)
        return 8
    end,
    [0x34] = function (self)
        local hl = (self.regs.h * 256) + self.regs.l
        local val = self.ram:readb(hl)
        self.regs:setreg(14, hl+1) 
        self.regs:setflag(FZ, val == 0xff)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, (val % 0x10) == 0x0f)
        return 12
    end,
    [0x36] = function (self)
        local hl = (self.regs.h * 256) + self.regs.l
        local val = self:fetch8()
        self.ram:writeb(hl,val)
        return 12
    end,
    [0x3c] = function (self)
        local a  = self.regs.a
        self.regs:setreg(0, a+1)
        self.regs:setflag(FZ, a == 0xff)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, (a % 0x10) == 0x0f)
        return 4
    end,

    [0x3d] = function (self)
        local a  = self.regs.a
        self.regs:setreg(0, a-1)
        self.regs:setflag(FZ, a == 1)
        self.regs:setflag(FN, true)
        self.regs:setflag(FH, (a % 16) == 0)
        return 4
    end,
    [0x3e] = function (self)
        local v = self:fetch8()
        self.regs:setreg(0, v)
        return 8
    end,
    [0x47] = function (self)
        self.regs:setreg(1, self.regs.a)
        return 4
    end,
    [0x4f] = function (self)
        self.regs:setreg(2,self.regs.a)
        return 4
    end,
    [0x56] = function (self)
        local hl = self.regs.h * 256 + self.regs.l
        self.regs:setreg(3,self.ram:readb(hl))
        return 8
    end,
    [0x5e] = function (self)
        self.regs:setreg(4,self.ram:readb(self.regs.h*256 + self.regs.l))
        return 8
    end,
    [0x5f] = function (self)
        local a = self.regs.a
        self.regs:setreg(4,a)
        return 4
    end,
    [0x71] = function (self)
        local hl = self.regs.h * 256 + self.regs.l
        self.ram:writeb(hl,self.regs.c)
        return 8
    end,
    [0x76] = function(self)
        local pending = bit.band(
            self.ram:readb(0xFFFF),
            self.ram:readb(0xFF0F),
            0x1F
        )

        if not self.ime and pending ~= 0 then
            self.halt_bug = true
        else
            self.halt = true
        end

        return 4
    end,
    [0x78] = function (self)
        local b = self.regs.b
        self.regs:setreg(0,b)
        return 4
    end,
    [0x79] = function (self)
        self.regs:setreg(0, self.regs.c)
        return 4
    end,
    [0x7c] = function (self)
        self.regs:setreg(0,self.regs.h)
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
    [0x87] = function (self)
        local a = self.regs.a
        self.regs:setreg(0,a+a)
        self.regs:setflag(FZ, 0 == a)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, (a%0x10) + (a%0x10) > 0xf)
        self.regs:setflag(FC, a+a > 0xff)
        return 4
    end,
    [0xa1] = function (self)
        self.regs:setreg(0, bit.band(self.regs.a, self.regs.c))
        self.regs:setflag(FZ, bit.band(self.regs.a, self.regs.c) == 0)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, true)
        self.regs:setflag(FC, false)
        return 4
    end,
    [0xa7] = function (self)
        self.regs:setflag(FZ, self.regs.a == 0)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, true)
        self.regs:setflag(FC, false)
        return 4
    end,
    [0xa9] = function (self)
        self.regs:setreg(0, bit.bxor(self.regs.a, self.regs.b))
        self.regs:setflag(FZ, bit.bxor(self.regs.a, self.regs.b) == 0)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, false)
        self.regs:setflag(FC, false)
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
    [0xb0] = function (self)
        local val = bit.bor(self.regs.a, self.regs.b)
        self.regs:setreg(0,val)
        self.regs:setflag(FZ, val == 0)
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, false)
        self.regs:setflag(FC, false)
        return 4
    end,
    [0xb1] = function (self)
        local a = self.regs.a
        local c = self.regs.c
        self.regs:setreg(0, bit.bor(a,c))
        self.regs:setflag(FZ, 0 == bit.bor(a,c))
        self.regs:setflag(FN, false)
        self.regs:setflag(FH, false)
        self.regs:setflag(FC, false)
        return 4
    end,
    [0xc0] = function(self)
        if not self.regs:getflag(FZ) then
            self.regs.pc = self:pop16()
            return 20
        end
        return 8
    end,
    [0xc1] = function(self)
        local val = self:pop16()
        self.regs:setreg(12, val)
        return 12
    end,
    [0xC3] = function(self)
        local low = self:fetch8()
        local high = self:fetch8()
        self.regs.pc = high * 256 + low
        return 16
    end,
    [0xc8] = function(self)
        if self.regs:getflag(FZ) then
            self.regs.pc = self:pop16()
            return 20
        end
        return 8
    end,
    [0xc9] = function(self)
        self.regs.pc = self:pop16()
        return 16
    end,
    [0xd1] = function(self)
        local val = self:pop16()
        self.regs:setreg(13, val)
        return 12
    end,
    [0xd5] = function (self)
        local d = self.regs.d
        local e = self.regs.e
        self:push16(d*256+e)
        return 16
    end,
    [0xd9] = function(self)
        self.regs.pc = self:pop16()
        self.ime = true
        return 16
    end,
    [0xe0] = function(self)
        local u8 = self:fetch8()
        self.ram:writeb(0xff00+u8, self.regs.a)
        return 12
    end,
    [0xe1] = function(self)
        local val = self:pop16()
        self.regs:setreg(14, val)
        return 12
    end,
    [0xe2] = function(self)
        local a = self.regs.a
        local c = self.regs.c
        self.ram:writeb(0xff00+c, self.regs.a)
        return 8
    end,
    [0xe5] = function (self)
        local h = self.regs.h
        local l = self.regs.l
        self:push16(h*256+l)
        return 16
    end,
    [0xc5] = function (self)
        local b = self.regs.b
        local c = self.regs.c
        self:push16(b*256+c)
        return 16
    end,
    [0xcb] = function(self)
        local opcode = self:fetch8()
        return self.cbopcodes[opcode](self)
    end,
    [0xe6] = function(self)
        local val = self:fetch8()
        self.regs:setreg(0, bit.band(val,self.regs.a))
        return 8
    end,
    [0xcd] = function(self)
        local low = self:fetch8()
        local high = self:fetch8()
        local address = high * 256 + low
        self:push16(self.regs.pc)
        self.regs.pc = address

        return 24
    end,
    [0xe9] = function(self)
        local hl = self.regs.h * 256 + self.regs.l
        self.regs.pc = hl

        return 4
    end,
    [0xea] = function (self)
        local v1 = self:fetch8()
        local v2 = self:fetch8()
        local addr = (v2 * 256) + v1
        local a = self.regs.a
        self.ram:writeb(addr,a)
        return 16
    end,
    [0xef] = function (self)
        self:push16(self.regs.pc)
        self.regs.pc = 0x0028
        return 16
    end,
    [0xf0] = function(self)
        local u8 = self:fetch8()
        self.regs:setreg(0,self.ram:readb(0xff00 + u8))
        return 12
    end,
    [0xf1] = function(self)
        local val = self:pop16()
        self.regs:setreg(11, val)
        return 12
    end,
    [0xf3] = function (self)
        self.ime = false
        self.eipend = 0
        return 4
    end,
    [0xf5] = function (self)
        local a = self.regs.a
        local f = self.regs.f
        self:push16(a*256+f)
        return 16
    end,
    [0xfb] = function (self)
        self.eipend = 2
        return 4
    end,
    [0xfa] = function (self)
        local l = self:fetch8()
        local h = self:fetch8()
        local addr = h*256 + l
        self.regs:setreg(0,self.ram:readb(addr))
        return 16
    end,
    [0xfe] = function(self)
        local val = self:fetch8()
        local a = self.regs.a
        local result = a - val
        self.regs:setflag(FZ, result == 0)
        self.regs:setflag(FN, true)
        self.regs:setflag(FH, (a % 16) < (val % 16))
        self.regs:setflag(FC, a < val)

        return 8
    end,
}

function cpu:dump()
    return "error " .. self.fb0 .. " " .. self.fb1 .. " at" .. self.fpc
end


function cpu:init()
    cpu.ram:init()
    cpu.ram:ldrom("tetris.gb")
end
function cpu:push16(value)
    local sp = self.regs.sp
    sp = (sp - 1) % 65536
    self.ram:writeb(sp, math.floor(value / 256) % 256)
    sp = (sp - 1) % 65536
    self.ram:writeb(sp, value % 256)
    self.regs.sp = sp
end

function cpu:pop16()
    local sp = self.regs.sp
    local low = self.ram:readb(sp)
    sp = (sp + 1) % 65536
    local high = self.ram:readb(sp)
    sp = (sp + 1) % 65536
    self.regs.sp = sp
    return high * 256 + low
end
local intjumps = {
    [0] = 0x0040, -- vblank
    [1] = 0x0048, -- lcd
    [2] = 0x0050, -- timer
    [3] = 0x0058, -- serial
    [4] = 0x0060  -- joypad
}
function cpu:handint()
    local ie = self.ram:readb(0xFFFF)
    local flags = self.ram:readb(0xFF0F)
    local ints = bit.band(ie, flags, 0x1F)
    
    if ints == 0 then
        return 0
    end
    self.halt = false
    if not self.ime then
        return 0
    end
    for i = 0, 4 do
        local mask = bit.lshift(1, i)

        if bit.band(ints, mask) ~= 0 then
            self.ime = false
            self.ram:writeb(
                0xFF0F,
                bit.band(flags, bit.bnot(mask))
            )
            self:push16(self.regs.pc)
            self.regs.pc = intjumps[i]

            return 20
        end
    end

    return 0
end
local throwerr = true
local cpf = 70224
function cpu:runit()
    local tcycles = 0
        while tcycles < 70224 do
        local cycles = 0

        if self.halt then
            local pending = bit.band(
                self.ram:readb(0xFFFF),
                self.ram:readb(0xFF0F),
                0x1F
            )

            if pending == 0 then
                cycles = 4
            else
                self.halt = false
                cycles = 4
            end
        else
        local intc = self:handint()
        if intc > 0 then
            cycles = intc
        else
        local pc = self.regs["pc"]
        local b0 = self:fetch8()
        self.fpc = pc
        self.fb0 = b0
        self.fb1 = self.ram:readb(pc+1)
        if throwerr == false and cpu.opcodes[b0] ~= nil then
        cycles = cpu.opcodes[b0](self)
        elseif throwerr == true then
        cycles = cpu.opcodes[b0](self)
        else
            print(self.regs.pc)
            cycles = 4
        end
        if self.eipend > 0 then
            self.eipend = self.eipend - 1
            if self.eipend <= 0 then
                self.ime = true
            end
        end
    end
    if cycles > 0 then
            self.ppu:tick(cycles)
            tcycles = tcycles + cycles
    end        
end
    end
    return
end
return cpu