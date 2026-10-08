-- Movimiento de parkour en primera persona (estilo Parkour Reborn).
--
-- FLUJO: corriendo recto vas ganando velocidad poco a poco hasta FLUJO_MAX. Cada
-- mecánica bien hecha te da un empujón por encima, que baja despacio si dejas de
-- encadenar. Pierdes flujo al pararte, al girar de golpe o al chocar contra una pared.
--
-- Mecánicas:
--   · Saltar vallas: corre hacia un obstáculo bajo y lo saltas solo, sin frenar.
--   · Escalar: salta hacia un borde alto y te agarras y subes.
--   · Trepar: corre contra una pared y pulsa saltar: subes corriendo por ella.
--     Saltar mientras trepas = te impulsas hacia atrás.
--   · Correr por la pared: salta en paralelo a una pared yendo rápido y mantén W.
--   · Saltar desde un muro: en el aire, pegado a una pared, pulsa saltar.
--   · Slide: Ctrl/C/Shift corriendo. Empujón al empezar; cuesta abajo acelera.
--   · Barras: salta hacia una barra; W/S balancea, saltar te lanza, slide te suelta.
--   · Rodar: al caer de alto, pulsa slide justo antes de tocar el suelo.
--
-- Arquitectura: el Humanoid hace colisiones y gravedad; la velocidad horizontal la
-- calcula este script y la aplica con un LinearVelocity en X y Z. En las mecánicas
-- "animadas" (vallas, escalar, barras) el cuerpo se mueve a mano con el Humanoid en
-- estado Physics y siempre derecho, para que la cámara no gire.
--
-- Publica su estado en atributos del jugador (Mov*) para los brazos y la partida.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()

local UP = Vector3.yAxis
local humanoid, root, linVel
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local s = {}

local function resetState()
	s.modo = "normal" -- normal | valla | escalar | trepar | barra
	s.wasGrounded = false
	s.lastGroundedAt = -math.huge
	s.lastJumpAt = -math.huge
	s.jumpBufferedAt = -math.huge
	s.lastJumpRequest = -math.huge
	s.lastAirVelY = 0

	s.flujo = C.RUN_BASE

	s.slideHeld = false
	s.slidePressedAt = -math.huge
	s.sliding = false
	s.slideBoostAt = -math.huge

	s.wallrun = nil
	s.wallrunLado = 0
	s.ultimaPared = nil
	s.trepadoUsado = false

	s.anim = nil -- { desde, hasta, inicio, duracion, salida, agarre } para valla/escalar
	s.trepar = nil -- { normal, hasta }
	s.barra = nil
	s.barraSoltadaAt = -math.huge

	s.rodarInicio = -math.huge
	s.aturdidoHasta = -math.huge
	s.golpeParedAt = -math.huge

	s.combo = 0
	s.comboUltimoAt = -math.huge

	s.empujePendiente = nil
	s.empujeHasta = -math.huge

	s.paso = 0
	s.pasoAnterior = 0
	s.fovPunch = 0
	s.landDip = 0
	s.roll = 0
	s.pitchKick = 0
	s.speed = 0
	s.agarre = nil
end
resetState()

------------------------------------------------------------------------
-- Sonidos (sonidos incluidos en Roblox, sin descargar nada)
------------------------------------------------------------------------

local sonidos = {}
local function crearSonido(nombre, id, volumen, bucle)
	local snd = Instance.new("Sound")
	snd.Name = "Mov" .. nombre
	snd.SoundId = id
	snd.Volume = volumen * C.VOLUMEN
	snd.Looped = bucle or false
	snd.Parent = SoundService
	sonidos[nombre] = snd
	return snd
end
crearSonido("paso", "rbxasset://sounds/action_jump_land.mp3", 0.25)
crearSonido("salto", "rbxasset://sounds/action_jump.mp3", 0.5)
crearSonido("aterrizar", "rbxasset://sounds/action_jump_land.mp3", 0.8)
crearSonido("rodar", "rbxasset://sounds/action_get_up.mp3", 0.7)
crearSonido("viento", "rbxasset://sounds/action_falling.mp3", 0, true)
crearSonido("roce", "rbxasset://sounds/action_falling.mp3", 0, true)

local function sonar(nombre, tono, volumen)
	local base = sonidos[nombre]
	if not base then
		return
	end
	local snd = base:Clone()
	snd.PlaybackSpeed = (tono or 1) * (0.94 + math.random() * 0.12)
	if volumen then
		snd.Volume = volumen * C.VOLUMEN
	end
	snd.Parent = SoundService
	snd:Play()
	snd.Ended:Once(function()
		snd:Destroy()
	end)
end

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v, alt)
	return v.Magnitude > 0.001 and v.Unit or alt
end

local function mirarPlano()
	return unitOr(flat(camera.CFrame.LookVector), unitOr(flat(root.CFrame.LookVector), Vector3.zAxis))
end

local function accelerate(vel, wishDir, wishSpeed, accel, dt)
	if wishDir.Magnitude == 0 then
		return vel
	end
	local add = wishSpeed - vel:Dot(wishDir)
	if add <= 0 then
		return vel
	end
	return vel + wishDir * math.min(accel * wishSpeed * dt, add)
end

local function applyFriction(vel, amount, dt)
	local speed = vel.Magnitude
	if speed < 0.01 then
		return Vector3.zero
	end
	local drop = math.max(speed, C.STOP_SPEED) * amount * dt
	return vel * (math.max(speed - drop, 0) / speed)
end

local function steer(vel, wishDir, rate, dt)
	local speed = vel.Magnitude
	if speed < 0.01 or wishDir.Magnitude == 0 then
		return vel
	end
	local dir = vel / speed
	if dir:Dot(wishDir) < -0.3 then
		return vel
	end
	return unitOr(dir:Lerp(wishDir, math.clamp(rate * dt, 0, 1)), dir) * speed
end

local function alturaPies()
	return humanoid.HipHeight + root.Size.Y / 2
end

local function feetY()
	return root.Position.Y - alturaPies()
end

