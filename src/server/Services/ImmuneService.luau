-- The host fights back. Every host dish has:
--   Whitey      a white blood cell that hunts germs in the inner zones (drains or swallows them)
--   Antibodies  little Y-shapes drifting in the inner zones: bigger germs eat them, smaller ones get slowed
--   Macrophage  a giant boss that shows up every few minutes and gulps germs; beat it together
--   Fever       the host heats up: double food, double DNA, harder fights
--   Medicine    the host takes medicine: the dish wall closes in for a minute
-- Bosses have health. Everyone who dealt at least 5% of it shares the DNA reward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local World = require(script.Parent.World)
local DishService = require(script.Parent.DishService)
local Bus = require(script.Parent.Bus)

local ImmuneService = {}
local I = Config.Immune

local WHITE = Color3.fromRGB(245, 245, 255)

local function announce(dish, text)
	World.fireDish(dish, Net.Announce, text)
end

local function innerLimit(dish, minZone)
	local zones = dish.layout.zones
	if #zones < minZone then
		return dish.wall
	end
	return zones[minZone].Outer
end

local function spawnNpc(dish, kind, name, color, size, npc, x, z)
	npc.kind = kind
	npc.damageBy = {}
	local germ = World.newGerm({ name = name, color = color, npc = npc, equipped = {} })
	World.spawnGerm(germ, dish, size, x, z)
	germ.shieldUntil = 0
	return germ
end

