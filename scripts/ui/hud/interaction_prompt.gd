extends Control
## Pequeño indicador de interacción ("Presiona E para..."). El texto
## se controla por código; no contiene lógica de interacción.

## Grupo por el que InteractionManager localiza este nodo automáticamente
## (ver scripts/interaction/interaction_manager.gd), sin necesidad de que
## cada escena cablee un NodePath a mano.
const GROUP_NAME := "interaction_prompt"

@onready var _label: Label = %PromptLabel


func _ready() -> void:
	visible = false
	add_to_group(GROUP_NAME)


func show_prompt(text: String) -> void:
	_label.text = text
	visible = true


func hide_prompt() -> void:
	visible = false


func set_text(text: String) -> void:
	_label.text = text
