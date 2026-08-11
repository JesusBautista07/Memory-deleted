class_name PSXNPCTestWalker
extends Node3D
## NPC de prueba SIN IA: reutiliza el mismo sistema de retargeting que el
## personaje del jugador (PSXAnimationRetargeter + PSXBoneRetargetMap) para
## comprobar que Idle / Walk / Sprint funcionan sobre distintos modelos de
## Characters_psx.
##
## Comportamiento (deliberadamente simple, sin NavigationAgent ni árbol de
## comportamiento): se queda en Idle, camina hacia delante
## `patrol_distance` metros, hace una pausa en Idle, vuelve corriendo
## (Sprint) al punto de partida, pausa en Idle, y repite. Esto basta para
## comprobar visualmente las 3 animaciones sin implementar IA de verdad.
##
## Requiere la misma estructura de hijos que PSXCharacterVisual:
##   Model (instancia de un .fbx de Characters_psx)
##   RetargetedAnimationPlayer (AnimationPlayer vacío)

enum _State { IDLE_START, WALK_OUT, IDLE_TURN, SPRINT_BACK, IDLE_END }

## CORRECCIÓN: usaban los nombres inventados "Idle"/"Walk"/"Sprint", que no
## existen en UAL1_Standard.glb, así que has_animation() siempre fallaba y
## este NPC de prueba (PSXNPC_Monster en Test_Final_System.tscn) nunca
## llegaba a reproducir ninguna animación real. Se reutilizan los mismos
## nombres reales que LocomotionState.
const ANIM_IDLE := LocomotionState.ANIM_IDLE
const ANIM_WALK := LocomotionState.ANIM_WALK
const ANIM_SPRINT := LocomotionState.ANIM_SPRINT

## Interruptor de depuración: si se desactiva, el NPC se queda quieto en
## Idle en su punto de partida (no patrulla). Útil para aislar si los
## errores/lag reportados vienen del movimiento o de otra parte de la
## escena.
@export var movement_enabled: bool = true
@export var patrol_distance: float = 4.0
@export var walk_speed: float = 1.4
@export var sprint_speed: float = 3.5
@export var idle_pause_seconds: float = 1.5

@onready var _model: Node3D = $Model
@onready var _anim_player: AnimationPlayer = $RetargetedAnimationPlayer

var _skeleton: Skeleton3D = null
var _current_state_anim: String = ""
var _state: int = _State.IDLE_START
var _state_timer: float = 0.0
var _start_local_z: float = 0.0


func _ready() -> void:
	_skeleton = PSXAnimationRetargeter.apply_to(_model, _anim_player, name)
	_start_local_z = position.z
	_state = _State.IDLE_START
	_state_timer = idle_pause_seconds
	_play_state(ANIM_IDLE)


func _process(delta: float) -> void:
	if _skeleton == null:
		return
	if not movement_enabled:
		return

	match _state:
		_State.IDLE_START, _State.IDLE_TURN, _State.IDLE_END:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_advance_state()
		_State.WALK_OUT:
			_move_toward_z(_start_local_z - patrol_distance, walk_speed, delta)
			if is_equal_approx(position.z, _start_local_z - patrol_distance):
				_advance_state()
		_State.SPRINT_BACK:
			_move_toward_z(_start_local_z, sprint_speed, delta)
			if is_equal_approx(position.z, _start_local_z):
				_advance_state()


func _move_toward_z(target_z: float, speed: float, delta: float) -> void:
	position.z = move_toward(position.z, target_z, speed * delta)


func _advance_state() -> void:
	match _state:
		_State.IDLE_START:
			_state = _State.WALK_OUT
			_play_state(ANIM_WALK)
		_State.WALK_OUT:
			_state = _State.IDLE_TURN
			_state_timer = idle_pause_seconds
			rotation.y += PI
			_play_state(ANIM_IDLE)
		_State.IDLE_TURN:
			_state = _State.SPRINT_BACK
			_play_state(ANIM_SPRINT)
		_State.SPRINT_BACK:
			_state = _State.IDLE_END
			_state_timer = idle_pause_seconds
			rotation.y += PI
			_play_state(ANIM_IDLE)
		_State.IDLE_END:
			_state = _State.IDLE_START
			_state_timer = idle_pause_seconds
			_play_state(ANIM_IDLE)


func _play_state(state_anim: String) -> void:
	if state_anim == _current_state_anim:
		return

	# Se marca el estado como "intentado" ANTES de comprobar si la
	# animación existe. Así, si no existe, la próxima llamada con este
	# mismo state_anim se corta en el guard de arriba en vez de volver a
	# intentarlo (y volver a avisar) en cada frame de _process().
	_current_state_anim = state_anim

	var full_name := PSXAnimationRetargeter.RETARGET_LIBRARY_NAME + "/" + state_anim
	if not _anim_player.has_animation(full_name):
		push_warning(
			"PSXNPCTestWalker (%s): la animación '%s' no está disponible tras el retargeting."
			% [name, full_name]
		)
		return

	_anim_player.play(full_name)
