local Deck = {}
Deck.__index = Deck

function Deck.new(settings)
	local self = setmetatable({}, Deck)
	self.settings = settings or {}

	self.handSize       = self.settings.handSize or 5
	self.publicCount    = self.settings.publicCardCount or 3
	self.maxRecycles    = self.settings.maxRecycles or 1
	self.remainingCycles = self.settings.loopCount or 1

	self.deck    = {}
	self.hand    = {}
	self.discard = {}
	self.history = {}

	return self
end

function Deck:build(cardPool)
	self.deck = {}
	self.discard = {}
	for _, info in ipairs(cardPool) do
		for i = 1, info.count do
			table.insert(self.deck, {
				id = info.id,
				canRecycle = info.canRecycle,
				recyclesUsed = 0,
			})
		end
	end
	self:shuffle()
end

function Deck:shuffle()
	for i = #self.deck, 2, -1 do
		local j = math.random(i)
		self.deck[i], self.deck[j] = self.deck[j], self.deck[i]
	end
end

function Deck:draw(n)
	n = n or 1
	for i = 1, n do
		if #self.deck == 0 then
			if #self.discard > 0 and self.remainingCycles > 0 then
				self.deck, self.discard = self.discard, {}
				self:shuffle()
				if self.remainingCycles ~= math.huge then
					self.remainingCycles -= 1
				end
			else
				break
			end
		end
		if #self.deck > 0 and #self.hand < self.handSize then
			table.insert(self.hand, table.remove(self.deck, 1))
		end
	end
end

function Deck:play(index)
	local card = self.hand[index]
	if not card then return nil end
	table.remove(self.hand, index)

	if card.canRecycle and card.recyclesUsed < self.maxRecycles then
		card.recyclesUsed += 1
		table.insert(self.deck, card)
	else
		table.insert(self.discard, card)
	end

	self:draw(1)
	return card
end

function Deck:recordPlay(cardName, hitLanded)
	table.insert(self.history, {card = cardName, hit = hitLanded})
	if self.settings.comboRegainDiscarded and hitLanded and #self.discard > 0 then
		table.insert(self.deck, table.remove(self.discard, math.random(1, #self.discard)))
	end
end

function Deck:getPublic()
	local out = {}
	for i = 1, math.min(self.publicCount, #self.hand) do
		out[i] = self.hand[i].id
	end
	return out
end

function Deck:getFullIds()
	local out = {}
	for i, c in ipairs(self.hand) do out[i] = c.id end
	return out
end

function Deck:isDepleted()
	return #self.hand == 0 and #self.deck == 0 and (#self.discard == 0 or self.remainingCycles <= 0)
end

function Deck:reset()
	self.deck = {}
	self.hand = {}
	self.discard = {}
	self.history = {}
end

return Deck