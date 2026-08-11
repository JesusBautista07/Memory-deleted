class_name NPCWanderer
extends CharacterBody3D
## NPC "de fondo" reutilizable para cualquier personaje PSX o Universal
## Base Character del proyecto. Reemplaza a PSXNPCTestWalker para los NPC
## que ya no queremos fijos en una fila sin IA (ver Ticket NPC-021).
##
## Responsabilidades:
## 1. Navegación real vía NavigationAgent3D sobre el NavigationMesh
##    bakeado por NavmeshRuntimeBaker: elige un punto aleatorio dentro de
##    wander_radius, camina o corre hacia él, hace una pausa en Idle y
##    repite. Al usar NavigationAgent3D (y no mover una coordenada a
##    mano, como hacía el walker de prueba) puede subir las escaleras si
##    el navmesh las cubre, y no tiene que moverse en línea recta.
## 2. Animación: aplica PSXAnimationRetargeter (personajes PSX) o
##    SharedAnimationLibrary (Universal Base Character) sobre su propio
##    AnimationPlayer y reproduce Idle_Loop / Walk_Loop / Sprint_Loop según
##    la velocidad horizontal real (misma convención de nombres que usa
##    PSXCharacterController para el jugador).
## 3. Salud/muerte: implementa take_damage(amount), el mismo punto de
##    entrada que WeaponCombat ya invoca sobre cualquier collider golpeado
##    (ver TestDummy). Al morir se desactiva la colisión, se detiene la
##    animación y se emite `died` para que NPCSpawner pueda reponerlo.
## 4. Caída del mapa: si global_position.y cae por debajo de FALL_DEATH_Y
##    (p. ej. empujado fuera del escenario), se considera "muerto" igual
##    que si lo hubiera matado el jugador.
##
## Estructura de hijos esperada (ver escenas NPCWanderer_*.tscn):
##   Model (instancia del modelo visual: .fbx PSX o .gltf Universal)
##   AnimPlayer (AnimationPlayer vacío, se rellena en _ready)
##   NavigationAgent3D
##   CollisionShape3D (cápsula, centrada en el origen del CharacterBody3D,
##                     igual convención que Player.tscn)

signal died(npc: NPCWanderer)

enum CharacterKind { PSX, UNIVERSAL }

const ANIM_IDLE := "Idle_Loop"
const ANIM_WALK := "Walk_Loop"
const ANIM_SPRINT := "Sprint_Loop"

const ARRIVAL_DISTANCE: float = 0.6
const MOVE_SPEED_THRESHOLD: float = 0.15

@export_group("Personaje")
@export var character_kind: CharacterKind = CharacterKind.PSX
@export var max_health: float = 30.0

@export_group("Movimiento")
## Interruptor de depuración: si se desactiva, el NPC no elige destinos ni
## se mueve (se queda en Idle en su punto de spawn), pero sigue vivo,
## visible y recibiendo gravedad. Útil para aislar si los errores/lag
## reportados vienen del pathfinding/animación en movimiento o de otra
## parte de la escena.
@export var wandering_enabled: bool = true
@export var walk_speed: float = 1.4
@export var sprint_speed: float = 3.2
## Probabilidad (0-1) de que, al elegir un nuevo destino, el NPC corra en
## vez de caminar hacia él. Da variedad visual entre los NPC.
@export var sprint_chance: float = 0.2
@export var wander_radius: float = 35.0
@export var idle_pause_min: float = 1.0
@export var idle_pause_max: float = 3.5

@export_group("Caída fuera del mapa")
@export var fall_death_y: float = -25.0

@onready var _model: Node3D = $Model
@onready var _anim_player: AnimationPlayer = $AnimPlayer
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D

var _health: float = 0.0
var _is_dead: bool = false
var _wander_origin: Vector3
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _target_speed: float = 0.0
var _waiting: bool = false
var _wait_timer: float = 0.0

var _current_state_anim: String = ""
var _library_prefix: String = ""


