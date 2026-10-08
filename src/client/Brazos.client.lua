-- Brazos en primera persona (viewmodel).
--
-- Se hace una COPIA de los brazos de tu avatar (con tu piel, tu camiseta y sus mallas)
-- y se pega a la cámara. Es como lo hacen los shooters de Roblox: no depende del
-- cuerpo de verdad, que en primera persona Roblox esconde.
--
-- Cada brazo es una cadena hombro → codo → mano que apunta hacia donde toque según lo
-- que estés haciendo (lo publica Movimiento.client.lua en atributos Mov*):
-- correr, slide, pared, barra, escalar, rodar, salto, aterrizaje y manotazo.
-- Funciona con avatares R15 y R6.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local modelo
local brazos = {} -- [lado] = { piezas = {Part...}, largos = {number...}, dir = Vector3, codo = number }

local estado = {
	bob = 0,
	sway = Vector2.zero,
	ultimoSalto = -math.huge,
	salto = 0,
	aterrizaje = 0,
	estabaEnSuelo = true,
}

local PIEZAS = {
	R15 = { [1] = { "RightUpperArm", "RightLowerArm", "RightHand" }, [-1] = { "LeftUpperArm", "LeftLowerArm", "LeftHand" } },
	R6 = { [1] = { "Right Arm" }, [-1] = { "Left Arm" } },
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
	local tipo = hum.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6"

	modelo = Instance.new("Model")
	modelo.Name = "BrazosVista"
	-- con un Humanoid dentro, Roblox pinta la camiseta y los colores del cuerpo
	local h = Instance.new("Humanoid")
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	h.RequiresNeck = false
	h.BreakJointsOnDeath = false
	h.EvaluateStateMachine = false
	h.Parent = modelo
	for _, nombre in { "Shirt", "BodyColors" } do
		local v = char:FindFirstChildOfClass(nombre)
		if v then
			v:Clone().Parent = modelo
		end
	end

	for _, lado in { 1, -1 } do
		local piezas, largos = {}, {}
		for _, nombre in PIEZAS[tipo][lado] do
			local original = char:FindFirstChild(nombre)
			if original then
				local p = original:Clone()
				-- quitar uniones y extras; se quedan la malla y las texturas
				for _, hijo in p:GetChildren() do
					if not (hijo:IsA("DataModelMesh") or hijo:IsA("Decal") or hijo:IsA("SurfaceAppearance")) then
						hijo:Destroy()
					end
				end
				p.Size = original.Size * C.BRAZOS_ESCALA
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Massless = true
				p.LocalTransparencyModifier = 0
				p.Transparency = 0
				p.Parent = modelo
				table.insert(piezas, p)
				table.insert(largos, p.Size.Y)
			end
		end
		if #piezas > 0 then
			brazos[lado] = { piezas = piezas, largos = largos, dir = Vector3.new(0, -0.4, -1).Unit, codo = 0.4 }
		end
	end
	modelo.Parent = camera
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- vector "lateral" hecho perpendicular a "abajo"
local function unitLateral(lateral, abajo)
	local d = lateral - abajo * lateral:Dot(abajo)
	if d.Magnitude < 0.01 then
		d = abajo:Cross(Vector3.zAxis)
	end
	return d.Unit
end

-- coloca una pieza para que vaya de "desde" en dirección "dir" (su -Y apunta en dir)
local function colocar(p, desde, dir, largo, lateral)
	local abajo = -dir
	local derecha = unitLateral(lateral, abajo)
	local atras = derecha:Cross(abajo)
	p.CFrame = CFrame.fromMatrix(desde + dir * (largo / 2), derecha, abajo, atras)
	return desde + dir * largo
end

-- gira "v" un ángulo alrededor de "eje"
local function girar(v, eje, ang)
	return CFrame.fromAxisAngle(eje, ang):VectorToWorldSpace(v)
end

local function actualizar(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local cabeza = char and char:FindFirstChild("Head")
	local visible = hum and hum.Health > 0 and cabeza and (camera.CFrame.Position - cabeza.Position).Magnitude < 2.5
	if not modelo then
		return
	end
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

	-- balanceo al correr
	local andar = (enSuelo and not enSlide and modo == "normal") and math.clamp(vel / 20, 0, 1.3) or 0
	estado.bob += dt * (4 + vel * 0.28) * (andar > 0.05 and 1 or 0)

	-- retraso al girar la vista
	local delta = UserInputService:GetMouseDelta()
	estado.sway = estado.sway:Lerp(Vector2.new(math.clamp(-delta.X * 0.005, -0.2, 0.2), math.clamp(delta.Y * 0.005, -0.2, 0.2)), math.min(dt * 8, 1))

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

	-- manotazo: 0 → 1 → 0 en ~0,3 s
	local tm = now - (player:GetAttribute("MovManotazo") or -math.huge)
	local golpe = 0
	if tm < 0.08 then
		golpe = tm / 0.08
	elseif tm < 0.32 then
		golpe = (1 - (tm - 0.08) / 0.24) ^ 2
	end

	local cam = camera.CFrame
	for lado, b in brazos do
		local l = lado
		local hombro = cam:PointToWorldSpace(Vector3.new(C.BRAZOS_HOMBRO.X * l, C.BRAZOS_HOMBRO.Y, C.BRAZOS_HOMBRO.Z))
		local objetivo -- dirección en el mundo
		local codo = 0.45 -- radianes de doblez

		if modo == "barra" and typeof(barra) == "Vector3" then
			-- las dos manos a la barra, brazos estirados
			local agarre = barra + cam.RightVector * 0.7 * l
			objetivo = (agarre - hombro).Unit
			codo = 0.05
		elseif modo == "escalar" then
			-- manos hacia delante y abajo, empujando el borde
			objetivo = cam:VectorToWorldSpace(Vector3.new(0.25 * l, -0.75, -1).Unit)
			codo = 0.15
		elseif rodando then
			objetivo = cam:VectorToWorldSpace(Vector3.new(0.3 * l, -1, 0.3).Unit)
			codo = 1.6
		else
			local fase = estado.bob + (l == 1 and math.pi or 0)
			local d = Vector3.new(0.18 * l, -0.42, -1)
			d += Vector3.new(math.cos(fase) * 0.08 * l, 0, math.sin(fase) * 0.22) * andar -- brazos que van y vienen al correr
			d += Vector3.new(estado.sway.X, estado.sway.Y, 0)
			if enSlide then
				d += Vector3.new(0.7 * l, -0.1, 0.4) -- se abren para equilibrarse
				codo = 0.25
			end
			if not enSuelo then
				d += Vector3.new(0.15 * l, 0.3, 0)
			end
			d += Vector3.new(0, 0.4, 0) * estado.salto
			d += Vector3.new(0, -0.35, 0) * estado.aterrizaje
			-- corriendo por la pared, la mano de ese lado la toca
			if (pared > 0 and l == 1) or (pared < 0 and l == -1) then
				d = Vector3.new(1.1 * l, 0.35, -0.6)
				codo = 0.2
			end
			-- manotazo con la derecha
			if l == 1 and golpe > 0 then
				d = d:Lerp(Vector3.new(-0.15, -0.05, -1), golpe)
				codo = lerp(codo, 0.05, golpe)
			elseif l == -1 then
				d += Vector3.new(0, -0.15, 0.2) * golpe
			end
			objetivo = cam:VectorToWorldSpace(d.Unit)
		end

		-- suavizado (el manotazo va rápido)
		local rapidez = golpe > 0.05 and 40 or (modo == "barra" and 20 or 14)
		b.dir = b.dir:Lerp(objetivo, math.min(dt * rapidez, 1))
		if b.dir.Magnitude < 0.01 then
			b.dir = objetivo
		end
		b.dir = b.dir.Unit
		b.codo = lerp(b.codo, codo, math.min(dt * rapidez, 1))

		-- cadena hombro → codo → mano
		local lateral = cam.RightVector
		local ejeCodo = unitLateral(lateral, -b.dir)
		local punto = hombro
		for i, p in b.piezas do
			local dir = b.dir
			if i >= 2 then
				-- el antebrazo y la mano se doblan hacia arriba/dentro
				dir = girar(b.dir, ejeCodo, b.codo)
			end
			punto = colocar(p, punto, dir, b.largos[i], lateral)
		end
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
