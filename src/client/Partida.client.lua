-- Cliente de la partida: botón de manotazo, HUD de la ronda y efectos al golpear.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotos = ReplicatedStorage:WaitForChild("Remotos")
local Manotazo = remotos:WaitForChild("Manotazo")
local Golpe = remotos:WaitForChild("Golpe")
local Cinematica = remotos:WaitForChild("Cinematica")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

------------------------------------------------------------------------
-- Manotazo
------------------------------------------------------------------------

local ultimo = -math.huge

local function darManotazo()
	local ahora = os.clock()
	if ahora - ultimo < C.MANOTAZO_ESPERA then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0) then
		return
	end
	ultimo = ahora
	player:SetAttribute("MovManotazo", ahora) -- los brazos lo animan
	Manotazo:FireServer(camera.CFrame.LookVector, { combo = player:GetAttribute("MovCombo") or 0 })
end

ContextActionService:BindActionAtPriority("Manotazo", function(_, estado)
	if estado == Enum.UserInputState.Begin then
		darManotazo()
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2, Enum.KeyCode.E)
ContextActionService:SetTitle("Manotazo", "Manotazo")
ContextActionService:SetPosition("Manotazo", UDim2.new(1, -250, 1, -130))

------------------------------------------------------------------------
-- HUD
------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "HUDPartida"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function texto(props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.Text = ""
	for k, v in props do
		t[k] = v
	end
	t.Parent = gui
	return t
end

local reloj = texto({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 16),
	Size = UDim2.fromOffset(200, 40),
	TextSize = 34,
})
local modo = texto({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 54),
	Size = UDim2.fromOffset(300, 20),
	TextSize = 16,
	Font = Enum.Font.GothamBold,
	TextTransparency = 0.2,
})
local mensaje = texto({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.new(0.9, 0, 0, 90),
	TextSize = 30,
	TextWrapped = true,
})
local rol = texto({
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 20, 0, 16),
	Size = UDim2.fromOffset(240, 36),
	TextSize = 24,
	TextXAlignment = Enum.TextXAlignment.Left,
})

-- borde rojo en pantalla cuando pillas
local bordeStroke = Instance.new("UIStroke")
bordeStroke.Thickness = 10
bordeStroke.Color = Color3.fromRGB(255, 60, 60)
bordeStroke.Transparency = 1
local bordeFrame = Instance.new("Frame")
bordeFrame.BackgroundTransparency = 1
bordeFrame.Size = UDim2.fromScale(1, 1)
bordeFrame.Parent = gui
bordeStroke.Parent = bordeFrame