local function groundHit()
	local reach = alturaPies() + 0.45
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
	if hit then
		return hit
	end
	-- cuatro rayos más en las esquinas, para no "caerse" justo en los bordes
	for _, o in { Vector3.new(0.7, 0, 0), Vector3.new(-0.7, 0, 0), Vector3.new(0, 0, 0.7), Vector3.new(0, 0, -0.7) } do
		hit = workspace:Raycast(root.Position + o, Vector3.new(0, -reach, 0), rayParams)
		if hit and hit.Normal.Y > 0.6 then
			return hit
		end
	end
	return nil
end

local function wishDirection()
	local move = controls:GetMoveVector()
	if move.Magnitude < 0.01 then
		return Vector3.zero
	end
	local look = flat(camera.CFrame.LookVector)
	local right = flat(camera.CFrame.RightVector)
	if look.Magnitude < 0.01 then
		return Vector3.zero
	end
	return unitOr(look.Unit * -move.Z + right.Unit * move.X, Vector3.zero)
end

local function sumarCombo(now)
	s.combo += 1
	s.comboUltimoAt = now
end

-- empujón: sube la velocidad y el flujo
-- Cuanto más rápido vas, menos te da cada empujón (al tope casi nada): así llegar
-- al máximo cuesta encadenar bien muchas mecánicas.
local function empujon(horiz, extra, dirAlternativa)
	local dir = unitOr(horiz, dirAlternativa or mirarPlano())
	local base = math.max(horiz.Magnitude, C.RUN_BASE)
	local margen = math.clamp((C.MAX_SPEED - base) / (C.MAX_SPEED - C.RUN_BASE), 0, 1)
	local rapidez = math.min(base + extra * margen ^ C.EMPUJON_CURVA, C.MAX_SPEED)
	s.flujo = math.max(s.flujo, math.min(rapidez, C.MAX_SPEED))
	s.fovPunch = math.max(s.fovPunch, C.FOV_GOLPE * 0.6)
	return dir * rapidez
end

-- ¿pared en esta dirección? → hit
local function paredEn(dir, distancia, alturaY)
	local origen = root.Position + Vector3.new(0, alturaY or 0, 0)
	local hit = workspace:Raycast(origen, dir * distancia, rayParams)
	if hit and math.abs(hit.Normal.Y) < 0.4 then
		return hit
	end
	return nil
end

local function paredLateral(adelante)
	local derecha = adelante:Cross(UP)
	for _, lado in { 1, -1 } do
		-- justo de lado y en diagonal hacia delante (así se detectan paredes que no son paralelas del todo)
		for _, dir in { derecha * lado, (derecha * lado + adelante * 0.6).Unit, (derecha * lado - adelante * 0.4).Unit } do
			for _, y in { 0, -1.2 } do
				local hit = paredEn(dir, C.WALLRUN_DISTANCIA, y)
				if hit and math.abs(flat(hit.Normal).Unit:Dot(adelante)) < 0.75 then
					return flat(hit.Normal).Unit, lado, hit.Position
				end
			end
		end
	end
	return nil
end

local function muroCercano()
	local mejor, mejorDist, punto = nil, math.huge, nil
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local hit = paredEn(Vector3.new(math.cos(a), 0, math.sin(a)), C.MURO_SALTO_DISTANCIA)
		if hit and hit.Distance < mejorDist then
			mejor, mejorDist, punto = hit.Normal, hit.Distance, hit.Position
		end
	end
	return mejor, punto
end

-- Quita la parte de la velocidad que va contra una pared (así no te empuja ni tiembla).
-- Devuelve la velocidad corregida y si ha sido un choque de frente.
local function deslizarParedes(horiz, dt)
	local rapidez = horiz.Magnitude
	if rapidez < 0.1 then
		return horiz, false
	end
	local dir = horiz / rapidez
	local alcance = root.Size.X / 2 + 0.6 + rapidez * dt
	local deFrente = false
	for _, y in { -1.2, 0, 1.2 } do
		local hit = paredEn(dir, alcance, y)
		if hit then
			local n = flat(hit.Normal)
			if n.Magnitude > 0.01 then
				n = n.Unit
				local contra = -horiz:Dot(n)
				if contra > 0 then
					if contra / rapidez > 0.92 then
						deFrente = true
					end
					horiz += n * contra
				end
			end
		end
	end
	return horiz, deFrente
end

------------------------------------------------------------------------
-- Cuerpo movido a mano (vallas, escalar, barras)
------------------------------------------------------------------------

local function cuerpoManual(activar)
	if activar then
		humanoid.AutoRotate = false
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		linVel.Enabled = false
	else
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		linVel.Enabled = true
	end
	root.AssemblyAngularVelocity = Vector3.zero
end

local function ponerCuerpo(pos)
	root.CFrame = CFrame.lookAt(pos, pos + mirarPlano())
	root.AssemblyAngularVelocity = Vector3.zero
end

------------------------------------------------------------------------
-- Detectar bordes (para vallas y escalar)
------------------------------------------------------------------------

-- Busca el borde de lo que hay delante. Devuelve:
--   { altura (desde los pies), cima (punto de la superficie), dentro (dirección hacia el obstáculo),
--     borde (punto del canto, para las manos), distancia, cabe (hay sitio encima) }
local function buscarBorde(adelante, alcance)
	local hitPared
	for _, y in { -1.6, -0.6, 0.6, 1.8 } do
		hitPared = paredEn(adelante, alcance, y)
		if hitPared then
			break
		end
	end
	if not hitPared then
		return nil
	end
	local dentro = unitOr(-flat(hitPared.Normal), adelante)
	local pies = feetY()
	local desde = Vector3.new(hitPared.Position.X, pies + C.ESCALAR_ALTURA_MAX + 1, hitPared.Position.Z) + dentro * 0.9
	local hitCima = workspace:Raycast(desde, Vector3.new(0, -(C.ESCALAR_ALTURA_MAX + 1.5), 0), rayParams)
	if not hitCima or hitCima.Normal.Y < 0.7 then
		return nil
	end
	local altura = hitCima.Position.Y - pies
	if altura < 0.5 then
		return nil
	end
	local alto = alturaPies() + root.Size.Y / 2
	local encima = hitCima.Position + dentro * 0.6
	local cabe = workspace:Raycast(encima + Vector3.new(0, 0.2, 0), Vector3.new(0, alto + 1, 0), rayParams) == nil
	return {
		altura = altura,
		cima = hitCima.Position,
		dentro = dentro,
		borde = Vector3.new(hitPared.Position.X, hitCima.Position.Y, hitPared.Position.Z),
		distancia = hitPared.Distance,
		cabe = cabe,
	}
