-- Manos en primera persona: no se ven al correr; aparecen desde abajo solo cuando
-- hacen algo (agarrar una barra, escalar, saltar una valla, trepar, tocar la pared o
-- dar un manotazo). Tienen peso y codos.
--
-- Cada brazo tiene dos piezas: brazo (hombro → codo) y antebrazo con la mano
-- (codo → mano). El codo se calcula solo (cinemática inversa de dos huesos), así al
-- correr los brazos van doblados de forma natural.
-- En el salto de valla de parkour también se ven tus piernas pasando en horizontal.
--
-- Brazos de estilo Roblox clásico con TU color de piel y TU camiseta (con un Humanoid
-- R6 dentro, Roblox pinta la camiseta en las piezas "Right Arm"/"Left Arm").
--
-- Cada mano va colgada de un MUELLE: no se teletransporta a su sitio, sino que lo
-- persigue con inercia y un pequeño rebote. Así los brazos pesan.
--
-- Poses (lee el estado que publica Movimiento.client.lua):
--   · Correr: los brazos bombean adelante y atrás al ritmo de los pasos, alternados.
--   · Saltar / caer: suben; aterrizar: bajan de golpe.
--   · Slide: se abren para equilibrarse.
--   · Saltar valla: una mano se apoya en el obstáculo (punto fijo del mundo).
--   · Escalar: las dos manos agarran el borde y empujan hacia abajo mientras subes.
--   · Trepar: las manos van subiendo por la pared, alternadas.
--   · Pared: la mano de ese lado roza la pared.
--   · Barra: las dos manos en la barra.
--   · Rodar: se recogen.
--   · Manotazo: la derecha cruza al centro con la palma abierta.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local modelo
local brazos = {} -- [lado] = { brazo, antebrazo, pos (cámara), vel, giro }
local piernas = {} -- [lado] = Part (solo visibles en el salto de valla rápido)

local estado = {
	sway = Vector2.zero,
	ultimoSalto = -math.huge,
	salto = 0,
	aterrizaje = 0,
	estabaEnSuelo = true,
	correr = 0,
}

------------------------------------------------------------------------
-- Construcción
------------------------------------------------------------------------

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

	local function colorDe(lado)
		local nombre = lado == 1 and "Right" or "Left"
		local p = char:FindFirstChild(nombre .. "Hand") or char:FindFirstChild(nombre .. " Arm") or char:FindFirstChild(nombre .. "LowerArm")
		return p and p.Color or Color3.fromRGB(234, 184, 146)
	end

	local pantalon = char:FindFirstChildOfClass("Pants")
	if pantalon then
		pantalon:Clone().Parent = modelo
	end

	local function pieza(nombre, tam, color)
		local p = Instance.new("Part")
		p.Name = nombre
		p.Size = tam
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = modelo
		return p
	end

	-- color de la manga: el del torso (si no hay camiseta, la piel)
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	local e = C.BRAZOS_ESCALA
	for _, lado in { 1, -1 } do
		local piel = colorDe(lado)
		-- antebrazo con la mano: pieza R6 "Right/Left Arm" (lleva la parte baja de la camiseta y la mano)
		local antebrazo = pieza(lado == 1 and "Right Arm" or "Left Arm", Vector3.new(0.9 * e, C.BRAZOS_LARGO_ANTEBRAZO, 0.9 * e), piel)
		-- brazo (de hombro a codo)
		local manga = camiseta and torso and torso.Color or piel
		local brazo = pieza("Brazo", Vector3.new(0.95 * e, C.BRAZOS_LARGO_BRAZO, 0.95 * e), manga)
		local reposo = Vector3.new(C.BRAZOS_MANO.X * lado, C.BRAZOS_MANO.Y, C.BRAZOS_MANO.Z)
		brazos[lado] = { brazo = brazo, antebrazo = antebrazo, parte = antebrazo, pos = reposo + Vector3.new(0, -1.5, 0.5), vel = Vector3.zero, giro = 0 }

		local pierna = pieza(lado == 1 and "Right Leg" or "Left Leg", Vector3.new(1, 2, 1) * 0.9, (char:FindFirstChild(lado == 1 and "RightUpperLeg" or "LeftUpperLeg") or char:FindFirstChild(lado == 1 and "Right Leg" or "Left Leg") or antebrazo).Color)
		pierna.Transparency = 1
		piernas[lado] = pierna
	end
	if not camiseta then
		local bc = Instance.new("BodyColors")
		bc.RightArmColor3 = brazos[1].antebrazo.Color
		bc.LeftArmColor3 = brazos[-1].antebrazo.Color
		bc.RightLegColor3 = piernas[1].Color
		bc.LeftLegColor3 = piernas[-1].Color
		if torso then
			bc.TorsoColor3 = torso.Color
		end
		bc.Parent = modelo
	end
	modelo.Parent = camera
