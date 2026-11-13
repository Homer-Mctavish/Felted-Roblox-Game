-- SlotAllocator: hands out X-axis offsets so concurrent matches in ONE
-- server don't overlap. With reserved servers there's always exactly one
-- match per server (slot 0); this exists as graceful degradation if matches
-- ever share a server (e.g., a failed ReserveServer in Matchmaking).

local SlotAllocator = {}

SlotAllocator.SPACING = 1000 -- studs between slots; keep in sync across files

local inUse = {}      -- [index] = true
local freeList = {0}  -- slot 0 handed out first

function SlotAllocator.acquire()
	local index = table.remove(freeList)
	if index == nil then
		index = 0
		while inUse[index] do
			index += 1
		end
	end
	inUse[index] = true
	return index
end

function SlotAllocator.release(index)
	if index == nil then return end
	inUse[index] = nil
	table.insert(freeList, index)
end

return SlotAllocator