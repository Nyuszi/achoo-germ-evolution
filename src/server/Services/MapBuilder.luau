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
	gui.MaxDistance = 100000
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
	-- outer zones: many small blobs; inner zones: fewer, bigger ones (everything in there is bigger)
	local big = 1 + (zone - 1) * 0.7
	local count = math.floor((info.Outer - inner) * 0.34 / big)
	for _ = 1, count do
		local a = math.random() * math.pi * 2
		local d = inner + 6 + math.random() * math.max(1, info.Outer - inner - 12)
		local r = (3 + math.random() * 9) * big
		part(parent, {
			Name = "Blob",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, r * 2, r * 2),
			CFrame = CFrame.new(cx + math.cos(a) * d, 0.02 + zone * 0.05, cz + math.sin(a) * d) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color:Lerp(Color3.new(0, 0, 0), 0.06 + math.random() * 0.06),
		})
	end
end

-- count shapes round the band; from/spread = how far out; size/vary = how big; block = a long
-- box of that length instead of a disc; light = lighter than the wall instead of darker
local WALL_STYLES = {
	{ count = 64, from = 14, spread = 30, size = 5, vary = 4, block = 20, mix = 0.14 }, -- fur tufts (pointing outward)
	{ count = 30, from = 26, spread = 24, size = 14, vary = 12, mix = 0.1, light = true }, -- wet gums
	{ count = 44, from = 10, spread = 46, size = 3, vary = 2, block = 54, mix = 0.16, turn = math.pi / 2 }, -- wrinkles (along the wall)
	{ count = 56, from = 16, spread = 22, size = 9, vary = 2, mix = 0.14, even = true }, -- scales
	{ count = 26, from = 30, spread = 14, size = 13, vary = 6, mix = 0.12, ring = true }, -- suckers
	{ count = 36, from = 18, spread = 26, size = 4, vary = 1, block = 26, mix = 0.35, light = true, neon = true, even = true, turn = math.pi / 2 }, -- panels
}

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
	-- every host's wall has its own texture, made of flat shapes on the band:
	-- hamster fur tufts, dog gums, elephant wrinkles, dragon scales, kraken suckers, alien panels
	local style = WALL_STYLES[dish.host] or WALL_STYLES[1]
	for i = 1, style.count do
		local a = (i + (style.even and 0 or math.random() * 0.6)) / style.count * math.pi * 2
		local d = radius + style.from + (style.even and (i % 2) * style.spread or math.random() * style.spread)
		local r = style.size + math.random() * style.vary
		local tone = style.light and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
		local color = wall:Lerp(tone, style.mix + math.random() * 0.1)
		if style.block then
			-- long shapes lying across the band (wrinkles, tufts, panels)
			part(folder, {
				Name = "WallLump",
				Size = Vector3.new(style.block, 0.1, r),
				CFrame = CFrame.new(cx + math.cos(a) * d, -0.06, cz + math.sin(a) * d) * CFrame.Angles(0, -a + (style.turn or 0), 0),
				Color = color,
				Material = style.neon and Enum.Material.Neon or Enum.Material.SmoothPlastic,
			})
		else
			part(folder, {
				Name = "WallLump",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.1, r * 2, r * 2),
				CFrame = CFrame.new(cx + math.cos(a) * d, -0.06, cz + math.sin(a) * d) * CFrame.Angles(0, 0, math.rad(90)),
				Color = color,
			})
			if style.ring then
				-- a sucker: a lighter middle
				part(folder, {
					Name = "WallLump",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.1, r, r),
					CFrame = CFrame.new(cx + math.cos(a) * d, -0.04, cz + math.sin(a) * d) * CFrame.Angles(0, 0, math.rad(90)),
					Color = wall:Lerp(Color3.new(1, 1, 1), 0.3),
				})
			end
		end
	end
	local outside = rgb(host.Outside)
	disc(folder, cx, cz, radius + 400, -0.5, outside, "Outside")
	-- the dark beyond the wall isn't empty: big soft shapes far out
	for _ = 1, 26 do
		local a = math.random() * math.pi * 2
		local d = radius + 110 + math.random() * 250
		local r = 14 + math.random() * 30
		part(folder, {
			Name = "Beyond",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, r * 2, r * 2),
			CFrame = CFrame.new(cx + math.cos(a) * d, -0.44, cz + math.sin(a) * d) * CFrame.Angles(0, 0, math.rad(90)),
			Color = outside:Lerp(wall, 0.18 + math.random() * 0.2),
		})
	end
	-- a soft glow on the floor under the Sneeze Nerve so the goal shows from far away
	local top = #zones * 0.05
	part(folder, {
		Name = "NerveGlow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, Config.NerveRadius * 5, Config.NerveRadius * 5),
		CFrame = CFrame.new(cx, top, cz) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 230, 120),
		Material = Enum.Material.Neon,
		Transparency = 0.75,
	})
	part(folder, {
		Name = "NerveGlow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, Config.NerveRadius * 3.2, Config.NerveRadius * 3.2),
		CFrame = CFrame.new(cx, top + 0.03, cz) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 240, 160),
		Material = Enum.Material.Neon,
		Transparency = 0.55,
	})
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

local ARENA_TINTS = {
	Fever = Color3.fromRGB(255, 120, 110), LowGravity = Color3.fromRGB(190, 140, 255), Fog = Color3.fromRGB(150, 155, 165),
	SpikeField = Color3.fromRGB(255, 170, 90), TinyDish = Color3.fromRGB(140, 235, 170), GoldenRain = Color3.fromRGB(255, 220, 110),
	Mirror = Color3.fromRGB(150, 230, 255), MagnetStorm = Color3.fromRGB(120, 150, 255), CloneParty = Color3.fromRGB(255, 160, 220),
	GiantWhitey = Color3.fromRGB(245, 245, 255),
}

local function buildArena(folder, dish)
	local cx, cz = dish.cx, dish.cz
	local r = dish.layout.radius
	-- the glass is tinted by the floor's first modifier, so floors don't all look the same
	local glass = Color3.fromRGB(205, 230, 240)
	local tint = dish.modifiers and ARENA_TINTS[dish.modifiers[1]]
	if tint then
		glass = glass:Lerp(tint, 0.4)
	end
	disc(folder, cx, cz, r, 0, glass, "Glass", Enum.Material.Glass)
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
