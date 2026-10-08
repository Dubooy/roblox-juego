-- Mapas del juego. Se construyen por código al arrancar el servidor.
--
-- · Pista de pruebas (en el centro, donde apareces entre rondas): una zona por mecánica.
-- · Parque de calistenia y Torre de obras: los mapas de la partida, que se alternan.
--
-- Mapas.construir() devuelve una lista de mapas:
--   { nombre, apariciones = {Vector3}, alturaMinima, puntos = {Vector3} }
-- "puntos" son sitios por los que pasean los bots.
-- Las barras para columpiarse llevan la etiqueta "Barra" (CollectionService).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Mapas = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SOLO_MOVIMIENTO = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")).SOLO_MOVIMIENTO

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
-- Ayudas para los mapas grandes
------------------------------------------------------------------------

-- caja apoyada en el suelo: centro en planta (x, z), base en y0
local function caja(padre, o, x, z, ancho, alto, fondo, color, y0)
	return bloque(padre, Vector3.new(ancho, alto, fondo), o + Vector3.new(x, (y0 or 0) + alto / 2, z), color)
end

-- muro perimetral alto, con remate de otro color arriba
local function recinto(padre, o, mitadX, mitadZ, alto, color, remate)
	for _, v in {
		{ Vector3.new(0, 0, mitadZ), Vector3.new(mitadX * 2 + 2, alto, 2) },
		{ Vector3.new(0, 0, -mitadZ), Vector3.new(mitadX * 2 + 2, alto, 2) },
		{ Vector3.new(mitadX, 0, 0), Vector3.new(2, alto, mitadZ * 2 + 2) },
		{ Vector3.new(-mitadX, 0, 0), Vector3.new(2, alto, mitadZ * 2 + 2) },
	} do
		bloque(padre, v[2], o + v[1] + Vector3.new(0, alto / 2, 0), color)
		bloque(padre, Vector3.new(v[2].X + 0.4, 0.8, v[2].Z + 0.4), o + v[1] + Vector3.new(0, alto + 0.4, 0), remate)
	end
end

local function arbol(padre, pos, color)
	bloque(padre, Vector3.new(2, 10, 2), pos + Vector3.new(0, 5, 0), Color3.fromRGB(190, 160, 150))
	for i, d in { Vector3.new(0, 13, 0), Vector3.new(2.5, 11, 1.5), Vector3.new(-2.2, 11.5, -1.5) } do
		local bola = bloque(padre, Vector3.one * (i == 1 and 10 or 7), pos + d, color, { CastShadow = true })
		bola.Shape = Enum.PartType.Ball
	end
end

------------------------------------------------------------------------
-- Mapa 1: PARQUE DE CALISTENIA (circuito en forma de 8)
------------------------------------------------------------------------
--
--   Vista desde arriba. Los dos bucles del 8 rodean dos "islas":
--
--   ┌───────────── muro (correr por él) ─────────────┐
--   │  pasillo de paredes  ═══      ═══  pasillo     │
--   │   ╭──────╮                 ╭──────╮            │
--   │   │ RIG  │   ← cruce →     │BLOQUES│           │
--   │   │barras│   (valla+barras)│parkour│           │
--   │   ╰──────╯                 ╰──────╯            │
--   │  bancos (vallas)  ═══      ═══  bancos         │
--   └────────────────────────────────────────────────┘
--
--   · RIG (oeste): estructura de calistenia de 3 alturas: cajas para subir, plataformas a
--     8, panel para trepar hasta 18, pasamanos de barras entre plataformas y una torre a
--     30 con un tobogán larguísimo hacia el cruce (slide = mucha inercia).
--   · BLOQUES (este): cajas de 3, 6, 10 y 14 para vallas, escalar y trepar, con barras para
--     volver cruzando un hueco.
--   · Rectas del 8: pasillos de paredes paralelas (correr por la pared y saltar de una a
--     otra) y bancos bajos (vallas).

