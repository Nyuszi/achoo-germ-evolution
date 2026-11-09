-- Draws germs and food of the dish you are in, from the server's snapshots. Germs are a few
-- anchored parts each, moved with one BulkMoveTo call per frame and smoothed toward the latest
-- snapshot. Sizes arrive already divided by the host's scale, so a germ in host 6 is drawn just
-- as small as one in host 1 (the label shows the real size).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Flags = require(ReplicatedStorage.Shared.Flags)

local Renderer = {}

local FLAG_CROWN, FLAG_PROTECTED, FLAG_DASH, FLAG_FIGHT, FLAG_HIDDEN, FLAG_SLOW, FLAG_POISON = 1, 2, 4, 8, 16, 32, 64

local germFolder = Instance.new("Folder")
germFolder.Name = "Germs"
germFolder.Parent = workspace
local foodFolder = Instance.new("Folder")
foodFolder.Name = "Food"
foodFolder.Parent = workspace

Renderer.cellGerm = {} -- [cellId] = germId
Renderer.germInfo = {} -- [germId] = info
Renderer.cells = {} -- [cellId] = visual
Renderer.dish = nil -- DishInfo of the dish we are in
Renderer.myGermId = nil
local scale = 1
local dishId = 0
local foodParts = {} -- [foodId] = part
local spare = {} -- unused food parts
local goldenFood = {} -- [foodId] = { x, z }
local latest = {} -- [cellId] = { x, z, size, flags }

local function newPart(shape, color, material, transparency, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape or Enum.PartType.Ball
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color or Color3.new(1, 1, 1)
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function rgb(t, fallback)
	if type(t) == "table" and t[1] then
		return Color3.fromRGB(t[1], t[2], t[3])
	end
	return fallback or Color3.new(1, 1, 1)
end

-- Food ------------------------------------------------------------------------------------

local FOOD_COLORS = {
	Color3.fromRGB(255, 240, 140), Color3.fromRGB(170, 255, 170), Color3.fromRGB(150, 220, 255),
	Color3.fromRGB(255, 180, 230), Color3.fromRGB(255, 200, 150),
}

local function addFood(id, x, z, value, golden)
	if foodParts[id] then
		return
	end
	local p = table.remove(spare)
	if not p then
		p = newPart(Enum.PartType.Ball, nil, Enum.Material.Neon, 0, foodFolder)
	end
	local d = math.min(3, 0.8 + math.sqrt(value) * 0.3)
	if golden == 1 then
		goldenFood[id] = { x = x, z = z }
		d = 5
		p.Color = Color3.fromRGB(255, 200, 40)
	else
		p.Color = FOOD_COLORS[(id % #FOOD_COLORS) + 1]
	end
	p.Size = Vector3.one * d
	p.CFrame = CFrame.new(x, d / 2, z)
	p.Transparency = 0
	foodParts[id] = p
end

local function removeFood(id)
	local p = foodParts[id]
	goldenFood[id] = nil
	if p then
		foodParts[id] = nil
		p.Transparency = 1
		p.CFrame = CFrame.new(0, -100, 0)
		table.insert(spare, p)
	end
end

function Renderer.foodSync(list)
	for id in foodParts do
		removeFood(id)
	end
	for i = 1, #list, 5 do
		addFood(list[i], list[i + 1], list[i + 2], list[i + 3], list[i + 4])
	end
end

function Renderer.foodDelta(added, removed)
	for _, id in removed do
		removeFood(id)
	end
	for i = 1, #added, 5 do
		addFood(added[i], added[i + 1], added[i + 2], added[i + 3], added[i + 4])
	end
end

-- Germ looks ----------------------------------------------------------------------------------

local WHITE, BLACK = Color3.new(1, 1, 1), Color3.fromRGB(25, 25, 35)

local function skinItem(cat, id)
	for _, item in Config.Skins[cat] or {} do
		if item.Id == id then
			return item
		end
	end
	return Config.Skins[cat] and Config.Skins[cat][1]
end

local TRAIL_COLORS = {
	Bubbles = { Color3.fromRGB(180, 230, 255), Color3.fromRGB(255, 255, 255) },
	Sparkles = { Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 255, 255) },
	SlimeTrail = { Color3.fromRGB(120, 230, 90), Color3.fromRGB(60, 160, 40) },
	Hearts = { Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 200, 220) },
	Fire = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(255, 60, 20) },
	ArenaFlame = { Color3.fromRGB(120, 255, 220), Color3.fromRGB(40, 120, 255) },
	ArenaLightning = { Color3.fromRGB(255, 255, 120), Color3.fromRGB(160, 120, 255) },
}

