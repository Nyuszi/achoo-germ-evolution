-- The on-screen interface: size and zone, progress to the next zone, DNA, the size board,
-- Dash/Split buttons, kill feed, toasts, death screen, quarantine banner, the Lab and Bugs & Ideas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local Hud = {}

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(255, 255, 255)
local PANEL = Color3.fromRGB(40, 25, 50)

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, children)
	local o = Instance.new(class)
	for k, v in props do
		o[k] = v
	end
	for _, c in children or {} do
		c.Parent = o
	end
	return o
end

local function corner(px)
	return make("UICorner", { CornerRadius = UDim.new(0, px or 12) })
end

local function stroke(px)
	return make("UIStroke", { Thickness = px or 2, Color = Color3.fromRGB(20, 10, 30), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end

local function text(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or INK
	props.TextScaled = props.TextScaled ~= false
	local label = make("TextLabel", props)
	stroke(2).Parent = label
	return label
end

local function button(props, onClick)
	props.Font = FONT
	props.TextColor3 = INK
	props.TextScaled = true
	props.AutoButtonColor = true
	local b = make("TextButton", props, { corner(14) })
	stroke(2).Parent = b
	b.Activated:Connect(onClick)
	return b
end

-- Top: size, zone and progress -----------------------------------------------------------

local top = make("Frame", {
	Size = UDim2.new(0, 360, 0, 92),
	Position = UDim2.new(0.5, -180, 0, 6),
	BackgroundTransparency = 1,
	Parent = gui,
})
local sizeLabel = text({ Size = UDim2.new(1, 0, 0, 40), Text = "Size 10", Parent = top })
local zoneLabel = text({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 40), Text = "", Parent = top })
local barBack = make("Frame", {
	Size = UDim2.new(1, 0, 0, 22),
	Position = UDim2.new(0, 0, 0, 64),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.2,
	Parent = top,
}, { corner(11) })
local barFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(120, 230, 140), Parent = barBack }, { corner(11) })
local barText = text({ Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 2, Parent = barBack })

-- DNA (left) ----------------------------------------------------------------------------------
local dnaLabel = text({
	Size = UDim2.new(0, 180, 0, 34),
	Position = UDim2.new(0, 12, 0, 60),
	Text = "🧬 0 DNA",
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = gui,
})

-- Size board (right) -------------------------------------------------------------------------
local board = make("Frame", {
	Size = UDim2.new(0, 190, 0, 190),
	Position = UDim2.new(1, -200, 0, 60),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.35,
	Parent = gui,
}, { corner(12), make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
text({ Size = UDim2.new(1, 0, 0, 22), Text = "Biggest germs", Parent = board })
local boardRows = {}
for i = 1, 6 do
	boardRows[i] = text({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0, 2 + i * 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = board,
	})
end

-- Toasts, announcements, kill feed -------------------------------------------------------------
local toast = text({
	Size = UDim2.new(0, 520, 0, 34),
	Position = UDim2.new(0.5, -260, 0, 110),
	Text = "",
	TextTransparency = 1,
	Parent = gui,
})
local banner = text({
	Size = UDim2.new(0, 600, 0, 40),
	Position = UDim2.new(0.5, -300, 0.22, 0),
	Text = "",
	TextColor3 = Color3.fromRGB(255, 220, 90),
	TextTransparency = 1,
	Parent = gui,
})
local feedFrame = make("Frame", {
	Size = UDim2.new(0, 320, 0, 120),
	Position = UDim2.new(0, 12, 1, -230),
	BackgroundTransparency = 1,
	Parent = gui,
}, { make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 2) }) })

local function fadeOut(label, after)
	label.TextTransparency = 0
	local id = (label:GetAttribute("Shown") or 0) + 1
	label:SetAttribute("Shown", id)
	task.delay(after, function()
		if label:GetAttribute("Shown") == id then
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		end
	end)
end

