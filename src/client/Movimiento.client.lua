-- Movimiento en primera persona: ritmo medio y con peso, velocidad por inercia.
--
-- Mecánicas:
--   · Correr y saltar (el salto solo desde el suelo).
--   · Slide: en llano frena poco; cuesta abajo acelera.
--   · Pared: corres por ella si vas rápido y en paralelo; desde cualquier muro cercano
--     puedes saltar en el aire (es el único "doble salto"). Cada salto de pared suma velocidad.
--   · Escalar bordes: si llegas a un borde alcanzable empujando hacia él, te agarras y subes.
--   · Barras (etiqueta "Barra"): te agarras en el aire, te columpias (W/S para bombear)
--     y al saltar sales lanzado con más velocidad. Slide para soltarte sin más.
--   · Aterrizaje: desde muy alto, pulsa slide justo antes de tocar suelo para rodar y
--     ganar velocidad; si no, el golpe te frena.
--
-- El Humanoid se encarga de colisiones y gravedad; la velocidad horizontal la calcula
-- este script y la aplica con un LinearVelocity en X y Z.
-- Publica su estado en atributos del jugador (Mov*) para los brazos y el servidor.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()

local PRIORIDAD = Enum.ContextActionPriority.High.Value
local UP = Vector3.yAxis

local humanoid, root, linVel
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local s = {} -- estado; se reinicia en cada aparición

local function resetState()
	s.modo = "normal" -- "normal" | "escalar" | "barra"
	s.wasGrounded = false
	s.lastGroundedAt = -math.huge
	s.lastJumpAt = -math.huge
	s.jumpBufferedAt = -math.huge
	s.lastJumpRequest = -math.huge
	s.lastAirVelY = 0

	s.slideHeld = false
	s.slidePressedAt = -math.huge
	s.sliding = false

	s.wallrun = nil -- { normal, lado, hasta }
	s.wallrunLado = 0
	s.ultimaPared = nil -- normal del último muro usado (no repetir el mismo sin tocar suelo)

	s.escalar = nil -- { desde, hasta, inicio, duracion, salida }
	s.barra = nil -- { punto, eje, frente, theta, omega }
	s.barraSoltadaAt = -math.huge

	s.rodandoHasta = -math.huge
	s.rodarInicio = -math.huge
	s.aturdidoHasta = -math.huge

	s.combo = 0
	s.comboUltimoAt = -math.huge

	s.empujePendiente = nil
	s.empujeHasta = -math.huge

	s.fovPunch = 0
	s.landDip = 0
	s.roll = 0
	s.speed = 0
end
resetState()

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v, alt)
	return v.Magnitude > 0.001 and v.Unit or alt
end

local function accelerate(vel, wishDir, wishSpeed, accel, dt)
	if wishDir.Magnitude == 0 then
		return vel
	end
	local current = vel:Dot(wishDir)
	local add = wishSpeed - current
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

-- gira la velocidad hacia wishDir sin cambiar su módulo
local function steer(vel, wishDir, rate, dt)
	local speed = vel.Magnitude
	if speed < 0.01 or wishDir.Magnitude == 0 then
		return vel
	end
	local dir = vel / speed
	if dir:Dot(wishDir) < -0.2 then
		return vel
	end
	return unitOr(dir:Lerp(wishDir, math.clamp(rate * dt, 0, 1)), dir) * speed
end

local function feetY()
	return root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2)
end

local function groundHit()
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 0.4
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
end

local function wishDirection()
	local move = controls:GetMoveVector() -- x = derecha, z = -adelante
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

-- muro a izquierda o derecha según hacia dónde vas → normal, lado
local function paredLateral(adelante)
	local derecha = adelante:Cross(UP)
	for _, lado in { 1, -1 } do
		local hit = workspace:Raycast(root.Position, derecha * lado * C.WALLRUN_DISTANCIA, rayParams)
		if hit and math.abs(hit.Normal.Y) < 0.3 then
			return hit.Normal, lado
		end
	end
	return nil
end

-- cualquier muro cerca (8 direcciones) → normal
local function muroCercano()
	local mejor, mejorDist = nil, math.huge
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local hit = workspace:Raycast(root.Position, dir * C.MURO_SALTO_DISTANCIA, rayParams)
		if hit and math.abs(hit.Normal.Y) < 0.3 and hit.Distance < mejorDist then
			mejor, mejorDist = hit.Normal, hit.Distance
		end
	end
	return mejor
