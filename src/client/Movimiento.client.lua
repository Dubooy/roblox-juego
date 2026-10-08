-- Controlador de movimiento en primera persona: dash, slide, doble salto,
-- coyote time, buffer de salto y bunny-hop. Va en StarterPlayerScripts.
--
-- Idea: el Humanoid sigue encargándose de la gravedad, las colisiones y el suelo,
-- pero la velocidad horizontal la calculamos nosotros y la imponemos con un
-- LinearVelocity que solo actúa en X y Z. Así el movimiento conserva el impulso.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()

player.CameraMode = Enum.CameraMode.LockFirstPerson
UserInputService.MouseIconEnabled = false

local PRIORIDAD = Enum.ContextActionPriority.High.Value

------------------------------------------------------------------------
-- Estado
------------------------------------------------------------------------

local humanoid, root, linVel
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local s = {} -- estado del movimiento; se reinicia en cada aparición

local function resetState()
	s.wasGrounded = false
	s.lastGroundedAt = -math.huge
	s.lastJumpAt = -math.huge
	s.jumpBufferedAt = -math.huge
	s.lastJumpRequest = -math.huge
	s.airJumpsLeft = C.AIR_JUMPS
	s.lastAirVelY = 0

	s.dashCharges = C.DASH_CHARGES
	s.dashQueued = false
	s.dashing = false
	s.dashEndsAt = -math.huge
	s.dashDir = Vector3.zero
	s.dashExitSpeed = 0

	s.slideHeld = false
	s.sliding = false
	s.lastSlideBoostAt = -math.huge

	s.fovPunch = 0
	s.landDip = 0
	s.roll = 0
	s.speed = 0
end
resetState()

------------------------------------------------------------------------
-- Física
------------------------------------------------------------------------

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Acelera hacia wishDir sin pasar de wishSpeed en esa dirección (estilo Quake).
-- La velocidad que ya llevas en otras direcciones no se toca: por eso existe el bunny-hop.
local function accelerate(vel, wishDir, wishSpeed, accel, dt)
	if wishDir.Magnitude < 0.01 then
		return vel
	end
	local add = wishSpeed - vel:Dot(wishDir)
	if add <= 0 then
		return vel
	end
	return vel + wishDir * math.min(accel * C.WALK_SPEED * dt, add)
end

local function applyFriction(vel, amount, dt)
	local speed = vel.Magnitude
	if speed < 0.1 then
		return Vector3.zero
	end
	local drop = math.max(speed, C.STOP_SPEED) * amount * dt
	return vel * (math.max(speed - drop, 0) / speed)
end

-- Gira el impulso hacia donde pulsas conservando la velocidad (solo si no vas hacia atrás).
local function steer(vel, wishDir, rate, dt)
	local speed = vel.Magnitude
	if speed < 0.1 or wishDir.Magnitude < 0.01 then
		return vel
	end
	local dir = vel / speed
	if dir:Dot(wishDir) <= 0 then
		return vel
	end
	local newDir = dir:Lerp(wishDir, math.clamp(rate * dt, 0, 1))
	if newDir.Magnitude < 0.001 then
		return vel
	end
	return newDir.Unit * speed
end

local function groundHit()
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 0.4
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
end

local function wishDirection()
	local move = controls:GetMoveVector() -- x = derecha, z = -adelante (teclado, mando y táctil)
	if move.Magnitude < 0.01 then
		return Vector3.zero
	end
	local look = flat(camera.CFrame.LookVector)
	local right = flat(camera.CFrame.RightVector)
	if look.Magnitude < 0.01 then
		return Vector3.zero
	end
	local dir = look.Unit * -move.Z + right.Unit * move.X
	return dir.Magnitude > 0.01 and dir.Unit or Vector3.zero
end

