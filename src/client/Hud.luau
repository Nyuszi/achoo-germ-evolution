-- The on-screen game interface: size and zone, progress to the next zone or the sneeze, DNA,
-- the size board, move buttons with cooldowns, kill feed, toasts, banners, boss health, the death
-- screen, quarantine, the Arena timer and the big ACHOO! sneeze cutscene.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Ui = require(script.Parent.Ui)

local Hud = {}

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local gui = Ui.gui
local make, text, button, corner = Ui.make, Ui.text, Ui.button, Ui.corner
local INK = Ui.INK

-- Top: size, zone and progress -----------------------------------------------------------

local top = make("Frame", { Size = UDim2.new(0, 380, 0, 96), Position = UDim2.new(0.5, -190, 0, 6), BackgroundTransparency = 1, Parent = gui })
local sizeLabel = text({ Size = UDim2.new(1, 0, 0, 40), Text = "Size 10", Parent = top })
local zoneLabel = text({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 40), Text = "", Parent = top })
local barBack = make("Frame", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 64), BackgroundColor3 = Color3.fromRGB(40, 25, 50), BackgroundTransparency = 0.2, Parent = top }, { corner(12) })
local barFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(120, 230, 140), Parent = barBack }, { corner(12) })
local barText = text({ Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 2, Parent = barBack })

local dnaLabel = text({ Size = UDim2.new(0, 220, 0, 34), Position = UDim2.new(0, 10, 0, 6), Text = "🧬 0 DNA", TextXAlignment = Enum.TextXAlignment.Left, Parent = gui })
local subLabel = text({ Size = UDim2.new(0, 260, 0, 22), Position = UDim2.new(0, 10, 0, 40), Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(220, 200, 255), Parent = gui })

-- size board (top right)
local board = make("Frame", { Size = UDim2.new(0, 210, 0, 170), Position = UDim2.new(1, -220, 0, 6), BackgroundColor3 = Ui.PANEL, BackgroundTransparency = 0.35, Parent = gui }, { corner(12) })
text({ Size = UDim2.new(1, 0, 0, 24), Text = "Biggest germs", Parent = board })
local boardRows = {}
for i = 1, 6 do
	boardRows[i] = text({ Size = UDim2.new(1, -12, 0, 22), Position = UDim2.new(0, 6, 0, 24 + (i - 1) * 23), Text = "", TextXAlignment = Enum.TextXAlignment.Left, Parent = board })
end

-- toasts, banner, kill feed
local toast = text({ Size = UDim2.new(0, 520, 0, 34), Position = UDim2.new(0.5, -260, 0, 106), Text = "", TextTransparency = 1, Parent = gui })
local banner = text({ Size = UDim2.new(0, 640, 0, 44), Position = UDim2.new(0.5, -320, 0.26, 0), Text = "", TextTransparency = 1, TextColor3 = Color3.fromRGB(255, 230, 120), Parent = gui })
local feedFrame = make("Frame", { Size = UDim2.new(0, 300, 0, 120), Position = UDim2.new(1, -310, 0, 352), BackgroundTransparency = 1, Parent = gui }, {
	make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Top, Padding = UDim.new(0, 2) }),
})

local function fadeOut(label, after)
	label.TextTransparency = 0
	label:FindFirstChildOfClass("UIStroke").Transparency = 0
	local token = {}
	label:SetAttribute("Token", tostring(token))
	task.delay(after, function()
		if label:GetAttribute("Token") == tostring(token) then
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			TweenService:Create(label:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
	end)
end

function Hud.notify(message, kind)
	toast.Text = message
	if kind == "error" then
		toast.TextColor3 = Color3.fromRGB(255, 140, 140)
	elseif kind == "success" then
		toast.TextColor3 = Color3.fromRGB(150, 255, 160)
	else
		toast.TextColor3 = INK
	end
	fadeOut(toast, 3.5)
end

function Hud.announce(message)
	banner.Text = message
	fadeOut(banner, 4)
end

function Hud.feed(eater, victim, revenge, crowned)
	local line = eater .. " ate " .. victim
	if revenge then
		line = "⚡ " .. eater .. " got REVENGE on " .. victim
	elseif crowned then
		line = "👑 " .. eater .. " ate the king " .. victim
	end
	local label = text({ Size = UDim2.new(1, 0, 0, 20), Text = line, TextXAlignment = Enum.TextXAlignment.Right, Parent = feedFrame })
	local children = {}
	for _, c in feedFrame:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(children, c)
		end
	end
	if #children > 5 then
		children[1]:Destroy()
	end
	task.delay(8, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

-- Quarantine, boss health, Arena timer, potion ------------------------------------------------

local quarantine = text({ Size = UDim2.new(0, 560, 0, 26), Position = UDim2.new(0.5, -280, 1, -150), Text = "", Visible = false, TextColor3 = Color3.fromRGB(150, 220, 255), Parent = gui })
local bossFrame = make("Frame", { Size = UDim2.new(0, 320, 0, 26), Position = UDim2.new(0.5, -160, 0, 140), BackgroundColor3 = Color3.fromRGB(40, 25, 50), Visible = false, Parent = gui }, { corner(12) })
local bossFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(230, 80, 120), Parent = bossFrame }, { corner(12) })
local bossText = text({ Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 2, Parent = bossFrame })
local bossSeen = 0
function Hud.bossHp(data)
	if data.hp <= 0 then
		bossFrame.Visible = false
		return
	end
	bossFrame.Visible = true
	bossSeen = os.clock()
	bossFill.Size = UDim2.fromScale(math.clamp(data.hp / data.max, 0, 1), 1)
	bossText.Text = data.name .. "  " .. Formulas.formatNumber(data.hp) .. " / " .. Formulas.formatNumber(data.max)