-- Builds one cell's parts. Each extra part has a place function(v, at, put, look) called every frame.
local function buildVisual(cellId)
	local germId = Renderer.cellGerm[cellId]
	local info = Renderer.germInfo[germId] or { name = "?", color = Color3.new(0.6, 0.9, 0.6), muts = {} }
	local model = Instance.new("Model")
	model.Name = info.name
	local v = { model = model, parts = {}, extras = {}, x = nil, z = nil, size = 0, r = 0, drawnR = -1, dirX = 1, dirZ = 0, info = info, germId = germId }
	local function add(p, key)
		p.Parent = model
		if key then
			v[key] = p
		end
		table.insert(v.parts, p)
		return p
	end
	-- extra = part sized k * radius (vector), placed at offset (forward, up, right) * radius
	local function extra(p, sizeK, fwd, up, right, spin)
		add(p)
		table.insert(v.extras, { part = p, size = sizeK, fwd = fwd, up = up, right = right, spin = spin })
		return p
	end
	local skin = info.skin or {}
	local color = info.color or Color3.new(0.6, 0.9, 0.6)
	local color2 = rgb(skin.Color2, WHITE)
	local body = skinItem("Body", skin.Body or "Jelly")
	local material = Enum.Material[body.Material or "SmoothPlastic"]
	local transparency = body.Transparency or 0.12
	local npc = info.npc
	if npc == "whitey" then
		color, material, transparency = Color3.fromRGB(245, 245, 255), Enum.Material.SmoothPlastic, 0.05
	elseif npc == "macrophage" then
		color, material, transparency = Color3.fromRGB(190, 120, 230), Enum.Material.SmoothPlastic, 0.1
	elseif npc == "antibody" then
		color, material, transparency = Color3.fromRGB(120, 180, 255), Enum.Material.Neon, 0
	end
	if info.core == "Crystal" then
		material = Enum.Material.Glass
	end
	v.baseTransparency = transparency
	add(newPart(Enum.PartType.Ball, color, material, transparency), "body")
	if npc == "antibody" then
		-- a little Y shape
		extra(newPart(Enum.PartType.Block, color, Enum.Material.Neon), Vector3.new(0.3, 0.3, 1.4), -0.5, 0.3, 0)
		extra(newPart(Enum.PartType.Block, color, Enum.Material.Neon), Vector3.new(0.3, 0.3, 1.0), 0.6, 0.3, -0.4)
		extra(newPart(Enum.PartType.Block, color, Enum.Material.Neon), Vector3.new(0.3, 0.3, 1.0), 0.6, 0.3, 0.4)
	else
		add(newPart(Enum.PartType.Ball, color:Lerp(BLACK, 0.35), Enum.Material.SmoothPlastic, 0.2), "nucleus")
		-- eyes
		local eyes = skin.Eyes or "Cute"
		if npc then
			eyes = "Angry"
		end
		local eyeK, pupilK = 0.42, 0.2
		if eyes == "Googly" then
			eyeK, pupilK = 0.55, 0.18
		elseif eyes == "Sleepy" then
			pupilK = 0.3
		end
		if eyes == "Cyclops" then
			extra(newPart(Enum.PartType.Ball, WHITE), Vector3.one * 0.6, 0.42, 0.75, 0)
			extra(newPart(Enum.PartType.Ball, BLACK), Vector3.one * 0.28, 0.55, 0.95, 0)
		else
			local list = { -0.32, 0.32 }
			if eyes == "Three" then
				list = { -0.4, 0, 0.4 }
			end
			for _, side in list do
				extra(newPart(Enum.PartType.Ball, WHITE), Vector3.one * eyeK, 0.42, 0.75, side)
				extra(newPart(Enum.PartType.Ball, BLACK), Vector3.one * pupilK, 0.52, 0.92, side)
			end
			if eyes == "Angry" or eyes == "Sleepy" then
				for _, side in { -0.32, 0.32 } do
					extra(newPart(Enum.PartType.Block, color:Lerp(BLACK, 0.5)), Vector3.new(0.4, 0.08, 0.12), 0.45, 1.0, side)
				end
			end
		end
		-- mouth
		local mouth = skin.Mouth or "Smile"
		if npc == "macrophage" then
			mouth = "Fangs"
		end
		if mouth == "Smile" or mouth == "Braces" then
			extra(newPart(Enum.PartType.Block, mouth == "Braces" and Color3.fromRGB(190, 190, 200) or BLACK), Vector3.new(0.4, 0.06, 0.1), 0.85, 0.35, 0)
		elseif mouth == "Fangs" then
			extra(newPart(Enum.PartType.Block, WHITE), Vector3.new(0.1, 0.1, 0.2), 0.9, 0.3, -0.12)
			extra(newPart(Enum.PartType.Block, WHITE), Vector3.new(0.1, 0.1, 0.2), 0.9, 0.3, 0.12)
		elseif mouth == "Tongue" then
			extra(newPart(Enum.PartType.Ball, Color3.fromRGB(255, 120, 150)), Vector3.one * 0.28, 0.95, 0.3, 0)
		elseif mouth == "Mustache" then
			extra(newPart(Enum.PartType.Block, Color3.fromRGB(70, 45, 30)), Vector3.new(0.5, 0.1, 0.14), 0.85, 0.45, 0)
		end
		-- pattern (in the second colour)
		local pattern = skin.Pattern or "None"
		if pattern == "Spots" or pattern == "Camo" or pattern == "Checkers" then
			local spots = pattern == "Spots" and 5 or 7
			for i = 1, spots do
				local a = (i / spots) * math.pi * 2
				local c = color2
				if pattern == "Camo" then
					c = color:Lerp(Color3.fromRGB(60, 80, 40), 0.5 + (i % 2) * 0.2)
				end
				local p = newPart(pattern == "Checkers" and Enum.PartType.Block or Enum.PartType.Ball, c)
				extra(p, Vector3.one * 0.3, math.cos(a) * 0.55, 0.7, math.sin(a) * 0.55)
			end
		elseif pattern == "Stripes" or pattern == "Flames" or pattern == "Swirl" then
			local c = pattern == "Flames" and Color3.fromRGB(255, 140, 30) or color2
			for i = -1, 1 do
				extra(newPart(Enum.PartType.Block, c, pattern == "Flames" and Enum.Material.Neon or Enum.Material.SmoothPlastic), Vector3.new(1.5, 0.08, 0.16), -0.1, 0.92, i * 0.45)
			end
		end
	end
	-- mutations
	local muts = info.muts or {}
	local function has(slot, id)
		local m = muts[slot]
		if m == id then
			return true
		end
		local f = m and Config.Fusions[(string.gsub(m, "^#", ""))]
		return f ~= nil and table.find(f.Parts, id) ~= nil
	end
	local bone = Color3.fromRGB(245, 245, 230)
	if has("Front", "Jaws") then
		v.jaws = {
			extra(newPart(Enum.PartType.Block, bone), Vector3.new(0.25, 0.3, 0.55), 1.0, 0, -0.2),
			extra(newPart(Enum.PartType.Block, bone), Vector3.new(0.25, 0.3, 0.55), 1.0, 0, 0.2),
		}
	end
	if has("Front", "Suction") then
		extra(newPart(Enum.PartType.Cylinder, color:Lerp(Color3.fromRGB(255, 120, 150), 0.5)), Vector3.new(0.3, 0.7, 0.7), 1.0, 0, 0)
	end
	if has("Front", "Drill") then
		extra(newPart(Enum.PartType.Block, Color3.fromRGB(170, 170, 185), Enum.Material.DiamondPlate), Vector3.new(0.3, 0.3, 0.8), 1.15, 0, 0)
	end
	if has("Back", "Flagella") then
		v.tail = extra(newPart(Enum.PartType.Block, color:Lerp(BLACK, 0.2)), Vector3.new(0.18, 0.12, 1.3), -1.35, 0, 0)
	end
	if has("Back", "Jet") then
		extra(newPart(Enum.PartType.Cylinder, Color3.fromRGB(255, 160, 60), Enum.Material.Neon), Vector3.new(0.3, 0.35, 0.35), -1.05, 0, -0.3)
		extra(newPart(Enum.PartType.Cylinder, Color3.fromRGB(255, 160, 60), Enum.Material.Neon), Vector3.new(0.3, 0.35, 0.35), -1.05, 0, 0.3)
	end
	if has("Back", "Slime") then
		extra(newPart(Enum.PartType.Ball, Color3.fromRGB(120, 230, 90), Enum.Material.Glass, 0.4), Vector3.one * 0.7, -1.1, -0.3, 0)
	end
	if has("Sides", "Spikes") or info.core == "Star" then
		v.spikes = {}
		for i = 1, 8 do
			local a = (i / 8) * math.pi * 2
			table.insert(v.spikes, extra(newPart(Enum.PartType.Block, color:Lerp(BLACK, 0.45)), Vector3.new(0.22, 0.22, 0.6), math.cos(a) * 1.05, 0, math.sin(a) * 1.05, a))
		end
	end
	if has("Sides", "Toxin") then
		for i = 1, 4 do
			local a = (i / 4) * math.pi * 2 + 0.4
			extra(newPart(Enum.PartType.Ball, Color3.fromRGB(150, 255, 80), Enum.Material.Neon), Vector3.one * 0.25, math.cos(a) * 0.95, 0.2, math.sin(a) * 0.95)
		end
	end
	if has("Sides", "Shell") then
		v.shell = add(newPart(Enum.PartType.Ball, Color3.fromRGB(170, 170, 185), Enum.Material.Slate, 0.55))
	end
	if has("Special", "Magnet") then
		extra(newPart(Enum.PartType.Block, Color3.fromRGB(230, 60, 60)), Vector3.new(0.25, 0.4, 0.25), 0, 1.0, -0.2)
		extra(newPart(Enum.PartType.Block, Color3.fromRGB(60, 90, 230)), Vector3.new(0.25, 0.4, 0.25), 0, 1.0, 0.2)
	end
	if has("Special", "Sneezer") then
		extra(newPart(Enum.PartType.Ball, color:Lerp(Color3.fromRGB(255, 120, 120), 0.5)), Vector3.one * 0.3, 0.95, 0.55, 0)
	end
	-- hats
	local hat = skin.Hat or "None"
	if hat == "Crown" then
		extra(newPart(Enum.PartType.Cylinder, Color3.fromRGB(255, 205, 50), Enum.Material.Neon), Vector3.new(0.35, 0.6, 0.6), 0, 1.15, 0)
	elseif hat == "Party" then
		extra(newPart(Enum.PartType.Block, Color3.fromRGB(255, 90, 200)), Vector3.new(0.35, 0.6, 0.35), 0, 1.2, 0)
		extra(newPart(Enum.PartType.Ball, Color3.fromRGB(255, 240, 90)), Vector3.one * 0.2, 0, 1.55, 0)
	elseif hat == "Propeller" then
		extra(newPart(Enum.PartType.Ball, Color3.fromRGB(80, 160, 255)), Vector3.one * 0.5, 0, 1.0, 0)
		v.propeller = extra(newPart(Enum.PartType.Block, Color3.fromRGB(255, 80, 80)), Vector3.new(1.0, 0.06, 0.15), 0, 1.28, 0, 0)
	elseif hat == "Halo" then
		extra(newPart(Enum.PartType.Cylinder, Color3.fromRGB(255, 250, 180), Enum.Material.Neon, 0.2), Vector3.new(0.08, 1.0, 1.0), 0, 1.5, 0)
	elseif hat == "Horns" then
		extra(newPart(Enum.PartType.Block, Color3.fromRGB(200, 40, 40)), Vector3.new(0.15, 0.45, 0.15), 0.2, 1.0, -0.35)
		extra(newPart(Enum.PartType.Block, Color3.fromRGB(200, 40, 40)), Vector3.new(0.15, 0.45, 0.15), 0.2, 1.0, 0.35)
	elseif hat == "Laurel" then
		extra(newPart(Enum.PartType.Cylinder, Color3.fromRGB(90, 200, 90)), Vector3.new(0.12, 1.1, 1.1), 0, 1.0, 0)
	end
	-- the parts above are rotated so cylinders lie flat
	for _, e in v.extras do
		if e.part.Shape == Enum.PartType.Cylinder then
			e.flat = true
		end
	end
	v.shield = add(newPart(Enum.PartType.Ball, Color3.fromRGB(150, 220, 255), Enum.Material.ForceField, 1))

	-- trail
	local trail = skin.Trail or "None"
	if TRAIL_COLORS[trail] then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.5, 0)
		a0.Parent = v.body
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.5, 0)
		a1.Parent = v.body
		local t = Instance.new("Trail")
		t.Attachment0, t.Attachment1 = a0, a1
		t.Color = ColorSequence.new(TRAIL_COLORS[trail][1], TRAIL_COLORS[trail][2])
		t.Transparency = NumberSequence.new(0.2, 1)
		t.Lifetime = 0.6
		t.LightEmission = 0.6
		t.FaceCamera = true
		t.Parent = v.body
		v.trail = { a0 = a0, a1 = a1 }
	end

	-- name tag (and flag)
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(170, 44)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.Adornee = v.body
	tag.Parent = v.body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = info.vip and Color3.fromRGB(255, 215, 80) or WHITE
	label.TextStrokeTransparency = 0.4
	label.Text = info.name
	label.Parent = tag
	v.label = label
	v.tag = tag
	if npc == "antibody" then
		tag.Enabled = false
	end
	if skin.Flag and skin.Flag ~= "" and not npc then
		-- flag skin: the whole top of the body becomes the flag. A round CanvasGroup clips a big
		-- flag emoji into a circle that lies just above the body; the face floats on top of it.
		local flagGui = Instance.new("BillboardGui")
		flagGui.AlwaysOnTop = false
		flagGui.LightInfluence = 0
		flagGui.Adornee = v.body
		flagGui.Parent = v.body
		local round = Instance.new("CanvasGroup")
		round.Size = UDim2.fromScale(1, 1)
		round.BackgroundColor3 = color
		round.Parent = flagGui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = round
		local f = Instance.new("TextLabel")
		f.Size = UDim2.fromScale(2.1, 2.1)
		f.Position = UDim2.fromScale(-0.55, -0.55)
		f.BackgroundTransparency = 1
		f.TextScaled = true
		f.Text = Flags.emoji(skin.Flag)
		f.Parent = round
		v.flagGui = flagGui
		v.lift = 0.8 -- face parts sit above the flag
		v.baseTransparency = math.max(v.baseTransparency, 0)
	end
	model.Parent = germFolder
	return v
