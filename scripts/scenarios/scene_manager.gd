class_name SceneManager
extends Node

signal scene_registered(scene_id: String)
signal scene_load_started(scene_id: String)
signal scene_loaded(scene_id: String)
signal scene_load_failed(scene_id: String, error: String)
signal scene_unload_started(scene_id: String)
signal scene_unloaded(scene_id: String)
signal scene_changed(previous_id: String, new_id: String)
signal scene_state_changed(scene_id: String, state: GameSceneState.State)
signal scene_reset(scene_id: String)
signal scene_reloaded(scene_id: String)

const GROUP_NAME: String = "scene_manager"

@export var scenario_container_path: NodePath

var _registry: SceneRegistry = SceneRegistry.new()
var _loader: SceneLoader = SceneLoader.new()

var _current_scene_id: String = ""
var _previous_scene_id: String = ""
var _next_scene_id: String = ""
var _scene_history: Array[String] = []

var _current_instance: Node
var _current_state: GameSceneState.State = GameSceneState.State.NOT_LOADED
var _container: Node


func _ready() -> void:
	add_to_group(GROUP_NAME)

	if not scenario_container_path.is_empty():
		_container = get_node_or_null(scenario_container_path)
	else:
		_container = get_parent()

	_loader.load_started.connect(_on_load_started)
	_loader.load_finished.connect(_on_load_finished)
	_loader.load_failed.connect(_on_load_failed)
	_loader.unload_started.connect(_on_unload_started)
	_loader.unload_finished.connect(_on_unload_finished)


func register_scenario(data: SceneData) -> void:
	if data == null:
		return
	_registry.register(data)
	scene_registered.emit(data.scene_id)


func unregister_scenario(scene_id: String) -> void:
	_registry.unregister(scene_id)


func is_scenario_registered(scene_id: String) -> bool:
	return _registry.is_registered(scene_id)


func get_scenario_data(scene_id: String) -> SceneData:
	return _registry.get_scene_data(scene_id)


func get_all_scenario_ids() -> Array[String]:
	return _registry.get_all_ids()


func get_current_scene_id() -> String:
	return _current_scene_id


func get_previous_scene_id() -> String:
	return _previous_scene_id


func get_next_scene_id() -> String:
	return _next_scene_id


func get_current_state() -> GameSceneState.State:
	return _current_state


func is_in_state(state: GameSceneState.State) -> bool:
	return _current_state == state


func has_active_scenario() -> bool:
	return _current_state == GameSceneState.State.ACTIVE and not _current_scene_id.is_empty()


func is_scenario_active(scene_id: String) -> bool:
	return _current_scene_id == scene_id and _current_state == GameSceneState.State.ACTIVE


func get_scene_history() -> Array[String]:
	return _scene_history.duplicate()


func get_current_info() -> SceneInfo:
	return get_scenario_info(_current_scene_id)


func get_scenario_info(scene_id: String) -> SceneInfo:
	var data: SceneData = get_scenario_data(scene_id)
	if data == null:
		return null
	var state: GameSceneState.State = _current_state if scene_id == _current_scene_id else GameSceneState.State.NOT_LOADED
	return SceneInfo.from_scene_data(data, state)


func load_scenario(scene_id: String, force: bool = false) -> void:
	if scene_id.is_empty():
		return
	if not force and _is_busy():
		return
	if not force and is_scenario_active(scene_id):
		return

	var data: SceneData = get_scenario_data(scene_id)
	if data == null:
		scene_load_failed.emit(scene_id, "Escenario no registrado: %s" % scene_id)
		return

	_set_state(GameSceneState.State.LOADING)
	var instance: Node = _loader.load_scene(data)
	if instance == null:
		_set_state(GameSceneState.State.NOT_LOADED)
		return

	if _container == null:
		scene_load_failed.emit(scene_id, "No hay contenedor válido para el escenario")
		instance.queue_free()
		_set_state(GameSceneState.State.NOT_LOADED)
		return

	_container.add_child(instance)

	_current_instance = instance
	_previous_scene_id = _current_scene_id
	_current_scene_id = scene_id
	_scene_history.append(scene_id)
	_set_state(GameSceneState.State.ACTIVE)
	scene_changed.emit(_previous_scene_id, _current_scene_id)


func unload_scenario() -> void:
	if _current_scene_id.is_empty():
		return
	if _is_busy():
		return

	var scene_id: String = _current_scene_id
	_set_state(GameSceneState.State.UNLOADING)
	_loader.unload_scene(scene_id, _current_instance)
	_current_instance = null
	_current_scene_id = ""
	_set_state(GameSceneState.State.NOT_LOADED)


func change_scenario(scene_id: String, force: bool = false) -> void:
	if scene_id.is_empty():
		return
	if not force and _is_busy():
		return
	if not force and is_scenario_active(scene_id):
		return

	_next_scene_id = scene_id
	unload_scenario()
	load_scenario(scene_id, true)
	_next_scene_id = ""


func restart_scenario() -> void:
	var scene_id: String = _current_scene_id
	if scene_id.is_empty() or _is_busy():
		return
	scene_reset.emit(scene_id)
	change_scenario(scene_id, true)


func reload_scenario() -> void:
	var scene_id: String = _current_scene_id
	if scene_id.is_empty() or _is_busy():
		return
	change_scenario(scene_id, true)
	scene_reloaded.emit(scene_id)


func pause_scenario() -> void:
	if _current_state != GameSceneState.State.ACTIVE:
		return
	_set_state(GameSceneState.State.PAUSED)


func resume_scenario() -> void:
	if _current_state != GameSceneState.State.PAUSED:
		return
	_set_state(GameSceneState.State.ACTIVE)


func finish_scenario() -> void:
	if _current_state != GameSceneState.State.ACTIVE and _current_state != GameSceneState.State.PAUSED:
		return
	_set_state(GameSceneState.State.FINISHED)


func _is_busy() -> bool:
	return _current_state == GameSceneState.State.LOADING or _current_state == GameSceneState.State.UNLOADING


func _set_state(state: GameSceneState.State) -> void:
	_current_state = state
	scene_state_changed.emit(_current_scene_id, state)


func _on_load_started(scene_id: String) -> void:
	scene_load_started.emit(scene_id)


func _on_load_finished(scene_id: String, instance: Node) -> void:
	scene_loaded.emit(scene_id)


func _on_load_failed(scene_id: String, error: String) -> void:
	scene_load_failed.emit(scene_id, error)


func _on_unload_started(scene_id: String) -> void:
	scene_unload_started.emit(scene_id)


func _on_unload_finished(scene_id: String) -> void:
	scene_unloaded.emit(scene_id)
