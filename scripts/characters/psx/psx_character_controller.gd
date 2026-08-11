class_name PSXCharacterController
extends Node3D
## Controlador reutilizable para CUALQUIER personaje visual de
## Characters_psx usado como modelo del jugador en primera persona.
##
## Responsabilidades:
## 1. En _ready(): localizar el Skeleton3D del modelo PSX instanciado como
##    hijo ("Model"), generar la AnimationLibrary retargeted (ver
##    PSXAnimationRetargeter) a partir de la librería universal ya
##    existente en el proyecto (SharedAnimationLibrary) y añadirla a un
##    AnimationPlayer propio.
## 2. En _physics_process(): leer el estado del PlayerMovement (velocidad,
##    is_crouching, is_on_floor) y reproducir la animación retargeted que
##    corresponda (Idle / Walk / Sprint / Crouch / Jump).
##
## NO controla movimiento, cámara ni colisiones -eso lo sigue haciendo
## PlayerMovement/CameraController sin cambios-, solo el aspecto visual y
## la animación, igual que character_variant.gd hace para el personaje
## Superhero. Este script es independiente de ese: no lo modifica ni lo
## sustituye.

## Nombres de animación dentro de UAL1_Standard.glb (los mismos que ya usa
## el resto del proyecto vía SharedAnimationLibrary) que este controlador
## sabe reproducir. Si alguno faltara en la librería retargeted (por
## ejemplo porque todos sus tracks dependieran de huesos sin mapear), se
## avisa por consola en vez de fallar en silencio.
##
## CORRECCIÓN: estas constantes usaban nombres inventados ("Idle", "Walk",
## "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump") que no existen en
## UAL1_Standard.glb, así que has_animation() siempre fallaba y este
## controlador nunca llegó a reproducir ninguna animación real. Idle/Walk/
## Sprint ahora reutilizan los mismos nombres que LocomotionState (fuente
## única para el jugador y para cualquier otro personaje que use este
## controlador); Crouch/Jump usan los nombres reales equivalentes que sí
## existen en la librería.
const ANIM_IDLE := LocomotionState.ANIM_IDLE
const ANIM_WALK := LocomotionState.ANIM_WALK
const ANIM_SPRINT := LocomotionState.ANIM_SPRINT
const ANIM_CROUCH_IDLE := "Crouch_Idle_Loop"
const ANIM_CROUCH_WALK := "Crouch_Fwd_Loop"
const ANIM_JUMP := "Jump_Loop"

## Ruta al nodo PlayerMovement cuyo estado se lee para decidir la
## animación. Por defecto asume que este controlador cuelga como hijo del
## propio Player (CharacterBody3D con player_movement.gd), igual que
## CharacterVisual en Player.tscn.
@export var movement_node_path: NodePath = NodePath("..")

## Velocidad horizontal mínima para considerar que el personaje se está
## moviendo (evita parpadeo Idle/Walk por ruido numérico a velocidad casi
## cero).
@export var move_speed_threshold: float = 0.15

@onready var _model: Node3D = $Model
@onready var _anim_player: AnimationPlayer = $RetargetedAnimationPlayer
@onready var _movement: PlayerMovement = get_node_or_null(movement_node_path) as PlayerMovement

var _skeleton: Skeleton3D = null
var _current_state_anim: String = ""


func _ready() -> void:
	if _movement == null:
		push_warning("PSXCharacterController (%s): no se encontró PlayerMovement en '%s'. La animación no reaccionará al movimiento." % [name, str(movement_node_path)])

	_skeleton = PSXAnimationRetargeter.apply_to(_model, _anim_player, name)
	if _skeleton == null:
		return

	_play_state(ANIM_IDLE)


func _physics_process(_delta: float) -> void:
	if _movement == null or _anim_player == null:
		return
	_play_state(_resolve_current_state())


# ---------------------------------------------------------------------------
# SELECCIÓN DE ESTADO / ANIMACIÓN
# ---------------------------------------------------------------------------

func _resolve_current_state() -> String:
	if not _movement.is_on_floor():
		return ANIM_JUMP

	var horizontal_speed := Vector2(_movement.velocity.x, _movement.velocity.z).length()
	var is_moving := horizontal_speed > move_speed_threshold

	if _movement.is_crouching:
		return ANIM_CROUCH_WALK if is_moving else ANIM_CROUCH_IDLE

	return LocomotionState.resolve(horizontal_speed, _movement.walk_speed, move_speed_threshold)


func _play_state(state_anim: String) -> void:
	if state_anim == _current_state_anim:
		return

	# Se marca el estado como "intentado" ANTES de comprobar si la
	# animación existe. Así, si no existe, la próxima llamada con este
	# mismo state_anim se corta en el guard de arriba en vez de volver a
	# intentarlo (y volver a avisar) en cada _physics_process().
	_current_state_anim = state_anim

	var full_name := PSXAnimationRetargeter.RETARGET_LIBRARY_NAME + "/" + state_anim
	if not _anim_player.has_animation(full_name):
		push_warning(
			"PSXCharacterController (%s): la animación '%s' no está disponible tras el retargeting (revisa el aviso de huesos omitidos)."
			% [name, full_name]
		)
		return

	_anim_player.play(full_name)