end

-- Sizes every part for radius r (only when the radius really changed)
local function resize(v, r)
	v.body.Size = Vector3.one * r * 2
	if v.nucleus then
		v.nucleus.Size = Vector3.one * r * 0.8
	end
	for _, e in v.extras do
		local s = e.size * r
		if e.flat then
			s = Vector3.new(s.X, s.Y, s.Z)
		end
		e.part.Size = s
	end
	if v.shell then
		v.shell.Size = Vector3.one * r * 2.15
	end
	v.shield.Size = Vector3.one * r * 2.5
	if v.flagGui then
		
		v.flagGui.Size = UDim2.fromScale(r * 2, r * 2)
		v.flagGui.StudsOffsetWorldSpace = Vector3.new(0, r * 1.03, 0) -- just above the top of the body
	end
	if v.trail then
		v.trail.a0.Position = Vector3.new(0, 0, r * 0.8)
		v.trail.a1.Position = Vector3.new(0, 0, -r * 0.8)
	end
	v.drawnR = r
end

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders stand upright

-- Positions every part of one germ cell. Adds parts and CFrames to the bulk lists.
local function place(v, partsOut, cframesOut, t)
	local r = v.r
	local x, z = v.x, v.z
	local fx, fz = v.dirX, v.dirZ
	local rx, rz = -fz, fx -- right-hand side when looking along the movement direction
	local look = CFrame.lookAt(Vector3.zero, Vector3.new(fx, 0, fz))
	local function put(p, pos, rot)
		table.insert(partsOut, p)
		table.insert(cframesOut, CFrame.new(pos) * (rot or look))
	end
	put(v.body, Vector3.new(x, r, z))
	if v.nucleus then
		put(v.nucleus, Vector3.new(x - fx * r * 0.2, r * 1.25, z - fz * r * 0.2))
	end
	for _, e in v.extras do
		local f, rr = e.fwd, e.right
		local rot = look
		if e.spin then
			-- spikes go round the body
			local a = e.spin + t * 0.6
			f, rr = math.cos(a) * 1.05, math.sin(a) * 1.05
			rot = CFrame.lookAt(Vector3.zero, Vector3.new(fx * math.cos(a) + rx * math.sin(a), 0, fz * math.cos(a) + rz * math.sin(a)))
		end
		if e.part == v.tail then
			local wiggle = math.sin(t * 12) * 0.35
			rot = CFrame.lookAt(Vector3.zero, Vector3.new(fx + rx * wiggle, 0, fz + rz * wiggle))
		elseif e.part == v.propeller then
			rot = CFrame.Angles(0, t * 12, 0)
		elseif v.jaws and (e.part == v.jaws[1] or e.part == v.jaws[2]) then
			local chomp = 0.15 + math.abs(math.sin(t * 8)) * 0.15
			rr = (e.part == v.jaws[1]) and -chomp or chomp
		end
		if e.flat then
			rot = rot * FLAT
		end
		local up = e.up
		if v.lift and up >= 0.2 then
			up += v.lift
		end
		put(e.part, Vector3.new(x + (fx * f + rx * rr) * r, r + up * r, z + (fz * f + rz * rr) * r), rot)
	end
	if v.shell then
		put(v.shell, Vector3.new(x, r, z))
	end
	put(v.shield, Vector3.new(x, r, z))
