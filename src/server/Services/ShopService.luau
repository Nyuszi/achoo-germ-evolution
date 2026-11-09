-- Robux shop (game passes and developer products) and the Germ Editor (cosmetics).
--
-- Every pass and product has an Id in Config. While an Id is 0 it is FREE inside Roblox Studio
-- (so you can test everything) and hidden in the live game. Put the real ids in Config once
-- you create the items in the Creator Hub.
--
-- Skins, bundles and flags are sold with one developer product per price ("Skin49" etc.):
-- the server remembers which item you picked (saved, so a server restart cannot lose it).
-- Nothing here is random: you always see exactly what you buy.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Flags = require(ReplicatedStorage.Shared.Flags)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local World = require(script.Parent.World)
local PlayerService = require(script.Parent.PlayerService)

local ShopService = {}

local IS_STUDIO = RunService:IsStudio()
local passCache = {} -- [player] = { [passId] = true/false }

-- Passes ------------------------------------------------------------------------------------------

function ShopService.ownsPass(player, id)
	local pass = Config.GamePasses[id]
	if not pass then
		return false
	end
	local data = DataService.get(player)
	if pass.Id == 0 then
		return IS_STUDIO and data ~= nil and data.TestPasses[id] == true
	end
	passCache[player] = passCache[player] or {}
	local cached = passCache[player][id]
	if cached == nil then
		cached = false
		passCache[player][id] = false -- not yet known: check in the background
		task.spawn(function()
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and owns and passCache[player] then
				passCache[player][id] = true
				PlayerService.refresh(player)
			end
		end)
	end
	return cached
end

-- Items (skins, bundles, flags) ---------------------------------------------------------------------

local function skinItem(cat, id)
	for _, item in Config.Skins[cat] or {} do
		if item.Id == id then
			return item
		end
	end
	return nil
end
ShopService.skinItem = skinItem

local function continentOf(id)
	for _, c in Flags.Continents do
		if c.Id == id then
			return c
		end
	end
	return nil
end

function ShopService.ownsSkin(data, cat, id)
	if cat == "Flag" then
		return id == "" or data.Flags[id] == true
	end
	local item = skinItem(cat, id)
	if not item then
		return false
	end
	return item.Free == true or data.OwnedSkins[cat .. ":" .. id] == true
end

-- What an item spec costs in Robux (nil if it cannot be bought with Robux)
local function robuxPrice(spec)
	if spec.kind == "Skin" then
		local item = skinItem(spec.cat, spec.id)
		return item and not item.Arena and item.Price or nil
	elseif spec.kind == "Bundle" then
		for _, b in Config.Bundles do
			if b.Id == spec.id then
				return b.Price
			end
		end
	elseif spec.kind == "Flag" then
		return Flags.ByCode[spec.id] and Config.FlagPrice or nil
	elseif spec.kind == "Continent" then
		return continentOf(spec.id) and Config.ContinentPackPrice or nil
	elseif spec.kind == "World" then
		return Config.WorldPackPrice
	end
	return nil
end

local function grantItem(player, data, spec)
	if spec.kind == "Skin" then
		data.OwnedSkins[spec.cat .. ":" .. spec.id] = true
		data.Skin[spec.cat] = spec.id
		return (skinItem(spec.cat, spec.id) or {}).Name or spec.id
	elseif spec.kind == "Bundle" then
		for _, b in Config.Bundles do
			if b.Id == spec.id then
				for cat, id in b.Items do
					data.OwnedSkins[cat .. ":" .. id] = true
					data.Skin[cat] = id
				end
				return b.Name
			end
		end
	elseif spec.kind == "Flag" then
		data.Flags[spec.id] = true
		data.Skin.Flag = spec.id
		return Flags.ByCode[spec.id].Name .. " flag"
	elseif spec.kind == "Continent" then
		for _, f in Flags.List do
			if f.Continent == spec.id then
				data.Flags[f.Code] = true
			end
		end
		return continentOf(spec.id).Name .. " flag pack"
	elseif spec.kind == "World" then
		for _, f in Flags.List do
			data.Flags[f.Code] = true
		end
		return "World flag pack (all 195 flags)"
	end
	return "?"
end
ShopService.grantItem = grantItem

