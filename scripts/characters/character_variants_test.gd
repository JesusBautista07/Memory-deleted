extends Node3D
## Script exclusivo de la escena de prueba CharacterVariants_TestScene.tscn.
## Reproduce una animación (Idle) en cada variante visible para comprobar
## de un vistazo que el rig y las animaciones importadas funcionan.
## No forma parte del Player ni de ningún otro sistema del juego.

const TEST_ANIMATION := "UAL/Idle_Loop"


func _ready() -> void:
	for child in get_children():
		_try_play_idle(child)


func _try_play_idle(node: Node) -> void:
	var anim_player := _find_animation_player(node)
	if anim_player != null and anim_player.has_animation(TEST_ANIMATION):
		anim_player.play(TEST_ANIMATION)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null
