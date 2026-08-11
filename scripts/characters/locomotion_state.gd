class_name LocomotionState
extends RefCounted
## Punto único de verdad para el trío de animaciones de locomoción básica
## (Idle/Walk/Sprint) que ya existen REALMENTE en UAL1_Standard.glb y que
## SharedAnimationLibrary (personajes Universal) y PSXAnimationRetargeter
## (personajes PSX, vía SharedAnimationLibrary como origen) exponen bajo
## su propio prefijo de librería ("UAL" o "PSX_UAL" respectivamente).
##
## Se usa desde character_variant.gd (jugador, modelo Universal actual) y
## psx_character_controller.gd (jugador o cualquier otro personaje PSX,
## ver Ticket de integración de animaciones) para no duplicar ni los
## nombres de animación ni el criterio de qué velocidad corresponde a
## cada estado.
##
## NPCWanderer (scripts/npc/npc_wanderer.gd) ya implementa este MISMO
## criterio (mismos nombres, mismo umbral) de forma independiente y no se
## ha migrado a esta clase para no tocar un sistema de NPC que ya
## funciona correctamente; si en el futuro se necesita, es un cambio
## mecánico y de bajo riesgo.

const ANIM_IDLE := "Idle"
const ANIM_WALK := "Walk"
const ANIM_SPRINT := "Sprint"

## Determina qué animación de locomoción corresponde al estado de
## movimiento actual.
## horizontal_speed: longitud (m/s) de la velocidad en el plano XZ.
## walk_speed: velocidad de referencia de "caminar" del propio personaje
##             (p. ej. PlayerMovement.walk_speed o NPCWanderer.walk_speed);
##             por encima de eso + un pequeño margen se considera Sprint.
## move_threshold: velocidad horizontal mínima para salir de Idle (evita
##                 parpadeo Idle/Walk por ruido numérico a velocidad casi
##                 cero).
static func resolve(horizontal_speed: float, walk_speed: float, move_threshold: float = 0.15) -> String:
	if horizontal_speed <= move_threshold:
		return ANIM_IDLE
	if horizontal_speed > walk_speed + 0.1:
		return ANIM_SPRINT
	return ANIM_WALK
