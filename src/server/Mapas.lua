-- Los mapas del pilla-pilla. Se construyen por código al arrancar el servidor
-- (así no hace falta modelar nada en Studio). Cada mapa es pequeño y vertical,
-- con paredes largas para correr por ellas.
--
-- Mapas.construir() crea todos y devuelve una lista:
--   { nombre, centro (Vector3), apariciones = {Vector3}, alturaMinima, puntos = {Vector3} }
-- "puntos" son sitios repartidos por el mapa que usan los bots para moverse.

local Mapas = {}

------------------------------------------------------------------------
-- Ayudas para construir
------------------------------------------------------------------------

local function parte(padre, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Parent = padre
	return p
end

local function bloque(padre, tam, pos, color, material, extra)
	local props = { Size = tam, CFrame = typeof(pos) == "CFrame" and pos or CFrame.new(pos), Color = color, Material = material or Enum.Material.SmoothPlastic }
	for k, v in extra or {} do
		props[k] = v
	end
	return parte(padre, props)
end

-- barra cilíndrica entre dos puntos
local function barra(padre, a, b, grosor, color)
	local largo = (b - a).Magnitude
	local p = parte(padre, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(largo, grosor, grosor),
		CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Material = Enum.Material.Metal,
	})
	return p
end

local function rampa(padre, desde, hasta, ancho, color, material)
	-- rampa (cuña aplanada) de "desde" a "hasta", ambos a nivel de la superficie
	local dir = hasta - desde
	local plano = Vector3.new(dir.X, 0, dir.Z)
	local largo = dir.Magnitude
	local cf = CFrame.lookAt((desde + hasta) / 2, (desde + hasta) / 2 + dir)
	return bloque(padre, Vector3.new(ancho, 1, largo), cf * CFrame.new(0, -0.5, 0), color, material)
end

------------------------------------------------------------------------
-- Mapa 1: Parque de calistenia y parkour
------------------------------------------------------------------------

