-- Brazos en primera persona: los brazos de verdad de tu avatar de Roblox
-- (con tu piel, tu camiseta y tus accesorios de brazo).
--
-- En primera persona Roblox esconde el cuerpo. Aquí volvemos visibles solo los brazos
-- y giramos los hombros para que apunten hacia delante, siguiendo la cámara.
-- Reaccionan al movimiento (lee el estado que publica Movimiento.client.lua):
-- balanceo al correr, retraso al girar, slide, dash, salto, aterrizaje, pared y manotazo.
-- Funciona con avatares R15 y R6.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local brazos = {} -- { lado, hombro (Motor6D), codo (Motor6D o nil), partes = {BasePart} }

local estado = {
	tiempo = 0,
	bob = 0,
	sway = Vector2.zero,
	slide = 0,
	dash = 0,
	aire = 0,
	aterrizaje = 0,
	estabaEnSuelo = true,
	ultimoSalto = -math.huge,
	salto = 0,
	pared = 0,
}

local NOMBRES = {
	R15 = {
		[1] = { hombro = "RightShoulder", codo = "RightElbow", partes = { "RightUpperArm", "RightLowerArm", "RightHand" } },
		[-1] = { hombro = "LeftShoulder", codo = "LeftElbow", partes = { "LeftUpperArm", "LeftLowerArm", "LeftHand" } },
	},
	R6 = {
		[1] = { hombro = "Right Shoulder", partes = { "Right Arm" } },
		[-1] = { hombro = "Left Shoulder", partes = { "Left Arm" } },
	},
}

local function buscarMotor(char, nombre)
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == nombre then
			return d
		end
	end
	return nil
end

local function prepararPersonaje(char)
	brazos = {}
	local hum = char:WaitForChild("Humanoid")
	local tipo = hum.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6"
	-- esperar a que el avatar termine de cargar
	for _ = 1, 50 do
		if buscarMotor(char, NOMBRES[tipo][1].hombro) then
			break
		end
		task.wait(0.1)
	end
	for _, lado in { 1, -1 } do
		local n = NOMBRES[tipo][lado]
		local hombro = buscarMotor(char, n.hombro)
		if hombro then
			local partes = {}
			for _, nombre in n.partes do
				local p = char:FindFirstChild(nombre)
				if p then
					table.insert(partes, p)
				end
			end
			table.insert(brazos, {
				lado = lado,
				hombro = hombro,
				codo = n.codo and buscarMotor(char, n.codo) or nil,
				partes = partes,
			})
		end
	end
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Gira el hombro para que el brazo (que cuelga hacia -Y) apunte en "direccion" (mundo).
local function apuntarHombro(motor, direccion, giroMuneca)
	local p0 = motor.Part0
	if not p0 then
		return
	end
	local junta = p0.CFrame * motor.C0 -- marco del hombro en el mundo, sin animación
	local abajo = -direccion.Unit -- el +Y del brazo debe mirar al lado contrario
	local lateral = camera.CFrame.RightVector
	lateral = (lateral - abajo * lateral:Dot(abajo))
	if lateral.Magnitude < 0.01 then
		return
	end
	lateral = lateral.Unit
	local atras = lateral:Cross(abajo)
	local objetivo = CFrame.fromMatrix(Vector3.zero, lateral, abajo, atras) * CFrame.Angles(0, giroMuneca or 0, 0)
	local rotJunta = junta - junta.Position
	motor.Transform = rotJunta:Inverse() * objetivo
end