end

------------------------------------------------------------------------
-- Escalar bordes
------------------------------------------------------------------------

local function buscarBorde(adelante)
	-- 1) pared delante, a la altura del pecho
	local pecho = root.Position
	local hitPared = workspace:Raycast(pecho, adelante * C.ESCALAR_ALCANCE, rayParams)
	if not hitPared or math.abs(hitPared.Normal.Y) > 0.3 then
		-- también a la altura de la cintura (bordes bajos)
		hitPared = workspace:Raycast(pecho - Vector3.new(0, 1.5, 0), adelante * C.ESCALAR_ALCANCE, rayParams)
		if not hitPared or math.abs(hitPared.Normal.Y) > 0.3 then
			return nil
		end
	end
	local dentro = -flat(hitPared.Normal).Unit
	-- 2) desde arriba, bajar justo detrás del borde para encontrar la superficie
	local pies = feetY()
	local arriba = Vector3.new(hitPared.Position.X, pies + C.ESCALAR_ALTURA_MAX + 0.5, hitPared.Position.Z) + dentro * 1.2
	local hitSuelo = workspace:Raycast(arriba, Vector3.new(0, -(C.ESCALAR_ALTURA_MAX + 0.5), 0), rayParams)
	if not hitSuelo or hitSuelo.Normal.Y < 0.7 then
		return nil
	end
	local altura = hitSuelo.Position.Y - pies
	if altura < C.ESCALAR_ALTURA_MIN or altura > C.ESCALAR_ALTURA_MAX then
		return nil
	end
	-- 3) que quepa el cuerpo encima
	local alturaCuerpo = humanoid.HipHeight + root.Size.Y
	local destinoPies = hitSuelo.Position + dentro * 0.8
	if workspace:Raycast(destinoPies + Vector3.new(0, 0.2, 0), Vector3.new(0, alturaCuerpo + 0.5, 0), rayParams) then
		return nil
	end
	return destinoPies + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 + 0.05, 0), dentro, altura
end

------------------------------------------------------------------------
-- Barras
------------------------------------------------------------------------

local function buscarBarra()
	local manos = root.Position + Vector3.new(0, 2.6, 0)
	local mejor, mejorDist = nil, C.BARRA_AGARRE
	for _, b in CollectionService:GetTagged("Barra") do
		if b:IsA("BasePart") and b:IsDescendantOf(workspace) then
			local eje = b.CFrame.RightVector -- las barras son cilindros: su eje es X
			if math.abs(eje.Y) < 0.3 then
				local largo = b.Size.X / 2
				local rel = manos - b.Position
				local t = math.clamp(rel:Dot(eje), -largo + 0.5, largo - 0.5)
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
	-- "frente" = dirección horizontal perpendicular a la barra hacia donde ibas
	local frente = UP:Cross(b.eje)
	local ref = flat(vel).Magnitude > 2 and flat(vel) or flat(camera.CFrame.LookVector)
	if frente:Dot(ref) < 0 then
		frente = -frente
	end
	local o = root.Position - b.punto
	local theta = math.atan2(o:Dot(frente), -o.Y)
	local tangente = frente * math.cos(theta) + UP * math.sin(theta)
	local omega = vel:Dot(tangente) / C.BARRA_RADIO
	s.barra = { punto = b.punto, eje = b.eje, frente = frente, theta = theta, omega = omega }
	s.modo = "barra"
	s.wallrun = nil
	s.sliding = false
	linVel.Enabled = false
	humanoid.PlatformStand = true
end

