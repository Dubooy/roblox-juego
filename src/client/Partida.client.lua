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
	Manotazo:FireServer(camera.CFrame.LookVector)
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

Golpe.OnClientEvent:Connect(function(atacante, golpeado)
	-- atacante y golpeado son modelos (personajes de jugadores o bots)
	local r = golpeado and golpeado:FindFirstChild("HumanoidRootPart")
	if r then
		-- chispazo
		local a = Instance.new("Attachment")
		a.Parent = r
		local p = Instance.new("ParticleEmitter")
		p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		p.Color = ColorSequence.new(Color3.fromRGB(255, 240, 160))
		p.Size = NumberSequence.new(1.2, 0)
		p.Lifetime = NumberRange.new(0.2, 0.4)
		p.Speed = NumberRange.new(20, 35)
		p.SpreadAngle = Vector2.new(180, 180)
		p.Rate = 0
		p.Parent = a
		p:Emit(25)
		sonido("rbxasset://sounds/swordlunge.wav", 0.7, 1.4, r)
		task.delay(1, function()
			a:Destroy()
		end)
	end
	if golpeado ~= nil and golpeado == player.Character then
		-- sacudida de cámara al recibir
		local inicio = os.clock()
		local con
		con = RunService.RenderStepped:Connect(function()
			local t = os.clock() - inicio
			if t > 0.25 then
				con:Disconnect()
				return
			end
			local f = (1 - t / 0.25) * 0.6
			camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * f * 6), math.rad((math.random() - 0.5) * f * 6), 0)
		end)
	end
end)
