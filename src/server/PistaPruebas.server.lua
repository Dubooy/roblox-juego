-- Construye un mapa de pruebas al pulsar Play: suelo cuadriculado (para notar la
-- velocidad), pista con marcas, rampas, parkour sobre lava, bosque de pilares y una
-- gran bajada para deslizar. Todo se crea en tiempo de ejecución y no se guarda en
-- el sitio; cuando tengas tu mapa de verdad, borra este script.

local Lighting = game:GetService("Lighting")

local mapa = Instance.new("Folder")
mapa.Name = "PistaPruebas"
mapa.Parent = workspace

-- Lo que trae la plantilla de Roblox estorba: se quita solo durante la prueba.
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then
	baseplate:Destroy()
end
for _, obj in workspace:GetDescendants() do
	if obj:IsA("SpawnLocation") then
		obj.Enabled = false
	end
end

Lighting.ClockTime = 14
Lighting.Brightness = 2

local COLORES = {
	sueloA = Color3.fromRGB(70, 74, 84),
	sueloB = Color3.fromRGB(58, 61, 70),
	marca = Color3.fromRGB(90, 200, 255),
	rampa = Color3.fromRGB(255, 170, 60),
	plataforma = Color3.fromRGB(230, 230, 235),
	lava = Color3.fromRGB(255, 60, 40),
	pilar = Color3.fromRGB(140, 110, 220),
	bajada = Color3.fromRGB(90, 210, 140),
}

local function bloque(props, clase)
	local p = Instance.new(clase or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		p[k] = v
	end
	p.Parent = props.Parent or mapa
	return p
end

local function cartel(texto, posicion)
	local ancla = bloque({ Size = Vector3.one, Position = posicion, Transparency = 1, CanCollide = false, CanQuery = false })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 50)
	gui.MaxDistance = 220
	gui.Parent = ancla
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.Text = texto
	t.Parent = gui
end

------------------------------------------------------------------------
-- Suelo: baldosas de 40 x 40 alternas, 600 x 600, con la cara de arriba en y = 0
------------------------------------------------------------------------

local TAM = 40
local N = 15
for i = 0, N - 1 do
	for j = 0, N - 1 do
		bloque({
			Name = "Suelo",
			Size = Vector3.new(TAM, 4, TAM),
			Position = Vector3.new((i - (N - 1) / 2) * TAM, -2, (j - (N - 1) / 2) * TAM),
			Color = (i + j) % 2 == 0 and COLORES.sueloA or COLORES.sueloB,
		})
	end
end

-- Muros de borde para no caerse del mapa
local borde = N * TAM / 2
for _, d in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
	bloque({
		Name = "Borde",
		Size = d.X ~= 0 and Vector3.new(4, 40, N * TAM) or Vector3.new(N * TAM, 40, 4),
		Position = d * (borde + 2) + Vector3.new(0, 20, 0),
		Transparency = 0.85,
		Color = COLORES.marca,
	})
end

local spawn = bloque({
	Name = "Salida",
	Size = Vector3.new(10, 1, 10),
	Position = Vector3.new(0, 0.5, 0),
	Color = COLORES.marca,
	Material = Enum.Material.Neon,
}, "SpawnLocation")
spawn.Duration = 0
cartel("WASD · Espacio: salto/doble salto · Shift/Q: dash · Ctrl/C: slide", Vector3.new(0, 9, 0))

------------------------------------------------------------------------
-- 1. Pista de velocidad (hacia -Z): marcas cada 20 studs
------------------------------------------------------------------------

