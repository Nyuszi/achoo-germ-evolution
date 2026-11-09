-- The Lab: buy and level up mutations with DNA, equip them in slots, fuse two max-level
-- mutations, pick a core (body shape), spend Germ Points on skills and save loadouts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Net = require(script.Parent.Net)
local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)

local LabService = {}

local function slotsOf(fusion)
	local slots, seen = {}, {}
	for _, part in Config.Fusions[fusion].Parts do
		local slot = Config.Mutations[part].Slot
		if not seen[slot] then
			seen[slot] = true
			table.insert(slots, slot)
		end
	end
	return slots
end

-- Takes whatever is in a slot off (a fusion comes off from all its slots)
local function clearSlot(equipped, slot)
	local id = equipped[slot]
	if not id then
		return
	end
	local fusion = Config.Fusions[id] and id or (type(id) == "string" and string.sub(id, 1, 1) == "#" and string.sub(id, 2))
	if fusion and Config.Fusions[fusion] then
		for s, v in equipped do
			if v == fusion or v == "#" .. fusion then
				equipped[s] = nil
			end
		end
	else
		equipped[slot] = nil
	end
end

-- How many slots a build fills (a fusion fills each of its slots)
local function usedSlots(equipped)
	local n = 0
	for _, slot in Config.Slots do
		if equipped[slot] then
			n += 1
		end
	end
	return n
end

local function slotsFullText(data)
	local lim = Formulas.hostLimits(data.Host)
	return "Only " .. lim.slots .. (lim.slots == 1 and " mutation slot" or " mutation slots") .. " in " .. Config.Hosts[data.Host].Name
		.. ". Sneeze into the next host for more, or take one off first"
end

local actions = {}

function actions.Upgrade(player, data, id)
	local m = Config.Mutations[id]
	if not m then
		return false, "Unknown mutation"
	end
	local level = data.Levels[id] or 0
	if level >= Config.MaxMutationLevel then
		return false, m.Name .. " is already max level"
	end
	local lim = Formulas.hostLimits(data.Host)
	if level >= lim.levelCap then
		return false, "Level " .. lim.levelCap .. " is the most in " .. Config.Hosts[data.Host].Name .. ". Sneeze into the next host to go higher"
	end
	local cost = Formulas.mutationCost(id, level + 1)
	if data.Dna < cost then
		return false, "You need " .. Formulas.formatNumber(cost) .. " DNA (eat germs and food to get DNA!)"
	end
	data.Dna -= cost
	data.Levels[id] = level + 1
	if level == 0 and not data.Equipped[m.Slot] and usedSlots(data.Equipped) < lim.slots then
		data.Equipped[m.Slot] = id
	end
	return true, m.Name .. " is now level " .. (level + 1) .. "!"
end

function actions.Equip(player, data, id)
	local m = Config.Mutations[id]
	local f = Config.Fusions[id]
	if m then
		if (data.Levels[id] or 0) <= 0 then
			return false, "Unlock it first"
		end
		if data.Equipped[m.Slot] == id then
			data.Equipped[m.Slot] = nil -- tap again to take it off
			return true, m.Name .. " taken off"
		end
		if not data.Equipped[m.Slot] and usedSlots(data.Equipped) >= Formulas.hostLimits(data.Host).slots then
			return false, slotsFullText(data)
		end
		clearSlot(data.Equipped, m.Slot)
		data.Equipped[m.Slot] = id
		return true, m.Name .. " equipped!"
	elseif f then
		if not data.Fusions[id] then
			return false, "Fuse it first"
		end
		local slots = slotsOf(id)
		if data.Equipped[slots[1]] == id then
			clearSlot(data.Equipped, slots[1])
			return true, f.Name .. " taken off"
		end
		local lim = Formulas.hostLimits(data.Host)
		if not lim.fusions then
			return false, "Fusions work from host " .. Config.FusionHost .. " (" .. Config.Hosts[Config.FusionHost].Name .. ")"
		end
		local after = table.clone(data.Equipped)
		for _, slot in slots do
			clearSlot(after, slot)
		end
		if usedSlots(after) + #slots > lim.slots then
			return false, slotsFullText(data)
		end
		for i, slot in slots do
			clearSlot(data.Equipped, slot)
			data.Equipped[slot] = i == 1 and id or ("#" .. id)
		end
		return true, f.Name .. " equipped!"
	end
	return false, "Unknown item"
