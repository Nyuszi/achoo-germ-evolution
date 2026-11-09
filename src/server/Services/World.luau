-- The simulation. The world holds several "dishes": one per host in use and one per Arena floor
-- in use. Each dish has its own germs, food, zones, hazards and events. The server owns
-- everything; clients send where they steer and draw the snapshots of their own dish.
--
-- A "germ" is one player, bot or immune NPC. A germ has 1-2 "cells" (2 after a split).
-- Cell and food positions are stored relative to their dish's centre; the network sends
-- world positions (centre + local).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Net = require(script.Parent.Net)

local World = {}

local dishes = {} -- [dishId] = dish
local germs = {} -- [germId] = germ
local cells = {} -- [cellId] = cell (all dishes)
local nextId = 0
local now = 0 -- simulation clock in seconds
local slotsUsed = {} -- world slots for dish centres

World.hooks = {
	gainDna = function(germ, amount) end,
	germDied = function(victim, eater) end, -- every cell of a germ was swallowed
	ateGerm = function(eater, victim, info) end, -- info = { dna, revenge, crowned }
	ateFood = function(germ, count, golden) end,
	sneeze = function(germ) end, -- a germ at sneeze size touched the Sneeze Nerve
	bossHit = function(boss, attacker, amount) end,
	bossDefeated = function(boss, damageBy) end,
	viewersChanged = function(dish) end,
	dishTick = function(dish, dt) end, -- hazards and bosses that move every tick
}

local function newId()
	nextId += 1
	return nextId
end

function World.now()
	return now
end

-- Dishes -------------------------------------------------------------------------------------

local G = Config.GridCell
local function gridKey(gx, gz)
	return gx * 100000 + gz
end
local function cellOf(v)
	return math.floor(v / G)
end

-- kind = "host" (hostIndex) or "arena" (floor). Returns a new dish at a free spot in the world.
function World.newDish(kind, index, layout)
	local slot = 1
	while slotsUsed[slot] do
		slot += 1
	end
	slotsUsed[slot] = true
	local dish = {
		id = newId(),
		slot = slot,
		kind = kind,
		host = kind == "host" and index or nil,
		floor = kind == "arena" and index or nil,
		layout = layout,
		scale = layout.scale,
		cx = (slot - 1) * Config.DishSpacing,
		cz = 0,
		wall = layout.radius,
		wallTarget = layout.radius,
		cells = {},
		food = {},
		foodGrid = {},
		zoneFoodCount = {},
		zoneCrumbCount = {},
		bubbles = {},
		crowned = nil,
		foodAdded = {},
		foodRemoved = {},
		cellsGone = {},
		eatenBy = {}, -- [tostring(cellId)] = eater cellId, sent with cellsGone
		info = { cells = {}, germs = {} },
		infoDirty = false,
		effects = { foodMult = 1, damageMult = 1, dnaMult = 1, pushX = 0, pushZ = 0, pull = 0, burnFrom = nil, burnRate = 0 },
		ink = {}, -- { x, z, r } clouds that hide germs
		warps = {}, -- { x, z, to }
		spikes = {}, -- { x, z, r } Arena spike field
		hidden = {}, -- [germ] = true, refreshed every tick
		viewers = {}, -- [player] = true
		tick = 0,
	}
	if kind == "host" then
		local d = layout.radius - Config.SpawnBubbleRadius - 30
		for i = 1, 6 do
			local a = (i / 6) * math.pi * 2
			table.insert(dish.bubbles, { x = math.cos(a) * d, z = math.sin(a) * d })
		end
	end
	dishes[dish.id] = dish
	for _ = 1, 200 do
		World.refillFood(dish)
	end
	dish.foodAdded, dish.foodRemoved = {}, {}
	return dish
end

function World.removeDish(dish)
	for _, cell in dish.cells do
		cells[cell.id] = nil
	end
	dishes[dish.id] = nil
	slotsUsed[dish.slot] = nil
end

function World.dishes()
	return dishes
end

function World.dish(id)
	return dishes[id]
end

-- Players who receive this dish's snapshots
function World.setViewer(player, dish)
	for _, d in dishes do
		if d.viewers[player] and d ~= dish then
			d.viewers[player] = nil
			World.hooks.viewersChanged(d)
		end
	end
	if dish and not dish.viewers[player] then
		dish.viewers[player] = true
		World.hooks.viewersChanged(dish)
	end
end

local function fireDish(dish, remote, ...)
	for player in dish.viewers do
		if player.Parent then
			remote:FireClient(player, ...)
		end
	end
end
World.fireDish = fireDish

-- Food -------------------------------------------------------------------------------------

-- big = a big crumb (see Config.BigFood): it counts toward its zone's crumbs, not its pellets
local function addFood(dish, x, z, value, zone, golden, big)
	local id = newId()
	local pellet = { id = id, x = x, z = z, v = value, zone = (not big) and zone or nil, golden = golden }
	if big then
		pellet.need = value * Config.BigFood.NeedMult
		pellet.crumbZone = zone
		dish.zoneCrumbCount[zone] = (dish.zoneCrumbCount[zone] or 0) + 1
	end
	dish.food[id] = pellet
	local key = gridKey(cellOf(x), cellOf(z))
	local bucket = dish.foodGrid[key]
	if not bucket then
		bucket = {}
		dish.foodGrid[key] = bucket
	end
	bucket[id] = pellet
	pellet.key = key
	if zone then
		dish.zoneFoodCount[zone] = (dish.zoneFoodCount[zone] or 0) + 1
	end
	local list = dish.foodAdded
	table.insert(list, id)
	table.insert(list, math.floor((x + dish.cx) * 10) / 10)
	table.insert(list, math.floor((z + dish.cz) * 10) / 10)
	table.insert(list, value / dish.scale)
	table.insert(list, golden and 1 or big and 2 or 0)
	return pellet
