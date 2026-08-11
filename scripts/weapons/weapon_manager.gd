extends Node3D
class_name WeaponManager
## Controla qué arma está equipada y visible en primera persona.
##
## Deliberadamente NO mantiene su propia lista de armas: en cada consulta
## lee el Inventory ya existente (localizándolo por el grupo "inventory",
## igual que hace PickupObject) y filtra los ObjectData que sean WeaponData.
## Así no existe ningún inventario paralelo — el Inventory sigue siendo la
## única fuente de verdad sobre qué objetos tiene el jugador.
##
## Este nodo tampoco lee input ni dispara nada: solo expone la API pública
## (equip_weapon, unequip_weapon, equip_next, equip_previous) para que un
## futuro sistema de disparo/input la use. Ver scenes/weapons/WeaponManager.tscn
## para la estructura de nodos (incluye el hijo WeaponMount, el punto donde
## se instancia el modelo en primera persona).

signal weapon_equipped(weapon_data: WeaponData)
signal weapon_unequipped(weapon_data: WeaponData)
signal weapon_list_changed(available: Array[WeaponData])

const INVENTORY_GROUP := "inventory"

@onready var weapon_mount: Node3D = $WeaponMount

var _current_weapon_data: WeaponData = null
var _current_view_model: Node3D = null
var _inventory: Node = null


func _ready() -> void:
	# Corrección Ticket 020D: Player (y por tanto WeaponManager) se ready()
	# antes que el nodo Inventory en el árbol de la escena, así que buscar
	# el grupo "inventory" aquí mismo siempre lo encontraba vacío. Se
	# difiere un frame con call_deferred (sigue siendo "localizar por
	# grupo", solo se corrige el momento) para que Inventory ya se haya
	# añadido a su grupo cuando se busca.
	call_deferred("_bind_inventory")


func _bind_inventory() -> void:
	_inventory = get_tree().get_first_node_in_group(INVENTORY_GROUP)

	if _inventory != null and _inventory.has_signal("item_removed"):
		_inventory.item_removed.connect(_on_inventory_item_removed)
	if _inventory != null and _inventory.has_signal("inventory_changed"):
		_inventory.inventory_changed.connect(_on_inventory_changed)


## Lee el Inventory existente y devuelve solo los ObjectData que son armas.
## Nunca guarda esta lista: se recalcula cada vez que se pide, para no
## desincronizarse jamás del Inventory real.
func get_available_weapons() -> Array[WeaponData]:
	var weapons: Array[WeaponData] = []

	if _inventory == null or not _inventory.has_method("get_items"):
		return weapons

	for data in _inventory.call("get_items"):
		if data is WeaponData:
			weapons.append(data)

	return weapons


## Equipa un arma que ya debe estar en el Inventory (recogida previamente
## mediante WeaponItem/PickupObject). Instancia su view_model_scene bajo
## WeaponMount y oculta/libera el modelo anterior si había uno.
func equip_weapon(weapon_data: WeaponData) -> bool:
	if weapon_data == null:
		return false

	if not get_available_weapons().has(weapon_data):
		return false  # Solo se puede equipar un arma que el Inventory ya tenga.

	_clear_view_model()
	_current_weapon_data = weapon_data

	if weapon_data.view_model_scene != null:
		_current_view_model = weapon_data.view_model_scene.instantiate()
		weapon_mount.add_child(_current_view_model)
		_current_view_model.position = weapon_data.holster_offset

	weapon_equipped.emit(weapon_data)
	print("[020E] Weapon equipada: ", weapon_data.object_id)
	return true


## Desequipa el arma actual (si hay una) y oculta su modelo en primera
## persona liberándolo.
func unequip_weapon() -> void:
	if _current_weapon_data == null:
		return

	var previous_weapon: WeaponData = _current_weapon_data
	_clear_view_model()
	_current_weapon_data = null
	weapon_unequipped.emit(previous_weapon)


## Equipa la siguiente arma disponible en el Inventory, en orden cíclico.
func equip_next() -> bool:
	return _equip_relative(1)


## Equipa el arma anterior disponible en el Inventory, en orden cíclico.
func equip_previous() -> bool:
	return _equip_relative(-1)


func is_weapon_equipped() -> bool:
	return _current_weapon_data != null


func get_equipped_weapon() -> WeaponData:
	return _current_weapon_data


## Añadido en el Ticket 020C: expone el nodo del view model actualmente
## instanciado bajo WeaponMount (o null si no hay arma equipada), para que
## un sistema externo (WeaponCombat) pueda animarlo al disparar sin tener
## que duplicar la lógica de instanciación que ya vive aquí.
func get_current_view_model() -> Node3D:
	return _current_view_model


func _equip_relative(step: int) -> bool:
	var weapons: Array[WeaponData] = get_available_weapons()
	if weapons.is_empty():
		return false

	var current_index: int = weapons.find(_current_weapon_data)
	var next_index: int

	if current_index == -1:
		next_index = 0 if step > 0 else weapons.size() - 1
	else:
		next_index = (current_index + step + weapons.size()) % weapons.size()

	print("[020E] Weapon cambiada -> ", weapons[next_index].object_id)
	return equip_weapon(weapons[next_index])


func _clear_view_model() -> void:
	if _current_view_model != null:
		_current_view_model.queue_free()
		_current_view_model = null


func _on_inventory_item_removed(object_data: ObjectData) -> void:
	# Si el arma equipada se pierde del Inventory (p. ej. un futuro sistema
	# de crafteo/consumo la retira), se desequipa automáticamente en vez de
	# quedar "fantasma" en la mano del jugador.
	if _current_weapon_data != null and object_data == _current_weapon_data:
		unequip_weapon()


func _on_inventory_changed(_items: Array) -> void:
	weapon_list_changed.emit(get_available_weapons())