local function parque(raiz, o)
	local m = Instance.new("Model")
	m.Name = "ParqueCalistenia"
	m.Parent = raiz

	local Q = {
		suelo = Color3.fromRGB(196, 222, 206), -- menta suave
		sueloB = Color3.fromRGB(186, 214, 198),
		camino = Color3.fromRGB(236, 214, 200), -- caucho melocotón
		muro = Color3.fromRGB(214, 200, 236),
		remate = Color3.fromRGB(250, 236, 168),
		madera = Color3.fromRGB(240, 206, 170),
		poste = Color3.fromRGB(150, 140, 190),
		rosa = P.rosa,
		cielo = P.cielo,
		menta = P.menta,
		lila = P.lila,
	}

	local MX, MZ = 78, 58
	-- suelo y caminos del 8
	bloque(m, Vector3.new(MX * 2 + 40, 2, MZ * 2 + 40), o + Vector3.new(0, -1, 0), Q.suelo)
	for _, z in { -42, 42 } do
		bloque(m, Vector3.new(150, 0.3, 14), o + Vector3.new(0, 0.15, z), Q.camino)
	end
	for _, x in { -70, 0, 70 } do
		bloque(m, Vector3.new(14, 0.3, 98), o + Vector3.new(x, 0.15, 0), Q.camino)
	end
	recinto(m, o, MX, MZ, 16, Q.muro, Q.remate)

	-- ISLA OESTE: estructura de calistenia
	local R = o + Vector3.new(-36, 0, 0)
	for _, x in { -14, 0, 14 } do
		for _, z in { -14, 14 } do
			cilindro(m, R + Vector3.new(x, 0, z), R + Vector3.new(x, 31, z), 1.2, Q.poste)
		end
	end
	-- plataformas a 8 en diagonal
	bloque(m, Vector3.new(12, 1, 12), R + Vector3.new(-10, 8, -8), Q.madera)
	bloque(m, Vector3.new(12, 1, 12), R + Vector3.new(10, 8, 8), Q.madera)
	-- cajas para subir a la primera (vallas y escalar)
	caja(m, R, -10, -20, 8, 3.5, 6, Q.rosa)
	caja(m, R, -17, -12, 6, 6, 8, Q.lila)
	-- pasamanos: barras colgantes entre las dos plataformas (cruzar columpiándote)
	for k = 1, 3 do
		local c = R + Vector3.new(-10 + k * 5, 13, -8 + k * 4)
		local eje = Vector3.new(4, 0, -5).Unit * 4
		local b = cilindro(m, c - eje, c + eje, 0.7, P.barra)
		CollectionService:AddTag(b, "Barra")
	end
	-- panel para trepar desde la plataforma este hasta la de 18
	bloque(m, Vector3.new(10, 12, 1.5), R + Vector3.new(10, 14 + 0.5, 14.5 - 0.75), Q.cielo)
	bloque(m, Vector3.new(14, 1, 10), R + Vector3.new(6, 20.5, 9), Q.madera)
	-- de 18 a la torre de 30: dos bordes para escalar
	caja(m, R, -2, 6, 6, 5, 6, Q.menta, 21)
	bloque(m, Vector3.new(10, 1, 10), R + Vector3.new(-6, 30.5, 0), Q.remate)
	caja(m, R, -4, 4, 2, 4, 2, Q.rosa, 26) -- escalón intermedio
	-- tobogán larguísimo desde la torre hasta el cruce (slide = inercia)
	rampa(m, R + Vector3.new(-1, 31, 0), o + Vector3.new(-6, 0.3, 0), 7, Q.rosa)
	-- barras de dominadas bajo la estructura (pasar deslizando o columpiarse)
	for k = 0, 2 do
		barraColumpio(m, R + Vector3.new(-6 + k * 6, 9 + k, 18), R + Vector3.new(-6 + k * 6, 9 + k, 26), Q.poste)
	end

	-- ISLA ESTE: bloques de parkour
	local B = o + Vector3.new(36, 0, 0)
	caja(m, B, -14, -10, 8, 3, 6, Q.menta) -- valla
	caja(m, B, -6, -14, 8, 6, 8, Q.rosa) -- escalar
	caja(m, B, 4, -12, 10, 10, 10, Q.lila) -- trepar
	caja(m, B, 12, 0, 10, 14, 14, Q.cielo) -- trepar + escalar
	caja(m, B, 2, 4, 8, 6.5, 8, Q.madera)
	caja(m, B, -10, 8, 10, 3.5, 4, Q.menta) -- valla
	-- de la torre de 14 se vuelve por barras sobre el hueco hacia el norte
	for k = 0, 2 do
		local z = 12 + k * 7
		barraColumpio(m, B + Vector3.new(7, 15 - k, z), B + Vector3.new(15, 15 - k, z), Q.poste)
	end
	caja(m, B, 11, 34, 10, 8, 6, Q.rosa) -- llegada (borde a 8)

	-- RECTAS: pasillos de paredes paralelas y bancos
	for _, z in { -42, 42 } do
		for _, x in { -40, 34 } do
			bloque(m, Vector3.new(26, 12, 1.5), o + Vector3.new(x, 6, z - 7), z > 0 and Q.cielo or Q.menta)
			bloque(m, Vector3.new(26, 12, 1.5), o + Vector3.new(x + 6, 6, z + 7), z > 0 and Q.lila or Q.rosa)
		end
		for _, x in { -10, 10 } do
			caja(m, o, x, z, 1.5, 2.5, 10, Q.madera) -- banco (valla)
		end
	end

	-- CRUCE central: valla alta y barras para pasar por encima
	caja(m, o, 0, -14, 12, 4, 1.5, Q.remate)
	caja(m, o, 0, 14, 12, 4, 1.5, Q.remate)
	barraColumpio(m, o + Vector3.new(-6, 11, -24), o + Vector3.new(6, 11, -24), Q.poste)
	barraColumpio(m, o + Vector3.new(-6, 11, 24), o + Vector3.new(6, 11, 24), Q.poste)

	-- decoración: árboles por fuera del muro
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		arbol(m, o + Vector3.new(math.cos(a) * 100, 0, math.sin(a) * 80), i % 2 == 0 and Color3.fromRGB(196, 228, 190) or Color3.fromRGB(250, 210, 226))
	end

	local apariciones, puntos = {}, {}
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		table.insert(apariciones, o + Vector3.new(math.cos(a) * 60, 4, math.sin(a) * 42))
	end
	for x = -66, 66, 22 do
		for _, z in { -42, -24, 24, 42 } do
			table.insert(puntos, o + Vector3.new(x, 3, z))
		end
	end
	for _, z in { -30, 30 } do
		table.insert(puntos, o + Vector3.new(0, 3, z))
	end
	return { nombre = "Parque de calistenia", apariciones = apariciones, alturaMinima = o.Y - 30, puntos = puntos }
