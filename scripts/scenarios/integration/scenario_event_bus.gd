class_name ScenarioEventBus
extends Node

## Ticket 013C — Integración del Sistema de Escenarios.
##
## Bus de eventos desacoplado. Es el ÚNICO punto del proyecto que
## conoce a SceneManager de forma directa. Cualquier otro sistema
## (Audio, Ambientación, IA, Eventos, Guardado, Cinemáticas, Objetos,
## Puertas, Puzzles, Documentos, UI) debe reaccionar al ciclo de vida
## de los escenarios escuchando ESTE nodo, nunca a SceneManager.
##
## SceneManager (scene_manager.gd) no fue modificado: este bus se
## limita a localizarlo por grupo (mismo patrón ya usado en todo el
## proyecto por AudioManager, AmbientManager, DocumentManager,
## Inventory, etc. — ver GROUP_NAME en cada uno) y retransmitir sus
## señales, sin alterar su comportamiento ni su estado interno.
##
## Uso:
##   1. Añadir un nodo con este script en la escena donde también
##      exista (o vaya a existir) el SceneManager, o en cualquier
##      punto del árbol accesible antes que los bridges.
##   2. Añadir nodos con los distintos *ScenarioBridge (ver
##      scenario_integration_bridge.gd y sus subclases) donde se
##      necesite reaccionar a los escenarios.
##   3. Nada más: el propio bus y los bridges se localizan entre sí
##      por grupo en _ready(), sin rutas fijas ni referencias
##      exportadas obligatorias.

signal scene_registered(scene_id: String)
signal scene_load_started(scene_id: String)
signal scene_loaded(scene_id: String, data: SceneData)
signal scene_load_failed(scene_id: String, error: String)
signal scene_unload_started(scene_id: String)
signal scene_unloaded(scene_id: String)
signal scene_changed(previous_id: String, new_id: String)
signal scene_state_changed(scene_id: String, state: GameSceneState.State)
signal scene_reset(scene_id: String)
signal scene_reloaded(scene_id: String)

## Señal genérica de "catch-all": mismo contenido que las señales
## específicas de arriba, pero en un único punto de entrada. Pensada
## para integraciones futuras que prefieran no depender de la firma
## exacta de cada señal (escalabilidad / Open-Closed).
## event_name reutiliza el nombre de la señal específica equivalente.
signal scenario_event(event_name: StringName, payload: Dictionary)

const GROUP_NAME: String = "scenario_event_bus"
const SCENE_MANAGER_GROUP: String = "scene_manager"

var _scene_manager: SceneManager = null


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_bind_scene_manager()


## Enlace manual (opcional) a una instancia concreta de SceneManager.
## Útil en tests o cuando no se quiera depender de la búsqueda por
## grupo. Si no se llama nunca, el bus se enlaza solo en _ready().
func bind_scene_manager(manager: SceneManager) -> void:
	if manager == null or manager == _scene_manager:
		return
	_unbind_scene_manager()
	_scene_manager = manager
	_connect_scene_manager()


func get_scene_manager() -> SceneManager:
	return _scene_manager


## Acceso de solo lectura a los datos de un escenario. Permite que los
## bridges consulten SceneData sin tener que depender de SceneManager
## directamente: solo dependen de este bus.
func get_scenario_data(scene_id: String) -> SceneData:
	if _scene_manager == null:
		return null
	return _scene_manager.get_scenario_data(scene_id)


func get_current_scene_id() -> String:
	return _scene_manager.get_current_scene_id() if _scene_manager != null else ""


func get_current_scenario_data() -> SceneData:
	return get_scenario_data(get_current_scene_id())


func _bind_scene_manager() -> void:
	if _scene_manager != null:
		return
	var found: Node = get_tree().get_first_node_in_group(SCENE_MANAGER_GROUP)
	if found is SceneManager:
		bind_scene_manager(found)


func _connect_scene_manager() -> void:
	_scene_manager.scene_registered.connect(_on_scene_registered)
	_scene_manager.scene_load_started.connect(_on_scene_load_started)
	_scene_manager.scene_loaded.connect(_on_scene_loaded)
	_scene_manager.scene_load_failed.connect(_on_scene_load_failed)
	_scene_manager.scene_unload_started.connect(_on_scene_unload_started)
	_scene_manager.scene_unloaded.connect(_on_scene_unloaded)
	_scene_manager.scene_changed.connect(_on_scene_changed)
	_scene_manager.scene_state_changed.connect(_on_scene_state_changed)
	_scene_manager.scene_reset.connect(_on_scene_reset)
	_scene_manager.scene_reloaded.connect(_on_scene_reloaded)


