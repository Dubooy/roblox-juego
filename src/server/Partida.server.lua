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
local Golpe = remoto("Golpe") -- servidor → todos: (modelo atacante, modelo golpeado) para efectos

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

local function golpear(atacante, vista)
	if typeof(vista) ~= "Vector3" or vista.Magnitude < 0.5 then
		return
	end
	local ahora = os.clock()
	if ahora - (ultimoManotazo[atacante] or -math.huge) < C.MANOTAZO_ESPERA * 0.8 then
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
		if otro ~= atacante then
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

	local plano = Vector3.new(vista.X, 0, vista.Z)
	if plano.Magnitude < 0.1 then
		local d = raiz(mejor).Position - r.Position
		plano = Vector3.new(d.X, 0, d.Z)
	end
	plano = plano.Unit
	local velAtacante = Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z).Magnitude
	local fuerza = C.MANOTAZO_EMPUJE + velAtacante * C.MANOTAZO_EMPUJE_EXTRA_VEL
	local empuje = plano * fuerza + Vector3.new(0, C.MANOTAZO_EMPUJE_ARRIBA, 0)

	if mejor:IsA("Player") then
		Empujon:FireClient(mejor, empuje)
	else
		Bots.empujar(mejor, empuje)
	end
	Golpe:FireAllClients(modeloDe(atacante), modeloDe(mejor))

	if faseJugando and modoActual and enJuego[atacante] and enJuego[mejor] then
		local aviso = modoActual.alGolpear(atacante, mejor)
		if aviso then
			ReplicatedStorage:SetAttribute("Mensaje", aviso)
		end
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

local function activos()
	local lista = {}
	for p in enJuego do
		if (p:IsA("Player") and p.Parent == Players) or (not p:IsA("Player") and p.Parent) then
			table.insert(lista, p)
		end
	end
	return lista
end

ReplicatedStorage:SetAttribute("Modo", C.MODO_INICIAL)
ReplicatedStorage:SetAttribute("Mapa", mapaActual.nombre)

if C.SOLO_MOVIMIENTO then
	-- modo de pruebas: nada de rondas
	fijarFase("Esperando", 0, "")
	return
end

while true do
	-- 1. Esperar a que haya gente (con los bots casi siempre la hay)
	while #participantes() < C.JUGADORES_MINIMOS do
		fijarFase("Esperando", 0, "Esperando jugadores...")
		task.wait(1)
	end

	-- 2. Siguiente mapa y cuenta atrás
	indiceMapa = indiceMapa % #mapas + 1
	mapaActual = mapas[indiceMapa]
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
