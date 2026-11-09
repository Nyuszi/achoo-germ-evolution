-- Draws the dish events the server tells us about: ink clouds, warp holes, the whisker sweep,
-- burning rings, the closing wall (Medicine, Arena sudden death), spikes, fever glow and fog.
local Lighting = game:GetService("Lighting")

local Fx = {}

local folder = Instance.new("Folder")
folder.Name = "DishFx"
folder.Parent = workspace

local dish = nil
local groups = {} -- [kind] = { parts }
local whisker = nil -- { part, start, duration, angle, length }
local wall = nil -- { model, radius, target }
local fever = Instance.new("ColorCorrectionEffect")
fever.Enabled = false
fever.TintColor = Color3.fromRGB(255, 200, 190)
fever.Saturation = 0.15
fever.Parent = Lighting
Fx.banner = function(text) end -- set by the HUD
Fx.bossHp = function(data) end
Fx.arenaTimer = function(data) end
Fx.mirror = false
Fx.fog = false

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		p[k] = v
	end
	p.Parent = folder
	return p
end

local function clear(kind)
	for _, p in groups[kind] or {} do
		p:Destroy()
	end
	groups[kind] = nil
end

local function disc(x, z, r, y, color, transparency, material)
	return part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, r * 2, r * 2),
		CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = transparency or 0,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function ringParts(cx, cz, radius, width, color, transparency, y)
	local list = {}
	local segments = 64
	local length = 2 * math.pi * radius / segments + 0.6
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		table.insert(list, part({
			Size = Vector3.new(length, 0.6, width),
			CFrame = CFrame.new(cx + math.cos(a) * radius, y or 0.6, cz + math.sin(a) * radius) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = transparency or 0.3,
		}))
	end
	return list
end

function Fx.setDish(info)
	for kind in groups do
		clear(kind)
	end
	if whisker then
		whisker.part:Destroy()
		whisker = nil
	end
	if wall then
		for _, p in wall.parts do
			p:Destroy()
		end
		wall = nil
	end
	dish = info
	fever.Enabled = false
	Fx.mirror = false
	Fx.fog = table.find(info.modifiers or {}, "Fog") ~= nil
	if info.wall and info.wall < info.radius - 1 then
		Fx.event("Medicine", { wall = info.wall, duration = 0 })
	end
	if Fx.fog then
		Fx.banner("🌫️ Fog: you can only see close by")
	end
end

local function setWall(target)
	if not dish then
		return
	end
	if not wall then
		wall = { parts = {}, radius = dish.radius, target = target }
	end
	wall.target = target
end

