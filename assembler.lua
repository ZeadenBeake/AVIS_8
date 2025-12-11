local codes = {}
local bytes = {}
local next = 1

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

local f = io.open("program.avis", "r")
local program
if f then
    program = f:read("a")
    f:close()
end

-- Simple assembler for your CPU
local function assemble(source_code)
    local lines = {}
    local labels = {}
    local address = 0
    
    -- First pass: parse lines and collect labels
    for line in source_code:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")  -- trim whitespace
        
        -- Skip empty lines and comments
        if line == "" or line:match("^;") then
            goto continue
        end
        
        -- Check for label (ends with :)
        local label = line:match("^(%w+):%s*$")
        if label then
            labels[label] = address
            goto continue
        end
        
        -- Parse instruction and operand
        local instruction, operand = line:match("^(%w+)%s*(.*)$")
        if instruction then
            table.insert(lines, {
                address = address,
                instruction = instruction,
                operand = operand,
                raw_line = line
            })
            address = address + 2  -- each instruction is 2 bytes
        end
        
        ::continue::
    end
    
    -- Second pass: resolve labels and generate bytecode
    local bytecode = {}
    for i = 0, 255 do bytecode[i] = 0 end  -- initialize memory
    
    for _, line in ipairs(lines) do
        local opcode = bytes[line.instruction]
        if not opcode then
            error("Unknown instruction: " .. line.instruction .. " at address " .. line.address)
        end
        
        -- Parse operand
        local operand_value = 0
        if line.operand ~= "" then
            -- Check if it's a label
            if labels[line.operand] then
                operand_value = labels[line.operand]
            -- Check if it's a register reference
            elseif line.operand == "A" then operand_value = 0
            elseif line.operand == "B" then operand_value = 1
            elseif line.operand == "C" then operand_value = 2
            elseif line.operand == "D" then operand_value = 3
            elseif line.operand == "N" then operand_value = 4
            -- Otherwise parse as number
            else
                operand_value = tonumber(line.operand) or 0
            end
        end
        
        bytecode[line.address] = opcode or 0
        bytecode[line.address + 1] = operand_value or 0
    end
    
    return bytecode
end

--[[
-- Usage example:
local program = [[
; Simple test program
SETA 5          ; Set A to 5
SETB 3          ; Set B to 3
ADRA B          ; Add B to A (A = 8)
PSHR A          ; Push A to queue
SAVL 128        ; Pop and save to video memory

loop:
ADLA 1          ; Increment A
JEZA end        ; If A is zero, jump to end
JUMP loop       ; Otherwise loop

end:
STOP
]]
--]]

local bytecode = assemble(program)
local outFile = io.open("program.bin", "wb")
-- Load into memory
local file = io.open("program.bin", "wb")  -- "wb" = write binary
if not file then
    error("Could not open program.bin!")
end

-- Write all 256 bytes
for i = 0, 255 do
    file:write(string.char(bytecode[i] or 0))
end

file:close()
print("Bytecode saved!")
