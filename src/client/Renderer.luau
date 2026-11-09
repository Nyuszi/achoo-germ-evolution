-- Draws germs and food from the server's snapshots. Germs are a few anchored parts each,
-- moved with one BulkMoveTo call per frame. Positions are smoothed toward the latest snapshot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local Renderer = {}

local SCALE = Formulas.host().Scale
local FLAG_CROWN, FLAG_PROTECTED, FLAG_DASH = 1, 2, 4

local germFolder = Instance.new("Folder")
germFolder.Name = "Germs"
germFolder.Parent = workspace
local foodFolder = Instance.new("Folder")
foodFolder.Name = "Food"
foodFolder.Parent = workspace

Renderer.cellGerm = {} -- [cellId] = germId
Renderer.germInfo = {} -- [germId] = { name, color, userId, muts }
Renderer.cells = {} -- [cellId] = visual
local foodParts = {} -- [foodId] = part
local spare = {} -- unused food parts

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
	local d = math.min(3, 0.8 + math.sqrt(value / SCALE) * 0.3)
	if golden == 1 then
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

local function buildVisual(cellId)
	local germId = Renderer.cellGerm[cellId]
	local info = Renderer.germInfo[germId] or { name = "?", color = Color3.new(0.6, 0.9, 0.6), muts = {} }
	local model = Instance.new("Model")
	model.Name = info.name
	local v = { model = model, parts = {}, offsets = {}, x = nil, z = nil, size = 0, r = 0, drawnR = -1, dirX = 1, dirZ = 0, info = info }

	local function add(p, key)
		p.Parent = model
		v[key] = p
		table.insert(v.parts, p)
		return p
	end
	add(newPart(Enum.PartType.Ball, info.color, Enum.Material.SmoothPlastic, 0.12), "body")
	add(newPart(Enum.PartType.Ball, info.color:Lerp(BLACK, 0.35), Enum.Material.SmoothPlastic, 0.2), "nucleus")
	add(newPart(Enum.PartType.Ball, WHITE), "eyeL")
	add(newPart(Enum.PartType.Ball, WHITE), "eyeR")
	add(newPart(Enum.PartType.Ball, BLACK), "pupilL")
	add(newPart(Enum.PartType.Ball, BLACK), "pupilR")
	local muts = info.muts or {}
	if muts.Front == "Jaws" then
		add(newPart(Enum.PartType.Block, Color3.fromRGB(245, 245, 230)), "jawL")
		add(newPart(Enum.PartType.Block, Color3.fromRGB(245, 245, 230)), "jawR")
	end
	if muts.Back == "Flagella" then
		add(newPart(Enum.PartType.Block, info.color:Lerp(BLACK, 0.2)), "tail")
	end
	if muts.Sides == "Spikes" then
		v.spikes = {}
		for i = 1, 8 do
			local s = add(newPart(Enum.PartType.Block, info.color:Lerp(BLACK, 0.45)), "spike" .. i)
			table.insert(v.spikes, s)
		end
	elseif muts.Sides == "Shell" then
		add(newPart(Enum.PartType.Ball, Color3.fromRGB(170, 170, 185), Enum.Material.Slate, 0.55), "shell")
	end
	v.shield = add(newPart(Enum.PartType.Ball, Color3.fromRGB(150, 220, 255), Enum.Material.ForceField, 1), "shieldPart")

	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(160, 40)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.Adornee = v.body
	tag.Parent = v.body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0.4
	label.Text = info.name
	label.Parent = tag
	v.label = label
	model.Parent = germFolder
	return v
end

-- Sizes every part for radius r (only when the radius really changed)
local function resize(v, r)
	v.body.Size = Vector3.one * r * 2
	v.nucleus.Size = Vector3.one * r * 0.8
	v.eyeL.Size = Vector3.one * r * 0.42
	v.eyeR.Size = Vector3.one * r * 0.42
	v.pupilL.Size = Vector3.one * r * 0.2
	v.pupilR.Size = Vector3.one * r * 0.2
	if v.jawL then
		v.jawL.Size = Vector3.new(r * 0.25, r * 0.3, r * 0.55)
		v.jawR.Size = Vector3.new(r * 0.25, r * 0.3, r * 0.55)
	end
	if v.tail then
		v.tail.Size = Vector3.new(r * 0.18, r * 0.12, r * 1.3)
	end
	if v.spikes then
		for _, s in v.spikes do
			s.Size = Vector3.new(r * 0.22, r * 0.22, r * 0.6)
		end
	end
	if v.shell then
		v.shell.Size = Vector3.one * r * 2.15
	end
	v.shield.Size = Vector3.one * r * 2.5
	v.drawnR = r
end

