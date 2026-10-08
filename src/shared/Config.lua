-- Ajustes del juego. Todo lo que define "cómo se siente" está aquí:
-- cambia números y prueba (Play) sin tocar el resto del código.
-- Velocidades en studs/segundo, tiempos en segundos.
--
-- Idea del movimiento: ritmo medio y con peso (tipo Mirror's Edge). No hay dash ni
-- doble salto. La velocidad se gana con INERCIA encadenando mecánicas: salir de una
-- barra, saltar de pared a pared, rodar al aterrizar y deslizar cuesta abajo.
-- Corriendo normal la inercia se va perdiendo poco a poco.

return {
	GRAVITY = 196.2,

	-- Suelo
	WALK_SPEED = 20, -- velocidad normal corriendo
	GROUND_ACCEL = 9, -- más = arranca antes
	GROUND_FRICTION = 7, -- frenado al soltar las teclas
	STOP_SPEED = 10,
	INERCIA_PERDIDA = 9, -- studs/s que pierdes cada segundo corriendo por encima de WALK_SPEED
	INERCIA_GIRO = 3, -- lo rápido que giras cuando llevas inercia (bajo = más peso)

	-- Aire
	AIR_ACCEL = 20,
	AIR_WISH_CAP = 3, -- poco control en el aire: el salto se decide antes de saltar
	AIR_STEER = 1.2,

	MAX_SPEED = 52, -- tope de velocidad horizontal

	-- Salto (solo desde el suelo; en el aire solo se salta apoyándose en un muro)
	JUMP_VELOCITY = 52,
	COYOTE_TIME = 0.12, -- puedes saltar un instante después de salir de un borde
	JUMP_BUFFER = 0.15, -- si pulsas justo antes de tocar suelo, salta al aterrizar

	-- Slide
	SLIDE_MIN_START = 16, -- velocidad mínima para empezar a deslizar
	SLIDE_FRICTION = 0.12, -- rozamiento en llano (bajo = deslizas más lejos)
	SLIDE_MIN_SPEED = 9, -- por debajo, el slide termina
	SLIDE_STEER = 1.0,
	SLIDE_CUESTA = 1.15, -- cuánto acelera deslizar cuesta abajo (1 = gravedad real)
	SLIDE_CAMERA_DROP = 1.6,

	-- Pared: correr por ella y saltar de pared a pared
	WALLRUN_DISTANCIA = 3, -- studs hasta la pared a cada lado
	WALLRUN_VEL_MIN = 15,
	WALLRUN_DURACION = 1.4, -- segundos máximos en la misma pared
	WALLRUN_SUBIDA_INICIAL = 8, -- al engancharte subes un poco
	WALLRUN_GRAVEDAD = 22, -- caída suave mientras corres
	WALLRUN_CAIDA_MAX = 12,
	WALLRUN_INCLINACION = 12, -- grados de inclinación de cámara
	MURO_SALTO_DISTANCIA = 3.2, -- distancia a un muro para poder saltar de él sin correr por él
	MURO_SALTO_FUERA = 26, -- empuje hacia fuera del muro
	MURO_SALTO_ARRIBA = 48,
	MURO_SALTO_BONUS = 4, -- velocidad que GANAS en cada salto de pared encadenado

	-- Escalar bordes
	ESCALAR_ALTURA_MIN = 2.2, -- por debajo es un escalón: se sube andando
	ESCALAR_ALTURA_MAX = 8, -- altura máxima del borde respecto a tus pies
	ESCALAR_ALCANCE = 2.6, -- distancia a la pared para agarrarte
	ESCALAR_DURACION = 0.38,
	ESCALAR_CONSERVA = 0.75, -- parte de la velocidad que conservas al terminar de subir

	-- Barras (columpiarse)
	BARRA_AGARRE = 2.8, -- distancia de tus manos a la barra para agarrarte
	BARRA_RADIO = 3.6, -- distancia de la barra a tu cuerpo colgado
	BARRA_BOMBEO = 3.2, -- impulso al pulsar W/S en el sentido del balanceo
	BARRA_AMORTIGUA = 0.12, -- pérdida de balanceo por segundo
	BARRA_IMPULSO = 1.25, -- multiplicador de velocidad al soltarte saltando
	BARRA_SALTO_EXTRA = 12, -- empujón hacia arriba al soltarte
	BARRA_ESPERA = 0.35, -- tras soltarte, tiempo antes de poder agarrar otra

	-- Aterrizaje: rodar o golpe
	CAIDA_FUERTE = 70, -- velocidad de caída a partir de la que el aterrizaje cuenta
	RODAR_VENTANA = 0.3, -- pulsa slide como mucho este tiempo antes de tocar suelo
	RODAR_BONUS = 5, -- velocidad que ganas al rodar bien
	RODAR_DURACION = 0.45,
	GOLPE_FRENO = 0.35, -- si no ruedas te quedas con esta parte de la velocidad
	GOLPE_ATURDIDO = 0.3,

	-- Combo: mecánicas encadenadas sin pararse (para las cinemáticas épicas)
	COMBO_CADUCA = 0.8, -- segundos andando normal antes de que el combo se pierda

	-- Cámara
	FOV_BASE = 75,
	FOV_MAX_EXTRA = 14, -- FOV extra a máxima velocidad
	FOV_SPEED_FOR_MAX = 50,
	FOV_GOLPE = 6,
	ROLL_MAX = 2.5, -- grados de inclinación al moverte de lado
	LAND_DIP_MAX = 1.6, -- golpe de cámara al aterrizar

	-- Brazos (copia de los de tu avatar pegada a la cámara)
	BRAZOS_ESCALA = 0.7, -- tamaño respecto a los brazos reales
	BRAZOS_HOMBRO = Vector3.new(1.05, -1.25, 0.35), -- dónde está el hombro respecto a la cámara (x derecha, y arriba, z atrás)

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