end

local function empezarAnim(modo, hasta, duracion, salida, agarre, now)
	s.anim = { desde = root.Position, hasta = hasta, inicio = now, duracion = duracion, salida = salida, agarre = agarre }
	s.modo = modo
	s.wallrun = nil
	s.trepar = nil
	s.sliding = false
	s.agarre = agarre
	cuerpoManual(true)
	sumarCombo(now)
end

------------------------------------------------------------------------
-- Barras
------------------------------------------------------------------------

local function buscarBarra()
	local manos = root.Position + Vector3.new(0, 2.6, 0)
	local mejor, mejorDist = nil, C.BARRA_AGARRE
	for _, b in CollectionService:GetTagged("Barra") do
		if b:IsA("BasePart") and b:IsDescendantOf(workspace) then
			local eje = b.CFrame.RightVector
			if math.abs(eje.Y) < 0.3 then
				local largo = b.Size.X / 2
				local t = math.clamp((manos - b.Position):Dot(eje), -largo + 0.5, largo - 0.5)
				local punto = b.Position + eje * t
				local d = (manos - punto).Magnitude
				if d < mejorDist then
					mejor, mejorDist = { punto = punto, eje = flat(eje).Unit }, d
				end
			end
		end
	end
	return mejor
end

local function agarrarBarra(b, vel, now)
	local frente = UP:Cross(b.eje)
	local ref = flat(vel).Magnitude > 2 and flat(vel) or mirarPlano()
	if frente:Dot(ref) < 0 then
		frente = -frente
	end
	local o = root.Position - b.punto
	local theta = math.atan2(o:Dot(frente), -o.Y)
	local tangente = frente * math.cos(theta) + UP * math.sin(theta)
	s.barra = { punto = b.punto, eje = b.eje, frente = frente, theta = theta, omega = vel:Dot(tangente) / C.BARRA_RADIO }
	s.modo = "barra"
	s.wallrun = nil
	s.sliding = false
	s.agarre = b.punto
	cuerpoManual(true)
	sumarCombo(now)
end

local function soltarBarra(conImpulso, now)
	local b = s.barra
	s.barra = nil
	s.modo = "normal"
	s.agarre = nil
	s.barraSoltadaAt = now
	cuerpoManual(false)
	local tangente = b.frente * math.cos(b.theta) + UP * math.sin(b.theta)
	local v = tangente * (b.omega * C.BARRA_RADIO)
	if conImpulso then
		local mirar = mirarPlano()
		local h = flat(v) * C.BARRA_IMPULSO
		if h:Dot(mirar) < C.RUN_BASE then
			h = mirar * math.max(h:Dot(mirar), C.RUN_BASE) + (h - mirar * h:Dot(mirar)) * 0.5
		end
		h = empujon(h, 2, mirar)
		v = Vector3.new(h.X, math.max(v.Y, 0) + C.BARRA_SALTO_EXTRA, h.Z)
		sonar("salto", 1.1)
	end
	local h = flat(v)
	if h.Magnitude > C.MAX_SPEED then
		h = h.Unit * C.MAX_SPEED
	end
	root.AssemblyLinearVelocity = Vector3.new(h.X, v.Y, h.Z)
	linVel.VectorVelocity = h
	s.lastJumpAt = now
	s.ultimaPared = nil
end

local function pasoBarra(dt, now)
	local b = s.barra
	local alpha = -(C.GRAVITY / C.BARRA_RADIO) * math.sin(b.theta)
	local empuje = wishDirection():Dot(b.frente)
	if math.abs(empuje) > 0.3 and math.abs(b.theta) < 1.2 then
		local sentido = b.omega >= 0 and 1 or -1
		if math.abs(b.omega) < 0.3 then
			sentido = empuje > 0 and 1 or -1
		end
		alpha += sentido * C.BARRA_BOMBEO * math.abs(empuje)
	end
	b.omega += alpha * dt
	b.omega *= (1 - C.BARRA_AMORTIGUA * dt)
	b.theta += b.omega * dt
	if math.abs(b.theta) > 2.4 then
		b.theta = math.sign(b.theta) * 2.4
		b.omega = -b.omega * 0.3
	end
	local pos = b.punto + (b.frente * math.sin(b.theta) - UP * math.cos(b.theta)) * C.BARRA_RADIO
	ponerCuerpo(pos)
	local tangente = b.frente * math.cos(b.theta) + UP * math.sin(b.theta)
	root.AssemblyLinearVelocity = tangente * (b.omega * C.BARRA_RADIO)
	s.speed = math.abs(b.omega * C.BARRA_RADIO)

	if now - s.jumpBufferedAt <= C.JUMP_BUFFER then
		s.jumpBufferedAt = -math.huge
		soltarBarra(true, now)
	elseif s.slideHeld then
		soltarBarra(false, now)
	end
end

------------------------------------------------------------------------
-- Paso de física
------------------------------------------------------------------------

local function publicar(grounded)
	player:SetAttribute("MovVelocidad", s.speed)
	player:SetAttribute("MovSlide", s.sliding)
	player:SetAttribute("MovSuelo", grounded)
	player:SetAttribute("MovUltimoSalto", s.lastJumpAt)
	player:SetAttribute("MovPared", s.wallrunLado)
	player:SetAttribute("MovModo", s.modo)
	player:SetAttribute("MovAgarre", s.agarre)
	player:SetAttribute("MovVallaRapida", s.anim ~= nil and s.anim.rapida == true and s.modo == "valla")
	player:SetAttribute("MovLadoValla", s.ladoValla or 1)
	player:SetAttribute("MovAnimT", s.anim and math.clamp((os.clock() - s.anim.inicio) / s.anim.duracion, 0, 1) or 0)
	player:SetAttribute("MovRodando", os.clock() - s.rodarInicio < C.RODAR_DURACION)
	player:SetAttribute("MovPaso", s.paso)
	player:SetAttribute("MovCombo", s.combo)
	player:SetAttribute("MovFlujo", s.flujo)