function Hud.notify(message, kind)
	toast.Text = message
	if kind == "success" then
		toast.TextColor3 = Color3.fromRGB(140, 255, 160)
	elseif kind == "error" then
		toast.TextColor3 = Color3.fromRGB(255, 140, 140)
	else
		toast.TextColor3 = INK
	end
	fadeOut(toast, 3)
end

function Hud.announce(message)
	banner.Text = message
	fadeOut(banner, 4)
end

function Hud.feed(eater, victim, revenge, crowned)
	local line = eater .. " ate " .. victim
	if crowned then
		line = eater .. " ate the king " .. victim .. " 👑"
	elseif revenge then
		line = eater .. " got revenge on " .. victim
	end
	local label = text({ Size = UDim2.new(1, 0, 0, 22), Text = line, TextXAlignment = Enum.TextXAlignment.Left, Parent = feedFrame })
	local items = {}
	for _, c in feedFrame:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(items, c)
		end
	end
	if #items > 4 then
		items[1]:Destroy()
	end
	task.delay(6, function()
		if label.Parent then
			label:Destroy()
		end
	end)
end

-- Quarantine banner --------------------------------------------------------------------------
local quarantine = text({
	Size = UDim2.new(0, 560, 0, 26),
	Position = UDim2.new(0.5, -280, 0, 100),
	Text = "",
	TextColor3 = Color3.fromRGB(160, 220, 255),
	Visible = false,
	Parent = gui,
})

-- Death screen -----------------------------------------------------------------------------
local death = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(30, 0, 10),
	BackgroundTransparency = 0.45,
	Visible = false,
	ZIndex = 20,
	Parent = gui,
})
local deathText = text({ Size = UDim2.new(0.8, 0, 0, 60), Position = UDim2.new(0.1, 0, 0.4, 0), Text = "", ZIndex = 21, Parent = death })
local deathSub = text({ Size = UDim2.new(0.8, 0, 0, 30), Position = UDim2.new(0.1, 0, 0.4, 66), Text = "", ZIndex = 21, Parent = death })

function Hud.died(eaterName, seconds)
	death.Visible = true
	deathText.Text = "You were eaten by " .. eaterName .. "!"
	deathSub.Text = "You keep all your DNA. Back in " .. math.ceil(seconds) .. "..."
	task.delay(seconds, function()
		death.Visible = false
	end)
end

-- Moves (Dash / Split) -------------------------------------------------------------------------
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local dashButton = button({
	Size = UDim2.new(0, 110, 0, 110),
	Position = UDim2.new(1, -130, 1, -250),
	BackgroundColor3 = Color3.fromRGB(90, 170, 255),
	Text = isTouch and "DASH" or "DASH\n[Shift]",
	Parent = gui,
}, function()
	Remotes.Action:FireServer("Dash")
end)
local splitButton = button({
	Size = UDim2.new(0, 90, 0, 90),
	Position = UDim2.new(1, -240, 1, -150),
	BackgroundColor3 = Color3.fromRGB(255, 150, 90),
	Text = isTouch and "SPLIT" or "SPLIT\n[Space]",
	Parent = gui,
}, function()
	Remotes.Action:FireServer("Split")
end)
Hud.buttons = { dashButton, splitButton }

local function cooldownText(base, keys, seconds)
	if seconds > 0.05 then
		return base .. "\n" .. string.format("%.1f", seconds)
	end
	if isTouch then
		return base
	end
	return base .. "\n" .. keys
end

-- The Lab (mutations) ----------------------------------------------------------------------------
local state = nil
local lab = make("Frame", {
	Size = UDim2.new(0, 460, 0, 380),
	Position = UDim2.new(0.5, -230, 0.5, -190),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 10,
	Parent = gui,
}, { corner(16) })
text({ Size = UDim2.new(1, -60, 0, 40), Position = UDim2.new(0, 14, 0, 8), Text = "🧪 The Lab: Mutations", ZIndex = 11, TextXAlignment = Enum.TextXAlignment.Left, Parent = lab })
local labDna = text({ Size = UDim2.new(1, -28, 0, 22), Position = UDim2.new(0, 14, 0, 48), Text = "", ZIndex = 11, TextXAlignment = Enum.TextXAlignment.Left, Parent = lab })
button({ Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -50, 0, 10), BackgroundColor3 = Color3.fromRGB(220, 80, 90), Text = "X", ZIndex = 11, Parent = lab }, function()
	lab.Visible = false
