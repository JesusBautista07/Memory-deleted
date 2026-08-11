class_name CharacterVariant
extends Node3D
## Aplica una variante visual (tono de piel, color de pelo, estilo de pelo)
## sobre el modelo base de Quaternius (Superhero_Male_FullBody) SIN duplicar
## el archivo del modelo ni sus texturas: usa material_override con la
## textura original y solo cambia albedo_color (tinte de color).
##
## También conecta la AnimationLibrary compartida (ver shared_animation_library.gd)
## al AnimationPlayer de este personaje, y reproduce Idle/Walk/Sprint según
## el movimiento real de PlayerMovement (ver movement_node_path más abajo),
## usando el mismo criterio que LocomotionState ya define para el resto del
## proyecto (jugador PSX, y en el futuro cualquier otro personaje).
##
## Este script NO controla movimiento, cámara, colisiones ni input; solo
## LEE el estado de PlayerMovement (velocidad) para decidir qué animación
## reproducir. Si no hay ningún PlayerMovement en movement_node_path (por
## ejemplo en CharacterVariants_TestScene.tscn, donde este nodo no cuelga
## de un Player), simplemente se queda en Idle, igual que antes.

## Nombre real de la malla del cuerpo dentro del modelo original de Quaternius.
const BODY_MESH_NAME := "SuperHero_Male"
## Nombre real de la malla de pelo dentro del modelo original de Quaternius
## (en el archivo fuente esta malla se llama "Eyebrows", pero corresponde
## al pelo/cabello del personaje, no a las cejas).
const HAIR_MESH_NAME := "Eyebrows"

@export_group("Apariencia de esta variante")
## Tinte multiplicativo sobre la textura de piel/cuerpo original.
## Color(1,1,1,1) = tono original sin cambios.
@export var skin_tint: Color = Color(1, 1, 1, 1)
## Tinte multiplicativo sobre la textura de pelo original.
@export var hair_tint: Color = Color(1, 1, 1, 1)
## Si es false, el pelo se oculta (variante "sin pelo" / calvo), usando el
## mismo modelo base sin necesidad de otra malla.
@export var hair_visible: bool = true

@export_group("Animación de locomoción")
## Ruta al nodo PlayerMovement cuyo estado se lee para decidir la
## animación. Por defecto asume que este nodo cuelga como hijo directo del
## Player (CharacterBody3D con player_movement.gd), igual convención que
## ya usa psx_character_controller.gd para el jugador PSX.
@export var movement_node_path: NodePath = NodePath("..")
## Velocidad horizontal mínima para considerar que el personaje se está
## moviendo (evita parpadeo Idle/Walk por ruido numérico a velocidad casi
## cero).
@export var move_speed_threshold: float = 0.15

@export_group("Foot IK (locomoción procedural)")
## Primera versión de Foot IK: adapta la posición/orientación de los pies
## al terreno real por encima de Idle/Walk/Sprint/Crouch/Jump, sin tocar
## esas animaciones. Ver scripts/systems/procedural_locomotion/
## foot_ik_controller.gd para el detalle de qué hace y sus limitaciones.
@export var enable_foot_ik: bool = true
## Expuestos aquí los parámetros que más probablemente haya que ajustar
## por variante/escenario; el resto de opciones de FootIKController se
## quedan en sus valores por defecto (ya pensados para este personaje).
@export var foot_ik_ray_length: float = 0.6
@export_flags_3d_physics var foot_ik_collision_mask: int = 1

@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _movement: PlayerMovement = get_node_or_null(movement_node_path) as PlayerMovement

var _current_state_anim: String = ""


func _ready() -> void:
	SharedAnimationLibrary.apply_to(_animation_player)
	_apply_appearance()
	_play_state(LocomotionState.ANIM_IDLE)
	if enable_foot_ik:
		_setup_foot_ik()


func _physics_process(_delta: float) -> void:
	if _movement == null:
		return
	var horizontal_speed := Vector2(_movement.velocity.x, _movement.velocity.z).length()
	_play_state(LocomotionState.resolve(horizontal_speed, _movement.walk_speed, move_speed_threshold))


