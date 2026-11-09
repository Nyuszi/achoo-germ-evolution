-- Reasons to come back: 3 daily quests, a weekly goal, a login streak, codes, invite rewards,
-- collectible cards (earned only, never sold) and the global leaderboards.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local Bus = require(script.Parent.Bus)

local QuestService = {}

local questById = {}
for _, q in Config.DailyQuests do
	questById[q.Id] = q
end

local function today()
	return Formulas.dayNumber(os.time())
end

-- Fresh quests each day (the same 3 for a player all day)
local function ensureQuests(player, data)
	local day = today()
	local q = data.Quests
	if q.Day ~= day then
		q.Day = day
		q.List = {}
		local rng = Random.new(day * 7919 + player.UserId % 100000)
		local pool = {}
		for _, quest in Config.DailyQuests do
			table.insert(pool, quest.Id)
		end
		local tier = math.clamp(1 + math.floor((data.MaxHost - 1) / 2), 1, 3)
		for _ = 1, Config.QuestsPerDay do
			local id = table.remove(pool, rng:NextInteger(1, #pool))
			table.insert(q.List, { Id = id, Goal = questById[id].Goals[tier], Progress = 0, Claimed = false })
		end
	end
	local week = math.floor(day / 7)
	if q.Week ~= week then
		q.Week = week
		q.Weekly = 0
		q.WeeklyClaimed = false
	end
end

local function giveCard(player, data, set, name)
	if data.Cards[name] then
		return
	end
	data.Cards[name] = true
	Net.notify(player, "🃏 New card: " .. name .. " (" .. set .. " set)", "success")
	PlayerService.markProfile(player)
end

local function nextMissing(data, set)
	for _, name in Config.CardSets[set] do
		if not data.Cards[name] then
			return name
		end
	end
	return nil
end

local function progress(player, id, amount, setTo)
	local data = DataService.get(player)
	if not data then
		return
	end
	ensureQuests(player, data)
	for _, q in data.Quests.List do
		if q.Id == id and not q.Claimed and q.Progress < q.Goal then
			if setTo then
				q.Progress = math.max(q.Progress, setTo)
			else
				q.Progress = math.min(q.Goal, q.Progress + (amount or 1))
			end
			if q.Progress >= q.Goal then
				Net.notify(player, "✅ Quest done! Open Quests to claim your DNA", "success")
				PlayerService.markProfile(player)
			end
		end
	end
end

local actions = {}

function actions.Refresh(player, data)
	ensureQuests(player, data)
	return true
end

function actions.Claim(player, data, index)
	ensureQuests(player, data)
	local q = type(index) == "number" and data.Quests.List[index]
	if not q or q.Claimed or q.Progress < q.Goal then
		return false, "Not finished yet"
	end
	q.Claimed = true
	local dna = questById[q.Id].Dna
	data.Dna += dna
	data.Quests.Weekly = math.min(Config.WeeklySteps, data.Quests.Weekly + 1)
	return true, "+" .. dna .. " DNA"
end

function actions.ClaimWeekly(player, data)
	ensureQuests(player, data)
	local q = data.Quests
	if q.WeeklyClaimed or q.Weekly < Config.WeeklySteps then
		return false, "Finish " .. Config.WeeklySteps .. " daily quests this week"
	end
	q.WeeklyClaimed = true
	data.Dna += 500
	local card = nextMissing(data, "Germs")
	if card then
		giveCard(player, data, "Germs", card)
	end
	return true, "+500 DNA" .. (card and (" and the " .. card .. " card") or "")
end

function actions.ClaimSet(player, data, set)
	local list = type(set) == "string" and Config.CardSets[set]
	if not list or data.CardSetsClaimed[set] then
		return false
	end
	if nextMissing(data, set) then
		return false, "Collect every card in the set first"
	end
	data.CardSetsClaimed[set] = true
	local cat, id = string.match(Config.CardSetRewards[set], "^(%a+):(%a+)$")
	data.OwnedSkins[cat .. ":" .. id] = true
	return true, "Set complete! You unlocked a new " .. cat
end

function actions.Redeem(player, data, code)
	if type(code) ~= "string" then
		return false, "Type a code"
	end
	code = string.upper(string.gsub(code, "%s", ""))
	local reward = Config.Codes[code]
	if not reward then
		return false, "That code doesn't work"
	end
	if data.Codes[code] then
		return false, "You already used this code"
	end
	data.Codes[code] = true
	if reward.Dna then
		data.Dna += reward.Dna
	end
	if reward.Potion then
		data.Potions += reward.Potion
	end
	return true, "Code redeemed! " .. (reward.Dna and ("+" .. reward.Dna .. " DNA") or "+1 Growth Potion")
end

-- Login streak: a reward every day you come back, day 7 gives a sneeze effect
local function loginStreak(player, data)
	local day = today()
	local s = data.Streak
	if s.Day == day then
		return
	end
	if s.Day == day - 1 then
		s.Count += 1
	else
		s.Count = 1
	end
	s.Day = day
	local reward = Config.StreakRewards[((s.Count - 1) % #Config.StreakRewards) + 1]
	if type(reward) == "number" then
		data.Dna += reward
		Net.notify(player, "🔥 Day " .. s.Count .. " streak! +" .. reward .. " DNA", "success")
	else
		local cat, id = string.match(reward, "^(%a+):(%a+)$")
		if cat == "Sneeze" then
			cat = "SneezeFx"
		end
		data.OwnedSkins[cat .. ":" .. id] = true
		Net.notify(player, "🔥 Day " .. s.Count .. " streak! You unlocked the " .. id .. " sneeze effect", "success")
	end
end

-- Invites: a player who joins through a friend's invite gets a potion, and so does the friend
local function referral(player, data)
	if data.ReferredBy ~= 0 or data.TotalPlaySeconds > 60 then
		return
	end
	local ok, join = pcall(function()
		return player:GetJoinData()
	end)
	local by = ok and join and join.ReferredByPlayerId or 0
	if by and by > 0 and by ~= player.UserId then
		data.ReferredBy = by
		data.Potions += Config.ReferralReward.Potion
		Net.notify(player, "Thanks for joining through an invite! +1 Growth Potion", "success")
		local friend = Players:GetPlayerByUserId(by)
		local fd = friend and DataService.get(friend)
		if fd and not fd.Referrals[tostring(player.UserId)] then
			fd.Referrals[tostring(player.UserId)] = true
			fd.Potions = math.max(fd.Potions, math.min(fd.Potions + Config.ReferralReward.Potion, Config.MaxQuestPotions)) -- free potions stack up to a limit
			Net.notify(friend, player.DisplayName .. " joined from your invite! +1 Growth Potion", "success")
			PlayerService.markProfile(friend)
		end
	end
end

-- Leaderboards -------------------------------------------------------------------------------------

local stores = {}
local cache = {} -- [boardId] = { time, rows }
local boardInfo = {} -- [boardId] = the Config entry
for _, lb in Config.Leaderboards do
	boardInfo[lb.Id] = lb
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, lb.Store)
	stores[lb.Id] = ok and store or nil
end

local function boardValue(data, id)
	if id == "BestSize" then
		return data.BestSize
	elseif id == "Sneezes" then
		return data.Sneezes
	elseif id == "Kills" then
		return data.Kills
	elseif id == "ArenaFloor" then
		return data.ArenaBestEver
	elseif id == "FastestRun" then
		return data.BestRun
	elseif id == "Runs" then
		return data.Mutant
	end
	return 0
end

local function writeBoards(player)
	local data = DataService.get(player)
	if not data or player:GetAttribute("SaveDisabled") then
		return
	end
	for id, store in stores do
		local v = math.floor(math.min(boardValue(data, id), 2 ^ 52))
		if v > 0 then
			pcall(store.SetAsync, store, tostring(player.UserId), v)
		end
	end
end

local function readBoard(id)
	local c = cache[id]
	if c and os.clock() - c.time < 60 then
		return c.rows
	end
	local rows = {}
	local store = stores[id]
	local ok = false
	if store then
		ok = pcall(function()
			local page = store:GetSortedAsync(boardInfo[id].Ascending == true, 10):GetCurrentPage()
			for i, entry in page do
				local userId = tonumber(entry.key) or 0
				local nameOk, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
				rows[i] = { name = nameOk and name or ("Player " .. entry.key), value = entry.value }
			end
		end)
	end
	if not ok then
		-- Studio without API access: show this server's players
		for _, p in Players:GetPlayers() do
			local data = DataService.get(p)
			if data then
				table.insert(rows, { name = p.DisplayName, value = boardValue(data, id) })
			end
		end
		local ascending = boardInfo[id].Ascending == true
		for i = #rows, 1, -1 do
			if rows[i].value <= 0 then
				table.remove(rows, i) -- nothing yet (e.g. no finished run)
			end
		end
		table.sort(rows, function(a, b)
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
	end
	cache[id] = { time = os.clock(), rows = rows }
	return rows
end

function QuestService.start()
	Bus.on("Joined", function(player)
		local data = DataService.get(player)
		ensureQuests(player, data)
		loginStreak(player, data)
		referral(player, data)
		PlayerService.markProfile(player)
	end)
	Bus.on("AteGerm", function(player, victim)
		if not victim.npc then
			progress(player, "EatGerms", 1)
		end
	end)
	Bus.on("AteFood", function(player, count)
		progress(player, "EatFood", count)
	end)
	Bus.on("Golden", function(player)
		progress(player, "Golden", 1)
	end)
	Bus.on("Revenge", function(player)
		progress(player, "Revenge", 1)
	end)
	Bus.on("Dash", function(player)
		progress(player, "Dash", 1)
	end)
	Bus.on("Zone", function(player, zone)
		progress(player, "Grow", nil, zone)
	end)
	Bus.on("Fever", function(player)
		progress(player, "Fever", 1)
		local data = DataService.get(player)
		if data then
			giveCard(player, data, "Bosses", "Fever")
		end
	end)
	Bus.on("Boss", function(player, kind)
		progress(player, "Boss", 1)
		local data = DataService.get(player)
		if data then
			data.BossesBeaten += 1
			if kind == "whitey" then
				giveCard(player, data, "Bosses", "Whitey")
			elseif kind == "macrophage" then
				giveCard(player, data, "Bosses", "Macrophage Mama")
			end
			if data.BossesBeaten >= 5 then
				giveCard(player, data, "Bosses", "Antibody Swarm")
			end
		end
	end)
	Bus.on("EnteredHost", function(player, host)
		local data = DataService.get(player)
		if data then
			giveCard(player, data, "Hosts", Config.CardSets.Hosts[host])
		end
	end)
	Bus.on("Sneeze", function(player, info)
		local data = DataService.get(player)
		if data and info.from >= 3 then
			giveCard(player, data, "Bosses", "Medicine Drop")
		end
	end)
	Bus.on("ArenaFloor", function(player, floor)
		local data = DataService.get(player)
		if data and floor >= 10 then
			giveCard(player, data, "Bosses", "Arena Macrophage")
		end
	end)

	Net.Quests.OnServerInvoke = function(player, action, arg)
		local data = DataService.get(player)
		local fn = type(action) == "string" and actions[action]
		if not data or not fn then
			return false, "Not ready"
		end
		local ok, message = fn(player, data, arg)
		PlayerService.markProfile(player)
		return ok, message
	end

	local boardIds = {}
	for _, lb in Config.Leaderboards do
		boardIds[lb.Id] = true
	end
	Net.Leaders.OnServerInvoke = function(_, id)
		if not boardIds[id] then
			return {}
		end
		return readBoard(id)
	end

	task.spawn(function()
		while true do
			task.wait(150)
			for _, player in Players:GetPlayers() do
				task.spawn(writeBoards, player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(writeBoards)
end

return QuestService
