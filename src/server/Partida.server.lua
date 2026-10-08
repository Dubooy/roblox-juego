-- Partida: manotazo (con empujón), bots y rondas de pilla-pilla en dos mapas.
--
-- "Participante" = un Player o un bot (Model). Los dos guardan su equipo en el
-- atributo "Pillador" y se marcan con un Highlight rojo (pilla) o azul (huye).
--
-- Modos previstos: "Contagio" y "CoronaRobada". Se elegirán en el lobby más
-- adelante; de momento se juega siempre C.MODO_INICIAL. Los mapas se van alternando.
--
-- Estado público para el HUD (atributos de ReplicatedStorage):
--   Fase "Esperando" | "Preparando" | "Jugando" | "Fin", Modo, Mapa, Tiempo, Mensaje

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Mapas = require(script.Parent:WaitForChild("Mapas"))
local Bots = require(script.Parent:WaitForChild("Bots"))

local mapas = Mapas.construir()
local mapaActual = mapas[1]
local indiceMapa = 0

------------------------------------------------------------------------
-- Remotos
------------------------------------------------------------------------

local remotos = Instance.new("Folder")
remotos.Name = "Remotos"
remotos.Parent = ReplicatedStorage

local function remoto(nombre)
	local r = Instance.new("RemoteEvent")
	r.Name = nombre
	r.Parent = remotos
	return r
end

local Manotazo = remoto("Manotazo") -- cliente → servidor: dirección de la vista
local Empujon = remoto("Empujon") -- servidor → golpeado: vector de empujón
local Golpe = remoto("Golpe") -- servidor → todos: (modelo atacante, modelo golpeado, congelado) para efectos
local Congelar = remoto("Congelar") -- servidor → atacante: quedarse congelado (segundos)
local Cinematica = remoto("Cinematica") -- servidor → quien la ve: (atacante, golpeado, dirección, texto, motivo)

------------------------------------------------------------------------
-- Participantes (jugadores y bots)
------------------------------------------------------------------------

local function modeloDe(p)
	if p:IsA("Player") then
		return p.Character
	end
	return p
end

local function nombreDe(p)
	if p:IsA("Player") then
		return p.DisplayName
	end
	return p:GetAttribute("NombreVisible") or p.Name
end

local function raiz(p)
	local m = modeloDe(p)
	local hum = m and m:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0) then
		return nil
	end
	return m:FindFirstChild("HumanoidRootPart")
end

local function participantes()
	local lista = {}
	for _, p in Players:GetPlayers() do
		if raiz(p) then
			table.insert(lista, p)
		end
	end
	for _, b in Bots.lista() do
		table.insert(lista, b)
	end
	return lista
end

local function esPillador(p)
	return p:GetAttribute("Pillador") == true
end