end
local arenaLabel = text({ Size = UDim2.new(0, 300, 0, 24), Position = UDim2.new(0.5, -150, 0, 112), Text = "", Visible = false, Parent = gui })
function Hud.arenaTimer(data)
	arenaLabel.Visible = true
	local s = math.ceil(data.left)
	if data.sudden then
		arenaLabel.Text = string.format("☠️ SUDDEN DEATH %d:%02d", s // 60, s % 60)
		arenaLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	else
		arenaLabel.Text = string.format("⏱️ Sudden death in %d:%02d", s // 60, s % 60)
		arenaLabel.TextColor3 = INK
	end
end

-- Death screen ----------------------------------------------------------------------------------

local death = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Visible = false, ZIndex = 20, Parent = gui })
local deathText = text({ Size = UDim2.new(0.8, 0, 0, 60), Position = UDim2.new(0.1, 0, 0.36, 0), Text = "", ZIndex = 21, Parent = death })
local deathSub = text({ Size = UDim2.new(0.8, 0, 0, 30), Position = UDim2.new(0.1, 0, 0.36, 66), Text = "", ZIndex = 21, Parent = death })
local reviveButton = button({ Size = UDim2.new(0, 260, 0, 50), Position = UDim2.new(0.5, -130, 0.36, 110), Text = "💖 Revive at full size (25 R$)", BackgroundColor3 = Ui.GOOD, ZIndex = 21, Parent = death }, function()
	local ok, message = Remotes.Shop:InvokeServer("BuyProduct", "Revive")
	if not ok and message then
		Hud.notify(message, "error")
	end
end)

function Hud.died(eaterName, seconds, canRevive, backToFloor)
	death.Visible = true
	deathText.Text = "You were eaten by " .. eaterName .. "!"
	if backToFloor then
		deathSub.Text = "Back to Floor " .. backToFloor .. " (your checkpoint)..."
	else
		deathSub.Text = "Coming back with part of your size... (Revenge: eat them within 60 s for 2x DNA)"
	end
	reviveButton.Visible = canRevive == true
	task.delay(seconds, function()
		death.Visible = false
	end)
end

-- Sneeze cutscene ---------------------------------------------------------------------------------

local sneezeFx = {
	Classic = { Color3.fromRGB(180, 255, 180), Color3.fromRGB(255, 255, 255) },
	Glitter = { Color3.fromRGB(255, 220, 255), Color3.fromRGB(255, 240, 150) },
	Fireworks = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 160, 255) },
	Rainbow = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(80, 255, 120) },
	Confetti = { Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 100, 220) },
	Galaxy = { Color3.fromRGB(80, 40, 160), Color3.fromRGB(160, 220, 255) },
}
local sneezeScreen = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui })
local sneezeBig = text({ Size = UDim2.new(0.9, 0, 0.22, 0), Position = UDim2.new(0.05, 0, 0.25, 0), Text = "ACHOO!", ZIndex = 32, Parent = sneezeScreen })
local sneezeSub = text({ Size = UDim2.new(0.8, 0, 0, 40), Position = UDim2.new(0.1, 0, 0.5, 0), Text = "", ZIndex = 32, Parent = sneezeScreen })
local sneezeSub2 = text({ Size = UDim2.new(0.8, 0, 0, 30), Position = UDim2.new(0.1, 0, 0.5, 46), Text = "", ZIndex = 32, TextColor3 = Color3.fromRGB(255, 240, 160), Parent = sneezeScreen })

