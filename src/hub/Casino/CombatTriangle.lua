-- CombatTriangle: the casino clash resolver. Pure functions only — no
-- Roblox services, no state. TableSession owns state (health, focus,
-- dodge buffs, draws); this module answers one question per clash:
-- "these two moves met — what happens?"
--
-- Design: one MOVE_DEFS registry holds everything per-move (what it beats,
-- whether it deals damage on a win, default speed, win/mirror events).
-- Adding a MOVE = one registry row. Adding a CARD never touches this file:
-- cards carry a `Move = "<moveName>"` field in CardData, and TableSession
-- maps through MOVE_DEFS.
--
-- Design source: casino design doc. Two pairs were left undefined there;
-- defaults chosen and marked [doc-gap]:
--   Attack vs HeavyAttack → Attack wins (fast poke beats slow heavy)
--   Block  vs Dodge       → neutral (neither interacts; both recover)
--
-- Damage rule: only Attack, HeavyAttack, and Throw deal damage when they
-- win. Block/Dodge/Draw wins apply their event (focus/buff/refill) only.

local CombatTriangle = {}

-- ============================================================================
-- MOVE REGISTRY — the single place move behavior is defined.
--   beats       : set of move names this move counters
--   damageOnWin : deal the played card's Damage stat on victory
--   speed       : mirror-match tiebreak default (cards may override)
--   alwaysEvent : event fired whenever the move is played (Block → focus)
--   winEvent    : event fired only on victory (Dodge → buff, Draw → refill)
--   mirrorEvent : event fired by BOTH sides on a mirror (Draw-Draw)
-- ============================================================================
CombatTriangle.MOVE_DEFS = {
	Attack = {
		beats = { Throw = true, Draw = true, HeavyAttack = true }, -- [doc-gap]
		damageOnWin = true,
		speed = 5,
	},
	HeavyAttack = {
		beats = { Dodge = true, Draw = true },
		damageOnWin = true,
		speed = 2,
	},
	Throw = {
		beats = { Block = true, HeavyAttack = true },
		damageOnWin = true,
		speed = 3,
	},
	Block = {
		beats = { Attack = true, HeavyAttack = true },
		damageOnWin = false,
		speed = 1,
		alwaysEvent = "Blocked",
	},
	Dodge = {
		beats = { Attack = true, Throw = true },
		damageOnWin = false,
		speed = 4,
		winEvent = "Dodged",
	},
	Draw = {
		beats = { Block = true, Dodge = true, Throw = true },
		damageOnWin = false,
		speed = 1,
		winEvent = "Drew",
		mirrorEvent = "Drew",
	},
}

-- Stable order for UI (help screen, relationship chart). Derived lists from
-- MOVE_DEFS would iterate in hash order; keep this explicit.
CombatTriangle.Moves = { "Attack", "HeavyAttack", "Throw", "Block", "Dodge", "Draw" }

-- Card→move mapping was REMOVED from this module: it lives on each CardData
-- entry as `Move = "<name>"`. If a card id lacks a Move field it is not
-- playable at casino tables.

function CombatTriangle.moveDef(move)
	return CombatTriangle.MOVE_DEFS[move]
end

-- Exposed for the client help screen / relationship chart UI.
function CombatTriangle.doesBeat(a, b)
	local def = CombatTriangle.MOVE_DEFS[a]
	return def ~= nil and def.beats[b] == true
end

function CombatTriangle.defaultSpeed(move)
	local def = CombatTriangle.MOVE_DEFS[move]
	return def and def.speed or 1
end

