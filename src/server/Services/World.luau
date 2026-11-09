-- The simulation of the host's insides: germs (players and bots), their cells, food,
-- eating, same-size fights, dashing, splitting and the crown. The server owns all of it;
-- clients only send where they steer and draw the snapshots.
--
-- A "germ" is one player or bot. A germ has 1-2 "cells" (2 after a split).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Net = require(script.Parent.Net)

local World = {}

local HOST = Formulas.host()
local SCALE = HOST.Scale

local germs = {} -- [germId] = germ
local cells = {} -- [cellId] = cell
local food = {} -- [foodId] = pellet
local foodGrid = {} -- [gridKey] = { [foodId] = pellet }
local zoneFoodCount = {}
local nextId = 0
local now = 0 -- simulation clock in seconds

-- Changes collected during a tick, sent with the next snapshot
local foodAdded = {} -- flat list: id, x, z, value, golden(0/1), ...
local foodRemoved = {}
local cellsGone = {}
local infoQueue = { cells = {}, germs = {} }
local infoDirty = false

-- Hooks the other services fill in
World.hooks = {
	gainDna = function(germ, amount) end,
	germDied = function(victim, eater) end, -- every cell of a germ was swallowed
	ateGerm = function(eater, victim, info) end, -- info = { dna, revenge, crowned }
}

World.crowned = nil -- the biggest germ right now
World.bubbles = {} -- spawn bubble centres { x, z }

local function newId()
	nextId += 1
	return nextId
end

function World.now()
	return now
end

-- Food -------------------------------------------------------------------------------

local G = Config.GridCell
local function gridKey(gx, gz)
	return gx * 100000 + gz
end
local function cellOf(v)
	return math.floor(v / G)
end

local function addFood(x, z, value, zone, golden)
	local id = newId()
	local pellet = { id = id, x = x, z = z, v = value, zone = zone, golden = golden }
	food[id] = pellet
	local key = gridKey(cellOf(x), cellOf(z))
	local bucket = foodGrid[key]
	if not bucket then
		bucket = {}
		foodGrid[key] = bucket
	end
	bucket[id] = pellet
	pellet.key = key
	if zone then
		zoneFoodCount[zone] = (zoneFoodCount[zone] or 0) + 1
	end
	table.insert(foodAdded, id)
	table.insert(foodAdded, math.floor(x * 10) / 10)
	table.insert(foodAdded, math.floor(z * 10) / 10)
	table.insert(foodAdded, value)
	table.insert(foodAdded, golden and 1 or 0)
	return pellet
end

local function removeFood(pellet)
	food[pellet.id] = nil
	local bucket = foodGrid[pellet.key]
	if bucket then
		bucket[pellet.id] = nil
	end
	if pellet.zone then
		zoneFoodCount[pellet.zone] -= 1
	end
	table.insert(foodRemoved, pellet.id)
end

-- A random point in a zone's ring
local function randomInZone(zone, margin)
	local zones = Config.Zones
	local outer = zones[zone].Outer - (margin or 4)
	local inner = 0
	if zones[zone + 1] then
		inner = zones[zone + 1].Outer + (margin or 4)
	end
	local angle = math.random() * math.pi * 2
	local dist = math.sqrt(math.random() * (outer * outer - inner * inner) + inner * inner)
	return math.cos(angle) * dist, math.sin(angle) * dist
end
World.randomInZone = randomInZone

local function refillFood()
	for zone, info in Config.Zones do
		local missing = info.FoodCount - (zoneFoodCount[zone] or 0)
		for _ = 1, math.min(missing, 6) do
			local x, z = randomInZone(zone)
			addFood(x, z, info.FoodValue * SCALE, zone, false)
		end
	end
end

