# Pilla-pilla de parkour para Roblox (prototipo)

Movimiento fluido en primera persona con dash, slide, doble salto, coyote time, buffer de
salto y bunny-hop, más un mapa de pruebas que se construye solo al pulsar **Play**.

## Controles (movimiento de parkour, estilo Parkour Reborn)

| Acción | Cómo |
|---|---|
| Correr | WASD. Corriendo recto vas cogiendo velocidad (flujo) |
| Saltar | Espacio (solo desde el suelo o apoyándote en un muro) |
| Saltar vallas | corre hacia un obstáculo bajo: se salta solo sin frenar |
| Salto de valla de parkour | igual, pero yendo rápido (34+): pasas tumbado con las piernas en horizontal, más alto y sales más rápido |
| Escalar un borde | salta hacia él empujando hacia delante |
| Trepar una pared | corre contra ella y pulsa saltar. Otra vez saltar = impulso hacia atrás |
| Correr por la pared | salta en paralelo a una pared yendo rápido y mantén W |
| Saltar desde un muro | en el aire, junto a una pared, pulsa saltar |
| Slide | Ctrl, C o Shift corriendo. Cuesta abajo acelera |
| Barras | salta hacia una. W/S balancea, Espacio te lanza, slide te suelta |
| Rodar | al caer de alto, pulsa slide justo antes de tocar el suelo |
| Manotazo | clic izquierdo o E |

Cada mecánica bien hecha te da un empujón de velocidad. Lo pierdes al pararte, al girar
de golpe, al chocar contra una pared o al caer de alto sin rodar.

## Pillar
- Al pillar, todo se congela un instante para los dos (destello y blanco y negro) y luego
  el pillado sale volando con una estela.
- **Pillado épico**: si se cumplen dos de estas (pillar en el aire, ir a 45 o más, llevar
  un combo de 3), salta una cinemática de 3 planos (~3 s): impacto casi congelado, giro
  alrededor a cámara lenta y el pillado volando visto desde abajo con su nombre. La ven
  los dos implicados, que son intocables mientras. El **último superviviente** siempre
  es épico y lo ve todo el mundo. Luego se sigue jugando.

## Mapas
- **Parque de calistenia**: circuito en forma de 8 alrededor de una estructura de barras
  (con un tobogán larguísimo desde 30 de altura) y de un bloque de cajas de parkour.
  Rectas con pasillos de paredes para correr por ellas y bancos para saltar.
- **Torre de obras**: edificio de 4 plantas abiertas con rampas, andamio con barras,
  pluma de la grúa inclinada para bajar deslizando hasta el edificio pequeño,
  tobogán de escombros y contenedores.
- **Pista de pruebas**: en el centro, donde apareces entre rondas. Con
  `SOLO_MOVIMIENTO = true` en `Config.lua` se juega solo en ella, sin rondas ni bots.

## Modo Contagio
Uno empieza pillando (se queda quieto unos segundos para daros ventaja). Cada jugador al que da un
manotazo pasa a pillar. Si al acabar el tiempo queda alguien sin pillar, ganan los que huyen.
Los pilladores se ven en rojo y los que huyen en azul, incluso a través de las paredes.
El modo "Corona robada" llegará con el lobby, donde se elegirá el modo.

## Probar
Abre `PillaParkour.rbxlx` en Studio y pulsa **Play**. Hay bots que rellenan la partida hasta 6
participantes, así que se puede jugar solo. Los mapas se alternan cada ronda:
**Parque de calistenia** y **Torre de obras**. Si cambias algo en `src/`, regenera el archivo con
`python3 herramientas/crear_rbxlx.py`.

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
- `Mapas.lua`: construye por código el parque de calistenia y la torre de obras.
- `Bots.lua`: bots que persiguen o huyen con pathfinding y dan manotazos.
- `Partida.server.lua`: manotazo, rondas, modos y mapas.
- `Brazos.client.lua`: tus brazos de verdad visibles en primera persona.

## Siguientes pasos
1. Wall-run y salto en pared.
2. Arma hitscan con validación en el servidor.
3. Sistema de mejoras roguelike (elegir 1 de 3 entre salas).