local function soltarBarra(conImpulso, now)
	local b = s.barra
	s.barra = nil
	s.modo = "normal"
	s.barraSoltadaAt = now
	linVel.Enabled = true
	humanoid.PlatformStand = false
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	local tangente = b.frente * math.cos(b.theta) + UP * math.sin(b.theta)
	local v = tangente * (b.omega * C.BARRA_RADIO)
	if conImpulso then
		v = v * C.BARRA_IMPULSO + UP * C.BARRA_SALTO_EXTRA
		sumarCombo(now)
		s.fovPunch = C.FOV_GOLPE
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
	-- péndulo
	local alpha = -(C.GRAVITY / C.BARRA_RADIO) * math.sin(b.theta)
	-- bombear: W en el sentido del balanceo cuando vas por abajo
	local wish = wishDirection()
	local empuje = wish:Dot(b.frente)
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
	-- tope: no pasar por encima de la barra
	if math.abs(b.theta) > 2.4 then
		b.theta = math.sign(b.theta) * 2.4
		b.omega = -b.omega * 0.3
	end

	local pos = b.punto + (b.frente * math.sin(b.theta) - UP * math.cos(b.theta)) * C.BARRA_RADIO
	local mirar = flat(camera.CFrame.LookVector)
	local giro = mirar.Magnitude > 0.01 and CFrame.lookAt(Vector3.zero, mirar) or CFrame.identity
	root.CFrame = CFrame.new(pos) * giro
	local tangente = b.frente * math.cos(b.theta) + UP * math.sin(b.theta)
	root.AssemblyLinearVelocity = tangente * (b.omega * C.BARRA_RADIO)
	s.speed = math.abs(b.omega * C.BARRA_RADIO)

	-- saltar = salir lanzado; slide = soltarse
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
	player:SetAttribute("MovModo", s.modo) -- "normal" | "escalar" | "barra"
	player:SetAttribute("MovBarra", s.barra and s.barra.punto or nil)
	player:SetAttribute("MovRodando", os.clock() < s.rodandoHasta)
	player:SetAttribute("MovCombo", s.combo)
end

