extends Node
class_name Interactable

enum InteractionType {
	NONE,
	DOOR,
	ITEM,
	DOCUMENT,
	SWITCH,
	EVENT,
	PUZZLE,
}

signal interacted(interactor: Object)

@export var interaction_prompt: String = "[E] Interactuar"
@export var can_interact: bool = true
@export var interaction_type: InteractionType = InteractionType.NONE
@export var interaction_id: String = ""

func interact() -> void:
	if not can_interact:
		return
	interacted.emit(self)

func get_interaction_prompt() -> String:
	return interaction_prompt

func is_interactable() -> bool:
	return can_interact

func set_interactable(value: bool) -> void:
	can_interact = value

func get_interaction_type() -> InteractionType:
	return interaction_type

func get_interaction_id() -> String:
	return interaction_id
