-- Builds what a dish looks like, at the dish's spot in the world:
--   hosts: four ring-shaped zones in the host's colours, glowing membranes, a fleshy outer wall,
--          spawn bubbles and the Sneeze Nerve in the middle
--   Arena floors: a glass petri dish with a grid and the Exit Pore in the middle
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local root = Instance.new("Folder")
root.Name = "Dishes"
root.Parent = workspace

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- A flat disc whose top surface sits at height y
local function disc(parent, cx, cz, radius, y, color, name, material)
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, radius * 2, radius * 2),
		CFrame = CFrame.new(cx, y - 1, cz) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

-- A ring of short segments (membranes and the outer wall)
local function ring(parent, cx, cz, radius, segments, height, thickness, color, material, transparency)
	local model = Instance.new("Model")
	model.Name = "Ring" .. math.floor(radius)
	model.Parent = parent
	local length = 2 * math.pi * radius / segments + 0.4
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		part(model, {
			Size = Vector3.new(length, height, thickness),
			CFrame = CFrame.new(cx + math.cos(a) * radius, height / 2, cz + math.sin(a) * radius) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = color,
			Material = material,
			Transparency = transparency or 0,
		})
	end
	return model
end

-- The dish's edge, flat: a wide band under the floor's edge plus a low lip on the edge itself
local function flatWall(parent, cx, cz, radius, color, material)
	disc(parent, cx, cz, radius + 70, -0.1, color, "WallBand", material)
	disc(parent, cx, cz, radius + 72, -0.2, color:Lerp(Color3.new(0, 0, 0), 0.35), "WallEdge")
	ring(parent, cx, cz, radius + 1.5, 90, 1.6, 3, color:Lerp(Color3.new(1, 1, 1), 0.25), Enum.Material.SmoothPlastic, 0)
end

-- Text written on the floor, readable from the top-down camera
local function floorLabel(parent, text, x, z, width, color)
	local p = part(parent, {
		Name = "Label",
		Size = Vector3.new(width, 0.2, width / 4),
		CFrame = CFrame.new(x, 0.3, z),
		Transparency = 1,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 10
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextTransparency = 0.35
	label.TextStrokeTransparency = 0.7
	label.Parent = gui
end

local function centreTag(parent, nerve, text, color)
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(260, 60)
	tag.StudsOffset = Vector3.new(0, 18, 0)
	tag.AlwaysOnTop = true
	tag.Parent = nerve
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = tag
	local _ = parent
end

-- Little blobs on the floor so movement is easy to see
local function decorate(parent, cx, cz, zones, zone, color)
	local info = zones[zone]
	local inner = zones[zone + 1] and zones[zone + 1].Outer or 0
	local count = math.floor((info.Outer - inner) * 0.3)
	for _ = 1, count do
		local a = math.random() * math.pi * 2
		local d = inner + 6 + math.random() * math.max(1, info.Outer - inner - 12)
		local r = 3 + math.random() * 9
		part(parent, {
			Name = "Blob",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, r * 2, r * 2),
			CFrame = CFrame.new(cx + math.cos(a) * d, 0.02 + zone * 0.05, cz + math.sin(a) * d) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color:Lerp(Color3.new(0, 0, 0), 0.06 + math.random() * 0.06),
		})
	end
end

local function buildHost(folder, dish)
	local host = Config.Hosts[dish.host]
	local cx, cz = dish.cx, dish.cz
	local zones = dish.layout.zones
	for i, info in zones do
		local floor = rgb(host.Floors[i])
		disc(folder, cx, cz, info.Outer, (i - 1) * 0.05, floor, host.Zones[i])
		decorate(folder, cx, cz, zones, i, floor)
	end
	for i = 2, #zones do
		ring(folder, cx, cz, zones[i].Outer, 72, 1.2, 2.5, rgb(host.Membranes[i]), Enum.Material.Neon, 0.25)
	end
	-- the wall: a flat fleshy band that starts under the floor's edge (so no background shows
	-- between floor and wall), a low lip on the edge, and darker lumps. Tall walls looked like
	-- slanted 3D blocks from the top-down camera.
	local radius = dish.layout.radius
	local wall = rgb(host.Wall)
	flatWall(folder, cx, cz, radius, wall, Enum.Material.SmoothPlastic)
	for i = 1, 36 do
		local a = (i + math.random() * 0.6) / 36 * math.pi * 2
		local d = radius + 22 + math.random() * 34
		local r = 10 + math.random() * 14
		part(folder, {
			Name = "WallLump",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, r * 2, r * 2),
			CFrame = CFrame.new(cx + math.cos(a) * d, -0.06, cz + math.sin(a) * d) * CFrame.Angles(0, 0, math.rad(90)),
			Color = wall:Lerp(Color3.new(0, 0, 0), 0.12 + math.random() * 0.1),
		})
	end
	disc(folder, cx, cz, radius + 400, -0.5, rgb(host.Outside), "Outside")
	for i, info in zones do
		local inner = zones[i + 1] and zones[i + 1].Outer or 0
		local mid = (info.Outer + inner) / 2
		if i == #zones then
			mid = info.Outer * 0.55
		end
		floorLabel(folder, host.Zones[i], cx, cz - mid, math.min(120, (info.Outer - inner) * 1.6))
	end
	floorLabel(folder, host.Name, cx, cz + dish.layout.radius - 40, 160, rgb(host.Membranes[1]))
	for _, b in dish.bubbles do
		part(folder, {
			Name = "SpawnBubble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * Config.SpawnBubbleRadius * 2,
			CFrame = CFrame.new(cx + b.x, 0, cz + b.z),
			Color = Color3.fromRGB(150, 220, 255),
			Material = Enum.Material.ForceField,
			Transparency = 0.2,
		})
	end
	local nerve = part(folder, {
		Name = "SneezeNerve",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * Config.NerveRadius * 2,
		CFrame = CFrame.new(cx, 2, cz),
		Color = Color3.fromRGB(255, 230, 120),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	})
	centreTag(folder, nerve, "SNEEZE NERVE\nreach the sneeze size and touch it!", Color3.fromRGB(255, 240, 160))
