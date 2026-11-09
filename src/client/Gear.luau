-- Gear: the Lab mutations drawn as flat 2D art on the germ, and animated so you can see what
-- each one does. Built on the same square Frame as Looks (the body's disc: 0..1 both ways,
-- centre 0.5, radius 0.5). The game's look billboard is twice the body, so art may reach from
-- -0.5 to 1.5.
--
-- Most of it sits in the "Gear" group, which Gear.animate turns every frame so its top points
-- where the germ swims: front parts (Jaws, Suction, Drill) are drawn at the top, back parts
-- (Flagella, Jet, Slime) at the bottom. Camo blotches and the Sneezer nose do not turn.
--
-- Animations (Gear.animate state: dx, dz, fight, dash, power, powerAge):
--   Jaws      steel chompers that open and shut slowly, snap fast in a fight, 3 times on Chomp
--   Suction   a steel intake with a spinning turbine, a vortex and food motes flowing in
--             (Vacuum: the vortex grows and spins hard)
--   Drill     a striped cone that spins (Pierce: glows orange and throws sparks)
--   Flagella  two whipping tails (faster while dashing)
--   Jet       two nozzles with flickering flames (long blue-hot flames while dashing)
--   Slime     dripping goo (the Renderer also leaves puddles on the floor)
--   Spikes    a ring of thorns that turns (Buzzsaw: spins fast while dashing), red tips in fights
--   Toxin     four throbbing poison canisters leaking bubbles
--   Shell     riveted steel plates that flash when hit
--   Magnet    a horseshoe magnet with ripples (Gravity well: a ring of dots spiralling in)
--   Sneezer   a twitchy nose (Blast: shock rings and spray)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Looks = require(script.Parent.Looks)

local Gear = {}

local S = Looks.shapes
local box, circle, tri, bar, arc = S.box, S.circle, S.tri, S.bar, S.arc

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local INK = rgb(32, 22, 44)
local WHITE = rgb(255, 255, 255)
local PINK = rgb(255, 120, 150)
local STEEL = rgb(190, 195, 210)
local STEEL_DARK = rgb(95, 100, 120)
local THROAT = rgb(70, 10, 30)

local function lerp(a, b, k)
	return a:Lerp(b, k)
end
local function shade(a, b)
	return ColorSequence.new(a, b)
end
local function fade(from, to)
	return NumberSequence.new(from, to)
end

-- A see-through frame centred on (x, y), w by h of its parent, to group parts in its own 0..1 space
local function sub(parent, x, y, w, h, z, name)
	local f = Instance.new("Frame")
	f.Name = name or "Part"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

-- Is this mutation on (by itself, or as part of a fusion)?
function Gear.has(muts, id)
	for _, m in muts or {} do
		if m == id then
			return true
		end
		local f = Config.Fusions[(string.gsub(m, "^#", ""))]
		if f and table.find(f.Parts, id) then
			return true
		end
	end
	return false
end

-- A mouth mutation replaces the skin's mouth (no germ with two mouths)
function Gear.mouthless(muts)
	return Gear.has(muts, "Jaws") or Gear.has(muts, "Suction")
end

function Gear.fused(muts, id)
	for _, m in muts or {} do
		if string.gsub(m, "^#", "") == id then
			return true
		end
	end
	return false
end

local BUILD = {}

-- Front -------------------------------------------------------------------------------------------

-- Gradient cut: keep one half of a shape (hard step in transparency)
local function keepHalf(first)
	local a, b = first and 0 or 1, first and 1 or 0
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, a),
		NumberSequenceKeypoint.new(0.499, a),
		NumberSequenceKeypoint.new(0.501, b),
		NumberSequenceKeypoint.new(1, b),
	})
end

