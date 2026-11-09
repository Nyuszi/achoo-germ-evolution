-- The client: bird's-eye camera that zooms out as you grow, steering (mouse, touch, WASD),
-- Dash/Split/ability keys, and wiring the server's messages to the renderer, effects, HUD and menus.
local AvatarEditorService = game:GetService("AvatarEditorService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Renderer = require(script.Parent.Renderer)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Menus = require(script.Parent.Menus)

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local camera = workspace.CurrentCamera

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local myGermId = nil
local alive = false
local camX, camZ, camH = 0, 0, Config.Camera.BaseHeight

Fx.banner = Hud.announce
Fx.bossHp = Hud.bossHp
Fx.arenaTimer = Hud.arenaTimer
Menus.notify = Hud.notify

-- Server messages ---------------------------------------------------------------------------
Remotes.DishInfo.OnClientEvent:Connect(function(info)
	Renderer.setDish(info)
	Fx.setDish(info)
	-- jump the camera to the new dish
	camX, camZ = info.cx, info.cz
	if info.kind == "host" then
		Hud.announce("🦠 Inside " .. info.name .. "! " .. (info.hazard or ""))
	else
		local mods = {}
		for _, id in info.modifiers or {} do
			table.insert(mods, Config.Arena.Modifiers[id].Name)
		end
		Hud.announce("🏟️ Floor " .. info.floor .. (#mods > 0 and (": " .. table.concat(mods, ", ")) or ""))
	end
end)
Remotes.CellInfo.OnClientEvent:Connect(Renderer.applyInfo)
Remotes.CellGone.OnClientEvent:Connect(Renderer.removeCells)
Remotes.Snapshot.OnClientEvent:Connect(Renderer.snapshot)
Remotes.FoodSync.OnClientEvent:Connect(Renderer.foodSync)
Remotes.FoodDelta.OnClientEvent:Connect(Renderer.foodDelta)
Remotes.DishFx.OnClientEvent:Connect(Fx.event)
Remotes.Notify.OnClientEvent:Connect(Hud.notify)
Remotes.Announce.OnClientEvent:Connect(Hud.announce)
Remotes.Feed.OnClientEvent:Connect(Hud.feed)
local tipsShown = false
Remotes.Profile.OnClientEvent:Connect(function(profile)
	Menus.setProfile(profile)
	-- first-time tips
	if not tipsShown and profile.Sneezes == 0 and profile.BestSize < 60 then
		tipsShown = true
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local tips = {
			touch and "👆 Hold your finger where you want to swim" or "🖱️ Your germ swims toward the mouse (or use WASD)",
			"🍬 Eat the glowing food and germs smaller than you to grow",
			"⚠️ Germs 25% bigger than you can swallow you!",
			touch and "💨 DASH to escape, SPLIT to catch prey" or "💨 Shift = dash, Space = split",
			"🤧 Grow to the sneeze size and touch the Sneeze Nerve in the middle!",
		}
		task.spawn(function()
			task.wait(4)
			for _, tip in tips do
				Hud.announce(tip)
				task.wait(5)
			end
		end)
	end
end)
Remotes.Sneeze.OnClientEvent:Connect(Hud.sneeze)
Remotes.Died.OnClientEvent:Connect(function(eaterName, seconds, canRevive, backToFloor)
	alive = false
	Hud.died(eaterName, seconds, canRevive, backToFloor)
end)
Remotes.Sync.OnClientEvent:Connect(function(state)
	myGermId = state.germId
	Renderer.myGermId = myGermId
	alive = state.alive
	Menus.setMode(state.mode)
	Hud.sync(state)
end)
Remotes.Prompt.OnClientEvent:Connect(function(kind)
	if kind == "Favorite" then
		pcall(function()
			AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
	elseif kind == "Invite" then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end
end)

-- Camera -------------------------------------------------------------------------------------
-- Straight down from above. Height follows your size, so a bigger germ sees more of the host.
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = 60
local zoom = 1 -- mouse wheel / pinch, 0.7 .. 1.6
local pulse = 0 -- short zoom bump when you grow a lot
local lastTotal = 0
local growCheck = 0
local lastRadius = Formulas.radius(Config.StartSize)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel and not Hud.isOverUi(input.Position.X, input.Position.Y) then
		zoom = math.clamp(zoom - input.Position.Z * 0.08, 0.7, 1.6)
	end
end)
UserInputService.TouchPinch:Connect(function(_, scale, _, state)
	if state == Enum.UserInputState.Change then
		zoom = math.clamp(zoom / (1 + (scale - 1) * 0.05), 0.7, 1.6)
	end
end)

-- Steering -------------------------------------------------------------------------------------
local steerX, steerZ = nil, nil
local touchPos = nil -- the finger currently steering

local function screenToWorld(x, y)
	local ray = camera:ViewportPointToRay(x, y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local t = -ray.Origin.Y / ray.Direction.Y
	local p = ray.Origin + ray.Direction * t
	return p.X, p.Z
end

UserInputService.TouchStarted:Connect(function(input, processed)
	if processed or Hud.isOverUi(input.Position.X, input.Position.Y) then
		return
	end
	touchPos = input
end)
UserInputService.TouchEnded:Connect(function(input)
	if touchPos == input then
		touchPos = nil
	end
end)

local KEYS = {
	[Enum.KeyCode.W] = { 0, -1 }, [Enum.KeyCode.Up] = { 0, -1 },
	[Enum.KeyCode.S] = { 0, 1 }, [Enum.KeyCode.Down] = { 0, 1 },
	[Enum.KeyCode.A] = { -1, 0 }, [Enum.KeyCode.Left] = { -1, 0 },
	[Enum.KeyCode.D] = { 1, 0 }, [Enum.KeyCode.Right] = { 1, 0 },
}
local usingKeys = false

local function updateSteer(cx, cz, radius)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	local kx, kz = 0, 0
	for key, dir in KEYS do
		if UserInputService:IsKeyDown(key) then
			kx += dir[1]
			kz += dir[2]
		end
	end
	if kx ~= 0 or kz ~= 0 then
		usingKeys = true
		local len = math.sqrt(kx * kx + kz * kz)
		steerX, steerZ = cx + kx / len * (radius + 60), cz + kz / len * (radius + 60)
		return
	end
	if touchPos then
		local inset = GuiService:GetGuiInset() -- touch positions are in GUI space
		local x, z = screenToWorld(touchPos.Position.X + inset.X, touchPos.Position.Y + inset.Y)
		if x then
			steerX, steerZ = x, z
		end
		return
	end
	if usingKeys then
		-- keys released: stop where we are until the mouse moves
		steerX, steerZ = cx, cz
		usingKeys = false
		return
	end
	if UserInputService.MouseEnabled then
		local m = UserInputService:GetMouseLocation()
		local x, z = screenToWorld(m.X, m.Y)
		if x then
			steerX, steerZ = x, z
		end
	end
end

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		usingKeys = false
	end
end)

-- Move keys
local function bind(name, action, ...)
	ContextActionService:BindAction(name, function(_, state)
		if state == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() then
			Remotes.Action:FireServer(action)
		end
		return Enum.ContextActionResult.Pass
	end, false, ...)
end
bind("GermDash", "Dash", Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonR2)
bind("GermSplit", "Split", Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
bind("GermFront", "Front", Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
bind("GermSpecial", "Special", Enum.KeyCode.R, Enum.KeyCode.ButtonY)

-- Frame loop ------------------------------------------------------------------------------------
local sendTimer, boardTimer, clock = 0, 0, 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	Renderer.update(dt, clock)
	Hud.tick(dt)
	Fx.update(dt, camH)

	local cx, cz, radius, total = nil, nil, nil, 0
	if myGermId then
		cx, cz, radius, total = Renderer.germView(myGermId)
	end
	if not cx then
		radius = lastRadius -- dead or not spawned yet: keep the camera where it was
	else
		lastRadius = radius
		-- zoom pulse when you grow more than 8% within a second
		growCheck += dt
		if growCheck >= 1 then
			if lastTotal > 0 and total > lastTotal * 1.08 then
				pulse = 0.12
			end
			lastTotal = total
			growCheck = 0
		end
		local followK = 1 - math.exp(-Config.Camera.Smooth * 2 * dt)
		camX += (cx - camX) * followK
		camZ += (cz - camZ) * followK
	end
	pulse = math.max(0, pulse - dt * 0.25)
	local targetH = Formulas.cameraHeight(radius) * zoom * (1 + pulse)
	camH += (targetH - camH) * (1 - math.exp(-Config.Camera.Smooth * dt))
	camera.CFrame = CFrame.lookAt(Vector3.new(camX, camH, camZ + 0.01), Vector3.new(camX, 0, camZ), Vector3.new(0, 0, -1))
	camera.Focus = CFrame.new(camX, 0, camZ)

	-- steering, 15 times a second
	sendTimer += dt
	if alive and cx and sendTimer >= 1 / 15 then
		sendTimer = 0
		updateSteer(cx, cz, radius)
		if steerX then
			local sx, sz = steerX, steerZ
			if Fx.mirror then
				sx, sz = cx - (steerX - cx), cz - (steerZ - cz)
			end
			Remotes.Steer:FireServer(sx, sz)
		end
	end

	boardTimer += dt
	if boardTimer >= 0.5 then
		boardTimer = 0
		Hud.board(Renderer.board(6), myGermId)
	end
end)
