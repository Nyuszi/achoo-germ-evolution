-- Bot germs keep every server busy while the game is new. They use the same moves and rules
-- as players. They are never added to the Roblox player list or player count: they only exist
-- as germs in the dish (and on the in-game size board).
--
-- Behaviours:
--   Wanderer - grazes on food, runs from bigger germs
--   Hunter   - chases smaller germs, gives up after a few seconds
--   Coward   - runs early and dashes away
--   Bully    - big and slow, goes for the crowned germ
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Names = require(ReplicatedStorage.Shared.Names)
local World = require(script.Parent.World)

local BotService = {}

local B = Config.Bots
local bots = {} -- [germ] = brain
local botCount = 0
local pendingSpawns = 0
local usedNames = {}

local BEHAVIOURS = { "Wanderer", "Wanderer", "Hunter", "Coward", "Wanderer", "Hunter" }

local function pickName()
	for _ = 1, 20 do
		local name = Names[math.random(1, #Names)]
		if not usedNames[name] then
			usedNames[name] = true
			return name
		end
	end
	return "Germ" .. math.random(100, 999)
end

local function pickSize()
	local roll = math.random()
	for _, band in B.SizeMix do
		roll -= band[1]
		if roll <= 0 then
			return math.random(band[2], band[3]) * Formulas.host().Scale
		end
	end
	return Config.StartSize * Formulas.host().Scale
end

local function randomMutations()
	local equipped = {}
	for _, id in Config.MutationOrder do
		local m = Config.Mutations[id]
		if not equipped[m.Slot] and math.random() < 0.3 then
			equipped[m.Slot] = id
		end
	end
	return equipped
end

function BotService.spawnBot()
	local size = pickSize()
	local behaviour = BEHAVIOURS[math.random(1, #BEHAVIOURS)]
	if size >= 400 * Formulas.host().Scale then
		behaviour = "Bully"
	end
	local germ = World.newGerm({
		name = pickName(),
		color = Config.GermColors[math.random(1, #Config.GermColors)],
		equipped = randomMutations(),
	})
	local brain = { behaviour = behaviour, nextThink = 0, huntStart = 0, restUntil = 0, wanderAt = 0 }
	germ.bot = brain
	if behaviour == "Bully" then
		germ.slowMult = 0.85
	end
	bots[germ] = brain
	botCount += 1
	World.spawnGerm(germ, size)
	return germ
end

local function removeBot(germ, pop)
	if not bots[germ] then
		return
	end
	bots[germ] = nil
	botCount -= 1
	usedNames[germ.name] = nil
	if pop then
		World.popGerm(germ)
	else
		World.removeGerm(germ)
	end
end

local function wanted()
	return math.max(0, B.TargetGerms - #Players:GetPlayers())
end

-- Called when a bot germ is fully eaten
function BotService.onBotDied(germ)
	removeBot(germ, false)
	pendingSpawns += 1
	task.delay(B.RespawnMin + math.random() * (B.RespawnMax - B.RespawnMin), function()
		pendingSpawns -= 1
		if botCount < wanted() then
			BotService.spawnBot()
		end
	end)
end

local function steerAway(germ, cx, cz, fromX, fromZ, distance)
	local dx, dz = cx - fromX, cz - fromZ
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.01 then
		dx, dz, len = 1, 0, 1
	end
	-- also lean toward the middle of the allowed ring so bots do not get stuck on the wall
	germ.target = { x = cx + dx / len * distance, z = cz + dz / len * distance }
end

local function think(germ, brain)
	local now = World.now()
	local cx, cz = World.germCentre(germ)
	local mySize = World.germSize(germ)
	local smallest, biggest = math.huge, 0
	local myR = 0
	for _, cell in germ.cells do
		smallest = math.min(smallest, cell.size)
		if cell.size > biggest then
			biggest = cell.size
			myR = cell.r
		end
	end
	local view = 40 + myR * 6

	local threat, threatD, threatR = nil, math.huge, 0
	local prey, preyD = nil, math.huge
	for _, other in World.allGerms() do
		if other ~= germ and other.alive then
			for _, cell in other.cells do
				local dx, dz = cell.x - cx, cell.z - cz
				local d = math.sqrt(dx * dx + dz * dz)
				if d < view then
					if Formulas.canEat(cell.size, smallest) and World.mayEat(other, germ) then
						if d - cell.r < threatD then
							threat, threatD, threatR = cell, d - cell.r, cell.r
						end
					elseif Formulas.canEat(biggest, cell.size) and World.mayEat(germ, other) then
						local skip = other.player and other.isNewPlayer
						local bonus = 1
						if brain.behaviour == "Bully" and World.crowned == other then
							bonus = 0.2
						end
						if not skip and d * bonus < preyD then
							prey, preyD = cell, d * bonus
						end
					end
				end
			end
		end
	end

	-- 1. run from danger
	local fleeAt = threatR + 25
	if brain.behaviour == "Coward" then
		fleeAt = view
	elseif brain.behaviour == "Bully" then
		fleeAt = threatR + 10
	end
	if threat and threatD < fleeAt then
		steerAway(germ, cx, cz, threat.x, threat.z, 80)
		if threatD < 12 and math.random() < 0.3 then
			World.dash(germ)
		end
		brain.huntStart = 0
		return
	end

	-- 2. hunt
	local hunts = brain.behaviour == "Hunter" or brain.behaviour == "Bully"
	if hunts and prey and now >= brain.restUntil then
		if brain.huntStart == 0 then
			brain.huntStart = now
		end
		if now - brain.huntStart > B.HunterGiveUp then
			brain.huntStart = 0
			brain.restUntil = now + 4
		else
			germ.target = { x = prey.x, z = prey.z }
			if preyD < myR * 2 + 6 and math.random() < 0.2 then
				World.dash(germ)
			end
			if brain.behaviour == "Hunter" and mySize >= prey.size * Config.EatRatio * 2.1 and preyD < myR * 3 and math.random() < 0.1 then
				World.split(germ)
			end
			return
		end
	end
	brain.huntStart = 0

	-- 3. graze
	local pellet = World.nearestFood(cx, cz, 64, mySize)
	if pellet then
		germ.target = { x = pellet.x, z = pellet.z }
		return
	end
	if now >= brain.wanderAt then
		local x, z = World.randomInZone(math.random(Formulas.shallowestZone(mySize), Formulas.deepestZone(mySize)), 10)
		germ.target = { x = x, z = z }
		brain.wanderAt = now + 4 + math.random() * 4
	end
end

function BotService.start()
	task.spawn(function()
		while true do
			task.wait(B.ThinkSeconds)
			for germ, brain in bots do
				if germ.alive then
					local ok, err = pcall(think, germ, brain)
					if not ok then
						warn("[Bots] " .. tostring(err))
					end
				end
			end
		end
	end)

	-- keep the dish at the target number of germs
	task.spawn(function()
		while true do
			local want = wanted()
			if botCount + pendingSpawns < want then
				BotService.spawnBot()
			elseif botCount > want then
				-- make room for a real player: pop the smallest bot nobody is chasing
				local smallest, size = nil, math.huge
				for germ in bots do
					local s = World.germSize(germ)
					if s < size then
						smallest, size = germ, s
					end
				end
				if smallest then
					removeBot(smallest, true)
				end
			end
			task.wait(1)
		end
	end)
end

BotService.think = think -- used by tools/sim-server.js

function BotService.isBot(germ)
	return bots[germ] ~= nil
end

return BotService