func _ready() -> void:
	_health = max_health
	_wander_origin = global_position

	add_to_group("npc_wanderers")

	match character_kind:
		CharacterKind.PSX:
			_library_prefix = PSXAnimationRetargeter.RETARGET_LIBRARY_NAME
			PSXAnimationRetargeter.apply_to(_model, _anim_player, name)
		CharacterKind.UNIVERSAL:
			_library_prefix = SharedAnimationLibrary.LIBRARY_NAME
			SharedAnimationLibrary.apply_to(_anim_player)

	_nav_agent.path_desired_distance = 0.5
	_nav_agent.target_desired_distance = ARRIVAL_DISTANCE
	_nav_agent.avoidance_enabled = false

	_play_state(ANIM_IDLE)
	_start_idle_pause()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	if global_position.y < fall_death_y:
		_die(false)
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if not wandering_enabled:
		velocity.x = 0.0
		velocity.z = 0.0
	elif _waiting:
		_wait_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _wait_timer <= 0.0:
			_pick_new_target()
	elif _nav_agent.is_navigation_finished():
		_start_idle_pause()
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var next_pos: Vector3 = _nav_agent.get_next_path_position()
		var to_next: Vector3 = next_pos - global_position
		to_next.y = 0.0
		if to_next.length() > 0.01:
			var direction := to_next.normalized()
			velocity.x = direction.x * _target_speed
			velocity.z = direction.z * _target_speed
			_face_direction(direction, delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0

	move_and_slide()
	_update_animation()


func _face_direction(direction: Vector3, delta: float) -> void:
	var target_angle := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, clamp(delta * 6.0, 0.0, 1.0))


func _update_animation() -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var state_anim := ANIM_IDLE
	if horizontal_speed > MOVE_SPEED_THRESHOLD:
		state_anim = ANIM_SPRINT if horizontal_speed > walk_speed + 0.2 else ANIM_WALK
	_play_state(state_anim)


func _play_state(state_anim: String) -> void:
	if state_anim == _current_state_anim or _anim_player == null:
		return

	# Se marca el estado como "intentado" ANTES de comprobar si la
	# animación existe. Así, si no existe, la próxima llamada con este
	# mismo state_anim se corta en el guard de arriba en vez de volver a
	# intentarlo (y volver a avisar) en cada _physics_process().
	_current_state_anim = state_anim

	var full_name := _library_prefix + "/" + state_anim
	if not _anim_player.has_animation(full_name):
		push_warning(
			"NPCWanderer (%s): la animación '%s' no está disponible en su AnimationPlayer."
			% [name, full_name]
		)
		return

	_anim_player.play(full_name)


func _start_idle_pause() -> void:
	_waiting = true
	_wait_timer = randf_range(idle_pause_min, idle_pause_max)


func _pick_new_target() -> void:
	_waiting = false
	_target_speed = sprint_speed if randf() < sprint_chance else walk_speed

	var angle := randf() * TAU
	var radius := randf_range(wander_radius * 0.25, wander_radius)
	var candidate := _wander_origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_nav_agent.target_position = candidate


## Punto de entrada que WeaponCombat invoca automáticamente sobre
## cualquier collider golpeado que lo implemente (mismo contrato que
## TestDummy.take_damage()).
func take_damage(amount: float) -> void:
	if _is_dead or amount <= 0.0:
		return

	_health = max(_health - amount, 0.0)
	if _health <= 0.0:
		_die(true)


func is_dead() -> bool:
	return _is_dead


func get_health() -> float:
	return _health


func _die(_by_damage: bool) -> void:
	if _is_dead:
		return
	_is_dead = true

	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)

	if _anim_player != null:
		_anim_player.stop()
	if _model != null:
		_model.visible = false

	died.emit(self)

	# Pequeño margen antes de liberar el nodo para que quien reciba `died`
	# (NPCSpawner) alcance a leer su posición/estado si lo necesita.
	var timer := get_tree().create_timer(0.5)
	await timer.timeout
	queue_free()