local function parque(raiz, origen)
	local m = Instance.new("Model")
	m.Name = "ParqueCalistenia"
	m.Parent = raiz
	local o = origen

	local CAUCHO = Color3.fromRGB(64, 120, 88)
	local CAUCHO2 = Color3.fromRGB(196, 92, 60)
	local HORMIGON = Color3.fromRGB(190, 186, 178)
	local METAL = Color3.fromRGB(40, 44, 52)
	local AMARILLO = Color3.fromRGB(240, 196, 60)
	local MADERA = Color3.fromRGB(160, 116, 74)

	-- suelo de caucho con césped alrededor
	bloque(m, Vector3.new(260, 2, 260), o + Vector3.new(0, -1, 0), Color3.fromRGB(96, 160, 72), Enum.Material.Grass)
	bloque(m, Vector3.new(170, 0.4, 170), o + Vector3.new(0, 0.2, 0), CAUCHO, Enum.Material.Fabric)
	for i = -2, 2 do
		bloque(m, Vector3.new(170, 0.42, 3), o + Vector3.new(0, 0.21, i * 34), CAUCHO2, Enum.Material.Fabric)
	end

	-- valla perimetral (muy alta para no salir)
	for _, lado in { { Vector3.new(0, 0, 90), Vector3.new(184, 40, 1) }, { Vector3.new(0, 0, -90), Vector3.new(184, 40, 1) }, { Vector3.new(90, 0, 0), Vector3.new(1, 40, 184) }, { Vector3.new(-90, 0, 0), Vector3.new(1, 40, 184) } } do
		bloque(m, lado[2], o + lado[1] + Vector3.new(0, 20, 0), METAL, Enum.Material.DiamondPlate, { Transparency = 0.6 })
	end

	-- 1. Muros de parkour para correr por ellos (pares paralelos con hueco en medio)
	local muros = {
		{ Vector3.new(-50, 0, -55), 0 },
		{ Vector3.new(50, 0, 55), 0 },
		{ Vector3.new(-62, 0, 30), 90 },
		{ Vector3.new(62, 0, -30), 90 },
	}
	for _, mu in muros do
		local cf = CFrame.new(o + mu[1]) * CFrame.Angles(0, math.rad(mu[2]), 0)
		bloque(m, Vector3.new(44, 16, 2), cf * CFrame.new(0, 8, -9), HORMIGON, Enum.Material.Concrete)
		bloque(m, Vector3.new(44, 16, 2), cf * CFrame.new(0, 8, 9), HORMIGON, Enum.Material.Concrete)
		-- franja de color en lo alto, para ver bien los muros
		bloque(m, Vector3.new(44, 1, 2.2), cf * CFrame.new(0, 16, -9), AMARILLO)
		bloque(m, Vector3.new(44, 1, 2.2), cf * CFrame.new(0, 16, 9), AMARILLO)
	end

	-- 2. Torre central de barras: tres pisos de plataformas unidas por barras
	local tc = o + Vector3.new(0, 0, 0)
	for _, x in { -14, 14 } do
		for _, z in { -14, 14 } do
			barra(m, tc + Vector3.new(x, 0, z), tc + Vector3.new(x, 38, z), 1.4, METAL)
		end
	end
	for i, y in { 10, 20, 30 } do
		local hueco = (i % 2 == 0) and -1 or 1
		-- plataforma con un hueco por el que subir saltando
		bloque(m, Vector3.new(30, 1, 18), tc + Vector3.new(0, y, 6 * hueco), MADERA, Enum.Material.WoodPlanks)
		for _, x in { -14, 14 } do
			barra(m, tc + Vector3.new(x, y + 4, -14), tc + Vector3.new(x, y + 4, 14), 0.8, METAL)
		end
	end
	-- techo de la torre: el sitio más alto del parque
	bloque(m, Vector3.new(32, 1, 32), tc + Vector3.new(0, 39, 0), CAUCHO2, Enum.Material.Fabric)
	-- cajas para subir a la primera plataforma
	bloque(m, Vector3.new(8, 4, 8), tc + Vector3.new(-22, 2, 6), MADERA, Enum.Material.WoodPlanks)
	bloque(m, Vector3.new(8, 7, 8), tc + Vector3.new(-22, 3.5, -4), MADERA, Enum.Material.WoodPlanks)
	bloque(m, Vector3.new(8, 4, 8), tc + Vector3.new(22, 2, -6), MADERA, Enum.Material.WoodPlanks)

	-- 3. Barras de dominadas en fila (para pasar por debajo deslizando o saltar encima)
	for i = 0, 4 do
		local z = -70 + i * 9
		local x = 20
		barra(m, o + Vector3.new(x - 6, 0, z), o + Vector3.new(x - 6, 9 + i, z), 0.8, METAL)
		barra(m, o + Vector3.new(x + 6, 0, z), o + Vector3.new(x + 6, 9 + i, z), 0.8, METAL)
		barra(m, o + Vector3.new(x - 6, 9 + i, z), o + Vector3.new(x + 6, 9 + i, z), 0.6, METAL)
	end

	-- 4. Escalera horizontal (pasamanos) elevada que hace de puente
	local a, b = o + Vector3.new(-40, 0, 70), o + Vector3.new(-40, 0, 40)
	for _, x in { -3, 3 } do
		barra(m, a + Vector3.new(x, 0, 0), a + Vector3.new(x, 12, 0), 0.8, METAL)
		barra(m, b + Vector3.new(x, 0, 0), b + Vector3.new(x, 12, 0), 0.8, METAL)
		barra(m, a + Vector3.new(x, 12, 0), b + Vector3.new(x, 12, 0), 0.7, METAL)
	end
	for z = 0, 10 do
		barra(m, a + Vector3.new(-3, 12, -z * 3), a + Vector3.new(3, 12, -z * 3), 0.4, AMARILLO)
	end

	-- 5. Cajones pliométricos escalonados
	for i, h in { 3, 5, 8, 11, 14 } do
		bloque(m, Vector3.new(7, h, 7), o + Vector3.new(-75 + i * 9, h / 2, -20), i % 2 == 0 and CAUCHO2 or MADERA, Enum.Material.WoodPlanks)
	end

	-- 6. Paralelas y bancos inclinados (para deslizar)
	for i = 0, 2 do
		local base = o + Vector3.new(70, 0, 0 + i * 14)
		barra(m, base + Vector3.new(-8, 4, -2), base + Vector3.new(8, 4, -2), 0.6, METAL)
		barra(m, base + Vector3.new(-8, 4, 2), base + Vector3.new(8, 4, 2), 0.6, METAL)
		for _, x in { -8, 8 } do
			barra(m, base + Vector3.new(x, 0, -2), base + Vector3.new(x, 4, -2), 0.6, METAL)
			barra(m, base + Vector3.new(x, 0, 2), base + Vector3.new(x, 4, 2), 0.6, METAL)
		end
	end
	rampa(m, o + Vector3.new(30, 0.4, 20), o + Vector3.new(30, 9, 44), 10, HORMIGON, Enum.Material.Concrete)
	bloque(m, Vector3.new(10, 9, 14), o + Vector3.new(30, 4.5, 51), HORMIGON, Enum.Material.Concrete)

	-- 7. Árboles de decoración por fuera
	for i = 0, 11 do
		local ang = i / 12 * math.pi * 2
		local p = o + Vector3.new(math.cos(ang) * 115, 0, math.sin(ang) * 115)
		bloque(m, Vector3.new(2.5, 14, 2.5), p + Vector3.new(0, 7, 0), Color3.fromRGB(110, 76, 50), Enum.Material.Wood)
		parte(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(14, 14, 14), Position = p + Vector3.new(0, 18, 0), Color = Color3.fromRGB(70, 140, 60), Material = Enum.Material.Grass })
	end

	local apariciones, puntos = {}, {}
	for i = 0, 7 do
		local ang = i / 8 * math.pi * 2
		table.insert(apariciones, o + Vector3.new(math.cos(ang) * 60, 4, math.sin(ang) * 60))
	end
	for x = -70, 70, 28 do
		for z = -70, 70, 28 do
			table.insert(puntos, o + Vector3.new(x, 3, z))
		end
	end
	table.insert(puntos, tc + Vector3.new(0, 12, 6))
	table.insert(puntos, tc + Vector3.new(0, 41, 0))

	return { nombre = "Parque de calistenia", modelo = m, centro = o, apariciones = apariciones, alturaMinima = o.Y - 30, puntos = puntos }
