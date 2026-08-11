extends Label
## HUD mínimo de munición (Test_Final_System). No existía ningún elemento
## de HUD aparte de InteractionPrompt, así que no había forma visual de
## comprobar cargador/reserva/recarga aunque WeaponCombat ya emitía las
## señales necesarias (ammo_changed, reload_started, reload_finished).
## Responsabilidad única: mostrar texto. No lee input ni conoce Inventory.

@export var weapon_combat: WeaponCombat


func _ready() -> void:
	text = ""
	if weapon_combat == null:
		return

	weapon_combat.ammo_changed.connect(_on_ammo_changed)
	weapon_combat.reload_started.connect(_on_reload_started)
	weapon_combat.reload_finished.connect(_on_reload_finished)
	weapon_combat.weapon_empty.connect(_on_weapon_empty)


func _on_ammo_changed(magazine: int, reserve: int) -> void:
	text = "Munición: %d / %d" % [magazine, reserve]


func _on_reload_started(_weapon_data: WeaponData) -> void:
	text += "  (recargando...)"


func _on_reload_finished(_weapon_data: WeaponData) -> void:
	pass  # ammo_changed ya llega justo después con los valores finales.


func _on_weapon_empty(_weapon_data: WeaponData) -> void:
	text += "  ¡VACÍO!"