end

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- muelle amortiguado (semi-implícito): mueve pos hacia objetivo con inercia
local function muelle(b, objetivo, rigidez, dt)
	local k = rigidez
	local c = 2 * math.sqrt(k) * C.BRAZOS_AMORTIGUA
	local paso = math.min(dt, 1 / 30)
	local fuerza = (objetivo - b.pos) * k - b.vel * c
	b.vel += fuerza * paso
	b.pos += b.vel * paso
end

-- coloca una pieza entre a y b (su -Y apunta de a hacia b)
local function entre(p, a, b, lateral, giro)
	local dir = b - a
	if dir.Magnitude < 0.01 then
		return
	end
	local abajo = -dir.Unit
	local derecha = lateral - abajo * lateral:Dot(abajo)
	derecha = derecha.Magnitude > 0.01 and derecha.Unit or abajo:Cross(Vector3.zAxis).Unit
	local atras = derecha:Cross(abajo)
	p.CFrame = CFrame.fromMatrix((a + b) / 2, derecha, abajo, atras) * CFrame.Angles(0, giro or 0, 0)
end

-- Cinemática inversa de dos huesos: dado el hombro, la mano y hacia dónde debe
-- apuntar el codo ("polo"), devuelve dónde queda el codo.
local function codoIK(hombro, mano, largoA, largoB, polo)
	local d = mano - hombro
	local dist = math.clamp(d.Magnitude, 0.05, largoA + largoB - 0.01)
	local dir = d.Unit
	-- distancia del hombro al punto del eje que queda bajo el codo
	local x = (largoA * largoA - largoB * largoB + dist * dist) / (2 * dist)
	local h = math.sqrt(math.max(largoA * largoA - x * x, 0))
	local perp = polo - dir * polo:Dot(dir)
	perp = perp.Magnitude > 0.01 and perp.Unit or dir:Cross(Vector3.yAxis).Unit
	return hombro + dir * x + perp * h, hombro + dir * dist
end

------------------------------------------------------------------------
-- Cada frame
------------------------------------------------------------------------