function Hud.sneeze(data)
	local colors = sneezeFx[data.fx] or sneezeFx.Classic
	sneezeScreen.Visible = true
	sneezeScreen.BackgroundTransparency = 0
	sneezeScreen.BackgroundColor3 = colors[1]
	sneezeBig.Text = "A-A-ACHOO!"
	sneezeSub.Text = "You were sneezed out of " .. data.from .. "!"
	local extras = { "+" .. data.dna .. " DNA", "+1 Germ Point", "+25% growth forever" }
	if data.core then
		table.insert(extras, "New core: " .. data.core)
	end
	if data.mutantUp then
		table.insert(extras, "MUTANT " .. data.mutant .. "! +50% DNA forever")
	end
	if data.arenaUnlocked then
		table.insert(extras, "THE INFINITE PETRI IS OPEN!")
	end
	sneezeSub2.Text = table.concat(extras, "  ·  ")
	-- confetti of the sneeze effect's colours
	for i = 1, 40 do
		local dot = make("Frame", {
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.fromScale(0.5, 0.45),
			BackgroundColor3 = (i % 2 == 0) and colors[1] or colors[2],
			ZIndex = 31,
			Parent = sneezeScreen,
		}, { corner(7) })
		local a = math.random() * math.pi * 2
		local d = 0.3 + math.random() * 0.5
		TweenService:Create(dot, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5 + math.cos(a) * d, 0.45 + math.sin(a) * d),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(1.7, function()
			dot:Destroy()
		end)
	end
	TweenService:Create(sneezeScreen, TweenInfo.new(1.2), { BackgroundColor3 = Color3.fromRGB(30, 20, 40), BackgroundTransparency = 0.15 }):Play()
	local extra = data.sneezeCam and 2 or 0
	local frame = nil
	if data.sneezeCam then
		-- Sneeze Cam: a sticker photo frame around the moment (screenshot it!)
		frame = make("Frame", { Size = UDim2.fromScale(0.8, 0.7), Position = UDim2.fromScale(0.1, 0.12), BackgroundTransparency = 1, ZIndex = 31, Parent = sneezeScreen }, { Ui.stroke(10), corner(24) })
		frame:FindFirstChildOfClass("UIStroke").Color = colors[2]
		for i, sticker in { "🤧", "💥", "🦠", "✨", "📸", "🎉" } do
			local a = (i / 6) * math.pi * 2
			text({ Size = UDim2.fromOffset(70, 70), Position = UDim2.new(0.5 + math.cos(a) * 0.42, -35, 0.47 + math.sin(a) * 0.4, -35), Text = sticker, ZIndex = 33, Parent = frame })
		end
		text({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -40), Text = "📸 SNEEZE CAM · " .. player.DisplayName .. " · sneeze #" .. data.sneezes, ZIndex = 33, Parent = frame })
	end
	task.delay(2.2 + extra / 2, function()
		sneezeBig.Text = "Welcome inside"
		sneezeSub.Text = data.to .. "!"
	end)
	task.delay(4.2 + extra, function()
		if frame then
			frame:Destroy()
		end
		TweenService:Create(sneezeScreen, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		task.wait(0.8)
		sneezeScreen.Visible = false
	end)
end

-- Move buttons --------------------------------------------------------------------------------

local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local moves = make("Frame", { Size = UDim2.new(0, 260, 0, 140), Position = UDim2.new(1, -270, 1, -150), BackgroundTransparency = 1, Parent = gui })
local function moveButton(label, x, y, action, color)
	return button({ Size = UDim2.new(0, 120, 0, isTouch and 64 or 52), Position = UDim2.new(0, x, 0, y), Text = label, BackgroundColor3 = color, Parent = moves }, function()
		Remotes.Action:FireServer(action)
	end)
end
local dashButton = moveButton("DASH", 0, 76, "Dash", Color3.fromRGB(80, 170, 255))
local splitButton = moveButton("SPLIT", 130, 76, "Split", Color3.fromRGB(255, 140, 80))
local frontButton = moveButton("Q", 0, 14, "Front", Color3.fromRGB(150, 90, 220))
local specialButton = moveButton("R", 130, 14, "Special", Color3.fromRGB(220, 80, 150))

local ACTIVE_NAMES = { Chomp = "Chomp", Vacuum = "Vacuum", Pierce = "Pierce", Ghost = "Ghost", GravityWell = "Gravity", Blast = "Blast" }

local function cooldownText(base, keys, seconds)
	local t = base
	if not isTouch and keys then
		t = t .. " " .. keys
	end
	if seconds > 0.05 then
		t = t .. string.format(" %.0f", math.ceil(seconds))
	end
	return t
end

-- Minimap (top right, under the size board) ------------------------------------------------------

local MAP = 160
local map = make("Frame", { Size = UDim2.fromOffset(MAP, MAP), Position = UDim2.new(1, -MAP - 25, 0, 182), BackgroundColor3 = Color3.fromRGB(30, 20, 40), BackgroundTransparency = 0.2, Parent = gui }, { corner(MAP / 2), Ui.stroke(3) })
local mapRings = {}
local mapDots = {}
local mapDish = nil
local function dot(color, size, z)
	return make("Frame", { Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, ZIndex = z or 3, Parent = map }, { corner(size / 2) })
end
local meDot = dot(Color3.new(1, 1, 1), 10, 6)
Ui.stroke(2).Parent = meDot
local mapLabel = text({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, 2), Text = "", Parent = map })

