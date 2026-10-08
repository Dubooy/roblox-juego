-- Mapas del juego. Se construyen por código al arrancar el servidor.
--
-- Fase 1: solo hay una PISTA DE PRUEBAS en estilo pastel para probar cada mecánica:
-- bordes para escalar, pasillo de paredes, zigzag de saltos de pared, barras sobre un
-- foso, torre alta para probar a rodar al caer y un tobogán para deslizar.
-- En la fase 2 llegan el parque de calistenia y la torre de obras.
--
-- Mapas.construir() devuelve una lista de mapas:
--   { nombre, apariciones = {Vector3}, alturaMinima, puntos = {Vector3} }
-- "puntos" son sitios por los que pasean los bots.
-- Las barras para columpiarse llevan la etiqueta "Barra" (CollectionService).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Mapas = {}

-- Paleta pastel
local P = {
	suelo = Color3.fromRGB(214, 204, 222), -- lavanda grisácea (no deslumbra)
	sueloB = Color3.fromRGB(204, 194, 214),
	lila = Color3.fromRGB(205, 190, 238),
	menta = Color3.fromRGB(178, 230, 210),
	melocoton = Color3.fromRGB(255, 205, 178),
	rosa = Color3.fromRGB(250, 196, 214),
	cielo = Color3.fromRGB(176, 214, 245),
	limon = Color3.fromRGB(250, 236, 168),
	barra = Color3.fromRGB(120, 120, 150),
}

------------------------------------------------------------------------
-- Ayudas
------------------------------------------------------------------------

