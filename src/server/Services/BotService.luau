-- Bot germs keep every server busy while the game is new. They use the same moves and rules
-- as players. They are never added to the Roblox player list or player count: they only exist
-- as germs in the dish (and on the in-game size board).
--
-- Behaviours:
--   Wanderer - grazes on food, runs from bigger germs
--   Hunter   - chases smaller germs, gives up after a few seconds
--   Coward   - runs early and dashes away
--   Bully    - big and slow, goes for the crowned germ
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Names = require(ReplicatedStorage.Shared.Names)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Flags = require(ReplicatedStorage.Shared.Flags)
local World = require(script.Parent.World)

local BotService = {}

local B = Config.Bots
local bots = {} -- [germ] = brain
local pending = {} -- [dish] = bots waiting to respawn
local usedNames = {}
BotService.playerCount = function(dish)
	return 0
end -- set by Main (DishService.playerCount)

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

local function pickSize(dish)
	if dish.kind == "arena" then
		return Config.Arena.StartSize * (1 + math.random() * 1.5)
	end
	local roll = math.random()
	for _, band in B.SizeMix do
		roll -= band[1]
		if roll <= 0 then
			return math.random(band[2], band[3]) * dish.scale
		end
	end
	return Config.StartSize * dish.scale
end

local function pick(list)
	return list[math.random(1, #list)]
end

-- Bots dress like players: random colours, some paid-looking items, sometimes a flag
local function randomSkin()
	local s = Config.Skins
	local function any(cat, chance)
		if math.random() < chance then
			return pick(s[cat]).Id
		end
		return s[cat][1].Id
	end
	local c = Config.GermColors[math.random(1, #Config.GermColors)]
	local skin = {
		Body = any("Body", 0.4), Pattern = any("Pattern", 0.4), Eyes = any("Eyes", 0.5), Mouth = any("Mouth", 0.5),
		Hat = any("Hat", 0.25), Trail = any("Trail", 0.15), SneezeFx = "Classic", Flag = "",
		Color = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) }, Color2 = { 255, 255, 255 },
	}
	if skin.Body == "Champion" then
		skin.Body = "Jelly"
	end
	if skin.Hat == "Laurel" then
		skin.Hat = "None"
	end
	if skin.Trail == "ArenaFlame" or skin.Trail == "ArenaLightning" then
		skin.Trail = "None"
	end
	if math.random() < 0.12 then
		skin.Flag = pick(Flags.List).Code
	end
	return skin
end

local function randomBuild(dish)
	local equipped, levels = {}, {}
	local hostLevel = dish.host or 3
	for _, id in Config.MutationOrder do
		local m = Config.Mutations[id]
		if not equipped[m.Slot] and math.random() < 0.3 then
			equipped[m.Slot] = id
			levels[id] = math.random(1, math.min(Config.MaxMutationLevel, 1 + hostLevel))
		end
	end
	local build = { equipped = equipped, levels = levels, core = (dish.host and Config.Hosts[dish.host].Core) or "Blob", sneezes = math.max(0, (dish.host or 1) - 1) }
	if dish.kind == "arena" then
		build.arena = true
		build.floor = dish.floor
		build.levelCap = Formulas.arenaLevelCap(dish.floor)
	end
	return build
end

function BotService.spawnBot(dish)
	local size = pickSize(dish)
	local behaviour = BEHAVIOURS[math.random(1, #BEHAVIOURS)]
	if dish.kind == "host" and size >= 400 * dish.scale then
		behaviour = "Bully"
	end
	local build = randomBuild(dish)
	local skin = randomSkin()
	local germ = World.newGerm({
		name = pickName(),
		color = Color3.fromRGB(skin.Color[1], skin.Color[2], skin.Color[3]),
		equipped = build.equipped,
		skin = skin,
		core = build.core,
		stats = Stats.compute(build),
	})
	local brain = { behaviour = behaviour, nextThink = 0, huntStart = 0, restUntil = 0, wanderAt = 0, dish = dish }
	germ.bot = brain
	if behaviour == "Bully" then
		germ.slowMult = 0.85
	end
	bots[germ] = brain
	World.spawnGerm(germ, dish, size)
	return germ
end

local function removeBot(germ, pop)
	if not bots[germ] then
		return
	end
	bots[germ] = nil
	usedNames[germ.name] = nil
	if pop and germ.alive then
		World.popGerm(germ)
	else
		World.removeGerm(germ)
	end
end

local function botsIn(dish)
	local list = {}
	for germ, brain in bots do
		if brain.dish == dish then
			table.insert(list, germ)
		end
	end
	return list
end

local function wanted(dish)
	if dish.kind == "arena" and dish.floor > Config.Arena.BotFloors then
		return 0
	end
	return math.max(0, B.TargetGerms - BotService.playerCount(dish))
end

-- Called when a bot germ is fully eaten
function BotService.onBotDied(germ)
	local dish = germ.bot.dish
	removeBot(germ, false)
	pending[dish] = (pending[dish] or 0) + 1
	task.delay(B.RespawnMin + math.random() * (B.RespawnMax - B.RespawnMin), function()
		pending[dish] = math.max(0, (pending[dish] or 0) - 1)
		if World.dish(dish.id) and #botsIn(dish) < wanted(dish) then
			BotService.spawnBot(dish)
		end
	end)
end

function BotService.dishRemoved(dish)
	for _, germ in botsIn(dish) do
		bots[germ] = nil
		usedNames[germ.name] = nil
	end
	pending[dish] = nil
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
	for _, other in World.dishGerms(germ.dish) do
		local antibody = other.npc and other.npc.kind == "antibody"
		if other ~= germ and not antibody then
			for _, cell in other.cells do
				local dx, dz = cell.x - cx, cell.z - cz
				local d = math.sqrt(dx * dx + dz * dz)
				if d < view then
					if other.npc and (Formulas.canEat(cell.size, smallest) or d - cell.r < 20) then
						if d - cell.r < threatD then
							threat, threatD, threatR = cell, d - cell.r, cell.r
						end
					elseif other.npc then
						-- bosses are not prey
					elseif Formulas.canEat(cell.size, smallest) and World.mayEat(other, germ) then
						if d - cell.r < threatD then
							threat, threatD, threatR = cell, d - cell.r, cell.r
						end
					elseif Formulas.canEat(biggest, cell.size) and World.mayEat(germ, other) then
						local skip = other.player and other.isNewPlayer
						local bonus = 1
						if brain.behaviour == "Bully" and germ.dish.crowned == other then
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
	local pellet = World.nearestFood(germ.dish, cx, cz, 64, mySize)
	if pellet then
		germ.target = { x = pellet.x, z = pellet.z }
		return
	end
	if now >= brain.wanderAt then
		local x, z = World.randomInZone(germ.dish, math.random(Formulas.shallowestZone(mySize, germ.dish.layout), Formulas.deepestZone(mySize, germ.dish.layout)), 10)
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

	-- keep every dish at the target number of germs
	task.spawn(function()
		while true do
			for _, dish in World.dishes() do
				local mine = botsIn(dish)
				local want = wanted(dish)
				if #mine + (pending[dish] or 0) < want then
					BotService.spawnBot(dish)
				elseif #mine > want then
					-- make room for a real player: pop the smallest bot
					local smallest, size = nil, math.huge
					for _, germ in mine do
						local s = World.germSize(germ)
						if s < size then
							smallest, size = germ, s
						end
					end
					if smallest then
						removeBot(smallest, true)
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

BotService.think = think -- used by tools/sim-server.js

function BotService.isBot(germ)
	return bots[germ] ~= nil
end

return BotService
