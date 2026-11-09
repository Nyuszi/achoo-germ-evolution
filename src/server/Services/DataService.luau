-- Loads and saves each player's progress with DataStoreService.
-- In Studio without "Enable Studio Access to API Services", saving is skipped and
-- everyone starts fresh, so the game still works for testing.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

local DEFAULTS = {
	Dna = 0,
	BestSize = 0,
	Kills = 0,
	Deaths = 0,
	Sneezes = 0,
	Mutations = {}, -- [mutationId] = true (owned)
	Equipped = {}, -- [slot] = mutationId
	TotalPlaySeconds = 0,
	Receipts = {}, -- [purchaseId] = true, so a purchase is never granted twice
	ReceiptOrder = {},
	ReferredBy = 0,
	Referrals = {},
	FavoritePrompted = false,
}

local profiles = {} -- [player] = data table
local loaded = {} -- [player] = BindableEvent fired once data is ready
local store
local storeOk = pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function reconcile(data)
	for key, default in DEFAULTS do
		if data[key] == nil then
			data[key] = deepCopy(default)
		end
	end
	return data
end

local function withRetries(fn)
	local lastError
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		-- No point retrying when Studio simply isn't allowed to use DataStores
		if string.find(tostring(result), "403") or string.find(tostring(result), "StudioAccessToApis") then
			break
		end
		task.wait(attempt)
	end
	return false, lastError
end

function DataService.load(player)
	local data
	if storeOk and store then
		local ok, result = withRetries(function()
			return store:GetAsync("Player_" .. player.UserId)
		end)
		if ok then
			data = result
		else
			warn("[Data] Could not load " .. player.Name .. ": " .. tostring(result) .. " (progress will not save)")
			player:SetAttribute("SaveDisabled", true)
		end
	end
	profiles[player] = reconcile(type(data) == "table" and data or {})
	if loaded[player] then
		loaded[player]:Fire()
	end
	return profiles[player]
end

function DataService.get(player)
	return profiles[player]
end

-- Waits until the player's data is ready (or they leave).
function DataService.waitFor(player)
	if profiles[player] then
		return profiles[player]
	end
	if not loaded[player] then
		loaded[player] = Instance.new("BindableEvent")
	end
	while not profiles[player] and player.Parent do
		loaded[player].Event:Wait()
	end
	return profiles[player]
end

function DataService.save(player)
	local data = profiles[player]
	if not data or not storeOk or not store or player:GetAttribute("SaveDisabled") then
		return false
	end
	local ok, err = withRetries(function()
		store:UpdateAsync("Player_" .. player.UserId, function()
			return data
		end)
	end)
	if not ok then
		warn("[Data] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

function DataService.recordReceipt(player, purchaseId)
	local data = profiles[player]
	data.Receipts[purchaseId] = true
	table.insert(data.ReceiptOrder, purchaseId)
	-- Only remember the last 50 purchases so the save stays small.
	while #data.ReceiptOrder > 50 do
		local old = table.remove(data.ReceiptOrder, 1)
		data.Receipts[old] = nil
	end
end

function DataService.release(player)
	DataService.save(player)
	profiles[player] = nil
	if loaded[player] then
		loaded[player]:Destroy()
		loaded[player] = nil
	end
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for _, player in Players:GetPlayers() do
				task.spawn(DataService.save, player)
			end
		end
	end)

	game:BindToClose(function()
		local threads = 0
		for _, player in Players:GetPlayers() do
			threads += 1
			task.spawn(function()
				DataService.save(player)
				threads -= 1
			end)
		end
		local waited = 0
		while threads > 0 and waited < 25 do
			waited += task.wait(0.5)
		end
	end)
end

return DataService
