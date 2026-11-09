-- Small helpers for building the interface in code (one look for every menu).
local Players = game:GetService("Players")

local Ui = {}

Ui.FONT = Enum.Font.FredokaOne
Ui.INK = Color3.fromRGB(255, 255, 255)
Ui.PANEL = Color3.fromRGB(40, 25, 50)
Ui.ROW = Color3.fromRGB(62, 42, 78)
Ui.GOOD = Color3.fromRGB(90, 200, 110)
Ui.BLUE = Color3.fromRGB(80, 150, 230)
Ui.GOLD = Color3.fromRGB(235, 175, 40)
Ui.BAD = Color3.fromRGB(210, 80, 90)
Ui.GREY = Color3.fromRGB(110, 100, 120)

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")
Ui.screen = gui

-- Everything sits in one root frame that is scaled down on small screens (phones), so the
-- layout made for a 1100x620 screen fits everywhere.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root
local function fit()
	local view = workspace.CurrentCamera.ViewportSize
	local s = math.clamp(math.min(view.X / 1100, view.Y / 620), 0.5, 1)
	uiScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
end
fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
Ui.gui = root

function Ui.make(class, props, children)
	local o = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			o[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = o
	end
	if props.Parent then
		o.Parent = props.Parent
	end
	return o
end
local make = Ui.make

function Ui.corner(px)
	return make("UICorner", { CornerRadius = UDim.new(0, px or 12) })
end

function Ui.stroke(px)
	return make("UIStroke", { Thickness = px or 2, Color = Color3.fromRGB(20, 10, 30), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end

function Ui.text(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Ui.FONT
	props.TextColor3 = props.TextColor3 or Ui.INK
	if props.TextScaled == nil then
		props.TextScaled = true
	end
	local label = make("TextLabel", props)
	Ui.stroke(2).Parent = label
	return label
end

function Ui.button(props, onClick)
	props.Font = Ui.FONT
	props.TextColor3 = props.TextColor3 or Ui.INK
	props.TextScaled = true
	props.AutoButtonColor = true
	local b = make("TextButton", props, { Ui.corner(12) })
	Ui.stroke(2).Parent = b
	make("UITextSizeConstraint", { MaxTextSize = 22, Parent = b })
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local openPanel = nil -- only one menu is open at a time
Ui.panels = {}

-- A menu window with a title, a close button, optional tabs and a scrolling list.
-- Returns { frame, list, setTabs(names, onPick), clear(), title }
function Ui.panel(name, title)
	local frame = make("Frame", {
		Name = name,
		Size = UDim2.new(0.9, 0, 0.78, 0),
		Position = UDim2.new(0.05, 0, 0.12, 0),
		BackgroundColor3 = Ui.PANEL,
		BackgroundTransparency = 0, -- fully solid, or the boss bar and germs show through the menu
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	}, { Ui.corner(18), Ui.stroke(3), make("UISizeConstraint", { MaxSize = Vector2.new(720, 620) }) })
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0.12, 0)
	local titleLabel = Ui.text({ Size = UDim2.new(1, -110, 0, 38), Position = UDim2.new(0, 14, 0, 8), Text = title, ZIndex = 11, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	local sub = Ui.text({ Size = UDim2.new(1, -28, 0, 22), Position = UDim2.new(0, 14, 0, 46), Text = "", ZIndex = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(220, 200, 255), Parent = frame })
	Ui.button({ Size = UDim2.new(0, 44, 0, 38), Position = UDim2.new(1, -54, 0, 8), Text = "X", BackgroundColor3 = Ui.BAD, ZIndex = 11, Parent = frame }, function()
		Ui.close()
	end)
	local tabs = make("Frame", { Size = UDim2.new(1, -28, 0, 34), Position = UDim2.new(0, 14, 0, 72), BackgroundTransparency = 1, ZIndex = 11, Parent = frame }, {
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	})
	local list = make("ScrollingFrame", {
		Size = UDim2.new(1, -28, 1, -122),
		Position = UDim2.new(0, 14, 0, 112),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 11,
		Parent = frame,
	}, { make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local p = { frame = frame, list = list, sub = sub, title = titleLabel, tab = nil, onOpen = nil }
	function p.setTabs(names, onPick)
		for _, c in tabs:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for _, n in names do
			local b = Ui.button({ Size = UDim2.new(1 / #names, -6, 1, 0), Text = n, BackgroundColor3 = (p.tab == n) and Ui.GOLD or Ui.ROW, ZIndex = 12, Parent = tabs }, function()
				p.tab = n
				p.setTabs(names, onPick)
				onPick(n)
			end)
			local _ = b
		end
	end
	function p.clear()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end
	Ui.panels[name] = p
	return p
end

function Ui.open(name)
	local p = Ui.panels[name]
	if openPanel and openPanel ~= p then
		openPanel.frame.Visible = false
	end
	if openPanel == p and p.frame.Visible then
		p.frame.Visible = false
		openPanel = nil
		return
	end
	openPanel = p
	p.frame.Visible = true
	if p.onOpen then
		p.onOpen()
	end
end

function Ui.close()
	if openPanel then
		openPanel.frame.Visible = false
		openPanel = nil
	end
end

function Ui.isOpen(name)
	return openPanel ~= nil and openPanel == Ui.panels[name] and openPanel.frame.Visible
end

function Ui.openPanel()
	return openPanel
end

-- A row in a menu list: title, a smaller line of text, and up to 2 buttons on the right.
-- buttons = { { text, color, onClick } }. swatch = optional Color3 or emoji shown on the left.
-- swatch: a Color3, an emoji/text, or function(box) that draws into a 44 x 44 box
function Ui.row(list, order, title, info, buttons, swatch)
	local row = make("Frame", { Size = UDim2.new(1, -10, 0, 60), BackgroundColor3 = Ui.ROW, LayoutOrder = order, ZIndex = 12, Parent = list }, { Ui.corner(10) })
	local left = 10
	if swatch then
		if typeof(swatch) == "Color3" then
			make("Frame", { Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(0, 10, 0, 10), BackgroundColor3 = swatch, ZIndex = 13, Parent = row }, { Ui.corner(20) })
		elseif type(swatch) == "function" then
			-- draws its own picture into a 44 x 44 box (the Germ Editor's item previews)
			swatch(make("Frame", { Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0, 8, 0, 8), BackgroundTransparency = 1, ZIndex = 13, Parent = row }))
		else
			Ui.text({ Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0, 8, 0, 8), Text = tostring(swatch), ZIndex = 13, Parent = row })
		end
		left = 58
	end
	local width = 0
	for _ in buttons or {} do
		width += 118
	end
	Ui.text({ Size = UDim2.new(1, -left - width - 10, 0, 28), Position = UDim2.new(0, left, 0, 4), Text = title, ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
	Ui.text({ Size = UDim2.new(1, -left - width - 10, 0, 22), Position = UDim2.new(0, left, 0, 33), Text = info or "", ZIndex = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(215, 205, 230), Parent = row })
	for i, b in buttons or {} do
		Ui.button({
			Size = UDim2.new(0, 110, 0, 44),
			Position = UDim2.new(1, -118 * (#buttons - i + 1), 0, 8),
			Text = b[1],
			BackgroundColor3 = b[2] or Ui.BLUE,
			ZIndex = 13,
			Parent = row,
		}, b[3])
	end
	return row
end

-- A heading line inside a list
function Ui.heading(list, order, text)
	return Ui.text({ Size = UDim2.new(1, -10, 0, 28), Text = text, LayoutOrder = order, ZIndex = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 220, 120), Parent = list })
end

return Ui