local function actualizar(dt)
	if not modelo then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local cabeza = char and char:FindFirstChild("Head")
	local visible = hum and hum.Health > 0 and cabeza and (camera.CFrame.Position - cabeza.Position).Magnitude < 3
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
	local agarre = player:GetAttribute("MovAgarre")
	local animT = player:GetAttribute("MovAnimT") or 0
	local rodando = player:GetAttribute("MovRodando") == true
	local paso = player:GetAttribute("MovPaso") or 0
	local ultimoSalto = player:GetAttribute("MovUltimoSalto") or -math.huge
	local tieneAgarre = typeof(agarre) == "Vector3"

	-- cuánto "corre" (para la amplitud del bombeo)
	local corriendo = (enSuelo and not enSlide and modo == "normal") and math.clamp(vel / C.RUN_BASE, 0, 1.5) or 0
	estado.correr = lerp(estado.correr, corriendo, math.min(dt * 8, 1))

	local delta = UserInputService:GetMouseDelta()
	estado.sway = estado.sway:Lerp(Vector2.new(math.clamp(-delta.X * 0.003, -0.12, 0.12), math.clamp(delta.Y * 0.003, -0.12, 0.12)), math.min(dt * 10, 1))

	if ultimoSalto ~= estado.ultimoSalto then
		estado.ultimoSalto = ultimoSalto
		estado.salto = 1
	end
	estado.salto = lerp(estado.salto, 0, math.min(dt * 5, 1))
	if enSuelo and not estado.estabaEnSuelo then
		estado.aterrizaje = 1
	end
	estado.estabaEnSuelo = enSuelo
	estado.aterrizaje = lerp(estado.aterrizaje, 0, math.min(dt * 8, 1))

	local tm = now - (player:GetAttribute("MovManotazo") or -math.huge)
	local golpe = 0
	if tm < 0.07 then
		golpe = tm / 0.07
	elseif tm < 0.3 then
		golpe = (1 - (tm - 0.07) / 0.23) ^ 2
	end

	local cam = camera.CFrame
	local function delMundo(p)
		return cam:PointToObjectSpace(p)
	end

	-- piernas en el salto de valla de parkour: pasan en horizontal por debajo de la vista
	local vallaRapida = player:GetAttribute("MovVallaRapida") == true
	local ladoValla = player:GetAttribute("MovLadoValla") or 1
	for lado, pierna in piernas do
		if vallaRapida then
			local curva = math.sin(animT * math.pi)
			-- cadera abajo, pies hacia el lado contrario al que se tumba el cuerpo
			local cadera = Vector3.new(-0.4 * ladoValla + lado * 0.45, -2.6 + curva * 0.6, -1.2)
			local pie = cadera + Vector3.new(-ladoValla * 2.6 * curva + lado * 0.2, 0.3 * curva, -1.6 * curva - 0.4)
			entre(pierna, cam:PointToWorldSpace(cadera), cam:PointToWorldSpace(pie), cam.LookVector, 0)
			pierna.Transparency = 1 - math.clamp(curva * 3, 0, 1)
		else
			pierna.Transparency = 1
		end
	end

	for lado, b in brazos do
		local l = lado
		local reposo = Vector3.new(C.BRAZOS_MANO.X * l, C.BRAZOS_MANO.Y, C.BRAZOS_MANO.Z)
		local objetivo = reposo
		local giro = 0
		local rigidez = C.BRAZOS_MUELLE

		if modo == "barra" and tieneAgarre then
			objetivo = delMundo(agarre + cam.RightVector * 0.8 * l)
			rigidez = 400
		elseif modo == "escalar" and tieneAgarre then
			-- manos agarradas al canto (fijas en el mundo): al subir, bajan en pantalla = empujar
			objetivo = delMundo(agarre + cam.RightVector * 0.9 * l + Vector3.new(0, 0.2, 0))
			if animT > 0.75 then
				objetivo = objetivo:Lerp(reposo, (animT - 0.75) / 0.25)
			end
			rigidez = 500
		elseif modo == "valla" and tieneAgarre and vallaRapida then
			-- las dos manos se apoyan en el obstáculo y empujan
			objetivo = delMundo(agarre + cam.RightVector * 0.7 * l + Vector3.new(0, 0.2, 0))
			if animT > 0.55 then
				objetivo = objetivo:Lerp(reposo + Vector3.new(0.5 * l, 0.2, 0.4), (animT - 0.55) / 0.45)
			end
			rigidez = 600
		elseif modo == "valla" and tieneAgarre then
			if l == -1 then
				-- la izquierda se apoya en el obstáculo
				objetivo = delMundo(agarre + Vector3.new(0, 0.2, 0))
				rigidez = 600
			else
				objetivo = reposo + Vector3.new(0.4, 0.3, 0.3)
			end
		elseif tieneAgarre and modo == "normal" and pared == 0 then
			-- trepando: las manos suben por la pared, alternadas
			local fase = now * 9 + (l == 1 and math.pi or 0)
			objetivo = delMundo(agarre + cam.RightVector * 0.8 * l + Vector3.new(0, math.sin(fase) * 0.8, 0))
			rigidez = 350
		elseif rodando then
			objetivo = Vector3.new(0.5 * l, -1.6, -1.3)
			rigidez = 300
		else
			-- correr: bombeo adelante/atrás alternado al ritmo de los pasos
			local fase = paso + (l == 1 and 0 or math.pi)
			local bombeo = math.sin(fase)
			local a = estado.correr
			objetivo += Vector3.new(-0.12 * l * bombeo, -math.abs(bombeo) * 0.12 + 0.05, -bombeo * 0.55) * a
			-- muy rápido: brazos más recogidos y bajos, como un sprint
			local sprint = math.clamp((vel - C.FLUJO_MAX * 0.8) / 20, 0, 1) * a
			objetivo += Vector3.new(-0.1 * l, -0.15, 0.2) * sprint
			objetivo += Vector3.new(estado.sway.X, estado.sway.Y, 0)

			if enSlide then
				objetivo = Vector3.new(1.5 * l, -0.8, -1.5) -- abiertos para equilibrarse
			end
			if not enSuelo then
				objetivo += Vector3.new(0.15 * l, 0.25, 0.1)
			end
			objetivo += Vector3.new(0, 0.35, 0) * estado.salto
			objetivo += Vector3.new(0, -0.4, 0.1) * estado.aterrizaje

			-- pared: la mano de ese lado roza la pared
			if (pared > 0 and l == 1) or (pared < 0 and l == -1) then
				if tieneAgarre then
					objetivo = delMundo(agarre)
				else
					objetivo = Vector3.new(1.7 * l, 0, -1.6)
				end
				rigidez = 260
			end

			if l == 1 and golpe > 0 then
				objetivo = objetivo:Lerp(Vector3.new(0.05, -0.4, -2.6), golpe)
				giro = golpe * math.rad(80)
				rigidez = 900
			elseif l == -1 then
				objetivo += Vector3.new(0, -0.25, 0.25) * golpe
			end
		end

		-- Solo se ven las manos cuando hacen algo. Si no, se van por debajo de la pantalla
		-- (y vuelven a entrar desde abajo, con el muelle, cuando las necesitas).
		local activa = (modo == "barra" and tieneAgarre)
			or (modo == "escalar" and tieneAgarre)
			or (modo == "valla" and tieneAgarre and (vallaRapida or l == -1))
			or (modo == "normal" and tieneAgarre and pared == 0) -- trepando
			or (pared > 0 and l == 1) or (pared < 0 and l == -1)
			or (l == 1 and golpe > 0)
		if not activa then
			objetivo = reposo + Vector3.new(0.4 * l, -2.8, 0.9)
			rigidez = C.BRAZOS_MUELLE * 0.8
		end

		-- que la mano nunca se meta dentro de la cámara ni se vaya demasiado lejos
		if objetivo.Z > -0.9 then
			objetivo = Vector3.new(objetivo.X, objetivo.Y, -0.9)
		end
		if objetivo.Magnitude > 4 then
			objetivo = objetivo.Unit * 4
		end

		muelle(b, objetivo, rigidez, dt)
		b.giro = lerp(b.giro, giro, math.min(dt * 20, 1))

		local hombro = cam:PointToWorldSpace(Vector3.new(C.BRAZOS_HOMBRO.X * l, C.BRAZOS_HOMBRO.Y, C.BRAZOS_HOMBRO.Z))
		local mano = cam:PointToWorldSpace(b.pos)
		-- el codo apunta hacia fuera y hacia abajo, como al correr
		local polo = cam.RightVector * l * 0.8 - cam.UpVector * 1 + cam.LookVector * 0.2
		local codo, manoReal = codoIK(hombro, mano, C.BRAZOS_LARGO_BRAZO, C.BRAZOS_LARGO_ANTEBRAZO, polo)
		local lateral = cam.RightVector
		entre(b.brazo, hombro, codo, lateral, 0)
		entre(b.antebrazo, codo, manoReal, lateral, b.giro)
		-- el brazo de arriba nunca se ve; el antebrazo se esconde cuando está fuera de la vista
		b.brazo.Transparency = 1
		b.antebrazo.Transparency = b.pos.Y < -2.4 and 1 or 0
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