local function step(dt)
	if not (root and humanoid and linVel) or humanoid.Health <= 0 then
		return
	end
	dt = math.min(dt, 1 / 20)
	local now = os.clock()

	local vel = root.AssemblyLinearVelocity
	local horiz = flat(vel)
	local vy = vel.Y
	local setY = false

	-- Suelo
	local hit = groundHit()
	local grounded = hit ~= nil and (now - s.lastJumpAt) > 0.1 and vy <= 2
	if grounded then
		if not s.wasGrounded then
			s.landDip = math.clamp(-s.lastAirVelY / 120, 0, 1) * C.LAND_DIP_MAX
		end
		s.lastGroundedAt = now
		s.airJumpsLeft = C.AIR_JUMPS
	else
		s.lastAirVelY = vy
	end
	s.wasGrounded = grounded

	local wish = wishDirection()

	-- Recarga de dashes
	if s.dashCharges < C.DASH_CHARGES then
		s.dashCharges = math.min(C.DASH_CHARGES, s.dashCharges + dt / C.DASH_RECHARGE)
	end

	-- Salto (con coyote time, buffer y doble salto)
	if now - s.jumpBufferedAt <= C.JUMP_BUFFER then
		local jumped = false
		if grounded or now - s.lastGroundedAt <= C.COYOTE_TIME then
			vy = C.JUMP_VELOCITY
			jumped = true
		elseif s.airJumpsLeft > 0 then
			s.airJumpsLeft -= 1
			vy = C.AIR_JUMP_VELOCITY
			-- el doble salto te deja cambiar de dirección sin perder velocidad
			if wish.Magnitude > 0 then
				horiz = wish * math.max(horiz.Magnitude, C.WALK_SPEED)
			end
			jumped = true
		end
		if jumped then
			setY = true
			s.jumpBufferedAt = -math.huge
			s.lastJumpAt = now
			s.lastGroundedAt = -math.huge
			grounded = false -- saltar en el mismo frame que aterrizas = sin rozamiento (bunny-hop)
			s.sliding = false
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end

	-- Dash
	if s.dashQueued then
		s.dashQueued = false
		if s.dashCharges >= 1 and now - s.dashEndsAt >= C.DASH_COOLDOWN and not s.dashing then
			s.dashCharges -= 1
			local look = flat(camera.CFrame.LookVector)
			s.dashDir = wish.Magnitude > 0 and wish or (look.Magnitude > 0.01 and look.Unit or Vector3.zAxis)
			s.dashExitSpeed = math.max(C.DASH_EXIT_SPEED, horiz.Magnitude)
			s.dashEndsAt = now + C.DASH_DURATION
			s.dashing = true
			s.sliding = false
			s.fovPunch = C.FOV_DASH_PUNCH
		end
	end

	if s.dashing then
		if now < s.dashEndsAt then
			horiz = s.dashDir * C.DASH_SPEED
			vy = 0
			setY = true
		else
			s.dashing = false
			horiz = s.dashDir * s.dashExitSpeed
		end
	elseif grounded then
		-- Slide: al pulsar con velocidad suficiente
		if s.slideHeld and not s.sliding and horiz.Magnitude >= C.SLIDE_MIN_START then
			s.sliding = true
			if now - s.lastSlideBoostAt >= C.SLIDE_BOOST_COOLDOWN then
				s.lastSlideBoostAt = now
				horiz += horiz.Unit * C.SLIDE_BOOST
			end
		end

		if s.sliding and (not s.slideHeld or horiz.Magnitude < C.SLIDE_MIN_SPEED) then
			s.sliding = false
		end

		if s.sliding then
			horiz = applyFriction(horiz, C.SLIDE_FRICTION, dt)
			-- en cuesta abajo el slide acelera
			local n = hit.Normal
			local g = Vector3.new(0, -C.GRAVITY, 0)
			horiz += flat(g - n * g:Dot(n)) * dt
			horiz = steer(horiz, wish, C.SLIDE_STEER, dt)
		else
			horiz = applyFriction(horiz, C.GROUND_FRICTION, dt)
			horiz = accelerate(horiz, wish, C.WALK_SPEED, C.GROUND_ACCEL, dt)
		end
	else
		horiz = accelerate(horiz, wish, C.AIR_WISH_CAP, C.AIR_ACCEL, dt)
		horiz = steer(horiz, wish, C.AIR_STEER, dt)
	end

	if horiz.Magnitude > C.MAX_SPEED then
		horiz = horiz.Unit * C.MAX_SPEED
	end

	linVel.VectorVelocity = horiz
	if setY then
		root.AssemblyLinearVelocity = Vector3.new(horiz.X, vy, horiz.Z)
	end
	s.speed = horiz.Magnitude

	-- Estado público para otros scripts (brazos en primera persona)
	player:SetAttribute("MovVelocidad", s.speed)
	player:SetAttribute("MovSlide", s.sliding)
	player:SetAttribute("MovDash", s.dashing)
	player:SetAttribute("MovSuelo", grounded)
	player:SetAttribute("MovUltimoSalto", s.lastJumpAt)
end

------------------------------------------------------------------------
-- Cámara: FOV por velocidad, inclinación lateral, bajada al deslizar y al aterrizar
------------------------------------------------------------------------

