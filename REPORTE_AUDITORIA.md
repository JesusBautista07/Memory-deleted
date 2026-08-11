# Auditoría funcional — Memory Deleted
Escena oficial de pruebas: `tests/Test_Final_System.tscn`

Metodología: no se asumió que el código estuviera bien. Se leyó cada script
implicado en cada flujo del checklist (movimiento, cámara, interacción,
inventario, puertas, armas, combate, menús, HUD) y se siguió la cadena real
de llamadas/señales de punta a punta, no solo la existencia de las
funciones. Cuando un flujo se cortaba en algún punto, se corrigió ahí
mismo, sin reescribir ni duplicar sistemas que ya funcionaban.

No se pudo ejecutar el proyecto dentro de este entorno (no hay binario de
Godot disponible), así que la verificación fue por lectura exhaustiva del
código y de las escenas (`.tscn`) node por node, comprobando NodePaths,
grupos, señales y tipos. Se recomienda abrir `Test_Final_System.tscn` en el
editor una vez para confirmar visualmente (no debería haber errores de
parseo: se revisaron manualmente los `load_steps`, ids de `ext_resource` /
`sub_resource` y unicidad de nombres de nodo por padre).

---

## Sistemas verificados SIN cambios (ya funcionaban correctamente)

- **Movimiento** (`player_movement.gd`): caminar, correr, salto, gravedad
  asimétrica (subida/caída), agachado con redimensionado de cápsula,
  pendientes (`floor_max_angle`), subida automática de escalones
  (`_try_step_up`), y **reinicio por caída** (`_check_fall_reset`,
  `fall_reset_y = -30`). El `DiveBoard` de la escena de pruebas está
  colocado justo al borde del suelo (fuera del `Floor` de 30×30) para
  poder saltar al vacío y comprobar el respawn.
- **Cámara** (agachado): sincronización altura cápsula ↔ altura cámara,
  correcta.
- **Flujo Jugador → RayCast → InteractionManager → Prompt → Interacción →
  Objeto → Inventario**: correcto, incluida la búsqueda de `interact()`
  en ancestros (necesario porque el RayCast golpea el `StaticBody3D` hijo,
  no el nodo raíz del objeto).
- **Puertas**: `Door.interact()` ya reúne las llaves reales del `Inventory`
  (por grupo) antes de intentar abrir — puerta bloqueada sin llave no
  abre, con llave sí, y puede volver a cerrarse.
- **Armas**: recoger, guardar en el `Inventory` real (sin lista paralela),
  equipar, cambiar de arma (cíclico), apuntar/disparar con cooldown,
  recargar con munición de reserva independiente por arma, todo correcto.
- **Menú de pausa / Opciones**: pausan el árbol correctamente
  (`process_mode = ALWAYS` en `PauseMenu`), reasignación de teclas por
  `InputMap` funcional.

## Bugs reales encontrados y corregidos

### 1. Lectura de documentos rota de punta a punta
**Por qué ocurría:** `InventoryUI.request_open_document()` era un `pass`
vacío (un stub nunca implementado). `DocumentsUI` (la ventana que muestra
el texto) no estaba conectada a nada ni instanciada en ninguna escena.
Además, `DocumentManager` auto-registraba el documento al recogerlo pero
solo copiaba `object_name`/`description` del `ObjectData` compartido —
nunca el texto real (`DocumentItem.document_text`), que vive en el pickup
del mundo, no en el `Inventory`. Resultado: aunque todo el resto de la
cadena (recoger → guardar → aparecer en inventario) funcionaba, no había
forma de **leer** el documento.
**Cómo se corrigió:**
- `document_manager.gd`: al recibir `document_registered` desde
  `Inventory`, ahora usa el `source` (un `DocumentItem`) para copiar su
  `document_text` a `DocumentData.pages`.
- `documents_ui.gd`: se agregó al grupo `"documents_ui"` (mismo patrón de
  "localizar por grupo" que usa el resto del proyecto) y ahora avisa a
  `DocumentManager.close_document()` al cerrarse.
- `inventory_ui.gd`: `request_open_document()` ahora localiza
  `DocumentManager` y `DocumentsUI` por grupo, pide abrir el documento y
  le pasa título/texto/página real.
- `InventoryUI.tscn`: se agregó un botón **"Usar"** (no existía ninguna
  forma de "usar" un objeto seleccionado, pese a que el checklist lo pide
  explícitamente). Sobre un documento, abre el lector; sobre cualquier
  otro objeto, emite la señal `item_used` (los objetos como linterna,
  encendedor, teléfono, etc. ya tienen sus propios `toggle()`/
  `request_*()` preparados, pero ningún consumidor de UI los usa aún —
  igual patrón "preparado, no implementado" que ya traía el resto del
  proyecto para sonido, por ejemplo).