-- steel chompers at the front: two riveted half-disc jaws with big teeth that open on a dark
-- throat and snap shut (like a robot mouth / bear trap)
local function chomperJaw(parent, up, tooth)
	local j = sub(parent, 0.5, 0.5, 1, 1, up and 3 or 2, up and "UpperJaw" or "LowerJaw")
	local cut = { trans = keepHalf(up), rot = 90 }
	box(j, 0.5, 0.5, 1, 1, INK, { z = 1, grad = cut })
	box(j, 0.5, 0.5, 0.9, 0.9, STEEL, { z = 2, grad = { trans = keepHalf(up), rot = 90, color = up and shade(WHITE, rgb(140, 145, 165)) or shade(rgb(140, 145, 165), rgb(210, 215, 230)) } })
	local ry = up and 0.3 or 0.7
	box(j, 0.5, up and 0.46 or 0.54, 0.86, 0.05, STEEL_DARK, { z = 3, corner = false }) -- the jaw's lip
	for _, x in { 0.3, 0.7 } do
		circle(j, x, ry, 0.08, STEEL_DARK, { z = 3 })
		circle(j, x - 0.01, ry - 0.01, 0.035, WHITE, { z = 4, t = 0.3 })
	end
	for i = 0, 5 do
		local x = 0.17 + i * 0.132
		tri(j, x, up and 0.49 or 0.51, 0.15, up and 180 or 0, tooth, { z = 5 })
	end
	return j
end

function BUILD.Jaws(g, h, color, o)
	local trap = sub(g, 0.5, -0.1, 0.64, 0.64, 3, "Jaws")
	local tooth = o.venom and rgb(170, 255, 90) or WHITE
	local throat = box(trap, 0.5, 0.5, 0.8, 0.1, THROAT, { z = 1, corner = UDim.new(0.3, 0), grad = { color = shade(rgb(40, 5, 20), rgb(150, 35, 60)), rot = 90 } })
	local upper = chomperJaw(trap, true, tooth)
	local lower = chomperJaw(trap, false, tooth)
	-- hinge bolts on both sides
	for _, x in { 0.02, 0.98 } do
		circle(trap, x, 0.5, 0.16, INK, { z = 6 })
		circle(trap, x, 0.5, 0.12, STEEL_DARK, { z = 7, grad = { color = shade(WHITE, rgb(120, 120, 140)), rot = 90 } })
		box(trap, x, 0.5, 0.08, 0.025, INK, { z = 8, rot = 45, corner = false })
	end
	h.jaws = { trap = trap, upper = upper, lower = lower, throat = throat }
end

local function animJaws(j, t, st)
	local open, grow = 0.5 + 0.3 * math.sin(t * 2.5), 1
	if st.power == "Chomp" and st.powerAge < 1 then
		open = math.abs(math.cos(st.powerAge * math.pi * 3))
		grow = 1.3
	elseif st.fight then
		open = math.abs(math.cos(t * 10))
		grow = 1.1
	end
	local gap = 0.02 + 0.48 * open
	j.trap.Size = UDim2.fromScale(0.64 * grow, 0.64 * grow)
	j.upper.Position = UDim2.fromScale(0.5, 0.5 - gap / 2)
	j.lower.Position = UDim2.fromScale(0.5, 0.5 + gap / 2)
	j.throat.Size = UDim2.fromScale(0.8, gap + 0.04)
end

