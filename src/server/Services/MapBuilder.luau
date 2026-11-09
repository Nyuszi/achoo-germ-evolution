-- Builds the inside of host 1 (Nibbles the Hamster) as a round dish seen from above:
-- four ring-shaped zones, glowing membranes between them, a fleshy outer wall,
-- spawn bubbles and the Sneeze Nerve in the middle.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local ZONE_LOOK = {
	{ floor = Color3.fromRGB(255, 196, 196), membrane = Color3.fromRGB(255, 120, 150) }, -- Nose Cave
	{ floor = Color3.fromRGB(255, 220, 180), membrane = Color3.fromRGB(255, 170, 90) }, -- Cheek Pouch
	{ floor = Color3.fromRGB(250, 200, 140), membrane = Color3.fromRGB(230, 120, 60) }, -- Tummy
	{ floor = Color3.fromRGB(220, 90, 100), membrane = Color3.fromRGB(255, 60, 80) }, -- Heart
}

local folder

local function part(props)
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
	p.Parent = props.Parent or folder
	return p
end

-- A flat disc whose top surface sits at height y
local function disc(radius, y, color, name)
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, radius * 2, radius * 2),
		CFrame = CFrame.new(0, y - 1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
	})
end

-- A ring of short segments (membranes and the outer wall)
local function ring(radius, segments, height, thickness, color, material, transparency, y)
	local model = Instance.new("Model")
	model.Name = "Ring" .. radius
	model.Parent = folder
	local length = 2 * math.pi * radius / segments + 0.4
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		part({
			Size = Vector3.new(length, height, thickness),
			CFrame = CFrame.new(math.cos(a) * radius, (y or 0) + height / 2, math.sin(a) * radius)
				* CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = color,
			Material = material,
			Transparency = transparency or 0,
			Parent = model,
		})
	end
end

-- Zone name written on the floor, readable from the top-down camera
local function floorLabel(text, x, z, width)
	local p = part({
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
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextTransparency = 0.35
	label.TextStrokeTransparency = 0.7
	label.Parent = gui
end

-- Little blobs on the floor so movement is easy to see
local function decorate(zone, info)
	local inner = 0
	if Config.Zones[zone + 1] then
		inner = Config.Zones[zone + 1].Outer
	end
	local count = math.floor((info.Outer - inner) * 0.35)
	for _ = 1, count do
		local a = math.random() * math.pi * 2
		local d = inner + 6 + math.random() * (info.Outer - inner - 12)
		local r = 3 + math.random() * 9
		local c = ZONE_LOOK[zone].floor:Lerp(Color3.new(0, 0, 0), 0.06 + math.random() * 0.06)
		part({
			Name = "Blob",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, r * 2, r * 2),
			CFrame = CFrame.new(math.cos(a) * d, 0.02 + zone * 0.05, math.sin(a) * d) * CFrame.Angles(0, 0, math.rad(90)),
			Color = c,
		})
	end
end

function MapBuilder.build(bubbles)
	for _, name in { "Baseplate", "SpawnLocation", "Host" } do
		local old = workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	folder = Instance.new("Folder")
	folder.Name = "Host"
	folder.Parent = workspace

	-- zone floors, outer ring first, each one a hair higher than the last
	for i, info in Config.Zones do
		disc(info.Outer, (i - 1) * 0.05, ZONE_LOOK[i].floor, info.Name)
		decorate(i, info)
	end
	-- membranes between zones (you need to be big enough to pass them)
	for i = 2, #Config.Zones do
		ring(Config.Zones[i].Outer, 72, 1.2, 2.5, ZONE_LOOK[i].membrane, Enum.Material.Neon, 0.25)
	end
	-- fleshy outer wall
	ring(Config.ArenaRadius + 3, 96, 14, 6, Color3.fromRGB(200, 110, 120), Enum.Material.SmoothPlastic, 0)
	-- dark void outside the host
	disc(Config.ArenaRadius + 400, -0.5, Color3.fromRGB(60, 20, 30), "Outside")

	-- zone names on the floor (north side of each ring)
	for i, info in Config.Zones do
		local inner = 0
		if Config.Zones[i + 1] then
			inner = Config.Zones[i + 1].Outer
		end
		local mid = (info.Outer + inner) / 2
		if i == #Config.Zones then
			mid = info.Outer * 0.55
		end
		floorLabel(info.Name, 0, -mid, math.min(120, (info.Outer - inner) * 1.6))
	end

	-- spawn bubbles: safe spots where nobody can be eaten for a while
	for _, b in bubbles do
		part({
			Name = "SpawnBubble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * Config.SpawnBubbleRadius * 2,
			CFrame = CFrame.new(b.x, 0, b.z),
			Color = Color3.fromRGB(150, 220, 255),
			Material = Enum.Material.ForceField,
			Transparency = 0.2,
		})
	end

	-- the Sneeze Nerve in the heart (sneezing arrives in the next update)
	local nerve = part({
		Name = "SneezeNerve",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 26,
		CFrame = CFrame.new(0, 2, 0),
		Color = Color3.fromRGB(255, 230, 120),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	})
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(260, 60)
	tag.StudsOffset = Vector3.new(0, 18, 0)
	tag.AlwaysOnTop = true
	tag.Parent = nerve
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 240, 160)
	text.TextStrokeTransparency = 0.3
	text.Text = "SNEEZE NERVE\n(coming soon!)"
	text.Parent = tag

	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.GlobalShadows = false
	Lighting.Ambient = Color3.fromRGB(150, 110, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(180, 140, 140)
end

return MapBuilder