local function cameraStep(dt)
	if not humanoid then
		return
	end
	local speedT = math.clamp((s.speed - C.WALK_SPEED) / (C.FOV_SPEED_FOR_MAX - C.WALK_SPEED), 0, 1)
	s.fovPunch = s.fovPunch + (0 - s.fovPunch) * math.min(dt * 6, 1)
	local targetFov = C.FOV_BASE + speedT * C.FOV_MAX_EXTRA + s.fovPunch
	camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(dt * 8, 1)

	local targetRoll = -controls:GetMoveVector().X * C.ROLL_MAX
	if s.sliding then
		targetRoll += 2
	end
	s.roll += (targetRoll - s.roll) * math.min(dt * 10, 1)
	camera.CFrame *= CFrame.Angles(0, 0, math.rad(s.roll))

	s.landDip += (0 - s.landDip) * math.min(dt * 10, 1)
	local drop = (s.sliding and C.SLIDE_CAMERA_DROP or 0) + s.landDip
	local current = humanoid.CameraOffset.Y
	humanoid.CameraOffset = Vector3.new(0, current + (-drop - current) * math.min(dt * 14, 1), 0)
end

------------------------------------------------------------------------
-- HUD de pruebas: velocidad y cargas de dash
------------------------------------------------------------------------

local hud = Instance.new("ScreenGui")
hud.Name = "HUDMovimiento"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.Parent = player:WaitForChild("PlayerGui")

local speedLabel = Instance.new("TextLabel")
speedLabel.AnchorPoint = Vector2.new(0.5, 1)
speedLabel.Position = UDim2.new(0.5, 0, 1, -40)
speedLabel.Size = UDim2.fromOffset(200, 30)
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextSize = 24
speedLabel.TextColor3 = Color3.new(1, 1, 1)
speedLabel.TextStrokeTransparency = 0.5
speedLabel.Parent = hud

local crosshair = Instance.new("Frame")
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(4, 4)
crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
crosshair.BorderSizePixel = 0
crosshair.Parent = hud

local bars = {}
for i = 1, C.DASH_CHARGES do
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, (i - (C.DASH_CHARGES + 1) / 2) * 48, 1, -20)
	back.Size = UDim2.fromOffset(40, 8)
	back.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	back.BorderSizePixel = 0
	back.Parent = hud
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 200, 255)
	fill.BorderSizePixel = 0
	fill.Parent = back
	bars[i] = fill
end

local function hudStep()
	speedLabel.Text = string.format("%d", math.floor(s.speed + 0.5))
	for i, fill in bars do
		fill.Size = UDim2.fromScale(math.clamp(s.dashCharges - (i - 1), 0, 1), 1)
	end
end

------------------------------------------------------------------------
-- Controles (teclado, mando y botones táctiles)
------------------------------------------------------------------------

-- JumpRequest sirve para teclado, mando y el botón táctil de Roblox.
-- Mientras se mantiene pulsado se repite; solo cuenta una pulsación nueva.
UserInputService.JumpRequest:Connect(function()
	local now = os.clock()
	if now - s.lastJumpRequest > 0.1 then
		s.jumpBufferedAt = now
	end
	s.lastJumpRequest = now
end)

ContextActionService:BindActionAtPriority("Dash", function(_, state)
	if state == Enum.UserInputState.Begin then
		s.dashQueued = true
	end
	return Enum.ContextActionResult.Sink
end, true, PRIORIDAD, Enum.KeyCode.LeftShift, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonX)
ContextActionService:SetTitle("Dash", "Dash")

ContextActionService:BindActionAtPriority("Slide", function(_, state)
	s.slideHeld = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end, true, PRIORIDAD, Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonB)
ContextActionService:SetTitle("Slide", "Slide")
ContextActionService:SetPosition("Slide", UDim2.new(1, -170, 1, -80))

------------------------------------------------------------------------
-- Personaje
------------------------------------------------------------------------

local function onCharacter(char)
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")
	rayParams.FilterDescendantsInstances = { char }
	resetState()

	-- El salto lo hacemos nosotros (doble salto, coyote, buffer)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

	local att = Instance.new("Attachment")
	att.Name = "MovimientoAttachment"
	att.Parent = root

	linVel = Instance.new("LinearVelocity")
	linVel.Name = "MovimientoVelocity"
	linVel.Attachment0 = att
	linVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linVel.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	linVel.MaxAxesForce = Vector3.new(1e6, 0, 1e6) -- en Y manda la gravedad
	linVel.VectorVelocity = Vector3.zero
	linVel.Parent = root

	humanoid.Died:Connect(function()
		if linVel then
			linVel.Enabled = false
		end
		linVel = nil
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

RunService.PreSimulation:Connect(step)
RunService:BindToRenderStep("MovimientoCamara", Enum.RenderPriority.Camera.Value + 1, function(dt)
	cameraStep(dt)
	hudStep()
end)
