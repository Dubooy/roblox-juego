-- Ajustes del juego. Todo lo que define "cómo se siente" está aquí:
-- cambia números y prueba (Play) sin tocar el resto del código.
-- Velocidades en studs/segundo, tiempos en segundos.
--
-- Movimiento estilo Parkour Reborn:
--   · Corriendo en línea recta vas cogiendo FLUJO (velocidad) poco a poco.
--   · Cada mecánica bien hecha (saltar vallas, trepar, correr por la pared, saltar de
--     pared, slide, rodar, barras) te da un empujón y el flujo se mantiene si encadenas.
--   · Pierdes flujo al pararte, al girar de golpe, al chocar contra una pared o al
--     caer de alto sin rodar.

return {
	GRAVITY = 196.2,

	-- Correr y flujo
	RUN_BASE = 24, -- velocidad al empezar a correr
	FLUJO_MAX = 42, -- velocidad a la que llegas corriendo recto un rato
	FLUJO_GANA = 4.5, -- studs/s que ganas cada segundo corriendo recto
	FLUJO_PIERDE_GIRO = 30, -- pérdida por segundo al girar muy cerrado
	FLUJO_DECAE = 5, -- lo que bajas cada segundo si vas por encima de FLUJO_MAX (por empujones)
	GROUND_ACCEL = 11, -- arrancar desde parado (más = antes)
	GROUND_FRICTION = 9, -- frenado al soltar las teclas
	STOP_SPEED = 10,
	GIRO_SUELO = 7, -- lo rápido que giras corriendo despacio (a más velocidad, más peso)
	ZANCADA = 6.5, -- studs por paso (para pasos, balanceo de cámara y brazos)

	MAX_SPEED = 78, -- tope absoluto en horizontal

	-- Aire
	AIR_ACCEL = 24,
	AIR_WISH_CAP = 3,
	AIR_STEER = 1.8,

	-- Salto
	JUMP_VELOCITY = 58,
	COYOTE_TIME = 0.12,
	JUMP_BUFFER = 0.15,

	-- Saltar vallas (obstáculos bajos: se saltan solos al correr hacia ellos)
	VALLA_ALTURA_MIN = 1.3, -- por debajo es un escalón
	VALLA_ALTURA_MAX = 4.3,
	VALLA_VEL_MIN = 12,
	VALLA_DURACION = 0.26,
	VALLA_BONUS = 4,
	-- Salto de valla de parkour (con inercia): el cuerpo se tumba de lado con las piernas
	-- en horizontal, pasa más alto y más lejos, y sales más rápido
	VALLA_RAPIDA_VEL = 34, -- velocidad a partir de la que sale este salto
	VALLA_RAPIDA_ALTURA_MAX = 5.5,
	VALLA_RAPIDA_DURACION = 0.38,
	VALLA_RAPIDA_BONUS = 6,

	-- Escalar bordes altos (salta hacia el borde y te agarras)
	ESCALAR_ALTURA_MAX = 9.5, -- desde tus pies
	ESCALAR_ALCANCE = 2.8,
	ESCALAR_DURACION = 0.42,
	ESCALAR_CONSERVA = 0.7, -- parte de la velocidad que conservas al subir

	-- Trepar paredes (corre contra una pared y salta: subes corriendo por ella)
	TREPAR_VEL = 44, -- velocidad de subida inicial
	TREPAR_DURACION = 0.5,
	TREPAR_DISTANCIA = 2.8,

	-- Correr por la pared
	WALLRUN_DISTANCIA = 3,
	WALLRUN_VEL_MIN = 20,
	WALLRUN_DURACION = 1.3,
	WALLRUN_SUBIDA_INICIAL = 10,
	WALLRUN_GRAVEDAD = 24,
	WALLRUN_CAIDA_MAX = 12,
	WALLRUN_BONUS = 3, -- empujón al engancharte
	WALLRUN_INCLINACION = 10,

	-- Saltar desde un muro (en el aire, pegado a una pared)
	MURO_SALTO_DISTANCIA = 3.2,
	MURO_SALTO_FUERA = 28,
	MURO_SALTO_ARRIBA = 54,
	MURO_SALTO_BONUS = 5,

	-- Slide
	SLIDE_MIN_START = 18,
	SLIDE_BOOST = 8, -- empujón al empezar
	SLIDE_BOOST_ESPERA = 1.2, -- para que no se pueda encadenar sin parar
	SLIDE_FRICTION = 0.12,
	SLIDE_MIN_SPEED = 12,
	SLIDE_STEER = 1.0,
	SLIDE_CUESTA = 1.2, -- aceleración cuesta abajo (1 = gravedad real)
	SLIDE_SALTO_BONUS = 3,
	SLIDE_CAMERA_DROP = 1.7,

	-- Barras (columpiarse)
	BARRA_AGARRE = 2.8,
	BARRA_RADIO = 3.6,
	BARRA_BOMBEO = 3.2,
	BARRA_AMORTIGUA = 0.12,
	BARRA_IMPULSO = 1.3,
	BARRA_SALTO_EXTRA = 42,
	BARRA_ESPERA = 0.35,

	-- Aterrizaje
	CAIDA_FUERTE = 78, -- a partir de esta velocidad de caída hay que rodar
	RODAR_VENTANA = 0.3, -- pulsa slide como mucho este tiempo antes de tocar suelo
	RODAR_BONUS = 6,
	RODAR_DURACION = 0.5,
	GOLPE_FRENO = 0.45,
	GOLPE_ATURDIDO = 0.3,

	-- Combo (para las cinemáticas épicas)
	COMBO_CADUCA = 0.8,

	-- Cámara
	FOV_BASE = 74,
	FOV_MAX_EXTRA = 16,
	FOV_SPEED_FOR_MAX = 70,
	FOV_GOLPE = 5,
	ROLL_MAX = 2,
	LAND_DIP_MAX = 1.8,
	BALANCEO_CAMARA = 0.14, -- cuánto sube y baja la cámara al correr

	-- Sonido
	VOLUMEN = 0.6,

	-- Brazos (estilo Roblox clásico con tu piel y tu camiseta, entrando desde abajo)
	-- Posiciones respecto a la cámara: x derecha, y arriba, z hacia atrás (negativo = delante)
	BRAZOS_ESCALA = 0.75,
	BRAZOS_MANO = Vector3.new(0.95, -1.15, -2.3), -- mano derecha en reposo
	BRAZOS_HOMBRO = Vector3.new(1.3, -1.45, -0.2), -- hombro (fuera de la pantalla)
	BRAZOS_LARGO_BRAZO = 1.15, -- hombro → codo
	BRAZOS_LARGO_ANTEBRAZO = 1.3, -- codo → mano
	BRAZOS_MUELLE = 170, -- rigidez del muelle (más = siguen antes a su sitio)
	BRAZOS_AMORTIGUA = 0.62, -- 1 = sin rebote; menos = rebotan un poco (peso)

	-- Servidor (anti-trampas básico)
	SERVER_SPEED_TOLERANCE = 1.35,

	-- Manotazo (en la fase 3 llegan el congelado y las cinemáticas)
	MANOTAZO_ALCANCE = 8,
	MANOTAZO_ANGULO = 0.45, -- producto escalar mínimo con la vista (0.45 ≈ 63°)
	MANOTAZO_ESPERA = 0.7,
	MANOTAZO_EMPUJE = 45,
	MANOTAZO_EMPUJE_ARRIBA = 30,
	MANOTAZO_EMPUJE_EXTRA_VEL = 0.3,
	EMPUJE_SIN_LIMITE = 0.5, -- segundos en que el empujado puede superar la velocidad máxima

	-- Partida
	SOLO_MOVIMIENTO = true, -- fase 1: sin rondas ni bots, para probar el movimiento tranquilo
	MODO_INICIAL = "Contagio", -- más adelante se elegirá en el lobby
	JUGADORES_MINIMOS = 2, -- cuentan los bots
	PREPARACION = 8,
	VENTAJA_HUIDA = 4,
	DURACION_RONDA = 120,
	PAUSA_FINAL = 6,

	-- Bots
	PARTICIPANTES_OBJETIVO = 6, -- se rellenan con bots hasta este número
	BOT_VELOCIDAD = 22,
	BOT_PIENSA_CADA = 0.35,
}