local function formatoTiempo(seg)
	seg = math.max(0, math.floor(seg))
	return string.format("%d:%02d", seg // 60, seg % 60)
end

local ultimoMensaje = ""
RunService.RenderStepped:Connect(function()
	local fase = ReplicatedStorage:GetAttribute("Fase") or "Esperando"
	local t = ReplicatedStorage:GetAttribute("Tiempo") or 0
	local m = ReplicatedStorage:GetAttribute("Mensaje") or ""

	reloj.Text = fase == "Jugando" and formatoTiempo(t) or ""
	modo.Text = fase == "Jugando"
			and string.upper((ReplicatedStorage:GetAttribute("Modo") or "") .. " · " .. (ReplicatedStorage:GetAttribute("Mapa") or ""))
		or ""

	if m ~= ultimoMensaje then
		ultimoMensaje = m
		mensaje.Text = m
		mensaje.TextTransparency = 0
		mensaje.TextStrokeTransparency = 0.4
		if fase == "Jugando" and m ~= "" then
			-- los avisos de la ronda se desvanecen solos
			task.delay(2.5, function()
				if ultimoMensaje == m then
					TweenService:Create(mensaje, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				end
			end)
		end
	end

	local pillador = player:GetAttribute("Pillador")
	if pillador == true then
		rol.Text = "PILLAS"
		rol.TextColor3 = Color3.fromRGB(255, 90, 90)
	elseif pillador == false then
		rol.Text = "HUYE"
		rol.TextColor3 = Color3.fromRGB(110, 210, 255)
	else
		rol.Text = ""
	end
	bordeStroke.Transparency = pillador == true and 0.35 or 1
end)

------------------------------------------------------------------------
-- Efectos al golpear
------------------------------------------------------------------------

local function sonido(id, volumen, tono, parent)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volumen
	s.PlaybackSpeed = tono
	s.Parent = parent
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local Lighting = game:GetService("Lighting")

-- efectos de pantalla compartidos por el golpe y la cinemática
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "EfectoPillar"
cc.Parent = Lighting

local destello = Instance.new("Frame")
destello.Size = UDim2.fromScale(1, 1)
destello.BackgroundColor3 = Color3.new(1, 1, 1)
destello.BackgroundTransparency = 1
destello.BorderSizePixel = 0
destello.ZIndex = 50
destello.Parent = gui

local function chispazo(r, cantidad, color)
	local a = Instance.new("Attachment")
	a.Parent = r
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Color = ColorSequence.new(color or Color3.fromRGB(255, 240, 160))
	p.Size = NumberSequence.new(1.4, 0)
	p.Lifetime = NumberRange.new(0.25, 0.5)
	p.Speed = NumberRange.new(20, 45)
	p.SpreadAngle = Vector2.new(180, 180)
	p.LightEmission = 0.6
	p.Rate = 0
	p.Parent = a
	p:Emit(cantidad)
	task.delay(1.5, function()
		a:Destroy()
	end)
end

local function estela(r, segundos)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = r
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = r
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Lifetime = 0.35
	tr.Color = ColorSequence.new(Color3.fromRGB(255, 220, 240))
	tr.Transparency = NumberSequence.new(0.2, 1)
	tr.LightEmission = 0.5
	tr.Parent = r
	task.delay(segundos, function()
		tr.Enabled = false
		task.wait(0.5)
		tr:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
end

Golpe.OnClientEvent:Connect(function(atacante, golpeado, congelado, pillado)
	-- atacante y golpeado son modelos (personajes de jugadores o bots)
	local r = golpeado and golpeado:FindFirstChild("HumanoidRootPart")
	congelado = typeof(congelado) == "number" and congelado or 0.1
	if r then
		chispazo(r, pillado and 45 or 20)
		sonido("rbxasset://sounds/swordlunge.wav", pillado and 1 or 0.6, pillado and 1.1 or 1.4, r)
		if pillado then
			-- el golpe seco suena justo al soltarse el congelado
			task.delay(congelado, function()
				if r.Parent then
					sonido("rbxasset://sounds/electronicpingshort.wav", 0.5, 0.6, r)
					estela(r, 1.2)
				end
			end)
		end
	end
	local implicado = (golpeado ~= nil and golpeado == player.Character) or (atacante ~= nil and atacante == player.Character)
	if implicado and not player:GetAttribute("EnCinematica") then
		-- destello y blanco y negro durante el congelado
		destello.BackgroundTransparency = pillado and 0.55 or 0.8
		TweenService:Create(destello, TweenInfo.new(congelado + 0.15), { BackgroundTransparency = 1 }):Play()
		cc.Saturation = pillado and -0.8 or -0.3
		cc.Contrast = 0.15
		task.delay(congelado, function()
			TweenService:Create(cc, TweenInfo.new(0.25), { Saturation = 0, Contrast = 0 }):Play()
		end)
	end
	if golpeado ~= nil and golpeado == player.Character then
		-- sacudida de cámara al salir volando
		task.delay(congelado, function()
			local inicio = os.clock()
			local con
			con = RunService.RenderStepped:Connect(function()
				local tt = os.clock() - inicio
				if tt > 0.3 or player:GetAttribute("EnCinematica") then
					con:Disconnect()
					return
				end
				local f = (1 - tt / 0.3) * 0.8
				camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * f * 6), math.rad((math.random() - 0.5) * f * 6), 0)
			end)
		end)
	end
end)

------------------------------------------------------------------------
-- Cinemática del pillado épico: 3 planos (~3 s) y se sigue jugando
------------------------------------------------------------------------
--  1. IMPACTO (casi congelado, blanco y negro): primer plano de la mano llegando.
--  2. GIRO: la cámara da media vuelta alrededor de los dos mientras el pillado sale disparado.
--  3. VUELO: desde abajo, el pillado volando contra el cielo con su nombre en grande.

local cine = Instance.new("ScreenGui")
cine.Name = "Cinematica"
cine.ResetOnSpawn = false
cine.IgnoreGuiInset = true
cine.DisplayOrder = 20
cine.Enabled = false
cine.Parent = player:WaitForChild("PlayerGui")

local function franja(arriba)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0, arriba and 0 or 1)
	f.Position = UDim2.fromScale(0, arriba and 0 or 1)
	f.Size = UDim2.fromScale(1, 0)
	f.BackgroundColor3 = Color3.fromRGB(20, 16, 28)
	f.BorderSizePixel = 0
	f.Parent = cine
	return f