local function actualizar(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local cabeza = char and char:FindFirstChild("Head")
	if not (hum and hum.Health > 0 and cabeza and #brazos > 0) then
		return
	end
	local primera = (camera.CFrame.Position - cabeza.Position).Magnitude < 2
	if not primera then
		return
	end

	local vel = player:GetAttribute("MovVelocidad") or 0
	local enSlide = player:GetAttribute("MovSlide") == true
	local enDash = player:GetAttribute("MovDash") == true
	local enSuelo = player:GetAttribute("MovSuelo") ~= false
	local ultimoSalto = player:GetAttribute("MovUltimoSalto") or -math.huge
	local pared = player:GetAttribute("MovPared") or 0

	local k = math.min(dt * 12, 1)
	estado.tiempo += dt

	local andar = (enSuelo and not enSlide) and math.clamp(vel / 16, 0, 1) or 0
	estado.bob += dt * (5 + vel * 0.3) * (andar > 0.05 and 1 or 0)

	local delta = UserInputService:GetMouseDelta()
	local objetivoSway = Vector2.new(math.clamp(-delta.X * 0.006, -0.25, 0.25), math.clamp(delta.Y * 0.006, -0.25, 0.25))
	estado.sway = estado.sway:Lerp(objetivoSway, math.min(dt * 8, 1))

	estado.slide = lerp(estado.slide, enSlide and 1 or 0, k)
	estado.dash = lerp(estado.dash, enDash and 1 or 0, math.min(dt * 18, 1))
	estado.aire = lerp(estado.aire, enSuelo and 0 or 1, math.min(dt * 6, 1))
	estado.pared = lerp(estado.pared, pared, k)

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

	local tm = os.clock() - (player:GetAttribute("MovManotazo") or -math.huge)
	local golpe = 0
	if tm < 0.08 then
		golpe = tm / 0.08
	elseif tm < 0.32 then
		golpe = (1 - (tm - 0.08) / 0.24) ^ 2
	end

	local cam = camera.CFrame
	for _, b in brazos do
		local l = b.lado
		local fase = estado.bob + (l == 1 and math.pi or 0)

		-- Dirección del brazo en coordenadas de la cámara (x derecha, y arriba, z atrás)
		local d = Vector3.new(0.12 * l, -0.42, -1)
		d += Vector3.new(math.cos(fase) * 0.06, math.abs(math.sin(fase)) * -0.08, 0) * andar
		d += Vector3.new(estado.sway.X, estado.sway.Y, 0)
		d += Vector3.new(0.5 * l, -0.2, 0.3) * estado.slide -- se abren para equilibrarse
		d += Vector3.new(0.15 * l, -0.5, 0.6) * estado.dash -- hacia atrás
		d += Vector3.new(0.1 * l, 0.25, 0) * estado.aire + Vector3.new(0, 0.35, 0) * estado.salto
		d += Vector3.new(0, -0.3, 0) * estado.aterrizaje
		-- en la pared, la mano de ese lado la toca
		if (estado.pared > 0.1 and l == 1) or (estado.pared < -0.1 and l == -1) then
			d += Vector3.new(0.9 * l, 0.45, 0.2) * math.abs(estado.pared)
		end
		-- manotazo con la derecha, cruzando hacia el centro
		if l == 1 then
			d += Vector3.new(-0.35, 0.5, -0.4) * golpe
		else
			d += Vector3.new(0, -0.2, 0.3) * golpe
		end

		local mundo = cam:VectorToWorldSpace(d)
		apuntarHombro(b.hombro, mundo, l == 1 and golpe * math.rad(70) or 0)
		if b.codo then
			-- codo un poco doblado; se estira al dar el manotazo
			local doblez = math.rad(lerp(25, 5, golpe))
			b.codo.Transform = CFrame.Angles(doblez, 0, 0)
		end
		for _, p in b.partes do
			p.LocalTransparencyModifier = 0
		end
		-- accesorios pegados a los brazos (relojes, mangas, etc.)
		for _, acc in char:GetChildren() do
			if acc:IsA("Accessory") then
				local h = acc:FindFirstChild("Handle")
				local w = h and h:FindFirstChildWhichIsA("Weld")
				if w and table.find(b.partes, w.Part1) then
					h.LocalTransparencyModifier = 0
				end
			end
		end
	end
end

player.CharacterAdded:Connect(prepararPersonaje)
if player.Character then
	task.spawn(prepararPersonaje, player.Character)
end

-- después de la cámara (que vuelve a esconder el cuerpo) y de las animaciones
RunService:BindToRenderStep("BrazosVista", Enum.RenderPriority.Camera.Value + 2, actualizar)
