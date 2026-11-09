-- Draws germs and food of the dish you are in, from the server's snapshots. Germs are a few
-- anchored parts each, moved with one BulkMoveTo call per frame and smoothed toward the latest
-- snapshot. Sizes arrive already divided by the host's scale, so a germ in host 6 is drawn just
-- as small as one in host 1 (the label shows the real size).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Flags = require(ReplicatedStorage.Shared.Flags)
local Looks = require(script.Parent.Looks)
local Gear = require(script.Parent.Gear)

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
local foodAt = {} -- [foodId] = { x, y, z, d } (where each pellet is drawn)
local latest = {} -- [cellId] = { x, z, size, flags }
local sucking = {} -- food being sucked into a germ: { part, x, z, d, cell, t }
local dying = {} -- cells being swallowed (or fading out): { v, eater, t, r }
local puddles = {} -- slime left on the floor by the Slime mutation: { part, t }
local freePuddles = {}
local PUDDLE_TIME = 2.4
local SUCK_TIME, GULP_TIME = 0.16, 0.24

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
	local y = d / 2
	p.Material = Enum.Material.Neon
	if golden == 1 then
		goldenFood[id] = { x = x, z = z }
		d = 5
		y = d / 2
		p.Color = Color3.fromRGB(255, 200, 40)
	elseif golden == 2 then
		-- a big crumb, drawn exactly as big as a germ must be to eat it (bigger than it = you can).
		-- Mostly sunk into the floor so small germs swim visibly over it.
		d = Formulas.radius(value * Config.BigFood.NeedMult, 1) * 2
		y = -d * 0.25
		p.Color = Color3.fromRGB(235, 175, 105)
		p.Material = Enum.Material.Sand
	else
		p.Color = FOOD_COLORS[(id % #FOOD_COLORS) + 1]
	end
	p.Size = Vector3.one * d
	p.CFrame = CFrame.new(x, y, z)
	foodAt[id] = { x, y, z, d }
	p.Transparency = 0
	foodParts[id] = p
end

local function hideFood(p)
	p.Transparency = 1
	p.CFrame = CFrame.new(0, -100, 0)
	table.insert(spare, p)
end

-- The germ cell whose mouth is closest to (x, z), if one is right there (it just ate the food)
local function eaterNear(x, z)
	local best, bestD = nil, math.huge
	for id, v in Renderer.cells do
		if v.x and v.info.npc ~= "antibody" then
			local dx, dz = v.x - x, v.z - z
			local d = math.sqrt(dx * dx + dz * dz) - v.r
			if d < bestD and d < 16 then -- magnets and suction pull food from a way off
				best, bestD = id, d
			end
		end
	end
	return best
end

-- animate = the food was eaten: it gets sucked into the nearest germ instead of vanishing
local function removeFood(id, animate)
	local p = foodParts[id]
	local at = foodAt[id]
	goldenFood[id] = nil
	foodAt[id] = nil
	if p then
		foodParts[id] = nil
		local cell = animate and at and eaterNear(at[1], at[3])
		if cell then
			table.insert(sucking, { part = p, x = at[1], y = at[2], z = at[3], d = at[4], cell = cell, t = 0 })
		else
			hideFood(p)
		end
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
		removeFood(id, true)
	end
	for i = 1, #added, 5 do
		addFood(added[i], added[i + 1], added[i + 2], added[i + 3], added[i + 4])
	end
end

-- Germ looks ----------------------------------------------------------------------------------

local WHITE, BLACK = Color3.new(1, 1, 1), Color3.fromRGB(25, 25, 35)
local LOOK_PAD = 2 -- the look billboard is this much bigger than the body, so hats fit
local FLAG_BOX = 100 -- pixels: the flag emoji's box before it is scaled up to the body

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
	end
	-- mutations are flat 2D art on the look billboard (see Gear); only flat-lying cylinders here
	for _, e in v.extras do
		if e.part.Shape == Enum.PartType.Cylinder then
			e.flat = true
		end
	end
	v.shield = add(newPart(Enum.PartType.Ball, Color3.fromRGB(150, 220, 255), Enum.Material.ForceField, 1))

	-- trail: a flat ribbon lying behind the germ (the body faces its movement, so the back is
	-- local +Z). Its two ends sit at the back edge, one each side, so it is as wide as the germ.
	local trail = skin.Trail or "None"
	if TRAIL_COLORS[trail] then
		local a0 = Instance.new("Attachment")
		a0.Parent = v.body
		local a1 = Instance.new("Attachment")
		a1.Parent = v.body
		local t = Instance.new("Trail")
		t.Attachment0, t.Attachment1 = a0, a1
		t.Color = ColorSequence.new(TRAIL_COLORS[trail][1], TRAIL_COLORS[trail][2])
		t.Transparency = NumberSequence.new(0.05, 1)
		t.WidthScale = NumberSequence.new(1, 0.25)
		t.Lifetime = 0.7
		t.MinLength = 0
		t.LightEmission = 1
		t.LightInfluence = 0 -- same colour on every floor
		t.Brightness = 2
		t.FaceCamera = false
		t.Parent = v.body
		v.trail = { a0 = a0, a1 = a1, t = t }
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
	label.Text = (info.rookie and "🌱 " or "") .. info.name -- 🌱 = first run, veterans can't eat them
	label.Parent = tag
	v.label = label
	v.tag = tag
	if npc == "antibody" then
		tag.Enabled = false
	end
	if npc ~= "antibody" then
		-- the face, pattern and hat: flat 2D art (see Looks) on a billboard lying just above the
		-- body, which the top-down camera sees face on. A flag skin turns the whole disc into the
		-- flag (a round CanvasGroup clips a big flag emoji) with the face on top.
		local lookGui = Instance.new("BillboardGui")
		lookGui.Name = "Look"
		lookGui.AlwaysOnTop = false
		lookGui.LightInfluence = 0
		lookGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		lookGui.Adornee = v.body
		lookGui.Parent = v.body
		local root = Instance.new("Frame")
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.5)
		root.Size = UDim2.fromScale(1 / LOOK_PAD, 1 / LOOK_PAD)
		root.BackgroundTransparency = 1
		root.Parent = lookGui
		local flag = skin.Flag and skin.Flag ~= "" and not npc
		if flag then
			local round = Instance.new("CanvasGroup")
			round.Size = UDim2.fromScale(1, 1)
			round.BackgroundColor3 = color
			round.ZIndex = 0
			round.Parent = root
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = round
			-- Roblox stops growing scaled text at 100 px, so a big germ only got a small flag.
			-- The emoji is drawn in a fixed 100 px box instead and a UIScale blows it up to
			-- 2.1x the disc every frame (see FLAG_BOX in Renderer.update).
			local f = Instance.new("TextLabel")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(0.5, 0.5)
			f.Size = UDim2.fromOffset(FLAG_BOX, FLAG_BOX)
			f.BackgroundTransparency = 1
			f.TextScaled = true
			f.Text = Flags.emoji(skin.Flag)
			f.Parent = round
			local grow = Instance.new("UIScale")
			grow.Scale = 1
			grow.Parent = f
			v.flagScale = grow
		end
		local lookSkin = skin
		if npc then
			lookSkin = { Eyes = "Angry", Mouth = "Fangs" }
		end
		v.look = Looks.build(root, { skin = lookSkin, color = color, flag = flag })
		v.gear = Gear.build(root, info.muts or {}, color, info.core)
		v.gearState = {}
		v.lookGui = lookGui
		v.blinkAt = os.clock() + 1 + math.random() * 4
	end
	model.Parent = germFolder
	return v
end

-- The Slime mutation leaves a fading trail of goo puddles behind the germ
local function dropSlime(v, now, color)
	if now < (v.slimeAt or 0) then
		return
	end
	local dx, dz = v.x - (v.slimeX or 1e9), v.z - (v.slimeZ or 1e9)
	if dx * dx + dz * dz < (v.r * 0.4) ^ 2 then
		return
	end
	v.slimeAt, v.slimeX, v.slimeZ = now + 0.15, v.x, v.z
	local p = table.remove(freePuddles) or newPart(Enum.PartType.Cylinder, color, Enum.Material.Glass, 1, germFolder)
	p.Color = color
	p.Size = Vector3.new(0.15, v.r * 1.3, v.r * 1.3)
	p.CFrame = CFrame.new(v.x - v.dirX * v.r * 0.9, 0.1, v.z - v.dirZ * v.r * 0.9) * CFrame.Angles(0, 0, math.rad(90))
	p.Transparency = 0.35
	table.insert(puddles, { part = p, t = 0 })
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
	v.shield.Size = Vector3.one * r * 2.5
	if v.lookGui then
		v.lookGui.Size = UDim2.fromScale(r * 2 * LOOK_PAD, r * 2 * LOOK_PAD)
		v.lookGui.StudsOffsetWorldSpace = Vector3.new(0, r * 1.03, 0) -- just above the top of the body
	end
	if v.trail then
		-- just outside the back of the ball, half way up (above any floor bumps)
		v.trail.a0.Position = Vector3.new(-r * 0.5, 0, r * 0.9)
		v.trail.a1.Position = Vector3.new(r * 0.5, 0, r * 0.9)
		v.trail.t.Lifetime = math.clamp(0.5 + r * 0.03, 0.5, 2.5) -- big germs are slow: a longer tail
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
		if e.flat then
			rot = rot * FLAT
		end
		put(e.part, Vector3.new(x + (fx * f + rx * rr) * r, r + e.up * r, z + (fz * f + rz * rr) * r), rot)
	end
	put(v.shield, Vector3.new(x, r, z))
end

-- Dish and snapshots ------------------------------------------------------------------------

local function clearAll()
	for _, v in Renderer.cells do
		v.model:Destroy()
	end
	for _, d in dying do
		d.v.model:Destroy()
	end
	dying = {}
	for _, pd in puddles do
		pd.part.Transparency = 1
		table.insert(freePuddles, pd.part)
	end
	puddles = {}
	for _, s in sucking do
		hideFood(s.part)
	end
	sucking = {}
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

-- eatenBy = { [tostring(cellId)] = eater cellId } for cells that were swallowed: those fly into
-- the eater's mouth (which chomps); other cells shrink away where they are.
function Renderer.removeCells(ids, eatenBy)
	for _, id in ids do
		local v = Renderer.cells[id]
		if v then
			local eater = eatenBy and eatenBy[tostring(id)]
			if v.x then
				v.tag.Enabled = false
				table.insert(dying, { v = v, eater = eater, t = 0, r = v.r })
				local ev = eater and Renderer.cells[eater]
				if ev and ev ~= v then
					ev.chomp = 1
					ev.pulse = 1
				end
			else
				v.model:Destroy()
			end
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
			-- a gulp makes the body bulge for a moment
			local pulse = v.pulse or 0
			if pulse > 0 then
				v.pulse = math.max(0, pulse - dt * 4)
				resize(v, v.r * (1 + 0.12 * math.sin(math.min(1, pulse) * math.pi)))
			elseif math.abs(v.r - v.drawnR) > v.drawnR * 0.01 then
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
				if v.lookGui then
					v.lookGui.Enabled = not hidden or mine
				end
			end
			if v.look then
				-- eyes follow the swim direction, blink now and then, the propeller spins
				Looks.aim(v.look, v.dirX, v.dirZ, t)
				local now = os.clock()
				if now >= v.blinkAt then
					local shut = not v.blinking
					v.blinking = shut
					Looks.blink(v.look, shut)
					v.blinkAt = now + (shut and 0.12 or 2.5 + math.random() * 3.5)
				end
				if v.chomp and v.chomp > 0 then
					-- swallowing a germ: mouth wide open, eyes squeezed shut
					v.chomp = math.max(0, v.chomp - dt * 3.5)
					Looks.gulp(v.look, v.chomp)
				end
				if v.flagScale then
					-- keep the flag covering the whole body however big it is on screen
					local px = v.lookGui.AbsoluteSize.X / LOOK_PAD
					local want = math.max(0.01, px * 2.1 / FLAG_BOX)
					if math.abs(v.flagScale.Scale - want) > want * 0.01 then
						v.flagScale.Scale = want
					end
				end
				if v.look.spin then
					v.look.spin.Rotation = (t * 720) % 360
				end
				if v.gear and (not hidden or mine) then
					-- mutations: face the swim direction and show what they do
					local st = v.gearState
					st.dx, st.dz = v.dirX, v.dirZ
					st.fight = bit(flags, FLAG_FIGHT)
					st.dash = bit(flags, FLAG_DASH)
					if v.power and now - v.powerAt < 3.5 then
						st.power, st.powerAge = v.power, now - v.powerAt
					else
						v.power, st.power, st.powerAge = nil, nil, nil
					end
					Gear.animate(v.gear, dt, t, st)
					if v.gear.slimeColor and not hidden then
						dropSlime(v, now, v.gear.slimeColor)
					end
				end
			end
			if bit(flags, FLAG_POISON) then
				v.body.Color = v.info.color:Lerp(Color3.fromRGB(120, 255, 60), 0.4 + math.sin(t * 6) * 0.2)
				v.poisoned = true
			elseif v.poisoned then
				v.poisoned = false
				v.body.Color = v.info.color
			end
			local text = (v.info.rookie and "🌱 " or "") .. v.info.name .. "\n" .. Formulas.formatNumber(s.size * scale)
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
	-- swallowed cells fly into the eater and shrink; eaten food gets sucked in
	for i = #dying, 1, -1 do
		local d = dying[i]
		local v = d.v
		d.t += dt
		local p = math.min(1, d.t / GULP_TIME)
		local ev = d.eater and Renderer.cells[d.eater]
		if ev and ev.x then
			local f = math.min(1, dt * 16)
			v.x += (ev.x - v.x) * f
			v.z += (ev.z - v.z) * f
		end
		if p >= 1 then
			v.model:Destroy()
			table.remove(dying, i)
		else
			v.r = math.max(0.05, d.r * (1 - p))
			resize(v, v.r)
			place(v, parts, cframes, t)
		end
	end
	for i = #sucking, 1, -1 do
		local s = sucking[i]
		s.t += dt
		local p = math.min(1, s.t / SUCK_TIME)
		local v = Renderer.cells[s.cell]
		if p >= 1 or not v or not v.x then
			hideFood(s.part)
			table.remove(sucking, i)
			if v then
				v.pulse = math.max(v.pulse or 0, 0.35)
			end
		else
			local e = p * p
			s.part.Size = Vector3.one * math.max(0.05, s.d * (1 - p * 0.8))
			s.part.CFrame = CFrame.new(s.x + (v.x - s.x) * e, s.y + (v.r - s.y) * e, s.z + (v.z - s.z) * e)
		end
	end
	for i = #puddles, 1, -1 do
		local pd = puddles[i]
		pd.t += dt
		if pd.t >= PUDDLE_TIME then
			pd.part.Transparency = 1
			table.insert(freePuddles, pd.part)
			table.remove(puddles, i)
		else
			pd.part.Transparency = 0.35 + 0.65 * (pd.t / PUDDLE_TIME)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- A germ used its ability (Chomp, Vacuum, Pierce, Gravity well, Blast...): its gear shows it
function Renderer.power(germId, kind)
	local now = os.clock()
	for cellId, gid in Renderer.cellGerm do
		local v = gid == germId and Renderer.cells[cellId]
		if v then
			v.power, v.powerAt = kind, now
		end
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
