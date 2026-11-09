-- The Infinite Petri: the endless PvP Arena, unlocked at Mutant I (finish all 6 hosts once).
--
-- Everyone starts every floor at the same size. Reach the goal size and touch the Exit Pore in
-- the middle to clear the floor and go down to the next one. Being eaten sends you back to
-- your last checkpoint (every 10 floors). Floors roll modifiers; every few minutes a floor goes
-- into sudden death and its wall closes in. Bots fill floors 1-9 only.
-- Paid boosts do not work here and Arena cosmetics are earned with Arena Tokens, never sold.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local World = require(script.Parent.World)
local DishService = require(script.Parent.DishService)
local PlayerService = require(script.Parent.PlayerService)
local Bus = require(script.Parent.Bus)

local ArenaService = {}
local A = Config.Arena

local SUDDEN_DEATH_SECONDS = 60

ArenaService.isDev = function(player)
	return false
end

local function rollModifiers(floor)
	if floor < 3 then
		return {} -- the first floors are plain so new Arena players learn it
	end
	local pool = table.clone(A.ModifierOrder)
	local mods = {}
	for _ = 1, Formulas.arenaModifierCount(floor) do
		if #pool == 0 then
			break
		end
		table.insert(mods, table.remove(pool, math.random(1, #pool)))
	end
	return mods
end

local function hasMod(dish, id)
	return dish.modifiers ~= nil and table.find(dish.modifiers, id) ~= nil
end

local function applyModifiers(dish)
	dish.round = { endsAt = World.now() + A.FloorSeconds, sudden = false }
	if hasMod(dish, "LowGravity") then
		dish.effects.lowGravity = true
	end
	if hasMod(dish, "Fever") then
		dish.effects.foodMult, dish.effects.damageMult = 2, 1.5
	end
	if hasMod(dish, "SpikeField") then
		for _ = 1, 8 do
			local x, z = World.randomInZone(dish, 1, 20)
			table.insert(dish.spikes, { x = x, z = z, r = 8 })
		end
	end
	if hasMod(dish, "MagnetStorm") then
		dish.effects.pull, dish.effects.basePull = 6, 6
	end
	if hasMod(dish, "GiantWhitey") then
		dish.giantWhitey = true
		dish.timers.whiteyAt = World.now() + 20
	end
end

function ArenaService.unlocked(player)
	local data = DataService.get(player)
	return data ~= nil and (data.Mutant >= A.UnlockMutant or ArenaService.isDev(player))
end

local function seasonCheck(data)
	local season = Formulas.season(os.time())
	if data.ArenaSeason ~= season then
		data.ArenaSeason = season
		data.ArenaBest = 0
		data.ArenaFloor = 1
	end
end

-- Puts a player on an Arena floor
function ArenaService.toFloor(player, floor)
	local germ = PlayerService.germ(player)
	local data = DataService.get(player)
	if not germ or not data then
		return
	end
	germ.mode = "arena"
	germ.arenaFloor = floor
	germ.advancing = false
	germ.mirrored = false
	germ.quarantineUntil = 0
	PlayerService.refresh(player)
	local dish = DishService.arenaDish(floor)
	DishService.enter(germ, dish, A.StartSize)
	if hasMod(dish, "CloneParty") then
		germ.splitReadyAt = 0
		World.split(germ)
	end
	PlayerService.sync(player)
end

local actions = {}

function actions.Enter(player, data)
	if not ArenaService.unlocked(player) then
		return false, "Finish all 6 hosts (Mutant I) to unlock The Infinite Petri"
	end
	seasonCheck(data)
	ArenaService.toFloor(player, math.max(1, data.ArenaFloor))
	return true, "Welcome to The Infinite Petri! Reach size " .. A.GoalSize .. " and touch the Exit Pore"
end

function actions.Leave(player, data)
	local germ = PlayerService.germ(player)
	if not germ or germ.mode ~= "arena" then
		return false, "You're not in the Arena"
	end
	PlayerService.goHost(player)
	return true, "Back to " .. Config.Hosts[data.Host].Name
end

function actions.Buy(player, data, index)
	local item = type(index) == "number" and A.TokenShop[index]
	if not item then
		return false, "Unknown item"
	end
	local key = item.Kind .. ":" .. item.Id
	if data.OwnedSkins[key] then
		return false, "You own it already"
	end
	if data.Tokens < item.Cost then
		return false, "You need " .. item.Cost .. " Arena Tokens"
	end
	data.Tokens -= item.Cost
	data.OwnedSkins[key] = true
	data.Skin[item.Kind] = item.Id
	PlayerService.refresh(player)
	return true, "Unlocked! Equipped in the Germ Editor"
end

local function onGoal(player, germ)
	local data = DataService.get(player)
	if not data or germ.advancing then
		return
	end
	germ.advancing = true
	local cleared = germ.arenaFloor or 1
	local nextFloor = cleared + 1
	local oldRank = Formulas.arenaRank(cleared)
	data.Tokens += A.TokensPerFloor
	data.ArenaBest = math.max(data.ArenaBest, cleared)
	data.ArenaBestEver = math.max(data.ArenaBestEver, cleared)
	data.ArenaFloor = math.max(data.ArenaFloor, Formulas.arenaCheckpoint(nextFloor))
	World.despawn(germ)
	local rank = Formulas.arenaRank(nextFloor)
	local text = "Floor " .. cleared .. " cleared! +" .. A.TokensPerFloor .. " Arena Tokens"
	if rank ~= oldRank then
		text = text .. ". New rank: " .. rank .. "!"
	end
	Net.notify(player, text, "success")
	if cleared % A.ChampionEvery == 0 then
		Net.Announce:FireAllClients("🏆 " .. player.DisplayName .. " cleared Floor " .. cleared .. " of The Infinite Petri!")
	end
	Bus.fire("ArenaFloor", player, cleared)
	task.delay(1.5, function()
		if PlayerService.germ(player) == germ and germ.mode == "arena" and player.Parent then
			ArenaService.toFloor(player, nextFloor)
		end
	end)
end

local function onDied(player, germ, eater)
	local data = DataService.get(player)
	local floor = germ.arenaFloor or 1
	local back = Formulas.arenaCheckpoint(floor)
	Net.Died:FireClient(player, eater and eater.name or "?", Config.RespawnSeconds, false, back)
	task.delay(Config.RespawnSeconds, function()
		if PlayerService.germ(player) == germ and germ.mode == "arena" and player.Parent and not germ.alive then
			ArenaService.toFloor(player, back)
		end
	end)
	local _ = data
end

function ArenaService.start()
	DishService.rollModifiers = rollModifiers
	DishService.hooks.created = function(dish)
		if dish.kind == "arena" then
			applyModifiers(dish)
		end
	end
	PlayerService.hooks.arenaGoal = onGoal
	PlayerService.hooks.arenaDied = onDied
	PlayerService.hooks.profileExtra = function(player, profile)
		local season, left = Formulas.season(os.time())
		profile.Season = season
		profile.SeasonLeft = left
		profile.ArenaUnlocked = ArenaService.unlocked(player)
		profile.Rank = Formulas.arenaRank(math.max(1, profile.ArenaBest or 1))
	end

	Bus.on("AteGerm", function(player, victim)
		local germ = PlayerService.germ(player)
		local data = DataService.get(player)
		if germ and data and germ.mode == "arena" and not victim.npc then
			data.Tokens += A.TokensPerKill
		end
	end)

	Net.Arena.OnServerInvoke = function(player, action, arg)
		local data = DataService.get(player)
		local fn = type(action) == "string" and actions[action]
		if not data or not fn then
			return false, "Not ready"
		end
		local ok, message = fn(player, data, arg)
		PlayerService.markProfile(player)
		return ok, message
	end

	DishService.onSecond(function(dish, now)
		if dish.kind ~= "arena" or not dish.round then
			return
		end
		local r = dish.round
		-- sudden death: the wall closes in, then the floor starts a new round
		if not r.sudden and now >= r.endsAt then
			r.sudden = true
			r.endsAt = now + SUDDEN_DEATH_SECONDS
			dish.wallTarget = dish.layout.radius * A.SuddenDeathShrink
			World.fireDish(dish, Net.DishFx, "Medicine", { wall = dish.wallTarget, duration = SUDDEN_DEATH_SECONDS })
			World.fireDish(dish, Net.Announce, "☠️ SUDDEN DEATH! The dish is shrinking")
		elseif r.sudden and now >= r.endsAt then
			r.sudden = false
			r.endsAt = now + A.FloorSeconds
			dish.wallTarget = dish.layout.radius
			World.fireDish(dish, Net.DishFx, "MedicineEnd", { wall = dish.wallTarget })
		end
		if math.floor(now) % 2 == 0 then
			World.fireDish(dish, Net.DishFx, "ArenaTimer", { left = math.max(0, r.endsAt - now), sudden = r.sudden })
		end
		if hasMod(dish, "GoldenRain") then
			dish.timers.rain = dish.timers.rain or now
			if now >= dish.timers.rain then
				dish.timers.rain = now + 10
				World.spawnGolden(dish)
			end
		end
		if hasMod(dish, "Mirror") then
			local phase = (now - dish.openedAt) % 30
			local on = phase >= 25
			for _, germ in World.dishGerms(dish) do
				if germ.player and germ.mirrored ~= on then
					germ.mirrored = on
					Net.DishFx:FireClient(germ.player, "Mirror", { on = on })
				end
			end
		end
	end)
end

return ArenaService