-- ============================================================================
-- RESOLUTION
-- ============================================================================
-- aMove/bMove : names from MOVE_DEFS (callers map cards via CardData.Move).
-- aStats/bStats: { Damage = number, Speed = number? } for the played card.
--   Speed overrides the registry default; Damage defaults 0.
-- Returns a plain table; the caller applies results to its own state:
--   { Winner = "A"|"B"|"None", DamageA/DamageB, EventA/EventB }
function CombatTriangle.resolve(aMove, bMove, aStats, bStats)
	local A = CombatTriangle.MOVE_DEFS[aMove]
	local B = CombatTriangle.MOVE_DEFS[bMove]
	if not A then error(("CombatTriangle: unknown move '%s'"):format(tostring(aMove))) end
	if not B then error(("CombatTriangle: unknown move '%s'"):format(tostring(bMove))) end

	local outcome = {
		Winner = "None",
		DamageA = 0,   -- damage dealt TO side A
		DamageB = 0,
		EventA = A.alwaysEvent, -- e.g. a Block was played; focus accrues win or lose
		EventB = B.alwaysEvent,
	}

	-- Mirror matches: Draw refills both; otherwise higher Speed wins, but
	-- only damage-dealing mirrors can actually hurt anyone.
	if aMove == bMove then
		if A.mirrorEvent then
			outcome.EventA = A.mirrorEvent
			outcome.EventB = B.mirrorEvent
			return outcome
		end
		local aSpd = (aStats and aStats.Speed) or A.speed
		local bSpd = (bStats and bStats.Speed) or B.speed
		local winner, wStats, wDef
		if aSpd > bSpd then
			winner, wStats, wDef = "A", aStats, A
		elseif bSpd > aSpd then
			winner, wStats, wDef = "B", bStats, B
		end
		if winner and wDef.damageOnWin then
			outcome.Winner = winner
			local dmg = (wStats and wStats.Damage) or 0
			if winner == "A" then outcome.DamageB = dmg else outcome.DamageA = dmg end
		end
		return outcome
	end

	-- Counter relationships; pairs with no entry in either direction are
	-- neutral (e.g. Block vs Dodge) and resolve to nothing.
	local winner, wStats, wDef = nil, nil, nil
	if A.beats[bMove] then
		winner, wStats, wDef = "A", aStats, A
	elseif B.beats[aMove] then
		winner, wStats, wDef = "B", bStats, B
	else
		return outcome
	end

	outcome.Winner = winner
	if wDef.damageOnWin then
		local dmg = (wStats and wStats.Damage) or 0
		if winner == "A" then outcome.DamageB = dmg else outcome.DamageA = dmg end
	end
	if wDef.winEvent then
		if winner == "A" then outcome.EventA = wDef.winEvent
		else outcome.EventB = wDef.winEvent end
	end

	return outcome
end

-- ============================================================================
-- SELF-TEST: run from the command bar —
--   local CT = require(game.ServerScriptService.Casino.CombatTriangle)
--   local errs = CT.selftest()
--   if #errs == 0 then print("CombatTriangle: all checks passed")
--   else for _, e in ipairs(errs) do print(e) end end
-- ============================================================================
function CombatTriangle.selftest()
	local errors = {}
	local function check(name, cond)
		if not cond then table.insert(errors, "FAIL: " .. name) end
	end

	local r

	-- Counters
	r = CombatTriangle.resolve("Attack", "Block", {Damage = 3}, {Damage = 0})
	check("Block beats Attack", r.Winner == "B" and r.DamageA == 0 and r.EventB == "Blocked")

	r = CombatTriangle.resolve("HeavyAttack", "Block", {Damage = 6}, {Damage = 99})
	check("Block win deals no damage", r.Winner == "B" and r.DamageA == 0)

	r = CombatTriangle.resolve("HeavyAttack", "Dodge", {Damage = 6}, {Damage = 0})
	check("HeavyAttack beats Dodge; failed dodge takes damage",
		r.Winner == "A" and r.DamageB == 6 and r.EventB == nil)

	r = CombatTriangle.resolve("Dodge", "Attack", {Damage = 0}, {Damage = 3})
	check("Dodge beats Attack; dodge win deals no damage but grants buff",
		r.Winner == "A" and r.DamageB == 0 and r.EventA == "Dodged")

	r = CombatTriangle.resolve("Attack", "Draw", {Damage = 3}, {Damage = 0})
	check("Attack beats Draw, draw fails, full damage lands",
		r.Winner == "A" and r.DamageB == 3)

	r = CombatTriangle.resolve("Draw", "Block", {Damage = 0}, {Damage = 0})
	check("Draw beats Block; draw win deals no damage but refills",
		r.Winner == "A" and r.DamageB == 0 and r.EventA == "Drew")

	-- Mirrors
	r = CombatTriangle.resolve("Draw", "Draw", {}, {})
	check("Draw-Draw mutual refill", r.Winner == "None" and r.EventA == "Drew" and r.EventB == "Drew")

	r = CombatTriangle.resolve("Attack", "Attack", {Damage = 3, Speed = 5}, {Damage = 3, Speed = 5})
	check("equal-speed Attack mirror: no damage", r.Winner == "None" and r.DamageA == 0 and r.DamageB == 0)

	r = CombatTriangle.resolve("Attack", "Attack", {Damage = 3, Speed = 7}, {Damage = 3, Speed = 5})
	check("faster Attack wins mirror", r.Winner == "A" and r.DamageB == 3)

	-- [doc-gap] resolutions
	r = CombatTriangle.resolve("Attack", "HeavyAttack", {Damage = 3}, {Damage = 6})
	check("[doc-gap] Attack beats HeavyAttack", r.Winner == "A" and r.DamageB == 3)

	r = CombatTriangle.resolve("Block", "Dodge", {}, {})
	check("[doc-gap] Block vs Dodge neutral", r.Winner == "None" and r.DamageA == 0 and r.DamageB == 0)

	return errors
end

return CombatTriangle