end

------------------------------------------------------------------------
-- Mapa 2: Torre de obras
------------------------------------------------------------------------

local function obras(raiz, origen)
	local m = Instance.new("Model")
	m.Name = "TorreObras"
	m.Parent = raiz
	local o = origen

	local TIERRA = Color3.fromRGB(150, 118, 84)
	local HORMIGON = Color3.fromRGB(168, 166, 160)
	local ACERO = Color3.fromRGB(214, 120, 40)
	local ANDAMIO = Color3.fromRGB(110, 116, 126)
	local TABLON = Color3.fromRGB(176, 140, 90)
	local AMARILLO = Color3.fromRGB(245, 200, 40)
	local AZUL = Color3.fromRGB(40, 90, 160)

	-- solar de obra
	bloque(m, Vector3.new(220, 2, 220), o + Vector3.new(0, -1, 0), TIERRA, Enum.Material.Ground)
	for _, lado in { { Vector3.new(0, 0, 80), Vector3.new(164, 40, 1) }, { Vector3.new(0, 0, -80), Vector3.new(164, 40, 1) }, { Vector3.new(80, 0, 0), Vector3.new(1, 40, 164) }, { Vector3.new(-80, 0, 0), Vector3.new(1, 40, 164) } } do
		bloque(m, lado[2], o + lado[1] + Vector3.new(0, 20, 0), Color3.fromRGB(230, 230, 230), Enum.Material.SmoothPlastic, { Transparency = 0.7 })
	end

	-- el edificio: 6 forjados de 56x56, 16 de altura entre plantas
	local ALTURA, LADO, PISOS = 16, 56, 6
	for piso = 0, PISOS do
		local y = piso * ALTURA
		if piso > 0 then
			-- forjado con un hueco de escalera que cambia de esquina en cada planta
			local hx = (piso % 2 == 0) and 1 or -1
			bloque(m, Vector3.new(LADO, 1.2, LADO - 14), o + Vector3.new(0, y, -7 * hx), HORMIGON, Enum.Material.Concrete)
			bloque(m, Vector3.new(LADO - 16, 1.2, 14), o + Vector3.new(-8 * hx, y, (LADO / 2 - 7) * hx), HORMIGON, Enum.Material.Concrete)
		end
		if piso < PISOS then
			-- pilares
			for _, x in { -26, 0, 26 } do
				for _, z in { -26, 0, 26 } do
					if not (x == 0 and z == 0) then
						bloque(m, Vector3.new(2.5, ALTURA, 2.5), o + Vector3.new(x, y + ALTURA / 2, z), HORMIGON, Enum.Material.Concrete)
					end
				end
			end
			-- tabiques sueltos para correr por ellos (cambian de sitio en cada planta)
			local giro = piso * 47 % 180
			local cf = CFrame.new(o + Vector3.new(0, y + 6.5, 0)) * CFrame.Angles(0, math.rad(giro), 0)
			bloque(m, Vector3.new(30, 11, 1.5), cf * CFrame.new(0, 0, -11), AZUL, Enum.Material.Brick)
			bloque(m, Vector3.new(30, 11, 1.5), cf * CFrame.new(0, 0, 11), AZUL, Enum.Material.Brick)
			-- rampa de una planta a la siguiente dentro del hueco
			local hx = ((piso + 1) % 2 == 0) and 1 or -1
			local ini = o + Vector3.new((LADO / 2 - 10) * hx, y + 0.6, (LADO / 2 - 30) * hx)
			local fin = o + Vector3.new((LADO / 2 - 10) * hx, y + ALTURA + 0.6, (LADO / 2 - 2) * hx)
			rampa(m, ini, fin, 12, TABLON, Enum.Material.WoodPlanks)
		end
	end
	-- azotea con barandilla baja
	local top = PISOS * ALTURA
	for _, cfg in { { Vector3.new(0, 0, 28), Vector3.new(56, 3, 1) }, { Vector3.new(0, 0, -28), Vector3.new(56, 3, 1) }, { Vector3.new(28, 0, 0), Vector3.new(1, 3, 56) }, { Vector3.new(-28, 0, 0), Vector3.new(1, 3, 56) } } do
		bloque(m, cfg[2], o + cfg[1] + Vector3.new(0, top + 2, 0), AMARILLO)
	end

	-- andamios por fuera, en dos caras: plataformas de tablones cada media planta
	for _, cara in { 1, -1 } do
		local x = cara * (LADO / 2 + 6)
		for z = -24, 24, 12 do
			barra(m, o + Vector3.new(x - 3, 0, z), o + Vector3.new(x - 3, top, z), 0.5, ANDAMIO)
			barra(m, o + Vector3.new(x + 3, 0, z), o + Vector3.new(x + 3, top, z), 0.5, ANDAMIO)
		end
		for nivel = 1, PISOS * 2 - 1 do
			local y = nivel * ALTURA / 2
			-- tablones a tramos, alternando, para obligar a saltar
			local desfase = (nivel % 2 == 0) and 6 or -6
			bloque(m, Vector3.new(6, 0.6, 22), o + Vector3.new(x, y, -14 + desfase), TABLON, Enum.Material.WoodPlanks)
			bloque(m, Vector3.new(6, 0.6, 14), o + Vector3.new(x, y, 18 + desfase), TABLON, Enum.Material.WoodPlanks)
			barra(m, o + Vector3.new(x + 3, y + 3.5, -24), o + Vector3.new(x + 3, y + 3.5, 24), 0.4, ANDAMIO)
		end
	end
	-- lona en la otra cara: una pared enorme para correr
	bloque(m, Vector3.new(LADO, top - 4, 0.6), o + Vector3.new(0, top / 2, LADO / 2 + 5), Color3.fromRGB(60, 140, 90), Enum.Material.Fabric)
	bloque(m, Vector3.new(LADO, top - 4, 0.6), o + Vector3.new(0, top / 2, -LADO / 2 - 5), Color3.fromRGB(60, 140, 90), Enum.Material.Fabric)

	-- grúa torre al lado, con la pluma pasando por encima de la azotea
	local g = o + Vector3.new(-58, 0, -50)
	for _, dx in { -2, 2 } do
		for _, dz in { -2, 2 } do
			barra(m, g + Vector3.new(dx, 0, dz), g + Vector3.new(dx, top + 24, dz), 0.6, AMARILLO)
		end
	end
	for y = 4, top + 20, 8 do
		bloque(m, Vector3.new(5, 0.4, 5), g + Vector3.new(0, y, 0), AMARILLO, Enum.Material.DiamondPlate)
	end
	-- la pluma: una pasarela larga a gran altura
	local pluma = CFrame.lookAt(g + Vector3.new(0, top + 24, 0), o + Vector3.new(30, top + 24, 40))
	bloque(m, Vector3.new(4, 1, 120), pluma * CFrame.new(0, 0, -50), AMARILLO, Enum.Material.DiamondPlate)
	bloque(m, Vector3.new(6, 4, 14), pluma * CFrame.new(0, -2, 16), HORMIGON, Enum.Material.Concrete) -- contrapeso
	-- carga colgando a mitad de pluma (plataforma de paso)
	bloque(m, Vector3.new(12, 1, 8), pluma * CFrame.new(0, -14, -60), TABLON, Enum.Material.WoodPlanks)
	barra(m, (pluma * CFrame.new(0, 0, -60)).Position, (pluma * CFrame.new(0, -14, -60)).Position, 0.3, Color3.fromRGB(30, 30, 30))

	-- contenedores y vigas por el suelo
	local colores = { Color3.fromRGB(180, 50, 40), Color3.fromRGB(40, 110, 170), Color3.fromRGB(60, 140, 70) }
	for i = 0, 5 do
		local ang = i / 6 * math.pi * 2 + 0.4
		local p = o + Vector3.new(math.cos(ang) * 58, 0, math.sin(ang) * 58)
		local cf = CFrame.new(p) * CFrame.Angles(0, ang, 0)
		bloque(m, Vector3.new(8, 8.5, 20), cf * CFrame.new(0, 4.25, 0), colores[i % 3 + 1], Enum.Material.CorrodedMetal)
		if i % 2 == 0 then
			bloque(m, Vector3.new(8, 8.5, 20), cf * CFrame.new(0, 12.75, 3), colores[(i + 1) % 3 + 1], Enum.Material.CorrodedMetal)
		end
	end
	for i = 0, 3 do
		bloque(m, Vector3.new(1.5, 2, 26), CFrame.new(o + Vector3.new(44, 1 + i * 2, -10 + i)) * CFrame.Angles(0, math.rad(i * 12), 0), ACERO, Enum.Material.Metal)
	end

	local apariciones, puntos = {}, {}
	for i = 0, 7 do
		local ang = i / 8 * math.pi * 2
		table.insert(apariciones, o + Vector3.new(math.cos(ang) * 45, 4, math.sin(ang) * 45))
	end
	for piso = 0, PISOS do
		for _, x in { -18, 18 } do
			for _, z in { -18, 18 } do
				table.insert(puntos, o + Vector3.new(x, piso * ALTURA + 3, z))
			end
		end
	end
	for i = 0, 7 do
		local ang = i / 8 * math.pi * 2
		table.insert(puntos, o + Vector3.new(math.cos(ang) * 50, 3, math.sin(ang) * 50))
	end

	return { nombre = "Torre de obras", modelo = m, centro = o, apariciones = apariciones, alturaMinima = o.Y - 30, puntos = puntos }
end

------------------------------------------------------------------------

function Mapas.construir()
	-- quitar lo que trae la plantilla Baseplate
	for _, nombre in { "Baseplate", "SpawnLocation", "Mapas" } do
		local v = workspace:FindFirstChild(nombre)
		if v then
			v:Destroy()
		end
	end
	local raiz = Instance.new("Folder")
	raiz.Name = "Mapas"
	raiz.Parent = workspace

	local lista = {
		parque(raiz, Vector3.new(0, 0, 0)),
		obras(raiz, Vector3.new(600, 0, 0)),
	}

	-- aparición entre rondas: en el parque
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 0.5, 70)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = raiz

	local luz = game:GetService("Lighting")
	luz.ClockTime = 15.5
	luz.Brightness = 2.5
	luz.OutdoorAmbient = Color3.fromRGB(140, 140, 150)

	return lista
end

return Mapas
