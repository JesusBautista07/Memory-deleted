extends Node3D
## Sistema de puertas. Responsabilidad única: controlar el estado
## (abierta/cerrada/bloqueada) de ESTA puerta y notificarlo mediante señales.
## No gestiona input, inventario, UI ni eventos reales — solo expone
## los puntos de conexión para que esos sistemas se integren después.

signal door_opened
signal door_closed
signal door_locked(required_key: String)   ## se emite cuando se intenta abrir sin la llave correcta
signal event_triggered(event_name: String) ## para que un futuro EventManager se conecte

enum State { CLOSED, OPENING, OPEN, CLOSING }

## --- Configuración desde el Inspector ---
@export var key_id: String = ""              ## ID de la llave requerida. Vacío = no requiere llave.
@export var starts_locked: bool = false
@export var open_speed: float = 1.0           ## segundos que tarda en abrir/cerrar
@export var open_angle: float = 90.0          ## grados de apertura
@export var sound_open: AudioStream
@export var sound_close: AudioStream
@export var triggers_event: bool = false
@export var event_name: String = ""

@onready var pivot: Node3D = $DoorPivot
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

var is_locked: bool = false
var _state: State = State.CLOSED
var _tween: Tween


func _ready() -> void:
	is_locked = starts_locked


## Punto de entrada público único. El futuro sistema de Interacción llama
## a esta función pasando las llaves que el jugador posee (desde Inventario).
## available_keys: Array de Strings con los IDs de llaves del jugador.
func try_open(available_keys: Array = []) -> bool:
	print("[020E] Door.try_open() llaves disponibles=", available_keys, " requiere=", key_id)

	if _state == State.OPEN or _state == State.OPENING:
		close()
		return true

	if is_locked:
		if key_id != "" and available_keys.has(key_id):
			unlock()
		else:
			print("[020E] Puerta bloqueada (falta llave: ", key_id, ")")
			door_locked.emit(key_id)
			return false

	open()
	return true


func open() -> void:
	if _state == State.OPEN or _state == State.OPENING:
		return

	_state = State.OPENING
	_play_sound(sound_open)

	_tween = create_tween()
	_tween.tween_property(pivot, "rotation_degrees:y", open_angle, open_speed) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(_on_open_finished)


func close() -> void:
	if _state == State.CLOSED or _state == State.CLOSING:
		return

	_state = State.CLOSING
	_play_sound(sound_close)

	_tween = create_tween()
	_tween.tween_property(pivot, "rotation_degrees:y", 0.0, open_speed) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(_on_close_finished)


func lock() -> void:
	is_locked = true


func unlock() -> void:
	is_locked = false


func _on_open_finished() -> void:
	_state = State.OPEN
	print("[020E] Puerta abierta")
	door_opened.emit()
	if triggers_event:
		event_triggered.emit(event_name)


func _on_close_finished() -> void:
	_state = State.CLOSED
	door_closed.emit()


func _play_sound(stream: AudioStream) -> void:
	if stream == null:
		return
	audio_player.stream = stream
	audio_player.play()


# ---------------------------------------------------------------------------
# INTEGRACIÓN CON EL SISTEMA OFICIAL DE INTERACCIÓN
# ---------------------------------------------------------------------------
# InteractionManager (scripts/interaction/interaction_manager.gd) detecta
# con el RayCast el StaticBody3D hijo (DoorPivot/DoorStaticBody) y, si ese
# collider no tiene interact(), sube por sus antepasados hasta encontrarlo.
# Como este script (Door, nodo raíz) es antepasado de DoorStaticBody, basta
# con implementar aquí interact() y get_interaction_prompt() para que la
# puerta quede interactuable en cualquier escena donde se instancie
# Door.tscn, sin scripts "puente" añadidos a mano por escena.
#
# --- CORRECCIÓN TICKET 020E ---
# interact() llamaba a try_open() SIN argumentos, así que available_keys
# llegaba siempre vacío ([] por defecto) y una puerta bloqueada jamás podía
# abrirse desde el flujo real de juego, aunque el jugador tuviera la llave
# correcta en el Inventory (solo test_door_sandbox.gd, un script exclusivo
# de pruebas, pasaba las llaves manualmente). Ahora interact() reúne los
# IDs de llave del Inventory existente (localizándolo por grupo, mismo
# patrón que usan PickupObject y WeaponManager) antes de llamar a try_open().

const INVENTORY_GROUP := "inventory"

func interact() -> void:
	try_open(_get_available_key_ids())


## Reúne los object_id de todos los objetos-llave (is_key_item = true) que
## el jugador tiene actualmente en el Inventory. Devuelve un array vacío si
## no hay Inventory en la escena o si todavía no expone get_key_ids().
func _get_available_key_ids() -> Array:
	var inventory: Node = get_tree().get_first_node_in_group(INVENTORY_GROUP)

	if inventory == null or not inventory.has_method("get_key_ids"):
		return []

	return inventory.call("get_key_ids")


func get_interaction_prompt() -> String:
	if is_locked:
		return "Puerta bloqueada"
	if _state == State.OPEN or _state == State.OPENING:
		return "[E] Cerrar puerta"
	return "[E] Abrir puerta"
