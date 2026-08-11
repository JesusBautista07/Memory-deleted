# REPORTE_BUILDINGS_ESCENARIO.md

## Aviso importante sobre validación
No tengo Godot disponible en este entorno, así que esto es **validación
estática** (rutas, IDs de recursos, transforms calculados a mano, bounding
boxes reales medidas con Assimp sobre los .fbx/.glb). No he podido abrirlo
en el editor. La primera vez que lo abras, Godot importará
`Buildings.glb` y `Trees.fbx` automáticamente; revisa la consola por si
salta algún warning.

Fui estrictamente a los archivos necesarios: `tests/Test_Final_System.tscn`,
`scenes/player/Player.tscn` y las 6 escenas de personajes PSX en
`scenes/characters/psx/`. No toqué nada de movimiento, cámara, interacción,
inventario, armas, puertas, pausa ni InputMap.

## 1. Personaje delante de la cámara

En `Player.tscn`, el nodo `CharacterVisual` (instancia de
`Male_Variant_PielMedia_CabelloNegro.tscn`, el cuerpo del jugador en
primera persona) quedó con `visible = false`. No lo borré ni desconecté
nada: solo se oculta, así que reactivarlo es cambiar ese valor a `true`.

## 2. Escala de los personajes PSX (bug de escala Mixamo)

Medí con Assimp la bounding box real de cada `.fbx` de Characters_psx.
Todos declaran `UnitScaleFactor = 1` (cm), que es lo que Godot usa para
convertir automáticamente a metros al importar — y aun así, después de esa
conversión, los modelos entran a **~4.5–5.9 metros de alto**. Es el bug de
escala típico de personajes exportados desde Mixamo (el armature trae un
factor ×100 extra ya horneado). Lo comprobé comparando contra
`Trees.dae`/`Trees.fbx` (que sí entra a escala correcta) y contra
`Superhero_Male_FullBody.gltf` (1.81 m, ya usado como referencia en el
proyecto).

Corrección aplicada: `scale` en el nodo `Model` de cada escena PSX, para
dejarlos en alturas humanas coherentes entre sí:

| Escena | Alto original (aprox.) | Escala aplicada | Alto resultante |
|---|---|---|---|
| PSXCharacterVisual_Male01 | 4.70 m | 0.383 | ~1.80 m |
| PSXNPC_Male02 | 4.60 m | 0.387 | ~1.78 m |
| PSXNPC_Police17 | 4.77 m | 0.388 | ~1.85 m |
| PSXNPC_Female02 | 4.45 m | 0.371 | ~1.65 m |
| PSXNPC_Female03 | 4.57 m | 0.361 | ~1.65 m |
| PSXNPC_Monster | 5.93 m | 0.371 | ~2.20 m (a propósito, más alto que los humanos) |

El sistema de retargeting de animaciones (`PSXAnimationRetargeter`) busca
el `Skeleton3D` dentro de `Model` en tiempo de ejecución y no depende de la
escala del nodo contenedor, así que esto no debería afectar animaciones.
No verifiqué esto último en el editor real — si al abrir el proyecto ves
algo raro en huesos/animaciones, avísame.

## 3. Mapa de prueba ampliado

`Floor` en `Test_Final_System.tscn` pasó de 30×30 a **400×400** (mesh y
colisión). Todos los objetos de prueba que ya existían (puertas, pickups,
armas, escaleras, rampa, dummy, NPCs, etc.) se dejaron exactamente donde
estaban, cerca del origen — solo se agrandó el suelo alrededor.

## 4. Bosque y edificios (Trees + Buildings)

Copié los assets originales sin tocarlos:
- `assets/models/environment/buildings/Buildings.glb` (el pack ya trae 10
  edificios distintos agrupados en un solo archivo, con texturas
  embebidas — no hace falta la carpeta `Textures/` suelta).
- `assets/models/environment/trees/Trees.fbx` + todas sus texturas
  (`Wood_*.jpg`, `Branch_*.png`) — el `.fbx` no trae texturas embebidas,
  así que estas sí van sueltas al lado del modelo.

En `Test_Final_System.tscn`, dentro de tres nodos nuevos
(`Environment_Forest`, `Environment_Buildings`, `Environment_Paths`) añadí:
- 6 instancias de `Trees.fbx` (cada una ya es un grupo de ~9 árboles)
  repartidas en un anillo alrededor del área de pruebas, con distintas
  rotaciones para que no se vea repetitivo.
- 2 instancias de `Buildings.glb` (cada una ya trae los 10 edificios del
  pack) en dos esquinas del mapa, alejadas del área de pruebas y del
  bosque.
- 3 franjas planas (`Path_North`, `Path_West`, `Path_East`) con un
  material color tierra a modo de caminos que salen del área central hacia
  el bosque/edificios.

**Limitación conocida (a propósito, para no salirme del alcance):** los
árboles y edificios son solo visuales, **sin colisión** — el jugador puede
atravesarlos. Si quieres que bloqueen el paso, dímelo y lo agrego
(collision shapes aproximadas por edificio/tronco), pero eso ya es un
cambio adicional que no incluí aquí.

## 5. Dependencias faltantes
Ninguna. Todo lo necesario (Buildings.glb, Trees.fbx + texturas) va
incluido en esta entrega.

## Archivos modificados
- `scenes/player/Player.tscn`
- `tests/Test_Final_System.tscn`
- `scenes/characters/psx/PSXCharacterVisual_Male01.tscn`
- `scenes/characters/psx/PSXNPC_Male02.tscn`
- `scenes/characters/psx/PSXNPC_Female02.tscn`
- `scenes/characters/psx/PSXNPC_Female03.tscn`
- `scenes/characters/psx/PSXNPC_Police17.tscn`
- `scenes/characters/psx/PSXNPC_Monster.tscn`

## Archivos nuevos
- `assets/models/environment/buildings/Buildings.glb`
- `assets/models/environment/trees/Trees.fbx`
- `assets/models/environment/trees/Wood*.jpg`, `Branch*.png` (26 texturas)

## Cómo aplicar esta entrega
Descomprime este ZIP dentro de la raíz de tu proyecto Godot (mismas rutas
`res://...`), sobrescribiendo los 8 archivos `.tscn` modificados y
añadiendo los archivos nuevos de `assets/models/environment/`.
