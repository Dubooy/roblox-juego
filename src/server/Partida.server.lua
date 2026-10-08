-- Partida: manotazo (con empujón) y rondas de pilla-pilla.
--
-- Modos previstos: "Contagio" y "CoronaRobada". Se elegirán en un lobby más
-- adelante; de momento se juega siempre C.MODO_INICIAL. Cada modo es una tabla
-- con empezar / alGolpear / terminada / resultado, así añadir uno nuevo no toca el resto.
--
-- Estado público (lo leen los clientes para el HUD):
--   ReplicatedStorage:GetAttribute("Fase")    "Esperando" | "Preparando" | "Jugando" | "Fin"
--   ReplicatedStorage:GetAttribute("Modo")    nombre del modo
--   ReplicatedStorage:GetAttribute("Tiempo")  segundos que quedan de la fase
--   ReplicatedStorage:GetAttribute("Mensaje") texto grande en pantalla
--   player:GetAttribute("Pillador")           true si pilla

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

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

local Manotazo = remoto("Manotazo") -- cliente → servidor: "he dado un manotazo" (dirección de la vista)
local Empujon = remoto("Empujon") -- servidor → golpeado: vector de empujón
local Golpe = remoto("Golpe") -- servidor → todos: (atacante, golpeado) para efectos

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------

local function raiz(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0) then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function fijarFase(fase, tiempo, mensaje)
	ReplicatedStorage:SetAttribute("Fase", fase)
	ReplicatedStorage:SetAttribute("Tiempo", tiempo or 0)
	ReplicatedStorage:SetAttribute("Mensaje", mensaje or "")
end

local COLOR_PILLADOR = Color3.fromRGB(255, 70, 70)
local COLOR_HUYE = Color3.fromRGB(80, 200, 255)

local function marcar(player, pillador)
	player:SetAttribute("Pillador", pillador)
	local char = player.Character
	if not char then
		return
	end
	local h = char:FindFirstChild("MarcaEquipo")
	if not h then
		h = Instance.new("Highlight")
		h.Name = "MarcaEquipo"
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- se ve a través de las paredes
		h.FillTransparency = 0.75
		h.Parent = char
	end
	h.FillColor = pillador and COLOR_PILLADOR or COLOR_HUYE
	h.OutlineColor = h.FillColor
	h.Enabled = true
end

local function quitarMarca(player)
	player:SetAttribute("Pillador", nil)
	local char = player.Character
	local h = char and char:FindFirstChild("MarcaEquipo")
	if h then
		h:Destroy()
	end
end

------------------------------------------------------------------------
-- Modos
------------------------------------------------------------------------

local Modos = {}

