extends Control
## Menú principal. Navega a test_player.tscn, o muestra Ajustes/Créditos
## como overlays. No depende de ningún otro sistema del proyecto.

@onready var _button_new_game: Button = %ButtonNewGame
@onready var _button_continue: Button = %ButtonContinue
@onready var _button_settings: Button = %ButtonSettings
@onready var _button_credits: Button = %ButtonCredits
@onready var _button_quit: Button = %ButtonQuit
@onready var _options_menu: Control = %OptionsMenu
@onready var _credits_menu: Control = %CreditsMenu


func _ready() -> void:
	_button_new_game.pressed.connect(_on_new_game_pressed)
	_button_continue.disabled = true
	_button_settings.pressed.connect(_on_settings_pressed)
	_button_credits.pressed.connect(_on_credits_pressed)
	_button_quit.pressed.connect(_on_quit_pressed)

	_options_menu.visible = false
	_credits_menu.visible = false
	_options_menu.closed.connect(_on_options_closed)
	_credits_menu.closed.connect(_on_credits_closed)


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://tests/test_player.tscn")


func _on_settings_pressed() -> void:
	_options_menu.visible = true


func _on_credits_pressed() -> void:
	_credits_menu.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_options_closed() -> void:
	_options_menu.visible = false


func _on_credits_closed() -> void:
	_credits_menu.visible = false