cartel("Pista de velocidad", Vector3.new(0, 8, -50))
for k = 0, 11 do
	local z = -60 - k * 20
	bloque({
		Name = "Marca",
		Size = Vector3.new(30, 0.2, 1),
		Position = Vector3.new(0, 0.1, z),
		Color = COLORES.marca,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	for _, x in { -18, 18 } do
		bloque({ Name = "Poste", Size = Vector3.new(2, 10, 2), Position = Vector3.new(x, 5, z), Color = COLORES.pilar })
	end
end

------------------------------------------------------------------------
-- 2. Rampas (corre hacia +Z y sube): 3 inclinaciones para lanzarte
------------------------------------------------------------------------

cartel("Rampas: sube corriendo o deslizando", Vector3.new(0, 10, 75))
for idx, alto in { 8, 16, 26 } do
	local x = (idx - 2) * 30
	bloque({
		Name = "Rampa",
		Size = Vector3.new(20, alto, 40),
		CFrame = CFrame.new(x, alto / 2, 120),
		Color = COLORES.rampa,
	}, "WedgePart")
end

------------------------------------------------------------------------
-- 3. Parkour sobre lava (hacia +Z, en x = -150). Si tocas la lava vuelves al inicio.
------------------------------------------------------------------------

local PX = -150
local ALTO = 6
local LARGO = 16
local huecos = {
	{ 10, "Salto" },
	{ 16, "Salto con carrerilla" },
	{ 22, "Doble salto" },
	{ 32, "Dash + doble salto" },
	{ 44, "Slide + salto + dash + doble" },
}

local zInicio = -40
bloque({ Name = "Escalon", Size = Vector3.new(16, 3, 6), Position = Vector3.new(PX, 1.5, zInicio - 3), Color = COLORES.plataforma })
local inicio = bloque({
	Name = "PlataformaInicio",
	Size = Vector3.new(16, ALTO, 30),
	Position = Vector3.new(PX, ALTO / 2, zInicio + 15),
	Color = COLORES.plataforma,
})
cartel("Parkour sobre lava", inicio.Position + Vector3.new(0, 8, 0))
local checkpoint = inicio.CFrame + Vector3.new(0, ALTO / 2 + 4, 0)

local z = zInicio + 30
local zLavaInicio = z
for _, h in huecos do
	z += h[1]
	local p = bloque({
		Name = "Plataforma",
		Size = Vector3.new(16, ALTO, LARGO),
		Position = Vector3.new(PX, ALTO / 2, z + LARGO / 2),
		Color = COLORES.plataforma,
	})
	cartel(("%s (%d)"):format(h[2], h[1]), p.Position + Vector3.new(0, 7, -LARGO / 2 - h[1] / 2))
	z += LARGO
end

local lava = bloque({
	Name = "Lava",
	Size = Vector3.new(40, 1, z - zLavaInicio),
	Position = Vector3.new(PX, 0.5, (zLavaInicio + z) / 2),
	Color = COLORES.lava,
	Material = Enum.Material.Neon,
})
lava.Touched:Connect(function(hit)
	local char = hit.Parent
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and char:FindFirstChildOfClass("Humanoid") then
		root:SetAttribute("Teletransportado", true)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = checkpoint
	end
end)

------------------------------------------------------------------------
-- 4. Bosque de pilares para zigzaguear
------------------------------------------------------------------------

cartel("Bosque de pilares", Vector3.new(200, 10, 40))
local rng = Random.new(7)
for _ = 1, 45 do
	local alto = rng:NextNumber(8, 30)
	bloque({
		Name = "Pilar",
		Size = Vector3.new(4, alto, 4),
		Position = Vector3.new(rng:NextNumber(140, 270), alto / 2, rng:NextNumber(60, 260)),
		Color = COLORES.pilar,
	})
end

------------------------------------------------------------------------
-- 5. Torre y gran bajada para deslizar (sube por la escalera del este)
------------------------------------------------------------------------

local TORRE = 40
bloque({
	Name = "Torre",
	Size = Vector3.new(40, TORRE, 20),
	Position = Vector3.new(170, TORRE / 2, -110),
	Color = COLORES.bajada,
})
bloque({
	Name = "Bajada",
	Size = Vector3.new(40, TORRE, 160),
	CFrame = CFrame.new(170, TORRE / 2, -200),
	Color = COLORES.bajada,
}, "WedgePart")
for i = 1, 13 do
	local alto = 3 * i
	bloque({
		Name = "Escalon",
		Size = Vector3.new(8, alto, 20),
		Position = Vector3.new(190 + (13 - i) * 8 + 4, alto / 2, -110),
		Color = COLORES.plataforma,
	})
end
cartel("Bajada: mantén slide cuesta abajo", Vector3.new(170, TORRE + 8, -110))
