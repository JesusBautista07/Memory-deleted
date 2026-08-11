class_name SharedAnimationLibrary
extends RefCounted
## Carga la AnimationLibrary del pack "Universal Animation Library [Standard]"
## (Quaternius) UNA sola vez y la reutiliza para todos los personajes.
##
## No duplica datos: se instancia la escena de animaciones (.glb) una sola
## vez para extraer su AnimationLibrary, se cachea en una variable estática,
## y esa MISMA referencia se añade a cada AnimationPlayer de cada variante
## de personaje. Godot permite que varios AnimationPlayer compartan la
## misma AnimationLibrary sin copiar las curvas de animación.

const ANIMATIONS_SOURCE_PATH := "res://assets/animations/UAL1_Standard.glb"

## Nombre con el que se registra la librería en cada AnimationPlayer.
## Las animaciones quedan disponibles como "UAL/Idle_Loop", "UAL/Walk_Loop", etc.
const LIBRARY_NAME := "UAL"

static var _cached_library: AnimationLibrary = null


## NOTA: antes se marcaba `_load_attempted = true` incluso cuando la carga
## fallaba, así que un primer fallo (por ejemplo transitorio, o por orden
## de instanciación de escenas) dejaba `_cached_library` en null PARA
## SIEMPRE: como es una var static compartida por todo el proyecto, ese
## null se propagaba a CUALQUIER personaje (jugador o NPC, PSX o
## Universal) que pidiera la librería después, sin ningún reintento
## posible durante toda la sesión. Ahora solo se cachea un resultado
## no-null; un intento fallido se puede reintentar en la siguiente
## llamada a get_library().
static func get_library() -> AnimationLibrary:
	if _cached_library == null:
		_cached_library = _load_library_from_source()
	return _cached_library


static func _load_library_from_source() -> AnimationLibrary:
	var packed_scene: PackedScene = load(ANIMATIONS_SOURCE_PATH)
	if packed_scene == null:
		push_warning("SharedAnimationLibrary: no se pudo cargar '%s'." % ANIMATIONS_SOURCE_PATH)
		return null

	var temp_root: Node = packed_scene.instantiate()
	var source_player: AnimationPlayer = _find_animation_player(temp_root)

	var library: AnimationLibrary = null
	if source_player != null and source_player.has_animation_library(""):
		library = source_player.get_animation_library("")
	else:
		push_warning("SharedAnimationLibrary: el archivo de animaciones no contiene un AnimationPlayer con animaciones.")

	temp_root.queue_free()
	return library


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null


## Añade la librería compartida a un AnimationPlayer de personaje, si no
## la tiene ya cargada. Devuelve true si la librería quedó disponible.
static func apply_to(animation_player: AnimationPlayer) -> bool:
	if animation_player == null:
		return false
	if animation_player.has_animation_library(LIBRARY_NAME):
		return true
	var lib := get_library()
	if lib == null:
		return false
	animation_player.add_animation_library(LIBRARY_NAME, lib)
	return true