end
local franjaArriba, franjaAbajo = franja(true), franja(false)

local titulo = Instance.new("TextLabel")
titulo.AnchorPoint = Vector2.new(0.5, 0.5)
titulo.Position = UDim2.fromScale(0.5, 0.72)
titulo.Size = UDim2.new(0.9, 0, 0, 80)
titulo.BackgroundTransparency = 1
titulo.Font = Enum.Font.GothamBlack
titulo.TextScaled = true
titulo.TextColor3 = Color3.fromRGB(255, 236, 246)
titulo.TextStrokeColor3 = Color3.fromRGB(120, 60, 110)
titulo.TextStrokeTransparency = 0
titulo.Text = ""
titulo.Parent = cine
local subtitulo = titulo:Clone()
subtitulo.Position = UDim2.fromScale(0.5, 0.8)
subtitulo.Size = UDim2.new(0.8, 0, 0, 32)
subtitulo.Font = Enum.Font.GothamBold
subtitulo.TextColor3 = Color3.fromRGB(255, 214, 120)
subtitulo.Parent = cine

-- líneas de velocidad (rayas blancas que cruzan la pantalla en el plano 2)
local lineas = {}
for i = 1, 14 do
	local l = Instance.new("Frame")
	l.BackgroundColor3 = Color3.new(1, 1, 1)
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = UDim2.new(0.35, 0, 0, 2)
	l.Parent = cine
	lineas[i] = { frame = l, y = math.random(), v = 1.5 + math.random() * 2 }
end

local enCurso = false

