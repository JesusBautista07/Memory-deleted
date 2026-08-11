extends Node3D
class_name WeaponCombat
## Sistema básico de combate (Ticket 020C).
##
## Amplía la arquitectura de armas ya existente sin reemplazarla ni
## duplicarla:
## - No mantiene ninguna lista propia de armas: pregunta a WeaponManager
##   cuál está equipada (get_equipped_weapon()) y usa su API pública
##   (equip_next/equip_previous) para cambiar de arma.
## - No toca el Inventory: WeaponManager sigue siendo el único que lee el
##   Inventory, e Inventory sigue siendo la única fuente de verdad sobre
##   qué armas tiene el jugador.
## - El ESTADO de munición (cargador/reserva) vive ÚNICAMENTE aquí, en un
##   diccionario en memoria indexado por object_id. No se escribe nunca en
##   el recurso WeaponData (que es configuración de diseño, no estado de
##   partida), evitando así compartir estado entre instancias del mismo
##   recurso.
##
## Debe colocarse como nodo hermano de WeaponManager (p. ej. bajo
## Player/CameraPivot/Camera3D, igual que WeaponManager), con sus dos
## NodePaths exportados apuntando al WeaponManager existente y a un
## RayCast3D dedicado al disparo (distinto del RayCast3D de
## InteractionManager, que no se toca).

signal ammo_changed(magazine: int, reserve: int)
signal weapon_fired(weapon_data: WeaponData)
signal weapon_empty(weapon_data: WeaponData)
signal reload_started(weapon_data: WeaponData)
signal reload_finished(weapon_data: WeaponData)
## Gancho preparado para un futuro sistema de daño/IA. hit_target será el
## Object golpeado por el RayCast (puede o no implementar take_damage()).
signal hit_detected(hit_target: Object, hit_position: Vector3, weapon_data: WeaponData)

const AUDIO_GROUP := "audio_manager"

@export var weapon_manager: WeaponManager
@export var fire_ray_cast: RayCast3D
@export var fire_action: String = "fire"
@export var reload_action: String = "reload"
@export var weapon_next_action: String = "weapon_next"
@export var weapon_previous_action: String = "weapon_previous"

## Desplazamiento de "retroceso" visual aplicado al view model al disparar,
## y velocidad a la que vuelve a su posición original. Es deliberadamente
## simple (no es un sistema de animación): solo mueve el nodo un poco y lo
## devuelve, tal como pide el ticket ("aunque sea mover ligeramente el arma").
@export var view_model_kick_offset: Vector3 = Vector3(0, 0, 0.08)
@export var view_model_kick_recover_speed: float = 8.0

var _cooldown_remaining: float = 0.0
var _is_reloading: bool = false
var _reload_time_remaining: float = 0.0

## object_id -> {"magazine": int, "reserve": int}. Única fuente de verdad
## del estado de munición. Se inicializa la primera vez que se ve un arma
## (al equiparla), a partir de la configuración de su WeaponData.
var _ammo_state: Dictionary = {}

var _audio_manager: Node = null

var _view_model_base_position: Vector3 = Vector3.ZERO
var _view_model_kick_active: bool = false
var _tracked_view_model: Node3D = null


func _ready() -> void:
	# Misma corrección que en WeaponManager (Ticket 020D): si en el futuro
	# se añade un AudioManager en un nodo posterior del árbol, buscarlo
	# aquí mismo en _ready() podría no encontrarlo todavía. Se difiere un
	# frame por la misma razón, sin cambiar el patrón de "localizar por
	# grupo" ya usado en el resto del proyecto.
	call_deferred("_bind_audio_manager")

	if weapon_manager != null:
		weapon_manager.weapon_equipped.connect(_on_weapon_equipped)
		weapon_manager.weapon_unequipped.connect(_on_weapon_unequipped)

	if fire_ray_cast != null:
		# El RayCast de disparo no necesita escanear cada frame como el de
		# InteractionManager: solo se consulta en el instante del disparo
		# (force_raycast_update), así que se mantiene desactivado el resto
		# del tiempo.
		fire_ray_cast.enabled = false

		# CORRECCIÓN (mismo bug real que InteractionManager, ver
		# scripts/interaction/interaction_manager.gd::_exclude_owner_body):
		# este RayCast también está anidado dentro del propio
		# CharacterBody3D del jugador (Player > CameraPivot > Camera3D >
		# WeaponFireRayCast) y con Jolt Physics puede reportar colisión
		# con el propio jugador como primer impacto, antes de llegar a
		# cualquier objetivo real. Se excluye aquí el cuerpo físico
		# antepasado del jugador para que el disparo golpee lo que el
		# jugador realmente apunta.
		_exclude_owner_body(fire_ray_cast)