end

local function saltar(vy, now)
	s.jumpBufferedAt = -math.huge
	s.lastJumpAt = now
	s.lastGroundedAt = -math.huge
	s.sliding = false
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	sonar("salto")
	return vy
end

local function step(dt)
	if not (root and humanoid and linVel) or humanoid.Health <= 0 then
		return
	end
	dt = math.min(dt, 1 / 20)
	local now = os.clock()

	if s.combo > 0 and s.wasGrounded and not s.sliding and now - s.comboUltimoAt > C.COMBO_CADUCA then
		s.combo = 0
	end

	-- Colgado de una barra
	if s.modo == "barra" then
		pasoBarra(dt, now)
		s.wallrunLado = 0
		publicar(false)
		return
	end

	-- Animaciones de cuerpo: saltar valla / escalar
	if s.modo == "valla" or s.modo == "escalar" then
		local a = s.anim
		local t = math.clamp((now - a.inicio) / a.duracion, 0, 1)
		local pos
		if s.modo == "escalar" then
			-- primero sube (con las manos apoyadas), luego pasa el cuerpo por encima
			local subida = 1 - (1 - math.min(t / 0.7, 1)) ^ 2.2
			local avance = math.clamp((t - 0.45) / 0.55, 0, 1)
			avance = avance * avance * (3 - 2 * avance)
			pos = Vector3.new(
				a.desde.X + (a.hasta.X - a.desde.X) * avance,
				a.desde.Y + (a.hasta.Y - a.desde.Y) * subida,
				a.desde.Z + (a.hasta.Z - a.desde.Z) * avance
			)
		else
			-- valla: arco rápido por encima del obstáculo
			-- sube rápido al principio para pasar por encima, avanza a ritmo constante
			local subida = 1 - (1 - math.min(t * 1.8, 1)) ^ 2
			pos = Vector3.new(
				a.desde.X + (a.hasta.X - a.desde.X) * t,
				a.desde.Y + (a.hasta.Y - a.desde.Y) * subida + math.sin(t * math.pi) * (a.rapida and 1.4 or 0.6),
				a.desde.Z + (a.hasta.Z - a.desde.Z) * t
			)
		end
		ponerCuerpo(pos)
		root.AssemblyLinearVelocity = Vector3.zero
		if t >= 1 then
			s.modo = "normal"
			s.anim = nil
			s.agarre = nil
			cuerpoManual(false)
			root.AssemblyLinearVelocity = a.salida + Vector3.new(0, 2, 0)
			linVel.VectorVelocity = a.salida
			s.lastGroundedAt = now
			s.trepadoUsado = false
		end
		s.speed = a.salida.Magnitude
		s.paso += dt * s.speed / C.ZANCADA * math.pi
		publicar(false)
		return
	end

	local vel = root.AssemblyLinearVelocity
	local horiz = flat(vel)
	local vy = vel.Y
	local setY = false
	local wish = wishDirection()
	local adelante = mirarPlano()

	-- Suelo
	local hit = groundHit()
	local grounded = hit ~= nil and (now - s.lastJumpAt) > 0.12 and vy <= 3 and not s.trepar
	if grounded then
		if not s.wasGrounded then
			local caida = -s.lastAirVelY
			s.landDip = math.clamp(caida / 110, 0, 1) * C.LAND_DIP_MAX
			if caida >= C.CAIDA_FUERTE then
				if now - s.slidePressedAt <= C.RODAR_VENTANA or s.slideHeld then
					horiz = empujon(horiz, C.RODAR_BONUS)
					s.rodarInicio = now
					s.landDip = 0.4
					sumarCombo(now)
					sonar("rodar", 1.1)
				else
					-- golpe: pierdes una parte de lo que llevas por encima de la base, no todo
					local r = horiz.Magnitude
					if r > C.RUN_BASE then
						local nueva = C.RUN_BASE + (r - C.RUN_BASE) * (1 - C.GOLPE_PIERDE)
						horiz = horiz.Unit * nueva
						s.flujo = math.max(C.RUN_BASE, math.min(s.flujo, nueva))
					end
					s.aturdidoHasta = now + C.GOLPE_ATURDIDO
					s.combo = 0
					sonar("aterrizar", 0.8, 1)
				end
			elseif caida > 25 then
				sonar("aterrizar", 1, math.clamp(caida / 90, 0.2, 0.8))
			end
		end
		s.lastGroundedAt = now
		s.wallrun = nil
		s.ultimaPared = nil
		s.trepadoUsado = false
	else
		s.lastAirVelY = vy
	end
	s.wasGrounded = grounded

	-- Empujón recibido (manotazo)
	if s.empujePendiente then
		local e = s.empujePendiente
		s.empujePendiente = nil
		horiz = flat(e)
		vy = e.Y
		setY = true
		s.sliding = false
		s.wallrun = nil
		s.trepar = nil
		s.lastJumpAt = now
		s.lastGroundedAt = -math.huge
		grounded = false
		s.empujeHasta = now + C.EMPUJE_SIN_LIMITE
		s.fovPunch = C.FOV_GOLPE
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	local saltoPedido = now - s.jumpBufferedAt <= C.JUMP_BUFFER and now > s.aturdidoHasta
	local libreDeAnim = now > s.aturdidoHasta and not s.sliding

	-- 1) SALTAR VALLA (automático corriendo hacia un obstáculo bajo)
	if libreDeAnim and wish.Magnitude > 0 and wish:Dot(adelante) > 0.6 and horiz.Magnitude >= C.VALLA_VEL_MIN and not s.trepar then
		local rapida = horiz.Magnitude >= C.VALLA_RAPIDA_VEL
		local alturaMax = rapida and C.VALLA_RAPIDA_ALTURA_MAX or C.VALLA_ALTURA_MAX
		local b = buscarBorde(adelante, root.Size.X / 2 + 1.2 + horiz.Magnitude * (rapida and 0.09 or 0.06))
		if b and b.cabe and b.altura >= C.VALLA_ALTURA_MIN and b.altura <= alturaMax then
			local rapidez = math.max(horiz.Magnitude, C.RUN_BASE)
			local sobre = b.cima.Y + alturaPies() + (rapida and 0.9 or 0.4)
			local avanceH = b.distancia + (rapida and 5 or 2.6)
			local destino = flat(root.Position) + b.dentro * avanceH
			local hasta = Vector3.new(destino.X, math.max(sobre, root.Position.Y), destino.Z)
			local salida = empujon(b.dentro * rapidez, rapida and C.VALLA_RAPIDA_BONUS or C.VALLA_BONUS, b.dentro)
			local duracion = rapida and C.VALLA_RAPIDA_DURACION or C.VALLA_DURACION * math.clamp(26 / rapidez, 0.7, 1.2)
			empezarAnim("valla", hasta, duracion, salida, b.borde, now)
			s.anim.rapida = rapida
			-- lado hacia el que se tumba el cuerpo (piernas en horizontal), alterna cada vez
			s.ladoValla = -(s.ladoValla or 1)
			sonar("paso", rapida and 0.9 or 1.2, 0.5)
			publicar(false)
			return
		end
	end

	-- 2) ESCALAR un borde alto (en el aire, yendo hacia él)
	if libreDeAnim and not grounded and wish.Magnitude > 0 and wish:Dot(adelante) > 0.4 then
		local b = buscarBorde(adelante, C.ESCALAR_ALCANCE)
		local manosY = root.Position.Y + 2.4
		if b and b.cabe and b.altura > C.VALLA_ALTURA_MIN and b.cima.Y - manosY < C.ESCALAR_MANOS and b.cima.Y > root.Position.Y - 1.5 then
			local destino = b.cima + b.dentro * 1.4 + Vector3.new(0, alturaPies() + 0.05, 0)
			local salida = b.dentro * math.max(horiz.Magnitude * C.ESCALAR_CONSERVA, C.RUN_BASE * 0.7)
			empezarAnim("escalar", destino, C.ESCALAR_DURACION * math.clamp((destino.Y - root.Position.Y) / 6, 0.6, 1.1), salida, b.borde, now)
			s.trepar = nil
			publicar(false)
			return
		end
	end

	-- Saltos
	if saltoPedido then
		if s.trepar then
			-- impulso hacia atrás desde la pared mientras trepas
			local n = s.trepar.normal
			s.trepar = nil
			horiz = empujon(n * math.max(C.MURO_SALTO_FUERA, horiz.Magnitude), C.MURO_SALTO_BONUS, n)
			vy = saltar(C.MURO_SALTO_ARRIBA * 0.9, now)
			s.ultimaPared = n
			sumarCombo(now)
			setY = true
		elseif grounded or now - s.lastGroundedAt <= C.COYOTE_TIME then
			-- ¿pared delante? → trepar
			local frente = paredEn(adelante, C.TREPAR_DISTANCIA, 0.5)
			local b = frente and buscarBorde(adelante, C.TREPAR_DISTANCIA)
			if frente and wish:Dot(adelante) > 0.5 and not s.trepadoUsado and not (b and b.altura <= C.VALLA_ALTURA_MAX) then
				local n = flat(frente.Normal).Unit
				s.trepar = { normal = n, hasta = now + C.TREPAR_DURACION, punto = frente.Position }
				s.trepadoUsado = true
				vy = saltar(C.TREPAR_VEL, now)
				horiz = -n * 2
				sumarCombo(now)
				setY = true
			else
				local extra = s.sliding and C.SLIDE_SALTO_BONUS or 0
				if extra > 0 then
					horiz = empujon(horiz, extra)
					sumarCombo(now)
				end
				vy = saltar(C.JUMP_VELOCITY, now)
				setY = true
			end
			grounded = false
		else
			-- en el aire de cara a una pared (sin haber trepado ya): trepar
			local frente = not s.wallrun and not s.trepadoUsado and wish:Dot(adelante) > 0.5 and vy > -25 and paredEn(adelante, C.TREPAR_DISTANCIA, 0.5)
			local n
			if frente then
				local nf = flat(frente.Normal).Unit
				s.trepar = { normal = nf, hasta = now + C.TREPAR_DURACION * 0.8, punto = frente.Position }
				s.trepadoUsado = true
				vy = saltar(C.TREPAR_VEL * 0.85, now)
				horiz = -nf * 2
				sumarCombo(now)
				setY = true
			elseif s.wallrun then
				n = s.wallrun.normal
			else
				n = muroCercano()
			end
			if n and not (s.ultimaPared and s.ultimaPared:Dot(n) > 0.7) then
				n = unitOr(flat(n), n)
				local paralelo = flat(horiz - n * horiz:Dot(n))
				local dir = unitOr(paralelo + n * C.MURO_SALTO_FUERA, n)
				if wish.Magnitude > 0 and wish:Dot(n) > -0.2 then
					dir = unitOr(dir:Lerp(wish, 0.35), dir)
				end
				horiz = empujon(dir * math.max(horiz.Magnitude, C.RUN_BASE), C.MURO_SALTO_BONUS, dir)
				vy = saltar(C.MURO_SALTO_ARRIBA, now)
				s.ultimaPared = n
				s.wallrun = nil
				sumarCombo(now)
				setY = true
			end
		end
	end

	-- Trepando por la pared
	if s.trepar then
		local t = s.trepar
		local sigue = now < t.hasta and paredEn(-t.normal, C.TREPAR_DISTANCIA + 0.5, 0.5) ~= nil
		if sigue then
			local resto = (t.hasta - now) / C.TREPAR_DURACION
			vy = C.TREPAR_VEL * (0.35 + 0.65 * resto)
			horiz = -t.normal * 3
			setY = true
			s.agarre = t.punto + Vector3.new(0, 2 + (1 - resto) * 3, 0)
			s.comboUltimoAt = now
		else
			s.trepar = nil
			s.agarre = nil
			s.ultimaPared = t.normal
		end
	end

	-- ¿Agarrar una barra?
	if not grounded and not s.trepar and now - s.barraSoltadaAt > C.BARRA_ESPERA then
		local b = buscarBarra()
		if b then
			agarrarBarra(b, Vector3.new(horiz.X, vy, horiz.Z), now)
			sonar("paso", 0.7, 0.6)
			publicar(false)
			return
		end
	end

	if grounded then
		-- Slide
		if s.slideHeld and not s.sliding and horiz.Magnitude >= C.SLIDE_MIN_START and now > s.aturdidoHasta then
			s.sliding = true
			if now - s.slideBoostAt > C.SLIDE_BOOST_ESPERA then
				s.slideBoostAt = now
				horiz = empujon(horiz, C.SLIDE_BOOST)
				sumarCombo(now)
			end
		end
		if s.sliding and (not s.slideHeld or horiz.Magnitude < C.SLIDE_MIN_SPEED) then
			s.sliding = false
		end

		if s.sliding then
			horiz = applyFriction(horiz, C.SLIDE_FRICTION, dt)
			local n = hit.Normal
			local g = Vector3.new(0, -C.GRAVITY, 0)
			local cuesta = flat(g - n * g:Dot(n))
			horiz += cuesta * C.SLIDE_CUESTA * dt
			horiz = steer(horiz, wish, C.SLIDE_STEER, dt)
			if cuesta.Magnitude > 5 then
				s.comboUltimoAt = now
				s.flujo = math.max(s.flujo, math.min(horiz.Magnitude, C.MAX_SPEED))
			end
		elseif now < s.aturdidoHasta then
			horiz = applyFriction(horiz, C.GROUND_FRICTION, dt)
		elseif wish.Magnitude > 0 then
			local rapidez = horiz.Magnitude
			if rapidez < C.RUN_BASE - 0.5 then
				-- arrancando
				horiz = applyFriction(horiz, C.GROUND_FRICTION * 0.3, dt)
				horiz = accelerate(horiz, wish, C.RUN_BASE, C.GROUND_ACCEL, dt)
				s.flujo = C.RUN_BASE
			else
				-- corriendo: cuanto más rápido, más cuesta girar
				local dir = horiz / rapidez
				local alineado = dir:Dot(wish)
				local giro = C.GIRO_SUELO * math.clamp(C.RUN_BASE / rapidez, 0.35, 1)
				horiz = steer(horiz, wish, giro, dt)
				if alineado > 0.8 then
					if s.flujo < C.FLUJO_MAX then
						s.flujo = math.min(s.flujo + C.FLUJO_GANA * dt, C.FLUJO_MAX)
					else
						s.flujo = math.max(s.flujo - C.FLUJO_DECAE * dt, C.FLUJO_MAX)
					end
				else
					s.flujo = math.max(s.flujo - C.FLUJO_PIERDE_GIRO * (0.8 - alineado) * dt, C.RUN_BASE)
				end
				-- frenar si pides ir hacia atrás
				if alineado < -0.3 then
					horiz = applyFriction(horiz, C.GROUND_FRICTION, dt)
				else
					local objetivo = s.flujo
					if rapidez < objetivo then
						rapidez = math.min(rapidez + math.max(C.FLUJO_GANA, (objetivo - rapidez) * 4) * dt, objetivo)
					else
						rapidez = math.max(rapidez - C.FLUJO_DECAE * dt, objetivo)
					end
					horiz = unitOr(horiz, wish) * rapidez
				end
			end
		else
			-- soltar las teclas: frenas, y el flujo baja poco a poco (no de golpe)
			horiz = applyFriction(horiz, C.GROUND_FRICTION, dt)
			s.flujo = math.max(C.RUN_BASE, math.min(s.flujo - C.FLUJO_SOLTAR * dt, math.max(horiz.Magnitude, C.RUN_BASE)))
		end
	elseif not s.trepar then
		-- ¿Correr por la pared?
		if not s.wallrun and horiz.Magnitude >= C.WALLRUN_VEL_MIN and wish.Magnitude > 0 and wish:Dot(horiz.Unit) > 0.3 then
			local n, lado, punto = paredLateral(horiz.Unit)
			if n and not (s.ultimaPared and s.ultimaPared:Dot(n) > 0.7) then
				s.wallrun = { normal = n, lado = lado, hasta = now + C.WALLRUN_DURACION, punto = punto }
				vy = math.max(vy, C.WALLRUN_SUBIDA_INICIAL)
				horiz = empujon(horiz, C.WALLRUN_BONUS)
				sumarCombo(now)
				setY = true
			end
		end

		if s.wallrun then
			local w = s.wallrun
			local dirMov = unitOr(horiz, adelante)
			local n, lado, punto = paredLateral(dirMov)
			local sigue = n and n:Dot(w.normal) > 0.8 and now < w.hasta and wish.Magnitude > 0 and horiz.Magnitude >= C.WALLRUN_VEL_MIN * 0.6
			if sigue then
				w.normal, w.lado, w.punto = n, lado, punto
				local tangente = unitOr(flat(dirMov - n * dirMov:Dot(n)), dirMov)
				horiz = tangente * horiz.Magnitude - n * 2
				vy = math.max(vy - C.WALLRUN_GRAVEDAD * dt, -C.WALLRUN_CAIDA_MAX)
				setY = true
				s.comboUltimoAt = now
				s.agarre = punto + Vector3.new(0, 1.5, 0) + tangente * 1.5
			else
				s.ultimaPared = w.normal
				s.wallrun = nil
				s.agarre = nil
			end
		end

		if not s.wallrun then
			horiz = accelerate(horiz, wish, C.AIR_WISH_CAP, C.AIR_ACCEL, dt)
			horiz = steer(horiz, wish, C.AIR_STEER, dt)
		end
	end
	s.wallrunLado = s.wallrun and s.wallrun.lado or 0
	if not s.wallrun and not s.trepar and s.modo == "normal" then
		s.agarre = nil
	end

	-- Paredes: no empujar contra ellas. Chocar de frente corriendo rápido te corta el flujo.
	if not s.wallrun and not s.trepar then
		local deFrente
		horiz, deFrente = deslizarParedes(horiz, dt)
		if deFrente and grounded and s.speed > C.RUN_BASE + 4 and now - s.golpeParedAt > 0.5 then
			s.golpeParedAt = now
			s.flujo = math.max(C.RUN_BASE, C.RUN_BASE + (s.flujo - C.RUN_BASE) * (1 - C.CHOQUE_PIERDE))
			s.landDip = 0.6
			sonar("aterrizar", 1.3, 0.4)
		end
	end

	if horiz.Magnitude > C.MAX_SPEED and now > s.empujeHasta then
		horiz = horiz.Unit * C.MAX_SPEED
	end

	linVel.VectorVelocity = horiz
	if setY then
		root.AssemblyLinearVelocity = Vector3.new(horiz.X, vy, horiz.Z)
	end
	s.speed = horiz.Magnitude

	-- pasos
	if grounded and not s.sliding and s.speed > 2 then
		s.paso += dt * s.speed / C.ZANCADA * math.pi
		if math.floor(s.paso / math.pi) ~= math.floor(s.pasoAnterior / math.pi) then
			sonar("paso", 1.5 + s.speed / 120, 0.18 + s.speed / 300)
		end
	elseif s.wallrun then
		s.paso += dt * s.speed / C.ZANCADA * math.pi * 1.2
		if math.floor(s.paso / math.pi) ~= math.floor(s.pasoAnterior / math.pi) then
			sonar("paso", 1.8, 0.2)
		end
	end
	s.pasoAnterior = s.paso

	publicar(grounded)