end

-- Dish and snapshots ------------------------------------------------------------------------

local function clearAll()
	for _, v in Renderer.cells do
		v.model:Destroy()
	end
	Renderer.cells = {}
	Renderer.cellGerm = {}
	Renderer.germInfo = {}
	latest = {}
	for id in foodParts do
		removeFood(id)
	end
end

-- A new dish: forget everything from the old one
function Renderer.setDish(info)
	clearAll()
	Renderer.dish = info
	scale = info.scale or 1
	dishId = info.id
end

function Renderer.scale()
	return scale
end

function Renderer.applyInfo(payload)
	-- ids arrive as string keys (see World.wireInfo)
	for key, info in payload.germs do
		local germId = tonumber(key)
		Renderer.germInfo[germId] = info
		-- rebuild visuals of this germ's cells so new mutations and skins show
		for cellId, gid in Renderer.cellGerm do
			if gid == germId and Renderer.cells[cellId] then
				Renderer.cells[cellId].model:Destroy()
				Renderer.cells[cellId] = nil
			end
		end
	end
	for key, germId in payload.cells do
		Renderer.cellGerm[tonumber(key)] = germId
	end
end

function Renderer.removeCells(ids)
	for _, id in ids do
		local v = Renderer.cells[id]
		if v then
			v.model:Destroy()
		end
		Renderer.cells[id] = nil
		Renderer.cellGerm[id] = nil
		latest[id] = nil
	end