local function burstFood(x, z, total, spread)
	local count = Config.BurstPellets
	local each = total / count
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.5
		local d = spread * (0.6 + math.random() * 0.8)
		local px, pz = x + math.cos(angle) * d, z + math.sin(angle) * d
		local dist = math.sqrt(px * px + pz * pz)
		if dist > Config.ArenaRadius - 3 then
			local k = (Config.ArenaRadius - 3) / dist
			px, pz = px * k, pz * k
		end
		addFood(px, pz, each, nil, false)
	end
end

function World.spawnGolden()
	local zone = math.random(1, math.min(3, #Config.Zones))
	local x, z = randomInZone(zone, 20)
	addFood(x, z, Config.GoldenShare * HOST.SneezeSize, nil, true)
	return Config.Zones[zone].Name
end

-- The closest pellet within a few grid squares that a germ of this size may reach
-- (bots use this to graze).
function World.nearestFood(x, z, reach, size)
	local minDist, maxDist = 0, math.huge
	if size then
		minDist, maxDist = Formulas.allowedRange(size)
	end
	local cx, cz = cellOf(x), cellOf(z)
	local n = math.max(1, math.ceil((reach or G) / G))
	local best, bestD = nil, math.huge
	for gx = cx - n, cx + n do
		for gz = cz - n, cz + n do
			local bucket = foodGrid[gridKey(gx, gz)]
			if bucket then
				for _, pellet in bucket do
					local dx, dz = pellet.x - x, pellet.z - z
					local d = dx * dx + dz * dz
					local fromCentre = pellet.x * pellet.x + pellet.z * pellet.z
					if fromCentre < minDist * minDist or fromCentre > maxDist * maxDist then
						d = math.huge -- in a zone this germ may not enter
					end
					if pellet.golden then
						d *= 0.1 -- bots love golden food too
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

function World.foodList()
	local list = {}
	for id, p in food do
		table.insert(list, id)
		table.insert(list, math.floor(p.x * 10) / 10)
		table.insert(list, math.floor(p.z * 10) / 10)
		table.insert(list, p.v)
		table.insert(list, p.golden and 1 or 0)
	end
	return list
end

-- Germs and cells ------------------------------------------------------------------

local function queueInfo(germ)
	infoQueue.germs[germ.id] = World.germInfo(germ)
	for _, cell in germ.cells do
		infoQueue.cells[cell.id] = germ.id
	end
	infoDirty = true
end

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
	}
end

function World.refreshInfo(germ)
	queueInfo(germ)
end

-- Recalculates bite / armour / thorns / speed from the equipped mutations.
function World.applyMutations(germ)
	local stats = { bite = 0, thorns = 0, armor = 0, speed = 0 }
	for _, id in germ.equipped do
		local m = Config.Mutations[id]
		if m then
			stats.bite += m.Bite or 0
			stats.thorns += m.Thorns or 0
			stats.armor += m.Armor or 0
			stats.speed += m.Speed or 0
		end
	end
	germ.stats = stats
	queueInfo(germ)
end

-- germ fields set by the caller: name, color, player or bot, equipped
function World.newGerm(fields)
	local germ = fields
	germ.id = newId()
	germ.cells = {}
	germ.alive = false
	germ.equipped = germ.equipped or {}
	germ.recentFeeds = {} -- [victimGermId] = { count, time }
	germ.dashUntil = 0
	germ.dashReadyAt = 0
	germ.splitReadyAt = 0
	germ.shieldUntil = 0
	germ.bubbleTime = 0
	germ.quarantineUntil = germ.quarantineUntil or 0
	germ.target = nil -- { x, z } world point the germ steers to
	germs[germ.id] = germ
	World.applyMutations(germ)
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

-- The middle of all of a germ's cells, weighted by size.
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
	local cell = {
		id = newId(),
		germ = germ,
		x = x,
		z = z,
		vx = 0,
		vz = 0,
		size = size,
		r = Formulas.radius(size, SCALE),
		mergeAt = 0,
	}
	cells[cell.id] = cell
	germ.cells[cell.id] = cell
	return cell
end

local function removeCell(cell)
	cells[cell.id] = nil
	cell.germ.cells[cell.id] = nil
	table.insert(cellsGone, cell.id)
end

-- A spawn point for a germ of this size: a spawn bubble in zone 1, otherwise a quiet spot
-- in the deepest zone it may enter.
function World.spawnPoint(size)
	local zone = Formulas.deepestZone(size)
	if zone == 1 and #World.bubbles > 0 then
		local b = World.bubbles[math.random(1, #World.bubbles)]
		local a = math.random() * math.pi * 2
		local d = math.random() * (Config.SpawnBubbleRadius * 0.5)
		return b.x + math.cos(a) * d, b.z + math.sin(a) * d
	end
	-- try a few spots, keep the one farthest from anything that could eat us
	local bestX, bestZ, bestScore = 0, 0, -1
	for _ = 1, 8 do
		local x, z = randomInZone(zone, 10)
		local score = math.huge
		for _, other in cells do
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

function World.spawnGerm(germ, size)
	for _, cell in germ.cells do
		removeCell(cell)
	end
	local x, z = World.spawnPoint(size)
	addCell(germ, size, x, z)
	germ.alive = true
	germ.target = { x = x, z = z }
	germ.shieldUntil = now + Config.SpawnShieldSeconds
	germ.bubbleTime = 0
	germ.spawnedAt = now
	queueInfo(germ)
end

-- Removes a germ by popping it into food (used when a bot makes room for a real player).
function World.popGerm(germ)
	for _, cell in germ.cells do
		burstFood(cell.x, cell.z, cell.size * 0.5, cell.r + 3)
	end
	World.removeGerm(germ)
end

function World.removeGerm(germ)
	for _, cell in germ.cells do
		removeCell(cell)
	end
	germ.alive = false
	germs[germ.id] = nil
	if World.crowned == germ then
		World.crowned = nil
	end
end

-- Moves ---------------------------------------------------------------------------------

function World.dash(germ)
	if not germ.alive or now < germ.dashReadyAt then
		return false
	end
	local d = Config.Dash
	if World.germSize(germ) < d.MinSize then
		return false
	end
	for _, cell in germ.cells do
		cell.size -= cell.size * d.CostShare
	end
	germ.dashUntil = now + d.Duration
	germ.dashReadyAt = now + d.Cooldown
	return true
end

function World.split(germ)
	local s = Config.Split
	if not germ.alive or now < germ.splitReadyAt then
		return false
	end
	local count, biggest = 0, nil
	for _, cell in germ.cells do
		count += 1
		if not biggest or cell.size > biggest.size then
			biggest = cell
		end
	end
	if count >= s.MaxCells or not biggest or biggest.size < s.MinSize then
		return false
	end
	local half = biggest.size / 2
	biggest.size = half
	biggest.r = Formulas.radius(half, SCALE)
	local dx, dz = 1, 0
	if germ.target then
		dx, dz = germ.target.x - biggest.x, germ.target.z - biggest.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 0.01 then
			dx, dz = 1, 0
		else
			dx, dz = dx / len, dz / len
		end
	end
	local new = addCell(germ, half, biggest.x + dx * biggest.r, biggest.z + dz * biggest.r)
	new.vx, new.vz = dx * s.LaunchSpeed, dz * s.LaunchSpeed
	new.mergeAt = now + s.MergeSeconds
	biggest.mergeAt = now + s.MergeSeconds
	germ.splitReadyAt = now + s.Cooldown
	queueInfo(germ)
	return true
end

-- Protection --------------------------------------------------------------------------

local function inBubble(cell)
	for _, b in World.bubbles do
		local dx, dz = cell.x - b.x, cell.z - b.z
		if dx * dx + dz * dz <= Config.SpawnBubbleRadius * Config.SpawnBubbleRadius then
			return true
		end
	end
	return false
end

-- Germs that cannot eat other germs or be eaten right now.
function World.isProtected(germ)
	if now < germ.quarantineUntil or now < germ.shieldUntil then
		return true
	end
	return germ.inBubble == true and germ.bubbleTime < Config.SpawnBubbleSeconds
end

-- May this germ swallow that one right now? Protected germs cannot be eaten. A protected
-- player (quarantine, spawn shield, bubble) may still eat bots, so new players get their
-- first "I ate someone!" moment early, but cannot eat other players yet.
local function mayEat(eater, prey)
	if World.isProtected(prey) then
		return false
	end
	if World.isProtected(eater) then
		return eater.player ~= nil and prey.bot ~= nil
	end
	return true
end
World.mayEat = mayEat

-- Eating and fighting -----------------------------------------------------------------

local function eatCell(eaterCell, preyCell)
	local eater, victim = eaterCell.germ, preyCell.germ
	local keep, burst = Formulas.eatSplit(preyCell.size)
	eaterCell.size += keep
	eaterCell.r = Formulas.radius(eaterCell.size, SCALE)
	burstFood(preyCell.x, preyCell.z, burst, preyCell.r + 4)
	local preySize = preyCell.size
	removeCell(preyCell)

	-- rewards
	local feeds = eater.recentFeeds[victim.id]
	if feeds and now - feeds.time > Config.FeedWindowSeconds then
		feeds = nil
	end
	local revenge = eater.revengeOn == victim.id and now < (eater.revengeUntil or 0)
	local crowned = World.crowned == victim
	local dna = Formulas.killDna(preySize, {
		revenge = revenge,
		crowned = crowned,
		crownedSeconds = crowned and (now - (victim.crownedSince or now)) or 0,
		recentFeeds = feeds and feeds.count or 0,
	})
	World.hooks.gainDna(eater, dna)
	eater.shieldUntil = 0 -- attacking ends your spawn shield

	if next(victim.cells) == nil then
		victim.alive = false
		victim.sizeAtDeath = (victim.peakSize or preySize)
		victim.revengeOn = eater.id
		victim.revengeUntil = now + Config.RevengeSeconds
		eater.recentFeeds[victim.id] = { count = (feeds and feeds.count or 0) + 1, time = now }
		if World.crowned == victim then
			World.crowned = nil
		end
		World.hooks.ateGerm(eater, victim, { dna = dna, revenge = revenge, crowned = crowned })
		World.hooks.germDied(victim, eater)
	end
end

local function fightStats(germ, otherGerm)
	local mult = 1
	if germ.bot and otherGerm.isNewPlayer then
		mult = Config.Bots.NewPlayerDamageMult
	end
	return germ.stats.bite, germ.stats.thorns, germ.stats.armor, mult
end

local function fight(a, b, dt)
	local biteA, thornsA, armorA, multA = fightStats(a.germ, b.germ)
	local biteB, thornsB, armorB, multB = fightStats(b.germ, a.germ)
	local toB = Formulas.fightDamage(
		{ size = a.size, bite = biteA, thorns = thornsA, mult = multA },
		{ size = b.size, armor = armorB },
		dt
	)
	local toA = Formulas.fightDamage(
		{ size = b.size, bite = biteB, thorns = thornsB, mult = multB },
		{ size = a.size, armor = armorA },
		dt
	)
	a.size += toB * Config.FightStealShare - toA
	b.size += toA * Config.FightStealShare - toB
	a.fighting, b.fighting = true, true
end

-- Pushes two overlapping cells apart a little so they do not sit inside each other.
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

local function interact(dt)
	local list = {}
	for _, cell in cells do
		cell.fighting = false
		table.insert(list, cell)
	end
	for i = 1, #list do
		local a = list[i]
		if cells[a.id] then
			for j = i + 1, #list do
				local b = list[j]
				if cells[b.id] and cells[a.id] then
					local dx, dz = b.x - a.x, b.z - a.z
					local dist = math.sqrt(dx * dx + dz * dz)
					if dist < a.r + b.r then
						if a.germ == b.germ then
							if now >= a.mergeAt and now >= b.mergeAt then
								if dist < math.max(a.r, b.r) then
									local big, small = a, b
									if b.size > a.size then
										big, small = b, a
									end
									big.size += small.size
									big.r = Formulas.radius(big.size, SCALE)
									removeCell(small)
								end
							else
								separate(a, b, dist, 0.5)
							end
						elseif Formulas.canEat(a.size, b.size) then
							if mayEat(a.germ, b.germ) and Formulas.isSwallowed(dist, a.r, b.r) then
								eatCell(a, b)
							elseif not mayEat(a.germ, b.germ) then
								separate(a, b, dist, 0.3)
							end
						elseif Formulas.canEat(b.size, a.size) then
							if mayEat(b.germ, a.germ) and Formulas.isSwallowed(dist, b.r, a.r) then
								eatCell(b, a)
							elseif not mayEat(b.germ, a.germ) then
								separate(a, b, dist, 0.3)
							end
						elseif not World.isProtected(a.germ) and not World.isProtected(b.germ) then
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
end

local function eatFood(cell)
	local r = cell.r
	local gx0, gx1 = cellOf(cell.x - r), cellOf(cell.x + r)
	local gz0, gz1 = cellOf(cell.z - r), cellOf(cell.z + r)
	local gained, dna = 0, 0
	for gx = gx0, gx1 do
		for gz = gz0, gz1 do
			local bucket = foodGrid[gridKey(gx, gz)]
			if bucket then
				for _, pellet in bucket do
					local dx, dz = pellet.x - cell.x, pellet.z - cell.z
					if dx * dx + dz * dz <= r * r then
						gained += pellet.v
						dna += pellet.v / SCALE * Config.DnaPerFood
						if pellet.golden then
							cell.germ.ateGolden = true
						end
						removeFood(pellet)
					end
				end
			end
		end
	end
	if gained > 0 then
		cell.size += gained
		cell.r = Formulas.radius(cell.size, SCALE)
		cell.germ.dnaPending = (cell.germ.dnaPending or 0) + dna
	end
end

-- Movement ---------------------------------------------------------------------------------

local function moveCell(cell, dt)
	local germ = cell.germ
	local total = World.germSize(germ)
	local speed = Formulas.speed(cell.size, SCALE, 1 + germ.stats.speed)
	if now < germ.dashUntil then
		speed *= Config.Dash.SpeedMult
	end
	if germ.slowMult then
		speed *= germ.slowMult
	end
	local target = germ.target
	if target then
		local dx, dz = target.x - cell.x, target.z - cell.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 0.5 then
			-- slow down near the target so the germ does not jitter around the mouse
			local step = math.min(speed * dt, len) * math.min(1, len / (cell.r + 2))
			cell.x += dx / len * step
			cell.z += dz / len * step
		end
	end
	-- launch speed after a split fades out quickly
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
	-- stay inside the zones this germ may enter
	local dist = math.sqrt(cell.x * cell.x + cell.z * cell.z)
	local allowed = Formulas.clampDistance(dist, total, cell.r)
	if math.abs(allowed - dist) > 0.001 then
		if dist < 0.001 then
			cell.x, cell.z = allowed, 0
		else
			-- move part of the way each tick so being coughed out looks smooth
			local k = (dist + (allowed - dist) * math.min(1, dt * 10)) / dist
			cell.x *= k
			cell.z *= k
		end
	end
end

-- Snapshot -----------------------------------------------------------------------------

local FLAG_CROWN, FLAG_PROTECTED, FLAG_DASH, FLAG_FIGHT = 1, 2, 4, 8

local function sendSnapshot()
	local count = 0
	for _ in cells do
		count += 1
	end
	local buf = buffer.create(4 + count * 17)
	buffer.writef32(buf, 0, now)
	local offset = 4
	for id, cell in cells do
		local germ = cell.germ
		local flags = 0
		if World.crowned == germ then
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
		buffer.writeu32(buf, offset, id)
		buffer.writef32(buf, offset + 4, cell.x)
		buffer.writef32(buf, offset + 8, cell.z)
		buffer.writef32(buf, offset + 12, cell.size)
		buffer.writeu8(buf, offset + 16, flags)
		offset += 17
	end
	if infoDirty then
		Net.CellInfo:FireAllClients(infoQueue)
		infoQueue = { cells = {}, germs = {} }
		infoDirty = false
	end
	if #cellsGone > 0 then
		Net.CellGone:FireAllClients(cellsGone)
		cellsGone = {}
	end
	if #foodAdded > 0 or #foodRemoved > 0 then
		Net.FoodDelta:FireAllClients(foodAdded, foodRemoved)
		foodAdded, foodRemoved = {}, {}
	end
	Net.Snapshot:FireAllClients(buf)
end

-- Everything a player who just joined needs to draw the world.
function World.fullState()
	local info = { cells = {}, germs = {} }
	for _, germ in germs do
		info.germs[germ.id] = World.germInfo(germ)
		for _, cell in germ.cells do
			info.cells[cell.id] = germ.id
		end
	end
	return info, World.foodList()
end

-- The tick ------------------------------------------------------------------------------

local tickCount = 0
local crownTimer = 0

function World.step(dt)
	now += dt
	tickCount += 1

	for _, germ in germs do
		if germ.alive then
			local inside = false
			for _, cell in germ.cells do
				moveCell(cell, dt)
				if inBubble(cell) then
					inside = true
				end
				local decay = Formulas.decay(cell.size, dt)
				if decay > 0 then
					cell.size -= decay
				end
			end
			germ.inBubble = inside
			if inside then
				germ.bubbleTime += dt
			end
		end
	end

	interact(dt)

	for _, cell in cells do
		eatFood(cell)
		if cell.size < Config.MinSize then
			cell.size = Config.MinSize
		end
	end

	-- size caps (no sneeze in Phase 1; bots stay below the sneeze size)
	for _, germ in germs do
		if germ.alive then
			local cap = HOST.SneezeSize * Config.MaxSizeShare
			if germ.bot and not germ.bot.uncapped then
				cap = HOST.SneezeSize * Config.Bots.MaxSizeShare
			end
			local size = World.germSize(germ)
			if size > cap then
				local k = cap / size
				for _, cell in germ.cells do
					cell.size *= k
				end
			end
		end
	end
	for _, cell in cells do
		cell.r = Formulas.radius(cell.size, SCALE)
	end

	for _, germ in germs do
		if germ.alive then
			local size = World.germSize(germ)
			germ.peakSize = size
			if germ.dnaPending and germ.dnaPending >= 1 then
				local whole = math.floor(germ.dnaPending)
				germ.dnaPending -= whole
				World.hooks.gainDna(germ, whole)
			end
		end
	end

	-- the crown goes to the biggest germ
	crownTimer += dt
	if crownTimer >= 1 then
		crownTimer = 0
		local best, bestSize = nil, 0
		for _, germ in germs do
			if germ.alive then
				local size = World.germSize(germ)
				if size > bestSize then
					best, bestSize = germ, size
				end
			end
		end
		if best ~= World.crowned then
			World.crowned = best
			if best then
				best.crownedSince = now
			end
		end
	end

	refillFood()

	if tickCount % Config.SnapshotEvery == 0 then
		sendSnapshot()
	end
end

function World.start()
	-- six spawn bubbles around the outer ring
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		local d = Config.ArenaRadius - Config.SpawnBubbleRadius - 30
		table.insert(World.bubbles, { x = math.cos(a) * d, z = math.sin(a) * d })
	end
	for _ = 1, 100 do
		refillFood()
	end
	foodAdded, foodRemoved = {}, {}

	local RunService = game:GetService("RunService")
	local step = 1 / Config.TickRate
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += math.min(dt, 0.25)
		while acc >= step do
			acc -= step
			World.step(step)
		end
	end)
end

return World