-- a steel intake at the front with a spinning turbine; a vortex pulls food motes into it
function BUILD.Suction(g, h, color, o)
	local dark = o.blackHole
	local rim = dark and rgb(90, 50, 140) or STEEL
	local swirl = dark and rgb(170, 110, 255) or rgb(200, 240, 255)
	local vortex = sub(g, 0.5, -0.14, 0.55, 0.55, 1, "Vortex")
	for k = 0, 2 do
		local r = 0.44 - k * 0.12
		arc(vortex, 0.5, 0.5, r, r, k * 120, k * 120 + 210, 0.05, swirl, { t = 0.3 + k * 0.1, n = 6 })
	end
	local motes = {}
	for i = 1, 4 do
		table.insert(motes, circle(g, 0.5, -0.3, 0.05, dark and rgb(220, 180, 255) or rgb(255, 230, 140), { z = 2, t = 0.2 }))
	end
	local mouth = sub(g, 0.5, 0.04, 0.5, 0.5, 3, "Suction")
	circle(mouth, 0.5, 0.5, 1, INK, { z = 1, t = 0.1 })
	circle(mouth, 0.5, 0.5, 0.92, rim, { z = 2, grad = { color = shade(WHITE, lerp(rim, INK, 0.3)), rot = 90 } })
	circle(mouth, 0.5, 0.5, 0.7, dark and rgb(15, 5, 25) or rgb(30, 30, 45), { z = 3 })
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + 0.26
		circle(mouth, 0.5 + math.cos(a) * 0.405, 0.5 + math.sin(a) * 0.405, 0.07, STEEL_DARK, { z = 4 })
	end
	local fan = sub(mouth, 0.5, 0.5, 1, 1, 5, "Fan")
	for i = 1, 5 do
		local a = i / 5 * 360
		local r = math.rad(a)
		box(fan, 0.5 + math.cos(r) * 0.16, 0.5 + math.sin(r) * 0.16, 0.3, 0.1, dark and rgb(200, 170, 255) or rgb(215, 220, 235), { z = 1, rot = a + 20, corner = UDim.new(0.5, 0) })
	end
	circle(mouth, 0.5, 0.5, 0.16, STEEL_DARK, { z = 6 })
	circle(mouth, 0.47, 0.47, 0.06, WHITE, { z = 7, t = 0.4 })
	h.suction = { vortex = vortex, ring = fan, motes = motes, mouth = mouth }
end

local function animSuction(s, t, st)
	local pull = st.power == "Vacuum" and st.powerAge < 2.2
	if st.power == "Chomp" and st.powerAge < 1 then
		local k = math.abs(math.sin(st.powerAge * math.pi * 3))
		s.mouth.Size = UDim2.fromScale(0.5 * (1 + 0.4 * k), 0.5 * (1 + 0.4 * k))
	else
		s.mouth.Size = UDim2.fromScale(0.5, 0.5)
	end
	local speed = pull and 6 or 1
	s.ring.Rotation = (t * 240 * speed) % 360
	s.vortex.Rotation = (-t * 90 * speed) % 360
	local size = pull and 1.3 or 0.55
	s.vortex.Size = UDim2.fromScale(size, size)
	s.vortex.Position = UDim2.fromScale(0.5, pull and -0.42 or -0.14)
	local reach = pull and 0.95 or 0.42
	for i, m in s.motes do
		local p = (t * 0.8 * (pull and 2.5 or 1) + i / 4) % 1
		local e = p * p
		m.Position = UDim2.fromScale(0.5 + math.sin(i * 1.7 + t) * 0.25 * (1 - e), -reach + (reach + 0.02) * e)
		m.BackgroundTransparency = 0.15 + 0.85 * math.max(0, 1 - p * 4) * 0.6
	end
end

function BUILD.Drill(g, h)
	local segs = {}
	box(g, 0.5, 0.09, 0.44, 0.08, STEEL_DARK, { z = 2, corner = UDim.new(0.4, 0) })
	for i = 1, 6 do
		local w = 0.38 * (1 - (i - 1) / 6.5)
		table.insert(segs, box(g, 0.5, 0.04 - (i - 1) * 0.072, w, 0.082, STEEL, { z = 3, corner = UDim.new(0.35, 0), grad = { color = shade(rgb(150, 150, 165), WHITE), rot = 0 } }))
	end
	local tip = tri(g, 0.5, 0.04 - 6 * 0.072 + 0.035, 0.1, 0, STEEL, { z = 3 })
	local sparks = {}
	for i = 1, 4 do
		local s = circle(g, 0.5, -0.4, 0.04, rgb(255, 230, 120), { z = 4 })
		s.Visible = false
		table.insert(sparks, s)
	end
	h.drill = { segs = segs, tip = tip, sparks = sparks, phase = -1 }
