extends Node
class_name Inventory

signal item_added(object_data: ObjectData)
signal item_removed(object_data: ObjectData)
signal document_registered(object_data: ObjectData, source: PickupObject)
signal inventory_changed(items: Array)

const GROUP_NAME := "inventory"
const SAVEABLE_GROUP_NAME := "saveable_inventory"

var _items: Array[ObjectData] = []
var _document_ids: Array[String] = []

func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(SAVEABLE_GROUP_NAME)

func add_item(object_data: ObjectData, source: PickupObject = null) -> bool:
	if object_data == null:
		return false

	if not object_data.can_be_stored:
		return false

	if has_item(object_data.object_id):
		return false

	print("[020E] Inventory.add_item() -> ", object_data.object_id)

	_items.append(object_data)
	item_added.emit(object_data)
	inventory_changed.emit(get_items())

	if source is DocumentItem:
		_register_document(object_data, source)

	return true

func remove_item(object_id: String) -> bool:
	for i in range(_items.size()):
		if _items[i].object_id == object_id:
			var removed: ObjectData = _items[i]
			_items.remove_at(i)
			item_removed.emit(removed)
			inventory_changed.emit(get_items())
			return true
	return false

func has_item(object_id: String) -> bool:
	for data in _items:
		if data.object_id == object_id:
			return true
	return false

func get_items() -> Array[ObjectData]:
	return _items.duplicate()

func get_item(object_id: String) -> ObjectData:
	for data in _items:
		if data.object_id == object_id:
			return data
	return null

func is_document(object_id: String) -> bool:
	return _document_ids.has(object_id)

func get_document_ids() -> Array[String]:
	return _document_ids.duplicate()

## Añadido en el Ticket 020E: devuelve los object_id de todos los objetos
## marcados como is_key_item = true que el jugador tiene actualmente. Es lo
## que consume Door._get_available_key_ids() para poder abrir puertas
## bloqueadas desde el flujo real del juego (antes solo funcionaba en el
## script de pruebas test_door_sandbox.gd, que simulaba las llaves a mano).
func get_key_ids() -> Array:
	var key_ids: Array = []
	for data in _items:
		if data != null and data.is_key_item:
			key_ids.append(data.object_id)
	return key_ids

func _register_document(object_data: ObjectData, source: PickupObject) -> void:
	if _document_ids.has(object_data.object_id):
		return
	_document_ids.append(object_data.object_id)
	document_registered.emit(object_data, source)

## Contrato consumido por SaveManager para el grupo "saveable_inventory".
## Devuelve el estado actual como object_id -> ObjectData, listo para ser
## asignado directamente a SaveData.inventory (Dictionary).
func save_state() -> Dictionary:
	var state: Dictionary = {}
	for data in _items:
		state[data.object_id] = data
	return state

## Contrato consumido por SaveManager para el grupo "saveable_inventory".
## Restaura _items a partir de los datos devueltos previamente por
## save_state(). No dispara document_registered: el estado de lectura de
## documentos se restaura por separado a través del propio DocumentManager.
func load_state(state: Dictionary) -> void:
	_items.clear()
	for object_id in state.keys():
		var data: ObjectData = state[object_id]
		if data == null:
			continue
		_items.append(data)
	inventory_changed.emit(get_items())
