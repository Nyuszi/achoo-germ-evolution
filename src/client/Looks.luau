-- Looks: a germ's pattern, eyes, mouth, hat and shine, drawn as flat 2D art.
-- Everything is built on a square Frame that stands for the body's disc (0..1 both ways,
-- centre 0.5, radius 0.5). The game puts it on a BillboardGui just above the 3D body (the camera
-- looks straight down), the Germ Editor uses it for its little previews, and
-- tools/render-looks.js draws the skin pictures from this same code.
--
-- Only Frames, UICorner, UIGradient, Rotation and ZIndex are used: cheap, and the art scales
-- with the germ. Nothing relies on clipping (no CanvasGroup): every shape is placed inside the
-- circle. Triangles are squares cut along the diagonal with a hard UIGradient step.
local Looks = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local INK = rgb(32, 22, 44)
local WHITE = rgb(255, 255, 255)
local MOUTH = rgb(120, 28, 52)
local PINK = rgb(255, 120, 150)
local GOLD = rgb(255, 205, 60)

-- Shapes ----------------------------------------------------------------------------------------

-- A Frame centred on (x, y) with size (w, h), in the parent's 0..1 space.
-- o = { t = transparency, rot = degrees, z = ZIndex, corner = UDim or false, grad = {...} }
local function box(parent, x, y, w, h, color, o)
	o = o or {}
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = o.t or 0
	f.BorderSizePixel = 0
	f.Rotation = o.rot or 0
	f.ZIndex = o.z or 1
	if o.corner ~= false then
		local c = Instance.new("UICorner")
		c.CornerRadius = o.corner or UDim.new(0.5, 0)
		c.Parent = f
	end
	if o.grad then
		local g = Instance.new("UIGradient")
		if o.grad.color then
			g.Color = o.grad.color
		end
		if o.grad.trans then
			g.Transparency = o.grad.trans
		end
		g.Rotation = o.grad.rot or 0
		g.Parent = f
	end
	f.Parent = parent
	return f
end

local function circle(parent, x, y, d, color, o)
	return box(parent, x, y, d, d, color, o)
end