end

------------------------------------------------------------------------
-- Cámara: FOV por velocidad, balanceo al correr, inclinaciones, voltereta al rodar
------------------------------------------------------------------------

-- Todo lo que se aplica a la cámara "de adorno" (balanceo, inclinaciones, voltereta)
-- se guarda en s.offsetCam y se deshace justo antes de que Roblox mueva la cámara
-- el frame siguiente. Si no, esos giros se irían sumando y acabarías mirando al suelo.
s.offsetCam = CFrame.identity

local function deshacerOffset()
	if s.offsetCam ~= CFrame.identity then
		camera.CFrame *= s.offsetCam:Inverse()
		s.offsetCam = CFrame.identity
	end
end

local function aplicarOffset(cf)
	camera.CFrame *= cf
	s.offsetCam *= cf
end

-- gira de verdad la vista hacia la horizontal (esto sí se queda)
local function nivelarVista(dt, rapidez)
	local look = camera.CFrame.LookVector
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	local objetivo = math.rad(-4)
	local delta = (objetivo - pitch) * math.min(dt * rapidez, 1)
	if math.abs(delta) > 1e-4 then
		camera.CFrame *= CFrame.Angles(delta, 0, 0)
	end
end

local function cameraStep(dt)
	if not humanoid then
		return
	end
	local now = os.clock()
	local speedT = math.clamp((s.speed - C.RUN_BASE) / (C.FOV_SPEED_FOR_MAX - C.RUN_BASE), 0, 1)
	s.fovPunch += (0 - s.fovPunch) * math.min(dt * 5, 1)
	local targetFov = C.FOV_BASE + speedT * C.FOV_MAX_EXTRA + s.fovPunch
	camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(dt * 7, 1)

	-- inclinación: de lado al moverte, hacia fuera en la pared, un poco en el slide
	local targetRoll = -controls:GetMoveVector().X * C.ROLL_MAX
	if s.sliding then
		targetRoll += 3
	end
	targetRoll += s.wallrunLado * C.WALLRUN_INCLINACION
	s.roll += (targetRoll - s.roll) * math.min(dt * 9, 1)

	-- balanceo al correr (sube y baja con cada paso, y se mece un poco)
	local enSuelo = s.wasGrounded and not s.sliding and s.modo == "normal"
	local amp = enSuelo and math.clamp(s.speed / C.RUN_BASE, 0, 1.4) * C.BALANCEO_CAMARA or 0
	local bobY = -math.abs(math.sin(s.paso)) * amp
	local bobRoll = math.sin(s.paso) * amp * 4

	-- salto de valla rápido: el cuerpo se tumba de lado (piernas en horizontal)
	local vallaRoll, vallaBaja = 0, 0
	if s.modo == "valla" and s.anim and s.anim.rapida then
		local t = math.clamp((now - s.anim.inicio) / s.anim.duracion, 0, 1)
		local curva = math.sin(t * math.pi)
		vallaRoll = (s.ladoValla or 1) * 18 * curva
		vallaBaja = -0.5 * curva
	end

	-- al escalar, la vista vuelve sola a mirar al frente
	if s.modo == "escalar" and s.anim then
		local t = math.clamp((now - s.anim.inicio) / s.anim.duracion, 0, 1)
		if t > 0.3 then
			nivelarVista(dt, 7)
		end
	end

	aplicarOffset(CFrame.new(0, bobY + vallaBaja, 0) * CFrame.Angles(0, 0, math.rad(s.roll + bobRoll + vallaRoll)))

	-- voltereta al rodar
	local tr = (now - s.rodarInicio) / C.RODAR_DURACION
	if tr >= 0 and tr < 1 then
		-- amortiguar la caída: la cabeza se inclina hacia delante y vuelve
		local curva = math.sin(math.min(tr * 1.4, 1) * math.pi)
		aplicarOffset(CFrame.Angles(-curva * math.rad(28), 0, curva * math.rad(6)))
	end

	-- escalar: la cabeza baja un poco al empujar el borde
	if s.modo == "escalar" and s.anim then
		local t = math.clamp((now - s.anim.inicio) / s.anim.duracion, 0, 1)
		aplicarOffset(CFrame.Angles(-math.sin(t * math.pi) * math.rad(6), 0, 0))
	end

	s.landDip += (0 - s.landDip) * math.min(dt * 9, 1)
	local agachado = (tr >= 0 and tr < 1) and math.sin(tr * math.pi) * 1.8 or 0
	local drop = (s.sliding and C.SLIDE_CAMERA_DROP or 0) + s.landDip + agachado
	local current = humanoid.CameraOffset.Y
	humanoid.CameraOffset = Vector3.new(0, current + (-drop - current) * math.min(dt * 14, 1), 0)

	-- sonidos continuos: viento según la velocidad y roce en slide/pared
	local viento = sonidos.viento
	local objetivoViento = math.clamp((s.speed - C.FLUJO_MAX * 0.8) / 30, 0, 1) * 0.5 * C.VOLUMEN
	viento.Volume += (objetivoViento - viento.Volume) * math.min(dt * 4, 1)
	viento.PlaybackSpeed = 0.8 + speedT * 0.5
	if viento.Volume > 0.01 and not viento.IsPlaying then
		viento:Play()
	end
	local roce = sonidos.roce
	local objetivoRoce = (s.sliding or s.wallrunLado ~= 0 or s.trepar) and 0.35 * C.VOLUMEN or 0
	roce.Volume += (objetivoRoce - roce.Volume) * math.min(dt * 10, 1)
	roce.PlaybackSpeed = s.sliding and 0.55 or 1.4
	if roce.Volume > 0.01 and not roce.IsPlaying then
		roce:Play()
	end