end

function actions.Fuse(player, data, id)
	local f = Config.Fusions[id]
	if not f then
		return false, "Unknown fusion"
	end
	if data.Fusions[id] then
		return actions.Equip(player, data, id)
	end
	for _, part in f.Parts do
		if (data.Levels[part] or 0) < Config.MaxMutationLevel then
			return false, "Get " .. Config.Mutations[part].Name .. " to level " .. Config.MaxMutationLevel .. " first"
		end
	end
	data.Fusions[id] = true
	local equipped = actions.Equip(player, data, id)
	return true, "FUSION! " .. f.Name .. " unlocked" .. (equipped and " and equipped" or "")
end

function actions.Core(player, data, id)
	local core = Config.Cores[id]
	if not core then
		return false, "Unknown core"
	end
	if data.MaxHost < core.Host and data.Mutant == 0 then
		return false, "Reach host " .. core.Host .. " (" .. Config.Hosts[core.Host].Name .. ") to unlock it"
	end
	data.Core = id
	return true, core.Name .. " core equipped"
end

function actions.Skill(player, data, id)
	local skill = Config.Skills[id]
	if not skill then
		return false, "Unknown skill"
	end
	local level = data.Skills[id] or 0
	if level >= skill.Max then
		return false, skill.Name .. " is maxed"
	end
	if data.GermPoints < 1 then
		return false, "You need a Germ Point (you get one every sneeze)"
	end
	data.GermPoints -= 1
	data.Skills[id] = level + 1
	return true, skill.Name .. " level " .. (level + 1)
end

function actions.SaveLoadout(player, data, n)
	local max = PlayerService.ownsPass(player, "ExtraLoadout") and 3 or 1
	if type(n) ~= "number" or n % 1 ~= 0 or n < 1 or n > max then
		return false, "Get the Extra Loadouts pass for 3 builds"
	end
	for i = 1, n - 1 do
		if data.Loadouts[i] == nil then
			data.Loadouts[i] = false -- keep the list without holes so it saves
		end
	end
	data.Loadouts[n] = table.clone(data.Equipped)
	return true, "Build " .. n .. " saved"
end

function actions.LoadLoadout(player, data, n)
	local saved = type(n) == "number" and data.Loadouts[n]
	if not saved then
		return false, "Nothing saved there yet"
	end
	local equipped = {}
	for slot, id in saved do
		local base = type(id) == "string" and string.gsub(id, "^#", "") or id
		if Config.Mutations[base] and (data.Levels[base] or 0) > 0 then
			equipped[slot] = id
		elseif Config.Fusions[base] and data.Fusions[base] then
			equipped[slot] = id
		end
	end
	data.Equipped = equipped
	return true, "Build " .. n .. " loaded"
end

-- arg = { slot = n, sure = bool }
function actions.NewRun(player, data, arg)
	if type(arg) ~= "table" then
		return false, "Pick a slot"
	end
	return PlayerService.switchStrain(player, arg.slot, true, arg.sure == true)
end

function actions.SwitchStrain(player, data, slot)
	return PlayerService.switchStrain(player, slot, false)
end

function LabService.start()
	Net.Lab.OnServerInvoke = function(player, action, arg)
		local data = DataService.get(player)
		local fn = type(action) == "string" and actions[action]
		if not data or not fn then
			return false, "Not ready"
		end
		local ok, message = fn(player, data, arg)
		if ok then
			PlayerService.refresh(player)
		end
		return ok, message
	end
end

return LabService
