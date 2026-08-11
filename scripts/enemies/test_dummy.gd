extends StaticBody3D
class_name TestDummy
## Objetivo de combate mínimo para pruebas (Test_Final_System).
##
## No es un enemigo con IA: no persigue, no ataca, no usa
## scripts/ai/*. Su única responsabilidad es dar un objetivo real a
## WeaponCombat._fire_ray(), que ya buscaba un método take_damage() en el
## collider golpeado pero no existía NINGÚN nodo en el proyecto que lo
## implementara, así que "Combate" no se podía probar de principio a fin
## pese a que el disparo y el daño (weapon_data.damage) ya funcionaban.
##
## Deliberadamente en scripts/enemies/ (no scripts/ai/) porque no sustituye
## ni amplía el sistema de IA existente (AIController/AIStateMachine): es
## solo un maniquí de pruebas, tal como pide el ticket ("no importa si usa
## un modelo simple").

signal health_changed(current: float, max_health: float)
signal died

@export var max_health: float = 30.0
@export var visual_root: Node3D

var _health: float = 0.0
var _is_dead: bool = false


func _ready() -> void:
	_health = max_health
	health_changed.emit(_health, max_health)


## Punto de entrada que WeaponCombat ya invoca automáticamente
## (collider.call("take_damage", weapon_data.damage)) sobre cualquier
## objeto golpeado que lo implemente.
func take_damage(amount: float) -> void:
	if _is_dead or amount <= 0.0:
		return

	_health = max(_health - amount, 0.0)
	print("[020F] TestDummy recibió daño: ", amount, " -> salud=", _health, "/", max_health)
	health_changed.emit(_health, max_health)

	if _health <= 0.0:
		_die()


func is_dead() -> bool:
	return _is_dead


func get_health() -> float:
	return _health


func _die() -> void:
	_is_dead = true
	print("[020F] TestDummy murió")
	died.emit()

	# Deja de ser un objetivo válido (igual que PickupObject.deactivate()
	# desactiva colisión al recogerse) para que no se le pueda seguir
	# disparando ni bloquee el RayCast de interacción.
	collision_layer = 0
	collision_mask = 0

	if visual_root != null:
		visual_root.visible = false
	else:
		visible = false