end

------------------------------------------------------------------------
-- Mapa 2: TORRE DE OBRAS (bucle vertical)
------------------------------------------------------------------------
--
--   Subes por los andamios o por las rampas entre plantas del edificio (4 plantas
--   abiertas), cruzas la azotea y bajas DESLIZANDO por la pluma inclinada de la grúa
--   hasta el tejado del edificio pequeño. De ahí saltas a los contenedores y al suelo
--   (rodando si caes de alto). Desde la planta 2 hay un tobogán de escombros.

local function obras(raiz, o)
	local m = Instance.new("Model")
	m.Name = "TorreObras"
	m.Parent = raiz

	local Q = {
		tierra = Color3.fromRGB(240, 218, 196), -- arena pastel
		hormigon = Color3.fromRGB(222, 216, 226),
		forjado = Color3.fromRGB(210, 204, 218),
		pilar = Color3.fromRGB(196, 188, 210),
		andamio = Color3.fromRGB(160, 170, 200),
		tablon = Color3.fromRGB(242, 210, 168),
		lona = Color3.fromRGB(180, 222, 206),
		amarillo = Color3.fromRGB(250, 226, 150),
		valla = Color3.fromRGB(250, 200, 214),
		contenedores = { Color3.fromRGB(250, 190, 190), Color3.fromRGB(180, 210, 245), Color3.fromRGB(190, 230, 200), Color3.fromRGB(230, 200, 245) },
	}

	local MX, MZ = 76, 76
	bloque(m, Vector3.new(MX * 2 + 40, 2, MZ * 2 + 40), o + Vector3.new(0, -1, 0), Q.tierra)
	recinto(m, o, MX, MZ, 16, Q.valla, Q.amarillo)

	-- EDIFICIO PRINCIPAL: 4 plantas de 14, abierto
	local E = o + Vector3.new(18, 0, -14)
	local H, A, PLANTAS = 14, 22, 4 -- altura de planta, mitad del lado
	for k = 1, PLANTAS do
		local y = k * H
		local este = (k % 2 == 1) -- en plantas impares el hueco de la rampa está al este
		if este then
			bloque(m, Vector3.new(32, 1.2, 44), E + Vector3.new(-6, y, 0), Q.forjado)
			bloque(m, Vector3.new(12, 1.2, 16), E + Vector3.new(16, y, 14), Q.forjado)
			-- rampa que llega a esta planta desde la de abajo
			rampa(m, E + Vector3.new(15.5, y - H + 0.6, -21), E + Vector3.new(15.5, y + 0.6, 6), 9, Q.tablon)
		else
			bloque(m, Vector3.new(32, 1.2, 44), E + Vector3.new(6, y, 0), Q.forjado)
			bloque(m, Vector3.new(12, 1.2, 16), E + Vector3.new(-16, y, -14), Q.forjado)
			rampa(m, E + Vector3.new(-15.5, y - H + 0.6, 21), E + Vector3.new(-15.5, y + 0.6, -6), 9, Q.tablon)
		end
		-- pilares de la planta de abajo (sin estorbar la rampa)
		for _, x in { -20, 0, 20 } do
			for _, z in { -20, 0, 20 } do
				local estorba = (este and x == 20 and z <= 0) or (not este and x == -20 and z >= 0)
				if not estorba then
					bloque(m, Vector3.new(2.5, H, 2.5), E + Vector3.new(x, y - H / 2, z), Q.pilar)
				end
			end
		end
		-- en cada planta (menos la azotea): un tabique para correr por él y dos vallas bajas
		if k < PLANTAS then
			local giro = (k % 2 == 0) and 0 or 90
			local cf = CFrame.new(E + Vector3.new(-2, y + 5.6, 2)) * CFrame.Angles(0, math.rad(giro), 0)
			bloque(m, Vector3.new(18, 10, 1.5), cf, Q.lona)
			caja(m, E, -12, -12, 8, 3, 1.5, Q.valla, y + 0.6)
			caja(m, E, 6, 14, 1.5, 3, 8, Q.valla, y + 0.6)
		end
	end
	-- planta baja: vallas y pilares ya puestos por la planta 1
	caja(m, E, -6, 8, 10, 3, 1.5, Q.valla)
	-- azotea: pretil bajo en dos lados (los otros abiertos para saltar)
	local top = PLANTAS * H
	bloque(m, Vector3.new(44, 2.5, 1), E + Vector3.new(0, top + 1.8, -A), Q.amarillo)
	bloque(m, Vector3.new(1, 2.5, 44), E + Vector3.new(A, top + 1.8, 0), Q.amarillo)
	-- lona en la cara norte: pared enorme para correr
	bloque(m, Vector3.new(44, top - 6, 0.6), E + Vector3.new(0, top / 2 + 1, A + 3), Q.lona)

	-- ANDAMIO en la cara oeste: tablones con huecos y barras para cruzarlos
	local xa = -A - 5
	for _, z in { -20, -6, 8, 22 } do
		for _, dx in { -2.5, 2.5 } do
			cilindro(m, E + Vector3.new(xa + dx, 0, z), E + Vector3.new(xa + dx, top, z), 0.5, Q.andamio)
		end
	end
	for nivel = 1, PLANTAS * 2 - 1 do
		local y = nivel * H / 2
		local hueco = (nivel % 2 == 0) and 8 or -8 -- el hueco cambia de lado
		bloque(m, Vector3.new(5, 0.6, 18), E + Vector3.new(xa, y, -hueco * 1.6), Q.tablon)
		bloque(m, Vector3.new(5, 0.6, 12), E + Vector3.new(xa, y, hueco * 1.9), Q.tablon)
		local b = cilindro(m, E + Vector3.new(xa - 2.5, y + 6, hueco * 0.4), E + Vector3.new(xa + 2.5, y + 6, hueco * 0.4), 0.5, P.barra)
		CollectionService:AddTag(b, "Barra")
	end

	-- EDIFICIO PEQUEÑO (2 plantas, paredes macizas para trepar)
	local S = o + Vector3.new(-42, 0, 40)
	caja(m, S, 0, 0, 24, 28, 24, Q.hormigon)
	bloque(m, Vector3.new(24.4, 1.5, 24.4), S + Vector3.new(0, 28.75, 0), Q.amarillo)
	caja(m, S, 14, -8, 4, 9, 6, Q.valla) -- escalón para empezar a trepar

	-- GRÚA: la pluma va inclinada de la azotea al tejado pequeño (bajar deslizando)
	local desde = E + Vector3.new(-A + 2, top + 0.6, A - 2)
	local hasta = S + Vector3.new(8, 29.5, -8)
	rampa(m, desde, hasta, 5, Q.amarillo)
	local mitad = (desde + hasta) / 2
	for _, d in { Vector3.new(2, 0, 2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, -2) } do
		cilindro(m, Vector3.new(mitad.X, o.Y, mitad.Z) + d, mitad + d + Vector3.new(0, 6, 0), 0.6, Q.amarillo)
	end
	bloque(m, Vector3.new(6, 4, 6), mitad + Vector3.new(0, 9, 0), Q.amarillo) -- cabina

	-- TOBOGÁN DE ESCOMBROS desde la planta 2
	rampa(m, E + Vector3.new(A, 2 * H + 0.6, 4), E + Vector3.new(A + 48, 0.4, 4), 8, Q.tablon)

	-- CONTENEDORES (vallas, escalar, trepar)
	local cont = {
		{ -14, 6, 0, 0 }, { -14, 6, 0, 1 }, -- doble, junto al edificio pequeño
		{ -20, 24, 90, 0 },
		{ 50, 40, 0, 0 },
		{ -46, -30, 90, 0 }, { -46, -30, 90, 1 },
		{ 0, 50, 90, 0 },
		{ 54, -50, 0, 0 },
	}
	for i, c in ipairs(cont) do
		local cf = CFrame.new(o + Vector3.new(c[1], 4.25 + c[4] * 8.5, c[2])) * CFrame.Angles(0, math.rad(c[3]), 0)
		bloque(m, Vector3.new(8, 8.5, 20), cf, Q.contenedores[i % #Q.contenedores + 1], { Material = Enum.Material.SmoothPlastic })
	end
	-- montones bajos (vallas)
	for _, p in { Vector3.new(-20, 0, -50), Vector3.new(30, 0, 40), Vector3.new(-60, 0, 0) } do
		caja(m, o, p.X, p.Z, 10, 3, 3, Q.valla)
	end

	local apariciones, puntos = {}, {}
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		table.insert(apariciones, o + Vector3.new(math.cos(a) * 58, 4, math.sin(a) * 58))
	end
	for x = -60, 60, 20 do
		for z = -60, 60, 20 do
			local dentroEdif = math.abs(x - 18) < 26 and math.abs(z + 14) < 26
			local dentroPeq = math.abs(x + 42) < 14 and math.abs(z - 40) < 14
			if not dentroEdif and not dentroPeq then
				table.insert(puntos, o + Vector3.new(x, 3, z))
			end
		end
	end
	for k = 1, PLANTAS do
		table.insert(puntos, E + Vector3.new(-8, k * H + 3, -8))
	end
	return { nombre = "Torre de obras", apariciones = apariciones, alturaMinima = o.Y - 30, puntos = puntos }
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
	-- la pista de pruebas queda en el centro (es donde apareces entre rondas)
	local prueba = pista(raiz)
	local lista = {
		parque(raiz, Vector3.new(0, 0, 450)),
		obras(raiz, Vector3.new(450, 0, 450)),
	}
	if SOLO_MOVIMIENTO then
		table.insert(lista, 1, prueba)
	end

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