-- A see-through Frame covering the whole parent, to group parts (same 0..1 space inside)
local function group(parent, name, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

-- Gradient helpers. A hard step in transparency cuts a shape in two.
local function keepBefore(t)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(t, 0),
		NumberSequenceKeypoint.new(math.min(1, t + 0.002), 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end
local function keepAfter(t)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(math.max(0, t - 0.002), 1),
		NumberSequenceKeypoint.new(t, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
end
local function shade(top, bottom)
	return ColorSequence.new(top, bottom)
end

-- A right-angled triangle: its long side is centred on (x, y) and is `base` wide, and it points
-- `dir` degrees clockwise from straight up. Its height is base / 2.
local function tri(parent, x, y, base, dir, color, o)
	o = o or {}
	local s = base / math.sqrt(2)
	return box(parent, x, y, s, s, color, { z = o.z, t = o.t, rot = 45 + (dir or 0), corner = UDim.new(0, 0), grad = { trans = keepBefore(0.5), rot = 45 } })
end

-- A rounded bar from (x1, y1) to (x2, y2)
local function bar(parent, x1, y1, x2, y2, th, color, o)
	o = o or {}
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	return box(parent, (x1 + x2) / 2, (y1 + y2) / 2, len + th, th, color, { z = o.z, t = o.t, rot = math.deg(math.atan2(dy, dx)) })
end

-- A curved line along an ellipse, from angle a0 to a1 (degrees, 0 = right, 90 = down)
local function arc(parent, cx, cy, rx, ry, a0, a1, th, color, o)
	o = o or {}
	local n = o.n or 6
	local spin = math.rad(o.spin or 0)
	local function at(a)
		local px, py = math.cos(math.rad(a)) * rx, math.sin(math.rad(a)) * ry
		return cx + px * math.cos(spin) - py * math.sin(spin), cy + px * math.sin(spin) + py * math.cos(spin)
	end
	local px, py = at(a0)
	for i = 1, n do
		local nx, ny = at(a0 + (a1 - a0) * i / n)
		bar(parent, px, py, nx, ny, th, color, o)
		px, py = nx, ny
	end
end

local function heart(parent, x, y, s, color, o)
	o = o or {}
	circle(parent, x - s * 0.22, y - s * 0.1, s * 0.56, color, o)
	circle(parent, x + s * 0.22, y - s * 0.1, s * 0.56, color, o)
	tri(parent, x, y - s * 0.04, s * 0.92, 180, color, o)
end

local function teardrop(parent, x, y, d, color, o)
	circle(parent, x, y, d, color, o)
	tri(parent, x, y, d * 0.98, 0, color, o)
end

local function lerp(a, b, k)
	return a:Lerp(b, k)
end

-- Patterns (in the second colour) --------------------------------------------------------------------

local PATTERNS = {}

function PATTERNS.Spots(g, c2)
	local spots = {
		{ 0.27, 0.27, 0.18 }, { 0.73, 0.25, 0.14 }, { 0.15, 0.55, 0.12 }, { 0.83, 0.55, 0.17 }, { 0.5, 0.84, 0.16 },
		{ 0.27, 0.78, 0.11 }, { 0.73, 0.8, 0.1 }, { 0.5, 0.12, 0.09 }, { 0.62, 0.66, 0.07 }, { 0.37, 0.66, 0.06 },
	}
	for _, s in spots do
		circle(g, s[1], s[2], s[3], c2)
		circle(g, s[1] - s[3] * 0.18, s[2] - s[3] * 0.18, s[3] * 0.4, WHITE, { t = 0.65 })
	end
end

-- tiger stripes coming in from the rim
function PATTERNS.Stripes(g, c2)
	for i = 0, 11 do
		local a = math.rad(i * 30 + 10)
		local long = (i % 2 == 0) and 0.2 or 0.13
		local ox, oy = math.cos(a), math.sin(a)
		bar(g, 0.5 + ox * 0.44, 0.5 + oy * 0.44, 0.5 + ox * (0.44 - long * 0.55), 0.5 + oy * (0.44 - long * 0.55), 0.06, c2)
		bar(g, 0.5 + ox * (0.44 - long * 0.5), 0.5 + oy * (0.44 - long * 0.5), 0.5 + ox * (0.44 - long), 0.5 + oy * (0.44 - long), 0.033, c2)
	end
end

-- a candy swirl that thickens as it winds out
function PATTERNS.Swirl(g, c2)
	local px, py
	for i = 0, 22 do
		local t = i / 22
		local a = math.rad(t * 600)
		local rad = 0.03 + t * 0.37
		local x, y = 0.5 + math.cos(a) * rad, 0.52 + math.sin(a) * rad
		if px then
			bar(g, px, py, x, y, 0.035 + t * 0.075, c2)
		end
		px, py = x, y
	end
end

function PATTERNS.Camo(g, c2)
	local tones = { lerp(c2, INK, 0.25), lerp(c2, INK, 0.55), c2 }
	local blobs = {
		{ 0.28, 0.3, 1 }, { 0.62, 0.22, 2 }, { 0.76, 0.5, 3 }, { 0.45, 0.48, 2 }, { 0.22, 0.62, 3 }, { 0.58, 0.74, 1 }, { 0.36, 0.8, 2 }, { 0.8, 0.72, 2 },
	}
	for i, b in blobs do
		local c = tones[b[3]]
		circle(g, b[1], b[2], 0.13, c)
		circle(g, b[1] + 0.06, b[2] + 0.03, 0.09, c)
		circle(g, b[1] - 0.05, b[2] + 0.05, 0.08, c)
		if i % 2 == 0 then
			circle(g, b[1] + 0.02, b[2] - 0.06, 0.07, c)
		end
	end
end

function PATTERNS.Checkers(g, c2)
	local cell = 0.12
	for i = -4, 3 do
		for j = -4, 3 do
			if (i + j) % 2 == 0 then
				local x, y = 0.5 + (i + 0.5) * cell, 0.5 + (j + 0.5) * cell
				local far = math.sqrt((x - 0.5) ^ 2 + (y - 0.5) ^ 2) + cell * 0.7
				if far < 0.48 then
					box(g, x, y, cell, cell, c2, { corner = UDim.new(0.2, 0) })
				end
			end
		end
	end
end

-- flames rising from the bottom
function PATTERNS.Flames(g)
	local outer, mid, core = rgb(255, 90, 30), rgb(255, 160, 40), rgb(255, 235, 110)
	for _, f in { { 0.14, 0.6, 0.15 }, { 0.86, 0.6, 0.15 }, { 0.27, 0.77, 0.21 }, { 0.73, 0.77, 0.21 }, { 0.5, 0.83, 0.25 } } do
		teardrop(g, f[1], f[2], f[3], outer)
		teardrop(g, f[1], f[2] + f[3] * 0.12, f[3] * 0.68, mid)
		teardrop(g, f[1], f[2] + f[3] * 0.22, f[3] * 0.38, core)
	end
end

function PATTERNS.Hearts(g, c2)
	for _, h in { { 0.24, 0.26, 0.2 }, { 0.77, 0.27, 0.17 }, { 0.14, 0.56, 0.15 }, { 0.86, 0.56, 0.19 }, { 0.5, 0.85, 0.18 }, { 0.29, 0.79, 0.13 }, { 0.71, 0.8, 0.13 }, { 0.5, 0.12, 0.12 } } do
		heart(g, h[1], h[2], h[3], c2)
	end
end

-- leopard rosettes: a broken dark ring around a lighter centre
function PATTERNS.Leopard(g, c2)
	local dark = lerp(c2, INK, 0.6)
	local spots = {
		{ 0.27, 0.26, 0.17 }, { 0.72, 0.23, 0.15 }, { 0.15, 0.56, 0.15 }, { 0.85, 0.55, 0.17 }, { 0.5, 0.84, 0.17 },
		{ 0.28, 0.8, 0.13 }, { 0.72, 0.81, 0.13 }, { 0.5, 0.11, 0.1 },
	}
	for _, r in spots do
		circle(g, r[1], r[2], r[3] * 0.8, c2)
		for k = 0, 4 do
			local a = math.rad(k * 72 + 20 + r[1] * 90)
			box(g, r[1] + math.cos(a) * r[3] * 0.48, r[2] + math.sin(a) * r[3] * 0.48, r[3] * 0.42, r[3] * 0.26, dark, { rot = math.deg(a) + 90 })
		end
	end
end

-- Eyes ------------------------------------------------------------------------------------------------

-- One anime eye. The iris, pupil and shines go in `look` (moves with the swim direction).
local function eye(face, look, x, y, w, h, iris, o)
	o = o or {}
	local cut = o.cutTop -- y where a heavy lid starts (sleepy)
	local function cutGrad(cy, hh, color)
		if not cut then
			return color and { color = color, rot = 90 } or nil
		end
		local t = math.clamp((cut - (cy - hh / 2)) / hh, 0.01, 0.99)
		return { color = color, trans = keepAfter(t), rot = 90 }
	end
	box(face, x, y, w * 1.14, h * 1.1, INK, { z = 1, grad = cutGrad(y, h * 1.1), rot = o.tilt })
	box(face, x, y, w, h, WHITE, { z = 2, grad = cutGrad(y, h, shade(rgb(225, 230, 248), WHITE)), rot = o.tilt })
	local ih = o.irisH or 0.8
	box(look, x, y + h * 0.04, w * (o.irisW or 0.74), h * ih, iris, { z = 3, grad = cutGrad(y + h * 0.04, h * ih, shade(lerp(iris, INK, 0.5), lerp(iris, WHITE, 0.3))) })
	if o.slit then
		box(look, x, y + h * 0.04, w * 0.14, h * 0.62, INK, { z = 4, grad = cutGrad(y + h * 0.04, h * 0.62) })
	else
		box(look, x, y + h * 0.06, w * 0.34, h * 0.4, INK, { z = 4, grad = cutGrad(y + h * 0.06, h * 0.4) })
	end
	if not cut then
		circle(look, x - w * 0.15, y - h * 0.16, w * 0.3, WHITE, { z = 5 })
		circle(look, x + w * 0.14, y + h * 0.18, w * 0.13, WHITE, { z = 5, t = 0.1 })
	end
	if o.lash ~= false and not cut then
		-- the thick upper lid line of anime eyes, with a little flick at the outer corner
		arc(face, x, y, w * 0.56, h * 0.54, 198, 342, h * 0.12, INK, { z = 6, n = 5, spin = o.tilt })
		local side = o.side or 1
		local ex, ey = x + side * w * 0.55, y - h * 0.15
		bar(face, ex, ey, ex + side * w * 0.16, ey - h * 0.14, h * 0.09, INK, { z = 6 })
	end
end

local function closedEye(g, x, y, w, h)
	arc(g, x, y - h * 0.05, w * 0.5, h * 0.22, 15, 165, h * 0.12, INK, { z = 6, n = 5 })
end

local function blush(g, z)
	box(g, 0.2, 0.61, 0.14, 0.075, rgb(255, 130, 165), { t = 0.35, z = z })
	box(g, 0.8, 0.61, 0.14, 0.075, rgb(255, 130, 165), { t = 0.35, z = z })
end

-- Each returns how far the iris may move (in disc units); 0 = it doesn't follow
local EYES = {}

function EYES.Cute(face, look, closed)
	blush(face, 0)
	for _, s in { -1, 1 } do
		eye(face, look, 0.5 + s * 0.17, 0.44, 0.25, 0.31, rgb(80, 120, 235), { side = s })
		closedEye(closed, 0.5 + s * 0.17, 0.46, 0.25, 0.31)
	end
	return 0.035
end

function EYES.Angry(face, look, closed)
	for _, s in { -1, 1 } do
		eye(face, look, 0.5 + s * 0.17, 0.47, 0.25, 0.24, rgb(225, 50, 60), { side = s, irisH = 0.85 })
		closedEye(closed, 0.5 + s * 0.17, 0.48, 0.25, 0.24)
		-- brows slanting down to the middle
		bar(face, 0.5 + s * 0.31, 0.29, 0.5 + s * 0.08, 0.37, 0.06, INK, { z = 8 })
	end
	return 0.03
end

function EYES.Sleepy(face, look)
	for _, s in { -1, 1 } do
		local x, y, h = 0.5 + s * 0.17, 0.46, 0.27
		eye(face, look, x, y, 0.25, h, rgb(120, 110, 200), { side = s, cutTop = y - h * 0.02 })
		arc(face, x, y + 0.02, 0.15, 0.03, 180, 360, 0.04, INK, { z = 7, n = 4 })
	end
	local z = Instance.new("TextLabel")
	z.AnchorPoint = Vector2.new(0.5, 0.5)
	z.Position = UDim2.fromScale(0.8, 0.2)
	z.Size = UDim2.fromScale(0.16, 0.16)
	z.Rotation = -15
	z.BackgroundTransparency = 1
	z.Font = Enum.Font.FredokaOne
	z.TextScaled = true
	z.Text = "z"
	z.TextColor3 = WHITE
	z.TextTransparency = 0.15
	z.ZIndex = 9
	z.Parent = face
	return 0
end

function EYES.Cyclops(face, look, closed)
	eye(face, look, 0.5, 0.42, 0.4, 0.42, rgb(70, 205, 120), { side = 1 })
	closedEye(closed, 0.5, 0.44, 0.4, 0.42)
	return 0.05
end

function EYES.Googly(face, look, closed)
	for _, s in { -1, 1 } do
		local x = 0.5 + s * 0.17
		circle(face, x, 0.42, 0.33, INK, { z = 1 })
		circle(face, x, 0.42, 0.3, WHITE, { z = 2 })
		circle(look, x, 0.44, 0.15, INK, { z = 3 })
		circle(look, x - 0.03, 0.41, 0.045, WHITE, { z = 4 })
		closedEye(closed, x, 0.43, 0.3, 0.3)
	end
	return 0.075
end

function EYES.Three(face, look, closed)
	for _, e in { { 0.26, 0.48, -1 }, { 0.5, 0.35, 1 }, { 0.74, 0.48, 1 } } do
		eye(face, look, e[1], e[2], 0.2, 0.25, rgb(165, 90, 235), { side = e[3] })
		closedEye(closed, e[1], e[2] + 0.02, 0.2, 0.25)
	end
	return 0.028
end

function EYES.Cat(face, look, closed)
	for _, s in { -1, 1 } do
		local x = 0.5 + s * 0.17
		eye(face, look, x, 0.45, 0.28, 0.21, rgb(170, 220, 50), { side = s, tilt = -s * 10, irisW = 0.55, irisH = 0.95, slit = true })
		closedEye(closed, x, 0.46, 0.28, 0.21)
	end
	return 0.03
end

function EYES.Heart(face)
	blush(face, 0)
	for _, s in { -1, 1 } do
		local x = 0.5 + s * 0.17
		heart(face, x, 0.46, 0.25, INK, { z = 1 })
		heart(face, x, 0.46, 0.21, rgb(255, 70, 125), { z = 2 })
		circle(face, x - 0.05, 0.4, 0.05, WHITE, { z = 3 })
	end
	return 0
end

function EYES.Wink(face, look)
	blush(face, 0)
	eye(face, look, 0.33, 0.44, 0.25, 0.31, rgb(255, 140, 60), { side = -1 })
	-- the winking eye: a happy ^ shape
	arc(face, 0.67, 0.47, 0.11, 0.08, 200, 340, 0.045, INK, { z = 6, n = 4 })
	return 0.03
end

-- Mouths -------------------------------------------------------------------------------------------------

local MOUTHS = {}

local function halfMouth(g, x, y, w, h, z)
	-- an open "D" mouth: the bottom half of an ellipse
	box(g, x, y, w * 1.12, h * 1.14, INK, { z = z, grad = { trans = keepAfter(0.5), rot = 90 } })
	box(g, x, y, w, h, MOUTH, { z = z + 1, grad = { trans = keepAfter(0.5), rot = 90, color = shade(lerp(MOUTH, INK, 0.4), MOUTH) } })
end

function MOUTHS.Smile(g)
	arc(g, 0.5, 0.62, 0.085, 0.055, 20, 160, 0.035, INK, { z = 2 })
end

function MOUTHS.Fangs(g)
	halfMouth(g, 0.5, 0.63, 0.22, 0.17, 1)
	box(g, 0.5, 0.69, 0.09, 0.04, PINK, { z = 3 })
	tri(g, 0.455, 0.632, 0.05, 180, WHITE, { z = 4 })
	tri(g, 0.545, 0.632, 0.05, 180, WHITE, { z = 4 })
end

function MOUTHS.Tongue(g)
	box(g, 0.53, 0.69, 0.075, 0.095, PINK, { z = 1, grad = { color = shade(PINK, rgb(255, 160, 180)), rot = 90 } })
	bar(g, 0.53, 0.665, 0.53, 0.71, 0.012, rgb(220, 80, 110), { z = 2 })
	arc(g, 0.5, 0.62, 0.09, 0.05, 15, 165, 0.035, INK, { z = 3 })
end

function MOUTHS.Mustache(g)
	local brown = rgb(90, 55, 32)
	local grad = { color = shade(lerp(brown, WHITE, 0.25), brown), rot = 90 }
	box(g, 0.415, 0.635, 0.17, 0.07, brown, { rot = 14, grad = grad, z = 1 })
	box(g, 0.585, 0.635, 0.17, 0.07, brown, { rot = -14, grad = grad, z = 1 })
	circle(g, 0.33, 0.605, 0.05, brown, { z = 1 })
	circle(g, 0.67, 0.605, 0.05, brown, { z = 1 })
	circle(g, 0.5, 0.625, 0.055, lerp(brown, INK, 0.3), { z = 2 })
	arc(g, 0.5, 0.67, 0.05, 0.03, 20, 160, 0.025, INK, { z = 0 })
end

function MOUTHS.Braces(g)
	halfMouth(g, 0.5, 0.62, 0.28, 0.2, 1)
	box(g, 0.5, 0.64, 0.22, 0.036, WHITE, { z = 3, corner = UDim.new(0.3, 0) })
	bar(g, 0.4, 0.64, 0.6, 0.64, 0.009, rgb(150, 155, 170), { z = 4 })
	for _, x in { 0.42, 0.473, 0.527, 0.58 } do
		box(g, x, 0.64, 0.022, 0.022, rgb(175, 180, 195), { z = 5, corner = UDim.new(0.25, 0) })
	end
end

function MOUTHS.Kitty(g)
	tri(g, 0.5, 0.585, 0.04, 180, rgb(255, 130, 160), { z = 2 })
	arc(g, 0.46, 0.615, 0.04, 0.035, 0, 180, 0.025, INK, { z = 1, n = 5 })
	arc(g, 0.54, 0.615, 0.04, 0.035, 0, 180, 0.025, INK, { z = 1, n = 5 })
end

function MOUTHS.Surprised(g)
	box(g, 0.5, 0.66, 0.095, 0.12, INK, { z = 1 })
	box(g, 0.5, 0.66, 0.075, 0.1, MOUTH, { z = 2, grad = { color = shade(lerp(MOUTH, INK, 0.4), MOUTH), rot = 90 } })
	box(g, 0.5, 0.69, 0.045, 0.03, PINK, { z = 3 })
end

-- Hats (sit on the top edge of the disc and stick out above it) -------------------------------------

local HATS = {}

function HATS.Crown(g)
	local dark = rgb(230, 160, 30)
	for _, p in { { 0.34, 0.16 }, { 0.5, 0.2 }, { 0.66, 0.16 } } do
		tri(g, p[1], 0.06, p[2], 0, dark)
		circle(g, p[1], 0.06 - p[2] / 2 + 0.005, 0.045, GOLD)
	end
	box(g, 0.5, 0.08, 0.44, 0.1, GOLD, { corner = UDim.new(0.3, 0), grad = { color = shade(rgb(255, 240, 150), rgb(225, 150, 20)), rot = 90 } })
	for i, c in { rgb(230, 40, 70), rgb(60, 130, 255), rgb(40, 200, 110) } do
		circle(g, 0.38 + (i - 1) * 0.12, 0.08, 0.048, c)
		circle(g, 0.37 + (i - 1) * 0.12, 0.07, 0.016, WHITE, { t = 0.2 })
	end
end

-- a striped party cone with a pompom
function HATS.Party(g)
	local x = 0.58
	for i = 0, 6 do
		local y = 0.07 - i * 0.055
		local w = 0.28 * (1 - i / 7) + 0.025
		box(g, x, y, w, 0.064, (i % 2 == 0) and rgb(255, 90, 180) or rgb(255, 220, 70), { corner = UDim.new(0.3, 0) })
	end
	box(g, x, 0.1, 0.34, 0.055, rgb(80, 195, 255))
	circle(g, x, -0.31, 0.1, rgb(255, 250, 220))
	circle(g, x - 0.02, -0.325, 0.035, WHITE)
end

-- a beanie with a spinning propeller ("Spin" frame, turned by the renderer)
function HATS.Propeller(g)
	local cut = { trans = keepBefore(0.5), rot = 90 }
	box(g, 0.5, 0.12, 0.48, 0.46, rgb(70, 140, 240), { grad = cut })
	box(g, 0.5, 0.12, 0.22, 0.46, rgb(240, 70, 80), { grad = cut })
	box(g, 0.5, 0.12, 0.08, 0.46, rgb(255, 220, 70), { grad = cut })
	bar(g, 0.25, 0.12, 0.75, 0.12, 0.05, rgb(40, 90, 190))
	box(g, 0.5, -0.135, 0.025, 0.06, rgb(150, 150, 165), { corner = UDim.new(0.3, 0) })
	local spin = Instance.new("Frame")
	spin.Name = "Spin"
	spin.AnchorPoint = Vector2.new(0.5, 0.5)
	spin.Position = UDim2.fromScale(0.5, -0.17)
	spin.Size = UDim2.fromScale(0.34, 0.34)
	spin.BackgroundTransparency = 1
	spin.ZIndex = 2
	spin.Parent = g
	bar(spin, 0.5, 0.5, 0.06, 0.5, 0.2, rgb(240, 70, 80))
	bar(spin, 0.5, 0.5, 0.94, 0.5, 0.2, rgb(255, 220, 70))
	circle(spin, 0.5, 0.5, 0.2, rgb(70, 140, 240), { z = 2 })
end

function HATS.Halo(g)
	box(g, 0.5, -0.1, 0.6, 0.2, rgb(255, 235, 110), { t = 0.82 })
	box(g, 0.5, -0.1, 0.5, 0.13, rgb(255, 225, 80), { t = 0.5 })
	for i = 0, 15 do
		local a = math.rad(i * 22.5)
		local front = math.sin(a) > 0
		circle(g, 0.5 + math.cos(a) * 0.22, -0.1 + math.sin(a) * 0.055, front and 0.05 or 0.038, front and rgb(255, 225, 80) or rgb(240, 200, 70), { z = front and 3 or 1 })
	end
	circle(g, 0.5, -0.1, 0.03, WHITE, { t = 0.3, z = 2 })
end

function HATS.Horns(g)
	for _, s in { -1, 1 } do
		local x = 0.5 + s * 0.23
		box(g, x, 0.13, 0.14, 0.08, rgb(150, 20, 30), { z = 1 })
		tri(g, x, 0.12, 0.2, s * 24, rgb(220, 50, 50), { z = 2 })
		tri(g, x - s * 0.02, 0.1, 0.1, s * 24, rgb(255, 130, 120), { z = 3, t = 0.3 })
	end
end

function HATS.Laurel(g)
	local leaf, light = rgb(70, 170, 70), rgb(140, 220, 110)
	for _, s in { -1, 1 } do
		for k = 0, 6 do
			local a = math.rad(270 + s * (25 + k * 15))
			local x, y = 0.5 + math.cos(a) * 0.43, 0.42 + math.sin(a) * 0.43
			local tangent = math.deg(a) + 90
			box(g, x, y, 0.12, 0.05, leaf, { rot = tangent + s * 35, grad = { color = shade(light, leaf), rot = 90 } })
			if k % 2 == 1 then
				circle(g, x + math.cos(a) * 0.04, y + math.sin(a) * 0.04, 0.03, GOLD, { z = 2 })
			end
		end
	end
end

-- a big ribbon bow on one side: two puffy loops, two tails and a knot
function HATS.Bow(g)
	local x, y, c = 0.68, 0.1, rgb(255, 95, 160)
	local dark = lerp(c, INK, 0.25)
	bar(g, x - 0.02, y + 0.03, x - 0.07, y + 0.15, 0.06, dark, { z = 1 })
	bar(g, x + 0.02, y + 0.03, x + 0.08, y + 0.14, 0.06, dark, { z = 1 })
	for _, s in { -1, 1 } do
		box(g, x + s * 0.1, y, 0.17, 0.15, INK, { z = 2, rot = s * 12 })
		box(g, x + s * 0.1, y, 0.145, 0.125, c, { z = 3, rot = s * 12, grad = { color = shade(lerp(c, WHITE, 0.35), c), rot = 90 } })
		box(g, x + s * 0.06, y, 0.05, 0.06, dark, { z = 4, rot = s * 12, t = 0.2 })
	end
	circle(g, x, y, 0.085, INK, { z = 5 })
	circle(g, x, y, 0.065, lerp(c, WHITE, 0.15), { z = 6 })
	circle(g, x - 0.012, y - 0.014, 0.02, WHITE, { z = 7, t = 0.2 })
end

function HATS.CatEars(g, color)
	for _, s in { -1, 1 } do
		local a = math.rad(270 + s * 38)
		local x, y = 0.5 + math.cos(a) * 0.4, 0.5 + math.sin(a) * 0.4
		tri(g, x, y, 0.36, s * 38, lerp(color, INK, 0.45), { z = 1 })
		tri(g, x - math.cos(a) * 0.01, y - math.sin(a) * 0.01, 0.3, s * 38, lerp(color, WHITE, 0.08), { z = 2 })
		tri(g, x - math.cos(a) * 0.03, y - math.sin(a) * 0.03, 0.17, s * 38, rgb(255, 160, 185), { z = 3 })
	end
end

function HATS.TopHat(g)
	local black = rgb(40, 34, 52)
	box(g, 0.5, -0.07, 0.27, 0.27, black, { corner = UDim.new(0.12, 0), grad = { color = shade(rgb(90, 80, 110), black), rot = 0 } })
	box(g, 0.5, 0.02, 0.27, 0.055, rgb(205, 40, 65), { z = 2, corner = UDim.new(0.2, 0) })
	bar(g, 0.29, 0.065, 0.71, 0.065, 0.055, black, { z = 3 })
end

-- Building a look ----------------------------------------------------------------------------------------

local MOUTH_SCALE = 1.45
local HAT_SCALE = { Laurel = 1, CatEars = 1, Party = 1.15, Propeller = 1.3, Halo = 1.25 }

-- look = { skin = { Pattern, Eyes, Mouth, Hat, Color2 = {r,g,b} }, color = Color3, flag = bool }
-- Returns handles: { look = Frame (move it to follow the swim direction), lookAmount,
--                    open = Frame, closed = Frame (swap their Visible to blink), spin = Frame or nil }
function Looks.build(root, look)
	local skin = look.skin or {}
	local color = look.color or rgb(120, 220, 120)
	local c2 = skin.Color2 and rgb(skin.Color2[1], skin.Color2[2], skin.Color2[3]) or WHITE
	local handles = {}
	local pattern = PATTERNS[skin.Pattern or "None"]
	if pattern and not look.flag then
		pattern(group(root, "Pattern", 1), c2, color)
	end
	-- glossy shine (on flags too)
	local shine = group(root, "Shine", 2)
	box(shine, 0.33, 0.24, 0.3, 0.15, WHITE, { rot = -35, t = 0.62 })
	circle(shine, 0.19, 0.37, 0.05, WHITE, { t = 0.5 })
	local face = group(root, "Face", 3)
	local open = group(face, "Open", 1)
	local closed = group(face, "Closed", 2)
	closed.Visible = false
	local lookGroup = group(open, "Look", 3)
	local eyes = EYES[skin.Eyes or "Cute"] or EYES.Cute
	handles.lookAmount = eyes(open, lookGroup, closed)
	handles.look, handles.open, handles.closed = lookGroup, open, closed
	handles.googly = skin.Eyes == "Googly"
	local mouth = MOUTHS[skin.Mouth or "Smile"]
	if mouth then
		-- drawn at mouth scale, then blown up around the mouth so it reads at game size
		local g = group(face, "Mouth", 4)
		g.Size = UDim2.fromScale(MOUTH_SCALE, MOUTH_SCALE)
		g.Position = UDim2.fromScale(0.5, 0.64 - (0.63 - 0.5) * MOUTH_SCALE)
		mouth(g)
	end
	local hat = HATS[skin.Hat or "None"]
	if hat then
		-- grown around the top rim of the disc (y = 0.05), so it stays sitting on the head
		local k = HAT_SCALE[skin.Hat] or 1.4
		local g = group(root, "Hat", 5)
		g.Size = UDim2.fromScale(k, k)
		g.Position = UDim2.fromScale(0.5, 0.05 + 0.45 * k)
		hat(g, color)
		handles.spin = g:FindFirstChild("Spin")
	end
	return handles
end

-- Points the eyes along (dx, dz) (a unit direction on screen: x right, z down)
function Looks.aim(handles, dx, dz, t)
	local k = handles.lookAmount or 0
	if k <= 0 then
		return
	end
	if handles.googly and t then
		dx += math.sin(t * 9) * 0.35
		dz += math.cos(t * 7) * 0.35
	end
	handles.look.Position = UDim2.fromScale(0.5 + dx * k, 0.5 + dz * k)
end

function Looks.blink(handles, shut)
	if handles.closed and handles.closed:FindFirstChildWhichIsA("Frame") then
		handles.open.Visible = not shut
		handles.closed.Visible = shut
	end
end

Looks.patterns, Looks.eyes, Looks.mouths, Looks.hats = PATTERNS, EYES, MOUTHS, HATS
Looks.shapes = { box = box, circle = circle, tri = tri, bar = bar, arc = arc, heart = heart }
return Looks