end

------------------------------------------------------------------------
-- HUD: velocidad y combo (discreto, bajo la mira)
------------------------------------------------------------------------

local hud = Instance.new("ScreenGui")
hud.Name = "HUDMovimiento"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.Parent = player:WaitForChild("PlayerGui")

local speedLabel = Instance.new("TextLabel")
speedLabel.AnchorPoint = Vector2.new(0.5, 0)
speedLabel.Position = UDim2.new(0.5, 0, 0.5, 58)
speedLabel.Size = UDim2.fromOffset(200, 20)
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextSize = 15
speedLabel.TextColor3 = Color3.new(1, 1, 1)
speedLabel.TextTransparency = 0.35
speedLabel.TextStrokeTransparency = 0.7
speedLabel.Text = ""
speedLabel.Parent = hud

local comboLabel = speedLabel:Clone()
comboLabel.Position = UDim2.new(0.5, 0, 0.5, 76)
comboLabel.TextColor3 = Color3.fromRGB(255, 214, 236)
comboLabel.Parent = hud

local crosshair = Instance.new("Frame")
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(4, 4)
crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
crosshair.BackgroundTransparency = 0.2
crosshair.BorderSizePixel = 0
crosshair.Parent = hud
Instance.new("UICorner", crosshair).CornerRadius = UDim.new(1, 0)

