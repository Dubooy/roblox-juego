-- Brazos en primera persona (viewmodel).
-- Dos brazos con el color de piel y la ropa del personaje, pegados a la cámara.
-- Se balancean al andar, se retrasan al girar la vista y reaccionan al dash,
-- al slide, al salto y al aterrizaje. Lee el estado que publica Movimiento.client.lua.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local modelo -- Model con los brazos
local brazos = {} -- { lado = 1/-1, raiz = Part }

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
	ultimoManotazo = -math.huge,
}

local function crearParte(nombre, tam, color, material)
	local p = Instance.new("Part")
	p.Name = nombre
	p.Size = tam
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function redondear(p)
	-- malla simple (se puede cambiar por una malla redondeada más adelante)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Brick
	m.Parent = p
	return p
end

local function coloresDelPersonaje(char)
	local piel = Color3.fromRGB(234, 184, 146)
	local manga = Color3.fromRGB(45, 60, 90)
	local bc = char:FindFirstChildOfClass("BodyColors")
	if bc then
		piel = bc.LeftArmColor3
	end
	local brazo = char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")
	if brazo and not bc then
		piel = brazo.Color
	end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if torso then
		manga = torso.Color
	end
	return piel, manga
end

local function construir(char)
	if modelo then
		modelo:Destroy()
	end
	brazos = {}
	modelo = Instance.new("Model")
	modelo.Name = "BrazosVista"

	local piel, manga = coloresDelPersonaje(char)

	for _, lado in { -1, 1 } do
		local raiz = crearParte("Raiz", Vector3.new(0.05, 0.05, 0.05), piel)
		raiz.Transparency = 1
		raiz.Parent = modelo

		-- antebrazo con manga, apuntando hacia delante (eje -Z de la cámara)
		local antebrazo = redondear(crearParte("Antebrazo", Vector3.new(0.32, 0.32, 1.25), manga))
		antebrazo.Parent = modelo
		local puno = redondear(crearParte("Puno", Vector3.new(0.36, 0.36, 0.12), manga:Lerp(Color3.new(0, 0, 0), 0.25)))
		puno.Parent = modelo
		local mano = redondear(crearParte("Mano", Vector3.new(0.3, 0.26, 0.34), piel))
		mano.Parent = modelo
		local pulgar = redondear(crearParte("Pulgar", Vector3.new(0.1, 0.1, 0.18), piel))
		pulgar.Parent = modelo

		table.insert(brazos, {
			lado = lado,
			piezas = {
				{ parte = antebrazo, off = CFrame.new(0, 0, 0) },
				{ parte = puno, off = CFrame.new(0, 0, -0.62) },
				{ parte = mano, off = CFrame.new(0, -0.01, -0.84) },
				{ parte = pulgar, off = CFrame.new(-0.17 * lado, 0.06, -0.78) },
			},
		})
	end

	modelo.Parent = camera
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function actualizar(dt)
	if not modelo or not modelo.Parent then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local vivo = hum and hum.Health > 0
	-- solo en primera persona
	local primera = char and char:FindFirstChild("Head")
		and (camera.CFrame.Position - char.Head.Position).Magnitude < 1.5
	modelo.Parent = (vivo and primera) and camera or nil
	if not (vivo and primera) then
		return
	end

	local vel = player:GetAttribute("MovVelocidad") or 0
	local enSlide = player:GetAttribute("MovSlide") == true
	local enDash = player:GetAttribute("MovDash") == true
	local enSuelo = player:GetAttribute("MovSuelo") ~= false
	local ultimoSalto = player:GetAttribute("MovUltimoSalto") or -math.huge

	local k = math.min(dt * 12, 1)
	estado.tiempo += dt

	-- balanceo al andar (más rápido y amplio con la velocidad)
	local andar = enSuelo and not enSlide and math.clamp(vel / 16, 0, 1.6) or 0
	estado.bob += dt * (6 + vel * 0.35) * (andar > 0.05 and 1 or 0)
	local bobAmp = lerp(0, 1, math.min(andar, 1))

	-- retraso al girar la vista
	local delta = UserInputService:GetMouseDelta()
	local objetivoSway = Vector2.new(math.clamp(-delta.X * 0.004, -0.15, 0.15), math.clamp(delta.Y * 0.004, -0.15, 0.15))
	estado.sway = estado.sway:Lerp(objetivoSway, math.min(dt * 8, 1))

	estado.slide = lerp(estado.slide, enSlide and 1 or 0, k)
	estado.dash = lerp(estado.dash, enDash and 1 or 0, math.min(dt * 18, 1))
	estado.aire = lerp(estado.aire, enSuelo and 0 or 1, math.min(dt * 6, 1))

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

	-- manotazo: el brazo derecho sale disparado y vuelve (0 → 1 → 0 en ~0,3 s)
	local tm = os.clock() - (player:GetAttribute("MovManotazo") or -math.huge)
	local golpe = 0
	if tm < 0.08 then
		golpe = tm / 0.08
	elseif tm < 0.32 then
		golpe = 1 - (tm - 0.08) / 0.24
		golpe = golpe * golpe
	end

	local respira = math.sin(estado.tiempo * 1.6) * 0.012

	for _, b in brazos do
		local l = b.lado
		local fase = estado.bob + (l == 1 and math.pi or 0)
		local bobX = math.cos(fase) * 0.05 * bobAmp
		local bobY = math.abs(math.sin(fase)) * 0.07 * bobAmp

		-- posición de reposo: abajo a cada lado, un poco hacia dentro
		local pos = Vector3.new(0.85 * l, -0.85, -1.15)
		local rot = CFrame.Angles(math.rad(8), math.rad(-10 * l), math.rad(-6 * l))

		pos += Vector3.new(bobX, -bobY + respira, 0)
		pos += Vector3.new(estado.sway.X, estado.sway.Y, 0)

		-- slide: los brazos se abren y bajan para equilibrarse
		pos += Vector3.new(0.35 * l, -0.15, 0.25) * estado.slide
		rot *= CFrame.Angles(math.rad(-20) * estado.slide, 0, math.rad(-25 * l) * estado.slide)

		-- dash: los brazos se van hacia atrás
		pos += Vector3.new(0.1 * l, -0.35, 0.7) * estado.dash
		rot *= CFrame.Angles(math.rad(35) * estado.dash, 0, 0)

		-- en el aire: suben un poco; al saltar, impulso hacia arriba
		pos += Vector3.new(0.05 * l, 0.1, 0) * estado.aire + Vector3.new(0, 0.25, 0) * estado.salto
		rot *= CFrame.Angles(math.rad(-15) * estado.salto, 0, 0)

		-- manotazo con la mano derecha, abierta y de lado
		if l == 1 and golpe > 0 then
			pos += Vector3.new(-0.75, 0.55, -0.9) * golpe
			rot *= CFrame.Angles(math.rad(-10) * golpe, math.rad(25) * golpe, math.rad(80) * golpe)
		elseif l == -1 then
			pos += Vector3.new(0, -0.1, 0.15) * golpe -- el otro brazo se recoge
		end

		-- aterrizaje: bajan de golpe
		pos += Vector3.new(0, -0.22, 0) * estado.aterrizaje

		local base = camera.CFrame * CFrame.new(pos) * rot
		for _, pieza in b.piezas do
			pieza.parte.CFrame = base * pieza.off
		end
	end
end

local function alAparecer(char)
	char:WaitForChild("Humanoid")
	task.wait(0.2) -- espera a que carguen los colores
	construir(char)
end

player.CharacterAdded:Connect(alAparecer)
if player.Character then
	task.spawn(alAparecer, player.Character)
end

RunService:BindToRenderStep("BrazosVista", Enum.RenderPriority.Camera.Value + 2, actualizar)