function Fx.event(kind, data)
	if not dish then
		return
	end
	if kind == "Ink" then
		clear("Ink")
		groups.Ink = {}
		for _, c in data do
			table.insert(groups.Ink, disc(c.x, c.z, c.r, 3, Color3.fromRGB(20, 15, 40), 0.15))
		end
	elseif kind == "Warps" then
		clear("Warps")
		groups.Warps = {}
		for i, h in data do
			local color = (i <= 2) and Color3.fromRGB(190, 90, 255) or Color3.fromRGB(80, 255, 200)
			table.insert(groups.Warps, disc(h.x, h.z, h.r, 0.4, color, 0.1, Enum.Material.Neon))
			table.insert(groups.Warps, disc(h.x, h.z, h.r * 0.6, 0.6, Color3.fromRGB(10, 5, 20), 0))
		end
	elseif kind == "Spikes" then
		clear("Spikes")
		groups.Spikes = {}
		for _, s in data do
			table.insert(groups.Spikes, part({ Shape = Enum.PartType.Ball, Size = Vector3.one * s.r * 2, CFrame = CFrame.new(s.x, 0, s.z), Color = Color3.fromRGB(200, 40, 50), Material = Enum.Material.Neon, Transparency = 0.2 }))
		end
	elseif kind == "Whiskers" then
		if whisker then
			whisker.part:Destroy()
		end
		whisker = {
			part = part({ Size = Vector3.new(data.length, 1.5, 3), Color = Color3.fromRGB(60, 40, 30) }),
			start = os.clock(),
			duration = data.duration,
			angle = data.angle,
			length = data.length,
		}
		Fx.banner("〰️ WHISKER SWEEP! Watch out for the big whisker")
	elseif kind == "Drool" then
		Fx.banner("💧 DROOL WAVE! Everything slides one way")
		clear("Flow")
		groups.Flow = { disc(dish.cx, dish.cz, dish.radius, 0.9, Color3.fromRGB(140, 200, 255), 0.8, Enum.Material.Glass) }
	elseif kind == "Suction" then
		Fx.banner("🌀 TRUNK SUCTION! You're being pulled to the middle")
		clear("Flow")
		groups.Flow = { disc(dish.cx, dish.cz, dish.radius, 0.9, Color3.fromRGB(200, 200, 220), 0.85, Enum.Material.Glass) }
	elseif kind == "FireWarn" then
		Fx.banner("🔥 FIRE BURP in " .. data.seconds .. " seconds! Get inside the " .. (dish.zones[2] and dish.zones[2].name or "middle"))
		clear("Fire")
		groups.Fire = ringParts(dish.cx, dish.cz, (data.from + dish.radius) / 2, 3, Color3.fromRGB(255, 160, 40), 0.5, 0.7)
	elseif kind == "Fire" then
		clear("Fire")
		local width = dish.radius - data.from
		groups.Fire = ringParts(dish.cx, dish.cz, data.from + width / 2, width, Color3.fromRGB(255, 90, 20), 0.55, 0.5)
		Fx.banner("🔥 The outer ring is BURNING!")
	elseif kind == "HazardEnd" then
		clear("Fire")
		clear("Flow")
	elseif kind == "Fever" then
		fever.Enabled = true
	elseif kind == "FeverEnd" then
		fever.Enabled = false
	elseif kind == "Medicine" then
		setWall(data.wall)
	elseif kind == "MedicineEnd" then
		setWall(data.wall)
	elseif kind == "BossHp" then
		Fx.bossHp(data)
	elseif kind == "ArenaTimer" then
		Fx.arenaTimer(data)
	elseif kind == "Mirror" then
		Fx.mirror = data.on
		if data.on then
			Fx.banner("🪞 MIRROR! Your controls are flipped")
		end
	end
end

-- Called every frame
function Fx.update(dt, camHeight)
	if whisker then
		local p = (os.clock() - whisker.start) / whisker.duration
		if p >= 1 then
			whisker.part:Destroy()
			whisker = nil
		else
			local a = whisker.angle + p * math.pi * 2
			local half = whisker.length / 2
			whisker.part.CFrame = CFrame.new(dish.cx + math.cos(a) * half, 1.5, dish.cz + math.sin(a) * half) * CFrame.Angles(0, -a, 0)
		end
	end
	if wall and dish then
		local d = wall.target - wall.radius
		wall.radius += d * math.min(1, dt * 0.6)
		if math.abs(d) > 0.05 and os.clock() - (wall.lastDraw or 0) > 0.3 then
			for _, p in wall.parts do
				p:Destroy()
			end
			wall.parts = {}
			if wall.radius < dish.radius - 1 then
				wall.parts = ringParts(dish.cx, dish.cz, wall.radius + 2, 4, Color3.fromRGB(120, 255, 160), 0.2, 2)
			end
			wall.lastDraw = os.clock()
		end
	end
	if Fx.fog then
		Lighting.FogColor = Color3.fromRGB(200, 210, 220)
		Lighting.FogStart = camHeight + 5
		Lighting.FogEnd = camHeight + 70
	else
		Lighting.FogStart = 0
		Lighting.FogEnd = 100000
	end
end

return Fx
