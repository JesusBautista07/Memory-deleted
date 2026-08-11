class_name SaveData
extends Resource

## Contenedor de datos de una partida guardada.
## No depende de ningún otro sistema del proyecto: solo almacena datos
## primitivos y estructuras genéricas (Dictionary/Array) para mantener
## el acoplamiento lo más bajo posible.

# --- Versionado del formato de guardado ---
# Permite a SaveManager detectar partidas antiguas y migrarlas si el
# formato de este Resource cambia en el futuro.
@export var save_version: int = 1

# --- Identificación de la partida ---
@export var slot_id: int = -1
@export var save_name: String = ""

# --- Estado del jugador ---
@export var player_position: Vector3 = Vector3.ZERO
@export var player_rotation: Vector3 = Vector3.ZERO
@export var current_scene: String = ""  # Ruta técnica de la escena (scene_file_path)
@export var level_name: String = ""     # Nombre legible del nivel, para mostrar en UI

# --- Metadatos temporales ---
@export var save_date: String = ""    # Fecha de guardado, formato AAAA-MM-DD
@export var save_time: String = ""    # Hora de guardado, formato HH:MM:SS
@export var played_time: float = 0.0  # Tiempo jugado acumulado, en segundos

# --- Progreso y estado del mundo ---
# Se usan estructuras genéricas para no acoplar este Resource a sistemas
# concretos (Inventario, Puertas, Puzzles, etc.).
@export var inventory: Dictionary = {}        # item_id -> datos del item
@export var objects_state: Dictionary = {}    # object_id -> estado (Dictionary)
@export var documents: Array = []             # ids de documentos recolectados/leídos
@export var doors_state: Dictionary = {}      # door_id -> estado (abierta/cerrada/bloqueada...)
@export var events_state: Dictionary = {}     # event_id -> estado del evento
@export var puzzles_state: Dictionary = {}    # puzzle_id -> estado del puzzle
@export var global_variables: Dictionary = {} # variables globales de progreso narrativo

# --- Extensibilidad futura ---
# Diccionario libre para que futuros sistemas guarden datos propios sin
# necesidad de modificar este Resource ni romper compatibilidad con
# partidas ya guardadas.
@export var custom_data: Dictionary = {}


## Devuelve el tiempo jugado formateado como HH:MM:SS.
## La división entera aquí es intencional (se busca el número de horas/
## minutos completos, no una fracción), así que se silencia el warning
## INTEGER_DIVISION de Godot 4 en vez de dejarlo aparecer: no es un bug,
## es justo el comportamiento que se quiere.
func get_formatted_played_time() -> String:
	var total_seconds: int = int(played_time)
	@warning_ignore("integer_division")
	var hours: int = total_seconds / 3600
	@warning_ignore("integer_division")
	var minutes: int = (total_seconds % 3600) / 60
	var seconds: int = total_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]