func _exclude_owner_body(ray_cast: RayCast3D) -> void:
	var node: Node = ray_cast.get_parent()
	while node != null:
		if node is CollisionObject3D:
			ray_cast.add_exception(node)
			return
		node = node.get_parent()


func _bind_audio_manager() -> void:
	_audio_manager = get_tree().get_first_node_in_group(AUDIO_GROUP)


func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = max(_cooldown_remaining - delta, 0.0)

	_process_reload(delta)
	_process_view_model_kick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if weapon_manager == null:
		return

	if event.is_action_pressed(fire_action):
		try_fire()
	elif event.is_action_pressed(reload_action):
		try_reload()
	elif event.is_action_pressed(weapon_next_action):
		weapon_manager.equip_next()
	elif event.is_action_pressed(weapon_previous_action):
		weapon_manager.equip_previous()


## ---------------------------------------------------------------------
## Disparo
## ---------------------------------------------------------------------

## Intenta disparar el arma equipada. Devuelve true si el disparo se
## produjo. No hace nada si no hay arma equipada, si sigue en cooldown, si
## se está recargando o si el cargador está vacío (en este último caso
## reproduce el sonido de "vacío" y emite weapon_empty).
func try_fire() -> bool:
	if weapon_manager == null:
		return false

	var weapon_data: WeaponData = weapon_manager.get_equipped_weapon()
	if weapon_data == null:
		return false

	if _is_reloading or _cooldown_remaining > 0.0:
		return false

	var state: Dictionary = _get_or_init_ammo_state(weapon_data)

	if state["magazine"] <= 0:
		_play_sound(weapon_data.empty_sound_id)
		weapon_empty.emit(weapon_data)
		return false

	state["magazine"] -= 1
	_cooldown_remaining = weapon_data.fire_rate
	ammo_changed.emit(state["magazine"], state["reserve"])

	_fire_ray(weapon_data)
	_play_sound(weapon_data.fire_sound_id)
	_trigger_view_model_kick()

	print("[020E] Disparo realizado: ", weapon_data.object_id, " cargador=", state["magazine"], "/", weapon_data.magazine_size)
	weapon_fired.emit(weapon_data)
	return true


func _fire_ray(weapon_data: WeaponData) -> void:
	if fire_ray_cast == null:
		return

	fire_ray_cast.target_position = Vector3(0, 0, -weapon_data.fire_range)
	fire_ray_cast.force_raycast_update()

	if not fire_ray_cast.is_colliding():
		return

	var collider: Object = fire_ray_cast.get_collider()
	var hit_position: Vector3 = fire_ray_cast.get_collision_point()

	# Gancho preparado para daño futuro: si el objetivo ya implementa
	# take_damage(), se le llama; si no (todavía no hay IA/enemigos con
	# salud), simplemente no pasa nada más que la señal de aviso.
	if collider != null and collider.has_method("take_damage"):
		collider.call("take_damage", weapon_data.damage)

	hit_detected.emit(collider, hit_position, weapon_data)


## ---------------------------------------------------------------------
## Recarga
## ---------------------------------------------------------------------

func try_reload() -> bool:
	if weapon_manager == null:
		return false

	var weapon_data: WeaponData = weapon_manager.get_equipped_weapon()
	if weapon_data == null or _is_reloading:
		return false

	var state: Dictionary = _get_or_init_ammo_state(weapon_data)

	if state["magazine"] >= weapon_data.magazine_size or state["reserve"] <= 0:
		return false

	_is_reloading = true
	_reload_time_remaining = weapon_data.reload_time
	_play_sound(weapon_data.reload_sound_id)
	print("[020E] Recarga iniciada: ", weapon_data.object_id)
	reload_started.emit(weapon_data)
	return true


