# Pilla-pilla de parkour para Roblox (prototipo)

Movimiento fluido en primera persona con dash, slide, doble salto, coyote time, buffer de
salto y bunny-hop, más un mapa de pruebas que se construye solo al pulsar **Play**.

## Controles

| Acción | Teclado | Mando | Móvil |
|---|---|---|---|
| Moverse | WASD | stick izquierdo | joystick |
| Salto / doble salto | Espacio | A | botón de salto |
| Dash (3 cargas) | Shift izq. o Q | L1 o X | botón "Dash" |
| Slide (mantener) | Ctrl izq. o C | B | botón "Slide" |
| Manotazo (empuja) | clic izquierdo o E | R2 | botón "Manotazo" |

Abajo en pantalla ves la velocidad y las cargas de dash.

## Trucos para probar
- **Bunny-hop:** pulsa salto justo al aterrizar (hay un pequeño margen) y gira suavemente con el ratón
  mientras pulsas A o D: ganas velocidad.
- **Slide-hop:** corre, desliza (Ctrl) y salta durante el slide para conservar el empujón.
- **Dash + doble salto** para cruzar los huecos grandes del parkour.
- Desliza en la **bajada verde** (sube por la escalera) para alcanzar la velocidad máxima.

## Modo Contagio
Uno empieza pillando (se queda quieto unos segundos para daros ventaja). Cada jugador al que da un
manotazo pasa a pillar. Si al acabar el tiempo queda alguien sin pillar, ganan los que huyen.
Los pilladores se ven en rojo y los que huyen en azul, incluso a través de las paredes.
El modo "Corona robada" llegará con el lobby, donde se elegirá el modo.

## Probar con varios jugadores
Abre `MovimientoFPS.rbxlx` en Studio → pestaña **Probar** → en **Clientes y servidores** elige
**3 jugadores** → **Iniciar**. Se abre una ventana por jugador. Si cambias algo en `src/`,
regenera el archivo con `python3 herramientas/crear_rbxlx.py`.

## Cómo meterlo en Roblox Studio

### Opción A: copiar y pegar (sin instalar nada)
1. Crea un sitio nuevo en Studio (plantilla **Baseplate**).
2. En **ReplicatedStorage**, crea una carpeta `Shared` y dentro un **ModuleScript** llamado
   `Config`. Pega `src/shared/Config.lua`.
3. En **StarterPlayer → StarterPlayerScripts**, crea un **LocalScript** llamado `Movimiento`
   y pega `src/client/Movimiento.client.lua`.
4. En **ServerScriptService**, crea dos **Script**: `Validacion` y `PistaPruebas`,
   y pega sus archivos de `src/server/`.
5. Pulsa **Play**.

### Opción B: Rojo (recomendado para seguir desarrollando)
1. Instala [Rojo](https://rojo.space) y su plugin de Studio.
2. En esta carpeta: `rojo serve`.
3. En Studio, plugin de Rojo → **Connect**. Los cambios en los archivos se aplican al momento.

## Ajustar la sensación
Todo está en `src/shared/Config.lua`: velocidad, aceleración, fuerza del dash, duración del
slide, FOV, etc. Cambia un número, vuelve a pulsar Play y compara.

## Cómo funciona
- `Movimiento.client.lua`: el Humanoid se encarga de la gravedad y las colisiones, pero la
  velocidad horizontal la calcula el script (aceleración estilo Quake) y la aplica con un
  `LinearVelocity` solo en X y Z. Por eso se conserva el impulso.
- `Validacion.server.lua`: comprueba en el servidor que nadie supere la velocidad máxima
  posible. Por ahora solo avisa en la consola; servirá de base para el PvP.
- `PistaPruebas.server.lua`: el mapa de pruebas. Bórralo cuando tengas un mapa de verdad.

## Siguientes pasos
1. Wall-run y salto en pared.
2. Arma hitscan con validación en el servidor.
3. Sistema de mejoras roguelike (elegir 1 de 3 entre salas).
