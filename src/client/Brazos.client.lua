-- Brazos en primera persona (viewmodel), al estilo de los shooters de Roblox:
-- el antebrazo y la mano de TU avatar (copiados, con tu piel y tu camiseta) entran
-- desde la parte de abajo de la pantalla.
--
-- Cada brazo se coloca entre dos puntos relativos a la cámara: el CODO (fuera de la
-- pantalla, abajo) y la MANO. Según lo que hagas, la mano se mueve a otro sitio:
-- correr, slide, pared, barra, escalar, rodar, salto, aterrizaje y manotazo.
-- Funciona con avatares R15 (antebrazo + mano) y R6 (brazo entero).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local modelo
local brazos = {} -- [lado] = { antebrazo, mano (o nil en R6), mano = Vector3, codo = Vector3 }

local estado = {
	bob = 0,
	sway = Vector2.zero,
	ultimoSalto = -math.huge,
	salto = 0,
	aterrizaje = 0,
	estabaEnSuelo = true,
}

local function construir()
	if modelo then
		modelo:Destroy()
		modelo = nil
	end
	brazos = {}
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	-- Brazos de estilo Roblox clásico con TU color de piel y TU camiseta:
	-- con un Humanoid R6 dentro, Roblox pinta la camiseta en las piezas "Right Arm"/"Left Arm".
	-- (Las mallas de los avatares R15 tienen formas y orientaciones muy distintas y
	-- en primera persona quedaban deformes.)
	modelo = Instance.new("Model")
	modelo.Name = "BrazosVista"
	local h = Instance.new("Humanoid")
	h.RigType = Enum.HumanoidRigType.R6
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	h.RequiresNeck = false
	h.EvaluateStateMachine = false
	h.Parent = modelo
	local camiseta = char:FindFirstChildOfClass("Shirt")
	if camiseta then
		camiseta:Clone().Parent = modelo
	end

	-- color de piel: el de los brazos de verdad
	local function colorDe(lado)
		local nombre = lado == 1 and "Right" or "Left"
		local p = char:FindFirstChild(nombre .. "Hand") or char:FindFirstChild(nombre .. " Arm") or char:FindFirstChild(nombre .. "LowerArm")
		return p and p.Color or Color3.fromRGB(234, 184, 146)
	end

	for _, lado in { 1, -1 } do
		local p = Instance.new("Part")
		p.Name = lado == 1 and "Right Arm" or "Left Arm"
		p.Size = Vector3.new(1, 2, 1) * C.BRAZOS_ESCALA
		p.Color = colorDe(lado)
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = modelo
		brazos[lado] = {
			antebrazo = p,
			posMano = Vector3.new(C.BRAZOS_MANO.X * lado, C.BRAZOS_MANO.Y, C.BRAZOS_MANO.Z),
			posCodo = Vector3.new(C.BRAZOS_CODO.X * lado, C.BRAZOS_CODO.Y, C.BRAZOS_CODO.Z),
			giro = 0,
		}
	end
	-- sin camiseta: manga del color del torso
	if not camiseta then
		local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
		local bc = Instance.new("BodyColors")
		bc.RightArmColor3 = brazos[1].antebrazo.Color
		bc.LeftArmColor3 = brazos[-1].antebrazo.Color
		if torso then
			bc.TorsoColor3 = torso.Color
		end
		bc.Parent = modelo
	end
	modelo.Parent = camera
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Coloca una pieza entre a y b (en el mundo), con su -Y mirando de a hacia b.
-- "giro" rota la pieza sobre su eje (para poner la mano de canto en el manotazo).
local function entre(p, a, b, lateral, giro)
	local dir = b - a
	if dir.Magnitude < 0.01 then
		return
	end
	local abajo = -dir.Unit
	local derecha = lateral - abajo * lateral:Dot(abajo)
	derecha = derecha.Magnitude > 0.01 and derecha.Unit or abajo:Cross(Vector3.zAxis).Unit
	local atras = derecha:Cross(abajo)
	p.CFrame = CFrame.fromMatrix((a + b) / 2, derecha, abajo, atras) * CFrame.Angles(0, giro, 0)
end

