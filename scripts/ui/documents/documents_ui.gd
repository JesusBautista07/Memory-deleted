extends Control
## Interfaz de lectura de documentos. Sin lógica de documentos:
## solo muestra los datos que le pasen por código.

signal closed

## Grupo por el que InventoryUI localiza este nodo (ver
## scripts/ui/inventory/inventory_ui.gd -> request_open_document()), mismo
## patrón de "localizar por grupo" que usa el resto del proyecto.
const GROUP_NAME := "documents_ui"
const DOCUMENT_MANAGER_GROUP := "document_manager"

@onready var _title_label: Label = %TitleLabel
@onready var _content_label: RichTextLabel = %ContentLabel
@onready var _page_label: Label = %PageLabel
@onready var _button_close: Button = %ButtonClose


func _ready() -> void:
	add_to_group(GROUP_NAME)

	# CORRECCIÓN (auditoría Test_Final_System): DocumentsUI solo se abre
	# desde InventoryUI, que vive bajo PauseMenu (PROCESS_MODE_ALWAYS) y
	# solo es visible con el árbol en pausa. DocumentsUI en cambio cuelga
	# de HUD, que hereda el modo de proceso normal (se pausa con el resto
	# del juego) -- sin este ajuste, el botón "Cerrar" quedaba congelado
	# en cuanto se abría un documento, porque nunca podía recibir input
	# mientras get_tree().paused es true.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_button_close.pressed.connect(_on_close_pressed)
	visible = false


func show_document(title: String, content: String, page: int = 1, total_pages: int = 1) -> void:
	_title_label.text = title
	_content_label.text = content
	_page_label.text = "Página %d/%d" % [page, total_pages]
	visible = true


func hide_document() -> void:
	visible = false


func _on_close_pressed() -> void:
	hide_document()
	closed.emit()

	# CORRECCIÓN (auditoría Test_Final_System): cerrar la UI no avisaba al
	# DocumentManager, que se quedaba creyendo el documento seguía abierto
	# (get_current_document() no devolvía null). Se le notifica aquí por
	# grupo, sin que DocumentsUI necesite guardar su propio estado.
	var document_manager: Node = get_tree().get_first_node_in_group(DOCUMENT_MANAGER_GROUP)
	if document_manager != null and document_manager.has_method("close_document"):
		document_manager.call("close_document")
