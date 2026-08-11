class_name SaveSlot
extends Resource

## Representa la información resumida de una ranura de guardado.
## Pensado para listar/mostrar ranuras en menús (UI) sin necesidad de
## mantener en memoria el SaveData completo de cada partida.

@export var slot_id: int = -1
@export var exists: bool = false
@export var file_path: String = ""

@export var save_version: int = 1
@export var save_name: String = ""
@export var current_scene: String = ""
@export var level_name: String = ""
@export var save_date: String = ""
@export var save_time: String = ""
@export var played_time: float = 0.0


## Devuelve el tiempo jugado formateado como HH:MM:SS.
## División entera intencional (horas/minutos completos): se silencia el
## warning INTEGER_DIVISION de Godot 4 en vez de dejarlo aparecer, igual
## que en SaveData.get_formatted_played_time() (misma lógica duplicada
## aquí porque SaveSlot es la versión "ligera" para listar partidas sin
## cargar el SaveData completo).
func get_formatted_played_time() -> String:
	var total_seconds: int = int(played_time)
	@warning_ignore("integer_division")
	var hours: int = total_seconds / 3600
	@warning_ignore("integer_division")
	var minutes: int = (total_seconds % 3600) / 60
	var seconds: int = total_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]


## Construye un SaveSlot a partir de un SaveData ya cargado (y ya migrado).
static func from_save_data(p_slot_id: int, p_file_path: String, p_data: SaveData) -> SaveSlot:
	var slot := SaveSlot.new()
	slot.slot_id = p_slot_id
	slot.exists = true
	slot.file_path = p_file_path
	slot.save_version = p_data.save_version
	slot.save_name = p_data.save_name
	slot.current_scene = p_data.current_scene
	slot.level_name = p_data.level_name
	slot.save_date = p_data.save_date
	slot.save_time = p_data.save_time
	slot.played_time = p_data.played_time
	return slot


## Construye un SaveSlot vacío (ranura sin partida guardada, o corrupta/no legible).
static func empty(p_slot_id: int, p_file_path: String) -> SaveSlot:
	var slot := SaveSlot.new()
	slot.slot_id = p_slot_id
	slot.exists = false
	slot.file_path = p_file_path
	return slot
