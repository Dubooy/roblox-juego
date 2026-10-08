-- Ajustes del movimiento. Todo lo que define "cómo se siente" está aquí:
-- cambia números y prueba (Play) sin tocar el resto del código.
-- Velocidades en studs/segundo, tiempos en segundos.

return {
	GRAVITY = 196.2,

	-- Suelo
	WALK_SPEED = 22, -- velocidad objetivo andando
	GROUND_ACCEL = 12, -- cuánto tarda en llegar a WALK_SPEED (más = más seco)
	GROUND_FRICTION = 8, -- frenado al soltar las teclas
	STOP_SPEED = 10, -- por debajo de esto el frenado es constante (para parar del todo)

	-- Aire
	AIR_ACCEL = 40,
	AIR_WISH_CAP = 4, -- pequeño = el "strafe" en el aire suma velocidad poco a poco (bunny-hop)
	AIR_STEER = 2.5, -- giro suave del impulso hacia donde pulsas, sin perder velocidad

	MAX_SPEED = 110, -- tope absoluto en horizontal

	-- Salto
	JUMP_VELOCITY = 55,
	AIR_JUMPS = 1, -- saltos extra en el aire (1 = doble salto)
	AIR_JUMP_VELOCITY = 50,
	COYOTE_TIME = 0.12, -- puedes saltar un instante después de salir de un borde
	JUMP_BUFFER = 0.12, -- si pulsas justo antes de tocar suelo, salta al aterrizar

	-- Dash
	DASH_CHARGES = 3,
	DASH_RECHARGE = 1.1, -- segundos por carga
	DASH_SPEED = 95,
	DASH_DURATION = 0.16,
	DASH_EXIT_SPEED = 45, -- velocidad mínima con la que sales del dash (conserva impulso)
	DASH_COOLDOWN = 0.12, -- entre dos dashes seguidos

	-- Deslizamiento (slide)
	SLIDE_MIN_START = 18, -- velocidad mínima para empezar a deslizar
	SLIDE_BOOST = 14, -- empujón al empezar
	SLIDE_BOOST_COOLDOWN = 1.0, -- para que no se pueda encadenar el empujón sin parar
	SLIDE_FRICTION = 0.6, -- rozamiento deslizando (bajo = deslizas más lejos)
	SLIDE_MIN_SPEED = 10, -- por debajo, el slide termina
	SLIDE_STEER = 1.2,
	SLIDE_CAMERA_DROP = 1.6, -- cuánto baja la cámara

	-- Cámara
	FOV_BASE = 75,
	FOV_MAX_EXTRA = 20, -- FOV extra a máxima velocidad
	FOV_SPEED_FOR_MAX = 80,
	FOV_DASH_PUNCH = 8,
	ROLL_MAX = 3, -- grados de inclinación al moverte de lado
	LAND_DIP_MAX = 1.2, -- golpe de cámara al aterrizar

	-- Servidor (anti-trampas básico)
	SERVER_SPEED_TOLERANCE = 1.35,
}
