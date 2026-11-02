-- Move your resolveEffects here as standalone commands
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatUpdate = ReplicatedStorage.Remotes.CombatUpdate

return {
	Damage = function(ctx)
		if not ctx.targetCharacter then return end
		if ctx.canDamage and not ctx.canDamage(ctx.attacker, ctx.targetCharacter) then return end
		local res = ctx.damage(ctx.targetCharacter, ctx.amount, ctx.attacker)
		if ctx.targetPlayer then
			CombatUpdate:FireClient(ctx.targetPlayer, {Type = "Hit", Data = res})
		end
		return {Type = "Damage", Result = res}
	end,

	Block = function(ctx)
		if ctx.combat then ctx.combat.blockStacks += ctx.stacks end
		return {Type = "Block", Stacks = ctx.stacks}
	end,

	Dodge = function(ctx)
		if ctx.combat then ctx.combat.dodgeUntil = os.clock() + ctx.duration end
		return {Type = "Dodge", Duration = ctx.duration}
	end,

	Draw = function(ctx)
		if not ctx.deck then return end
		local before = #ctx.deck.hand
		ctx.deck:draw(ctx.amount)
		return {Type = "Draw", Amount = #ctx.deck.hand - before}
	end,

	GrantExtraPlays = function(ctx)
		if ctx.combat then ctx.combat.extraPlays += ctx.amount end
		return {Type = "ExtraPlays", Amount = ctx.amount}
	end,
}