-- Creates the remotes the client and server talk through.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local EVENTS = {
	"Snapshot", -- server -> all: germ positions and sizes (a buffer, 10 per second)
	"CellInfo", -- server -> all: names, colours and mutations of new germs ({ [id] = info })
	"CellGone", -- server -> all: germs that were eaten, merged or left ({ ids })
	"FoodSync", -- server -> client: every food pellet (on join)
	"FoodDelta", -- server -> all: pellets added and eaten since the last tick
	"Sync", -- server -> client: your stats for the HUD
	"Notify", -- server -> client: a toast message
	"Feed", -- server -> all: "A ate B" kill feed
	"Announce", -- server -> all: big server-wide message
	"Died", -- server -> client: you were eaten (by whom, respawn in)
	"Action", -- client -> server: "Dash" or "Split"
}
local UNRELIABLE = {
	"Steer", -- client -> server: where you are steering (x, z), many times a second
}
local FUNCTIONS = {
	"BuyMutation",
	"EquipMutation",
	"SendFeedback",
}

for _, name in EVENTS do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	Net[name] = remote
end
for _, name in UNRELIABLE do
	local remote = Instance.new("UnreliableRemoteEvent")
	remote.Name = name
	remote.Parent = folder
	Net[name] = remote
end
for _, name in FUNCTIONS do
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	Net[name] = remote
end

folder.Parent = ReplicatedStorage

function Net.notify(player, text, kind)
	Net.Notify:FireClient(player, text, kind or "info")
end

return Net
