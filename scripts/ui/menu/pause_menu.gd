extends CanvasLayer
## Menú de pausa. Se abre/cierra con ui_cancel (ESC por defecto).
## Pausa el árbol de escena, muestra el cursor y bloquea el movimiento
## del jugador/cámara de forma indirecta (esos scripts dejan de procesar
## al pausar el árbol, sin necesidad de modificarlos).
##
## CORRECCIÓN (causa raíz real de "el inventario se comporta como el menú
## de pausa" / "al abrir el inventario el juego se pausa"): InventoryUI
## está anidado dentro de %Panel (ver scenes/ui/menu/PauseMenu.tscn), el
## mismo Control que contiene el fondo oscuro y los botones Continuar/
## Inventario/Ajustes/Menú/Salir. Antes, abrir el inventario con su tecla
## (TAB) llamaba a _open_pause(), que solo hacía visible = true en este
## CanvasLayer; como %Panel nunca se ocultaba por separado, eso mostraba
## SIEMPRE el panel de pausa completo (fondo + botones) detrás/junto al
## inventario, exactamente como el menú de pausa. Ahora %Panel/Background
## y %Panel/CenterContainer (el fondo y los botones) se muestran u ocultan
## por separado de InventoryUI, así que TAB abre solo el inventario, y ESC
## sigue abriendo el menú de pausa real de forma independiente.

@onready var _pause_background: CanvasItem = %Panel.get_node("Background")
@onready var _pause_buttons: CanvasItem = %Panel.get_node("CenterContainer")
@onready var _button_continue: Button = %ButtonContinue
@onready var _button_inventory: Button = %ButtonInventory
@onready var _button_settings: Button = %ButtonSettings
@onready var _button_main_menu: Button = %ButtonMainMenu
@onready var _button_quit: Button = %ButtonQuit
@onready var _inventory_ui: Control = %InventoryUI
@onready var _options_menu: Control = %OptionsMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_button_continue.pressed.connect(_on_continue_pressed)
	_button_inventory.pressed.connect(_on_inventory_pressed)
	_button_settings.pressed.connect(_on_settings_pressed)
	_button_main_menu.pressed.connect(_on_main_menu_pressed)
	_button_quit.pressed.connect(_on_quit_pressed)

	_inventory_ui.visible = false
	_options_menu.visible = false
	_inventory_ui.closed.connect(_on_inventory_closed)
	_options_menu.closed.connect(_on_options_closed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible and not _pause_buttons.visible:
			# El inventario standalone (TAB) estaba abierto SIN el panel
			# de pausa: ESC lo cierra y vuelve directo al juego, en vez
			# de abrir encima el menú de pausa real.
			_close_inventory_only()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()
		return

	# CORRECCIÓN (auditoría Test_Final_System): la acción "inventory" ya
	# existía como entrada re-asignable en OptionsMenu (REBINDABLE_ACTIONS)
	# pero ningún script la leía todavía, así que no tenía ningún efecto en
	# el juego real. Se abre aquí, reutilizando el mismo InventoryUI que ya
	# usa el botón "Inventario" del menú de pausa, en vez de crear un
	# sistema de inventario "standalone" nuevo y duplicado.
	if event.is_action_pressed("inventory"):
		_toggle_inventory_shortcut()
		get_viewport().set_input_as_handled()


func _toggle_inventory_shortcut() -> void:
	if visible and _inventory_ui.visible and not _pause_buttons.visible:
		# El inventario standalone (TAB) ya estaba abierto: cerrarlo.
		_close_inventory_only()
	elif not visible:
		# Nada abierto todavía: abrir solo el inventario (sin el panel
		# de pausa) y ocultar el crosshair mientras esté abierto.
		_open_inventory_only()
	else:
		# El menú de pausa (ESC) ya está abierto: TAB solo alterna la
		# vista de inventario dentro de él, sin tocar el estado de pausa
		# ni el panel de botones, que ya está visible.
		if _inventory_ui.visible:
			_inventory_ui.visible = false
		else:
			_on_inventory_pressed()


func _toggle_pause() -> void:
	if visible:
		_close_pause()
	else:
		_open_pause()


func _open_pause() -> void:
	visible = true
	_pause_background.visible = true
	_pause_buttons.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_crosshair_visible(false)


func _close_pause() -> void:
	visible = false
	_pause_background.visible = true
	_pause_buttons.visible = true
	_inventory_ui.visible = false
	_options_menu.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_crosshair_visible(true)


func _open_inventory_only() -> void:
	visible = true
	_pause_background.visible = false
	_pause_buttons.visible = false
	_inventory_ui.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_crosshair_visible(false)


func _close_inventory_only() -> void:
	visible = false
	_inventory_ui.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_crosshair_visible(true)


func _on_continue_pressed() -> void:
	_close_pause()


func _on_inventory_pressed() -> void:
	_inventory_ui.visible = true


func _on_settings_pressed() -> void:
	_options_menu.visible = true


func _on_inventory_closed() -> void:
	_inventory_ui.visible = false
	if visible and not _pause_buttons.visible:
		# Se cerró el inventario standalone (TAB) desde su propio botón
		# "Cerrar": volver directo al juego en vez de dejar el CanvasLayer
		# visible y pausado sin ningún panel dentro.
		_close_inventory_only()


func _on_options_closed() -> void:
	_options_menu.visible = false


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/menu/MainMenu.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


## CORRECCIÓN (causa raíz real de "el crosshair no desaparece al abrir
## inventario/pausa"): Crosshair (scripts/ui/hud/crosshair.gd) solo
## cambiaba de FORMA según el estado que le manda InteractionManager (ver
## crosshair_state_changed), pero ningún sistema controlaba su
## visibilidad; se quedaba visible encima de cualquier menú. Se localiza
## por grupo ("crosshair_hud", el mismo que ya usa InteractionManager)
## para no acoplar PauseMenu a un NodePath fijo hacia el HUD.
func _set_crosshair_visible(value: bool) -> void:
	var crosshair: Node = get_tree().get_first_node_in_group("crosshair_hud")
	if crosshair != null:
		crosshair.visible = value
