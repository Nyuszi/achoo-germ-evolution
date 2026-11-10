-- The menus: Lab (mutations, fusions, cores, skills), Germ Editor (skins, colours, flags,
-- outfits), Shop (passes and products), Quests (daily, weekly, streak, codes, cards, invites),
-- Arena, Leaderboards, Dev (Studio / owner only) and Bugs & Ideas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Flags = require(ReplicatedStorage.Shared.Flags)
local Ui = require(script.Parent.Ui)
local Looks = require(script.Parent.Looks)
local Gear = require(script.Parent.Gear)

local Menus = {}

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local make, text, button, row, heading = Ui.make, Ui.text, Ui.button, Ui.row, Ui.heading
local profile = nil
Menus.notify = function(message, kind) end -- set by Main

local function call(remote, ...)
	local ok, message = Remotes[remote]:InvokeServer(...)
	if message then
		Menus.notify(message, ok and "success" or "error")
	end
	return ok
end

local function fmt(n)
	return Formulas.formatNumber(n)
end

-- A little germ drawn like in the game: a disc of the body colour with the face, pattern and hat
-- (Looks) on top. With a flag, the disc is the flag. size = the disc's width in pixels.
local function germPicture(parent, size, skin, pos, muts, core)
	local c = skin.Color or { 120, 220, 120 }
	local color = Color3.fromRGB(c[1], c[2], c[3])
	local flag = skin.Flag ~= nil and skin.Flag ~= ""
	local disc = make(flag and not Flags.picture(skin.Flag) and "CanvasGroup" or "Frame", { Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, BackgroundColor3 = color, ZIndex = 1, Parent = parent }, { Ui.corner(size / 2) })
	local flagImage, flagOffset, flagRect = nil, nil, nil
	if flag then
		flagImage, flagOffset, flagRect = Flags.picture(skin.Flag)
	end
	if flagImage then
		make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = flagImage, ImageRectOffset = flagOffset, ImageRectSize = flagRect, ZIndex = 1, Parent = disc }, { Ui.corner(size / 2) })
		disc = make("Frame", { Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, BackgroundTransparency = 1, ZIndex = 2, Parent = parent }, { Ui.corner(size / 2) })
	elseif flag then
		text({ Size = UDim2.fromScale(2.1, 2.1), Position = UDim2.fromScale(-0.55, -0.55), Text = Flags.emoji(skin.Flag), Parent = disc })
		disc = make("Frame", { Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, BackgroundTransparency = 1, ZIndex = 2, Parent = parent }, { Ui.corner(size / 2) })
	end
	-- a soft outline, like the body's rim in the game
	make("UIStroke", { Thickness = math.max(1, size / 30), Color = color:Lerp(Color3.new(0, 0, 0), 0.45), Transparency = 0.2, Parent = disc })
	if muts and Gear.mouthless(muts) then
		skin = table.clone(skin)
		skin.Mouth = "None"
	end
	Looks.build(disc, { skin = skin, color = color, flag = flag })
	-- Lab mutations, swimming up the screen (front at the top)
	local gear = muts and Gear.build(disc, muts, color, core)
	if gear then
		Gear.animate(gear, 0, 0.3, { dx = 0, dz = -1 })
	end
	return disc
end

-- Lab ---------------------------------------------------------------------------------------------

local lab = Ui.panel("Lab", "🧪 The Lab")
local function statText(id, level)
	local m = Config.Mutations[id]
	local bits = { m.Text }
	local function stat(key, label, pct)
		if m[key] then
			local v = Formulas.mutationStat(id, key, math.max(level, 1))
			if pct then
				table.insert(bits, string.format("%s %+d%%", label, math.floor(v * 100 + 0.5)))
			else
				table.insert(bits, string.format("%s %+g", label, v))
			end
		end
	end
	stat("Bite", "bite", true)
	stat("Speed", "speed", true)
	stat("Armor", "armour", true)
	stat("Pierce", "pierce", true)
	stat("Absorb", "food", true)
	stat("DashMult", "dash", true)
	stat("Trail", "slow", true)
	stat("Thorns", "thorns", true)
	stat("Poison", "poison", true)
	if m.Active then
		table.insert(bits, m.ActiveText .. (m.Slot == "Front" and " [Q]" or " [E]"))
	end
	return table.concat(bits, " · ")
end

local function equippedIn(id)
	for _, v in profile.Equipped do
		if v == id then
			return true
		end
	end
	return false
end

-- a row picture: a plain germ in your colour wearing these mutations
local function labPicture(muts, core)
	return function(box)
		local c = profile.Skin.Color or { 120, 220, 120 }
		germPicture(box, 30, { Color = c, Eyes = "Cute", Mouth = "Smile" }, UDim2.fromScale(0.5, 0.55), muts, core)
	end
end