func _unbind_scene_manager() -> void:
	if _scene_manager == null:
		return
	if _scene_manager.scene_registered.is_connected(_on_scene_registered):
		_scene_manager.scene_registered.disconnect(_on_scene_registered)
	if _scene_manager.scene_load_started.is_connected(_on_scene_load_started):
		_scene_manager.scene_load_started.disconnect(_on_scene_load_started)
	if _scene_manager.scene_loaded.is_connected(_on_scene_loaded):
		_scene_manager.scene_loaded.disconnect(_on_scene_loaded)
	if _scene_manager.scene_load_failed.is_connected(_on_scene_load_failed):
		_scene_manager.scene_load_failed.disconnect(_on_scene_load_failed)
	if _scene_manager.scene_unload_started.is_connected(_on_scene_unload_started):
		_scene_manager.scene_unload_started.disconnect(_on_scene_unload_started)
	if _scene_manager.scene_unloaded.is_connected(_on_scene_unloaded):
		_scene_manager.scene_unloaded.disconnect(_on_scene_unloaded)
	if _scene_manager.scene_changed.is_connected(_on_scene_changed):
		_scene_manager.scene_changed.disconnect(_on_scene_changed)
	if _scene_manager.scene_state_changed.is_connected(_on_scene_state_changed):
		_scene_manager.scene_state_changed.disconnect(_on_scene_state_changed)
	if _scene_manager.scene_reset.is_connected(_on_scene_reset):
		_scene_manager.scene_reset.disconnect(_on_scene_reset)
	if _scene_manager.scene_reloaded.is_connected(_on_scene_reloaded):
		_scene_manager.scene_reloaded.disconnect(_on_scene_reloaded)
	_scene_manager = null


# ---------------------------------------------------------------------------
# Retransmisión: señal específica de SceneManager -> señal propia + genérica
# ---------------------------------------------------------------------------

func _on_scene_registered(scene_id: String) -> void:
	scene_registered.emit(scene_id)
	scenario_event.emit(&"scene_registered", {"scene_id": scene_id})


func _on_scene_load_started(scene_id: String) -> void:
	scene_load_started.emit(scene_id)
	scenario_event.emit(&"scene_load_started", {"scene_id": scene_id})


func _on_scene_loaded(scene_id: String) -> void:
	var data: SceneData = get_scenario_data(scene_id)
	scene_loaded.emit(scene_id, data)
	scenario_event.emit(&"scene_loaded", {"scene_id": scene_id, "data": data})


func _on_scene_load_failed(scene_id: String, error: String) -> void:
	scene_load_failed.emit(scene_id, error)
	scenario_event.emit(&"scene_load_failed", {"scene_id": scene_id, "error": error})


func _on_scene_unload_started(scene_id: String) -> void:
	scene_unload_started.emit(scene_id)
	scenario_event.emit(&"scene_unload_started", {"scene_id": scene_id})


func _on_scene_unloaded(scene_id: String) -> void:
	scene_unloaded.emit(scene_id)
	scenario_event.emit(&"scene_unloaded", {"scene_id": scene_id})


func _on_scene_changed(previous_id: String, new_id: String) -> void:
	scene_changed.emit(previous_id, new_id)
	scenario_event.emit(&"scene_changed", {"previous_id": previous_id, "new_id": new_id})


func _on_scene_state_changed(scene_id: String, state: GameSceneState.State) -> void:
	scene_state_changed.emit(scene_id, state)
	scenario_event.emit(&"scene_state_changed", {"scene_id": scene_id, "state": state})


func _on_scene_reset(scene_id: String) -> void:
	scene_reset.emit(scene_id)
	scenario_event.emit(&"scene_reset", {"scene_id": scene_id})


func _on_scene_reloaded(scene_id: String) -> void:
	scene_reloaded.emit(scene_id)
	scenario_event.emit(&"scene_reloaded", {"scene_id": scene_id})