-- medidor de inercia: barrita fina bajo la mira (vacía = velocidad base, llena = tope)
local barraFondo = Instance.new("Frame")
barraFondo.AnchorPoint = Vector2.new(0.5, 0)
barraFondo.Position = UDim2.new(0.5, 0, 0.5, 50)
barraFondo.Size = UDim2.fromOffset(120, 4)
barraFondo.BackgroundColor3 = Color3.new(1, 1, 1)
barraFondo.BackgroundTransparency = 0.75
barraFondo.BorderSizePixel = 0
barraFondo.Parent = hud
Instance.new("UICorner", barraFondo).CornerRadius = UDim.new(1, 0)
local barraRelleno = Instance.new("Frame")
barraRelleno.Size = UDim2.fromScale(0, 1)
barraRelleno.BackgroundColor3 = Color3.fromRGB(255, 200, 225)
barraRelleno.BorderSizePixel = 0
barraRelleno.Parent = barraFondo
Instance.new("UICorner", barraRelleno).CornerRadius = UDim.new(1, 0)
local rellenoVisto = 0

local function hudStep()
	local objetivo = math.clamp((s.speed - C.RUN_BASE) / (C.MAX_SPEED - C.RUN_BASE), 0, 1)
	rellenoVisto += (objetivo - rellenoVisto) * 0.2
	barraRelleno.Size = UDim2.fromScale(rellenoVisto, 1)
	-- la marca de "flujo corriendo" se nota porque la barra cambia de color al pasarla
	local pasado = s.speed > C.FLUJO_MAX + 1
	barraRelleno.BackgroundColor3 = pasado and Color3.fromRGB(255, 150, 200) or Color3.fromRGB(255, 220, 235)
	speedLabel.Text = string.format("%d", math.floor(s.speed + 0.5))
	comboLabel.Text = s.combo >= 2 and ("x" .. s.combo) or ""
