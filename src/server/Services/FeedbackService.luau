-- Players can send bug reports and ideas from the game. They are saved in a DataStore,
-- so the developer can read them later in Studio:
--   game.ServerScriptService.Server.Services.FeedbackService -- see readAll below
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Net = require(script.Parent.Net)

local FeedbackService = {}

local MAX_LENGTH = 500
local COOLDOWN = 60 -- seconds between messages from one player

local store = nil
local lastSent = {} -- [player] = os.clock() of their last message

local function getStore()
	if not store then
		local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "Feedback_v1")
		store = ok and result or false
	end
	return store or nil
end

function FeedbackService.send(player, kind, text)
	if type(text) ~= "string" or type(kind) ~= "string" then
		return false, "Type a message first"
	end
	text = string.sub(string.gsub(text, "^%s+", ""), 1, MAX_LENGTH)
	if #text < 5 then
		return false, "Write a bit more so we can fix it!"
	end
	if lastSent[player] and os.clock() - lastSent[player] < COOLDOWN then
		return false, "Thanks! You can send another message in a minute"
	end
	lastSent[player] = os.clock()

	local entry = {
		Kind = (kind == "Bug") and "Bug" or "Idea",
		Text = text,
		UserId = player.UserId,
		Name = player.Name,
		Time = os.time(),
		Zone = player:GetAttribute("Zone") or 0,
		Size = player:GetAttribute("Size") or 0,
		PlaceVersion = game.PlaceVersion,
	}
	print("[Feedback]", entry.Kind, player.Name, text)
	local ds = getStore()
	if ds then
		task.spawn(function()
			local key = string.format("%d_%s", os.time(), string.sub(HttpService:GenerateGUID(false), 1, 8))
			local ok, err = pcall(ds.SetAsync, ds, key, entry)
			if not ok then
				warn("[Feedback] could not save:", err)
			end
		end)
	end
	return true, "Thanks! Your message was sent to the developer 🦠"
end

-- Studio helper: returns every saved message, newest first (needs API access enabled).
function FeedbackService.readAll(limit)
	local ds = getStore()
	local out = {}
	if not ds then
		return out
	end
	local pages = ds:ListKeysAsync(nil, 100)
	while true do
		for _, item in pages:GetCurrentPage() do
			local ok, value = pcall(ds.GetAsync, ds, item.KeyName)
			if ok and value then
				table.insert(out, value)
			end
			if limit and #out >= limit then
				break
			end
		end
		if pages.IsFinished or (limit and #out >= limit) then
			break
		end
		pages:AdvanceToNextPageAsync()
	end
	table.sort(out, function(a, b)
		return a.Time > b.Time
	end)
	return out
end

function FeedbackService.start()
	Net.SendFeedback.OnServerInvoke = FeedbackService.send
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
	end)
end

return FeedbackService