-- Contagio: uno empieza pillando; cada uno que toca pasa a pillar.
-- Ganan los que huyen si queda alguno al acabar el tiempo.
Modos.Contagio = {
	nombre = "Contagio",
	empezar = function(jugadores)
		local primero = jugadores[math.random(#jugadores)]
		for _, p in jugadores do
			marcar(p, p == primero)
		end
		return { primero }, primero.DisplayName .. " pilla. ¡Corred!"
	end,
	alGolpear = function(atacante, golpeado)
		if atacante:GetAttribute("Pillador") and not golpeado:GetAttribute("Pillador") then
			marcar(golpeado, true)
			return golpeado.DisplayName .. " ha sido pillado"
		end
		return nil
	end,
	terminada = function(jugadores)
		for _, p in jugadores do
			if not p:GetAttribute("Pillador") then
				return false
			end
		end
		return true
	end,
	resultado = function(jugadores, porTiempo)
		local libres = {}
		for _, p in jugadores do
			if not p:GetAttribute("Pillador") then
				table.insert(libres, p.DisplayName)
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

local ultimoManotazo = {} -- [player] = os.clock()
local enJuego = {} -- [player] = true durante la ronda
local modoActual = nil
local faseJugando = false

Manotazo.OnServerEvent:Connect(function(atacante, vista)
	if typeof(vista) ~= "Vector3" or vista.Magnitude < 0.5 then
		return
	end
	local ahora = os.clock()
	-- un poco de margen por la latencia
	if ahora - (ultimoManotazo[atacante] or -math.huge) < C.MANOTAZO_ESPERA * 0.8 then
		return
	end
	ultimoManotazo[atacante] = ahora

	local r = raiz(atacante)
	if not r then
		return
	end
	vista = vista.Unit

	-- el jugador más cercano delante de ti dentro del alcance
	local mejor, mejorDist = nil, math.huge
	for _, otro in Players:GetPlayers() do
		if otro ~= atacante then
			local ro = raiz(otro)
			if ro then
				local d = ro.Position - r.Position
				local dist = d.Magnitude
				-- margen extra por latencia: el otro puede haberse movido un poco
				if dist <= C.MANOTAZO_ALCANCE + 3 and dist > 0 and d.Unit:Dot(vista) >= C.MANOTAZO_ANGULO - 0.15 then
					if dist < mejorDist then
						mejor, mejorDist = otro, dist
					end
				end
			end
		end
	end
	if not mejor then
		return
	end

	-- empujón: hacia donde miras, con una parte de tu velocidad
	local plano = Vector3.new(vista.X, 0, vista.Z)
	if plano.Magnitude < 0.1 then
		plano = Vector3.new((raiz(mejor).Position - r.Position).X, 0, (raiz(mejor).Position - r.Position).Z)
	end
	plano = plano.Unit
	local velAtacante = Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z).Magnitude
	local fuerza = C.MANOTAZO_EMPUJE + velAtacante * C.MANOTAZO_EMPUJE_EXTRA_VEL
	local empuje = plano * fuerza + Vector3.new(0, C.MANOTAZO_EMPUJE_ARRIBA, 0)

	Empujon:FireClient(mejor, empuje)
	Golpe:FireAllClients(atacante, mejor)

	if faseJugando and modoActual and enJuego[atacante] and enJuego[mejor] then
		local aviso = modoActual.alGolpear(atacante, mejor)
		if aviso then
			ReplicatedStorage:SetAttribute("Mensaje", aviso)
		end
	end
end)

------------------------------------------------------------------------
-- Rondas
------------------------------------------------------------------------

local function listos()
	local lista = {}
	for _, p in Players:GetPlayers() do
		if raiz(p) then
			table.insert(lista, p)
		end
	end
	return lista
end

local function anclar(jugadores, anclado)
	for _, p in jugadores do
		local r = raiz(p)
		if r then
			r.Anchored = anclado
		end
	end
end

Players.PlayerRemoving:Connect(function(p)
	enJuego[p] = nil
	ultimoManotazo[p] = nil
end)

-- si alguien reaparece en mitad de la ronda, conserva su marca
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function()
		task.wait(0.1)
		if faseJugando and enJuego[p] then
			marcar(p, p:GetAttribute("Pillador") == true)
		end
	end)
end)

ReplicatedStorage:SetAttribute("Modo", C.MODO_INICIAL)

while true do
	-- 1. Esperar jugadores
	while #listos() < C.JUGADORES_MINIMOS do
		fijarFase("Esperando", 0, "Esperando jugadores (" .. #listos() .. "/" .. C.JUGADORES_MINIMOS .. ")")
		task.wait(1)
	end

	-- 2. Cuenta atrás
	modoActual = Modos[C.MODO_INICIAL] or Modos.Contagio
	ReplicatedStorage:SetAttribute("Modo", modoActual.nombre)
	local cancelada = false
	for t = C.PREPARACION, 1, -1 do
		fijarFase("Preparando", t, modoActual.nombre .. " empieza en " .. t)
		task.wait(1)
		if #listos() < C.JUGADORES_MINIMOS then
			cancelada = true
			break
		end
	end

	if not cancelada then
		-- 3. Empezar: todos reaparecen en el mapa
		for _, p in Players:GetPlayers() do
			p:LoadCharacter()
		end
		task.wait(0.5)
		local jugadores = listos()
		enJuego = {}
		for _, p in jugadores do
			enJuego[p] = true
		end

		local pilladores, mensaje = modoActual.empezar(jugadores)
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
		local porTiempo = true
		while os.clock() < fin do
			-- quitar a los que se van
			local activos = {}
			for p in enJuego do
				if p.Parent == Players then
					table.insert(activos, p)
				end
			end
			if #activos < C.JUGADORES_MINIMOS or modoActual.terminada(activos) then
				porTiempo = false
				break
			end
			ReplicatedStorage:SetAttribute("Tiempo", math.ceil(fin - os.clock()))
			task.wait(0.25)
		end

		-- 5. Resultado
		faseJugando = false
		local activos = {}
		for p in enJuego do
			if p.Parent == Players then
				table.insert(activos, p)
			end
		end
		fijarFase("Fin", C.PAUSA_FINAL, modoActual.resultado(activos, porTiempo))
		task.wait(C.PAUSA_FINAL)
		for _, p in Players:GetPlayers() do
			quitarMarca(p)
		end
		enJuego = {}
	end
end