-- Products ------------------------------------------------------------------------------------------

local productByid = {} -- [productId] = key
for key, p in Config.Products do
	if p.Id ~= 0 then
		productByid[p.Id] = key
	end
end

local handlers = {}

function handlers.Revive(player, data)
	return PlayerService.revive(player), "Revived at full size!"
end

function handlers.GrowthPotion(player, data)
	data.Potions += 1
	return true, "Growth Potion added: open the Shop to drink it"
end

local function dnaPack(key)
	return function(player, data)
		data.Dna += Config.Products[key].Dna
		return true, "+" .. Config.Products[key].Dna .. " DNA"
	end
end
handlers.DnaSmall = dnaPack("DnaSmall")
handlers.DnaMedium = dnaPack("DnaMedium")
handlers.DnaLarge = dnaPack("DnaLarge")

function handlers.ServerFever(player, data)
	local germ = PlayerService.germ(player)
	if not germ or not germ.dish or germ.dish.kind ~= "host" then
		return false, "Only inside a host"
	end
	ShopService.startFever(germ.dish, player.DisplayName)
	return true, "Fever started for everyone!"
end

function handlers.ImmuneStrike(player, data)
	local germ = PlayerService.germ(player)
	local dish = germ and germ.dish
	if not dish or dish.kind ~= "host" or not dish.crowned then
		return false, "No king to strike right now"
	end
	ShopService.immuneStrike(dish, dish.crowned, player.DisplayName)
	return true, "A white blood cell is hunting the king!"
end

local function skinHandler(player, data)
	local spec = data.PendingItem
	if not spec then
		return false, "Nothing picked"
	end
	data.PendingItem = nil
	return true, "You got " .. grantItem(player, data, spec) .. "!"
end
for key in Config.Products do
	if string.sub(key, 1, 4) == "Skin" then
		handlers[key] = skinHandler
	end
end