end)
local labRows = {}
for i, id in Config.MutationOrder do
	local m = Config.Mutations[id]
	local row = make("Frame", {
		Size = UDim2.new(1, -28, 0, 66),
		Position = UDim2.new(0, 14, 0, 78 + (i - 1) * 74),
		BackgroundColor3 = Color3.fromRGB(70, 45, 85),
		ZIndex = 11,
		Parent = lab,
	}, { corner(10) })
	text({ Size = UDim2.new(1, -150, 0, 28), Position = UDim2.new(0, 10, 0, 4), Text = m.Name .. " (" .. m.Slot .. ")", ZIndex = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
	text({ Size = UDim2.new(1, -150, 0, 24), Position = UDim2.new(0, 10, 0, 34), Text = m.Text, ZIndex = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(220, 210, 230), Parent = row })
	local b = button({ Size = UDim2.new(0, 126, 0, 46), Position = UDim2.new(1, -134, 0, 10), BackgroundColor3 = Color3.fromRGB(110, 200, 120), Text = "", ZIndex = 12, Parent = row }, function()
		local owned = state and state.owned and state.owned[id]
		local ok, message
		if owned then
			ok, message = Remotes.EquipMutation:InvokeServer(id)
		else
			ok, message = Remotes.BuyMutation:InvokeServer(id)
		end
		if message then
			Hud.notify(message, ok and "success" or "error")
		end
	end)
	labRows[id] = b
end

local function refreshLab()
	if not state then
		return
	end
	labDna.Text = "🧬 " .. Formulas.formatNumber(state.dna) .. " DNA (eat germs and food to earn more)"
	for id, b in labRows do
		local m = Config.Mutations[id]
		if state.equipped and state.equipped[m.Slot] == id then
			b.Text = "Equipped ✓"
			b.BackgroundColor3 = Color3.fromRGB(90, 160, 255)
		elseif state.owned and state.owned[id] then
			b.Text = "Equip"
			b.BackgroundColor3 = Color3.fromRGB(110, 200, 120)
		else
			b.Text = "🧬 " .. m.Cost
			b.BackgroundColor3 = (state.dna >= m.Cost) and Color3.fromRGB(110, 200, 120) or Color3.fromRGB(120, 110, 130)
		end
	end
end

button({
	Size = UDim2.new(0, 120, 0, 44),
	Position = UDim2.new(0, 12, 0, 100),
	BackgroundColor3 = Color3.fromRGB(170, 110, 230),
	Text = "🧪 Lab",
	Parent = gui,
}, function()
	lab.Visible = not lab.Visible
	refreshLab()
end)

-- Bugs & Ideas ------------------------------------------------------------------------------------
local feedback = make("Frame", {
	Size = UDim2.new(0, 420, 0, 250),
	Position = UDim2.new(0.5, -210, 0.5, -125),
	BackgroundColor3 = PANEL,
	Visible = false,
	ZIndex = 10,
	Parent = gui,
}, { corner(16) })
text({ Size = UDim2.new(1, -60, 0, 36), Position = UDim2.new(0, 14, 0, 8), Text = "🐞 Bugs & Ideas", ZIndex = 11, TextXAlignment = Enum.TextXAlignment.Left, Parent = feedback })
local box = make("TextBox", {
	Size = UDim2.new(1, -28, 0, 110),
	Position = UDim2.new(0, 14, 0, 50),
	BackgroundColor3 = Color3.fromRGB(250, 245, 255),
	TextColor3 = Color3.fromRGB(30, 20, 40),
	Font = Enum.Font.Gotham,
	TextSize = 18,
	TextWrapped = true,
	ClearTextOnFocus = false,
	MultiLine = true,
	PlaceholderText = "Tell us about a bug or an idea!",
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 11,
	Parent = feedback,
}, { corner(8) })
local function send(kind)
	local ok, message = Remotes.SendFeedback:InvokeServer(kind, box.Text)
	Hud.notify(message or "", ok and "success" or "error")
	if ok then
		box.Text = ""
		feedback.Visible = false
	end
end
button({ Size = UDim2.new(0, 120, 0, 44), Position = UDim2.new(0, 14, 1, -58), BackgroundColor3 = Color3.fromRGB(230, 100, 100), Text = "Send bug", ZIndex = 11, Parent = feedback }, function()
	send("Bug")
end)
button({ Size = UDim2.new(0, 120, 0, 44), Position = UDim2.new(0, 144, 1, -58), BackgroundColor3 = Color3.fromRGB(110, 200, 120), Text = "Send idea", ZIndex = 11, Parent = feedback }, function()
	send("Idea")
end)
button({ Size = UDim2.new(0, 100, 0, 44), Position = UDim2.new(1, -114, 1, -58), BackgroundColor3 = Color3.fromRGB(120, 110, 130), Text = "Close", ZIndex = 11, Parent = feedback }, function()
	feedback.Visible = false
end)
button({
	Size = UDim2.new(0, 120, 0, 34),
	Position = UDim2.new(0, 12, 0, 150),
	BackgroundColor3 = Color3.fromRGB(120, 110, 130),
	Text = "🐞 Bugs & Ideas",
	Parent = gui,
}, function()
	feedback.Visible = not feedback.Visible
end)

-- Updates --------------------------------------------------------------------------------------

function Hud.sync(newState)
	state = newState
	sizeLabel.Text = "Size " .. Formulas.formatNumber(state.size) .. (state.crowned and " 👑" or "")
	zoneLabel.Text = state.zoneName .. " · inside " .. state.hostName
	dnaLabel.Text = "🧬 " .. Formulas.formatNumber(state.dna) .. " DNA"
	local gate = state.nextGate
	local share = math.clamp(state.size / gate.size, 0, 1)
	barFill.Size = UDim2.fromScale(share, 1)
	if gate.name == "Sneeze" then
		barText.Text = "Size " .. Formulas.formatNumber(gate.size) .. " to SNEEZE (next update!)"
	else
		barText.Text = "Size " .. Formulas.formatNumber(gate.size) .. " to enter the " .. gate.name
	end
	if state.quarantine > 0 then
		quarantine.Visible = true
		local s = math.ceil(state.quarantine)
		quarantine.Text = string.format("🛡️ Quarantine %d:%02d: nobody can eat you, and you can't eat other players yet", s // 60, s % 60)
	else
		quarantine.Visible = false
	end
	if lab.Visible then
		refreshLab()
	end
end

-- Called every frame with the local cooldowns counting down
local dashIn, splitIn = 0, 0
function Hud.tick(dt)
	if state then
		dashIn = math.max(0, (state.dashIn or 0))
		splitIn = math.max(0, (state.splitIn or 0))
		state.dashIn = math.max(0, (state.dashIn or 0) - dt)
		state.splitIn = math.max(0, (state.splitIn or 0) - dt)
	end
	dashButton.Text = cooldownText("DASH", "[Shift]", dashIn)
	splitButton.Text = cooldownText("SPLIT", "[Space]", splitIn)
	dashButton.BackgroundTransparency = dashIn > 0.05 and 0.5 or 0
	splitButton.BackgroundTransparency = splitIn > 0.05 and 0.5 or 0
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
		if o:IsDescendantOf(gui) and (o:IsA("GuiButton") or o:IsA("TextBox") or o == lab or o == feedback) then
			return true
		end
	end
	return false
end

return Hud
