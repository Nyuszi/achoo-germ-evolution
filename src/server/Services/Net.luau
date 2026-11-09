-- Creates the remotes the client and server talk through.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local EVENTS = {
	"Snapshot", -- server -> dish viewers: germ positions and sizes (a buffer, 10 per second)
	"CellInfo", -- server -> dish viewers: names, colours, mutations and skins of germs
	"CellGone", -- server -> dish viewers: cells that were eaten, merged or left ({ ids })
	"FoodSync", -- server -> client: every food pellet of the dish you just entered
	"FoodDelta", -- server -> dish viewers: pellets added and eaten since the last snapshot
	"DishInfo", -- server -> client: the dish you are in now (host or Arena floor, theme, modifiers)
	"DishFx", -- server -> dish viewers: hazards and events (kind, data)
	"Sync", -- server -> client: your stats for the HUD
	"Profile", -- server -> client: your saved progress for the menus (Lab, Editor, Quests...)
	"Notify", -- server -> client: a toast message
	"Feed", -- server -> dish viewers: "A ate B" kill feed
	"Announce", -- server -> all or a dish: big message
	"Died", -- server -> client: you were eaten (by whom, respawn in)
	"Sneeze", -- server -> client: you sneezed (from host, to host, effect)
	"Prompt", -- server -> client: ask the client to show a Roblox prompt ("Favorite", "Invite")
	"Action", -- client -> server: "Dash", "Split", "Front" (Q), "Special" (R)
}
local UNRELIABLE = {
	"Steer", -- client -> server: where you are steering (x, z), many times a second
}
local FUNCTIONS = {
	"Lab", -- mutations, levels, fusions, cores, skills, loadouts
	"Shop", -- passes, products, skins, flags
	"Editor", -- equip skin items, colours, outfits
	"Quests", -- claim, redeem codes
	"Arena", -- enter, leave, token shop
	"Leaders", -- leaderboard lists
	"Dev", -- test commands (Studio and the game owner only)
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