local function actualizar(dt)
	if not modelo then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local cabeza = char and char:FindFirstChild("Head")
	local visible = hum and hum.Health > 0 and cabeza and (camera.CFrame.Position - cabeza.Position).Magnitude < 2.5
	modelo.Parent = visible and camera or nil
	if not visible then
		return
	end

	local now = os.clock()
	local vel = player:GetAttribute("MovVelocidad") or 0
	local enSlide = player:GetAttribute("MovSlide") == true
	local enSuelo = player:GetAttribute("MovSuelo") ~= false
	local pared = player:GetAttribute("MovPared") or 0
	local modo = player:GetAttribute("MovModo") or "normal"
	local barra = player:GetAttribute("MovBarra")
	local rodando = player:GetAttribute("MovRodando") == true
	local ultimoSalto = player:GetAttribute("MovUltimoSalto") or -math.huge

	local andar = (enSuelo and not enSlide and modo == "normal") and math.clamp(vel / C.WALK_SPEED, 0, 1.4) or 0
	estado.bob += dt * (5 + vel * 0.25) * (andar > 0.05 and 1 or 0)

	local delta = UserInputService:GetMouseDelta()
	estado.sway = estado.sway:Lerp(Vector2.new(math.clamp(-delta.X * 0.004, -0.15, 0.15), math.clamp(delta.Y * 0.004, -0.15, 0.15)), math.min(dt * 8, 1))

	if ultimoSalto ~= estado.ultimoSalto then
		estado.ultimoSalto = ultimoSalto
		estado.salto = 1
	end
	estado.salto = lerp(estado.salto, 0, math.min(dt * 5, 1))
	if enSuelo and not estado.estabaEnSuelo then
		estado.aterrizaje = 1
	end
	estado.estabaEnSuelo = enSuelo
	estado.aterrizaje = lerp(estado.aterrizaje, 0, math.min(dt * 9, 1))

	local tm = now - (player:GetAttribute("MovManotazo") or -math.huge)
	local golpe = 0
	if tm < 0.07 then
		golpe = tm / 0.07
	elseif tm < 0.3 then
		golpe = (1 - (tm - 0.07) / 0.23) ^ 2
	end

	local cam = camera.CFrame
	for lado, b in brazos do
		local l = lado
		local reposo = Vector3.new(C.BRAZOS_MANO.X * l, C.BRAZOS_MANO.Y, C.BRAZOS_MANO.Z)
		local codoReposo = Vector3.new(C.BRAZOS_CODO.X * l, C.BRAZOS_CODO.Y, C.BRAZOS_CODO.Z)
		local mano, codo, giro = reposo, codoReposo, 0
		local rapidez = 14

		if modo == "barra" and typeof(barra) == "Vector3" then
			-- manos arriba agarrando la barra
			local agarre = cam:PointToObjectSpace(barra + cam.RightVector * 0.8 * l)
			mano = agarre
			codo = Vector3.new(0.9 * l, -0.6, -0.2)
			rapidez = 22
		elseif modo == "escalar" then
			-- manos delante y abajo, apoyadas en el borde
			mano = Vector3.new(0.6 * l, -0.5, -1.9)
			codo = Vector3.new(1.0 * l, -1.2, -0.9)
			rapidez = 24
		elseif rodando then
			mano = Vector3.new(0.4 * l, -1.6, -1.0)
			rapidez = 20
		else
			-- correr: las manos van y vienen
			local fase = estado.bob + (l == 1 and math.pi or 0)
			mano += Vector3.new(0, math.abs(math.sin(fase)) * -0.06, math.sin(fase) * 0.25) * andar
			mano += Vector3.new(estado.sway.X, estado.sway.Y, 0)
			if enSlide then
				mano = Vector3.new(1.4 * l, -0.7, -1.2) -- abiertas para equilibrarse
			end
			if not enSuelo then
				mano += Vector3.new(0.1 * l, 0.15, 0)
			end
			mano += Vector3.new(0, 0.2, 0) * estado.salto
			mano += Vector3.new(0, -0.25, 0) * estado.aterrizaje
			-- pared: la mano de ese lado se apoya en ella
			if (pared > 0 and l == 1) or (pared < 0 and l == -1) then
				mano = Vector3.new(1.6 * l, -0.1, -1.4)
				codo = Vector3.new(1.3 * l, -1.4, -0.3)
			end
			-- manotazo: la derecha cruza al centro con la palma abierta
			if l == 1 and golpe > 0 then
				mano = mano:Lerp(Vector3.new(0.1, -0.35, -2.3), golpe)
				giro = golpe * math.rad(80)
				rapidez = 60
			elseif l == -1 then
				mano += Vector3.new(0, -0.2, 0.2) * golpe
			end
		end

		local k = math.min(dt * rapidez, 1)
		b.posMano = b.posMano:Lerp(mano, k)
		b.posCodo = b.posCodo:Lerp(codo, k)
		b.giro = lerp(b.giro, giro, k)

		local pMano = cam:PointToWorldSpace(b.posMano)
		local pCodo = cam:PointToWorldSpace(b.posCodo)
		local lateral = cam.RightVector
		entre(b.antebrazo, pCodo, pMano, lateral, b.giro)
	end
end

local function alAparecer(char)
	char:WaitForChild("Humanoid")
	if not player:HasAppearanceLoaded() then
		player.CharacterAppearanceLoaded:Wait()
	end
	task.wait(0.1)
	if player.Character == char then
		construir()
	end
end

player.CharacterAdded:Connect(alAparecer)
if player.Character then
	task.spawn(alAparecer, player.Character)
end

RunService:BindToRenderStep("BrazosVista", Enum.RenderPriority.Camera.Value + 2, actualizar)