end

function Renderer.snapshot(buf)
	if buffer.len(buf) < 8 or buffer.readu32(buf, 4) ~= dishId then
		return -- from the dish we just left
	end
	local seen = {}
	local count = (buffer.len(buf) - 8) // 17
	for i = 0, count - 1 do
		local o = 8 + i * 17
		local id = buffer.readu32(buf, o)
		seen[id] = true
		local s = latest[id]
		if not s then
			s = {}
			latest[id] = s
		end
		s.x = buffer.readf32(buf, o + 4)
		s.z = buffer.readf32(buf, o + 8)
		s.size = buffer.readf32(buf, o + 12)
		s.flags = buffer.readu8(buf, o + 16)
	end
	for id in latest do
		if not seen[id] then
			Renderer.removeCells({ id })
		end
	end
end

function Renderer.state(cellId)
	return latest[cellId]
end

local function bit(flags, f)
	return bit32.band(flags, f) ~= 0
end

-- Called every frame
function Renderer.update(dt, t)
	local parts, cframes = {}, {}
	local k = 1 - math.exp(-14 * dt)
	for id, s in latest do
		local v = Renderer.cells[id]
		if not v and Renderer.cellGerm[id] then
			v = buildVisual(id)
			Renderer.cells[id] = v
		end
		if v then
			if not v.x then
				v.x, v.z, v.size = s.x, s.z, s.size
			end
			local nx, nz = v.x + (s.x - v.x) * k, v.z + (s.z - v.z) * k
			local mx, mz = nx - v.x, nz - v.z
			local moved = math.sqrt(mx * mx + mz * mz)
			if moved > 0.02 then
				local tx, tz = mx / moved, mz / moved
				local dx, dz = v.dirX + (tx - v.dirX) * 0.25, v.dirZ + (tz - v.dirZ) * 0.25
				local len = math.sqrt(dx * dx + dz * dz)
				if len > 0.001 then
					v.dirX, v.dirZ = dx / len, dz / len
				end
			end
			v.x, v.z = nx, nz
			v.size = v.size + (s.size - v.size) * k
			v.r = Formulas.radius(v.size, 1)
			if math.abs(v.r - v.drawnR) > v.drawnR * 0.01 then
				resize(v, v.r)
			end
			local flags = s.flags
			v.shield.Transparency = bit(flags, FLAG_PROTECTED) and 0.3 or 1
			-- hidden germs (ink, camo, ghost): almost invisible to others, see-through to yourself
			local hidden = bit(flags, FLAG_HIDDEN)
			local mine = v.germId == Renderer.myGermId
			local wantT = v.baseTransparency
			if hidden then
				wantT = mine and 0.6 or 0.93
			end
			if v.body.Transparency ~= wantT then
				v.body.Transparency = wantT
				for _, e in v.extras do
					e.part.Transparency = hidden and (mine and 0.5 or 1) or 0
				end
				v.tag.Enabled = (not hidden or mine) and v.info.npc ~= "antibody"
			end
			if bit(flags, FLAG_POISON) then
				v.body.Color = v.info.color:Lerp(Color3.fromRGB(120, 255, 60), 0.4 + math.sin(t * 6) * 0.2)
				v.poisoned = true
			elseif v.poisoned then
				v.poisoned = false
				v.body.Color = v.info.color
			end
			local text = v.info.name .. "\n" .. Formulas.formatNumber(s.size * scale)
			if bit(flags, FLAG_CROWN) then
				text = "👑 " .. text
			end
			if bit(flags, FLAG_DASH) then
				text = "💨 " .. text
			end
			if bit(flags, FLAG_SLOW) then
				text = "🐌 " .. text
			end
			if bit(flags, FLAG_FIGHT) then
				text = "⚔️ " .. text
			end
			if v.label.Text ~= text then
				v.label.Text = text
			end
			place(v, parts, cframes, t)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- The drawn centre and combined radius of all cells of one germ (for the camera)