end

local function animDrill(d, t, st)
	local hot = (st.power == "Pierce" and st.powerAge < 3) or (st.turbo and st.dash)
	local rate = hot and 30 or (st.fight and 18 or 7)
	local phase = math.floor(t * rate) % 2
	if phase ~= d.phase or hot ~= d.hot then
		d.phase, d.hot = phase, hot
		local a = hot and rgb(255, 150, 40) or STEEL
		local b = hot and rgb(255, 230, 120) or STEEL_DARK
		for i, s in d.segs do
			s.BackgroundColor3 = ((i + phase) % 2 == 0) and a or b
		end
		d.tip.BackgroundColor3 = a
	end
	for i, s in d.sparks do
		s.Visible = hot
		if hot then
			local a = t * 23 + i * 1.9
			s.Position = UDim2.fromScale(0.5 + math.sin(a) * 0.14, -0.42 + math.abs(math.cos(a * 1.3)) * 0.12)
		end
	end
end

-- Back --------------------------------------------------------------------------------------------

function BUILD.Flagella(g, h, color)
	local tails = {}
	local c = lerp(color, INK, 0.3)
	for _, side in { -1, 1 } do
		local segs = {}
		for i = 1, 10 do
			local d = 0.1 - i * 0.0065
			table.insert(segs, circle(g, 0.5 + side * 0.1, 0.95 + i * 0.05, d, i == 10 and lerp(color, WHITE, 0.3) or c, { z = 1 }))
		end
		table.insert(tails, { side = side, segs = segs })
	end
	h.flagella = tails
end

local function animFlagella(tails, t, st)
	local freq = st.dash and 24 or (st.fight and 15 or 9)
	for _, tail in tails do
		for i, s in tail.segs do
			local x = 0.5 + tail.side * (0.1 + i * 0.01) + math.sin(t * freq - i * 0.65 + tail.side) * 0.1 * (i / 10)
			s.Position = UDim2.fromScale(x, 0.95 + i * 0.05)
		end
	end
end

function BUILD.Jet(g, h)
	local jets = {}
	for _, side in { -1, 1 } do
		local x = 0.5 + side * 0.17
		local flame = sub(g, x, 0.99, 0.18, 0.24, 1, "Flame")
		flame.AnchorPoint = Vector2.new(0.5, 0)
		local outer = box(flame, 0.5, 0.5, 1, 1, rgb(255, 120, 30), { z = 1, grad = { color = shade(rgb(255, 230, 90), rgb(255, 70, 20)), trans = fade(0, 1), rot = 90 } })
		local inner = box(flame, 0.5, 0.32, 0.5, 0.64, rgb(255, 255, 210), { z = 2, grad = { trans = fade(0, 1), rot = 90 } })
		box(g, x, 0.95, 0.22, 0.16, STEEL_DARK, { z = 3, corner = UDim.new(0.3, 0), grad = { color = shade(WHITE, rgb(160, 160, 175)), rot = 0 } })
		box(g, x, 1.0, 0.15, 0.06, INK, { z = 4, corner = UDim.new(0.3, 0) })
		table.insert(jets, { side = side, flame = flame, outer = outer, inner = inner })
	end
	h.jet = jets
end

local function animJet(jets, t, st)
	for _, j in jets do
		local flicker = 0.8 + 0.4 * math.abs(math.sin(t * 37 + j.side * 2.1)) * math.abs(math.cos(t * 23))
		local len = (st.dash and 0.6 or 0.22) * flicker
		j.flame.Size = UDim2.fromScale(st.dash and 0.22 or 0.18, len)
		if st.dash ~= j.dash then
			j.dash = st.dash
			j.inner.BackgroundColor3 = st.dash and rgb(170, 220, 255) or rgb(255, 255, 210)
		end
	end
end