-- A new dish: draw its zones
function Hud.mapDish(info)
	mapDish = info
	for _, r in mapRings do
		r:Destroy()
	end
	mapRings = {}
	for i, z in info.zones do
		local share = z.outer / info.radius
		local c = Color3.fromRGB(255, 255, 255)
		local ring = make("Frame", {
			Size = UDim2.fromScale(share * 0.94, share * 0.94),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = c,
			BackgroundTransparency = 0.88 - i * 0.06,
			ZIndex = 1 + i,
			Parent = map,
		}, { corner(1000) })
		table.insert(mapRings, ring)
	end
	local nerve = dot(info.kind == "arena" and Color3.fromRGB(120, 255, 200) or Color3.fromRGB(255, 230, 120), 9, 5)
	nerve.Position = UDim2.fromScale(0.5, 0.5)
	table.insert(mapRings, nerve)
	mapLabel.Text = info.kind == "arena" and ("Floor " .. info.floor) or info.name
end

local function mapPos(x, z)
	local r = mapDish.radius
	local u = (x - mapDish.cx) / r * 0.47 + 0.5
	local v = (z - mapDish.cz) / r * 0.47 + 0.5
	return UDim2.fromScale(u, v)
end

-- Every frame: you, the king, bosses and golden food
function Hud.map(meX, meZ, markers)
	if not mapDish then
		return
	end
	meDot.Visible = meX ~= nil
	if meX then
		meDot.Position = mapPos(meX, meZ)
	end
	for _, d in mapDots do
		d.Visible = false
	end
	local n = 0
	local function place(p, color, size, z)
		n += 1
		local d = mapDots[n]
		if not d then
			d = dot(color, size, z)
			mapDots[n] = d
		end
		d.BackgroundColor3 = color
		d.Size = UDim2.fromOffset(size, size)
		d.Position = mapPos(p.x, p.z)
		d.Visible = true
	end
	for _, g in markers.golden do
		place(g, Color3.fromRGB(255, 200, 40), 7, 4)
	end
	for _, b in markers.bosses do
		place(b, Color3.fromRGB(255, 70, 90), 10, 5)
	end
	if markers.king then
		place(markers.king, Color3.fromRGB(255, 215, 0), 11, 5)
	end
end

-- Germ Radar pass: arrows around your germ pointing at the nearest germs
local arrows = {}
local RADAR_COLORS = { prey = Color3.fromRGB(120, 255, 140), danger = Color3.fromRGB(255, 90, 90), fight = Color3.fromRGB(255, 220, 90) }
function Hud.radar(list, meX, meZ)
	for i = 1, 3 do
		local a = arrows[i]
		local target = list and list[i]
		if not a then
			a = text({ Size = UDim2.fromOffset(56, 56), AnchorPoint = Vector2.new(0.5, 0.5), Text = "➤", ZIndex = 8, Parent = gui })
			arrows[i] = a
		end
		a.Visible = target ~= nil and meX ~= nil
		if a.Visible then
			local dx, dz = target.x - meX, target.z - meZ
			local angle = math.atan2(dz, dx) -- the camera looks down with north (-Z) at the top
			local ring = 0.3
			a.Position = UDim2.new(0.5 + math.cos(angle) * ring * 0.62, 0, 0.5 + math.sin(angle) * ring, 0)
			a.Rotation = math.deg(angle)
			a.TextColor3 = RADAR_COLORS[target.kind] or Ui.INK
			a.TextTransparency = 0.1
		end
	end
end

-- Updates --------------------------------------------------------------------------------------

local state = nil

function Hud.state()
	return state
end

