-- DealerAI: personality-driven dealer decisions for casino tables.
-- Pure logic + seeded RNG; no Roblox services, no hidden state.
--
-- THE CORE CONTRACT (anti-fraud): commit() is called at CLASH START,
-- BEFORE the player's choice arrives, and returns only a move name.
-- It never sees the player's current pick — only history. TableSession
-- stores the committed move hidden and reveals it after the player
-- commits.
--
-- TELLS are Markov chains conditioned on the committed move: the NEXT tell
-- depends on the PREVIOUS tell (CasinoData.TellSets[personality].Chain).
-- Tells are primarily ANIMATION ids played on the dealer NPC's Animator
-- (server-side Play() replicates); Text tells are the rare fallback.
-- TableSession owns previousTell state and performs playback.
--
-- V0 NOTE: you only need Chain[move].Default rows populated (one canonical
-- tell per move + noise). Missing transition rows fall back to Default, so
-- the system behaves as a simple weighted tell until you author sequences.
--
-- handState contract (built by TableSession):
--   availableMoves = { "Attack", "Block", ... }   -- moves the dealer's hand can currently play (unique)
--   playerRecent   = { "Attack", "Block", ... }   -- player's chosen moves, oldest → newest
--   behind         = number (-1 .. 1)             -- dealer's score pressure: >0 = behind, <0 = ahead, 0 = even
--   clashIndex     = number                       -- 1-based clash within the hand

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatTriangle = require(script.Parent.CombatTriangle)
local CasinoData = require(ReplicatedStorage.Modules.CasinoData)

local DealerAI = {}

-- ============================================================================
-- DECISION
-- ============================================================================
local DAMAGE_MOVES = { Attack = true, HeavyAttack = true, Throw = true }

-- All moves in the registry that counter `move` (used by adaptivity).
local function countersTo(move)
	local out = {}
	for name, def in pairs(CombatTriangle.MOVE_DEFS) do
		if def.beats[move] then
			table.insert(out, name)
		end
	end
	return out
end