end

------------------------------------------------------------------------
-- Controles
------------------------------------------------------------------------

UserInputService.JumpRequest:Connect(function()
	local now = os.clock()
	if now - s.lastJumpRequest > 0.1 then
		s.jumpBufferedAt = now
	end
	s.lastJumpRequest = now
end)

ContextActionService:BindActionAtPriority("Slide", function(_, state)
	if state == Enum.UserInputState.Begin then
		s.slideHeld = true
		s.slidePressedAt = os.clock()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		s.slideHeld = false
	end
	return Enum.ContextActionResult.Sink
end, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB)
ContextActionService:SetTitle("Slide", "Slide")
ContextActionService:SetPosition("Slide", UDim2.new(1, -170, 1, -80))

------------------------------------------------------------------------
-- Personaje
------------------------------------------------------------------------

local function onCharacter(char)
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")
	rayParams.FilterDescendantsInstances = { char, camera }
	resetState()

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	-- silenciar los sonidos por defecto de Roblox (usamos los nuestros)
	task.delay(0.5, function()
		for _, snd in root:GetChildren() do
			if snd:IsA("Sound") then
				snd.Volume = 0
			end
		end
	end)

	local att = Instance.new("Attachment")
	att.Name = "MovimientoAttachment"
	att.Parent = root

	linVel = Instance.new("LinearVelocity")
	linVel.Name = "MovimientoVelocity"
	linVel.Attachment0 = att
	linVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linVel.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	linVel.MaxAxesForce = Vector3.new(1e5, 0, 1e5)
	linVel.VectorVelocity = Vector3.zero
	linVel.Parent = root

	humanoid.Died:Connect(function()
		if linVel then
			linVel.Enabled = false
		end
		linVel = nil
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

ReplicatedStorage:WaitForChild("Remotos"):WaitForChild("Empujon").OnClientEvent:Connect(function(vector)
	if typeof(vector) ~= "Vector3" or not humanoid then
		return
	end
	if s.modo == "barra" and s.barra then
		soltarBarra(false, os.clock())
	elseif s.modo == "valla" or s.modo == "escalar" then
		s.modo = "normal"
		s.anim = nil
		s.agarre = nil
		cuerpoManual(false)
	end
	s.trepar = nil
	s.empujePendiente = vector
end)

RunService.PreSimulation:Connect(step)
RunService:BindToRenderStep("MovimientoDeshacerCamara", Enum.RenderPriority.Camera.Value - 1, deshacerOffset)
RunService:BindToRenderStep("MovimientoCamara", Enum.RenderPriority.Camera.Value + 1, function(dt)
	cameraStep(dt)
	hudStep()
end)
