extends Control
class_name InventoryUI

signal closed
signal document_item_added(item: ObjectData)
## Emitida al pulsar "Usar" sobre un objeto que no es documento. No hay
## todavía un sistema de "objeto en mano" que la consuma (linterna,
## encendedor, etc. ya exponen su propio toggle()/request_*() -- ver
## scripts/objects/*.gd), así que por ahora solo se notifica.
signal item_used(item: ObjectData)

const INVENTORY_GROUP := "inventory"
const DOCUMENT_MANAGER_GROUP := "document_manager"
const DOCUMENTS_UI_GROUP := "documents_ui"

@export var inventory_path: NodePath

@onready var _item_list: ItemList = %ItemList
@onready var _item_name_label: Label = %ItemNameLabel
@onready var _item_description_label: Label = %ItemDescriptionLabel
@onready var _button_use: Button = %ButtonUse
@onready var _button_close: Button = %ButtonClose

var _inventory: Inventory = null
var _list_ids: Array[String] = []
var _selected_id: String = ""

func _ready() -> void:
	_button_close.pressed.connect(_on_button_close_pressed)
	_button_use.pressed.connect(_on_button_use_pressed)
	_item_list.item_selected.connect(_on_item_list_item_selected)
	_resolve_inventory()

func _resolve_inventory() -> void:
	if not inventory_path.is_empty():
		var node: Node = get_node_or_null(inventory_path)
		if node is Inventory:
			_bind_inventory(node)
			return

	var found: Node = get_tree().get_first_node_in_group(INVENTORY_GROUP)
	if found is Inventory:
		_bind_inventory(found)

func set_inventory(inventory: Inventory) -> void:
	_bind_inventory(inventory)

func _bind_inventory(inventory: Inventory) -> void:
	_inventory = inventory
	_inventory.item_added.connect(_on_item_added)
	_inventory.item_removed.connect(_on_item_removed)
	refresh()

func refresh() -> void:
	_item_list.clear()
	_list_ids.clear()
	_clear_details()

	if _inventory == null:
		return

	for item in _inventory.get_items():
		_add_item_to_list(item)

func _add_item_to_list(item: ObjectData) -> void:
	_item_list.add_item(item.object_name)
	_list_ids.append(item.object_id)

	if _inventory.is_document(item.object_id):
		document_item_added.emit(item)

func _on_item_added(_item: ObjectData) -> void:
	refresh()

func _on_item_removed(_item: ObjectData) -> void:
	refresh()

func _on_item_list_item_selected(index: int) -> void:
	if index < 0 or index >= _list_ids.size():
		_selected_id = ""
		_button_use.disabled = true
		return

	var item: ObjectData = _inventory.get_item(_list_ids[index])
	if item == null:
		_selected_id = ""
		_button_use.disabled = true
		return

	_selected_id = item.object_id
	_button_use.disabled = false
	_item_name_label.text = item.object_name
	_item_description_label.text = item.description

func _clear_details() -> void:
	_item_name_label.text = ""
	_item_description_label.text = ""
	_selected_id = ""
	_button_use.disabled = true

func _on_button_close_pressed() -> void:
	closed.emit()

func _on_button_use_pressed() -> void:
	if _selected_id.is_empty() or _inventory == null:
		return

	var item: ObjectData = _inventory.get_item(_selected_id)
	if item == null:
		return

	if _inventory.is_document(_selected_id):
		request_open_document(_selected_id)
	else:
		print("[020F] Objeto usado: ", item.object_id)
		item_used.emit(item)

## CORRECCIÓN (auditoría Test_Final_System): antes era un stub vacío, así
## que seleccionar un documento en el inventario y pulsar "Usar" no hacía
## nada -- el flujo Objeto -> Inventario -> Documento se cortaba aquí.
## Ahora localiza el DocumentManager y el DocumentsUI ya existentes (por
## grupo, mismo patrón que el resto del proyecto) y les pide abrir el
## documento, sin mantener ningún estado de lectura propio.
func request_open_document(object_id: String) -> void:
	var document_manager: Node = get_tree().get_first_node_in_group(DOCUMENT_MANAGER_GROUP)
	if document_manager == null or not document_manager.has_method("open_document"):
		return

	if not document_manager.call("open_document", object_id):
		return

	var documents_ui: Node = get_tree().get_first_node_in_group(DOCUMENTS_UI_GROUP)
	if documents_ui == null or not documents_ui.has_method("show_document"):
		return

	var text: String = document_manager.call("get_current_page_text")
	var page: int = document_manager.call("get_current_page_index")
	var doc: DocumentData = document_manager.call("get_current_document")
	var total: int = doc.get_page_count() if doc != null else 1

	documents_ui.call("show_document", doc.title if doc != null else "", text, page + 1, total)