local function step(dt)
	if not (root and humanoid and linVel) or humanoid.Health <= 0 then
		return
	end
	dt = math.min(dt, 1 / 20)
	local now = os.clock()

	-- el combo caduca si llevas un rato corriendo normal por el suelo
	if s.combo > 0 and s.wasGrounded and not s.sliding and now - s.comboUltimoAt > C.COMBO_CADUCA then
		s.combo = 0
	end

	-- Columpiándose en una barra
	if s.modo == "barra" then
		pasoBarra(dt, now)
		s.wallrunLado = 0
		publicar(false)
		return
	end

	-- Subiendo un borde
	if s.modo == "escalar" then
		local e = s.escalar
		local t = math.clamp((now - e.inicio) / e.duracion, 0, 1)
		-- primero sube, luego avanza
		local subida = math.min(t / 0.65, 1)
		local avance = math.clamp((t - 0.35) / 0.65, 0, 1)
		subida = 1 - (1 - subida) ^ 2
		local pos = Vector3.new(
			e.desde.X + (e.hasta.X - e.desde.X) * avance,
			e.desde.Y + (e.hasta.Y - e.desde.Y) * subida,
			e.desde.Z + (e.hasta.Z - e.desde.Z) * avance
		)
		root.CFrame = CFrame.new(pos) * (root.CFrame - root.CFrame.Position)
		root.AssemblyLinearVelocity = Vector3.zero
		linVel.VectorVelocity = Vector3.zero
		if t >= 1 then
			s.modo = "normal"
			s.escalar = nil
			humanoid.PlatformStand = false
			linVel.Enabled = true
			linVel.VectorVelocity = e.salida
			root.AssemblyLinearVelocity = e.salida
			s.lastGroundedAt = now
		end
		s.speed = e.salida.Magnitude
		publicar(true)
		return
	end

	local vel = root.AssemblyLinearVelocity
	local horiz = flat(vel)
	local vy = vel.Y
	local setY = false
	local wish = wishDirection()

	-- Suelo
	local hit = groundHit()
	local grounded = hit ~= nil and (now - s.lastJumpAt) > 0.1 and vy <= 2
	if grounded then
		if not s.wasGrounded then
			-- aterrizaje
			local caida = -s.lastAirVelY
			s.landDip = math.clamp(caida / 120, 0, 1) * C.LAND_DIP_MAX
			if caida >= C.CAIDA_FUERTE then
				if now - s.slidePressedAt <= C.RODAR_VENTANA or s.slideHeld then
					-- rodar: conservas la velocidad y ganas un poco
					local dir = unitOr(horiz, unitOr(flat(camera.CFrame.LookVector), Vector3.zAxis))
					horiz = dir * math.min(math.max(horiz.Magnitude, C.WALK_SPEED) + C.RODAR_BONUS, C.MAX_SPEED)
					s.rodarInicio = now
					s.rodandoHasta = now + C.RODAR_DURACION
					s.landDip = 0.3
					sumarCombo(now)
				else
					-- golpe: te frena y te aturde un momento
					horiz *= C.GOLPE_FRENO
					s.aturdidoHasta = now + C.GOLPE_ATURDIDO
					s.combo = 0
				end
			end
		end
		s.lastGroundedAt = now
		s.wallrun = nil
		s.ultimaPared = nil
	else
		s.lastAirVelY = vy
	end
	s.wasGrounded = grounded

	-- Empujón recibido (manotazo de otro jugador)
	if s.empujePendiente then
		local e = s.empujePendiente
		s.empujePendiente = nil
		horiz = flat(e)
		vy = e.Y
		setY = true
		s.sliding = false
		s.wallrun = nil
		s.lastJumpAt = now
		s.lastGroundedAt = -math.huge
		grounded = false
		s.empujeHasta = now + C.EMPUJE_SIN_LIMITE
		s.fovPunch = C.FOV_GOLPE
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	-- Saltos: desde el suelo, o desde un muro estando en el aire
	if now - s.jumpBufferedAt <= C.JUMP_BUFFER and now > s.aturdidoHasta then
		local jumped = false
		if grounded or now - s.lastGroundedAt <= C.COYOTE_TIME then
			vy = C.JUMP_VELOCITY
			jumped = true
		else
			local n = s.wallrun and s.wallrun.normal or muroCercano()
			if n and not (s.ultimaPared and s.ultimaPared:Dot(n) > 0.7) then
				-- salto de pared: fuera y arriba, ganando velocidad
				local rapidez = math.min(math.max(horiz.Magnitude, C.WALK_SPEED) + C.MURO_SALTO_BONUS, C.MAX_SPEED)
				local paralelo = flat(horiz - n * horiz:Dot(n))
				local dir = unitOr(paralelo + n * C.MURO_SALTO_FUERA, n)
				-- si empujas hacia algún sitio, el salto se tuerce un poco hacia ahí
				if wish.Magnitude > 0 and wish:Dot(n) > -0.2 then
					dir = unitOr(dir:Lerp(wish, 0.35), dir)
				end
				horiz = flat(dir).Unit * rapidez
				vy = C.MURO_SALTO_ARRIBA
				s.ultimaPared = n
				s.wallrun = nil
				sumarCombo(now)
				s.fovPunch = C.FOV_GOLPE * 0.6
				jumped = true
			end
		end
		if jumped then
			setY = true
			s.jumpBufferedAt = -math.huge
			s.lastJumpAt = now
			s.lastGroundedAt = -math.huge
			s.sliding = false
			grounded = false
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end

	-- ¿Escalar un borde? (empujando hacia delante, en el aire o corriendo contra él)
	if wish.Magnitude > 0 and not s.sliding and now > s.aturdidoHasta then
		local adelante = unitOr(flat(camera.CFrame.LookVector), wish)
		if wish:Dot(adelante) > 0.5 and (not grounded or horiz.Magnitude > 4) then
			local destino, dentro, altura = buscarBorde(adelante)
			if destino and (not grounded or altura > 3) then
				local salida = dentro * math.max(horiz.Magnitude * C.ESCALAR_CONSERVA, C.WALK_SPEED * 0.6)
				s.escalar = {
					desde = root.Position,
					hasta = destino,
					inicio = now,
					duracion = C.ESCALAR_DURACION * math.clamp(altura / 6, 0.6, 1.2),
					salida = salida,
				}
				s.modo = "escalar"
				s.wallrun = nil
				humanoid.PlatformStand = true
				linVel.Enabled = false
				sumarCombo(now)
				publicar(true)
				return
			end
		end
	end

	-- ¿Agarrar una barra?
	if not grounded and now - s.barraSoltadaAt > C.BARRA_ESPERA then
		local b = buscarBarra()
		if b then
			agarrarBarra(b, Vector3.new(horiz.X, vy, horiz.Z), now)
			publicar(false)
			return
		end
	end

	if grounded then
		-- Slide
		if s.slideHeld and not s.sliding and horiz.Magnitude >= C.SLIDE_MIN_START then
			s.sliding = true
		end
		if s.sliding and (not s.slideHeld or horiz.Magnitude < C.SLIDE_MIN_SPEED) then
			s.sliding = false
		end

		if s.sliding then
			horiz = applyFriction(horiz, C.SLIDE_FRICTION, dt)
			-- cuesta abajo acelera
			local n = hit.Normal
			local g = Vector3.new(0, -C.GRAVITY, 0)
			local cuesta = flat(g - n * g:Dot(n))
			horiz += cuesta * C.SLIDE_CUESTA * dt
			horiz = steer(horiz, wish, C.SLIDE_STEER, dt)
			if cuesta.Magnitude > 5 then
				s.comboUltimoAt = now -- deslizar cuesta abajo mantiene el combo
			end
		elseif now < s.aturdidoHasta then
			horiz = applyFriction(horiz, C.GROUND_FRICTION, dt)
		elseif horiz.Magnitude > C.WALK_SPEED + 0.5 and wish.Magnitude > 0 then
			-- con inercia: se pierde poco a poco y se gira con peso
			local rapidez = math.max(horiz.Magnitude - C.INERCIA_PERDIDA * dt, C.WALK_SPEED)
			horiz = steer(horiz, wish, C.INERCIA_GIRO, dt)
			horiz = unitOr(horiz, wish) * rapidez
		else
			horiz = applyFriction(horiz, C.GROUND_FRICTION, dt)
			horiz = accelerate(horiz, wish, C.WALK_SPEED, C.GROUND_ACCEL, dt)
		end
	else
		-- ¿Correr por la pared?
		if not s.wallrun and horiz.Magnitude >= C.WALLRUN_VEL_MIN and wish.Magnitude > 0 and wish:Dot(horiz.Unit) > 0.3 then
			local n, lado = paredLateral(horiz.Unit)
			if n and not (s.ultimaPared and s.ultimaPared:Dot(n) > 0.7) then
				s.wallrun = { normal = n, lado = lado, hasta = now + C.WALLRUN_DURACION }
				vy = math.max(vy, C.WALLRUN_SUBIDA_INICIAL)
				setY = true
			end
		end

		if s.wallrun then
			local w = s.wallrun
			local adelante = unitOr(horiz, unitOr(flat(camera.CFrame.LookVector), Vector3.zAxis))
			local n, lado = paredLateral(adelante)
			local sigue = n and n:Dot(w.normal) > 0.8 and now < w.hasta
				and wish.Magnitude > 0 and horiz.Magnitude >= C.WALLRUN_VEL_MIN * 0.6
			if sigue then
				w.normal, w.lado = n, lado
				local tangente = unitOr(flat(adelante - n * adelante:Dot(n)), adelante)
				horiz = tangente * horiz.Magnitude - n * 2 -- un poco hacia la pared para no despegarse
				vy = math.max(vy - C.WALLRUN_GRAVEDAD * dt, -C.WALLRUN_CAIDA_MAX)
				setY = true
				s.comboUltimoAt = now
			else
				s.ultimaPared = w.normal
				s.wallrun = nil
			end
		end

		if not s.wallrun then
			horiz = accelerate(horiz, wish, C.AIR_WISH_CAP, C.AIR_ACCEL, dt)
			horiz = steer(horiz, wish, C.AIR_STEER, dt)
		end
	end
	s.wallrunLado = s.wallrun and s.wallrun.lado or 0

	if horiz.Magnitude > C.MAX_SPEED and now > s.empujeHasta then
		horiz = horiz.Unit * C.MAX_SPEED
	end

	linVel.VectorVelocity = horiz
	if setY then
		root.AssemblyLinearVelocity = Vector3.new(horiz.X, vy, horiz.Z)
	end
	s.speed = horiz.Magnitude
	publicar(grounded)
