-- Allocates X-axis offsets so concurrent matches in one server don't overlap.
local SlotAllocator = {}
local inUse = {}   -- [index] = true
local freeList = {0} -- slot 0 first

function SlotAllocator.acquire()
	local index = table.remove(freeList)
	if index == nil then
		index = 0
		while inUse[index] do index += 1 end
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