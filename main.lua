QUEUE_SIZE = 16
MEM_SIZE = 256
BITS = 8

local codes = {}
local bytes = {}
local next = 1 -- Just a little helper variable for building the list of opcodes

print("Creating virtual storage...")
local queue = {head=1,tail=1,size=0}
for i = 1, QUEUE_SIZE do queue[i] = 0 end
local registers = {A = 0, B = 0, C = 0, D = 0, N = 0}
local memory = {}
for i = 1, MEM_SIZE do memory[i] = 0 end
local counter = 0

local function clampWithRollover8b(a)
    if a > 255 then
        return a - 255
    elseif a < 0 then
        return a + 255
    else
        return a
    end
end

local function load_bytecode(filename)
    local file = io.open(filename, "rb")  -- "rb" = read binary
    if not file then
        error("Could not open file: " .. filename)
    end

    local bytecode = {}
    local content = file:read("*all")

    for i = 1, #content do
        bytecode[i - 1] = string.byte(content, i)  -- Convert to 0-indexed
    end

    -- Pad with zeros if file is shorter than 256 bytes
    for i = #content, 255 do
        bytecode[i] = 0
    end

    file:close()
    return bytecode
end

local function getRegister(operand)
    if operand == 0 then return 'A'
    elseif operand == 1 then return 'B'
    elseif operand == 2 then return 'C'
    elseif operand == 3 then return 'D'
    else return 'N' end
end

local function make(instruct)
    codes[next] = instruct
    next = next + 1
end

local function makeR(instruct)
    make(instruct .. "A")
    make(instruct .. "B")
    make(instruct .. "C")
    make(instruct .. "D")
end

local function defFuncLit(reg, operation)
    return function(operand)
        if reg ~= "N" then
            registers[reg] = clampWithRollover8b(operation(registers[reg], operand) or registers[reg])
        end
    end
end

local function defFuncReg(reg, operation)
    return function(operand)
        if reg ~= "N" then
            local source = getRegister(operand)
            registers[reg] = clampWithRollover8b(operation(registers[reg], registers[source]) or registers[reg])
        end
    end
end

local function reverse(tab)
    local newTab = {}
    for i, item in ipairs(tab) do
        newTab[item] = i
    end
    return newTab
end

print("Making opcodes...")
make("NOOP") -- Do nothing
make("STOP") -- Stop execution
make("PSHL") -- Push literal to queue
make("PSHR") -- Push register to queue
make("POPR") -- Pop queue to register
make("ROTT") -- Rotate queue (pop to top)
makeR("SET") -- Set (A-D) to literal
makeR("COP") -- Copy register to (A-D)
make("COPN") -- Copy N to register (effectively clearing it)
makeR("ADL") -- Add literal to (A-D)
makeR("ADR") -- Add register to (A-D)
makeR("SBL") -- Subtract literal from (A-D)
makeR("SBR") -- Subtract register from (A-D)
makeR("MTL") -- Multiply (A-D) by literal
makeR("MTR") -- Multiply (A-D) by register
makeR("DVL") -- Perform (integer) division of (A-D) by literal
makeR("DVR") -- Perform (integer) division of (A-D) by register
makeR("ANL") -- Bitwise AND of (A-D) by literal mask
makeR("ANR") -- Bitwise AND of (A-D) by register
makeR("ORL") -- Bitwise OR of (A-D) by literal mask
makeR("ORR") -- Bitwise OR of (A-D) by register
makeR("XRL") -- Bitwise XOR of (A-D) by literal mask
makeR("XRR") -- Bitwise XOR of (A-D) by register
makeR("SFL") -- Bitshift of (A-D) by literal
makeR("SFR") -- Bitshift of (A-D) by register
make("NOTT") -- Bitwise NOT of register
make("JMPL") -- Uncontitional jump to literal program address
make("JMPR") -- Unconditional jump to register program address
makeR("JZL") -- Jumps to literal address if (A-D) is zero
makeR("JZR") -- Jumps to register address if (A-D) is zero
make("LODL") -- Loads a value from literal memory address to queue
make("LODR") -- Loads a value from register memory address to queue
make("SAVL") -- Saves the next value from the queue to literal address
make("SAVR") -- Saves the next value from the queue to register address
make("DEBG") -- Manually trigger a debug output.

print("Making bytecodes...")
bytes = reverse(codes)

