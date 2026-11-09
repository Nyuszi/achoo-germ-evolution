-- Test commands for Roblox Studio and the game's owner, so you can try every stage quickly.
-- Everyone else gets "not allowed". Open the 🛠 Dev button in the game.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local World = require(script.Parent.World)
local PlayerService = require(script.Parent.PlayerService)
local HazardService = require(script.Parent.HazardService)
local ImmuneService = require(script.Parent.ImmuneService)
local ArenaService = require(script.Parent.ArenaService)

local DevService = {}

-- Add more user ids here to give friends the Dev panel in the live game
local EXTRA_DEVS = {}

function DevService.isDev(player)
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		if ok and rank >= 254 then
			return true
		end
	end
	return table.find(EXTRA_DEVS, player.UserId) ~= nil
end

local commands = {}

-- grow to the sneeze size and jump next to the Sneeze Nerve
function commands.SneezeSize(player, data, germ)
	if not germ.alive then
		return false, "Wait until you respawn"
	end
	local dish = germ.dish
	World.setGermSize(germ, dish.layout.sneeze * 1.01)
	for _, cell in germ.cells do
		cell.x, cell.z = Config.NerveRadius + 25, 0
	end
	germ.target = { x = 0, z = 0 }
	return true, "Size set to the goal. Swim into the middle!"
end

function commands.Grow(player, data, germ)
	if not germ.alive then
		return false
	end
	World.setGermSize(germ, World.germSize(germ) * 2)
	return true, "Size doubled"
end

function commands.Dna(player, data)
	data.Dna += 10000
	return true, "+10,000 DNA"
end

function commands.NextHost(player, data, germ)
	if germ.mode ~= "host" or not germ.alive then
		return false, "Only in a host"
	end
	PlayerService.sneeze(germ)
	return true
end

function commands.Host(player, data, germ, n)
	n = math.clamp(tonumber(n) or 1, 1, #Config.Hosts)
	data.Host = n
	data.MaxHost = math.max(data.MaxHost, n)
	PlayerService.goHost(player)
	return true, "Moved to " .. Config.Hosts[n].Name
end

function commands.Mutant(player, data)
	data.Mutant += 1
	data.MaxHost = #Config.Hosts
	return true, "Mutant " .. data.Mutant .. ": the Arena is open"
end

function commands.GermPoints(player, data)
	data.GermPoints += 5
	return true, "+5 Germ Points"
end

function commands.Tokens(player, data)
	data.Tokens += 500
	return true, "+500 Arena Tokens"
end

function commands.MaxLab(player, data)
	for id in Config.Mutations do
		data.Levels[id] = Config.MaxMutationLevel
	end
	return true, "All mutations at max level (try fusions!)"
end

function commands.Whitey(player, data, germ)
	if not germ.dish then
		return false
	end
	ImmuneService.spawnWhitey(germ.dish, { hunt = germ })
	return true, "Whitey is coming for you"
end

function commands.Macrophage(player, data, germ)
	if not germ.dish then
		return false
	end
	ImmuneService.spawnMacrophage(germ.dish)
	return true
end

function commands.Fever(player, data, germ)
	if not germ.dish then
		return false
	end
	ImmuneService.startFever(germ.dish, player.DisplayName)
	return true
end

function commands.Medicine(player, data, germ)
	if not germ.dish then
		return false
	end
	ImmuneService.startMedicine(germ.dish)
	return true
end

function commands.Hazard(player, data, germ)
	if not germ.dish or germ.dish.kind ~= "host" then
		return false, "Only in a host"
	end
	HazardService.trigger(germ.dish)
	return true, Config.Hosts[germ.dish.host].HazardText
end

function commands.Golden(player, data, germ)
	if not germ.dish then
		return false
	end
	World.spawnGolden(germ.dish)
	return true, "Golden food spawned"
end

function commands.ArenaFloor(player, data, germ)
	if germ.mode ~= "arena" then
		return false, "Enter the Arena first"
	end
	ArenaService.toFloor(player, (germ.arenaFloor or 1) + 9)
	return true, "Skipped ahead 9 floors"
end

function commands.EndQuarantine(player, data, germ)
	germ.quarantineUntil = 0
	data.TotalPlaySeconds = math.max(data.TotalPlaySeconds, Config.QuarantineMinutes * 60)
	return true, "Quarantine off: you can be eaten now"
end

function commands.CompleteQuests(player, data)
	for _, q in data.Quests.List do
		q.Progress = q.Goal
	end
	return true, "Quests finished: claim them in Quests"
end

function commands.Reset(player, data)
	for key in data do
		if key ~= "Receipts" and key ~= "ReceiptOrder" then
			data[key] = nil
		end
	end
	DataService.reconcile(data)
	data.TotalPlaySeconds = Config.QuarantineMinutes * 60
	PlayerService.goHost(player)
	return true, "Progress wiped (like a brand new player)"
end

function DevService.start()
	PlayerService.isDev = DevService.isDev
	ArenaService.isDev = function()
		return false -- devs unlock the Arena with the Mutant button like everyone else
	end
	Net.Dev.OnServerInvoke = function(player, command, arg)
		if not DevService.isDev(player) then
			return false, "Not allowed"
		end
		local data = DataService.get(player)
		local germ = PlayerService.germ(player)
		local fn = type(command) == "string" and commands[command]
		if not data or not germ or not fn then
			return false, "Unknown command"
		end
		local ok, message = fn(player, data, germ, arg)
		PlayerService.refresh(player)
		return ok, message
	end
	local _ = Players
end

return DevService