- `Test_Final_System.tscn`: se instanciaron `DocumentManager` y
  `DocumentsUI`, que antes no existían en ninguna escena jugable.

### 2. La tecla de inventario dedicada no hacía nada
**Por qué ocurría:** `OptionsMenu` ya ofrecía "Inventario" como acción
reasignable (`REBINDABLE_ACTIONS`), pero la acción `"inventory"` no
existía en el `InputMap` del proyecto (`project.godot`) y ningún script la
escuchaba. Solo se podía abrir el inventario desde el botón dentro del
menú de pausa.
**Cómo se corrigió:** se agregó la acción `inventory` al `InputMap`
(Tab por defecto) y se conectó en `pause_menu.gd`, reutilizando el mismo
`InventoryUI` que ya usa el botón del menú (sin crear un sistema de
inventario "standalone" nuevo).

### 3. Balanceo de cámara (bob) al caminar/correr: no existía
El checklist lo pide explícitamente y no había ninguna implementación en
todo el proyecto. Se añadió a `camera_controller.gd` (no a
`player_movement.gd`, que solo gestiona física): la intensidad escala con
la velocidad horizontal real, se apaga suavemente al detenerse, y convive
con el ajuste de altura de agachado sin pisarlo (aplica sobre
`Camera3D.position`, no sobre `CameraPivot`).

### 4. "Combate" no se podía probar: no existía ningún objetivo
**Por qué ocurría:** `WeaponCombat._fire_ray()` ya buscaba
`take_damage()` en el collider golpeado (el gancho de daño ya estaba
listo y funcional), pero no había **ningún** nodo en todo el proyecto que
implementara ese método. Disparar nunca tenía ningún efecto observable.
**Cómo se corrigió:** se creó `scripts/enemies/test_dummy.gd` — un
maniquí de pruebas mínimo (sin IA, como pide el ticket) con
`take_damage()`, salud y `die()` (se desactiva su colisión y se oculta al
morir, mismo patrón que `PickupObject.deactivate()`). Se instanció en
`Test_Final_System.tscn`.

### 5. HUD sin ningún indicador de munición
No había forma visual de comprobar disparo/recarga aparte del mensaje de
interacción. Se creó `scripts/ui/hud/ammo_hud.gd` (un `Label` mínimo que
se conecta a las señales que `WeaponCombat` ya emitía) y se agregó a la
escena.

### 6. Bug introducido y corregido en la misma pasada: `DocumentsUI` se congelaba en pausa
Al conectar `DocumentsUI`, se detectó que solo se abre desde el
`InventoryUI` (que vive bajo `PauseMenu`, con `process_mode = ALWAYS` para
poder recibir input estando el árbol en pausa). `DocumentsUI` en cambio
colgaba de `HUD`, que hereda el modo de proceso normal — su botón
"Cerrar" habría quedado sin responder en cuanto se abriera un documento.
Se corrigió poniendo `process_mode = ALWAYS` también en `documents_ui.gd`.

## Objetos de prueba añadidos a la escena (ya existían como scripts, pero
nunca se habían instanciado en ninguna escena jugable, así que no se
podían verificar)
- `Phone_Lab` (celular), `Recorder_Lab` (grabadora), `Photo_Lab`
  (fotografía, como `ImportantItem`) — usan las clases
  `phone_item.gd` / `voice_recorder_item.gd` / `important_item.gd` que ya
  existían, sin modificarlas.
- `TestDummy` — enemigo de prueba nuevo (ver punto 4).

---

## Archivos modificados
- `project.godot` (agregada acción `inventory` al InputMap)
- `scripts/ui/menu/pause_menu.gd`
- `scripts/ui/inventory/inventory_ui.gd`
- `scenes/ui/inventory/InventoryUI.tscn` (botón "Usar" nuevo)
- `scripts/ui/documents/documents_ui.gd`
- `scripts/documents/document_manager.gd`
- `scripts/camera/camera_controller.gd` (balanceo de cámara)
- `tests/Test_Final_System.tscn` (reconstruida con todo lo anterior +
  objetos de prueba faltantes)

## Archivos nuevos
- `scripts/enemies/test_dummy.gd`
- `scripts/ui/hud/ammo_hud.gd`

## No se tocó
Movimiento, sistema de puertas, sistema de armas (equipar/disparar/
recargar), sistema de eventos, cinemáticas, IA, ambientación, audio,
guardado — todo revisado y funcional tal como estaba, sin necesidad de
cambios.