local function bloque(padre, tam, cf, color, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = tam
	p.CFrame = typeof(cf) == "CFrame" and cf or CFrame.new(cf)
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props or {} do
		p[k] = v
	end
	p.Parent = padre
	return p
end

-- cilindro entre dos puntos (su eje queda en X)
local function cilindro(padre, a, b, grosor, color)
	local p = bloque(padre, Vector3.new((b - a).Magnitude, grosor, grosor), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- barra para columpiarse, con sus dos postes
local function barraColumpio(padre, a, b, color)
	local barra = cilindro(padre, a, b, 0.8, P.barra)
	CollectionService:AddTag(barra, "Barra")
	cilindro(padre, a, Vector3.new(a.X, 0, a.Z), 0.9, color)
	cilindro(padre, b, Vector3.new(b.X, 0, b.Z), 0.9, color)
	return barra
end

-- rampa de "desde" a "hasta" (puntos de la superficie)
local function rampa(padre, desde, hasta, ancho, color)
	local dir = hasta - desde
	local cf = CFrame.lookAt((desde + hasta) / 2, (desde + hasta) / 2 + dir)
	return bloque(padre, Vector3.new(ancho, 1, dir.Magnitude), cf * CFrame.new(0, -0.5, 0), color)
end

local function letrero(padre, pos, texto)
	local a = bloque(padre, Vector3.new(0.4, 0.4, 0.4), pos, P.suelo, { Transparency = 1, CanCollide = false, CanQuery = false })
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(220, 40)
	g.AlwaysOnTop = false
	g.MaxDistance = 90
	g.Parent = a
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(110, 96, 140)
	t.Text = texto
	t.Parent = g
end

------------------------------------------------------------------------
-- Ambiente pastel: luz suave, niebla rosada, colores un poco lavados
------------------------------------------------------------------------

local function ambiente()
	for _, v in Lighting:GetChildren() do
		if v:IsA("Sky") or v:IsA("Atmosphere") or v:IsA("PostEffect") then
			v:Destroy()
		end
	end
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2
	Lighting.ExposureCompensation = -0.2
	Lighting.Ambient = Color3.fromRGB(150, 140, 165)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 170)
	Lighting.EnvironmentDiffuseScale = 0.8
	Lighting.EnvironmentSpecularScale = 0 -- sin reflejos: todo mate
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.6

	local atm = Instance.new("Atmosphere")
	atm.Density = 0.2
	atm.Offset = 0.1
	atm.Color = Color3.fromRGB(255, 226, 236)
	atm.Decay = Color3.fromRGB(200, 186, 230)
	atm.Glare = 0.2
	atm.Haze = 0.6
	atm.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0
	cc.Contrast = 0.05
	cc.Saturation = -0.12
	cc.TintColor = Color3.fromRGB(255, 248, 252)
	cc.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0
	bloom.Size = 30
	bloom.Threshold = 2.2
	bloom.Parent = Lighting
end

------------------------------------------------------------------------
-- Pista de pruebas (circuito en bucle)
------------------------------------------------------------------------
--
--   Vista desde arriba (Z hacia abajo):
--
--     [Bordes]  →  [Pasillo de paredes]  →  [Zigzag de muros]
--        ↑                                         ↓
--     [Tobogán] ←  [Torre para rodar]  ←  [Barras sobre el foso]

local function pista(raiz)
	local m = Instance.new("Model")
	m.Name = "PistaPruebas"
	m.Parent = raiz

	-- suelo con baldosas suaves
	for i = -4, 3 do
		for j = -3, 2 do
			bloque(m, Vector3.new(40, 2, 40), Vector3.new(i * 40 + 20, -1, j * 40 + 20), (i + j) % 2 == 0 and P.suelo or P.sueloB)
		end
	end
	-- muro alrededor (alto, para no salirse y para correr por él)
	for _, v in { { Vector3.new(0, 8, 120), Vector3.new(322, 16, 2) }, { Vector3.new(0, 8, -120), Vector3.new(322, 16, 2) }, { Vector3.new(160, 8, 0), Vector3.new(2, 16, 242) }, { Vector3.new(-160, 8, 0), Vector3.new(2, 16, 242) } } do
		bloque(m, v[2], v[1], P.lila)
	end

	-- 1. BORDES PARA ESCALAR (salta hacia ellos): alturas 5, 7 y 9
	letrero(m, Vector3.new(-120, 14, -90), "Salta hacia el borde para escalar")
	for i, h in { 5, 7, 9 } do
		bloque(m, Vector3.new(14, h, 14), Vector3.new(-140 + i * 16, h / 2, -90), ({ P.melocoton, P.rosa, P.lila })[i])
	end

	-- 1b. VALLAS (corre hacia ellas: se saltan solas sin frenar)
	letrero(m, Vector3.new(-80, 10, -40), "Vallas: corre hacia ellas")
	for i, h in { 2, 3, 4, 2.5, 3.5 } do
		bloque(m, Vector3.new(10, h, 2), Vector3.new(-130 + i * 18, h / 2, -40), i % 2 == 0 and P.menta or P.melocoton)
	end

	-- 1c. TREPAR (corre contra la pared y salta). La baja (11) se sube; en la alta (20) salta otra vez para impulsarte atrás
	letrero(m, Vector3.new(30, 26, -40), "Trepar: corre contra la pared y salta")
	bloque(m, Vector3.new(16, 11, 10), Vector3.new(20, 5.5, -48), P.rosa)
	bloque(m, Vector3.new(16, 20, 4), Vector3.new(44, 10, -50), P.cielo)

	-- 2. PASILLO DE PAREDES (correr por la pared)
	letrero(m, Vector3.new(-40, 22, -90), "Correr por la pared")
	bloque(m, Vector3.new(60, 18, 2), Vector3.new(-40, 9, -98), P.menta)
	bloque(m, Vector3.new(60, 18, 2), Vector3.new(-40, 9, -82), P.cielo)
	-- foso bajo el pasillo para obligar a ir por la pared
	bloque(m, Vector3.new(50, 0.2, 14), Vector3.new(-40, 0.1, -90), P.rosa)

	-- 3. ZIGZAG DE MUROS (saltar de pared a pared hacia arriba)
	letrero(m, Vector3.new(60, 30, -90), "Salto de pared")
	for i = 0, 5 do
		local lado = i % 2 == 0 and -1 or 1
		bloque(m, Vector3.new(10, 14, 2), Vector3.new(40 + i * 8, 7 + i * 3, -90 + lado * 6), i % 2 == 0 and P.lila or P.menta)
	end
	bloque(m, Vector3.new(20, 1, 20), Vector3.new(95, 24, -90), P.limon) -- meta arriba

	-- 4. BARRAS SOBRE EL FOSO (columpiarse)
	letrero(m, Vector3.new(120, 22, 0), "Barras")
	-- plataforma de salida
	bloque(m, Vector3.new(20, 10, 20), Vector3.new(120, 5, -50), P.melocoton)
	rampa(m, Vector3.new(120, 0, -20), Vector3.new(120, 10, -40), 8, P.melocoton)
	-- foso de "agua" (si caes, no pasa nada, solo pierdes tiempo)
	bloque(m, Vector3.new(24, 0.3, 60), Vector3.new(120, 0.15, 10), P.cielo, { Material = Enum.Material.Glass, Transparency = 0.2 })
	for k = 0, 3 do
		local z = -28 + k * 16
		local y = 15 - (k % 2) * 2
		barraColumpio(m, Vector3.new(112, y, z), Vector3.new(128, y, z), P.lila)
	end
	bloque(m, Vector3.new(20, 8, 16), Vector3.new(120, 4, 48), P.melocoton)

	-- 5. TORRE PARA RODAR (sube por los bordes y déjate caer pulsando slide al llegar)
	letrero(m, Vector3.new(40, 40, 90), "Cae y pulsa slide para rodar")
	local escalones = { 4, 9, 14, 19, 24, 30 }
	for i, h in escalones do
		bloque(m, Vector3.new(10, h, 10), Vector3.new(90 - i * 10, h / 2, 90), i % 2 == 0 and P.rosa or P.lila)
	end
	bloque(m, Vector3.new(14, 1, 14), Vector3.new(30 - 2, 30.5, 90), P.limon)

	-- 6. TOBOGÁN PARA DESLIZAR (empieza alto y baja hasta el inicio)
	letrero(m, Vector3.new(-60, 26, 90), "Desliza cuesta abajo")
	bloque(m, Vector3.new(14, 20, 14), Vector3.new(-20, 10, 90), P.menta)
	-- escalera de bordes para subir al tobogán
	for i, h in { 5, 10, 15 } do
		bloque(m, Vector3.new(8, h, 8), Vector3.new(-20 + i * 9, h / 2, 104), P.melocoton)
	end
	rampa(m, Vector3.new(-27, 20, 90), Vector3.new(-110, 0.2, 90), 12, P.cielo)
	rampa(m, Vector3.new(-110, 0.2, 90), Vector3.new(-125, 6, 70), 12, P.rosa) -- pequeña subida final (salto)

	-- decoración: nubes de algodón alrededor
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local c = Vector3.new(math.cos(a) * 230, 40 + (i % 3) * 12, math.sin(a) * 170)
		for k = 0, 2 do
			local bola = bloque(m, Vector3.one * (16 + k * 6), c + Vector3.new(k * 10 - 10, k % 2 * 4, 0), Color3.fromRGB(255, 250, 252), { CanCollide = false, CanQuery = false, CastShadow = false })
			bola.Shape = Enum.PartType.Ball
		end
	end

	local apariciones, puntos = {}, {}
	for i = 0, 7 do
		table.insert(apariciones, Vector3.new(-100 + i * 25, 4, 30))
	end
	for x = -140, 140, 35 do
		for z = -100, 100, 40 do
			table.insert(puntos, Vector3.new(x, 3, z))
		end
	end
	return { nombre = "Pista de pruebas", apariciones = apariciones, alturaMinima = -30, puntos = puntos }
end

------------------------------------------------------------------------

function Mapas.construir()
	for _, nombre in { "Baseplate", "SpawnLocation", "Mapas" } do
		local v = workspace:FindFirstChild(nombre)
		if v then
			v:Destroy()
		end
	end
	local raiz = Instance.new("Folder")
	raiz.Name = "Mapas"
	raiz.Parent = workspace

	ambiente()
	local lista = { pista(raiz) }

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 0.5, 30)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = raiz

	return lista
end

return Mapas