function BUILD.Slime(g, h, color, o)
	local goo = o.plague and rgb(170, 90, 230) or rgb(120, 230, 90)
	local light = lerp(goo, WHITE, 0.45)
	for _, b in { { 0.34, 0.94, 0.17 }, { 0.53, 0.99, 0.22 }, { 0.69, 0.93, 0.14 } } do
		circle(g, b[1], b[2], b[3], goo, { z = 1, t = 0.12, grad = { color = shade(light, goo), rot = 90 } })
		circle(g, b[1] - b[3] * 0.2, b[2] - b[3] * 0.2, b[3] * 0.25, WHITE, { z = 2, t = 0.4 })
	end
	local drops = {}
	for i = 1, 3 do
		table.insert(drops, circle(g, 0.4 + i * 0.07, 1.05, 0.07, goo, { z = 1, t = 0.2 }))
	end
	h.slime = drops
	h.slimeColor = goo
end

local function animSlime(drops, t)
	for i, d in drops do
		local p = (t * 0.7 + i / 3) % 1
		d.Position = UDim2.fromScale(0.34 + i * 0.08, 1.02 + p * 0.4)
		d.Size = UDim2.fromScale(0.1 * (1 - p * 0.5), 0.12 * (1 - p * 0.4))
		d.BackgroundTransparency = 0.15 + 0.85 * p
	end
end

-- Sides -------------------------------------------------------------------------------------------

function BUILD.Spikes(g, h, color, o)
	local ring = sub(g, 0.5, 0.5, 1, 1, 1, "Spikes")
	-- the Spikes mutation is steel; a Star core grows spikes in the body colour
	local dark = o.starOnly and lerp(color, INK, 0.5) or rgb(120, 125, 145)
	color = o.starOnly and color or rgb(200, 205, 220)
	local tips = {}
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local dir = math.deg(a) + 90
		tri(ring, 0.5 + math.cos(a) * 0.45, 0.5 + math.sin(a) * 0.45, 0.27, dir, INK, { z = 1, t = 0.15 })
		tri(ring, 0.5 + math.cos(a) * 0.46, 0.5 + math.sin(a) * 0.46, 0.23, dir, dark, { z = 2 })
		table.insert(tips, tri(ring, 0.5 + math.cos(a) * 0.52, 0.5 + math.sin(a) * 0.52, 0.11, dir, lerp(color, WHITE, 0.5), { z = 3 }))
	end
	h.spikes = { ring = ring, tips = tips, light = lerp(color, WHITE, 0.5) }
end

local function animSpikes(s, t, st, dt)
	local spin = (st.buzzsaw and st.dash) and 1100 or (st.buzzsaw and 90 or 18)
	s.angle = ((s.angle or 0) + spin * dt) % 360
	s.ring.Rotation = s.angle
	local hot = st.fight or (st.buzzsaw and st.dash)
	if hot ~= s.hot then
		s.hot = hot
		for _, tip in s.tips do
			tip.BackgroundColor3 = hot and rgb(255, 60, 60) or s.light
		end
	end
end

-- four glass canisters of glowing poison with steel caps, leaking bubbles
function BUILD.Toxin(g, h)
	local sacs = {}
	local green, deep = rgb(150, 255, 80), rgb(60, 170, 40)
	for k = 1, 4 do
		local a = math.rad(45 + 90 * k)
		local x, y = 0.5 + math.cos(a) * 0.43, 0.5 + math.sin(a) * 0.43
		local sac = sub(g, x, y, 0.24, 0.24, 2, "Canister")
		sac.Rotation = math.deg(a) + 90 -- standing out from the body
		box(sac, 0.5, 0.5, 0.62, 1.02, INK, { z = 1, t = 0.15, corner = UDim.new(0.3, 0) })
		box(sac, 0.5, 0.52, 0.52, 0.76, green, { z = 2, corner = UDim.new(0.25, 0), grad = { color = shade(rgb(220, 255, 170), deep), rot = 0 } })
		box(sac, 0.36, 0.5, 0.1, 0.6, WHITE, { z = 3, t = 0.45 })
		box(sac, 0.5, 0.1, 0.6, 0.16, STEEL, { z = 4, corner = UDim.new(0.3, 0), grad = { color = shade(WHITE, STEEL_DARK), rot = 90 } })
		box(sac, 0.5, 0.92, 0.6, 0.14, STEEL_DARK, { z = 4, corner = UDim.new(0.3, 0) })
		local bubble = circle(g, x, y, 0.06, green, { z = 1, t = 0.3 })
		table.insert(sacs, { a = a, k = k, sac = sac, bubble = bubble })
	end
	h.toxin = sacs
