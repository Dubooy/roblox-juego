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
	FLUJO_MAX = 38, -- velocidad a la que llegas corriendo recto un rato
	FLUJO_GANA = 3.5, -- studs/s que ganas cada segundo corriendo recto
	FLUJO_PIERDE_GIRO = 18, -- pérdida por segundo al girar muy cerrado
	FLUJO_SOLTAR = 25, -- pérdida por segundo al soltar las teclas
	FLUJO_DECAE = 2.5, -- lo que bajas cada segundo si vas por encima de FLUJO_MAX (por empujones)
	GROUND_ACCEL = 11, -- arrancar desde parado (más = antes)
	GROUND_FRICTION = 9, -- frenado al soltar las teclas
	STOP_SPEED = 10,
	GIRO_SUELO = 7, -- lo rápido que giras corriendo despacio (a más velocidad, más peso)
	ZANCADA = 6.5, -- studs por paso (para pasos, balanceo de cámara y brazos)

	MAX_SPEED = 68, -- tope absoluto en horizontal
	EMPUJON_CURVA = 1.6, -- cuánto se reducen los empujones al ir rápido (más = cuesta más llegar al tope)
	CHOQUE_PIERDE = 0.35, -- parte de la velocidad extra que pierdes al chocar de frente con una pared

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
	VALLA_BONUS = 3,
	-- Salto de valla de parkour (con inercia): el cuerpo se tumba de lado con las piernas
	-- en horizontal, pasa más alto y más lejos, y sales más rápido
	VALLA_RAPIDA_VEL = 34, -- velocidad a partir de la que sale este salto
	VALLA_RAPIDA_ALTURA_MAX = 5.5,
	VALLA_RAPIDA_DURACION = 0.38,
	VALLA_RAPIDA_BONUS = 5,

	-- Escalar bordes altos (salta hacia el borde y te agarras)
	ESCALAR_ALTURA_MAX = 9.5, -- desde tus pies
	ESCALAR_ALCANCE = 3.3,
	ESCALAR_MANOS = 2.6, -- cuánto por encima de tus manos puede estar el borde para agarrarlo
	ESCALAR_DURACION = 0.42,
	ESCALAR_CONSERVA = 0.7, -- parte de la velocidad que conservas al subir

	-- Trepar paredes (corre contra una pared y salta: subes corriendo por ella)
	TREPAR_VEL = 44, -- velocidad de subida inicial
	TREPAR_DURACION = 0.5,
	TREPAR_DISTANCIA = 2.8,

	-- Correr por la pared
	WALLRUN_DISTANCIA = 3.4,
	WALLRUN_VEL_MIN = 18,
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
	MURO_SALTO_BONUS = 4,

	-- Slide
	SLIDE_MIN_START = 18,
	SLIDE_BOOST = 6, -- empujón al empezar
	SLIDE_BOOST_ESPERA = 1.6, -- para que no se pueda encadenar sin parar
	SLIDE_FRICTION = 0.12,
	SLIDE_MIN_SPEED = 12,
	SLIDE_STEER = 1.0,
	SLIDE_CUESTA = 1.2, -- aceleración cuesta abajo (1 = gravedad real)
	SLIDE_SALTO_BONUS = 3,
	SLIDE_CAMERA_DROP = 1.7,

	-- Barras (columpiarse)
	BARRA_AGARRE = 3.6,
	BARRA_RADIO = 3.6,
	BARRA_BOMBEO = 3.2,
	BARRA_AMORTIGUA = 0.12,
	BARRA_IMPULSO = 1.3,
	BARRA_SALTO_EXTRA = 42,
	BARRA_ESPERA = 0.35,

	-- Aterrizaje
	CAIDA_FUERTE = 105, -- a partir de esta velocidad de caída hay que rodar (unos 28 studs de caída)
	RODAR_VENTANA = 0.3, -- pulsa slide como mucho este tiempo antes de tocar suelo
	RODAR_BONUS = 6,
	RODAR_DURACION = 0.4,
	GOLPE_PIERDE = 0.4, -- parte de la velocidad extra que pierdes al caer de alto sin rodar
	GOLPE_ATURDIDO = 0.2,

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

	-- Manotazo
	MANOTAZO_ALCANCE = 8,
	MANOTAZO_ANGULO = 0.45, -- producto escalar mínimo con la vista (0.45 ≈ 63°)
	MANOTAZO_ESPERA = 0.7,
	MANOTAZO_EMPUJE = 45,
	MANOTAZO_EMPUJE_ARRIBA = 30,
	MANOTAZO_EMPUJE_EXTRA_VEL = 0.3,
	EMPUJE_SIN_LIMITE = 0.8, -- segundos en que el empujado puede superar la velocidad máxima

	-- Pillar: todo se congela un instante para los dos y luego el pillado sale volando
	CONGELADO_GOLPE = 0.08, -- empujón sin pillar
	CONGELADO_PILLAR = 0.18, -- al pillar
	PILLADO_EMPUJE_EXTRA = 1.25, -- el pillado sale más lejos que en un empujón normal

	-- Pillado épico: cinemática de 3 planos (~3 s). Hacen falta EPICO_CONDICIONES de:
	-- pillar en el aire, ir a EPICO_VELOCIDAD o más, o llevar un combo de EPICO_COMBO.
	-- El último superviviente siempre es épico y lo ve todo el mundo.
	EPICO_CONDICIONES = 2,
	EPICO_VELOCIDAD = 45,
	EPICO_COMBO = 3,
	EPICO_EMPUJE_EXTRA = 1.35,
	CINE_PLANO1 = 0.8, -- impacto casi congelado, en blanco y negro
	CINE_PLANO2 = 1.2, -- giro alrededor a cámara lenta
	CINE_PLANO3 = 1.0, -- desde abajo, el pillado volando con su nombre
	CINE_DURACION = 3.0, -- suma de los tres (los dos implicados son intocables mientras)

	-- Partida
	SOLO_MOVIMIENTO = false, -- true = sin rondas ni bots, solo la pista de pruebas
	MODO_INICIAL = "Contagio", -- más adelante se elegirá en el lobby
	JUGADORES_MINIMOS = 2, -- cuentan los bots
	PREPARACION = 8,
	VENTAJA_HUIDA = 4,
	DURACION_RONDA = 120,
	PAUSA_FINAL = 6,
	MODO_LIBRE_DURACION = 90, -- sin rivales: segundos en cada mapa antes de pasar al siguiente

	-- Bots
	PARTICIPANTES_OBJETIVO = 6, -- se rellenan con bots hasta este número
	BOT_VELOCIDAD = 26,
	BOT_PIENSA_CADA = 0.35,
}