function DealerAI.commit(handState, personality, rng)
	local def = CasinoData.Personalities[personality]
	assert(def, ("DealerAI: unknown personality '%s'"):format(tostring(personality)))
	assert(rng, "DealerAI.commit: seeded Random required")
	local available = handState.availableMoves
	assert(type(available) == "table" and #available > 0, "DealerAI.commit: no available moves")

	-- Optional scripted pattern (Boss phases land here later): cycles
	-- regardless of weights, falling back to weights when exhausted/unavailable.
	local pattern = def.Pattern
	if pattern then
		local move = pattern[((handState.clashIndex or 1) - 1) % #pattern + 1]
		for _, avail in ipairs(available) do
			if avail == move then return move end
		end
	end

	-- Base weights from personality.
	local weights = {}
	for move, w in pairs(def) do
		if CombatTriangle.MOVE_DEFS[move] then
			weights[move] = w
		end
	end

	-- Adaptivity: punish the player's most recent habit by shifting weight
	-- toward a counter of their most frequent recent move.
	local recent = handState.playerRecent or {}
	if #recent > 0 and def.Adaptivity > 0 then
		local counts = {}
		for _, m in ipairs(recent) do counts[m] = (counts[m] or 0) + 1 end
		local topMove, topCount = nil, 0
		for m, c in pairs(counts) do
			if c > topCount then topMove, topCount = m, c end
		end
		if topMove then
			local playable = {}
			for _, c in ipairs(countersTo(topMove)) do
				for _, avail in ipairs(available) do
					if avail == c then table.insert(playable, c); break end
				end
			end
			if #playable > 0 then
				local counter = playable[rng:NextInteger(1, #playable)]
				weights[counter] = (weights[counter] or 0) + def.Adaptivity * 2
			end
		end
	end

	-- Score pressure: most dealers press when behind; personalities with
	-- AggressiveWhenAhead press when winning instead (the Collector).
	local behind = handState.behind or 0
	local pressing = (def.AggressiveWhenAhead and behind < 0) or (not def.AggressiveWhenAhead and behind > 0)
	if pressing then
		local intensity = math.abs(behind)
		for move in pairs(DAMAGE_MOVES) do
			weights[move] = (weights[move] or 0) * (1 + 0.5 * intensity)
		end
	elseif behind ~= 0 then
		weights.Block = (weights.Block or 0) * 1.25
		weights.Draw  = (weights.Draw  or 0) * 1.25
	end

	local total = 0
	for _, move in ipairs(available) do total += weights[move] or 0 end
	if total <= 0 then
		return available[rng:NextInteger(1, #available)]
	end
	local roll = rng:NextNumber() * total
	for _, move in ipairs(available) do
		roll -= weights[move] or 0
		if roll <= 0 then return move end
	end
	return available[#available]
end

-- ============================================================================
-- TELLS — Markov chain over tell names, conditioned on the committed move.
-- ============================================================================

-- Weighted sample over chain rows ({Tell = name, Weight = n}).
local function sampleRows(rows, rng)
	local total = 0
	for _, row in ipairs(rows) do total += row.Weight end
	if total <= 0 then return nil end
	local roll = rng:NextNumber() * total
	for _, row in ipairs(rows) do
		roll -= row.Weight
		if roll <= 0 then return row.Tell end
	end
	return rows[#rows].Tell
end

-- Returns the tell NAME to display this clash. `previousTell` is the tell
-- name from the previous clash (nil on the first). Falls back to the move's
-- Default row when the chain has no entry for the previous tell — which is
-- also what makes Default-only data (v0) behave like a simple tell system.
function DealerAI.nextTell(personality, committedMove, previousTell, rng)
	local set = CasinoData.TellSets[personality]
	assert(set, ("DealerAI: no TellSets for personality '%s'"):format(tostring(personality)))
	assert(rng, "DealerAI.nextTell: seeded Random required")

	local moveChain = set.Chain[committedMove]
	if not moveChain then
		-- Personality has no chain for this move: any tell, uniformly.
		local names = {}
		for name in pairs(set.Tells) do table.insert(names, name) end
		return names[rng:NextInteger(1, #names)]
	end

	local rows = (previousTell and moveChain[previousTell]) or moveChain.Default
	return sampleRows(rows, rng) or previousTell
end

-- Resolve a tell name to its playable payload: { Animation = assetId } or
-- { Text = string }. TableSession uses this to drive the NPC.
function DealerAI.tellInfo(personality, tellName)
	local set = CasinoData.TellSets[personality]
	local tell = set and set.Tells[tellName]
	return tell -- may be nil; caller should no-op unknown tells
end

-- ============================================================================
-- SELF-TEST
-- ============================================================================
function DealerAI.selftest()
	local errors = {}
	local function check(name, cond)
		if not cond then table.insert(errors, "FAIL: " .. name) end
	end

	-- commit(): available-moves constraint + Grinder skew.
	local rng = Random.new(42)
	local counts = { Attack = 0, Block = 0, Dodge = 0, Draw = 0, HeavyAttack = 0 }
	for i = 1, 200 do
		local move = DealerAI.commit({
			availableMoves = { "Attack", "Block", "Dodge", "Draw", "HeavyAttack" },
			playerRecent = {}, behind = 0, clashIndex = i,
		}, "Grinder", rng)
		check("commit returns an available move", counts[move] ~= nil)
		counts[move] += 1
	end
	check("Grinder attacks a lot", counts.Attack > 60)

	rng = Random.new(7)
	local counters = 0
	for i = 1, 200 do
		local move = DealerAI.commit({
			availableMoves = { "Attack", "Block", "Dodge" },
			playerRecent = { "Attack", "Attack", "Attack", "Attack" },
			behind = 0, clashIndex = i,
		}, "Shark", rng)
		if move == "Block" or move == "Dodge" then counters += 1 end
	end
	check("adaptivity counters spam", counters > 80)

	rng = Random.new(9)
	local dmg = 0
	for i = 1, 200 do
		local move = DealerAI.commit({
			availableMoves = { "Attack", "Block", "Draw" },
			playerRecent = {}, behind = 1, clashIndex = i,
		}, "Grinder", rng)
		if DAMAGE_MOVES[move] then dmg += 1 end
	end
	check("behind → aggression", dmg > 100)

	-- nextTell(): chain only emits known tell names (Default-only data works).
	rng = Random.new(11)
	local set = CasinoData.TellSets.Grinder
	local prev = nil
	for i = 1, 200 do
		local t = DealerAI.nextTell("Grinder", "Attack", prev, rng)
		check("nextTell returns a known tell", set.Tells[t] ~= nil)
		prev = t
	end

	-- Learnability: Attack's canonical tell must dominate the Default row.
	rng = Random.new(13)
	local canonical = 0
	for i = 1, 200 do
		if DealerAI.nextTell("Grinder", "Attack", nil, rng) == "TapFelt" then canonical += 1 end
	end
	check("canonical tell dominates (learnable)", canonical > 100)

	-- tellInfo(): resolves to animation or text payload.
	local info = DealerAI.tellInfo("Grinder", "TapFelt")
	check("tellInfo resolves", info ~= nil and (info.Animation ~= nil or info.Text ~= nil))

	return errors
end

return DealerAI