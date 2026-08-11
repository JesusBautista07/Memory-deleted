class_name ScenarioIntegrationBridge
extends Node

## Ticket 013C — Integración del Sistema de Escenarios.
##
## Clase base para todos los "bridges" de integración. Cada sistema
## del proyecto que necesite reaccionar al ciclo de vida de los
## escenarios extiende esta clase y sobrescribe únicamente los
## métodos virtuales `_on_scenario_*` que le interesen.
##
## Responsabilidad única de esta clase: localizar a ScenarioEventBus
## (por grupo, sin ruta fija) y traducir sus señales a llamadas de
## método virtuales. Ninguna subclase depende de SceneManager ni de
## ningún otro bridge, evitando dependencias circulares y cumpliendo
## el principio Open/Closed: añadir una integración nueva nunca
## requiere tocar esta clase ni el bus.
##
## También ofrece utilidades comunes para localizar sistemas destino
## (Audio, Ambientación, IA, Eventos, Guardado, Documentos, UI, etc.)
## por grupo y llamarlos por duck typing (has_method), siguiendo el
## mismo patrón que ya usa el resto del proyecto (SaveManager,
## ImportantItem, DocumentManager...).

const EVENT_BUS_GROUP: String = "scenario_event_bus"

## Si es true, además de las señales específicas también se escucha
## la señal genérica `scenario_event` (útil para logging/depuración
## o para integraciones que prefieran un único punto de entrada).
@export var listen_generic_event: bool = false

var _bus: Node = null


func _ready() -> void:
	_bind_event_bus()


## Enlace manual (opcional) a una instancia concreta del bus. Útil en
## tests. Si no se llama nunca, el bridge se enlaza solo en _ready().
func bind_event_bus(bus: Node) -> void:
	if bus == null or bus == _bus:
		return
	_bus = bus
	_connect_bus()


func get_event_bus() -> Node:
	return _bus


func _bind_event_bus() -> void:
	if _bus != null:
		return
	var found: Node = get_tree().get_first_node_in_group(EVENT_BUS_GROUP)
	if found != null:
		bind_event_bus(found)


func _connect_bus() -> void:
	if _bus == null:
		return
	_safe_connect(_bus, &"scene_registered", _handle_scene_registered)
	_safe_connect(_bus, &"scene_load_started", _handle_scene_load_started)
	_safe_connect(_bus, &"scene_loaded", _handle_scene_loaded)
	_safe_connect(_bus, &"scene_load_failed", _handle_scene_load_failed)
	_safe_connect(_bus, &"scene_unload_started", _handle_scene_unload_started)
	_safe_connect(_bus, &"scene_unloaded", _handle_scene_unloaded)
	_safe_connect(_bus, &"scene_changed", _handle_scene_changed)
	_safe_connect(_bus, &"scene_state_changed", _handle_scene_state_changed)
	_safe_connect(_bus, &"scene_reset", _handle_scene_reset)
	_safe_connect(_bus, &"scene_reloaded", _handle_scene_reloaded)
	if listen_generic_event:
		_safe_connect(_bus, &"scenario_event", _handle_scenario_event)


func _safe_connect(emitter: Object, signal_name: StringName, callable: Callable) -> void:
	if emitter == null or not emitter.has_signal(signal_name):
		return
	var sig: Signal = Signal(emitter, signal_name)
	if not sig.is_connected(callable):
		sig.connect(callable)


# ---------------------------------------------------------------------------
# Despachadores internos -> métodos virtuales para las subclases
# ---------------------------------------------------------------------------

func _handle_scene_registered(scene_id: String) -> void:
	_on_scenario_registered(scene_id)


func _handle_scene_load_started(scene_id: String) -> void:
	_on_scenario_load_started(scene_id)


func _handle_scene_loaded(scene_id: String, data: SceneData) -> void:
	_on_scenario_loaded(scene_id, data)


func _handle_scene_load_failed(scene_id: String, error: String) -> void:
	_on_scenario_load_failed(scene_id, error)


func _handle_scene_unload_started(scene_id: String) -> void:
	_on_scenario_unload_started(scene_id)


func _handle_scene_unloaded(scene_id: String) -> void:
	_on_scenario_unloaded(scene_id)


func _handle_scene_changed(previous_id: String, new_id: String) -> void:
	_on_scenario_changed(previous_id, new_id)


func _handle_scene_state_changed(scene_id: String, state: GameSceneState.State) -> void:
	_on_scenario_state_changed(scene_id, state)


func _handle_scene_reset(scene_id: String) -> void:
	_on_scenario_reset(scene_id)


func _handle_scene_reloaded(scene_id: String) -> void:
	_on_scenario_reloaded(scene_id)


func _handle_scenario_event(event_name: StringName, payload: Dictionary) -> void:
	_on_scenario_event(event_name, payload)


# ---------------------------------------------------------------------------
# Métodos virtuales: cada subclase sobrescribe solo los que necesite.
# ---------------------------------------------------------------------------

func _on_scenario_registered(_scene_id: String) -> void:
	pass


func _on_scenario_load_started(_scene_id: String) -> void:
	pass


func _on_scenario_loaded(_scene_id: String, _data: SceneData) -> void:
	pass


func _on_scenario_load_failed(_scene_id: String, _error: String) -> void:
	pass


func _on_scenario_unload_started(_scene_id: String) -> void:
	pass


func _on_scenario_unloaded(_scene_id: String) -> void:
	pass


func _on_scenario_changed(_previous_id: String, _new_id: String) -> void:
	pass


func _on_scenario_state_changed(_scene_id: String, _state: GameSceneState.State) -> void:
	pass


func _on_scenario_reset(_scene_id: String) -> void:
	pass


func _on_scenario_reloaded(_scene_id: String) -> void:
	pass


func _on_scenario_event(_event_name: StringName, _payload: Dictionary) -> void:
	pass


# ---------------------------------------------------------------------------
# Utilidades comunes para localizar y llamar a sistemas destino
# ---------------------------------------------------------------------------

## Busca el primer nodo del grupo indicado. Mismo patrón usado en todo
## el proyecto (SaveManager, ImportantItem, DocumentManager...) para
## no depender de rutas fijas ni nombres de autoload concretos.
func _find_system(group_name: String) -> Node:
	return get_tree().get_first_node_in_group(group_name)


## Llama a un método por nombre solo si el nodo existe y lo implementa
## (duck typing), evitando comprobaciones de tipo/casts frágiles y sin
## necesitar que el sistema destino conozca a este bridge.
func _call_if_supported(target: Node, method_name: StringName, args: Array = []) -> void:
	if target == null or not target.has_method(method_name):
		return
	target.callv(method_name, args)