local function colocar(p, posicion)
	local m = modeloDe(p)
	if m then
		m:PivotTo(CFrame.new(posicion) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
		local r = m:FindFirstChild("HumanoidRootPart")
		if r then
			r.AssemblyLinearVelocity = Vector3.zero
			r:SetAttribute("Teletransportado", true) -- que el anti-trampas no lo cuente
		end
	end
end

local COLOR_PILLADOR = Color3.fromRGB(255, 70, 70)
local COLOR_HUYE = Color3.fromRGB(80, 200, 255)

local function marcar(p, pillador)
	p:SetAttribute("Pillador", pillador)
	local m = modeloDe(p)
	if not m then
		return
	end
	local h = m:FindFirstChild("MarcaEquipo")
	if not h then
		h = Instance.new("Highlight")
		h.Name = "MarcaEquipo"
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- se ve a través de las paredes
		h.FillTransparency = 0.75
		h.Parent = m
	end
	h.FillColor = pillador and COLOR_PILLADOR or COLOR_HUYE
	h.OutlineColor = h.FillColor
end

local function quitarMarca(p)
	p:SetAttribute("Pillador", nil)
	local m = modeloDe(p)
	local h = m and m:FindFirstChild("MarcaEquipo")
	if h then
		h:Destroy()
	end
end

local function fijarFase(fase, tiempo, mensaje)
	ReplicatedStorage:SetAttribute("Fase", fase)
	ReplicatedStorage:SetAttribute("Tiempo", tiempo or 0)
	ReplicatedStorage:SetAttribute("Mensaje", mensaje or "")
end

------------------------------------------------------------------------
-- Modos
------------------------------------------------------------------------

local Modos = {}

-- Contagio: uno empieza pillando; cada uno que toca pasa a pillar.
Modos.Contagio = {
	nombre = "Contagio",
	empezar = function(lista)
		local primero = lista[math.random(#lista)]
		for _, p in lista do
			marcar(p, p == primero)
		end
		return { primero }, nombreDe(primero) .. " pilla. ¡Corred!"
	end,
	alGolpear = function(atacante, golpeado)
		if esPillador(atacante) and not esPillador(golpeado) then
			marcar(golpeado, true)
			return nombreDe(golpeado) .. " ha sido pillado"
		end
		return nil
	end,
	terminada = function(lista)
		for _, p in lista do
			if not esPillador(p) then
				return false
			end
		end
		return true
	end,
	resultado = function(lista)
		local libres = {}
		for _, p in lista do
			if not esPillador(p) then
				table.insert(libres, nombreDe(p))
			end
		end
		if #libres == 0 then
			return "¡Los pilladores ganan! No queda nadie"
		end
		return "¡Sobreviven " .. table.concat(libres, ", ") .. "!"
	end,
}

-- CoronaRobada: pendiente (se elegirá en el lobby).

------------------------------------------------------------------------
-- Manotazo
------------------------------------------------------------------------

local ultimoManotazo = {} -- [participante] = os.clock()
local enJuego = {} -- [participante] = true durante la ronda
local modoActual = nil
local faseJugando = false

local function activos()
	local lista = {}
	for p in enJuego do
		if (p:IsA("Player") and p.Parent == Players) or (not p:IsA("Player") and p.Parent) then
			table.insert(lista, p)
		end
	end
	return lista
end

local inmuneHasta = {} -- [participante] = os.clock(): en plena cinemática nadie le puede tocar

local function enElAire(p)
	local m = modeloDe(p)
	local hum = m and m:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.FloorMaterial == Enum.Material.Air
end

local function velocidadPlana(p)
	local r = raiz(p)
	if not r then
		return 0
	end
	local v = r.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- Congela a un participante "segundos" y después (si hay empuje) lo lanza.
local function congelarYLanzar(p, segundos, empuje)
	if p:IsA("Player") then
		if empuje then
			Empujon:FireClient(p, empuje, segundos)
		else
			Congelar:FireClient(p, segundos)
		end
	else
		local r = raiz(p)
		if not r then
			return
		end
		r.Anchored = true
		p:SetAttribute("AturdidoHasta", os.clock() + segundos + 0.6)
		task.delay(segundos, function()
			if r.Parent then
				r.Anchored = false
				if empuje then
					Bots.empujar(p, empuje)
				end
			end
		end)
	end
end

-- infoCliente: { combo } que manda el jugador (para saber si venía encadenando)
local function golpear(atacante, vista, infoCliente)
	if typeof(vista) ~= "Vector3" or vista.Magnitude < 0.5 then
		return
	end
	local ahora = os.clock()
	if ahora - (ultimoManotazo[atacante] or -math.huge) < C.MANOTAZO_ESPERA * 0.8 then
		return
	end
	if (inmuneHasta[atacante] or 0) > ahora then
		return
	end
	ultimoManotazo[atacante] = ahora

	local r = raiz(atacante)
	if not r then
		return
	end
	vista = vista.Unit

	-- el participante más cercano delante del atacante (con margen por la latencia)
	local mejor, mejorDist = nil, math.huge
	for _, otro in participantes() do
		if otro ~= atacante and (inmuneHasta[otro] or 0) <= ahora then
			local ro = raiz(otro)
			if ro then
				local d = ro.Position - r.Position
				local dist = d.Magnitude
				if dist > 0 and dist <= C.MANOTAZO_ALCANCE + 3 and d.Unit:Dot(vista) >= C.MANOTAZO_ANGULO - 0.15 and dist < mejorDist then
					mejor, mejorDist = otro, dist
				end
			end
		end
	end
	if not mejor then
		return
	end

	-- ¿Cuenta como pillado? (solo en ronda y si el modo lo dice)
	local aviso = nil
	if faseJugando and modoActual and enJuego[atacante] and enJuego[mejor] then
		aviso = modoActual.alGolpear(atacante, mejor)
	end

	-- ¿Es épico? Hacen falta C.EPICO_CONDICIONES de: en el aire, muy rápido, tras un combo.
	-- El último pillado de la ronda siempre es épico (y lo ve todo el mundo).
	local epico, paraTodos, motivo = false, false, nil
	if aviso then
		local combo = (typeof(infoCliente) == "table" and tonumber(infoCliente.combo)) or 0
		local condiciones = {}
		if enElAire(atacante) or enElAire(mejor) then
			table.insert(condiciones, "¡EN EL AIRE!")
		end
		if velocidadPlana(atacante) >= C.EPICO_VELOCIDAD then
			table.insert(condiciones, "¡A TODA VELOCIDAD!")
		end
		if combo >= C.EPICO_COMBO then
			table.insert(condiciones, "¡COMBO x" .. math.floor(combo) .. "!")
		end
		local ultimo = modoActual.terminada(activos())
		if ultimo then
			epico, paraTodos, motivo = true, true, "¡ÚLTIMO SUPERVIVIENTE!"
		elseif #condiciones >= C.EPICO_CONDICIONES then
			epico, motivo = true, table.concat(condiciones, "  ")
		end
	end

	-- empujón: hacia donde miras, con una parte de tu velocidad (más fuerte si es épico)
	local plano = Vector3.new(vista.X, 0, vista.Z)
	if plano.Magnitude < 0.1 then
		local d = raiz(mejor).Position - r.Position
		plano = Vector3.new(d.X, 0, d.Z)
	end
	plano = plano.Unit
	local fuerza = C.MANOTAZO_EMPUJE + velocidadPlana(atacante) * C.MANOTAZO_EMPUJE_EXTRA_VEL
	local arriba = C.MANOTAZO_EMPUJE_ARRIBA
	if aviso then
		fuerza *= C.PILLADO_EMPUJE_EXTRA
		arriba *= C.PILLADO_EMPUJE_EXTRA
	end
	if epico then
		fuerza *= C.EPICO_EMPUJE_EXTRA
		arriba *= C.EPICO_EMPUJE_EXTRA
	end
	local empuje = plano * fuerza + Vector3.new(0, arriba, 0)

	-- congelado: un instante en un golpe normal; en uno épico, el pillado espera al primer
	-- plano de la cinemática y el que pilla se queda quieto toda la cinemática
	local congeladoVictima = aviso and C.CONGELADO_PILLAR or C.CONGELADO_GOLPE
	local congeladoAtacante = congeladoVictima
	if epico then
		congeladoVictima = C.CINE_PLANO1
		congeladoAtacante = C.CINE_DURACION
		inmuneHasta[atacante] = ahora + C.CINE_DURACION
		inmuneHasta[mejor] = ahora + C.CINE_DURACION
	end
	congelarYLanzar(mejor, congeladoVictima, empuje)
	congelarYLanzar(atacante, congeladoAtacante, nil)

	Golpe:FireAllClients(modeloDe(atacante), modeloDe(mejor), congeladoVictima, aviso ~= nil)

	if epico then
		local texto = "¡" .. string.upper(nombreDe(mejor)) .. " PILLADO!"
		local args = { modeloDe(atacante), modeloDe(mejor), plano, texto, motivo or "" }
		if paraTodos then
			Cinematica:FireAllClients(table.unpack(args))
		else
			for _, p in { atacante, mejor } do
				if p:IsA("Player") then
					Cinematica:FireClient(p, table.unpack(args))
				end
			end
		end
	end

	if aviso then
		ReplicatedStorage:SetAttribute("Mensaje", aviso)
	end
end

Manotazo.OnServerEvent:Connect(golpear)

------------------------------------------------------------------------
-- Bots
------------------------------------------------------------------------

Bots.empezar({
	participantes = participantes,
	raiz = raiz,
	esPillador = esPillador,
	puntos = function()
		return mapaActual.puntos
	end,
	golpear = golpear,
	activo = function()
		return faseJugando
	end,
})

local function ajustarBots()
	local reales = #Players:GetPlayers()
	if C.SOLO_MOVIMIENTO then
		reales = C.PARTICIPANTES_OBJETIVO
	end
	Bots.ajustar(math.max(0, C.PARTICIPANTES_OBJETIVO - reales), mapaActual.apariciones[1])
end

Players.PlayerAdded:Connect(ajustarBots)
Players.PlayerRemoving:Connect(function(p)
	enJuego[p] = nil
	ultimoManotazo[p] = nil
	inmuneHasta[p] = nil
	task.defer(ajustarBots)
end)
ajustarBots()

------------------------------------------------------------------------
-- Caídas y reapariciones
------------------------------------------------------------------------

local function aparicionAleatoria()
	local a = mapaActual.apariciones
	return a[math.random(#a)]
end

task.spawn(function()
	while true do
		for _, p in participantes() do
			local r = raiz(p)
			if r and r.Position.Y < mapaActual.alturaMinima then
				colocar(p, aparicionAleatoria())
			end
		end
		task.wait(0.3)
	end
end)

-- quien reaparece (o entra a mitad) va al mapa actual y conserva su marca
local function alPersonaje(p)
	task.wait(0.2)
	colocar(p, aparicionAleatoria())
	if faseJugando and enJuego[p] then
		marcar(p, esPillador(p))
	end
end
local function conectar(p)
	p.CharacterAdded:Connect(function()
		alPersonaje(p)
	end)
	if p.Character then
		task.spawn(alPersonaje, p)
	end
end
Players.PlayerAdded:Connect(conectar)
for _, p in Players:GetPlayers() do
	conectar(p)
end

------------------------------------------------------------------------
-- Rondas
------------------------------------------------------------------------

local function anclar(lista, anclado)
	for _, p in lista do
		local r = raiz(p)
		if r then
			r.Anchored = anclado
		end
	end
end


ReplicatedStorage:SetAttribute("Modo", C.MODO_INICIAL)
ReplicatedStorage:SetAttribute("Mapa", mapaActual.nombre)

if C.SOLO_MOVIMIENTO then
	-- modo de pruebas: nada de rondas
	fijarFase("Esperando", 0, "")
	return
end

while true do
	-- 1. Siguiente mapa
	indiceMapa = indiceMapa % #mapas + 1
	mapaActual = mapas[indiceMapa]
	ReplicatedStorage:SetAttribute("Mapa", mapaActual.nombre)

	-- Si no hay con quién jugar (por ejemplo, si los bots no se han podido crear),
	-- MODO LIBRE: te lleva al mapa para que lo recorras, y cambia de mapa cada rato.
	if #participantes() < C.JUGADORES_MINIMOS then
		for _, p in participantes() do
			colocar(p, aparicionAleatoria())
		end
		local hasta = os.clock() + C.MODO_LIBRE_DURACION
		while #participantes() < C.JUGADORES_MINIMOS and os.clock() < hasta do
			fijarFase("Esperando", math.ceil(hasta - os.clock()), "Modo libre · " .. mapaActual.nombre)
			task.wait(1)
		end
		if #participantes() < C.JUGADORES_MINIMOS then
			continue -- siguiente mapa
		end
	end

	-- 2. Cuenta atrás
	ReplicatedStorage:SetAttribute("Mapa", mapaActual.nombre)
	modoActual = Modos[C.MODO_INICIAL] or Modos.Contagio
	ReplicatedStorage:SetAttribute("Modo", modoActual.nombre)

	-- todos al mapa nuevo
	for _, p in participantes() do
		colocar(p, aparicionAleatoria())
	end
	for t = C.PREPARACION, 1, -1 do
		fijarFase("Preparando", t, mapaActual.nombre .. " · " .. modoActual.nombre .. "\nEmpieza en " .. t)
		task.wait(1)
	end

	-- 3. Empezar
	local lista = participantes()
	enJuego = {}
	local apar = table.clone(mapaActual.apariciones)
	for i, p in lista do
		enJuego[p] = true
		colocar(p, apar[(i - 1) % #apar + 1])
	end
	local pilladores, mensaje = modoActual.empezar(lista)
	faseJugando = true

	-- ventaja: los pilladores esperan quietos unos segundos
	anclar(pilladores, true)
	for t = C.VENTAJA_HUIDA, 1, -1 do
		fijarFase("Jugando", C.DURACION_RONDA, mensaje .. " (sale en " .. t .. ")")
		task.wait(1)
	end
	anclar(pilladores, false)
	fijarFase("Jugando", C.DURACION_RONDA, "")

	-- 4. Ronda
	local fin = os.clock() + C.DURACION_RONDA
	while os.clock() < fin do
		local a = activos()
		if #a < C.JUGADORES_MINIMOS or modoActual.terminada(a) then
			break
		end
		ReplicatedStorage:SetAttribute("Tiempo", math.ceil(fin - os.clock()))
		task.wait(0.25)
	end

	-- 5. Resultado
	faseJugando = false
	fijarFase("Fin", C.PAUSA_FINAL, modoActual.resultado(activos()))
	task.wait(C.PAUSA_FINAL)
	for _, p in participantes() do
		quitarMarca(p)
	end
	for p in enJuego do
		if p.Parent then
			quitarMarca(p)
		end
	end
	enJuego = {}
end