end
World.addFood = addFood

local function removeFood(dish, pellet)
	dish.food[pellet.id] = nil
	local bucket = dish.foodGrid[pellet.key]
	if bucket then
		bucket[pellet.id] = nil
	end
	if pellet.zone then
		dish.zoneFoodCount[pellet.zone] -= 1
	end
	if pellet.crumbZone then
		dish.zoneCrumbCount[pellet.crumbZone] -= 1
	end
	table.insert(dish.foodRemoved, pellet.id)
end

-- A random point in a zone's ring (local coordinates)
function World.randomInZone(dish, zone, margin)
	local zones = dish.layout.zones
	zone = math.clamp(zone, 1, #zones)
	local outer = math.min(zones[zone].Outer, dish.wall) - (margin or 4)
	local inner = 0
	if zones[zone + 1] then
		inner = zones[zone + 1].Outer + (margin or 4)
	end
	if inner >= outer then
		inner = 0
	end
	local angle = math.random() * math.pi * 2
	local dist = math.sqrt(math.random() * (outer * outer - inner * inner) + inner * inner)
	return math.cos(angle) * dist, math.sin(angle) * dist
end

function World.refillFood(dish)
	for zone, info in dish.layout.zones do
		local missing = info.FoodCount - (dish.zoneFoodCount[zone] or 0)
		for _ = 1, math.min(missing, 8) do
			local x, z = World.randomInZone(dish, zone)
			addFood(dish, x, z, info.FoodValue * dish.scale, zone, false)
		end
		local crumbs = math.floor(info.FoodCount * Config.BigFood.Share)
		if (dish.zoneCrumbCount[zone] or 0) < crumbs and math.random() < Config.BigFood.RefillChance then
			local x, z = World.randomInZone(dish, zone, 10)
			addFood(dish, x, z, info.FoodValue * Config.BigFood.ValueMult * dish.scale, zone, false, true)
		end
	end
end

local function burstFood(dish, x, z, total, spread)
	local count = Config.BurstPellets
	local each = total / count
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.5
		local d = spread * (0.6 + math.random() * 0.8)
		local px, pz = x + math.cos(angle) * d, z + math.sin(angle) * d
		local dist = math.sqrt(px * px + pz * pz)
		local limit = dish.wall - 3
		if dist > limit then
			px, pz = px * limit / dist, pz * limit / dist
		end
		addFood(dish, px, pz, each, nil, false)
	end
end

function World.spawnGolden(dish)
	local zones = dish.layout.zones
	local zone = math.random(1, math.min(3, #zones))
	local x, z = World.randomInZone(dish, zone, 20)
	addFood(dish, x, z, Config.GoldenShare * dish.layout.sneeze, nil, true)
	return zone
end

-- The closest pellet within a few grid squares that a germ of this size may reach
-- (bots use this to graze).
function World.nearestFood(dish, x, z, reach, size)
	local minDist, maxDist = 0, math.huge
	if size then
		minDist, maxDist = Formulas.allowedRange(size, dish.layout, dish.wall)
	end
	local cx, cz = cellOf(x), cellOf(z)
	local n = math.max(1, math.ceil((reach or G) / G))
	local best, bestD = nil, math.huge
	for gx = cx - n, cx + n do
		for gz = cz - n, cz + n do
			local bucket = dish.foodGrid[gridKey(gx, gz)]
			if bucket then
				for _, pellet in bucket do
					local dx, dz = pellet.x - x, pellet.z - z
					local d = dx * dx + dz * dz
					local fromCentre = pellet.x * pellet.x + pellet.z * pellet.z
					if fromCentre < minDist * minDist or fromCentre > maxDist * maxDist or (pellet.need and size and size < pellet.need) then
						d = math.huge
					elseif pellet.golden then
						d *= 0.1
					end
					if d < bestD then
						best, bestD = pellet, d
					end
				end
			end
		end
	end
	return best
end

function World.foodList(dish)
	local list = {}
	for id, p in dish.food do
		table.insert(list, id)
		table.insert(list, math.floor((p.x + dish.cx) * 10) / 10)
		table.insert(list, math.floor((p.z + dish.cz) * 10) / 10)
		table.insert(list, p.v / dish.scale)
		table.insert(list, p.golden and 1 or p.need and 2 or 0)
	end
	return list
end

-- Germs and cells ------------------------------------------------------------------------------

-- What clients need to draw a germ. (Bots and players look the same on purpose.)
function World.germInfo(germ)
	local muts = {}
	for slot, id in germ.equipped do
		muts[slot] = id
	end
	return {
		name = germ.name,
		color = germ.color,
		userId = germ.player and germ.player.UserId or 0,
		muts = muts,
		core = germ.core or "Blob",
		skin = germ.skin, -- { Body, Pattern, Eyes, Mouth, Hat, Trail, Flag, Color2 }
		npc = germ.npc and germ.npc.kind or nil,
		vip = germ.vip,
		tier = germ.mutant or 0,
		rookie = germ.rookie,
	}
end

local function queueInfo(germ)
	local dish = germ.dish
	if not dish then
		return
	end
	dish.info.germs[germ.id] = World.germInfo(germ)
	for _, cell in germ.cells do
		dish.info.cells[cell.id] = germ.id
	end
	dish.infoDirty = true
end
World.refreshInfo = queueInfo

-- Sets the germ's numbers (from Stats.compute) and tells clients about its look.
function World.setStats(germ, stats)
	germ.stats = stats
	queueInfo(germ)
end

-- germ fields set by the caller: name, color, player / bot / npc, equipped, stats
function World.newGerm(fields)
	local germ = fields
	germ.id = newId()
	germ.cells = {}
	germ.alive = false
	germ.equipped = germ.equipped or {}
	germ.recentFeeds = {}
	germ.dashUntil = 0
	germ.dashReadyAt = 0
	germ.splitReadyAt = 0
	germ.shieldUntil = 0
	germ.bubbleTime = 0
	germ.quarantineUntil = germ.quarantineUntil or 0
	germ.abilityReady = {}
	germ.effects = {} -- timed effects: [name] = untilTime
	germ.target = nil
	germ.stats = germ.stats or Stats.compute({ equipped = germ.equipped })
	germs[germ.id] = germ
	return germ
end

function World.germ(id)
	return germs[id]
end

function World.allGerms()
	return germs
end

function World.germSize(germ)
	local total = 0
	for _, cell in germ.cells do
		total += cell.size
	end
	return total
end

-- The middle of all of a germ's cells, weighted by size (local coordinates).
function World.germCentre(germ)
	local sx, sz, total = 0, 0, 0
	for _, cell in germ.cells do
		sx += cell.x * cell.size
		sz += cell.z * cell.size
		total += cell.size
	end
	if total == 0 then
		return 0, 0
	end
	return sx / total, sz / total
end

local function addCell(germ, size, x, z)
	local dish = germ.dish
	local cell = {
		id = newId(),
		germ = germ,
		dish = dish,
		x = x,
		z = z,
		vx = 0,
		vz = 0,
		size = size,
		r = Formulas.radius(size, dish.scale),
		mergeAt = 0,
	}
	cells[cell.id] = cell
	dish.cells[cell.id] = cell
	germ.cells[cell.id] = cell
	return cell
end

-- by = the cell that swallowed it (clients animate it being gulped), or nil
local function removeCell(cell, by)
	if by then
		cell.dish.eatenBy[tostring(cell.id)] = by.id
	end
	cells[cell.id] = nil
	cell.dish.cells[cell.id] = nil
	cell.germ.cells[cell.id] = nil
	table.insert(cell.dish.cellsGone, cell.id)
end

-- A spawn point for a germ of this size: a spawn bubble in zone 1, otherwise a quiet spot
-- in the deepest zone it may enter.
function World.spawnPoint(dish, size)
	local zone = Formulas.deepestZone(size, dish.layout)
	if zone == 1 and #dish.bubbles > 0 then
		local b = dish.bubbles[math.random(1, #dish.bubbles)]
		local a = math.random() * math.pi * 2
		local d = math.random() * (Config.SpawnBubbleRadius * 0.5)
		return b.x + math.cos(a) * d, b.z + math.sin(a) * d
	end
	local bestX, bestZ, bestScore = 0, 0, -1
	for _ = 1, 8 do
		local x, z = World.randomInZone(dish, math.max(zone, Formulas.shallowestZone(size, dish.layout)), 10)
		local score = math.huge
		for _, other in dish.cells do
			if Formulas.canEat(other.size, size) then
				local dx, dz = other.x - x, other.z - z
				score = math.min(score, dx * dx + dz * dz)
			end
		end
		if score > bestScore then
			bestX, bestZ, bestScore = x, z, score
		end
	end
	return bestX, bestZ
end

-- Puts a germ into a dish (removing it from where it was) with the given size.
-- x, z (local) are optional.
function World.spawnGerm(germ, dish, size, x, z)
	local oldDish = germ.dish
	for _, cell in germ.cells do
		removeCell(cell)
	end
	if oldDish and oldDish ~= dish and oldDish.crowned == germ then
		oldDish.crowned = nil
	end
	germ.dish = dish
	if not x then
		x, z = World.spawnPoint(dish, size)
	end
	addCell(germ, size, x, z)
	germ.alive = true
	germ.target = { x = x, z = z }
	germ.shieldUntil = now + Config.SpawnShieldSeconds
	germ.bubbleTime = 0
	germ.spawnedAt = now
	germ.peakSize = size
	queueInfo(germ)
end

function World.removeGerm(germ)
	for _, cell in germ.cells do
		removeCell(cell)
	end
	germ.alive = false
	germs[germ.id] = nil
	if germ.dish and germ.dish.crowned == germ then
		germ.dish.crowned = nil
	end
end

-- Takes a germ's cells out of its dish but keeps the germ (sneezing, changing dish)
function World.despawn(germ)
	for _, cell in germ.cells do
		removeCell(cell)
	end
	germ.alive = false
	if germ.dish and germ.dish.crowned == germ then
		germ.dish.crowned = nil
	end
end

-- Removes a germ by popping it into food (a bot making room for a real player).
function World.popGerm(germ)
	for _, cell in germ.cells do
		burstFood(cell.dish, cell.x, cell.z, cell.size * 0.5, cell.r + 3)
	end
	World.removeGerm(germ)
end

-- Sets every cell of a germ to a total size (keeps the split ratio)
function World.setGermSize(germ, size)
	local total = World.germSize(germ)
	if total <= 0 then
		return
	end
	for _, cell in germ.cells do
		cell.size = cell.size / total * size
		cell.r = Formulas.radius(cell.size, cell.dish.scale)
	end
end

-- Germs in a dish (alive)
function World.dishGerms(dish)
	local list = {}
	local seen = {}
	for _, cell in dish.cells do
		if not seen[cell.germ] then
			seen[cell.germ] = true
			table.insert(list, cell.germ)
		end
	end
	return list
end

-- Moves -----------------------------------------------------------------------------------------

local function has(germ, effect)
	return (germ.effects[effect] or 0) > now
end
World.hasEffect = has

function World.addEffect(germ, effect, seconds)
	germ.effects[effect] = math.max(germ.effects[effect] or 0, now + seconds)
end

function World.dash(germ)
	if not germ.alive or now < germ.dashReadyAt or germ.npc then
		return false
	end
	local d = Config.Dash
	if World.germSize(germ) < d.MinSize * germ.dish.scale then
		return false
	end
	for _, cell in germ.cells do
		cell.size -= cell.size * d.CostShare
	end
	local mult = germ.stats.dashMult
	if germ.dish.effects.lowGravity then
		mult *= 2
	end
	germ.dashUntil = now + d.Duration * mult
	germ.dashReadyAt = now + germ.stats.dashCooldown
	if germ.stats.fusions.Ninja then
		World.addEffect(germ, "Ghost", 2)
	end
	germ.dashes = (germ.dashes or 0) + 1
	return true
end

function World.split(germ)
	local s = Config.Split
	if not germ.alive or now < germ.splitReadyAt or germ.npc then
		return false
	end
	-- every cell that is big enough splits in two (biggest first), up to MaxCells, and each half
	-- shoots toward where you steer. Press again to split again.
	local list, count = {}, 0
	for _, cell in germ.cells do
		count += 1
		table.insert(list, cell)
	end
	table.sort(list, function(a, b)
		return a.size > b.size
	end)
	local split = 0
	for _, cell in list do
		if count >= s.MaxCells or cell.size < s.MinSize * germ.dish.scale then
			break
		end
		local half = cell.size / 2
		cell.size = half
		cell.r = Formulas.radius(half, germ.dish.scale)
		local dx, dz = 1, 0
		if germ.target then
			dx, dz = germ.target.x - cell.x, germ.target.z - cell.z
			local len = math.sqrt(dx * dx + dz * dz)
			if len < 0.01 then
				dx, dz = 1, 0
			else
				dx, dz = dx / len, dz / len
			end
		end
		local new = addCell(germ, half, cell.x + dx * cell.r, cell.z + dz * cell.r)
		new.vx, new.vz = dx * s.LaunchSpeed, dz * s.LaunchSpeed
		new.mergeAt = now + s.MergeSeconds
		cell.mergeAt = now + s.MergeSeconds
		count += 1
		split += 1
	end
	if split == 0 then
		return false
	end
	germ.splitReadyAt = now + s.Cooldown
	queueInfo(germ)
	return true
end

-- Pushes a cell (studs per second, fades out)
function World.impulse(cell, vx, vz)
	cell.vx += vx
	cell.vz += vz
end

-- Active abilities: slot "Front" (Q) or "Special" (R)
function World.ability(germ, slot)
	local active = germ.stats.actives[slot]
	if not germ.alive or not active or now < (germ.abilityReady[slot] or 0) then
		return false
	end
	germ.abilityReady[slot] = now + active.cooldown
	local cx, cz = World.germCentre(germ)
	local myR = Formulas.radius(World.germSize(germ), germ.dish.scale)
	if active.id == "Chomp" then
		World.addEffect(germ, "Chomp", 1)
		local dx, dz = 0, 0
		if germ.target then
			dx, dz = germ.target.x - cx, germ.target.z - cz
		end
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 0.01 then
			for _, cell in germ.cells do
				World.impulse(cell, dx / len * 70, dz / len * 70)
			end
		end
	elseif active.id == "Vacuum" or active.id == "GravityWell" then
		World.addEffect(germ, active.id, 2)
	elseif active.id == "Pierce" then
		World.addEffect(germ, "Pierce", 3)
	elseif active.id == "Ghost" then
		World.addEffect(germ, "Ghost", 3)
	elseif active.id == "Blast" then
		for _, cell in germ.dish.cells do
			if cell.germ ~= germ and not cell.germ.npc then
				local dx, dz = cell.x - cx, cell.z - cz
				local d = math.sqrt(dx * dx + dz * dz)
				if d < myR * 5 + 10 and d > 0.01 then
					World.impulse(cell, dx / d * 120, dz / d * 120)
				end
			end
		end
		if germ.stats.fusions.Storm then
			World.addEffect(germ, "GravityWell", 2)
		end
	end
	World.fireDish(germ.dish, Net.DishFx, "Power", { id = germ.id, kind = active.id }) -- clients animate it
	return true
end

-- Protection ------------------------------------------------------------------------------------

local function inBubble(cell)
	for _, b in cell.dish.bubbles do
		local dx, dz = cell.x - b.x, cell.z - b.z
		if dx * dx + dz * dz <= Config.SpawnBubbleRadius * Config.SpawnBubbleRadius then
			return true
		end
	end
	return false
end

-- Germs that cannot be eaten right now.
function World.isProtected(germ)
	if now < germ.quarantineUntil or now < germ.shieldUntil then
		return true
	end
	return germ.inBubble == true and germ.bubbleTime < Config.SpawnBubbleSeconds
end

-- May this germ swallow that one right now? A protected player (quarantine, spawn shield,
-- bubble) may still eat bots, so new players get an early "I ate someone!" moment.
-- Rookie guard: inside hosts a veteran (finished a run) can't eat or bite a rookie (first run).
local function spared(a, b)
	return a.mode == "host" and ((b.rookie and a.veteran) or (a.rookie and b.veteran)) or false
end
World.spared = spared

local function mayEat(eater, prey)
	if prey.npc or eater.npc and eater.npc.kind == "antibody" then
		return false
	end
	if prey.rookie and eater.veteran and prey.mode == "host" then
		return false
	end
	if World.isProtected(prey) then
		return false
	end
	if World.isProtected(eater) then
		return eater.player ~= nil and prey.bot ~= nil
	end
	return true
end
World.mayEat = mayEat

function World.isHidden(germ)
	local dish = germ.dish
	return dish ~= nil and dish.hidden[germ] == true
end

-- Eating and fighting ---------------------------------------------------------------------------

local function eatCell(eaterCell, preyCell)
	local eater, victim = eaterCell.germ, preyCell.germ
	local dish = eaterCell.dish
	local keep, burst = Formulas.eatSplit(preyCell.size)
	eaterCell.size += keep * (eater.stats.growthMult or 1)
	eaterCell.r = Formulas.radius(eaterCell.size, dish.scale)
	burstFood(dish, preyCell.x, preyCell.z, burst, preyCell.r + 4)
	local preySize = preyCell.size
	removeCell(preyCell, eaterCell)

	local feeds = eater.recentFeeds[victim.id]
	if feeds and now - feeds.time > Config.FeedWindowSeconds then
		feeds = nil
	end
	local revenge = eater.revengeOn == victim.id and now < (eater.revengeUntil or 0)
	local crowned = dish.crowned == victim
	local dna = Formulas.killDna(preySize, {
		scale = dish.scale,
		revenge = revenge,
		crowned = crowned,
		crownedSeconds = crowned and (now - (victim.crownedSince or now)) or 0,
		recentFeeds = feeds and feeds.count or 0,
		mult = (eater.stats.dnaMult or 1) * dish.effects.dnaMult,
	})
	World.hooks.gainDna(eater, dna)
	eater.shieldUntil = 0 -- attacking ends your spawn shield

	if next(victim.cells) == nil then
		victim.alive = false
		victim.sizeAtDeath = victim.peakSize or preySize
		victim.revengeOn = eater.id
		victim.revengeUntil = now + Config.RevengeSeconds
		eater.recentFeeds[victim.id] = { count = (feeds and feeds.count or 0) + 1, time = now }
		if dish.crowned == victim then
			dish.crowned = nil
		end
		World.hooks.ateGerm(eater, victim, { dna = dna, revenge = revenge, crowned = crowned })
		World.hooks.germDied(victim, eater)
	end
end

local function attackStats(germ, other)
	local s = germ.stats
	local mult = germ.dish.effects.damageMult
	if germ.bot and other.isNewPlayer then
		mult *= Config.Bots.NewPlayerDamageMult
	end
	local bite = s.bite
	if has(germ, "Chomp") then
		bite = (1 + bite) * 3 - 1
	end
	local thorns = s.thorns
	if s.fusions.Buzzsaw and now < germ.dashUntil then
		thorns *= 3
	end
	local pierce = s.pierce
	if has(germ, "Pierce") or (s.fusions.Driller and now < germ.dashUntil) then
		pierce = 1
	end
	return { bite = bite, thorns = thorns, mult = mult, pierce = pierce }
end

local function defenceArmor(germ)
	local armor = germ.stats.armor
	if next(germ.cells, next(germ.cells)) ~= nil then -- split into 2+ cells
		armor += germ.stats.splitArmor
	end
	return armor
end

local function poison(target, attacker)
	if attacker.stats.poison > 0 then
		target.poisonRate = math.max(target.poisonRate or 0, attacker.stats.poison)
		World.addEffect(target, "Poison", 3)
	end
end

local function fight(a, b, dt)
	local sa, sb = attackStats(a.germ, b.germ), attackStats(b.germ, a.germ)
	sa.size, sb.size = a.size, b.size
	local toB = Formulas.fightDamage(sa, { size = b.size, armor = defenceArmor(b.germ) }, dt)
	local toA = Formulas.fightDamage(sb, { size = a.size, armor = defenceArmor(a.germ) }, dt)
	a.size += toB * Config.FightStealShare - toA
	b.size += toA * Config.FightStealShare - toB
	a.fighting, b.fighting = true, true
	poison(b.germ, a.germ)
	poison(a.germ, b.germ)
end

-- Touching an immune boss: it drains you, you damage its health.
local function bossContact(bossCell, otherCell, dt)
	local boss, other = bossCell.germ, otherCell.germ
	local npc = boss.npc
	if npc.kind == "antibody" then
		-- (a shielded germ, e.g. just after a sneeze, may still eat them; it just can't be slowed)
		if not other.npc and not npc.popped then
			local A = Config.Immune.Antibodies
			if Formulas.canEat(otherCell.size, bossCell.size) then
				-- big enough: swallow it (a snack) instead of getting slowed
				otherCell.size += bossCell.size * A.EatShare
				otherCell.r = Formulas.radius(otherCell.size, otherCell.dish.scale)
				World.hooks.gainDna(other, A.Dna * A.EatDnaMult)
				otherCell.dish.eatenBy[tostring(bossCell.id)] = otherCell.id
			elseif not World.isProtected(other) then
				World.addEffect(other, "Slow", A.SlowSeconds)
				World.hooks.gainDna(other, A.Dna)
			else
				return -- shielded and too small: nothing happens
			end
			npc.popped = true
		end
		return
	end
	if other.npc then
		return
	end
	if Formulas.canEat(bossCell.size, otherCell.size) and not World.isProtected(other) then
		local dx, dz = otherCell.x - bossCell.x, otherCell.z - bossCell.z
		if Formulas.isSwallowed(math.sqrt(dx * dx + dz * dz), bossCell.r, otherCell.r) then
			eatCell(bossCell, otherCell)
			return
		end
	end
	if not World.isProtected(other) then
		local drain = otherCell.size * npc.drain * (1 - math.max(0, defenceArmor(other))) * dt
		otherCell.size -= drain
	end
	local s = attackStats(other, boss)
	local dmg = Formulas.bossDamage(otherCell.size, s.bite, dt) + otherCell.size * s.thorns * dt
	npc.hp -= dmg
	npc.damageBy[other] = (npc.damageBy[other] or 0) + dmg
	bossCell.fighting, otherCell.fighting = true, true
	World.hooks.bossHit(boss, other, dmg)
end

local function separate(a, b, dist, strength)
	local overlap = a.r + b.r - dist
	if overlap <= 0 then
		return
	end
	local dx, dz = b.x - a.x, b.z - a.z
	if dist < 0.001 then
		dx, dz, dist = 1, 0, 1
	end
	local push = overlap * strength / 2
	a.x -= dx / dist * push
	a.z -= dz / dist * push
	b.x += dx / dist * push
	b.z += dz / dist * push
end

local function interact(dish, dt)
	local list = {}
	for _, cell in dish.cells do
		cell.fighting = false
		table.insert(list, cell)
	end
	for i = 1, #list do
		local a = list[i]
		for j = i + 1, #list do
			local b = list[j]
			if cells[a.id] and cells[b.id] then
				local dx, dz = b.x - a.x, b.z - a.z
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist < a.r + b.r then
					local ga, gb = a.germ, b.germ
					if ga == gb then
						if now >= a.mergeAt and now >= b.mergeAt then
							if dist < math.max(a.r, b.r) then
								local big, small = a, b
								if b.size > a.size then
									big, small = b, a
								end
								big.size += small.size
								big.r = Formulas.radius(big.size, dish.scale)
								removeCell(small, big)
							end
						else
							separate(a, b, dist, 0.5)
						end
					elseif ga.npc or gb.npc then
						if ga.npc and not gb.npc then
							bossContact(a, b, dt)
						elseif gb.npc and not ga.npc then
							bossContact(b, a, dt)
						end
						if cells[a.id] and cells[b.id] then
							separate(a, b, dist, 0.15)
						end
					elseif Formulas.canEat(a.size, b.size, ga.stats.eatRatio) then
						if mayEat(ga, gb) and Formulas.isSwallowed(dist, a.r, b.r) then
							eatCell(a, b)
						elseif not mayEat(ga, gb) then
							separate(a, b, dist, 0.3)
						end
					elseif Formulas.canEat(b.size, a.size, gb.stats.eatRatio) then
						if mayEat(gb, ga) and Formulas.isSwallowed(dist, b.r, a.r) then
							eatCell(b, a)
						elseif not mayEat(gb, ga) then
							separate(a, b, dist, 0.3)
						end
					elseif not World.isProtected(ga) and not World.isProtected(gb) and not spared(ga, gb) then
						fight(a, b, dt)
						separate(a, b, dist, 0.3)
					else
						separate(a, b, dist, 0.3)
					end
				end
			end
		end
	end
end

local function eatFood(cell)
	local dish = cell.dish
	local germ = cell.germ
	if germ.npc then
		return
	end
	local reach = cell.r + (germ.stats.magnet or 0)
	if has(germ, "GravityWell") then
		reach += 25
	end
	local gx0, gx1 = cellOf(cell.x - reach), cellOf(cell.x + reach)
	local gz0, gz1 = cellOf(cell.z - reach), cellOf(cell.z + reach)
	local gained, dna, count, golden = 0, 0, 0, false
	for gx = gx0, gx1 do
		for gz = gz0, gz1 do
			local bucket = dish.foodGrid[gridKey(gx, gz)]
			if bucket then
				for _, pellet in bucket do
					local dx, dz = pellet.x - cell.x, pellet.z - cell.z
					-- a big crumb only goes down once the cell is big enough for it
					if dx * dx + dz * dz <= reach * reach and (not pellet.need or cell.size >= pellet.need) then
						gained += pellet.v
						dna += pellet.v / dish.scale * Config.DnaPerFood
						count += 1
						if pellet.golden then
							golden = true
						end
						removeFood(dish, pellet)
					end
				end
			end
		end
	end
	if gained > 0 then
		cell.size += gained * germ.stats.foodMult * dish.effects.foodMult
		cell.r = Formulas.radius(cell.size, dish.scale)
		germ.dnaPending = (germ.dnaPending or 0) + dna * germ.stats.dnaMult * dish.effects.dnaMult
		World.hooks.ateFood(germ, count, golden)
	end
end

-- Movement ----------------------------------------------------------------------------------------

local function moveCell(cell, dt)
	local germ = cell.germ
	local dish = cell.dish
	local total = World.germSize(germ)
	local speed
	if germ.npc then
		speed = germ.npc.speed
	else
		speed = Formulas.speed(cell.size, dish.scale, 1 + germ.stats.speed)
		if now < germ.dashUntil then
			speed *= Config.Dash.SpeedMult
		end
		if has(germ, "Slow") then
			speed *= Config.Immune.Antibodies.SlowMult
		end
		if germ.trailSlow then
			speed *= 1 - germ.trailSlow
		end
	end
	if germ.slowMult then
		speed *= germ.slowMult
	end
	local target = germ.target
	if target then
		local dx, dz = target.x - cell.x, target.z - cell.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 0.5 then
			local step = math.min(speed * dt, len) * math.min(1, len / (cell.r + 2))
			cell.x += dx / len * step
			cell.z += dz / len * step
		end
	end
	-- dish currents (drool, suction, magnet storm)
	local fx = dish.effects
	if fx.pushX ~= 0 or fx.pushZ ~= 0 then
		cell.x += fx.pushX * dt
		cell.z += fx.pushZ * dt
	end
	if fx.pull ~= 0 then
		local d = math.sqrt(cell.x * cell.x + cell.z * cell.z)
		if d > 1 then
			cell.x -= cell.x / d * fx.pull * dt
			cell.z -= cell.z / d * fx.pull * dt
		end
	end
	if cell.vx ~= 0 or cell.vz ~= 0 then
		cell.x += cell.vx * dt
		cell.z += cell.vz * dt
		local fade = math.exp(-5 * dt)
		cell.vx *= fade
		cell.vz *= fade
		if math.abs(cell.vx) + math.abs(cell.vz) < 0.5 then
			cell.vx, cell.vz = 0, 0
		end
	end
	-- stay inside the zones this germ may enter (NPCs keep to their own zones)
	local dist = math.sqrt(cell.x * cell.x + cell.z * cell.z)
	local sizeForZones = total
	if germ.npc then
		sizeForZones = dish.layout.sneeze -- may go anywhere
	end
	local allowed = Formulas.clampDistance(dist, sizeForZones, cell.r, dish.layout, dish.wall)
	if germ.npc and germ.npc.minDist then
		allowed = math.max(allowed, math.min(germ.npc.minDist, dish.wall - cell.r))
	end
	if math.abs(allowed - dist) > 0.001 then
		if dist < 0.001 then
			cell.x, cell.z = allowed, 0
		else
			local k = (dist + (allowed - dist) * math.min(1, dt * 10)) / dist
			cell.x *= k
			cell.z *= k
		end
	end
end

-- Snapshot ------------------------------------------------------------------------------------------

local FLAG_CROWN, FLAG_PROTECTED, FLAG_DASH, FLAG_FIGHT, FLAG_HIDDEN, FLAG_SLOW, FLAG_POISON = 1, 2, 4, 8, 16, 32, 64

local function sendSnapshot(dish)
	if next(dish.viewers) == nil then
		dish.info = { cells = {}, germs = {} }
		dish.infoDirty = false
		dish.cellsGone, dish.foodAdded, dish.foodRemoved = {}, {}, {}
		dish.eatenBy = {}
		return
	end
	local count = 0
	for _ in dish.cells do
		count += 1
	end
	local buf = buffer.create(8 + count * 17)
	buffer.writef32(buf, 0, now)
	buffer.writeu32(buf, 4, dish.id)
	local offset = 8
	for id, cell in dish.cells do
		local germ = cell.germ
		local flags = 0
		if dish.crowned == germ then
			flags += FLAG_CROWN
		end
		if World.isProtected(germ) then
			flags += FLAG_PROTECTED
		end
		if now < germ.dashUntil then
			flags += FLAG_DASH
		end
		if cell.fighting then
			flags += FLAG_FIGHT
		end
		if dish.hidden[germ] then
			flags += FLAG_HIDDEN
		end
		if has(germ, "Slow") then
			flags += FLAG_SLOW
		end
		if has(germ, "Poison") then
			flags += FLAG_POISON
		end
		buffer.writeu32(buf, offset, id)
		buffer.writef32(buf, offset + 4, cell.x + dish.cx)
		buffer.writef32(buf, offset + 8, cell.z + dish.cz)
		buffer.writef32(buf, offset + 12, cell.size / dish.scale)
		buffer.writeu8(buf, offset + 16, flags)
		offset += 17
	end
	if dish.infoDirty then
		fireDish(dish, Net.CellInfo, World.wireInfo(dish.info))
		dish.info = { cells = {}, germs = {} }
		dish.infoDirty = false
	end
	if #dish.cellsGone > 0 then
		fireDish(dish, Net.CellGone, dish.cellsGone, dish.eatenBy)
		dish.cellsGone = {}
		dish.eatenBy = {}
	end
	if #dish.foodAdded > 0 or #dish.foodRemoved > 0 then
		fireDish(dish, Net.FoodDelta, dish.foodAdded, dish.foodRemoved)
		dish.foodAdded, dish.foodRemoved = {}, {}
	end
	fireDish(dish, Net.Snapshot, buf)
end

-- Remotes lose tables with gaps in their number keys, so ids travel as string keys.
function World.wireInfo(info)
	local out = { cells = {}, germs = {} }
	for id, germId in info.cells do
		out.cells[tostring(id)] = germId
	end
	for id, g in info.germs do
		out.germs[tostring(id)] = g
	end
	return out
end

-- Everything a player needs to draw a dish (on joining it).
function World.fullState(dish)
	local info = { cells = {}, germs = {} }
	for _, cell in dish.cells do
		info.germs[cell.germ.id] = World.germInfo(cell.germ)
		info.cells[cell.id] = cell.germ.id
	end
	return World.wireInfo(info), World.foodList(dish)
end

-- The tick -------------------------------------------------------------------------------------------

local function stepDish(dish, dt)
	dish.tick += 1
	local layout = dish.layout
	World.hooks.dishTick(dish, dt)

	-- the outer wall moves smoothly (Medicine drop, Arena sudden death)
	if dish.wall ~= dish.wallTarget then
		local d = dish.wallTarget - dish.wall
		local step = math.max(2, math.abs(d)) * dt * 0.6
		if math.abs(d) <= step then
			dish.wall = dish.wallTarget
		else
			dish.wall += step * math.sign(d)
		end
	end

	-- slime trails: germs right behind a slimy germ are slowed
	for _, cell in dish.cells do
		cell.germ.trailSlow = nil
	end
	for _, cell in dish.cells do
		local s = cell.germ.stats
		if s and s.trail > 0 then
			for _, other in dish.cells do
				if other.germ ~= cell.germ and not other.germ.npc then
					local dx, dz = other.x - cell.x, other.z - cell.z
					if dx * dx + dz * dz < (cell.r * 3) ^ 2 then
						other.germ.trailSlow = math.max(other.germ.trailSlow or 0, s.trail)
						if s.fusions.PlagueTrail then
							other.germ.poisonRate = math.max(other.germ.poisonRate or 0, 0.01)
							World.addEffect(other.germ, "Poison", 2)
						end
					end
				end
			end
		end
	end

	-- vacuum / gravity well pull smaller germs in
	for _, cell in dish.cells do
		local germ = cell.germ
		if not germ.npc and (has(germ, "Vacuum") or has(germ, "GravityWell")) then
			for _, other in dish.cells do
				if other.germ ~= germ and not other.germ.npc and other.size < cell.size then
					local dx, dz = cell.x - other.x, cell.z - other.z
					local d = math.sqrt(dx * dx + dz * dz)
					if d < cell.r * 6 + 20 and d > 0.1 then
						other.x += dx / d * 18 * dt
						other.z += dz / d * 18 * dt
					end
				end
			end
		end
	end

	local hidden = {}
	for _, germ in World.dishGerms(dish) do
		local inside = false
		for _, cell in germ.cells do
			moveCell(cell, dt)
			if inBubble(cell) then
				inside = true
			end
			if not germ.npc then
				local decay = Formulas.decay(cell.size, dt, layout)
				if decay > 0 then
					cell.size -= decay
				end
				-- poison, burning outer ring, Arena spikes
				if has(germ, "Poison") then
					cell.size -= cell.size * (germ.poisonRate or 0) * dt
				end
				local dist = math.sqrt(cell.x * cell.x + cell.z * cell.z)
				if dish.effects.burnFrom and dist > dish.effects.burnFrom and not World.isProtected(germ) then
					cell.size -= cell.size * dish.effects.burnRate * dt
				end
				for _, spike in dish.spikes do
					local dx, dz = cell.x - spike.x, cell.z - spike.z
					if dx * dx + dz * dz < (spike.r + cell.r) ^ 2 then
						cell.size -= cell.size * 0.05 * dt
					end
				end
				-- ink clouds hide germs; camo hides still germs
				for _, cloud in dish.ink do
					local dx, dz = cell.x - cloud.x, cell.z - cloud.z
					if dx * dx + dz * dz < cloud.r * cloud.r then
						hidden[germ] = true
					end
				end
			end
		end
		if germ.stats and germ.stats.camo and germ.target then
			local cx, cz = World.germCentre(germ)
			local dx, dz = germ.target.x - cx, germ.target.z - cz
			if dx * dx + dz * dz < 4 then
				germ.stillSince = germ.stillSince or now
				if now - germ.stillSince > 1.5 then
					hidden[germ] = true
				end
			else
				germ.stillSince = nil
			end
		end
		if has(germ, "Ghost") then
			hidden[germ] = true
		end
		germ.inBubble = inside
		if inside then
			germ.bubbleTime += dt
		end
	end
	dish.hidden = hidden

	-- warp holes
	for _, cell in dish.cells do
		local germ = cell.germ
		if not germ.npc and now >= (germ.warpReady or 0) then
			for _, hole in dish.warps do
				local dx, dz = cell.x - hole.x, cell.z - hole.z
				if dx * dx + dz * dz < hole.r * hole.r then
					local to = dish.warps[hole.to]
					for _, c in germ.cells do
						c.x, c.z = to.x + (c.x - cell.x), to.z + (c.z - cell.z)
					end
					germ.warpReady = now + Config.Hazards.Warp.Cooldown
					break
				end
			end
		end
	end

	interact(dish, dt)

	for _, cell in dish.cells do
		eatFood(cell)
		local min = Config.MinSize * dish.scale
		if cell.size < min and not cell.germ.npc then
			cell.size = min
		end
	end

	-- size caps (players must sneeze; bots stay below the sneeze size)
	local nerveR = Config.NerveRadius
	for _, germ in World.dishGerms(dish) do
		if not germ.npc then
			local cap = layout.sneeze * Config.MaxSizeShare
			if germ.bot and not germ.bot.uncapped then
				cap = layout.sneeze * Config.Bots.MaxSizeShare
			end
			local size = World.germSize(germ)
			if size > cap then
				World.setGermSize(germ, cap)
				size = cap
			end
			germ.peakSize = size
			if germ.dnaPending and germ.dnaPending >= 1 then
				local whole = math.floor(germ.dnaPending)
				germ.dnaPending -= whole
				World.hooks.gainDna(germ, whole)
			end
			-- the Sneeze Nerve
			if size >= layout.sneeze and not germ.bot then
				for _, cell in germ.cells do
					if cell.x * cell.x + cell.z * cell.z < (nerveR + cell.r) ^ 2 then
						World.hooks.sneeze(germ)
						break
					end
				end
			end
		else
			-- antibodies pop after touching someone, bosses die at 0 health
			if germ.npc.popped then
				World.removeGerm(germ)
			elseif germ.npc.hp and germ.npc.hp <= 0 then
				local damageBy = germ.npc.damageBy
				World.removeGerm(germ)
				World.hooks.bossDefeated(germ, damageBy)
			end
		end
	end
	for _, cell in dish.cells do
		cell.r = Formulas.radius(cell.size, dish.scale)
	end

	-- the crown goes to the biggest germ (players and bots)
	if dish.tick % Config.TickRate == 0 then
		local best, bestSize = nil, 0
		for _, germ in World.dishGerms(dish) do
			if not germ.npc then
				local size = World.germSize(germ)
				if size > bestSize then
					best, bestSize = germ, size
				end
			end
		end
		if best ~= dish.crowned then
			dish.crowned = best
			if best then
				best.crownedSince = now
			end
		end
	end

	World.refillFood(dish)

	if dish.tick % Config.SnapshotEvery == 0 then
		sendSnapshot(dish)
	end
end

function World.step(dt)
	now += dt
	for _, dish in dishes do
		stepDish(dish, dt)
	end
end

function World.start()
	local RunService = game:GetService("RunService")
	local step = 1 / Config.TickRate
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += math.min(dt, 0.25)
		while acc >= step do
			acc -= step
			local ok, err = pcall(World.step, step)
			if not ok then
				warn("[World] " .. tostring(err))
			end
		end
	end)
end

return World