function Renderer.germView(germId)
	local sx, sz, total, count = 0, 0, 0, 0
	for id, v in Renderer.cells do
		if Renderer.cellGerm[id] == germId and v.x then
			sx += v.x * v.size
			sz += v.z * v.size
			total += v.size
			count += 1
		end
	end
	if count == 0 or total <= 0 then
		return nil
	end
	return sx / total, sz / total, Formulas.radius(total, 1), total * scale
end

-- What the minimap shows: you, the crowned germ, immune bosses and golden food (not everyone,
-- so the map is not a free radar)
function Renderer.markers()
	local out = { king = nil, bosses = {}, golden = {} }
	for id, v in Renderer.cells do
		local s = latest[id]
		if s and v.x then
			if bit32.band(s.flags, FLAG_CROWN) ~= 0 and bit32.band(s.flags, FLAG_HIDDEN) == 0 then
				out.king = { x = v.x, z = v.z }
			end
			local npc = v.info.npc
			if npc == "whitey" or npc == "macrophage" then
				table.insert(out.bosses, { x = v.x, z = v.z })
			end
		end
	end
	for _, g in goldenFood do
		table.insert(out.golden, g)
	end
	return out
end

-- Biggest germs for the size board: { { name, size, germId } } (immune NPCs left out)
function Renderer.board(limit)
	local sizes = {}
	for id, s in latest do
		local germId = Renderer.cellGerm[id]
		local info = germId and Renderer.germInfo[germId]
		if info and not info.npc then
			sizes[germId] = (sizes[germId] or 0) + s.size * scale
		end
	end
	local list = {}
	for germId, size in sizes do
		table.insert(list, { name = Renderer.germInfo[germId].name, size = size, germId = germId })
	end
	table.sort(list, function(a, b)
		return a.size > b.size
	end)
	while #list > limit do
		table.remove(list)
	end
	return list
end

return Renderer
