extends Interactable
class_name PickupObject

signal picked_up(object_data: ObjectData, source: PickupObject)
signal storage_rejected(object_data: ObjectData, source: PickupObject)
signal sent_to_inventory(object_data: ObjectData, source: PickupObject, accepted: bool)

const INVENTORY_GROUP := "inventory"

@export var object_data: ObjectData
@export var disable_on_pickup: bool = true
@export var visual_root: Node3D

var _picked_up: bool = false

func interact() -> void:
	if not can_interact or _picked_up:
		return

	if object_data == null:
		return

	print("[020E] PickupObject.interact() -> ", object_data.object_id)

	if not object_data.can_be_stored:
		storage_rejected.emit(object_data, self)
		return

	_picked_up = true
	picked_up.emit(object_data, self)
	_send_to_inventory()
	super.interact()

	if disable_on_pickup:
		deactivate()

func deactivate() -> void:
	set_interactable(false)
	if visual_root != null:
		visual_root.visible = false
	else:
		set("visible", false)

	# Además de ocultarlo, se desactiva su colisión: sin esto el objeto
	# seguía siendo sólido y detectable por el RayCast de interacción
	# aunque ya estuviera invisible y guardado en el inventario.
	# Se usa is_instance_of()/set() en vez de "is"/"as" porque PickupObject
	# hereda de Node (vía Interactable), no de CollisionObject3D: el
	# comprobador estático de tipos no puede relacionarlos, aunque en
	# runtime el nodo real (StaticBody3D, etc.) sí lo sea.
	if is_instance_of(self, CollisionObject3D):
		set("collision_layer", 0)
		set("collision_mask", 0)

func is_picked_up() -> bool:
	return _picked_up

func get_object_data() -> ObjectData:
	return object_data

func get_object_id() -> String:
	if object_data == null:
		return ""
	return object_data.object_id

func is_key_item() -> bool:
	if object_data == null:
		return false
	return object_data.is_key_item

func _send_to_inventory() -> void:
	var inventory: Node = get_tree().get_first_node_in_group(INVENTORY_GROUP)

	if inventory == null or not inventory.has_method("add_item"):
		print("[020E] Objeto enviado al inventario -> SIN Inventory en la escena, rechazado")
		sent_to_inventory.emit(object_data, self, false)
		return

	var accepted: bool = inventory.call("add_item", object_data, self)
	print("[020E] Objeto enviado al inventario: ", object_data.object_id, " aceptado=", accepted)
	sent_to_inventory.emit(object_data, self, accepted)
