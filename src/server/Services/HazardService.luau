-- Each host has its own hazard (Config.Hosts[i].Hazard, numbers in Config.Hazards):
--   Whiskers  (Nibbles)  a whisker sweeps around the dish and knocks germs outward
--   Drool     (Barkley)  a drool wave pushes everything one way
--   Suction   (Trunk)    everyone is pulled toward the middle
--   FireBurp  (Ember)    after a warning the outer ring burns: get inside or shrink
--   Ink       (Kraken)   ink clouds drift around; germs inside one are hidden
--   Warp      (Zorb)     pairs of warp holes teleport you across the dish
-- Clients get a DishFx message so they can draw it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local World = require(script.Parent.World)
local DishService = require(script.Parent.DishService)

local HazardService = {}
local H = Config.Hazards

local function fx(dish, kind, data)
	World.fireDish(dish, Net.DishFx, kind, data)
end

local function worldPoints(dish, list)
	local out = {}
	for i, p in list do
		out[i] = { x = p.x + dish.cx, z = p.z + dish.cz, r = p.r }
	end
	return out
end

local function placeInk(dish)
	dish.ink = {}
	for _ = 1, H.Ink.Clouds do
		local x, z = World.randomInZone(dish, math.random(1, 3), H.Ink.CloudRadius)
		table.insert(dish.ink, { x = x, z = z, r = H.Ink.CloudRadius })
	end
	fx(dish, "Ink", worldPoints(dish, dish.ink))
end

local function placeWarps(dish)
	dish.warps = {}
	for i = 1, H.Warp.Holes do
		local x, z = World.randomInZone(dish, math.random(1, 3), 20)
		local to = i % 2 == 1 and i + 1 or i - 1
		table.insert(dish.warps, { x = x, z = z, r = H.Warp.HoleRadius, to = to })
	end
	fx(dish, "Warps", worldPoints(dish, dish.warps))
end

-- Starts the host's hazard right now (also used by the Dev panel)
function HazardService.trigger(dish)
	if dish.kind ~= "host" then
		return
	end
	local kind = Config.Hosts[dish.host].Hazard
	local now = World.now()
	local t = dish.timers
	if kind == "Whiskers" then
		t.whiskerFrom = now + H.Whiskers.Warn -- it shows first, then sweeps
		t.whiskerAngle = math.random() * math.pi * 2
		t.whiskerId = (t.whiskerId or 0) + 1
		fx(dish, "Whiskers", { duration = H.Whiskers.Duration, warn = H.Whiskers.Warn, angle = t.whiskerAngle, length = dish.layout.radius })
	elseif kind == "Drool" then
		local a = math.random() * math.pi * 2
		dish.effects.pushX, dish.effects.pushZ = math.cos(a) * H.Drool.Push, math.sin(a) * H.Drool.Push
		t.hazardEnd = now + H.Drool.Duration
		fx(dish, "Drool", { dx = math.cos(a), dz = math.sin(a), duration = H.Drool.Duration })
	elseif kind == "Suction" then
		dish.effects.pull = H.Suction.Pull
		t.hazardEnd = now + H.Suction.Duration
		fx(dish, "Suction", { duration = H.Suction.Duration })
	elseif kind == "FireBurp" then
		t.fireAt = now + H.FireBurp.Warn
		fx(dish, "FireWarn", { seconds = H.FireBurp.Warn, from = (dish.layout.zones[2].Outer + dish.layout.radius) / 2 })
	elseif kind == "Ink" then
		placeInk(dish)
	elseif kind == "Warp" then
		placeWarps(dish)
	end
end

function HazardService.start()
	DishService.onSecond(function(dish, now)
		if dish.kind ~= "host" then
			return
		end
		local kind = Config.Hosts[dish.host].Hazard
		local t = dish.timers
		if kind == "Ink" and #dish.ink == 0 then
			placeInk(dish)
		elseif kind == "Warp" and #dish.warps == 0 then
			placeWarps(dish)
		end
		local every = H[kind].Every or H[kind].MoveEvery or 30
		t.hazardNext = t.hazardNext or (now + every)
		if now >= t.hazardNext then
			t.hazardNext = now + every
			HazardService.trigger(dish)
		end
		-- end timed hazards
		if t.hazardEnd and now >= t.hazardEnd then
			t.hazardEnd = nil
			dish.effects.pushX, dish.effects.pushZ, dish.effects.pull = 0, 0, dish.effects.basePull or 0
			fx(dish, "HazardEnd", {})
		end
		if t.fireAt and now >= t.fireAt then
			t.fireAt = nil
			-- only the outer half of zone 1 burns: most germs here are too small for zone 2, so
			-- burning all of zone 1 cost them about a quarter of their size with no way out
			local from = (dish.layout.zones[2].Outer + dish.layout.radius) / 2
			dish.effects.burnFrom = from
			dish.effects.burnRate = H.FireBurp.DamagePerSecond
			t.fireEnd = now + H.FireBurp.Duration
			fx(dish, "Fire", { from = from, duration = H.FireBurp.Duration })
		end
		if t.fireEnd and now >= t.fireEnd then
			t.fireEnd = nil
			dish.effects.burnFrom = nil
			fx(dish, "HazardEnd", {})
		end
	end)

	-- the whisker sweep moves every tick
	DishService.onTick(function(dish, _, now)
		local t = dish.timers
		if not t or not t.whiskerFrom then
			return
		end
		local p = (now - t.whiskerFrom) / H.Whiskers.Duration
		if p < 0 then
			return -- still the warning
		end
		if p >= 1 then
			t.whiskerFrom = nil
			return
		end
		local angle = t.whiskerAngle + p * math.pi * 2
		local ax, az = math.cos(angle), math.sin(angle)
		for _, cell in dish.cells do
			-- a dashing germ goes straight through the whisker
			if not cell.germ.npc and cell.whisker ~= t.whiskerId and now >= cell.germ.dashUntil then
				-- distance from the whisker line (a ray from the centre)
				local along = cell.x * ax + cell.z * az
				local across = math.abs(-cell.x * az + cell.z * ax)
				if along > 0 and across < cell.r + 3 then
					cell.whisker = t.whiskerId
					local d = math.max(1, math.sqrt(cell.x * cell.x + cell.z * cell.z))
					-- knocked sideways (the way the whisker moves) and a bit outward
					World.impulse(cell, (-az * 0.8 + cell.x / d * 0.4) * H.Whiskers.Push, (ax * 0.8 + cell.z / d * 0.4) * H.Whiskers.Push)
				end
			end
		end
	end)

	-- a player arriving sees the ink clouds and warp holes that are already there
	DishService.onEnter(function(player, dish)
		if #dish.ink > 0 then
			Net.DishFx:FireClient(player, "Ink", worldPoints(dish, dish.ink))
		end
		if #dish.warps > 0 then
			Net.DishFx:FireClient(player, "Warps", worldPoints(dish, dish.warps))
		end
		if dish.bushes and #dish.bushes > 0 then
			Net.DishFx:FireClient(player, "Bushes", worldPoints(dish, dish.bushes))
		end
		if dish.spikes and #dish.spikes > 0 then
			Net.DishFx:FireClient(player, "Spikes", worldPoints(dish, dish.spikes))
		end
	end)
end

return HazardService