local function suave(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

Cinematica.OnClientEvent:Connect(function(atacante, golpeado, dir, texto, motivo)
	if enCurso or not (atacante and golpeado) then
		return
	end
	local ra = atacante:FindFirstChild("HumanoidRootPart")
	local rv = golpeado:FindFirstChild("HumanoidRootPart")
	if not (ra and rv) then
		return
	end
	enCurso = true
	player:SetAttribute("EnCinematica", true)
	dir = typeof(dir) == "Vector3" and dir.Magnitude > 0.1 and dir.Unit or (rv.Position - ra.Position).Unit
	local lado = dir:Cross(Vector3.yAxis).Unit

	local antes = { tipo = camera.CameraType, fov = camera.FieldOfView, cf = camera.CFrame }
	camera.CameraType = Enum.CameraType.Scriptable
	cine.Enabled = true
	titulo.Text = ""
	subtitulo.Text = ""
	franjaArriba.Size = UDim2.fromScale(1, 0)
	franjaAbajo.Size = UDim2.fromScale(1, 0)
	TweenService:Create(franjaArriba, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 0.11) }):Play()
	TweenService:Create(franjaAbajo, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 0.11) }):Play()

	local P1, P2, P3 = C.CINE_PLANO1, C.CINE_PLANO2, C.CINE_PLANO3
	local inicio = os.clock()
	local centro0 = (ra.Position + rv.Position) / 2
	local sonoVuelo = false

	RunService:BindToRenderStep("CinematicaPillado", Enum.RenderPriority.Last.Value, function(dt)
		local tt = os.clock() - inicio
		local pa = ra.Parent and ra.Position or centro0
		local pv = rv.Parent and rv.Position or centro0

		if tt < P1 then
			-- 1. IMPACTO: muy cerca, de lado, empujando despacio hacia la mano
			local k = tt / P1
			local foco = pv:Lerp(pa, 0.35) + Vector3.new(0, 1.2, 0)
			local pos = foco + lado * (6 - k * 1.5) + Vector3.new(0, 0.8, 0) - dir * 1.5
			camera.CFrame = CFrame.lookAt(pos, foco) * CFrame.Angles(0, 0, math.rad(-8))
			camera.FieldOfView = 40 - k * 6
			cc.Saturation = -0.95
			cc.Contrast = 0.3
			cc.TintColor = Color3.fromRGB(255, 240, 248)
		elseif tt < P1 + P2 then
			-- 2. GIRO: media vuelta alrededor de los dos, el pillado empieza a volar
			local k = suave((tt - P1) / P2)
			if not sonoVuelo then
				sonoVuelo = true
				sonido("rbxasset://sounds/electronicpingshort.wav", 0.8, 0.5, rv)
				estela(rv, 2.5)
				chispazo(rv, 60, Color3.fromRGB(255, 200, 230))
				titulo.Text = texto or ""
				titulo.TextTransparency = 1
				TweenService:Create(titulo, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
			end
			local foco = pa:Lerp(pv, 0.5 + k * 0.3) + Vector3.new(0, 1.5, 0)
			local ang = math.pi * 0.5 + k * math.pi
			local radio = 11 + k * 4
			local orbita = (lado * math.cos(ang) + dir * math.sin(ang)) * radio
			camera.CFrame = CFrame.lookAt(foco + orbita + Vector3.new(0, 3 + k * 2, 0), foco)
			camera.FieldOfView = 55 + k * 10
			cc.Saturation = -0.95 + k * 0.95
			cc.Contrast = 0.3 - k * 0.2
			-- líneas de velocidad
			for _, l in lineas do
				local x = ((tt * l.v + l.y * 3) % 1.6) - 0.3
				l.frame.Position = UDim2.fromScale(x, 0.12 + l.y * 0.76)
				l.frame.BackgroundTransparency = 0.35 + (1 - math.sin(k * math.pi)) * 0.65
			end
		elseif tt < P1 + P2 + P3 then
			-- 3. VUELO: desde abajo, el pillado contra el cielo
			local k = (tt - P1 - P2) / P3
			for _, l in lineas do
				l.frame.BackgroundTransparency = 1
			end
			subtitulo.Text = motivo or ""
			local suelo = Vector3.new(pv.X, math.min(pv.Y - 6, pa.Y - 1), pv.Z)
			local pos = suelo - dir * (7 + k * 2) + lado * 3
			camera.CFrame = CFrame.lookAt(pos, pv + Vector3.new(0, 1, 0))
			camera.FieldOfView = 65 + k * 8
			cc.Saturation = 0.25
			cc.Contrast = 0.1
			titulo.Size = UDim2.new(0.9, 0, 0, 80 + k * 20)
		else
			-- fin: vuelta al juego
			RunService:UnbindFromRenderStep("CinematicaPillado")
			for _, l in lineas do
				l.frame.BackgroundTransparency = 1
			end
			titulo.Text = ""
			titulo.Size = UDim2.new(0.9, 0, 0, 80)
			subtitulo.Text = ""
			cc.Saturation = 0
			cc.Contrast = 0
			cc.TintColor = Color3.new(1, 1, 1)
			camera.FieldOfView = antes.fov
			camera.CameraType = Enum.CameraType.Custom
			-- la vista vuelve a donde mirabas
			local char = player.Character
			local cabeza = char and char:FindFirstChild("Head")
			if cabeza then
				camera.CFrame = CFrame.new(cabeza.Position) * (antes.cf - antes.cf.Position)
			end
			local t1 = TweenService:Create(franjaArriba, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 0) })
			TweenService:Create(franjaAbajo, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 0) }):Play()
			t1:Play()
			t1.Completed:Once(function()
				cine.Enabled = false
			end)
			player:SetAttribute("EnCinematica", nil)
			enCurso = false
		end
	end)
end)