func _process_reload(delta: float) -> void:
	if not _is_reloading:
		return

	_reload_time_remaining -= delta
	if _reload_time_remaining > 0.0:
		return

	_is_reloading = false

	var weapon_data: WeaponData = weapon_manager.get_equipped_weapon()
	if weapon_data == null:
		return  # El arma se desequipó mientras recargaba; no hay nada que rellenar.

	var state: Dictionary = _get_or_init_ammo_state(weapon_data)
	var needed: int = weapon_data.magazine_size - state["magazine"]
	var transferred: int = min(needed, state["reserve"])

	state["magazine"] += transferred
	state["reserve"] -= transferred

	ammo_changed.emit(state["magazine"], state["reserve"])
	print("[020E] Recarga finalizada: ", weapon_data.object_id, " cargador=", state["magazine"], " reserva=", state["reserve"])
	reload_finished.emit(weapon_data)


## ---------------------------------------------------------------------
## Estado de munición
## ---------------------------------------------------------------------

## Munición actual en el cargador del arma equipada (0 si no hay arma).
func get_current_magazine_ammo() -> int:
	var weapon_data: WeaponData = weapon_manager.get_equipped_weapon() if weapon_manager != null else null
	if weapon_data == null:
		return 0
	return _get_or_init_ammo_state(weapon_data)["magazine"]


## Munición de reserva del arma equipada (0 si no hay arma).
func get_current_reserve_ammo() -> int:
	var weapon_data: WeaponData = weapon_manager.get_equipped_weapon() if weapon_manager != null else null
	if weapon_data == null:
		return 0
	return _get_or_init_ammo_state(weapon_data)["reserve"]


func is_reloading() -> bool:
	return _is_reloading


func _get_or_init_ammo_state(weapon_data: WeaponData) -> Dictionary:
	var key: String = weapon_data.object_id

	if not _ammo_state.has(key):
		_ammo_state[key] = {
			"magazine": weapon_data.magazine_size,
			"reserve": weapon_data.starting_reserve_ammo,
		}

	return _ammo_state[key]


func _on_weapon_equipped(weapon_data: WeaponData) -> void:
	_is_reloading = false
	_cooldown_remaining = 0.0

	var state: Dictionary = _get_or_init_ammo_state(weapon_data)
	ammo_changed.emit(state["magazine"], state["reserve"])

	_start_tracking_view_model()


func _on_weapon_unequipped(_weapon_data: WeaponData) -> void:
	_is_reloading = false
	_cooldown_remaining = 0.0
	_tracked_view_model = null
	_view_model_kick_active = false


## ---------------------------------------------------------------------
## Animación simple de disparo
## ---------------------------------------------------------------------

func _start_tracking_view_model() -> void:
	if weapon_manager == null:
		return

	_tracked_view_model = weapon_manager.get_current_view_model()
	_view_model_kick_active = false

	if _tracked_view_model != null:
		_view_model_base_position = _tracked_view_model.position


func _trigger_view_model_kick() -> void:
	if weapon_manager == null:
		return

	# Se relee cada disparo por si el view model cambió (p. ej. cambio de
	# arma justo antes de disparar).
	_tracked_view_model = weapon_manager.get_current_view_model()
	if _tracked_view_model == null:
		return

	# Solo se refresca la "posición base" cuando no hay un kick en curso,
	# para no acumular desplazamiento si el jugador dispara más rápido de
	# lo que tarda en recuperarse la animación anterior.
	if not _view_model_kick_active:
		_view_model_base_position = _tracked_view_model.position

	_tracked_view_model.position = _view_model_base_position + view_model_kick_offset
	_view_model_kick_active = true


func _process_view_model_kick(delta: float) -> void:
	if not _view_model_kick_active or _tracked_view_model == null:
		return

	_tracked_view_model.position = _tracked_view_model.position.move_toward(
		_view_model_base_position, view_model_kick_recover_speed * delta
	)

	if _tracked_view_model.position.is_equal_approx(_view_model_base_position):
		_tracked_view_model.position = _view_model_base_position
		_view_model_kick_active = false


## ---------------------------------------------------------------------
## Sonido preparado
## ---------------------------------------------------------------------

## Reproduce un sonido por su audio_id vía el AudioManager ya existente
## (localizado por grupo, igual que hacen otros sistemas del proyecto). Si
## no hay AudioManager en la escena, si el id está vacío, o si el sonido
## todavía no está registrado, simplemente no hace nada: la estructura
## queda preparada sin depender de que el audio ya exista.
func _play_sound(audio_id: String) -> void:
	if audio_id.is_empty() or _audio_manager == null:
		return

	if _audio_manager.has_method("has_sound") and not _audio_manager.call("has_sound", audio_id):
		return

	if _audio_manager.has_method("play_sfx"):
		_audio_manager.call("play_sfx", audio_id)
