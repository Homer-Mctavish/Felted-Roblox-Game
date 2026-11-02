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
		local combat = ctx.session:getCombat(ctx.attacker)
		if combat then combat.blockStacks += ctx.stacks end
		return {Type = "Block", Stacks = ctx.stacks}
	end,

	Dodge = function(ctx)
		local combat = ctx.session:getCombat(ctx.attacker)
		if combat then combat.dodgeUntil = os.clock() + ctx.duration end
		return {Type = "Dodge", Duration = ctx.duration}
	end,

	Draw = function(ctx)
		local deck = ctx.session:getDeck(ctx.attacker)
		if not deck then return end
		local before = #deck.hand
		deck:draw(ctx.amount)
		return {Type = "Draw", Amount = #deck.hand - before}
	end,

	GrantExtraPlays = function(ctx)
		local combat = ctx.session:getCombat(ctx.attacker)
		if combat then combat.extraPlays += ctx.amount end
		return {Type = "ExtraPlays", Amount = ctx.amount}
	end,
}