end

local function animToxin(sacs, t, st)
	local fast = st.fight and 2.5 or 1
	for _, s in sacs do
		local pulse = 0.24 * (1 + (st.fight and 0.25 or 0.1) * math.sin(t * 4 * fast + s.k))
		s.sac.Size = UDim2.fromScale(pulse, pulse)
		local p = (t * 0.6 * fast + s.k / 4) % 1
		local r = 0.5 + p * 0.38
		s.bubble.Position = UDim2.fromScale(0.5 + math.cos(s.a) * r, 0.5 + math.sin(s.a) * r)
		s.bubble.BackgroundTransparency = 0.2 + 0.8 * p
	end
end

function BUILD.Shell(g, h)
	local plates = {}
	for i = 1, 8 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local x, y = 0.5 + math.cos(a) * 0.455, 0.5 + math.sin(a) * 0.455
		local rot = math.deg(a) + 90
		box(g, x, y, 0.37, 0.14, INK, { z = 1, t = 0.2, rot = rot, corner = UDim.new(0.4, 0) })
		table.insert(plates, box(g, x, y, 0.34, 0.11, STEEL, { z = 2, rot = rot, corner = UDim.new(0.4, 0), grad = { color = shade(WHITE, rgb(150, 150, 170)), rot = rot + 90 } }))
		local tx, ty = math.cos(a + math.pi / 2), math.sin(a + math.pi / 2)
		for _, s in { -1, 1 } do
			circle(g, x + tx * 0.11 * s, y + ty * 0.11 * s, 0.035, STEEL_DARK, { z = 3 })
		end
	end
	h.shell = { plates = plates }
end

local function animShell(shell, t, st)
	local flash = st.fight and math.abs(math.sin(t * 10)) * 0.6 or 0
	if flash > 0 or shell.flash then
		shell.flash = flash > 0
		local c = lerp(STEEL, WHITE, flash)
		for _, p in shell.plates do
			p.BackgroundColor3 = c
		end
	end
end

-- Special -----------------------------------------------------------------------------------------

function BUILD.Camo(_, h, color, o)
	-- on the body itself (does not turn with the swim direction)
	local leaf, deep = rgb(110, 140, 60), rgb(60, 90, 40)
	for _, b in { { 0.3, 0.3, 0.2, 0.13, 20 }, { 0.68, 0.24, 0.16, 0.1, -30 }, { 0.22, 0.62, 0.15, 0.11, 60 }, { 0.75, 0.66, 0.22, 0.12, 10 }, { 0.5, 0.83, 0.18, 0.09, -15 }, { 0.5, 0.5, 0.14, 0.08, 45 } } do
		box(o.fixed, b[1], b[2], b[3], b[4], (b[5] > 0) and leaf or deep, { z = 1, t = 0.5, rot = b[5] })
	end
end

