class_name NPCSpawner
extends Node3D
## Mantiene una población objetivo de NPC (NPCWanderer) repartidos por
## todo el mapa, eligiendo entre varias escenas de personaje distintas
## (PSX + Universal Base Character, sin monstruos) para que no se vean
## todos iguales. Cuando un NPC muere (a manos del jugador o por caerse
## del mapa) lo repone tras una pausa aleatoria, en un punto distinto, para
## que el spawn se sienta continuo y no como una oleada.
##
## Requiere que exista un NavigationRegion3D ya bakeado en la escena
## (ver NavmeshRuntimeBaker) antes de spawnear el primer NPC: si no,
## NavigationAgent3D no tendría sobre qué navegar. Por eso espera a
## `navmesh_source.navmesh_ready` (si se asignó) antes de arrancar.

@export var npc_scenes: Array[PackedScene] = []

## Interruptor de depuración: si se desactiva, el spawner no crea NINGÚN
## NPC (ni la tanda inicial ni las reposiciones). Útil para aislar si los
## errores/lag reportados durante la carga vienen de los NPC o de otra
## parte de la escena.
@export var spawning_enabled: bool = true

@export_group("Población")
@export var target_population: int = 8
## Radio, centrado en la posición de este nodo, dentro del cual se elige
## el punto de spawn de cada NPC nuevo ("en todo el mapa").
@export var spawn_area_radius: float = 90.0
## Distancia mínima al jugador para no spawnear (ni reponer) un NPC justo
## encima de la cámara.
@export var min_distance_from_player: float = 10.0

@export_group("Ritmo de spawn")
@export var initial_spawn_interval: float = 0.6
@export var respawn_delay_min: float = 3.0
@export var respawn_delay_max: float = 9.0

@export_group("Referencias")
## NavigationRegion3D (o script que emita `navmesh_ready`) cuyo bakeo hay
## que esperar antes de spawnear. Opcional: si se deja vacío, se empieza a
## spawnear en el siguiente frame físico sin esperar ninguna señal.
@export var navmesh_source: Node = null
@export var player_path: NodePath

var _player: Node3D = null
var _alive_npcs: Array[NPCWanderer] = []


func _ready() -> void:
	if not spawning_enabled:
		return

	if not player_path.is_empty():
		_player = get_node_or_null(player_path) as Node3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D

	if npc_scenes.is_empty():
		push_warning("NPCSpawner (%s): npc_scenes está vacío, no hay nada que spawnear." % name)
		return

	if navmesh_source != null and navmesh_source.has_signal("navmesh_ready"):
		navmesh_source.navmesh_ready.connect(_start_initial_spawns)
	else:
		await get_tree().physics_frame
		_start_initial_spawns()


func _start_initial_spawns() -> void:
	for i in range(target_population):
		await get_tree().create_timer(initial_spawn_interval).timeout
		_spawn_one()


## Instancia un NPC nuevo y lo posiciona ANTES de añadirlo al árbol: la
## posición debe estar fijada antes de add_child() porque NPCWanderer
## captura su punto de origen para deambular (`_wander_origin`) dentro de
## su propio _ready(), que Godot dispara de forma síncrona durante
## add_child(). Se usa `position` (local), no `global_position`, porque
## este spawner asume que su propio padre (la raíz de la escena) no tiene
## transform propio; si alguna vez se reparenta bajo un nodo con
## transform distinto de la identidad, cambiar esto a global_position
## calculado manualmente contra ese transform.
func _spawn_one() -> void:
	var scene: PackedScene = npc_scenes[randi() % npc_scenes.size()]
	var npc: NPCWanderer = scene.instantiate()

	var spawn_pos := _pick_spawn_position()
	npc.position = spawn_pos
	npc.rotation.y = randf() * TAU

	get_parent().add_child(npc)

	npc.died.connect(_on_npc_died)
	_alive_npcs.append(npc)


func _pick_spawn_position() -> Vector3:
	var attempts := 0
	var candidate := global_position
	while attempts < 12:
		var angle := randf() * TAU
		var radius := randf() * spawn_area_radius
		candidate = global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if _player == null or candidate.distance_to(_player.global_position) >= min_distance_from_player:
			break
		attempts += 1

	# Se apoya sobre el navmesh ya bakeado para no dejar al NPC flotando o
	# incrustado si el punto aleatorio cayó fuera del área caminable.
	var map_rid := get_world_3d().navigation_map
	var closest_point := NavigationServer3D.map_get_closest_point(map_rid, candidate)
	return closest_point


## Cada muerte repone exactamente un NPC nuevo tras una pausa aleatoria
## ("naturalmente", no en cuanto muere) para mantener la población
## alrededor de target_population sin importar cuántas reposiciones haya
## en curso a la vez.
func _on_npc_died(npc: NPCWanderer) -> void:
	_alive_npcs.erase(npc)
	var delay := randf_range(respawn_delay_min, respawn_delay_max)
	await get_tree().create_timer(delay).timeout
	_spawn_one()


func get_alive_count() -> int:
	return _alive_npcs.size()
