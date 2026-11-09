-- The client: bird's-eye camera that zooms out as you grow, steering (mouse, touch, WASD),
-- Dash/Split keys, and wiring the server's messages to the renderer and HUD.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Renderer = require(script.Parent.Renderer)
local Hud = require(script.Parent.Hud)

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local camera = workspace.CurrentCamera

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local myGermId = nil
local alive = false

-- Server messages ---------------------------------------------------------------------------
Remotes.CellInfo.OnClientEvent:Connect(Renderer.applyInfo)
Remotes.CellGone.OnClientEvent:Connect(Renderer.removeCells)
Remotes.Snapshot.OnClientEvent:Connect(Renderer.snapshot)
Remotes.FoodSync.OnClientEvent:Connect(Renderer.foodSync)
Remotes.FoodDelta.OnClientEvent:Connect(Renderer.foodDelta)
Remotes.Notify.OnClientEvent:Connect(Hud.notify)
Remotes.Announce.OnClientEvent:Connect(Hud.announce)
Remotes.Feed.OnClientEvent:Connect(Hud.feed)
Remotes.Died.OnClientEvent:Connect(function(eaterName, seconds)
	alive = false
	Hud.died(eaterName, seconds)
end)
Remotes.Sync.OnClientEvent:Connect(function(state)
	myGermId = state.germId
	alive = state.alive
	Hud.sync(state)
end)

-- Camera -------------------------------------------------------------------------------------
-- Straight down from above. Height follows your size, so a bigger germ sees more of the host.
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = 60
local camX, camZ, camH = 0, 0, Config.Camera.BaseHeight
local zoom = 1 -- mouse wheel / pinch, 0.7 .. 1.6
local pulse = 0 -- short zoom bump when you grow a lot
local lastTotal = 0
local growCheck = 0
local lastRadius = Formulas.radius(Config.StartSize)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
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

-- Dash and split keys
ContextActionService:BindAction("GermDash", function(_, state)
	if state == Enum.UserInputState.Begin then
		Remotes.Action:FireServer("Dash")
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonR2)
ContextActionService:BindAction("GermSplit", function(_, state)
	if state == Enum.UserInputState.Begin then
		Remotes.Action:FireServer("Split")
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

-- Frame loop ------------------------------------------------------------------------------------
local sendTimer, boardTimer, clock = 0, 0, 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	Renderer.update(dt, clock)
	Hud.tick(dt)

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
			Remotes.Steer:FireServer(steerX, steerZ)
		end
	end

	boardTimer += dt
	if boardTimer >= 0.5 then
		boardTimer = 0
		Hud.board(Renderer.board(6), myGermId)
	end
end)