function BUILD.Magnet(g, h)
	local a = math.rad(130) -- back left shoulder
	local x, y = 0.5 + math.cos(a) * 0.5, 0.5 + math.sin(a) * 0.5
	local mag = sub(g, x, y, 0.46, 0.46, 3, "Magnet")
	mag.Rotation = math.deg(a) + 90 -- opening points away from the body
	local red, blue = rgb(230, 60, 60), rgb(70, 110, 240)
	arc(mag, 0.5, 0.5, 0.3, 0.3, 0, 90, 0.18, red, { n = 3, z = 2 })
	arc(mag, 0.5, 0.5, 0.3, 0.3, 90, 180, 0.18, blue, { n = 3, z = 2 })
	box(mag, 0.8, 0.32, 0.18, 0.36, red, { z = 2, corner = false })
	box(mag, 0.2, 0.32, 0.18, 0.36, blue, { z = 2, corner = false })
	box(mag, 0.8, 0.12, 0.18, 0.1, STEEL, { z = 3, corner = false })
	box(mag, 0.2, 0.12, 0.18, 0.1, STEEL, { z = 3, corner = false })
	local ripples = {}
	for i = 1, 3 do
		local r = sub(mag, 0.5, 0.0, 0.6, 0.6, 1, "Ripple")
		arc(r, 0.5, 0.5, 0.45, 0.45, 200, 340, 0.06, rgb(170, 220, 255), { n = 4, t = 0.3 })
		table.insert(ripples, r)
	end
	-- the gravity well: a ring of dots spiralling in around the whole germ
	local well = sub(g, 0.5, 0.5, 2, 2, 0, "Well")
	for i = 1, 14 do
		local w = i / 14 * math.pi * 2
		circle(well, 0.5 + math.cos(w) * 0.45, 0.5 + math.sin(w) * 0.45, 0.035, rgb(190, 140, 255), { t = 0.2 })
	end
	well.Visible = false
	h.magnet = { ripples = ripples, well = well }
end

local function animMagnet(m, t, st)
	for i, r in m.ripples do
		local p = (t * 0.7 + i / 3) % 1
		r.Size = UDim2.fromScale(0.5 + p * 0.9, 0.5 + p * 0.9)
		r.Position = UDim2.fromScale(0.5, 0.05 - p * 0.35)
		for _, b in r:GetChildren() do
			b.BackgroundTransparency = 0.25 + 0.75 * p
		end
	end
	local on = (st.power == "GravityWell" and st.powerAge < 2.2) or (st.power == "Blast" and st.storm and st.powerAge < 2.2)
	m.well.Visible = on
	if on then
		local p = (st.powerAge * 2) % 1
		local s = 2 - p * 0.9
		m.well.Size = UDim2.fromScale(s, s)
		m.well.Rotation = (st.powerAge * 260) % 360
	end
end

function BUILD.Sneezer(_, h, color, o)
	local nose = sub(o.top, 0.5, 0.53, 0.24, 0.18, 1, "Nose")
	local c = lerp(color, rgb(255, 120, 120), 0.55)
	box(nose, 0.5, 0.5, 1.12, 1.15, INK, { z = 1, t = 0.2 })
	box(nose, 0.5, 0.5, 1, 1, c, { z = 2, grad = { color = shade(lerp(c, WHITE, 0.35), lerp(c, INK, 0.15)), rot = 90 } })
	circle(nose, 0.32, 0.66, 0.2, INK, { z = 3, t = 0.15 })
	circle(nose, 0.68, 0.66, 0.2, INK, { z = 3, t = 0.15 })
	circle(nose, 0.36, 0.28, 0.25, WHITE, { z = 3, t = 0.45 })
	local rings = {}
	for i = 1, 2 do
		local r = sub(o.fixed, 0.5, 0.5, 1, 1, 0, "Shock")
		arc(r, 0.5, 0.5, 0.5, 0.5, 0, 360, 0.035, rgb(230, 255, 200), { n = 16, t = 0.2 })
		r.Visible = false
		table.insert(rings, r)
	end
	local spray = {}
	for i = 1, 8 do
		local d = circle(o.fixed, 0.5, 0.5, 0.05, rgb(200, 255, 170), { z = 1, t = 0.2 })
		d.Visible = false
		table.insert(spray, d)
	end
	h.sneezer = { nose = nose, rings = rings, spray = spray }
end

