class_name FirstPersonArmsController
extends Node3D
## Controlador mínimo de los brazos en primera persona (paquete
## PSX_First_Person_Arms). Por ahora solo se encarga de:
## - Reproducir una animación de reposo en bucle simple para que no se
##   queden en T-pose.
## - Exponer play_hand_animation() para que, en una etapa posterior,
##   agarrar objetos / sostener la linterna / armas puedan reproducir las
##   animaciones que ya trae el propio rig (grab.L, grab.R, push.L, push.R,
##   knife_idle, finger_gun_idle, etc. -ver ArmsModel/AnimationPlayer-).
##
## Este script NO lee input, NO gestiona inventario ni combate: solo el
## aspecto visual de los brazos. La integración con sostener linterna/armas
## se hará en una etapa posterior según lo indicado por el usuario.

## Animación del rig de brazos usada como pose de reposo. "rest" y "relax"
## son las dos disponibles en arms_rig.glb; "rest" es la pose neutra más
## cercana a sostener un arma imaginaria a la cadera, así que se usa como
## valor por defecto.
@export var idle_animation: StringName = &"rest"

var _anim_player: AnimationPlayer = null

## arms_rig.glb trae su propio AnimationPlayer embebido (con las
## animaciones grab/push/knife/etc. ya listas). Se localiza en tiempo de
## ejecución, en vez de asumir una ruta fija, para no depender de la
## jerarquía interna exacta que genere el importador FBX/glTF de Godot.
func _ready() -> void:
	_anim_player = _find_animation_player(self)

	if _anim_player == null:
		push_warning("FirstPersonArmsController: no se encontró ningún AnimationPlayer dentro de ArmsModel.")
		return

	play_hand_animation(idle_animation)


## Reproduce cualquiera de las animaciones que ya trae arms_rig.glb (rest,
## relax, grab.L, grab.R, push.L, push.R, jab.L, jab.R, knife_idle,
## knife_draw, knife_hit_01, knife_hit_02, guard_idle, guard_draw,
## finger_gun_idle, finger_gun_fire, finger_gun_fix, finger_gun_broken).
## Pensado para que la etapa de interacción (agarrar objetos, linterna,
## armas) llame a esto sin tener que conocer la jerarquía interna del rig.
func play_hand_animation(anim_name: StringName) -> void:
	if _anim_player == null:
		return
	if not _anim_player.has_animation(anim_name):
		push_warning("FirstPersonArmsController: la animación '%s' no existe en arms_rig.glb." % anim_name)
		return
	_anim_player.play(anim_name)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