function ImmuneService.spawnWhitey(dish, opts)
	opts = opts or {}
	local sneeze = dish.layout.sneeze
	local share = opts.giant and 1.1 or I.Whitey.SizeShare
	local x, z = World.randomInZone(dish, math.min(I.Whitey.MinZone, #dish.layout.zones), 10)
	-- a giant or hunting Whitey may leave the inner zones ("x and nil or y" always gave y, so a
	-- hunter used to stop at the zone edge and never reach its target)
	local maxDist = nil
	if not opts.giant and not opts.hunt then
		maxDist = innerLimit(dish, I.Whitey.MinZone)
	end
	local germ = spawnNpc(dish, "whitey", opts.giant and "Giant Whitey" or "Whitey", WHITE, sneeze * share, {
		speed = I.Whitey.Speed * (opts.hunt and 1.6 or 1), -- a hunter hurries
		drain = I.Whitey.DrainPerSecond,
		hp = sneeze * I.Whitey.HpShare * (opts.giant and 2 or 1),
		maxHp = sneeze * I.Whitey.HpShare * (opts.giant and 2 or 1),
		reward = I.Whitey.RewardShare,
		hunt = opts.hunt, -- a germ to chase first (Immune Strike)
		maxDist = maxDist, -- nil = may go anywhere
	}, x, z)
	dish.whitey = germ
	return germ
end

function ImmuneService.spawnMacrophage(dish)
	local sneeze = dish.layout.sneeze
	local x, z = World.randomInZone(dish, math.min(2, #dish.layout.zones), 30)
	local germ = spawnNpc(dish, "macrophage", "Macrophage Mama", Color3.fromRGB(190, 120, 230), sneeze * I.Macrophage.SizeShare, {
		speed = I.Macrophage.Speed,
		drain = I.Macrophage.DrainPerSecond,
		hp = sneeze * I.Macrophage.HpShare,
		maxHp = sneeze * I.Macrophage.HpShare,
		reward = I.Macrophage.RewardShare,
		diesAt = World.now() + I.Macrophage.Lifetime,
		maxDist = innerLimit(dish, 2), -- she leaves the outer zone (where new germs start) alone
		nextGulp = World.now() + I.Macrophage.GulpEvery,
	}, x, z)
	dish.macrophage = germ
	announce(dish, "🟣 MACROPHAGE MAMA is here! Team up to beat her, or swim for your life!")
	return germ
end

local function spawnAntibody(dish)
	local x, z = World.randomInZone(dish, math.min(I.Antibodies.MinZone, #dish.layout.zones), 6)
	return spawnNpc(dish, "antibody", "Antibody", Color3.fromRGB(120, 180, 255), dish.layout.sneeze * 0.01, {
		speed = I.Antibodies.Speed,
		drain = 0,
		maxDist = innerLimit(dish, I.Antibodies.MinZone),
	}, x, z)
end

function ImmuneService.startFever(dish, by)
	local f = I.Fever
	dish.effects.foodMult, dish.effects.damageMult, dish.effects.dnaMult = f.FoodMult, f.DamageMult, f.DnaMult
	dish.timers.feverEnd = World.now() + f.Duration
	World.fireDish(dish, Net.DishFx, "Fever", { duration = f.Duration })
	announce(dish, "🌡️ FEVER! " .. (by and (by .. " started a Fever! ") or "") .. "Double food and DNA for 90 seconds, but fights hurt more")
end

function ImmuneService.startMedicine(dish)
	local m = I.Medicine
	dish.wallTarget = dish.layout.radius * m.ShrinkTo
	dish.timers.medicineEnd = World.now() + m.Duration
	World.fireDish(dish, Net.DishFx, "Medicine", { wall = dish.wallTarget, duration = m.Duration })
	announce(dish, "💊 The host took MEDICINE! The walls are closing in for a minute")
end

local function npcsOf(dish)
	local list = {}
	for _, germ in World.dishGerms(dish) do
		if germ.npc then
			table.insert(list, germ)
		end
	end
	return list
end

-- Steering for every immune NPC (4 times a second)
local function think(dish, now)
	for _, germ in npcsOf(dish) do
		local npc = germ.npc
		local cx, cz = World.germCentre(germ)
		if npc.kind == "antibody" then
			if not germ.target or now >= (npc.wanderAt or 0) then
				local x, z = World.randomInZone(dish, math.min(I.Antibodies.MinZone, #dish.layout.zones), 6)
				germ.target = { x = x, z = z }
				npc.wanderAt = now + 5 + math.random() * 5
			end
		else
			local best, bestD = nil, math.huge
			if npc.hunt and npc.hunt.alive and npc.hunt.dish == dish then
				best = npc.hunt
			else
				npc.hunt = nil
				for _, other in World.dishGerms(dish) do
					if not other.npc and not World.isProtected(other) and not World.isHidden(other) then
						local ox, oz = World.germCentre(other)
						local fromCentre = math.sqrt(ox * ox + oz * oz)
						if not npc.maxDist or fromCentre <= npc.maxDist + 10 then
							local dx, dz = ox - cx, oz - cz
							local d = dx * dx + dz * dz
							if other.player then
								d *= 0.7 -- prefers real players a little
							end
							if d < bestD and d < 220 * 220 then
								best, bestD = other, d
							end
						end
					end
				end
			end
			if best then
				local ox, oz = World.germCentre(best)
				germ.target = { x = ox, z = oz }
				if npc.kind == "macrophage" and now >= npc.nextGulp then
					npc.nextGulp = now + I.Macrophage.GulpEvery
					local dx, dz = ox - cx, oz - cz
					local len = math.sqrt(dx * dx + dz * dz)
					if len > 0.1 then
						for _, cell in germ.cells do
							World.impulse(cell, dx / len * 60, dz / len * 60)
						end
						World.fireDish(dish, Net.DishFx, "Gulp", { id = germ.id })
					end
				end
			elseif not germ.target or now >= (npc.wanderAt or 0) then
				local zone = npc.maxDist and math.min(I.Whitey.MinZone, #dish.layout.zones) or 1
				local x, z = World.randomInZone(dish, zone, 10)
				germ.target = { x = x, z = z }
				npc.wanderAt = now + 6
			end
		end
		-- stay inside the zones this NPC lives in
		if npc.maxDist and germ.target then
			local t = germ.target
			local d = math.sqrt(t.x * t.x + t.z * t.z)
			if d > npc.maxDist then
				t.x, t.z = t.x / d * npc.maxDist, t.z / d * npc.maxDist
			end
		end
	end
end

-- Shares a boss reward between everyone who helped (at least 5% of its health)
local function onBossDefeated(boss, damageBy)
	local dish = boss.dish
	local npc = boss.npc
	local helpers = {}
	for germ, dmg in damageBy or {} do
		if dmg >= npc.maxHp * I.MinContribution then
			table.insert(helpers, germ)
		end
	end
	local dna = math.floor(npc.reward * dish.layout.sneeze / dish.scale + 0.5)
	local names = {}
	for _, germ in helpers do
		World.hooks.gainDna(germ, dna)
		-- winners also grow a bit
		World.setGermSize(germ, World.germSize(germ) * 1.1)
		if germ.player then
			Net.notify(germ.player, "You helped beat " .. boss.name .. "! +" .. dna .. " DNA", "success")
			Bus.fire("Boss", germ.player, npc.kind)
		end
		table.insert(names, germ.name)
	end
	announce(dish, "🏆 " .. boss.name .. " was defeated by " .. (#names > 0 and table.concat(names, ", ") or "the germs") .. "!")
	if dish.whitey == boss then
		dish.whitey = nil
		dish.timers.whiteyAt = World.now() + I.Whitey.RespawnSeconds
	elseif dish.macrophage == boss then
		dish.macrophage = nil
	end
end
ImmuneService.onBossDefeated = onBossDefeated

function ImmuneService.start()
	DishService.onSecond(function(dish, now)
		local t = dish.timers
		if dish.kind ~= "host" then
			-- Arena: only the Giant Whitey modifier
			if dish.giantWhitey and not (dish.whitey and dish.whitey.alive) and now >= (t.whiteyAt or 0) then
				ImmuneService.spawnWhitey(dish, { giant = true })
			end
			return
		end
		local age = now - dish.openedAt
		-- Whitey
		if not (dish.whitey and dish.whitey.alive) and now >= (t.whiteyAt or (dish.openedAt + 30)) then
			ImmuneService.spawnWhitey(dish)
		end
		-- antibodies
		local count = 0
		for _, germ in World.dishGerms(dish) do
			if germ.npc and germ.npc.kind == "antibody" then
				count += 1
			end
		end
		if count < I.Antibodies.Count and age > 10 then
			spawnAntibody(dish)
		end
		-- Macrophage
		t.macroAt = t.macroAt or (dish.openedAt + I.Macrophage.FirstAfter)
		if now >= t.macroAt then
			t.macroAt = now + I.Macrophage.EverySeconds
			if not (dish.macrophage and dish.macrophage.alive) then
				ImmuneService.spawnMacrophage(dish)
			end
		end
		local m = dish.macrophage
		if m and m.alive and now >= m.npc.diesAt then
			World.removeGerm(m)
			dish.macrophage = nil
			announce(dish, "Macrophage Mama swam away... she'll be back")
		end
		-- Fever
		t.feverAt = t.feverAt or (dish.openedAt + I.Fever.FirstAfter)
		if now >= t.feverAt then
			t.feverAt = now + I.Fever.EverySeconds
			ImmuneService.startFever(dish)
		end
		if t.feverEnd and now >= t.feverEnd then
			t.feverEnd = nil
			dish.effects.foodMult, dish.effects.damageMult, dish.effects.dnaMult = 1, 1, 1
			World.fireDish(dish, Net.DishFx, "FeverEnd", {})
			for _, germ in World.dishGerms(dish) do
				if germ.player then
					Bus.fire("Fever", germ.player)
				end
			end
		end
		-- Medicine
		t.medicineAt = t.medicineAt or (dish.openedAt + I.Medicine.FirstAfter)
		if now >= t.medicineAt then
			t.medicineAt = now + I.Medicine.EverySeconds
			ImmuneService.startMedicine(dish)
		end
		if t.medicineEnd and now >= t.medicineEnd then
			t.medicineEnd = nil
			dish.wallTarget = dish.layout.radius
			World.fireDish(dish, Net.DishFx, "MedicineEnd", { wall = dish.wallTarget })
		end
		-- boss health bars for the clients
		for _, germ in npcsOf(dish) do
			if germ.npc.maxHp and germ.npc.kind ~= "antibody" then
				World.fireDish(dish, Net.DishFx, "BossHp", { id = germ.id, name = germ.name, hp = math.max(0, germ.npc.hp), max = germ.npc.maxHp })
			end
		end
	end)

	local acc = {}
	DishService.onTick(function(dish, dt, now)
		acc[dish] = (acc[dish] or 0) + dt
		if acc[dish] >= 0.25 then
			acc[dish] = 0
			think(dish, now)
		end
	end)
	DishService.onRemoved(function(dish)
		acc[dish] = nil
	end)
	-- someone arriving in the middle of a Fever or Medicine sees it too
	DishService.onEnter(function(player, dish)
		local t = dish.timers
		if not t then
			return
		end
		local now = World.now()
		if t.feverEnd and now < t.feverEnd then
			Net.DishFx:FireClient(player, "Fever", { duration = t.feverEnd - now })
		end
		if t.medicineEnd and now < t.medicineEnd then
			Net.DishFx:FireClient(player, "Medicine", { wall = dish.wallTarget, duration = t.medicineEnd - now })
		end
	end)
end

return ImmuneService