local function animSneezer(s, t, st)
	local blast = st.power == "Blast" and st.powerAge < 0.9
	local twitch = math.max(0, math.sin(t * 2)) ^ 24
	local k = 1 + 0.18 * twitch
	if blast then
		k = 1 + 0.5 * math.max(0, 1 - st.powerAge * 4)
	end
	s.nose.Size = UDim2.fromScale(0.24 * k, 0.18 * k)
	for i, r in s.rings do
		local p = (st.powerAge or 9) / 0.6 - (i - 1) * 0.25
		local show = blast and p > 0 and p < 1
		r.Visible = show
		if show then
			local size = 1 + p
			r.Size = UDim2.fromScale(size, size)
			for _, b in r:GetChildren() do
				b.BackgroundTransparency = 0.1 + 0.9 * p
			end
		end
	end
	for i, d in s.spray do
		d.Visible = blast
		if blast then
			local a = i / 8 * math.pi * 2 + 0.3
			local r = 0.5 + st.powerAge * 0.6
			d.Position = UDim2.fromScale(0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r)
			d.BackgroundTransparency = math.min(1, 0.2 + st.powerAge)
		end
	end
end

-- Building and animating ----------------------------------------------------------------------------

local ORDER = { "Camo", "Slime", "Jet", "Flagella", "Shell", "Spikes", "Toxin", "Drill", "Suction", "Jaws", "Magnet", "Sneezer" }

-- muts = { [slot] = id or "#Fusion" }. Returns nil when there is nothing to draw.
function Gear.build(root, muts, color, core)
	local want = {}
	for _, id in ORDER do
		if Gear.has(muts, id) then
			want[id] = true
		end
	end
	local starOnly = false
	if core == "Star" and not want.Spikes then
		want.Spikes, starOnly = true, true
	end
	local o = {
		venom = Gear.fused(muts, "Venom"),
		blackHole = Gear.fused(muts, "BlackHole"),
		plague = Gear.fused(muts, "PlagueTrail"),
		starOnly = starOnly,
	}
	if o.blackHole then
		want.Jaws = nil -- one big dark sucking mouth instead of two mouths
	end
	if next(want) == nil then
		return nil
	end
	local h = { want = want, state = {} }
	h.frame = sub(root, 0.5, 0.5, 1, 1, 2, "Gear")
	o.fixed = sub(root, 0.5, 0.5, 1, 1, 2, "GearFixed")
	o.top = sub(root, 0.5, 0.5, 1, 1, 5, "GearTop")
	for _, id in ORDER do
		if want[id] then
			BUILD[id](h.frame, h, color or rgb(120, 220, 120), o)
		end
	end
	h.buzzsaw = Gear.fused(muts, "Buzzsaw")
	h.turbo = Gear.fused(muts, "Driller")
	h.storm = Gear.fused(muts, "Storm")
	return h
end

-- st = { dx, dz (swim direction on screen), fight, dash, power (ability name or nil), powerAge }
function Gear.animate(h, dt, t, st)
	local rot = math.deg(math.atan2(st.dz or 0, st.dx or 1)) + 90
	if math.abs(rot - (h.rot or -999)) > 0.5 then
		h.rot = rot
		h.frame.Rotation = rot
	end
	st.buzzsaw, st.turbo, st.storm = h.buzzsaw, h.turbo, h.storm
	st.powerAge = st.powerAge or 99
	if h.jaws then
		animJaws(h.jaws, t, st)
	end
	if h.suction then
		animSuction(h.suction, t, st)
	end
	if h.drill then
		animDrill(h.drill, t, st)
	end
	if h.flagella then
		animFlagella(h.flagella, t, st)
	end
	if h.jet then
		animJet(h.jet, t, st)
	end
	if h.slime then
		animSlime(h.slime, t)
	end
	if h.spikes then
		animSpikes(h.spikes, t, st, dt)
	end
	if h.toxin then
		animToxin(h.toxin, t, st)
	end
	if h.shell then
		animShell(h.shell, t, st)
	end
	if h.magnet then
		animMagnet(h.magnet, t, st)
	end
	if h.sneezer then
		animSneezer(h.sneezer, t, st)
	end
end

return Gear
