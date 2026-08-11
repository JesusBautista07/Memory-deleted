class_name GroupNotifyScenarioBridge
extends ScenarioIntegrationBridge

## Ticket 013C — Integración del Sistema de Escenarios.
##
## Bridge genérico y reutilizable, pensado para los sistemas que
## todavía no exponen un manager central con API propia para
## escenarios (Objetos, Puertas, Puzzles, Cinemáticas...) pero sí
## agrupan sus nodos en un grupo de Godot, igual que ya hace
## SaveManager con "saveable_objects", "saveable_doors",
## "saveable_events" y "saveable_puzzles" (ver save_manager.gd).
##
## No implementa lógica nueva DENTRO de esos sistemas: simplemente, si
## un nodo del grupo configurado implementa (de forma opcional) alguno
## de los métodos listados abajo, este bridge lo invoca por duck
## typing. Si no lo implementa, no ocurre nada: es pura infraestructura
## preparada para que esos sistemas puedan sumarse cuando lo necesiten,
## sin tener que modificar este archivo ni ninguno existente.
##
## Contrato opcional esperado por nodo del grupo (todos opcionales):
##   on_scenario_loaded(scene_id: String, data: SceneData)
##   on_scenario_unloaded(scene_id: String)
##   on_scenario_changed(previous_id: String, new_id: String)
##   on_scenario_reset(scene_id: String)
##   on_scenario_reloaded(scene_id: String)
##   on_scenario_state_changed(scene_id: String, state: GameSceneState.State)
##
## Uso: instanciar un nodo con este script por cada grupo que se
## quiera notificar y asignar `target_group`, por ejemplo:
##   "saveable_objects"  -> Sistema de Objetos
##   "saveable_doors"    -> Sistema de Puertas
##   "saveable_puzzles"  -> Sistema de Puzzles
##   "cinematic_manager" -> Sistema de Cinemáticas (cuando exista)

@export var target_group: String = ""


func _on_scenario_loaded(scene_id: String, data: SceneData) -> void:
	_broadcast(&"on_scenario_loaded", [scene_id, data])


func _on_scenario_unloaded(scene_id: String) -> void:
	_broadcast(&"on_scenario_unloaded", [scene_id])


func _on_scenario_changed(previous_id: String, new_id: String) -> void:
	_broadcast(&"on_scenario_changed", [previous_id, new_id])


func _on_scenario_reset(scene_id: String) -> void:
	_broadcast(&"on_scenario_reset", [scene_id])


func _on_scenario_reloaded(scene_id: String) -> void:
	_broadcast(&"on_scenario_reloaded", [scene_id])


func _on_scenario_state_changed(scene_id: String, state: GameSceneState.State) -> void:
	_broadcast(&"on_scenario_state_changed", [scene_id, state])


func _broadcast(method_name: StringName, args: Array) -> void:
	if target_group.is_empty():
		return
	for node in get_tree().get_nodes_in_group(target_group):
		_call_if_supported(node, method_name, args)