local function grantProduct(player, key)
	local data = DataService.get(player)
	local handler = handlers[key]
	if not data or not handler then
		return false
	end
	local ok, message = handler(player, data)
	if message then
		Net.notify(player, message, ok and "success" or "error")
	end
	PlayerService.refresh(player)
	return true -- the purchase is used up even if the effect could not happen (e.g. revive too late)
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.waitFor(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if data.Receipts[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = productByid[receipt.ProductId]
	if not key then
		warn("[Shop] Unknown product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	grantProduct(player, key)
	DataService.recordReceipt(player, receipt.PurchaseId)
	if not DataService.save(player) and not player:GetAttribute("SaveDisabled") then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Asks Roblox to sell a product (or grants it for free in Studio while its id is 0)
local function sellProduct(player, key)
	local p = Config.Products[key]
	if not p then
		return false, "Unknown product"
	end
	if p.Id == 0 then
		if IS_STUDIO then
			grantProduct(player, key)
			return true, "(Studio test: free)"
		end
		return false, "Not on sale yet"
	end
	MarketplaceService:PromptProductPurchase(player, p.Id)
	return true
end

-- Remotes -----------------------------------------------------------------------------------------

local shopActions = {}

function shopActions.BuyPass(player, data, id)
	local pass = Config.GamePasses[id]
	if not pass then
		return false, "Unknown pass"
	end
	if pass.Id == 0 then
		if IS_STUDIO then
			data.TestPasses[id] = not data.TestPasses[id] or nil
			return true, pass.Name .. (data.TestPasses[id] and " ON (Studio test)" or " OFF (Studio test)")
		end
		return false, "Not on sale yet"
	end
	if ShopService.ownsPass(player, id) then
		return false, "You already own " .. pass.Name
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	return true
end

function shopActions.BuyProduct(player, data, key)
	if type(key) ~= "string" or string.sub(key, 1, 4) == "Skin" then
		return false, "Unknown product"
	end
	return sellProduct(player, key)
end

-- spec = { kind = "Skin"|"Bundle"|"Flag"|"Continent"|"World", cat, id, dna = true to pay with DNA }
function shopActions.BuyItem(player, data, spec)
	if type(spec) ~= "table" or type(spec.kind) ~= "string" then
		return false, "Pick an item"
	end
	spec = { kind = spec.kind, cat = spec.cat, id = spec.id, dna = spec.dna }
	if spec.kind == "Skin" then
		if ShopService.ownsSkin(data, spec.cat, spec.id) then
			return false, "You own it already"
		end
		local item = skinItem(spec.cat, spec.id)
		if not item then
			return false, "Unknown item"
		end
		if item.Arena then
			return false, "Arena items come from the Arena Token shop"
		end
		if spec.dna and item.Dna then
			if data.Dna < item.Dna then
				return false, "You need " .. item.Dna .. " DNA"
			end
			data.Dna -= item.Dna
			spec.dna = nil
			local name = grantItem(player, data, spec)
			PlayerService.refresh(player)
			return true, "You got " .. name .. "!"
		end
	elseif spec.kind == "Flag" and data.Flags[spec.id] then
		return false, "You own this flag already"
	end
	local price = robuxPrice(spec)
	if not price then
		return false, "Not for sale"
	end
	spec.dna = nil
	data.PendingItem = spec
	return sellProduct(player, "Skin" .. price)
end

function shopActions.UsePotion(player, data)
	if data.Potions < 1 then
		return false, "No Growth Potions (get one from codes, invites or the shop)"
	end
	data.Potions -= 1
	data.PotionUntil = math.max(os.time(), data.PotionUntil or 0) + Config.GrowthPotionMinutes * 60
	local germ = PlayerService.germ(player)
	if germ then
		germ.potionOn = true
	end
	PlayerService.refresh(player)
	return true, "2x growth for " .. Config.GrowthPotionMinutes .. " minutes!"
end

local editorActions = {}

function editorActions.Equip(player, data, cat, id)
	if type(cat) ~= "string" or type(id) ~= "string" then
		return false
	end
	if not ShopService.ownsSkin(data, cat, id) then
		return false, "Buy it first"
	end
	data.Skin[cat] = id
	return true
end

function editorActions.Color(player, data, which, rgb)
	if (which ~= "Color" and which ~= "Color2") or type(rgb) ~= "table" then
		return false
	end
	local c = {}
	for i = 1, 3 do
		local v = tonumber(rgb[i])
		if not v or v ~= v then
			return false
		end
		c[i] = math.clamp(math.floor(v), 0, 255)
	end
	data.Skin[which] = c
	return true
end

function editorActions.SaveOutfit(player, data, n)
	if type(n) ~= "number" or n < 1 or n > Config.OutfitSlots then
		return false
	end
	for i = 1, n - 1 do
		if data.Outfits[i] == nil then
			data.Outfits[i] = false -- keep the list without holes so it saves
		end
	end
	data.Outfits[n] = table.clone(data.Skin)
	return true, "Outfit " .. n .. " saved"
end

function editorActions.LoadOutfit(player, data, n)
	local outfit = type(n) == "number" and data.Outfits[n]
	if not outfit then
		return false, "Nothing saved there yet"
	end
	for cat, id in outfit do
		if cat == "Color" or cat == "Color2" then
			data.Skin[cat] = table.clone(id)
		elseif ShopService.ownsSkin(data, cat, id) then
			data.Skin[cat] = id
		end
	end
	return true, "Outfit " .. n .. " on"
end

-- set by ImmuneService (avoids a require loop)
ShopService.startFever = function(dish, by) end
ShopService.immuneStrike = function(dish, target, by) end

function ShopService.start()
	PlayerService.ownsPass = ShopService.ownsPass
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
		if bought then
			for id, pass in Config.GamePasses do
				if pass.Id == passId then
					passCache[player] = passCache[player] or {}
					passCache[player][id] = true
					Net.notify(player, "Thanks! " .. pass.Name .. " is on", "success")
				end
			end
			PlayerService.refresh(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
	end)
	local function wire(remote, actions)
		remote.OnServerInvoke = function(player, action, a, b)
			local data = DataService.get(player)
			local fn = type(action) == "string" and actions[action]
			if not data or not fn then
				return false, "Not ready"
			end
			local ok, message = fn(player, data, a, b)
			PlayerService.refresh(player)
			return ok, message
		end
	end
	wire(Net.Shop, shopActions)
	wire(Net.Editor, editorActions)
	local _ = World
end

return ShopService
