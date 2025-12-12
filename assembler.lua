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
make("SETS")
makeR("COP") -- Copy register to (A-D)
make("COPN") -- Copy N to register (effectively clearing it)
make("COPS")
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

print("What file (Do not include .avis extension)? ")
local file = io.read()
if file == "" then file = "program" end
local f = io.open(file .. ".avis", "r")
local program
if f then
    program = f:read("a")
    f:close()
end

local debug = {
    predump = true
}

local function assemble(source_code)
    local lines = {}
    local labels = {}
    local aliases = {}
    local files = {}
    local address = 0
    local source_line = 0

    for line in source_code:gmatch("[^\r\n]+") do
        if line:match("^%.") then
            local _, filename = line:match("^(%S+)%s*(.*)$")
            print(filename)
            print(files[filename] or false)
            if not files[filename] then
                local subfile = io.open(filename, "r")
                if not subfile then
                    error("Library file not found: " .. filename)
                end
                files[filename] = true
                local subdata = subfile:read("a")
                print(subdata)
                print("----------------------")
                source_code = subdata .. "\n" .. source_code
                print(source_code)
            end
            print(files[filename] or false)
        end
    end

    -- Preproccessing step two, handle aliases
    for line in source_code:gmatch("[^\r\n]+") do
        if line:match("^@") then
            print("Found alias!")
            print(line)
            line = line:sub(2, -1)
            local from, to = line:match("^(%S+)%s*(.*)$")
            aliases[from] = to
            print(from, to)
        end
    end
    
    -- First pass: parse lines and collect labels
    for line in source_code:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")  -- trim whitespace
        
        -- Skip empty lines, comments and already handled aliases.
        if line == "" or line:match("^;") or line:match("^@") then
            source_line = source_line + 1
            goto continue
        end

        local subs = {}
        for word in line:gmatch("%S+") do
            if aliases[word] then
                subs[#subs+1] = aliases[word]
            else
                subs[#subs+1] = word
            end
        end
        line = table.concat(subs, " ")
        
        -- Check for label (ends with :)
        local label = line:match("^(%w+):%s*$")
        if label then
            labels[label] = address
            source_line = source_line + 1
            goto continue
        end
        
        -- Parse instruction and operand
        local instruction, operand = line:match("^(%w+)%s*(.*)$")
        if instruction then
            source_line = source_line + 1
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

    if debug.predump then
        local predump = io.open(file .. ".predump", "w")
        if not predump then
            error("Could not open predump file")
        end

        for i = 0, 255 do
            predump:write(program)
        end
    end
    
    -- Second pass: resolve labels and generate bytecode
    local bytecode = {}
    for i = 0, 255 do bytecode[i] = 0 end  -- initialize memory
    
    local offset = 0
    for _, line in ipairs(lines) do
        local opcode = bytes[line.instruction]
        if line.instruction:match("JMPL") and labels[line.operand] then
            bytecode[line.address + offset] = bytes["SETS"]
            bytecode[line.address + 1 + offset] = math.floor((labels[line.operand] + offset) / 256)
            offset = offset + 2
            bytecode[line.address + offset] = bytes["JUMPL"]
            bytecode[line.address + 1 + offset] = (labels[line.operand] + offset) % 256
        end
        if not opcode then
            error("Unknown instruction: " .. line.instruction .. " at address " .. line.address .. " line " .. source_line)
        end
        
        -- Parse operand
        local operand_value = 0
        if line.operand ~= "" then
            -- Check if it's a label
            if labels[line.operand] then
                operand_value = (labels[line.operand] + offset) % 256
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
        
        bytecode[line.address + offset] = opcode or 0
        bytecode[line.address + 1 + offset] = operand_value or 0
        ::cont::
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
-- Load into memory
local outfile = io.open(file .. ".bin", "wb")  -- "wb" = write binary
if not outfile then
    error("Could not open program.bin!")
end

-- Write all 256 bytes
for i = 0, #bytecode do
    print(bytecode[i])
    outfile:write(string.char(bytecode[i] or 0))
end

outfile:close()
print("Bytecode saved!")
