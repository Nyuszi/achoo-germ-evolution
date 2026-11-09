-- Turns a germ's build (equipped mutations + levels, fusions, core, skills, passes) into the
-- numbers the simulation uses. Shared so the server and the Lab screen agree.
local Config = require(script.Parent.Config)
local Formulas = require(script.Parent.Formulas)

local Stats = {}

-- build = {
--   equipped = { [slot] = mutationId or fusionId },  levels = { [mutationId] = level },
--   core = "Blob", skills = { [skillId] = level }, passes = { [passId] = true },
--   sneezes = n, mutant = n, levelCap = n (Arena), potion = bool, arena = bool,
--   host = n (in hosts: only Config.SlotsPerHost[host] slots and levels up to LevelCapPerHost count) }
function Stats.compute(build)
	local s = {
		bite = 0, thorns = 0, armor = 0, speed = 0, pierce = 0, absorb = 0, magnet = 0,
		dashMult = 1, trail = 0, poison = 0, eatRatio = Config.EatRatio, dashCooldown = Config.Dash.Cooldown,
		splitArmor = 0, foodMult = 1, growthMult = 1, dnaMult = 1, respawnShare = Config.RespawnShare,
		fusions = {}, actives = {}, camo = false, startMult = 1,
	}
	local levels = build.levels or {}
	local cap = build.levelCap or Config.MaxMutationLevel
	local slotLimit, fusionsOk = #Config.Slots, true
	if not build.arena and build.host then
		local lim = Formulas.hostLimits(build.host)
		cap = math.min(cap, lim.levelCap)
		slotLimit = lim.slots
		fusionsOk = lim.fusions
	end

	local function addMutation(id, level)
		level = math.min(level or 1, cap)
		s.bite = s.bite + Formulas.mutationStat(id, "Bite", level)
		s.thorns = s.thorns + Formulas.mutationStat(id, "Thorns", level)
		s.armor = s.armor + Formulas.mutationStat(id, "Armor", level)
		s.speed = s.speed + Formulas.mutationStat(id, "Speed", level)
		s.pierce = s.pierce + Formulas.mutationStat(id, "Pierce", level)
		s.absorb = s.absorb + Formulas.mutationStat(id, "Absorb", level)
		s.magnet = s.magnet + Formulas.mutationStat(id, "Magnet", level)
		s.dashMult = s.dashMult + Formulas.mutationStat(id, "DashMult", level)
		s.trail = s.trail + Formulas.mutationStat(id, "Trail", level)
		s.poison = s.poison + Formulas.mutationStat(id, "Poison", level)
		local m = Config.Mutations[id]
		if m.Active then
			s.actives[m.Slot] = { id = m.Active, cooldown = m.Cooldown }
		end
		if id == "Camo" then
			s.camo = true
		end
	end

	-- slots fill in a fixed order, so a build with more than the host allows uses the first ones
	local equipped = build.equipped or {}
	local used = 0
	for _, slot in ipairs(Config.Slots) do
		local id = equipped[slot]
		if id and Config.Mutations[id] then
			used = used + 1
			if used <= slotLimit then
				addMutation(id, levels[id] or 1)
			end
		elseif id and Config.Fusions[id] and fusionsOk and not (build.arena and (build.floor or 0) < Config.Arena.FusionFloor) then
			local f = Config.Fusions[id]
			used = used + #f.Parts
			if used <= slotLimit then
				s.fusions[id] = true
				for _, part in ipairs(f.Parts) do
					addMutation(part, Config.MaxMutationLevel)
				end
			end
		end
	end

	-- fusion specials
	if s.fusions.BlackHole then
		s.eatRatio = 1.15
	end
	if s.fusions.Fortress then
		s.armor = s.armor * 2
		s.thorns = s.thorns * 2
	end
	if s.fusions.Venom then
		s.poison = s.poison * 2
	end

	-- core
	local core = Config.Cores[build.core or "Blob"]
	if core then
		s.speed = s.speed + (core.Speed or 0)
		s.armor = s.armor + (core.Armor or 0)
		s.thorns = s.thorns + (core.Thorns or 0)
		s.absorb = s.absorb + (core.Absorb or 0)
		s.splitArmor = core.SplitArmor or 0
		s.dashCooldown = s.dashCooldown + (core.DashCooldown or 0)
	end

	-- Germ Points skills (they count in the Arena too: they are earned, not bought)
	local skills = build.skills or {}
	local function skill(id)
		return (skills[id] or 0) * Config.Skills[id].Per
	end
	s.dnaMult = s.dnaMult + skill("Hunter")
	s.absorb = s.absorb + skill("Glutton")
	s.speed = s.speed + skill("Sprinter")
	s.dashCooldown = math.max(1, s.dashCooldown - skill("Dasher"))
	s.respawnShare = s.respawnShare + skill("Survivor")
	s.startMult = 1 + skill("Starter")

	-- sneezes and Mutant tiers (not in the Arena: everyone is equal there)
	if not build.arena then
		s.growthMult = Formulas.growthMult(build.sneezes)
		s.dnaMult = s.dnaMult + Config.MutantDnaBonus * math.min(build.mutant or 0, Config.MutantBonusCap)
		-- paid boosts work in hosts only
		local passes = build.passes or {}
		if passes.DoubleDna then
			s.dnaMult = s.dnaMult * 2
		end
		if passes.VIP then
			s.dnaMult = s.dnaMult + 0.1
		end
		if passes.FastGrowth then
			s.absorb = s.absorb + 0.5
		end
		if passes.AutoCollect then
			s.magnet = s.magnet + 10
		end
		if passes.Vaccine then
			s.respawnShare = math.max(s.respawnShare, Config.VaccineRespawnShare)
		end
		if build.potion then
			s.growthMult = s.growthMult * 2
		end
	end

	s.foodMult = (1 + s.absorb) * s.growthMult
	s.armor = math.max(-0.5, math.min(0.8, s.armor))
	return s
end

return Stats
