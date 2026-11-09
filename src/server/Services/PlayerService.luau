-- Turns each player into a germ: loading, spawning, steering, moves, mutations, DNA,
-- respawning after being eaten, and the stats the HUD shows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local World = require(script.Parent.World)
local BotService = require(script.Parent.BotService)

local PlayerService = {}

local HOST = Formulas.host()
local germOf = {} -- [player] = germ

function PlayerService.germ(player)
	return germOf[player]
end

local function leaderstats(player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local size = Instance.new("IntValue")
	size.Name = "Size"
	size.Parent = folder
	local dna = Instance.new("IntValue")
	dna.Name = "DNA"
	dna.Parent = folder
	folder.Parent = player
end

local function setStat(player, name, value)
	local folder = player:FindFirstChild("leaderstats")
	local stat = folder and folder:FindFirstChild(name)
	if stat then
		stat.Value = math.floor(value)
	end
end

-- Sends the HUD everything it needs about you.
function PlayerService.sync(player)
	local germ = germOf[player]
	local data = DataService.get(player)
	if not germ or not data then
		return
	end
	local now = World.now()
	local size = World.germSize(germ)
	local cx, cz = World.germCentre(germ)
	local zone = Formulas.zoneAt(math.sqrt(cx * cx + cz * cz))
	local nextZone = Formulas.deepestZone(size) + 1
	local nextGate = nil
	if Config.Zones[nextZone] then
		nextGate = { name = Config.Zones[nextZone].Name, size = Formulas.zoneMinSize(nextZone) }
	else
		nextGate = { name = "Sneeze", size = HOST.SneezeSize }
	end
	Net.Sync:FireClient(player, {
		germId = germ.id,
		alive = germ.alive,
		size = size,
		best = data.BestSize,
		dna = data.Dna,
		zone = zone,
		zoneName = Config.Zones[zone].Name,
		hostName = HOST.Name,
		nextGate = nextGate,
		quarantine = math.max(0, germ.quarantineUntil - now),
		protected = World.isProtected(germ),
		dashIn = math.max(0, germ.dashReadyAt - now),
		splitIn = math.max(0, germ.splitReadyAt - now),
		owned = data.Mutations,
		equipped = data.Equipped,
		crowned = World.crowned == germ,
		kills = data.Kills,
	})
end

local function onJoin(player)
	leaderstats(player)
	local data = DataService.load(player)
	if not player.Parent then
		return
	end
	local played = data.TotalPlaySeconds or 0
	local germ = World.newGerm({
		name = player.DisplayName,
		color = Config.GermColors[math.random(1, #Config.GermColors)],
		player = player,
		equipped = table.clone(data.Equipped),
		quarantineUntil = World.now() + math.max(0, Config.QuarantineMinutes * 60 - played),
	})
	germ.isNewPlayer = played < Config.Bots.NewPlayerMinutes * 60
	germOf[player] = germ

	-- the world as it is right now
	local info, foodList = World.fullState()
	Net.CellInfo:FireClient(player, info)
	Net.FoodSync:FireClient(player, foodList)

	World.spawnGerm(germ, Config.StartSize * HOST.Scale)
	PlayerService.sync(player)
	if germ.quarantineUntil > World.now() then
		Net.notify(player, "Welcome! You're in Quarantine for a few minutes: nobody can eat you yet 🛡️ Eat food and smaller germs to grow!", "info")
	end
end

local function onLeave(player)
	local germ = germOf[player]
	if germ then
		World.removeGerm(germ)
		germOf[player] = nil
	end
	DataService.release(player)
end

-- Remotes ------------------------------------------------------------------------------

local function onSteer(player, x, z)
	local germ = germOf[player]
	if not germ or type(x) ~= "number" or type(z) ~= "number" then
		return
	end
	if x ~= x or z ~= z then -- NaN
		return
	end
	local limit = Config.ArenaRadius * 1.2
	germ.target = { x = math.clamp(x, -limit, limit), z = math.clamp(z, -limit, limit) }
end

local function onAction(player, action)
	local germ = germOf[player]
	if not germ then
		return
	end
	if action == "Dash" then
		World.dash(germ)
	elseif action == "Split" then
		World.split(germ)
	end
end

local function buyMutation(player, id)
	local data = DataService.get(player)
	local germ = germOf[player]
	local m = type(id) == "string" and Config.Mutations[id]
	if not data or not germ or not m then
		return false, "Unknown mutation"
	end
	if not data.Mutations[id] then
		if data.Dna < m.Cost then
			return false, "You need " .. m.Cost .. " DNA (eat germs to get DNA!)"
		end
		data.Dna -= m.Cost
		data.Mutations[id] = true
	end
	data.Equipped[m.Slot] = id
	germ.equipped = table.clone(data.Equipped)
	World.applyMutations(germ)
	PlayerService.sync(player)
	return true, m.Name .. " equipped!"
end

local function equipMutation(player, id)
	local data = DataService.get(player)
	local germ = germOf[player]
	if not data or not germ or type(id) ~= "string" then
		return false
	end
	local m = Config.Mutations[id]
	if m then
		if not data.Mutations[id] then
			return false, "Unlock it first"
		end
		if data.Equipped[m.Slot] == id then
			data.Equipped[m.Slot] = nil -- tap again to take it off
		else
			data.Equipped[m.Slot] = id
		end
	end
	germ.equipped = table.clone(data.Equipped)
	World.applyMutations(germ)
	PlayerService.sync(player)
	return true
end

-- World hooks ----------------------------------------------------------------------------

local function playerOf(germ)
	return germ and germ.player
end

local function onGainDna(germ, amount)
	local player = playerOf(germ)
	local data = player and DataService.get(player)
	if data and amount > 0 then
		data.Dna += amount
	end
end

local function onAteGerm(eater, victim, info)
	Net.Feed:FireAllClients(eater.name, victim.name, info.revenge, info.crowned)
	local player = playerOf(eater)
	local data = player and DataService.get(player)
	if data then
		data.Kills += 1
		local text = "You ate " .. victim.name .. "! +" .. info.dna .. " DNA"
		if info.revenge then
			text = "REVENGE on " .. victim.name .. "! +" .. info.dna .. " DNA"
		elseif info.crowned then
			text = "You ate the KING " .. victim.name .. "! +" .. info.dna .. " DNA 👑"
		end
		Net.notify(player, text, "success")
	end
end

local function onGermDied(victim, eater)
	if BotService.isBot(victim) then
		BotService.onBotDied(victim)
		return
	end
	local player = playerOf(victim)
	if not player or not player.Parent then
		return
	end
	local data = DataService.get(player)
	if data then
		data.Deaths += 1
	end
	Net.Died:FireClient(player, eater and eater.name or "?", Config.RespawnSeconds)
	local size = Formulas.respawnSize(victim.sizeAtDeath or 0)
	task.delay(Config.RespawnSeconds, function()
		if germOf[player] == victim and player.Parent then
			World.spawnGerm(victim, math.max(size, Config.StartSize * HOST.Scale))
			PlayerService.sync(player)
		end
	end)
end

-- Start ------------------------------------------------------------------------------------

function PlayerService.start()
	World.hooks.gainDna = onGainDna
	World.hooks.ateGerm = onAteGerm
	World.hooks.germDied = onGermDied

	Net.Steer.OnServerEvent:Connect(onSteer)
	Net.Action.OnServerEvent:Connect(onAction)
	Net.BuyMutation.OnServerInvoke = buyMutation
	Net.EquipMutation.OnServerInvoke = equipMutation

	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end

	-- once a second: play time, best size, leaderboard, HUD
	task.spawn(function()
		while true do
			task.wait(1)
			for player, germ in germOf do
				local data = DataService.get(player)
				if data then
					data.TotalPlaySeconds += 1
					germ.isNewPlayer = data.TotalPlaySeconds < Config.Bots.NewPlayerMinutes * 60
					local size = World.germSize(germ)
					if size > data.BestSize then
						data.BestSize = math.floor(size)
					end
					setStat(player, "Size", size)
					setStat(player, "DNA", data.Dna)
					player:SetAttribute("Size", math.floor(size))
					local cx, cz = World.germCentre(germ)
					player:SetAttribute("Zone", Formulas.zoneAt(math.sqrt(cx * cx + cz * cz)))
					if germ.ateGolden then
						germ.ateGolden = false
						Net.Announce:FireAllClients("✨ " .. germ.name .. " grabbed the golden food!")
					end
					PlayerService.sync(player)
				end
			end
		end
	end)

	-- golden food every 90 seconds
	task.spawn(function()
		while true do
			task.wait(Config.GoldenEverySeconds)
			local zoneName = World.spawnGolden()
			Net.Announce:FireAllClients("✨ Golden food appeared in the " .. zoneName .. "!")
		end
	end)
end

return PlayerService