end

------------------------------------------------------------------------
-- Cámara: FOV por velocidad, inclinaciones, bajada al deslizar, voltereta al rodar
------------------------------------------------------------------------

local function cameraStep(dt)
	if not humanoid then
		return
	end
	local now = os.clock()
	local speedT = math.clamp((s.speed - C.WALK_SPEED) / (C.FOV_SPEED_FOR_MAX - C.WALK_SPEED), 0, 1)
	s.fovPunch += (0 - s.fovPunch) * math.min(dt * 6, 1)
	local targetFov = C.FOV_BASE + speedT * C.FOV_MAX_EXTRA + s.fovPunch
	camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(dt * 8, 1)

	local targetRoll = -controls:GetMoveVector().X * C.ROLL_MAX
	if s.sliding then
		targetRoll += 2
	end
	targetRoll += s.wallrunLado * C.WALLRUN_INCLINACION
	s.roll += (targetRoll - s.roll) * math.min(dt * 10, 1)
	camera.CFrame *= CFrame.Angles(0, 0, math.rad(s.roll))

	-- voltereta al rodar
	if now < s.rodandoHasta then
		local t = (now - s.rodarInicio) / C.RODAR_DURACION
		local e = t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
		camera.CFrame *= CFrame.Angles(-e * math.pi * 2, 0, 0)
	end

	-- escalando: la cámara se inclina hacia el borde
	if s.modo == "escalar" and s.escalar then
		local t = math.clamp((now - s.escalar.inicio) / s.escalar.duracion, 0, 1)
		camera.CFrame *= CFrame.Angles(-math.sin(t * math.pi) * math.rad(10), 0, 0)
	end

	s.landDip += (0 - s.landDip) * math.min(dt * 10, 1)
	local drop = (s.sliding and C.SLIDE_CAMERA_DROP or 0) + s.landDip + (now < s.rodandoHasta and 1.5 or 0)
	local current = humanoid.CameraOffset.Y
	humanoid.CameraOffset = Vector3.new(0, current + (-drop - current) * math.min(dt * 14, 1), 0)