local confirmSlot = nil -- a New Run that would wipe a strain needs a second tap
local refreshLab
function refreshLab()
	if not profile then
		return
	end
	lab.clear()
	lab.sub.Text = "🧬 " .. fmt(profile.Dna) .. " DNA   ⭐ " .. profile.GermPoints .. " Germ Points"
	local tab = lab.tab or "Mutations"
	local n = 0
	local function nextN()
		n += 1
		return n
	end
	local lim = Formulas.hostLimits(profile.Host)
	if tab == "Mutations" or tab == "Fusions" or tab == "Cores" then
		-- your germ with everything it wears now
		local top = make("Frame", { Size = UDim2.new(1, -10, 0, 128), BackgroundColor3 = Ui.ROW, LayoutOrder = nextN(), ZIndex = 12, Parent = lab.list }, { Ui.corner(10) })
		germPicture(top, 64, profile.Skin, UDim2.new(0, 70, 0.52, 0), profile.Equipped, profile.Core)
		text({ Size = UDim2.new(1, -150, 0, 30), Position = UDim2.new(0, 135, 0, 20), Text = "Your germ", ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = top })
		text({ Size = UDim2.new(1, -150, 0, 44), Position = UDim2.new(0, 135, 0, 56), Text = "Swimming up. In the game your mutations move: jaws chew, tails whip, jets flame, and abilities show.", TextWrapped = true, TextScaled = true, ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(215, 205, 230), Parent = top })
	end
	if tab == "Mutations" then
		local hostName = Config.Hosts[profile.Host].Name
		heading(lab.list, nextN(), "In " .. hostName .. ": " .. lim.slots .. (lim.slots == 1 and " slot" or " slots") .. ", levels up to " .. lim.levelCap
			.. (lim.slots < #Config.Slots and "  ·  sneeze to unlock more 🔓" or ""))
		local used = 0
		for _, slot in Config.Slots do
			if profile.Equipped[slot] then
				used += 1
			end
		end
		for _, slot in Config.Slots do
			local now = profile.Equipped[slot]
			local nowName = "empty"
			if now then
				local base = string.gsub(now, "^#", "")
				nowName = (Config.Mutations[base] or Config.Fusions[base] or { Name = base }).Name
			elseif used >= lim.slots then
				nowName = "empty (all " .. lim.slots .. " in use)"
			end
			heading(lab.list, nextN(), slot .. " slot: " .. nowName)
			for _, id in Config.MutationOrder do
				local m = Config.Mutations[id]
				if m.Slot == slot then
					local level = profile.Levels[id] or 0
					local buttons = {}
					if level >= lim.levelCap and level < Config.MaxMutationLevel then
						table.insert(buttons, { "🔒 Lv" .. (level + 1), Ui.GREY, function()
							Menus.notify("Level " .. (level + 1) .. " unlocks in a later host. Sneeze to get there!", "info")
						end })
					elseif level < Config.MaxMutationLevel then
						local cost = Formulas.mutationCost(id, level + 1)
						table.insert(buttons, { (level == 0 and "Buy " or "Lv" .. (level + 1) .. " ") .. fmt(cost), profile.Dna >= cost and Ui.GOOD or Ui.GREY, function()
							call("Lab", "Upgrade", id)
						end })
					end
					if level > 0 then
						local on = equippedIn(id)
						table.insert(buttons, { on and "Take off" or "Equip", on and Ui.GOLD or Ui.BLUE, function()
							call("Lab", "Equip", id)
						end })
					end
					local stars = string.rep("●", level) .. string.rep("○", Config.MaxMutationLevel - level)
					row(lab.list, nextN(), m.Name .. "  " .. stars, statText(id, level), buttons, labPicture({ [slot] = id }))
				end
			end
		end
	elseif tab == "Fusions" then
		heading(lab.list, nextN(), lim.fusions and "Get two mutations to level 5 to fuse them into a combo"
			or ("🔒 Fusions work from host " .. Config.FusionHost .. " (" .. Config.Hosts[Config.FusionHost].Name .. ")"))
		for _, id in Config.FusionOrder do
			local f = Config.Fusions[id]
			local parts = {}
			local ready = true
			for _, p in f.Parts do
				local level = profile.Levels[p] or 0
				table.insert(parts, Config.Mutations[p].Name .. " " .. level .. "/5")
				if level < 5 then
					ready = false
				end
			end
			local owned = profile.Fusions[id]
			local label = owned and (equippedIn(id) and "Take off" or "Equip") or "Fuse"
			row(lab.list, nextN(), f.Name, f.Text .. "  (" .. table.concat(parts, " + ") .. ")", {
				{ label, (owned or ready) and Ui.GOOD or Ui.GREY, function()
					call("Lab", owned and "Equip" or "Fuse", id)
				end },
			}, labPicture({ Front = id, Back = "#" .. id }))
		end
	elseif tab == "Cores" then
		heading(lab.list, nextN(), "Your germ's body shape. Unlock one by reaching its host")
		for _, id in Config.CoreOrder do
			local c = Config.Cores[id]
			local unlocked = profile.MaxHost >= c.Host or profile.Mutant > 0
			local on = profile.Core == id
			row(lab.list, nextN(), c.Name .. (on and "  ✓" or ""), c.Text .. (unlocked and "" or ("  🔒 reach " .. Config.Hosts[c.Host].Name)), {
				{ on and "Equipped" or "Use", unlocked and (on and Ui.GOLD or Ui.BLUE) or Ui.GREY, function()
					call("Lab", "Core", id)
				end },
			})
		end
	elseif tab == "Skills" then
		heading(lab.list, nextN(), "Germ Points: you get 1 every sneeze. Skills are forever")
		for _, id in Config.SkillOrder do
			local s = Config.Skills[id]
			local level = profile.Skills[id] or 0
			row(lab.list, nextN(), s.Name .. "  " .. level .. "/" .. s.Max, s.Text, {
				{ level >= s.Max and "Max" or "+1 (1 ⭐)", (profile.GermPoints > 0 and level < s.Max) and Ui.GOOD or Ui.GREY, function()
					call("Lab", "Skill", id)
				end },
			})
		end
	elseif tab == "Runs" then
		local run = Formulas.formatTime(profile.RunSeconds or 0)
		heading(lab.list, nextN(), "⏱️ This run: " .. (profile.RunValid and run or (run .. " (finish it, the next one is timed)"))
			.. "   🏁 Best: " .. ((profile.BestRun or 0) > 0 and Formulas.formatTime(profile.BestRun) or "none yet"))
		heading(lab.list, nextN(), "New Run = a fresh build from host 1. Your other strains stay saved here")
		for i, st in profile.Strains or {} do
			local name = Config.StrainNames[i] or ("Strain " .. i)
			if st then
				local info = "Host " .. st.host .. " " .. st.hostName .. " · " .. (st.muts ~= "" and st.muts or "no mutations") .. " · " .. st.runs .. (st.runs == 1 and " run" or " runs")
				local buttons = {}
				if st.active then
					table.insert(buttons, { "Playing", Ui.GOLD, function() end })
				else
					table.insert(buttons, { "Play", Ui.GOOD, function()
						call("Lab", "SwitchStrain", i)
					end })
				end
				table.insert(buttons, { confirmSlot == i and "Sure?" or "New Run", confirmSlot == i and Ui.BAD or Ui.BLUE, function()
					if confirmSlot == i then
						confirmSlot = nil
						call("Lab", "NewRun", { slot = i, sure = true })
					else
						confirmSlot = i
						Menus.notify("This wipes " .. name .. "'s mutations (DNA, skills and looks stay). Tap Sure? to do it", "info")
						refreshLab()
					end
				end })
				row(lab.list, nextN(), name .. (st.active and "  ✓" or ""), info, buttons, "🧫")
			else
				row(lab.list, nextN(), name, "empty slot", { { "New Run", Ui.BLUE, function()
					call("Lab", "NewRun", { slot = i })
				end } }, "🧫")
			end
		end
		heading(lab.list, nextN(), "Fair play")
		row(lab.list, nextN(), "🌱 Rookies", "Players on their first run. Once you finish a run you can't eat or bite them in hosts", {})
		row(lab.list, nextN(), "🔓 Unlocks per host", "Host 1 gives " .. Config.SlotsPerHost[1] .. " mutation slots. More slots, higher levels, fusions and a bigger DNA bag come as you sneeze on", {})
	elseif tab == "Builds" then
		local slots = profile.Passes.ExtraLoadout and 3 or 1
		heading(lab.list, nextN(), slots == 1 and "Save your build (3 builds with the Extra Loadouts pass)" or "Save up to 3 builds")
		for i = 1, 3 do
			local saved = profile.Loadouts[i]
			local names = {}
			for _, id in saved or {} do
				if string.sub(id, 1, 1) ~= "#" then
					table.insert(names, (Config.Mutations[id] or Config.Fusions[id] or { Name = id }).Name)
				end
			end
			row(lab.list, nextN(), "Build " .. i, saved and table.concat(names, ", ") or "empty", {
				{ "Save", i <= slots and Ui.BLUE or Ui.GREY, function()
					call("Lab", "SaveLoadout", i)
				end },
				{ "Load", saved and Ui.GOOD or Ui.GREY, function()
					call("Lab", "LoadLoadout", i)
				end },
			})
		end
	end
end
lab.setTabs({ "Mutations", "Fusions", "Cores", "Skills", "Builds", "Runs" }, refreshLab)
lab.tab = "Mutations"
lab.onOpen = refreshLab

-- Germ Editor ------------------------------------------------------------------------------------

local editor = Ui.panel("Editor", "🎨 Germ Editor")
local PALETTE = {
	{ 120, 220, 120 }, { 110, 200, 255 }, { 255, 150, 200 }, { 255, 210, 90 }, { 190, 140, 255 }, { 255, 140, 100 },
	{ 100, 230, 210 }, { 240, 120, 140 }, { 170, 230, 90 }, { 255, 255, 255 }, { 60, 60, 70 }, { 255, 80, 80 },
	{ 80, 120, 255 }, { 255, 170, 40 }, { 150, 90, 60 }, { 255, 105, 180 }, { 0, 200, 120 }, { 140, 0, 200 },
	{ 255, 240, 200 }, { 20, 140, 160 }, { 200, 255, 60 }, { 255, 60, 160 }, { 120, 120, 140 }, { 255, 215, 0 },
}
local flagFilter = ""
local flagContinent = nil

local function ownsSkin(cat, id)
	if cat == "Flag" then
		return id == "" or profile.Flags[id] == true
	end
	for _, item in Config.Skins[cat] do
		if item.Id == id then
			return item.Free == true or profile.OwnedSkins[cat .. ":" .. id] == true
		end
	end
	return false
end


-- The player's look with one item swapped in
local function withItem(cat, id)
	local skin = table.clone(profile.Skin)
	skin[cat] = id
	if cat ~= "Flag" then
		skin.Flag = ""
	end
	return skin
end

local LOOK_TABS = { Body = true, Pattern = true, Eyes = true, Mouth = true, Hat = true, Flag = true, Colors = true, Outfits = true }

-- Owns every flag in a continent (id) or in the world (id = nil)
local function ownsFlags(continent)
	for _, f in Flags.List do
		if (not continent or f.Continent == continent) and not profile.Flags[f.Code] then
			return false
		end
	end
	return true
end

local function ownsBundle(b)
	for cat, id in b.Items do
		if not ownsSkin(cat, id) then
			return false
		end
	end
	return true
end

local function refreshEditor()
	if not profile then
		return
	end
	editor.clear()
	editor.sub.Text = "Looks only, no stats. Bought items are yours forever.  🧬 " .. fmt(profile.Dna) .. " DNA"
	local tab = editor.tab or "Body"
	local n = 0
	local function nextN()
		n += 1
		return n
	end
	if LOOK_TABS[tab] then
		-- your germ as it looks right now
		local top = make("Frame", { Size = UDim2.new(1, -10, 0, 128), BackgroundColor3 = Ui.ROW, LayoutOrder = nextN(), ZIndex = 12, Parent = editor.list }, { Ui.corner(10) })
		germPicture(top, 86, profile.Skin, UDim2.new(0, 66, 0.56, 0))
		text({ Size = UDim2.new(1, -150, 0, 30), Position = UDim2.new(0, 135, 0, 20), Text = "Your germ", ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = top })
		text({ Size = UDim2.new(1, -150, 0, 44), Position = UDim2.new(0, 135, 0, 56), Text = "Seen from above, like in the game. Eyes follow where you swim.", TextWrapped = true, TextScaled = true, ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(215, 205, 230), Parent = top })
	end
	if tab == "Colors" then
		for _, which in { "Color", "Color2" } do
			heading(editor.list, nextN(), which == "Color" and "Main colour (free)" or "Pattern colour (free)")
			local grid = make("Frame", { Size = UDim2.new(1, -10, 0, 110), BackgroundTransparency = 1, LayoutOrder = nextN(), ZIndex = 12, Parent = editor.list }, {
				make("UIGridLayout", { CellSize = UDim2.fromOffset(40, 40), CellPadding = UDim2.fromOffset(6, 6) }),
			})
			for _, c in PALETTE do
				local b = make("TextButton", { Text = "", BackgroundColor3 = Color3.fromRGB(c[1], c[2], c[3]), ZIndex = 13, Parent = grid }, { Ui.corner(20), Ui.stroke(2) })
				b.Activated:Connect(function()
					call("Editor", "Color", which, c)
				end)
			end
		end
		-- free RGB picker
		heading(editor.list, nextN(), "Any colour: type R, G, B (0-255)")
		local box = make("TextBox", { Size = UDim2.new(1, -140, 0, 44), Text = "", PlaceholderText = "e.g. 255, 100, 30", Font = Ui.FONT, TextSize = 22, BackgroundColor3 = Color3.fromRGB(240, 235, 250), TextColor3 = Color3.fromRGB(40, 25, 50), LayoutOrder = nextN(), ZIndex = 12, ClearTextOnFocus = false, Parent = editor.list }, { Ui.corner(10) })
		button({ Size = UDim2.new(0, 130, 0, 44), Text = "Use colour", BackgroundColor3 = Ui.GOOD, LayoutOrder = nextN(), ZIndex = 12, Parent = editor.list }, function()
			local r, g, b = string.match(box.Text, "(%d+)%D+(%d+)%D+(%d+)")
			if r then
				call("Editor", "Color", "Color", { tonumber(r), tonumber(g), tonumber(b) })
			else
				Menus.notify("Type three numbers like 255, 100, 30", "error")
			end
		end)
	elseif tab == "Flag" then
		heading(editor.list, nextN(), "195 country flags: " .. Config.FlagPrice .. " R$ each, a continent " .. Config.ContinentPackPrice .. " R$, the whole world " .. Config.WorldPackPrice .. " R$")
		local search = make("TextBox", { Size = UDim2.new(1, -10, 0, 40), Text = flagFilter, PlaceholderText = "Search a country...", Font = Ui.FONT, TextSize = 22, BackgroundColor3 = Color3.fromRGB(240, 235, 250), TextColor3 = Color3.fromRGB(40, 25, 50), LayoutOrder = nextN(), ZIndex = 12, ClearTextOnFocus = false, Parent = editor.list }, { Ui.corner(10) })
		search.FocusLost:Connect(function()
			flagFilter = search.Text
			refreshEditor()
		end)
		row(editor.list, nextN(), "No flag", profile.Skin.Flag == "" and "✓ on" or "", { { profile.Skin.Flag == "" and "On" or "Use", profile.Skin.Flag == "" and Ui.GOLD or Ui.BLUE, function()
			call("Editor", "Equip", "Flag", "")
		end } }, "🏳️")
		local allFlags = ownsFlags(nil)
		row(editor.list, nextN(), "🌍 World Pack" .. (allFlags and "  ✓" or ""), allFlags and "You own every flag" or "Every flag on Earth", { allFlags and { "Owned", Ui.GREY } or { Config.WorldPackPrice .. " R$", Ui.GOLD, function()
			call("Shop", "BuyItem", { kind = "World" })
		end } })
		for _, c in Flags.Continents do
			local owned = ownsFlags(c.Id)
			row(editor.list, nextN(), c.Name .. " pack" .. (owned and "  ✓" or ""), flagContinent == c.Id and "showing" or (owned and "owned · tap Show to filter" or "tap Show to filter"), {
				{ "Show", flagContinent == c.Id and Ui.GOLD or Ui.BLUE, function()
					flagContinent = flagContinent ~= c.Id and c.Id or nil
					refreshEditor()
				end },
				owned and { "Owned", Ui.GREY } or { Config.ContinentPackPrice .. " R$", Ui.GOLD, function()
					call("Shop", "BuyItem", { kind = "Continent", id = c.Id })
				end },
			})
		end
		local filter = string.lower(flagFilter)
		for _, f in Flags.List do
			if (filter == "" or string.find(string.lower(f.Name), filter, 1, true)) and (not flagContinent or f.Continent == flagContinent) then
				local owned = profile.Flags[f.Code]
				local on = profile.Skin.Flag == f.Code
				row(editor.list, nextN(), f.Name, on and "✓ wearing" or (owned and "owned" or ""), {
					owned and { on and "On" or "Wear", on and Ui.GOLD or Ui.BLUE, function()
						call("Editor", "Equip", "Flag", f.Code)
					end } or { Config.FlagPrice .. " R$", Ui.GOLD, function()
						call("Shop", "BuyItem", { kind = "Flag", id = f.Code })
					end },
				}, Flags.picture(f.Code) and function(box)
					local image, offset, rect = Flags.picture(f.Code)
					make("ImageLabel", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(2, 2), BackgroundTransparency = 1, Image = image, ImageRectOffset = offset, ImageRectSize = rect, ZIndex = 13, Parent = box }, { Ui.corner(20) })
				end or Flags.emoji(f.Code))
			end
		end
	elseif tab == "Outfits" then
		heading(editor.list, nextN(), "Save your look and swap any time")
		for i = 1, Config.OutfitSlots do
			local o = profile.Outfits[i]
			row(editor.list, nextN(), "Outfit " .. i, o and (o.Body .. ", " .. o.Pattern .. ", " .. o.Hat) or "empty", {
				{ "Save", Ui.BLUE, function()
					call("Editor", "SaveOutfit", i)
				end },
				{ "Wear", o and Ui.GOOD or Ui.GREY, function()
					call("Editor", "LoadOutfit", i)
				end },
			})
		end
		heading(editor.list, nextN(), "Bundles")
		for _, b in Config.Bundles do
			local parts = {}
			for cat, id in b.Items do
				table.insert(parts, id)
			end
			local owned = ownsBundle(b)
			row(editor.list, nextN(), b.Name .. (owned and "  ✓" or ""), table.concat(parts, ", "), { owned and { "Owned", Ui.GREY } or { b.Price .. " R$", Ui.GOLD, function()
				call("Shop", "BuyItem", { kind = "Bundle", id = b.Id })
			end } })
		end
	else
		local cat = tab == "Sneeze" and "SneezeFx" or tab
		for _, item in Config.Skins[cat] or {} do
			local owned = ownsSkin(cat, item.Id)
			local on = profile.Skin[cat] == item.Id
			local buttons = {}
			local info = ""
			if owned then
				table.insert(buttons, { on and "On" or "Wear", on and Ui.GOLD or Ui.BLUE, function()
					call("Editor", "Equip", cat, item.Id)
				end })
				info = item.Free and "free" or "owned"
			elseif item.Arena then
				info = "Arena Token shop only"
			else
				if item.Dna then
					table.insert(buttons, { fmt(item.Dna) .. " DNA", profile.Dna >= item.Dna and Ui.GOOD or Ui.GREY, function()
						call("Shop", "BuyItem", { kind = "Skin", cat = cat, id = item.Id, dna = true })
					end })
				end
				if item.Price then
					table.insert(buttons, { item.Price .. " R$", Ui.GOLD, function()
						call("Shop", "BuyItem", { kind = "Skin", cat = cat, id = item.Id })
					end })
				end
			end
			local swatch = nil
			if cat == "Pattern" or cat == "Eyes" or cat == "Mouth" or cat == "Hat" or cat == "Body" then
				local skin = withItem(cat, item.Id)
				swatch = function(box)
					-- hats stick out above the head, so those germs sit a bit lower and smaller
					local hat = skin.Hat ~= nil and skin.Hat ~= "None"
					germPicture(box, hat and 32 or 40, skin, UDim2.fromScale(0.5, hat and 0.62 or 0.5))
				end
			end
			row(editor.list, nextN(), item.Name .. (on and "  ✓" or ""), info, buttons, swatch)
		end
	end
end
editor.setTabs({ "Body", "Pattern", "Eyes", "Mouth", "Hat", "Trail", "Sneeze", "Flag", "Colors", "Outfits" }, refreshEditor)
editor.tab = "Body"
editor.onOpen = refreshEditor

-- Shop -------------------------------------------------------------------------------------------

local shop = Ui.panel("Shop", "🛒 Shop")
local function refreshShop()
	if not profile then
		return
	end
	shop.clear()
	shop.sub.Text = profile.Studio and "Studio test: items with id 0 are free here" or "Boosts work in hosts only (never in the Arena)"
	local n = 0
	local function nextN()
		n += 1
		return n
	end
	heading(shop.list, nextN(), "🧪 Growth Potions: " .. profile.Potions)
	row(shop.list, nextN(), "Drink a Growth Potion", "2x growth for " .. Config.GrowthPotionMinutes .. " minutes", { { "Drink", profile.Potions > 0 and Ui.GOOD or Ui.GREY, function()
		call("Shop", "UsePotion")
	end } })
	heading(shop.list, nextN(), "Game passes (yours forever)")
	for _, id in Config.GamePassOrder do
		local p = Config.GamePasses[id]
		if p.Id ~= 0 or profile.Studio then
			local owned = profile.Passes[id]
			-- owned passes can't be bought again (in Studio, a free test pass can be turned off)
			local canToggle = profile.Studio and p.Id == 0
			row(shop.list, nextN(), p.Name .. (owned and "  ✓" or ""), p.Text, { { owned and (canToggle and "Turn off" or "Owned") or (p.Price .. " R$"), owned and Ui.GREY or Ui.GOLD, (not owned or canToggle) and function()
				call("Shop", "BuyPass", id)
			end or nil } })
		end
	end
	heading(shop.list, nextN(), "Items")
	for _, id in Config.ProductOrder do
		local p = Config.Products[id]
		if (p.Id ~= 0 or profile.Studio) and id ~= "Revive" then
			row(shop.list, nextN(), p.Name, p.Text or ("+" .. (p.Dna or 0) .. " DNA"), { { p.Price .. " R$", Ui.GOLD, function()
				call("Shop", "BuyProduct", id)
			end } })
		end
	end
end
shop.onOpen = refreshShop

-- Quests -----------------------------------------------------------------------------------------

local quests = Ui.panel("Quests", "📜 Quests")
local function questText(q)
	local def
	for _, d in Config.DailyQuests do
		if d.Id == q.Id then
			def = d
		end
	end
	if q.Id == "Grow" then
		return string.format(def.Text, "zone " .. q.Goal), def.Dna
	end
	return string.format(def.Text, q.Goal), def.Dna
end

local function refreshQuests()
	if not profile then
		return
	end
	quests.clear()
	local tab = quests.tab or "Daily"
	quests.sub.Text = "🔥 Login streak: day " .. (profile.Streak.Count or 0)
	local n = 0
	local function nextN()
		n += 1
		return n
	end
	if tab == "Daily" then
		heading(quests.list, nextN(), "Today's quests (new ones every day)")
		for i, q in profile.Quests.List or {} do
			local label, dna = questText(q)
			local done = q.Progress >= q.Goal
			row(quests.list, nextN(), label, math.min(q.Progress, q.Goal) .. " / " .. q.Goal .. "  ·  +" .. dna .. " DNA", {
				{ q.Claimed and "Claimed" or (done and "Claim" or "..."), (done and not q.Claimed) and Ui.GOOD or Ui.GREY, function()
					call("Quests", "Claim", i)
				end },
			})
		end
		heading(quests.list, nextN(), "Weekly")
		local w = profile.Quests.Weekly or 0
		row(quests.list, nextN(), "Finish " .. Config.WeeklySteps .. " daily quests this week", w .. " / " .. Config.WeeklySteps .. "  ·  +500 DNA and a card", {
			{ profile.Quests.WeeklyClaimed and "Claimed" or (w >= Config.WeeklySteps and "Claim" or "..."), (w >= Config.WeeklySteps and not profile.Quests.WeeklyClaimed) and Ui.GOOD or Ui.GREY, function()
				call("Quests", "ClaimWeekly")
			end },
		})
		heading(quests.list, nextN(), "Codes")
		local box = make("TextBox", { Size = UDim2.new(1, -10, 0, 44), Text = "", PlaceholderText = "Type a code (try ACHOO)", Font = Ui.FONT, TextSize = 22, BackgroundColor3 = Color3.fromRGB(240, 235, 250), TextColor3 = Color3.fromRGB(40, 25, 50), LayoutOrder = nextN(), ZIndex = 12, ClearTextOnFocus = false, Parent = quests.list }, { Ui.corner(10) })
		button({ Size = UDim2.new(1, -10, 0, 44), Text = "Redeem", BackgroundColor3 = Ui.GOOD, LayoutOrder = nextN(), ZIndex = 12, Parent = quests.list }, function()
			call("Quests", "Redeem", box.Text)
		end)
		heading(quests.list, nextN(), "Invite friends")
		row(quests.list, nextN(), "Invite a friend", "You both get a Growth Potion when they join", { { "Invite", Ui.BLUE, function()
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		end } })
	else
		for set, names in Config.CardSets do
			local have = 0
			for _, name in names do
				if profile.Cards[name] then
					have += 1
				end
			end
			local reward = Config.CardSetRewards[set]
			heading(quests.list, nextN(), set .. " cards " .. have .. "/" .. #names .. "  (set reward: " .. reward .. ")")
			for _, name in names do
				row(quests.list, nextN(), (profile.Cards[name] and "🃏 " or "❔ ") .. name, profile.Cards[name] and "collected" or "not found yet", {})
			end
			row(quests.list, nextN(), "Claim set reward", reward, { { profile.CardSetsClaimed[set] and "Claimed" or (have == #names and "Claim" or (have .. "/" .. #names)), (have == #names and not profile.CardSetsClaimed[set]) and Ui.GOOD or Ui.GREY, function()
				call("Quests", "ClaimSet", set)
			end } })
		end
	end
end
quests.setTabs({ "Daily", "Cards" }, refreshQuests)
quests.tab = "Daily"
quests.onOpen = function()
	refreshQuests()
	if not quests.asked then
		quests.asked = true
		task.spawn(function()
			Remotes.Quests:InvokeServer("Refresh") -- fresh progress numbers
			task.wait(2)
			quests.asked = false
		end)
	end
end

-- Arena --------------------------------------------------------------------------------------------

local arena = Ui.panel("Arena", "🏟️ The Infinite Petri")
local inArena = false
local function refreshArena()
	if not profile then
		return
	end
	arena.clear()
	local days = math.floor((profile.SeasonLeft or 0) / 86400)
	arena.sub.Text = "Season " .. (profile.Season or 1) .. " ends in " .. days .. " days  ·  🎟️ " .. profile.Tokens .. " tokens"
	local n = 0
	local function nextN()
		n += 1
		return n
	end
	if not profile.ArenaUnlocked then
		heading(arena.list, nextN(), "🔒 Finish all 6 hosts once (Mutant I) to unlock the Arena")
		row(arena.list, nextN(), "How it works", "Everyone starts each floor equal. Reach size " .. Config.Arena.GoalSize .. " and touch the Exit Pore to go down a floor", {})
		return
	end
	row(arena.list, nextN(), "Rank: " .. profile.Rank, "Best this season: floor " .. profile.ArenaBest .. "  ·  best ever: " .. profile.ArenaBestEver .. "  ·  continue from floor " .. profile.ArenaFloor, {
		inArena and { "Leave", Ui.BAD, function()
			call("Arena", "Leave")
		end } or { "Enter", Ui.GOOD, function()
			if call("Arena", "Enter") then
				Ui.close()
			end
		end },
	})
	heading(arena.list, nextN(), "Rules")
	row(arena.list, nextN(), "Clear a floor", "Reach size " .. Config.Arena.GoalSize .. " and touch the Exit Pore (+" .. Config.Arena.TokensPerFloor .. " tokens)", {})
	row(arena.list, nextN(), "Checkpoints", "Eaten? You go back to your last checkpoint (every " .. Config.Arena.CheckpointEvery .. " floors)", {})
	row(arena.list, nextN(), "Fair fights", "Paid boosts are off. Mutation levels are capped on early floors, fusions from floor " .. Config.Arena.FusionFloor, {})
	heading(arena.list, nextN(), "Token shop (Arena-only looks, never sold for Robux)")
	for i, item in Config.Arena.TokenShop do
		local owned = profile.OwnedSkins[item.Kind .. ":" .. item.Id]
		row(arena.list, nextN(), item.Id .. " (" .. item.Kind .. ")", owned and "owned" or (item.Cost .. " tokens"), { { owned and "Owned" or "Buy", owned and Ui.GREY or Ui.GOLD, function()
			call("Arena", "Buy", i)
		end } })
	end
end
arena.onOpen = refreshArena
function Menus.setMode(mode)
	inArena = mode == "arena"
end

-- Leaderboards ---------------------------------------------------------------------------------------

local leaders = Ui.panel("Leaders", "🏆 Leaderboards")
local function refreshLeaders()
	leaders.clear()
	local id = leaders.tab or Config.Leaderboards[1].Tab
	for _, lb in Config.Leaderboards do
		if lb.Tab == id then
			leaders.sub.Text = "Loading..."
			task.spawn(function()
				local rows = Remotes.Leaders:InvokeServer(lb.Id)
				leaders.clear()
				leaders.sub.Text = lb.Name
				for i, r in rows do
					row(leaders.list, i, i .. ". " .. r.name, lb.Time and Formulas.formatTime(r.value) or fmt(r.value), {})
				end
				if #rows == 0 then
					row(leaders.list, 1, "Nobody yet", "Be the first!", {})
				end
			end)
		end
	end
end
local names = {}
for _, lb in Config.Leaderboards do
	table.insert(names, lb.Tab)
end
leaders.setTabs(names, refreshLeaders)
leaders.tab = names[1]
leaders.onOpen = refreshLeaders

-- Dev ------------------------------------------------------------------------------------------------

local dev = Ui.panel("Dev", "🛠 Dev / test")
local DEV = {
	{ "SneezeSize", "Grow to the goal size next to the middle" },
	{ "Grow", "Double my size" },
	{ "NextHost", "Sneeze into the next host now" },
	{ "Host1", "Go to host 1" }, { "Host3", "Go to host 3" }, { "Host6", "Go to host 6" },
	{ "Dna", "+10,000 DNA" },
	{ "MaxLab", "All mutations to level 5" },
	{ "GermPoints", "+5 Germ Points" },
	{ "Mutant", "+1 Mutant tier (unlocks the Arena)" },
	{ "Tokens", "+500 Arena Tokens" },
	{ "ArenaFloor", "Arena: skip 9 floors" },
	{ "Hazard", "Start this host's hazard" },
	{ "Whitey", "Whitey hunts me" },
	{ "Macrophage", "Spawn Macrophage Mama" },
	{ "Fever", "Start a Fever" },
	{ "Medicine", "Start Medicine (walls close in)" },
	{ "Golden", "Spawn golden food" },
	{ "EndQuarantine", "End my quarantine" },
	{ "CompleteQuests", "Finish today's quests" },
	{ "Reset", "Wipe my progress" },
}
dev.onOpen = function()
	dev.clear()
	dev.sub.Text = "Only you see this (Studio or the game owner)"
	for i, d in DEV do
		local cmd, arg = d[1], nil
		local hostN = string.match(cmd, "^Host(%d)$")
		if hostN then
			cmd, arg = "Host", tonumber(hostN)
		end
		row(dev.list, i, d[1], d[2], { { "Run", cmd == "Reset" and Ui.BAD or Ui.BLUE, function()
			call("Dev", cmd, arg)
		end } })
	end
end

-- Bugs & Ideas -------------------------------------------------------------------------------------

local feedback = Ui.panel("Feedback", "💬 Bugs & Ideas")
feedback.onOpen = function()
	feedback.clear()
	feedback.sub.Text = "Tell us what broke or what you'd love to see"
	local box = make("TextBox", { Size = UDim2.new(1, -10, 0, 150), Text = "", PlaceholderText = "Type here...", Font = Ui.FONT, TextSize = 20, TextWrapped = true, MultiLine = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, BackgroundColor3 = Color3.fromRGB(240, 235, 250), TextColor3 = Color3.fromRGB(40, 25, 50), LayoutOrder = 1, ZIndex = 12, ClearTextOnFocus = false, Parent = feedback.list }, { Ui.corner(10) })
	for i, kind in { "Bug", "Idea" } do
		button({ Size = UDim2.new(1, -10, 0, 44), Text = "Send as " .. kind, BackgroundColor3 = kind == "Bug" and Ui.BAD or Ui.GOOD, LayoutOrder = 1 + i, ZIndex = 12, Parent = feedback.list }, function()
			local ok, message = Remotes.SendFeedback:InvokeServer(kind, box.Text)
			Menus.notify(message or (ok and "Thanks!" or "Could not send"), ok and "success" or "error")
			if ok then
				box.Text = ""
				Ui.close()
			end
		end)
	end
end

-- Menu buttons -------------------------------------------------------------------------------------

-- the bar scales with the screen so it fits on phones too. On PC, Roblox's chat window is moved to
-- the bottom left (see Main), so the bar stays in the upper part of the screen, clear of it.
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local bar = make("Frame", { Size = UDim2.new(0, 112, touchOnly and 0.64 or 0.42, 0), Position = UDim2.new(0, 10, 0.2, 0), BackgroundTransparency = 1, Parent = Ui.gui }, {
	make("UIListLayout", { Padding = UDim.new(0, 5) }),
	make("UISizeConstraint", { MaxSize = Vector2.new(112, 430) }),
})
local menuButtons = {}
local function menuButton(name, label, color, order)
	menuButtons[name] = button({ Size = UDim2.new(1, 0, 0.125, -5), Text = label, BackgroundColor3 = color, LayoutOrder = order, Parent = bar }, function()
		Ui.open(name)
	end)
end
menuButton("Lab", "🧪 Lab", Color3.fromRGB(120, 200, 120), 1)
menuButton("Editor", "🎨 Editor", Color3.fromRGB(230, 140, 200), 2)
menuButton("Shop", "🛒 Shop", Ui.GOLD, 3)
menuButton("Quests", "📜 Quests", Color3.fromRGB(110, 170, 240), 4)
menuButton("Arena", "🏟️ Arena", Color3.fromRGB(170, 110, 230), 5)
menuButton("Leaders", "🏆 Top", Color3.fromRGB(240, 160, 80), 6)
menuButton("Feedback", "💬 Ideas", Color3.fromRGB(120, 120, 150), 7)
menuButton("Dev", "🛠 Dev", Color3.fromRGB(80, 80, 90), 8)
menuButtons.Dev.Visible = false

function Menus.setProfile(p)
	profile = p
	menuButtons.Dev.Visible = p.IsDev == true
	local open = Ui.openPanel()
	if UserInputService:GetFocusedTextBox() then
		return -- don't rebuild a menu while someone is typing in it
	end
	if open and open ~= Ui.panels.Feedback and open ~= Ui.panels.Leaders and open ~= Ui.panels.Dev and open.onOpen then
		local pos = open.list.CanvasPosition
		open.onOpen()
		open.list.CanvasPosition = pos
	end
end

function Menus.profile()
	return profile
end

return Menus