func _play_state(state_anim: String) -> void:
	if state_anim == _current_state_anim or _animation_player == null:
		return
	_current_state_anim = state_anim

	var full_name := SharedAnimationLibrary.LIBRARY_NAME + "/" + state_anim
	if not _animation_player.has_animation(full_name):
		push_warning("CharacterVariant (%s): la animación '%s' no está disponible." % [name, full_name])
		return
	_animation_player.play(full_name)


func _apply_appearance() -> void:
	var body_mesh := _find_mesh_instance(self, BODY_MESH_NAME)
	if body_mesh != null:
		_tint_mesh(body_mesh, skin_tint)
	else:
		push_warning("CharacterVariant: no se encontró la malla de cuerpo '%s'." % BODY_MESH_NAME)

	var hair_mesh := _find_mesh_instance(self, HAIR_MESH_NAME)
	if hair_mesh != null:
		hair_mesh.visible = hair_visible
		if hair_visible:
			_tint_mesh(hair_mesh, hair_tint)
	else:
		push_warning("CharacterVariant: no se encontró la malla de pelo '%s'." % HAIR_MESH_NAME)


func _tint_mesh(mesh_instance: MeshInstance3D, tint: Color) -> void:
	var base_material := mesh_instance.get_active_material(0)
	if base_material == null:
		return
	# duplicate() copia la referencia a la MISMA textura (no la duplica en
	# disco ni en memoria de forma pesada); solo creamos un pequeño material
	# nuevo con otro albedo_color.
	var override_material: Material = base_material.duplicate()
	if override_material is BaseMaterial3D:
		(override_material as BaseMaterial3D).albedo_color = tint
	mesh_instance.material_override = override_material


func _find_mesh_instance(node: Node, target_name: String) -> MeshInstance3D:
	if node is MeshInstance3D and node.name == target_name:
		return node
	for child in node.get_children():
		var result := _find_mesh_instance(child, target_name)
		if result != null:
			return result
	return null


# ---------------------------------------------------------------------------
# FOOT IK (locomoción procedural) — primera versión
# ---------------------------------------------------------------------------
# Instala un FootIKController (scripts/systems/procedural_locomotion/
# foot_ik_controller.gd) como hijo del Skeleton3D real de este personaje.
#
# El Skeleton3D se busca por TIPO de nodo, recorriendo el árbol del
# modelo importado (Model, hijo de este mismo nodo), en vez de asumir una
# ruta fija tipo "$Model/Skeleton3D" o "$Model/Armature/Skeleton3D": el
# nombre exacto que el importador de glTF de Godot le da al Skeleton3D
# generado no se ha podido confirmar abriendo el proyecto en el editor
# (ver notas de la entrega), así que en vez de arriesgarse a una ruta
# incorrecta se localiza dinámicamente, lo cual además hace que esto
# siga funcionando aunque cambie la estructura interna del modelo
# importado en una futura reexportación.
func _setup_foot_ik() -> void:
	var skeleton := _find_skeleton3d(self)
	if skeleton == null:
		push_warning("CharacterVariant (%s): no se encontró ningún Skeleton3D bajo este nodo; Foot IK no se ha instalado. Revisa que el modelo importado tenga un esqueleto (ver notas de la entrega)." % name)
		return

	var foot_ik := FootIKController.new()
	foot_ik.name = "FootIKController"
	foot_ik.ray_length_down = foot_ik_ray_length
	foot_ik.collision_mask = foot_ik_collision_mask
	# _movement es el CharacterBody3D del jugador (ver movement_node_path):
	# se excluye de los RayCast3D para que no se detecte a sí mismo como
	# "suelo". Se usa una ruta ABSOLUTA (get_path(), no get_path_to())
	# y se asigna ANTES de add_child(), porque FootIKController lee
	# body_to_exclude en su propio _ready(), que se dispara en el mismo
	# add_child() si skeleton ya está en el árbol (como es el caso aquí).
	if _movement != null:
		foot_ik.body_to_exclude = _movement.get_path()
	skeleton.add_child(foot_ik)


func _find_skeleton3d(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton3d(child)
		if result != null:
			return result
	return null