end

------------------------------------------------------------------------
-- HUD de pruebas: velocidad y combo
------------------------------------------------------------------------

local hud = Instance.new("ScreenGui")
hud.Name = "HUDMovimiento"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.Parent = player:WaitForChild("PlayerGui")

local speedLabel = Instance.new("TextLabel")
speedLabel.AnchorPoint = Vector2.new(0.5, 1)
speedLabel.Position = UDim2.new(0.5, 0, 1, -24)
speedLabel.Size = UDim2.fromOffset(200, 30)
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextSize = 22
speedLabel.TextColor3 = Color3.new(1, 1, 1)
speedLabel.TextStrokeTransparency = 0.6
speedLabel.Parent = hud

local comboLabel = speedLabel:Clone()
comboLabel.Position = UDim2.new(0.5, 0, 1, -52)
comboLabel.TextSize = 18
comboLabel.TextColor3 = Color3.fromRGB(255, 214, 236)
comboLabel.Parent = hud

local crosshair = Instance.new("Frame")
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(4, 4)
crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
crosshair.BorderSizePixel = 0
crosshair.Parent = hud
Instance.new("UICorner", crosshair).CornerRadius = UDim.new(1, 0)

local function hudStep()
	speedLabel.Text = string.format("%d", math.floor(s.speed + 0.5))
	comboLabel.Text = s.combo >= 2 and ("COMBO x" .. s.combo) or ""
end

------------------------------------------------------------------------
-- Controles (teclado, mando y botones táctiles)
------------------------------------------------------------------------

-- JumpRequest sirve para teclado, mando y el botón táctil de Roblox.
-- Mientras se mantiene pulsado se repite; solo cuenta una pulsación nueva.
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
end, true, PRIORIDAD, Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB)
ContextActionService:SetTitle("Slide", "Slide")
ContextActionService:SetPosition("Slide", UDim2.new(1, -170, 1, -80))

------------------------------------------------------------------------
-- Personaje
------------------------------------------------------------------------

local function onCharacter(char)
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")
	local filtro = { char }
	local brazos = camera:FindFirstChild("BrazosVista")
	if brazos then
		table.insert(filtro, brazos)
	end
	rayParams.FilterDescendantsInstances = filtro
	resetState()

	-- El salto lo hacemos nosotros; nada de escalar "a lo Roblox"
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

	local att = Instance.new("Attachment")
	att.Name = "MovimientoAttachment"
	att.Parent = root

	linVel = Instance.new("LinearVelocity")
	linVel.Name = "MovimientoVelocity"
	linVel.Attachment0 = att
	linVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linVel.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	linVel.MaxAxesForce = Vector3.new(1e6, 0, 1e6) -- en Y manda la gravedad
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

-- El servidor avisa cuando te dan un manotazo
ReplicatedStorage:WaitForChild("Remotos"):WaitForChild("Empujon").OnClientEvent:Connect(function(vector)
	if typeof(vector) ~= "Vector3" then
		return
	end
	if s.modo == "barra" and s.barra then
		soltarBarra(false, os.clock())
	elseif s.modo == "escalar" then
		s.modo = "normal"
		s.escalar = nil
		if humanoid then
			humanoid.PlatformStand = false
		end
		if linVel then
			linVel.Enabled = true
		end
	end
	s.empujePendiente = vector
end)

RunService.PreSimulation:Connect(step)
RunService:BindToRenderStep("MovimientoCamara", Enum.RenderPriority.Camera.Value + 1, function(dt)
	cameraStep(dt)
	hudStep()
end)