function Hud.sync(newState)
	state = newState
	local size = state.size
	sizeLabel.Text = "Size " .. Formulas.formatNumber(size) .. (state.crowned and " 👑" or "")
	zoneLabel.Text = state.zoneName .. " · inside " .. state.hostName
	dnaLabel.Text = "🧬 " .. Formulas.formatNumber(state.dna) .. " DNA"
	local bits = {}
	if state.gp > 0 then
		table.insert(bits, "⭐ " .. state.gp .. " Germ Points")
	end
	if state.mode == "arena" then
		table.insert(bits, "🎟️ " .. state.tokens .. " tokens")
	end
	if state.potion > 0 then
		local s = math.floor(state.potion)
		table.insert(bits, string.format("🧪 %d:%02d", s // 60, s % 60))
	end
	if state.mutant > 0 then
		table.insert(bits, "Mutant " .. state.mutant)
	end
	subLabel.Text = table.concat(bits, "  ")
	local gate = state.nextGate
	local share = math.clamp(size / gate.size, 0, 1)
	barFill.Size = UDim2.fromScale(share, 1)
	if gate.name == "Sneeze" then
		if size >= gate.size then
			barText.Text = "READY! Swim into the Sneeze Nerve in the middle!"
			barFill.BackgroundColor3 = Color3.fromRGB(255, 220, 90)
		else
			barText.Text = "Size " .. Formulas.formatNumber(gate.size) .. " to SNEEZE into the next host"
			barFill.BackgroundColor3 = Color3.fromRGB(120, 230, 140)
		end
	elseif gate.name == "Exit" then
		barText.Text = size >= gate.size and "Touch the Exit Pore in the middle!" or ("Floor " .. (state.floor or 1) .. ": reach size " .. Formulas.formatNumber(gate.size))
	else
		barText.Text = "Size " .. Formulas.formatNumber(gate.size) .. " to enter the " .. gate.name
		barFill.BackgroundColor3 = Color3.fromRGB(120, 230, 140)
	end
	if state.quarantine > 0 then
		quarantine.Visible = true
		local s = math.ceil(state.quarantine)
		quarantine.Text = string.format("🛡️ Quarantine %d:%02d: nobody can eat you, and you can only eat bots and food", s // 60, s % 60)
	else
		quarantine.Visible = false
	end
	if state.mode ~= "arena" then
		arenaLabel.Visible = false
	end
	reviveButton.Visible = reviveButton.Visible and state.canRevive
	for slot, b in { Front = frontButton, Special = specialButton } do
		local a = state.actives[slot]
		b.Visible = a ~= nil
		b:SetAttribute("Ready", a and a.readyIn or 0)
		b:SetAttribute("Name", a and (ACTIVE_NAMES[a.id] or a.id) or "")
	end
	Hud.onSync(state)
end
Hud.onSync = function(s) end

-- Called every frame with the local cooldowns counting down
function Hud.tick(dt)
	if state then
		state.dashIn = math.max(0, (state.dashIn or 0) - dt)
		state.splitIn = math.max(0, (state.splitIn or 0) - dt)
		dashButton.Text = cooldownText("DASH", "[Shift]", state.dashIn)
		splitButton.Text = cooldownText("SPLIT", "[Space]", state.splitIn)
		dashButton.BackgroundTransparency = state.dashIn > 0.05 and 0.5 or 0
		splitButton.BackgroundTransparency = state.splitIn > 0.05 and 0.5 or 0
		for key, b in { Q = frontButton, R = specialButton } do
			local ready = math.max(0, (b:GetAttribute("Ready") or 0) - dt)
			b:SetAttribute("Ready", ready)
			b.Text = cooldownText(b:GetAttribute("Name") or "", "[" .. key .. "]", ready)
			b.BackgroundTransparency = ready > 0.05 and 0.5 or 0
		end
	end
	if bossFrame.Visible and os.clock() - bossSeen > 3 then
		bossFrame.Visible = false
	end
end

function Hud.board(rows, myGermId)
	for i, label in boardRows do
		local row = rows[i]
		if row then
			label.Text = i .. ". " .. row.name .. "  " .. Formulas.formatNumber(row.size)
			label.TextColor3 = (row.germId == myGermId) and Color3.fromRGB(140, 255, 160) or INK
		else
			label.Text = ""
		end
	end
end

-- True when a screen point is over one of our buttons/panels (so a tap there is not steering)
function Hud.isOverUi(x, y)
	local objects = player.PlayerGui:GetGuiObjectsAtPosition(x, y)
	for _, o in objects do
		if o:IsDescendantOf(gui) and (o:IsA("GuiButton") or o:IsA("TextBox") or o:IsA("ScrollingFrame") or (Ui.openPanel() and o == Ui.openPanel().frame)) then
			return true
		end
	end
	return false
end

local _ = Config
return Hud