-- Positions every part of one germ cell. Adds parts and CFrames to the bulk lists.
local function place(v, partsOut, cframesOut, t)
	local r = v.r
	local x, z = v.x, v.z
	local fx, fz = v.dirX, v.dirZ
	local rx, rz = -fz, fx -- right-hand side when looking along the movement direction
	local function at(dx, dy, dz)
		return Vector3.new(x + dx, r + dy, z + dz)
	end
	local look = CFrame.lookAt(Vector3.zero, Vector3.new(fx, 0, fz))
	local function put(p, pos, rot)
		table.insert(partsOut, p)
		table.insert(cframesOut, CFrame.new(pos) * (rot or look))
	end
	put(v.body, at(0, 0, 0))
	put(v.nucleus, at(-fx * r * 0.2, r * 0.25, -fz * r * 0.2))
	local ex, ez = fx * r * 0.42, fz * r * 0.42
	local sx, sz = rx * r * 0.32, rz * r * 0.32
	put(v.eyeL, at(ex - sx, r * 0.75, ez - sz))
	put(v.eyeR, at(ex + sx, r * 0.75, ez + sz))
	local px, pz = fx * r * 0.52, fz * r * 0.52
	put(v.pupilL, at(px - sx, r * 0.92, pz - sz))
	put(v.pupilR, at(px + sx, r * 0.92, pz + sz))
	if v.jawL then
		local chomp = 0.15 + math.abs(math.sin(t * 8)) * 0.15
		put(v.jawL, at(fx * r * 1.0 - rx * r * chomp, 0, fz * r * 1.0 - rz * r * chomp))
		put(v.jawR, at(fx * r * 1.0 + rx * r * chomp, 0, fz * r * 1.0 + rz * r * chomp))
	end
	if v.tail then
		local wiggle = math.sin(t * 12) * 0.35
		local tailLook = CFrame.lookAt(Vector3.zero, Vector3.new(fx + rx * wiggle, 0, fz + rz * wiggle))
		put(v.tail, at(-fx * r * 1.35, 0, -fz * r * 1.35), tailLook)
	end
	if v.spikes then
		local spin = t * 0.6
		for i, s in v.spikes do
			local a = (i / #v.spikes) * math.pi * 2 + spin
			local dx, dz = math.cos(a), math.sin(a)
			put(s, at(dx * r * 1.05, 0, dz * r * 1.05), CFrame.lookAt(Vector3.zero, Vector3.new(dx, 0, dz)))
		end
	end
	if v.shell then
		put(v.shell, at(0, 0, 0))
	end
	put(v.shield, at(0, 0, 0))
end

-- Snapshots ------------------------------------------------------------------------------

local latest = {} -- [cellId] = { x, z, size, flags }

function Renderer.applyInfo(payload)
	for germId, info in payload.germs do
		Renderer.germInfo[germId] = info
		-- rebuild visuals of this germ's cells so new mutations show
		for cellId, gid in Renderer.cellGerm do
			if gid == germId and Renderer.cells[cellId] then
				Renderer.cells[cellId].model:Destroy()
				Renderer.cells[cellId] = nil
			end
		end
	end
	for cellId, germId in payload.cells do
		Renderer.cellGerm[cellId] = germId
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
	local seen = {}
	local count = (buffer.len(buf) - 4) // 17
	for i = 0, count - 1 do
		local o = 4 + i * 17
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
	-- cells missing from the snapshot are gone
	for id in latest do
		if not seen[id] then
			Renderer.removeCells({ id })
		end
	end
end

function Renderer.state(cellId)
	return latest[cellId]
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
				-- turn smoothly to face where we are going
				local tx, tz = mx / moved, mz / moved
				local dx, dz = v.dirX + (tx - v.dirX) * 0.25, v.dirZ + (tz - v.dirZ) * 0.25
				local len = math.sqrt(dx * dx + dz * dz)
				if len > 0.001 then
					v.dirX, v.dirZ = dx / len, dz / len
				end
			end
			v.x, v.z = nx, nz
			v.size = v.size + (s.size - v.size) * k
			v.r = Formulas.radius(v.size, SCALE)
			if math.abs(v.r - v.drawnR) > v.drawnR * 0.01 then
				resize(v, v.r)
			end
			local crown = bit32.band(s.flags, FLAG_CROWN) ~= 0
			v.shield.Transparency = (bit32.band(s.flags, FLAG_PROTECTED) ~= 0) and 0.3 or 1
			local text = v.info.name .. "\n" .. Formulas.formatNumber(s.size)
			if crown then
				text = "👑 " .. text
			end
			if bit32.band(s.flags, FLAG_DASH) ~= 0 then
				text = "💨 " .. text
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
	return sx / total, sz / total, Formulas.radius(total, SCALE), total
end

-- Biggest germs for the size board: { { name, size, germId } }
function Renderer.board(limit)
	local sizes = {}
	for id, s in latest do
		local germId = Renderer.cellGerm[id]
		if germId then
			sizes[germId] = (sizes[germId] or 0) + s.size
		end
	end
	local list = {}
	for germId, size in sizes do
		local info = Renderer.germInfo[germId]
		table.insert(list, { name = info and info.name or "?", size = size, germId = germId })
	end
	table.sort(list, function(a, b)
		return a.size > b.size
	end)
	while #list > limit do
		table.remove(list)
	end
	return list
end

local _ = Config
return Renderer