end

local function buildArena(folder, dish)
	local cx, cz = dish.cx, dish.cz
	local r = dish.layout.radius
	disc(folder, cx, cz, r, 0, Color3.fromRGB(205, 230, 240), "Glass", Enum.Material.Glass)
	disc(folder, cx, cz, r + 400, -0.5, Color3.fromRGB(15, 20, 35), "Outside")
	-- grid lines like a real petri dish
	local step = 20
	for x = -r, r, step do
		local half = math.sqrt(math.max(0, r * r - x * x))
		if half > 1 then
			part(folder, { Name = "Grid", Size = Vector3.new(0.4, 0.05, half * 2), CFrame = CFrame.new(cx + x, 0.05, cz), Color = Color3.fromRGB(160, 200, 220) })
			part(folder, { Name = "Grid", Size = Vector3.new(half * 2, 0.05, 0.4), CFrame = CFrame.new(cx, 0.05, cz + x), Color = Color3.fromRGB(160, 200, 220) })
		end
	end
	flatWall(folder, cx, cz, r, Color3.fromRGB(150, 205, 230), Enum.Material.SmoothPlastic)
	local pore = part(folder, {
		Name = "ExitPore",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * Config.NerveRadius * 2,
		CFrame = CFrame.new(cx, 2, cz),
		Color = Color3.fromRGB(120, 255, 200),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	})
	centreTag(folder, pore, "EXIT PORE\nreach size " .. dish.layout.sneeze .. " and touch it", Color3.fromRGB(160, 255, 210))
	floorLabel(folder, "FLOOR " .. dish.floor, cx, cz + r * 0.6, 100, Color3.fromRGB(60, 90, 120))
end

-- Builds a dish's look. Returns the folder (destroy it when the dish is removed).
function MapBuilder.buildDish(dish)
	local folder = Instance.new("Folder")
	folder.Name = (dish.kind == "host" and ("Host" .. dish.host) or ("Floor" .. dish.floor)) .. "_" .. dish.id
	if dish.kind == "host" then
		buildHost(folder, dish)
	else
		buildArena(folder, dish)
	end
	folder.Parent = root
	return folder
end

function MapBuilder.setup()
	for _, name in { "Baseplate", "SpawnLocation", "Host" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.GlobalShadows = false
	Lighting.Ambient = Color3.fromRGB(150, 130, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(180, 160, 160)
end

return MapBuilder