print("Defining instructions...")
local instructions = {}
-- NOOP and STOP are being implimented in the core loop.
do
    instructions["JMPL"] = function(op)
        counter = op - 2
    end

    instructions["JMPR"] = function(op)
        counter = registers[getRegister(op)] - 2
    end

    instructions["PSHL"] = function(op)
        for i, val in ipairs(queue) do
            if (val == 0) or (i == 16) then
                queue[i] = op
                break
            end
        end
    end

    instructions["PSHR"] = function(op)
        for i, val in ipairs(queue) do
            if (val == 0) or (i == 16) then
                queue[i] = registers[getRegister(op)]
                break
            end
        end
    end

    instructions["POPR"] = function(op)
        registers[getRegister(op)] = table.remove(queue, 1)
        queue[16] = 0
    end

    instructions["ROTT"] = function(op)
        for i = 1, op do
            table.insert(queue, table.remove(queue, 1))
        end
    end

    local registryNames = {"A", "B", "C", "D"}
    for i, reg in ipairs(registryNames) do
        instructions["SET" .. reg] = defFuncLit(reg,
            function (a, b)
                return b
            end
        )
        instructions["COP" .. reg] = defFuncReg(reg,
            function (a, b)
                return b
            end
        )
        instructions["ADL" .. reg] = defFuncLit(reg,
            function (a, b)
                return a + b
            end
        )
        instructions["ADR" .. reg] = defFuncReg(reg,
            function (a, b)
                return a + b
            end
        )
        instructions["SBL" .. reg] = defFuncLit(reg,
            function (a, b)
                return a - b
            end
        )
        instructions["SBR" .. reg] = defFuncReg(reg,
            function (a, b)
                return a - b
            end
        )
        instructions["DVL" .. reg] = defFuncLit(reg,
            function (a, b)
                return a // b
            end
        )
        instructions["DVR" .. reg] = defFuncReg(reg,
            function (a, b)
                return a // b
            end
        )
        instructions["MTL" .. reg] = defFuncLit(reg,
            function (a, b)
                return a * b
            end
        )
        instructions["MTR" .. reg] = defFuncReg(reg,
            function (a, b)
                return a * b
            end
        )
        instructions["JZL" .. reg] = defFuncLit(reg,
            function (a, b)
                if a == 0 then
                    counter = b - 2
                end
            end
        )
        instructions["JZR" .. reg] = defFuncReg(reg,
            function (a, b)
                if a == 0 then
                    counter = b - 2
                end
            end
        )
    end
end


print("Displaying opcodes...")
for i in ipairs(codes) do
    print(i, codes[i])
end
print(#codes .. " total codes.")

print("Loading program...")
--[[ Basic behavior test
memory[0] = bytes["SETA"]
memory[1] = 0
memory[2] = bytes["SETB"]
memory[3] = 5
memory[4] = bytes["COPC"]
memory[5] = 1
memory[6] = bytes["SBLC"]
memory[7] = 5
memory[8] = bytes["JZLC"]
memory[9] = 255 -- Stop once we're at five.
memory[10] = bytes["ADLA"]
memory[11] = 1
memory[12] = bytes["JMPL"]
memory[13] = 4
memory[255] = bytes["STOP"]
--]]
local loaded = load_bytecode("program.bin")
for addr, byte in pairs(loaded) do
    memory[addr] = byte
end

local function debug(opcode, operand)
    print("Debug log:")
    print("-------------------------------")
    print("| REGISTERS: | MISC:          |")
    print(string.format("| %-10s |", ("A: " .. registers.A)) .. string.format(" COUNTER:  %03d  |", counter))
    print(string.format("| %-10s |", ("B: " .. registers.B)) .. string.format(" BYTECODE: %03d  |", opcode))
    print(string.format("| %-10s |", ("C: " .. registers.C)) .. string.format(" OPCODE:   %s |", codes[opcode]))
    print(string.format("| %-10s |", ("D: " .. registers.D)) .. string.format(" OPERAND:  %03d  |", operand))
    print("-------------------------------------------------------------------------")
    print("|                                MEMORY:                                |")
    print("-------------------------------------------------------------------------")
    local memstring = ""
    local block_count = 0
    for i = 1, MEM_SIZE do
        if (i % 32) == 0 then
            memstring = memstring .. memory[i-1]
        else
            memstring = memstring .. memory[i-1] .. "-"
        end
        
        if (i % 32) == 0 then
            if i-1 == MEM_SIZE then break end
            memstring = memstring .. "\n"
            block_count = 0
        end
    end
    print(memstring)
    print("-------------------------------------------------------------------------")
    print("|                                 QUEUE:                                |")
    print("-------------------------------------------------------------------------")
    local queuestring = ""
    for i = 1, QUEUE_SIZE do
        queuestring = queuestring .. queue[i] .. " <- "
    end
    print("Next Popped <- " .. queuestring .. "Last pushed")
end

print("Init complete! Running CPU.")
local dbg = {
    step = true,
    stop = true,
    slow = false
}
local running = true
while running do
    local opcode = memory[counter]
    local operand = memory[counter + 1]

    if codes[opcode] == "NOOP" then
        -- Nothin'...
    elseif codes[opcode] == "STOP" then
        running = false
    elseif codes[opcode] == "DEBG" then
        debug(opcode, operand)
    elseif instructions[codes[opcode]] then
        instructions[codes[opcode]](operand)
    else
        error("FATAL:\nCPU was given an invalid instruction!\nINST: " .. opcode .. "\nCOUNTER: " .. counter)
    end

    if dbg.step then debug(opcode, operand) end
    if dbg.slow then os.execute("sleep " .. 0.25) end

    counter = clampWithRollover8b(counter + 2)
    registers.N = 0
end
print("Execution complete!")
if dbg.stop then debug(0, 0) end