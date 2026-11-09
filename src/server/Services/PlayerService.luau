-- Turns each player into a germ: loading, putting them in their host, steering, moves, DNA,
-- respawning after being eaten, sneezing into the next host, and the numbers the HUD shows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local World = require(script.Parent.World)
local DishService = require(script.Parent.DishService)
local BotService = require(script.Parent.BotService)
local Bus = require(script.Parent.Bus)

local PlayerService = {}

local germOf = {} -- [player] = germ
local profileDirty = {} -- [player] = true when the menus need fresh data

-- set by other services (avoids require loops)
PlayerService.ownsPass = function(player, passId)
	return false
end
PlayerService.isDev = function(player)
	return RunService:IsStudio()
end
PlayerService.hooks = {
	arenaDied = function(player, germ, eater) end,
	arenaGoal = function(player, germ) end,
	profileExtra = function(player, profile) end,
}

function PlayerService.germ(player)
	return germOf[player]
end

function PlayerService.players()
	return germOf
end

function PlayerService.markProfile(player)
	profileDirty[player] = true
end

local function leaderstats(player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, name in { "Size", "DNA", "Sneezes" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = folder
	end
	folder.Parent = player
end

local function setStat(player, name, value)
	local folder = player:FindFirstChild("leaderstats")
	local stat = folder and folder:FindFirstChild(name)
	if stat then
		stat.Value = math.floor(math.min(value, 2 ^ 31 - 1))
	end
end

-- Stats --------------------------------------------------------------------------------------

function PlayerService.passes(player)
	local passes = {}
	for id in Config.GamePasses do
		if PlayerService.ownsPass(player, id) then
			passes[id] = true
		end
	end
	return passes
end

function PlayerService.build(player)
	local data = DataService.get(player)
	local germ = germOf[player]
	local build = {
		equipped = data.Equipped,
		levels = data.Levels,
		core = data.Core,
		skills = data.Skills,
		passes = PlayerService.passes(player),
		sneezes = data.Sneezes,
		mutant = data.Mutant,
		potion = (data.PotionUntil or 0) > os.time(),
		host = data.Host,
	}
	if germ and germ.mode == "arena" then
		build.arena = true
		build.floor = germ.arenaFloor or 1
		build.levelCap = Formulas.arenaLevelCap(build.floor)
	end
	return build
end

-- Recomputes a player's numbers and look (after buying, equipping, entering the Arena...)
function PlayerService.refresh(player)
	local germ = germOf[player]
	local data = DataService.get(player)
	if not germ or not data then
		return
	end
	local c = data.Skin.Color or { 120, 220, 120 }
	germ.color = Color3.fromRGB(c[1], c[2], c[3])
	germ.skin = data.Skin
	germ.core = data.Core
	germ.equipped = table.clone(data.Equipped)
	germ.vip = PlayerService.ownsPass(player, "VIP")
	germ.mutant = data.Mutant
	-- fair play: rookies (first run) and veterans (finished a run), see Config.RookieGuard
	germ.rookie = Config.RookieGuard and data.Mutant == 0 or nil
	germ.veteran = data.Mutant >= 1
	germ.potionOn = (data.PotionUntil or 0) > os.time()
	World.setStats(germ, Stats.compute(PlayerService.build(player)))
	PlayerService.sendProfile(player)
end

-- The size you start a host with
function PlayerService.startSize(player, host)
	local germ = germOf[player]
	local scale = Config.Hosts[host].Scale
	local mult = germ and germ.stats and germ.stats.startMult or 1
	return Config.StartSize * scale * mult
end

-- Puts the player in their current host
function PlayerService.goHost(player, size)
	local germ = germOf[player]
	local data = DataService.get(player)
	if not germ or not data then
		return
	end
	germ.mode = "host"
	germ.arenaFloor = nil
	germ.bestZone = 1
	germ.mirrored = false
	PlayerService.refresh(player)
	local dish = DishService.hostDish(data.Host)
	DishService.enter(germ, dish, size or PlayerService.startSize(player, data.Host))
	Bus.fire("EnteredHost", player, data.Host)
end

-- HUD -------------------------------------------------------------------------------------------

function PlayerService.sync(player)
	local germ = germOf[player]
	local data = DataService.get(player)
	if not germ or not data or not germ.dish then
		return
	end
	local dish = germ.dish
	local layout = dish.layout
	local now = World.now()
	local size = World.germSize(germ)
	if not germ.alive then
		size = germ.sizeAtDeath or 0
	end
	local cx, cz = World.germCentre(germ)
	local zone = Formulas.zoneAt(math.sqrt(cx * cx + cz * cz), layout)
	local nextZone = Formulas.deepestZone(size, layout) + 1
	local gate
	if dish.kind == "host" and layout.zones[nextZone] then
		gate = { name = Config.Hosts[dish.host].Zones[nextZone], size = Formulas.zoneMinSize(nextZone, layout) }
	elseif dish.kind == "host" then
		gate = { name = "Sneeze", size = layout.sneeze }
	else
		gate = { name = "Exit", size = layout.sneeze }
	end
	local actives = {}
	for slot, a in germ.stats.actives do
		actives[slot] = { id = a.id, readyIn = math.max(0, (germ.abilityReady[slot] or 0) - now) }
	end
	Net.Sync:FireClient(player, {
		germId = germ.id,
		alive = germ.alive,
		mode = germ.mode,
		size = size,
		best = data.BestSize,
		dna = data.Dna,
		dnaCap = Formulas.hostLimits(data.Host).dnaCap,
		zone = zone,
		zoneName = dish.kind == "host" and Config.Hosts[dish.host].Zones[zone] or ("Floor " .. dish.floor),
		hostName = dish.kind == "host" and Config.Hosts[dish.host].Name or "The Infinite Petri",
		host = dish.host,
		floor = germ.arenaFloor,
		nextGate = gate,
		sneezeSize = layout.sneeze,
		quarantine = math.max(0, germ.quarantineUntil - now),
		protected = World.isProtected(germ),
		dashIn = math.max(0, germ.dashReadyAt - now),
		splitIn = math.max(0, germ.splitReadyAt - now),
		actives = actives,
		crowned = dish.crowned == germ,
		kills = data.Kills,
		gp = data.GermPoints,
		tokens = data.Tokens,
		mutant = data.Mutant,
		sneezes = data.Sneezes,
		potion = math.max(0, (data.PotionUntil or 0) - os.time()),
		canRevive = germ.reviveSize ~= nil and now < (germ.reviveUntil or 0),
		radar = PlayerService.radar(player, germ),
	})
end

-- Germ Radar pass: the 3 nearest germs (world positions), whether you can eat them or they you.
-- Hosts only (no paid help in the Arena); hidden germs never show up.
function PlayerService.radar(player, germ)
	if germ.mode ~= "host" or not germ.alive or not PlayerService.ownsPass(player, "Radar") then
		return nil
	end
	local dish = germ.dish
	local cx, cz = World.germCentre(germ)
	local mine = World.germSize(germ)
	local list = {}
	for _, other in World.dishGerms(dish) do
		if other ~= germ and not other.npc and not World.isHidden(other) then
			local ox, oz = World.germCentre(other)
			local d = math.sqrt((ox - cx) ^ 2 + (oz - cz) ^ 2)
			if d < Config.RadarRange then
				local size = World.germSize(other)
				local kind = "fight"
				if Formulas.canEat(mine, size, germ.stats.eatRatio) then
					kind = "prey"
				elseif Formulas.canEat(size, mine, other.stats.eatRatio) then
					kind = "danger"
				end
				table.insert(list, { x = ox + dish.cx, z = oz + dish.cz, d = d, kind = kind })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	while #list > 3 do
		table.remove(list)
	end
	return list
end

-- Everything the menus show (Lab, Editor, Shop, Quests, Arena)
function PlayerService.sendProfile(player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local profile = {
		Dna = data.Dna, Levels = data.Levels, Fusions = data.Fusions, Equipped = data.Equipped, Loadouts = data.Loadouts,
		Core = data.Core, MaxHost = data.MaxHost, Host = data.Host, Skills = data.Skills, GermPoints = data.GermPoints,
		Skin = data.Skin, OwnedSkins = data.OwnedSkins, Flags = data.Flags, Outfits = data.Outfits,
		Passes = PlayerService.passes(player), Potions = data.Potions, PotionUntil = data.PotionUntil,
		Quests = data.Quests, Streak = data.Streak, Cards = data.Cards, CardSetsClaimed = data.CardSetsClaimed,
		ArenaBest = data.ArenaBest, ArenaBestEver = data.ArenaBestEver, ArenaFloor = data.ArenaFloor, Tokens = data.Tokens,
		Mutant = data.Mutant, Sneezes = data.Sneezes, Kills = data.Kills, BestSize = data.BestSize,
		IsDev = PlayerService.isDev(player), Studio = RunService:IsStudio(),
		Strain = data.Strain, Strains = PlayerService.strainList(player), BestRun = data.BestRun,
		RunSeconds = data.RunSeconds, RunValid = data.RunValid, StrainRuns = data.StrainRuns,
	}
	PlayerService.hooks.profileExtra(player, profile)
	Net.Profile:FireClient(player, profile)
	profileDirty[player] = nil
end

-- Strains (New Run) ---------------------------------------------------------------------------------

local STRAIN_KEYS = { "Levels", "Fusions", "Equipped", "Loadouts", "Core", "Host", "RunSeconds", "RunValid", "StrainRuns" }
local switchedAt = {} -- [player] = World.now() of the last New Run / switch

local function storeStrain(data)
	local snap = { Name = Config.StrainNames[data.Strain] or ("Strain " .. data.Strain) }
	for _, k in STRAIN_KEYS do
		snap[k] = DataService.copy(data[k])
	end
	for i = 1, data.Strain - 1 do
		if data.Strains[i] == nil then
			data.Strains[i] = false -- no holes, so it saves
		end
	end
	data.Strains[data.Strain] = snap
end

local function countLevels(levels)
	local n = 0
	for _, l in levels do
		n += l
	end
	return n
end

-- A short summary of every slot for the Lab
function PlayerService.strainList(player)
	local data = DataService.get(player)
	local list = {}
	for i = 1, Config.StrainSlots do
		local src = (i == data.Strain) and data or data.Strains[i]
		if type(src) == "table" then
			local muts = {}
			for _, slot in Config.Slots do
				local id = src.Equipped[slot]
				if id and Config.Mutations[id] then
					table.insert(muts, Config.Mutations[id].Name)
				elseif id and Config.Fusions[id] then
					table.insert(muts, Config.Fusions[id].Name)
				end
			end
			list[i] = {
				name = Config.StrainNames[i] or ("Strain " .. i),
				host = src.Host,
				hostName = Config.Hosts[src.Host] and Config.Hosts[src.Host].Name or "?",
				core = src.Core,
				muts = table.concat(muts, ", "),
				levels = countLevels(src.Levels),
				runs = src.StrainRuns or 0,
				active = i == data.Strain,
			}
		else
			list[i] = false
		end
	end
	return list
end

-- Start a fresh strain in a slot (fresh = true) or go back to a saved one.
-- "sure" must be true when it would wipe a saved strain.
function PlayerService.switchStrain(player, slot, fresh, sure)
	local data = DataService.get(player)
	local germ = germOf[player]
	if not data or not germ then
		return false, "Not ready"
	end
	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > Config.StrainSlots then
		return false, "Pick a slot"
	end
	if germ.mode ~= "host" then
		return false, "Leave the Arena first"
	end
	if germ.sneezing then
		return false, "Wait for the sneeze to finish"
	end
	local wait = Config.StrainSwitchCooldown - (World.now() - (switchedAt[player] or -math.huge))
	if wait > 0 then
		return false, "Wait " .. math.ceil(wait) .. " s"
	end
	local saved = slot ~= data.Strain and data.Strains[slot]
	if fresh then
		local wipes = slot == data.Strain or type(saved) == "table"
		if wipes and sure ~= true then
			return false, "That slot has a strain. Tap again to replace it"
		end
	elseif slot == data.Strain then
		return false, "You're already playing this strain"
	elseif type(saved) ~= "table" then
		return false, "That slot is empty: start a New Run there"
	end
	if not (fresh and slot == data.Strain) then
		storeStrain(data)
	end
	if fresh then
		data.Levels, data.Fusions, data.Equipped, data.Loadouts = {}, {}, {}, {}
		data.Core = "Blob"
		data.Host = 1
		data.RunSeconds = 0
		data.RunValid = true
		data.StrainRuns = 0
	else
		for _, k in STRAIN_KEYS do
			if saved[k] ~= nil then
				data[k] = DataService.copy(saved[k])
			end
		end
	end
	data.Strain = slot
	data.Strains[slot] = nil
	storeStrain(data)
	switchedAt[player] = World.now()
	World.despawn(germ)
	PlayerService.goHost(player)
	PlayerService.sync(player)
	local name = Config.StrainNames[slot] or ("Strain " .. slot)
	if fresh then
		return true, "🧫 New Run! " .. name .. " starts fresh in " .. Config.Hosts[1].Name .. ". The run timer is on ⏱️"
	end
	return true, "Switched to " .. name .. " (" .. Config.Hosts[data.Host].Name .. ")"
end

-- Joining and leaving -----------------------------------------------------------------------

local function onJoin(player)
	leaderstats(player)
	local data = DataService.load(player)
	if not player.Parent then
		return
	end
	local played = data.TotalPlaySeconds or 0
	local c = data.Skin.Color
	local germ = World.newGerm({
		name = player.DisplayName,
		color = Color3.fromRGB(c[1], c[2], c[3]),
		player = player,
		equipped = table.clone(data.Equipped),
		quarantineUntil = World.now() + math.max(0, Config.QuarantineMinutes * 60 - played),
	})
	germ.isNewPlayer = played < Config.Bots.NewPlayerMinutes * 60
	germOf[player] = germ
	if played == 0 then
		-- a first random colour so not everyone is green
		local pick = Config.GermColors[math.random(1, #Config.GermColors)]
		data.Skin.Color = { math.floor(pick.R * 255), math.floor(pick.G * 255), math.floor(pick.B * 255) }
	end
	PlayerService.goHost(player)
	PlayerService.sync(player)
	PlayerService.sendProfile(player)
	Bus.fire("Joined", player)
	if germ.quarantineUntil > World.now() then
		Net.notify(player, "Welcome! You're in Quarantine for a few minutes: nobody can eat you yet 🛡️ Eat food and smaller germs to grow!", "info")
	end
end

local function onLeave(player)
	local germ = germOf[player]
	if germ then
		DishService.leave(germ)
		germOf[player] = nil
	end
	profileDirty[player] = nil
	switchedAt[player] = nil
	DataService.release(player)
end

-- Remotes ----------------------------------------------------------------------------------------

local function onSteer(player, x, z)
	local germ = germOf[player]
	if not germ or not germ.dish or type(x) ~= "number" or type(z) ~= "number" then
		return
	end
	if x ~= x or z ~= z then -- NaN
		return
	end
	local dish = germ.dish
	local limit = dish.layout.radius * 1.3
	x, z = x - dish.cx, z - dish.cz
	germ.target = { x = math.clamp(x, -limit, limit), z = math.clamp(z, -limit, limit) }
end

local function onAction(player, action)
	local germ = germOf[player]
	if not germ then
		return
	end
	if action == "Dash" then
		if World.dash(germ) then
			Bus.fire("Dash", player)
		end
	elseif action == "Split" then
		World.split(germ)
	elseif action == "Front" or action == "Special" then
		World.ability(germ, action)
	elseif action == "Revive" then
		-- handled by ShopService (it is a paid product)
	end
end

-- Sneezing ------------------------------------------------------------------------------------------

local function sneeze(germ)
	local player = germ.player
	local data = player and DataService.get(player)
	if not data or germ.sneezing then
		return
	end
	germ.sneezing = true
	local dish = germ.dish
	local from = data.Host
	data.Sneezes += 1
	data.GermPoints += 1
	local mutantUp = false
	local runTime, runRecord = nil, false
	if from >= #Config.Hosts then
		data.Mutant += 1
		data.Host = 1
		mutantUp = true
		-- a whole run done: time it, then the next run starts now
		data.StrainRuns = (data.StrainRuns or 0) + 1
		if data.RunValid then
			runTime = data.RunSeconds
			if data.BestRun == 0 or runTime < data.BestRun then
				data.BestRun = runTime
				runRecord = true
			end
		end
		data.RunSeconds = 0
		data.RunValid = true
	else
		data.Host = from + 1
	end
	data.MaxHost = math.max(data.MaxHost, data.Host)
	local bonus = 100 * from
	data.Dna += bonus
	local to = data.Host
	local core = Config.Hosts[to].Core
	World.despawn(germ)
	World.fireDish(dish, Net.Announce, "💥 ACHOO! " .. germ.name .. " was sneezed out of " .. Config.Hosts[from].Name .. "!")
	Net.Sneeze:FireClient(player, {
		from = Config.Hosts[from].Name,
		to = Config.Hosts[to].Name,
		toHost = to,
		fx = data.Skin.SneezeFx,
		dna = bonus,
		sneezes = data.Sneezes,
		mutant = data.Mutant,
		mutantUp = mutantUp,
		core = (not mutantUp and core ~= "Blob") and Config.Cores[core].Name or nil,
		arenaUnlocked = mutantUp and data.Mutant == Config.Arena.UnlockMutant,
		sneezeCam = PlayerService.ownsPass(player, "SneezeCam"),
		runTime = runTime,
		runRecord = runRecord,
		unlocks = PlayerService.unlockText(from, to),
	})
	Bus.fire("Sneeze", player, { from = from, to = to, mutantUp = mutantUp })
	if not data.FavoritePrompted then
		data.FavoritePrompted = true
		task.delay(6, function()
			if player.Parent then
				Net.Prompt:FireClient(player, "Favorite")
			end
		end)
	end
	local camSeconds = PlayerService.ownsPass(player, "SneezeCam") and 2 or 0
	task.delay(3 + camSeconds, function()
		germ.sneezing = false
		if germOf[player] == germ and player.Parent then
			PlayerService.goHost(player)
			PlayerService.sync(player)
		end
	end)
end
PlayerService.sneeze = sneeze

-- What a new host lets you use that the last one didn't (shown after a sneeze)
function PlayerService.unlockText(from, to)
	local a, b = Formulas.hostLimits(from), Formulas.hostLimits(to)
	if to < from then
		return "Back in host 1: only " .. b.slots .. " slots and levels up to " .. b.levelCap .. " count here again"
	end
	local bits = {}
	if b.slots > a.slots then
		table.insert(bits, "🔓 " .. b.slots .. " mutation slots")
	end
	if b.levelCap > a.levelCap then
		table.insert(bits, "levels up to " .. b.levelCap)
	end
	if b.fusions and not a.fusions then
		table.insert(bits, "🔓 Fusions")
	end
	if b.dnaCap > a.dnaCap then
		table.insert(bits, "DNA bag " .. Formulas.formatNumber(b.dnaCap))
	end
	return #bits > 0 and table.concat(bits, " · ") or nil
end

-- World hooks ------------------------------------------------------------------------------------

local function onGainDna(germ, amount)
	local player = germ.player
	local data = player and DataService.get(player)
	if data and amount > 0 then
		local cap = Formulas.hostLimits(data.Host).dnaCap
		if data.Dna < cap then
			data.Dna = math.min(cap, data.Dna + amount)
			if data.Dna >= cap and not germ.dnaFullWarned then
				germ.dnaFullWarned = true
				Net.notify(player, "🧬 Your DNA bag is full (" .. Formulas.formatNumber(cap) .. ")! Spend it in the Lab. Sneezing into the next host makes the bag bigger", "info")
			end
		end
	end
end

local function onAteGerm(eater, victim, info)
	if eater.dish then
		World.fireDish(eater.dish, Net.Feed, eater.name, victim.name, info.revenge, info.crowned)
	end
	local player = eater.player
	local data = player and DataService.get(player)
	if data then
		data.Kills += 1
		local text = "You ate " .. victim.name .. "! +" .. info.dna .. " DNA"
		if info.revenge then
			text = "REVENGE on " .. victim.name .. "! +" .. info.dna .. " DNA"
			Bus.fire("Revenge", player)
		elseif info.crowned then
			text = "You ate the KING " .. victim.name .. "! +" .. info.dna .. " DNA 👑"
		end
		Net.notify(player, text, "success")
		Bus.fire("AteGerm", player, victim, info)
	end
end

local function onAteFood(germ, count, golden)
	local player = germ.player
	if not player then
		return
	end
	Bus.fire("AteFood", player, count)
	if golden then
		Bus.fire("Golden", player)
		if germ.dish then
			World.fireDish(germ.dish, Net.Announce, "✨ " .. germ.name .. " grabbed the golden food!")
		end
	end
end

local function onGermDied(victim, eater)
	if BotService.isBot(victim) then
		BotService.onBotDied(victim)
		return
	end
	local player = victim.player
	if not player or not player.Parent then
		return
	end
	local data = DataService.get(player)
	if data then
		data.Deaths += 1
	end
	if victim.mode == "arena" then
		PlayerService.hooks.arenaDied(player, victim, eater)
		return
	end
	local dish = victim.dish
	local start = PlayerService.startSize(player, data.Host)
	local size = Formulas.respawnSize(victim.sizeAtDeath or 0, victim.stats.respawnShare, start)
	victim.reviveSize = victim.sizeAtDeath
	victim.reviveUntil = World.now() + 20
	Net.Died:FireClient(player, eater and eater.name or "?", Config.RespawnSeconds, true)
	task.delay(Config.RespawnSeconds, function()
		if germOf[player] == victim and player.Parent and not victim.alive and victim.mode == "host" then
			if World.dish(dish.id) then
				DishService.enter(victim, dish, size)
			else
				PlayerService.goHost(player, size)
			end
			PlayerService.sync(player)
		end
	end)
end

-- Paid revive: come back at the size you had (hosts only, within 20 s of being eaten)
function PlayerService.revive(player)
	local germ = germOf[player]
	if not germ or germ.mode ~= "host" or not germ.reviveSize or World.now() > (germ.reviveUntil or 0) then
		return false
	end
	local size = germ.reviveSize
	germ.reviveSize = nil
	if germ.alive then
		World.setGermSize(germ, math.max(size, World.germSize(germ)))
	else
		task.delay(Config.RespawnSeconds + 0.2, function()
			if germ.alive then
				World.setGermSize(germ, math.max(size, World.germSize(germ)))
			end
		end)
	end
	return true
end

-- Start -----------------------------------------------------------------------------------------

function PlayerService.start()
	World.hooks.gainDna = onGainDna
	World.hooks.ateGerm = onAteGerm
	World.hooks.ateFood = onAteFood
	World.hooks.germDied = onGermDied
	World.hooks.sneeze = function(germ)
		if germ.mode == "arena" then
			PlayerService.hooks.arenaGoal(germ.player, germ)
		else
			sneeze(germ)
		end
	end

	Net.Steer.OnServerEvent:Connect(onSteer)
	Net.Action.OnServerEvent:Connect(onAction)

	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end

	-- 4 times a second: HUD
	task.spawn(function()
		while true do
			task.wait(0.25)
			for player in germOf do
				PlayerService.sync(player)
			end
		end
	end)

	-- once a second: play time, best size, leaderboard, quests, menus
	task.spawn(function()
		while true do
			task.wait(1)
			for player, germ in germOf do
				local data = DataService.get(player)
				if data then
					data.TotalPlaySeconds += 1
					if germ.mode == "host" then
						data.RunSeconds += 1
					end
					if germ.dnaFullWarned and data.Dna < Formulas.hostLimits(data.Host).dnaCap * 0.9 then
						germ.dnaFullWarned = nil
					end
					germ.isNewPlayer = data.TotalPlaySeconds < Config.Bots.NewPlayerMinutes * 60
					local size = germ.alive and World.germSize(germ) or 0
					if size > data.BestSize then
						data.BestSize = math.floor(size)
					end
					setStat(player, "Size", size)
					setStat(player, "DNA", data.Dna)
					setStat(player, "Sneezes", data.Sneezes)
					player:SetAttribute("Size", math.floor(size))
					if germ.alive and germ.dish then
						local cx, cz = World.germCentre(germ)
						local zone = Formulas.zoneAt(math.sqrt(cx * cx + cz * cz), germ.dish.layout)
						player:SetAttribute("Zone", zone)
						if zone > (germ.bestZone or 1) and germ.mode == "host" then
							germ.bestZone = zone
							Bus.fire("Zone", player, zone)
						end
					end
					-- a Growth Potion running out changes the stats
					if germ.potionOn and data.PotionUntil <= os.time() then
						germ.potionOn = false
						PlayerService.refresh(player)
						Net.notify(player, "Your Growth Potion ran out", "info")
					end
					if profileDirty[player] then
						PlayerService.sendProfile(player)
					end
				end
			end
		end
	end)
end

return PlayerService
