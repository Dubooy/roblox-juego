-- Bots para jugar sin más gente. Son personajes de Roblox normales controlados por el
-- servidor: persiguen si pillan y huyen si no. Usan PathfindingService para subir por
-- rampas y cajas, y saltan si se atascan. Dan y reciben manotazos como los jugadores.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Bots = {}

local NOMBRES = { "Tostada", "Pepino", "Calcetín", "Brócoli", "Turbo", "Fideo", "Croqueta", "Albóndiga", "Churro", "Mango" }
local COLORES = {
	Color3.fromRGB(255, 200, 150), Color3.fromRGB(240, 180, 120), Color3.fromRGB(200, 140, 100),
	Color3.fromRGB(150, 100, 70), Color3.fromRGB(100, 70, 50), Color3.fromRGB(255, 220, 180),
}
local ROPA = {
	Color3.fromRGB(220, 60, 60), Color3.fromRGB(60, 120, 220), Color3.fromRGB(60, 180, 90),
	Color3.fromRGB(240, 190, 40), Color3.fromRGB(160, 80, 200), Color3.fromRGB(240, 120, 40),
}

local carpeta = Instance.new("Folder")
carpeta.Name = "Bots"
carpeta.Parent = workspace

local lista = {} -- bots vivos (Model)

local function crearModelo(i)
	local desc = Instance.new("HumanoidDescription")
	local piel = COLORES[math.random(#COLORES)]
	desc.HeadColor = piel
	desc.LeftArmColor = piel
	desc.RightArmColor = piel
	local ropa = ROPA[(i - 1) % #ROPA + 1]
	desc.TorsoColor = ropa
	local pantalon = ropa:Lerp(Color3.new(0, 0, 0), 0.5)
	desc.LeftLegColor = pantalon
	desc.RightLegColor = pantalon

	local ok, modelo = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not modelo then
		-- plan B: copiar el personaje de un jugador y pintarlo
		warn("[Bots] Roblox no generó el bot, se copia un personaje:", modelo)
		modelo = nil
		for _, p in Players:GetPlayers() do
			local char = p.Character
			if char and char:FindFirstChildOfClass("Humanoid") then
				local antes = char.Archivable
				char.Archivable = true
				modelo = char:Clone()
				char.Archivable = antes
				break
			end
		end
		if not modelo then
			return nil
		end
		for _, d in modelo:GetDescendants() do
			if d:IsA("LuaSourceContainer") or d:IsA("Highlight") or d:IsA("LinearVelocity") or d:IsA("Accessory") or d:IsA("Clothing") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Color = (d.Name:find("Torso") and ropa) or (d.Name:find("Leg") or d.Name:find("Foot")) and pantalon or piel
			end
		end
	end
	local nombre = NOMBRES[(i - 1) % #NOMBRES + 1]
	modelo.Name = nombre
	modelo:SetAttribute("EsBot", true)
	modelo:SetAttribute("NombreVisible", nombre)
	local hum = modelo:FindFirstChildOfClass("Humanoid")
	hum.DisplayName = nombre
	hum.WalkSpeed = C.BOT_VELOCIDAD
	hum.JumpPower = 60
	hum.UseJumpPower = true
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	return modelo
end

function Bots.lista()
	local vivos = {}
	for _, b in lista do
		if b.Parent and b:FindFirstChildOfClass("Humanoid") and b:FindFirstChildOfClass("Humanoid").Health > 0 then
			table.insert(vivos, b)
		end
	end
	return vivos
end

-- Ajusta cuántos bots hay para llegar a "cuantos"
function Bots.ajustar(cuantos, posicionInicial)
	while #lista > cuantos do
		local b = table.remove(lista)
		b:Destroy()
	end
	local i = #lista
	while #lista < cuantos do
		i += 1
		local m = crearModelo(i)
		if not m then
			break
		end
		m:PivotTo(CFrame.new(posicionInicial + Vector3.new(math.random(-20, 20), 4, math.random(-20, 20))))
		m.Parent = carpeta
		local root = m:FindFirstChild("HumanoidRootPart")
		if root then
			root:SetNetworkOwner(nil)
		end
		table.insert(lista, m)
	end
end

function Bots.colocar(bot, posicion)
	bot:PivotTo(CFrame.new(posicion))
	local root = bot:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Empujón a un bot (el servidor lo mueve directamente)
function Bots.empujar(bot, vector)
	local root = bot:FindFirstChild("HumanoidRootPart")
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if root and hum then
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
		root.AssemblyLinearVelocity = vector
		bot:SetAttribute("AturdidoHasta", os.clock() + 0.6)
	end
end

------------------------------------------------------------------------
-- Cerebro
------------------------------------------------------------------------

local cerebros = {} -- [bot] = { objetivo, camino, waypoint, ultimoPensar, ultimaPos, atascado }

-- ctx: {
--   participantes = function() → lista,
--   raiz = function(p) → BasePart,
--   esPillador = function(p) → bool,
--   puntos = function() → {Vector3} del mapa actual,
--   golpear = function(bot, vista) (intenta un manotazo),
--   activo = function() → bool (ronda en marcha)
-- }
function Bots.empezar(ctx)
	task.spawn(function()
		while true do
			local ahora = os.clock()
			for _, bot in Bots.lista() do
				local hum = bot:FindFirstChildOfClass("Humanoid")
				local root = bot:FindFirstChild("HumanoidRootPart")
				local cb = cerebros[bot]
				if not cb then
					cb = { ultimoPensar = 0, waypoints = {}, idx = 1, ultimaPos = root.Position, atascado = 0, destino = nil, ultimoGolpe = 0 }
					cerebros[bot] = cb
				end

				if (bot:GetAttribute("AturdidoHasta") or 0) > ahora then
					continue
				end

				if not ctx.activo() then
					-- entre rondas pasean
					if ahora - cb.ultimoPensar > 3 then
						cb.ultimoPensar = ahora
						local pts = ctx.puntos()
						if #pts > 0 then
							hum:MoveTo(pts[math.random(#pts)])
						end
					end
					continue
				end

				local soyPillador = ctx.esPillador(bot)

				-- elegir a quién perseguir o de quién huir
				local cercano, dist = nil, math.huge
				for _, p in ctx.participantes() do
					if p ~= bot then
						local r = ctx.raiz(p)
						if r and ctx.esPillador(p) ~= soyPillador then
							local d = (r.Position - root.Position).Magnitude
							if d < dist then
								cercano, dist = p, d
							end
						end
					end
				end

				-- manotazo si hay alguien delante y cerca (los que huyen también empujan)
				if cercano and dist <= C.MANOTAZO_ALCANCE and ahora - cb.ultimoGolpe > C.MANOTAZO_ESPERA * 1.6 then
					local r = ctx.raiz(cercano)
					if r then
						cb.ultimoGolpe = ahora
						-- los que huyen solo empujan a veces, para no ser imposibles
						if soyPillador or math.random() < 0.35 then
							ctx.golpear(bot, (r.Position - root.Position).Unit)
						end
					end
				end

				if ahora - cb.ultimoPensar >= C.BOT_PIENSA_CADA then
					cb.ultimoPensar = ahora
					local destino
					if cercano then
						local r = ctx.raiz(cercano)
						if soyPillador then
							-- un poco por delante de hacia donde va
							destino = r.Position + r.AssemblyLinearVelocity * 0.25
						else
							-- huir: el punto del mapa más lejos del pillador, sin ir hacia él
							local mejor, mejorValor = nil, -math.huge
							for _, pt in ctx.puntos() do
								local alejado = (pt - r.Position).Magnitude
								local cerca = (pt - root.Position).Magnitude
								local haciaEl = (pt - root.Position).Unit:Dot((r.Position - root.Position).Unit)
								local valor = alejado - cerca * 0.5 - math.max(haciaEl, 0) * 60
								if valor > mejorValor then
									mejor, mejorValor = pt, valor
								end
							end
							destino = mejor
						end
					else
						local pts = ctx.puntos()
						destino = #pts > 0 and pts[math.random(#pts)] or nil
					end

					if destino then
						-- cerca y a la vista: ir directo; lejos: pathfinding
						if soyPillador and dist < 25 then
							cb.waypoints = { { Position = destino, Action = Enum.PathWaypointAction.Walk } }
							cb.idx = 1
						else
							local camino = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
							local ok = pcall(function()
								camino:ComputeAsync(root.Position, destino)
							end)
							if ok and camino.Status == Enum.PathStatus.Success then
								cb.waypoints = camino:GetWaypoints()
								cb.idx = math.min(2, #cb.waypoints)
							else
								cb.waypoints = { { Position = destino, Action = Enum.PathWaypointAction.Walk } }
								cb.idx = 1
							end
						end
					end
				end

				-- seguir el camino
				local wp = cb.waypoints[cb.idx]
				if wp then
					hum:MoveTo(wp.Position)
					if wp.Action == Enum.PathWaypointAction.Jump then
						hum.Jump = true
					end
					local plano = Vector3.new(wp.Position.X - root.Position.X, 0, wp.Position.Z - root.Position.Z)
					if plano.Magnitude < 3 then
						cb.idx += 1
					end
				end

				-- ¿atascado? saltar
				local movido = (root.Position - cb.ultimaPos).Magnitude
				cb.ultimaPos = root.Position
				if wp and movido < 0.15 then
					cb.atascado += 1
					if cb.atascado > 4 then
						hum.Jump = true
						cb.atascado = 0
						cb.ultimoPensar = 0
					end
				else
					cb.atascado = 0
				end
			end
			task.wait(0.1)
		end
	end)
end

return Bots
