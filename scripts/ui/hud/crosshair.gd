extends Control
class_name Crosshair
## Punto de mira fijo en el centro de la pantalla, estilo FPS.
##
## Responsabilidad única: dibujar el crosshair y cambiar de forma según el
## estado que le manda InteractionManager (ver
## scripts/interaction/interaction_manager.gd, señal crosshair_state_changed
## y grupo "crosshair_hud"). No lee el RayCast directamente ni duplica
## ninguna lógica de detección: es puramente visual, para no crear un
## segundo sistema paralelo de detección de interactuables.
##
## Es un Control dentro de un CanvasLayer (ver scenes/ui/hud/Crosshair.tscn):
## no rota con la cámara ni forma parte del mundo 3D.

## Debe coincidir con las constantes CROSSHAIR_STATE_* de InteractionManager.
const STATE_NONE := 0
const STATE_INTERACT := 1
const STATE_COMBAT := 2

## Grupo por el que InteractionManager localiza este nodo automáticamente,
## igual que ya hace con InteractionPrompt (PROMPT_GROUP).
const GROUP_NAME := "crosshair_hud"

@export var dot_radius: float = 2.0
@export var plus_size: float = 6.0
@export var plus_thickness: float = 2.0
@export var line_color: Color = Color(1, 1, 1, 0.9)
@export var outline_color: Color = Color(0, 0, 0, 0.55)
## Color del crosshair en modo COMBAT (objetivo de disparo bajo la mira).
## Deliberadamente sutil -no rojo saturado- para no romper el estilo
## "limpio, sin colores exagerados" que pide el ticket.
@export var combat_color: Color = Color(1, 0.35, 0.3, 0.95)

var _state: int = STATE_NONE


func _ready() -> void:
	# Ignora el mouse: el crosshair nunca debe robar clics ni bloquear el
	# resto de la UI (prompt, inventario, menús).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP_NAME)

	# Centrado fijo en pantalla, tamaño pequeño, no se mueve con la cámara
	# (es un Control 2D dentro de un CanvasLayer, ver la escena).
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(32, 32)
	size = Vector2(32, 32)
	pivot_offset = size / 2.0


func set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var color := combat_color if _state == STATE_COMBAT else line_color

	if _state == STATE_NONE:
		# Estado normal: punto pequeño y discreto.
		draw_circle(center, dot_radius + 1.0, outline_color)
		draw_circle(center, dot_radius, color)
	else:
		# Apuntando a un interactuable o a un objetivo de combate: cruz.
		_draw_plus(center, color)


func _draw_plus(center: Vector2, color: Color) -> void:
	var half := plus_size / 2.0
	# Contorno oscuro primero (más grueso) para que se lea sobre cualquier
	# fondo, y encima la cruz de color.
	var outline_thickness := plus_thickness + 2.0
	draw_line(center + Vector2(-half, 0), center + Vector2(half, 0), outline_color, outline_thickness)
	draw_line(center + Vector2(0, -half), center + Vector2(0, half), outline_color, outline_thickness)
	draw_line(center + Vector2(-half, 0), center + Vector2(half, 0), color, plus_thickness)
	draw_line(center + Vector2(0, -half), center + Vector2(0, half), color, plus_thickness)
