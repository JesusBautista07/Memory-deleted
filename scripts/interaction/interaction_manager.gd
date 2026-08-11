extends Node3D
class_name InteractionManager

signal target_found(target: Object)
signal target_lost(target: Object)
signal interacted(target: Object)
## Emitida cada vez que cambia lo que el crosshair debe mostrar (ver
## scripts/ui/hud/crosshair.gd). state es uno de los CROSSHAIR_STATE_*
## de más abajo; text es lo que debe mostrar InteractionPrompt (puede ir
## vacío si state es NONE).
signal crosshair_state_changed(state: int, text: String)

## Grupo al que pertenece el nodo de UI que muestra el mensaje de
## interacción (ver scripts/ui/hud/interaction_prompt.gd). Se localiza por
## grupo -en vez de por un NodePath exportado a mano en cada escena- para
## que cualquier escena que contenga un InteractionManager y un
## InteractionPrompt quede conectada automáticamente y sin duplicar
## configuración por escena.
const PROMPT_GROUP := "interaction_prompt"

## Mismo patrón "localizar por grupo" que PROMPT_GROUP, para el Crosshair
## (scripts/ui/hud/crosshair.gd). Así cualquier escena que tenga un
## InteractionManager y un Crosshair queda conectada automáticamente.
const CROSSHAIR_GROUP := "crosshair_hud"

## Límite de niveles que se sube desde el collider detectado por el
## RayCast buscando un método interact() (o take_damage(), para el estado
## de combate del crosshair). Existe porque el nodo físico golpeado por
## el rayo no siempre es el mismo nodo que implementa ese método (p. ej.
## una puerta: el RayCast golpea su StaticBody3D hijo, pero interact()
## vive en el nodo raíz de la puerta). Antes esto se resolvía con scripts
## "puente" añadidos a mano en cada escena; ahora lo resuelve el propio
## InteractionManager de forma genérica.
const MAX_ANCESTOR_SEARCH_DEPTH := 5

## Estados posibles del crosshair. NONE = punto normal (nada detectado).
## INTERACT = hay un interactuable real (interact()) bajo la mira, se
## puede pulsar E. COMBAT = hay un objetivo de combate (take_damage())
## bajo la mira pero SIN interact(); el crosshair cambia de forma igual
## que con un interactuable, pero pulsar E no hace nada (para eso está
## WeaponCombat/fire, no InteractionManager).
const CROSSHAIR_STATE_NONE := 0
const CROSSHAIR_STATE_INTERACT := 1
const CROSSHAIR_STATE_COMBAT := 2

## Texto mostrado en el prompt cuando el objetivo bajo la mira es de
## combate (no tiene interact() propio, ver CROSSHAIR_STATE_COMBAT).
const COMBAT_PROMPT_TEXT := "OBJETIVO"

@export var ray_cast: RayCast3D
@export var interact_action: String = "interact"
## Texto de último recurso, solo para el caso (no esperado en los objetos
## actuales del proyecto) de que un interactuable no implemente
## get_interaction_prompt(). El texto real siempre se pide al propio
## objeto interactuable.
@export var default_prompt_text: String = "[E] Interactuar"

var _current_target: Object = null
## Objetivo de combate bajo la mira (algo con take_damage() pero sin
## interact()), solo para pintar el crosshair/prompt en modo COMBAT.
## Nunca se usa para llamar a interact() -> pulsar E sobre él no hace nada.
var _current_combat_target: Object = null
var _crosshair_state: int = CROSSHAIR_STATE_NONE
var _prompt: Node = null
var _crosshair: Node = null

func _ready() -> void:
	if ray_cast:
		ray_cast.enabled = true
		_exclude_owner_body()
	# CORRECCIÓN (causa raíz original del fallo de interacción): antes
	# _prompt se resolvía aquí mismo, en _ready(). Pero _ready() se
	# propaga por la escena en el orden de los nodos hijos (ver
	# tests/Test_Final_System.tscn), y en esa escena InteractionManager
	# aparece ANTES que HUD/InteractionPrompt. Eso significa que, cuando
	# este _ready() se ejecutaba, InteractionPrompt todavía no había
	# llamado a su propio _ready() ni a add_to_group(), así que
	# get_first_node_in_group(PROMPT_GROUP) siempre devolvía null.
	# _prompt se quedaba null para siempre y show_interaction() salía
	# inmediatamente, así que el mensaje "Presiona E" nunca se imprimía
	# ni se mostraba, sin importar el orden de instanciación de cada
	# escena concreta. Ahora se resuelve de forma perezosa (la primera
	# vez que hace falta, no en _ready()) para no depender de qué nodo
	# se declare antes en el árbol. Lo mismo aplica a _crosshair.
	print("[020E] InteractionManager listo, ray_cast=", ray_cast)
	if ray_cast:
		print("[DEBUG_INTERACTION] RayCast enabled=", ray_cast.enabled,
			" collision_mask=", ray_cast.collision_mask,
			" target=", ray_cast.target_position)

## CORRECCIÓN (causa raíz real de "no puedo interactuar con NINGÚN
## objeto"): RayCast3D.exclude_parent solo excluye a su padre INMEDIATO
## (aquí Camera3D, que no es un cuerpo físico), nunca a antepasados más
## lejanos. Este RayCast está anidado varios niveles dentro del propio
## CharacterBody3D del jugador (Player > CameraPivot > Camera3D >
## RayCast3D, ver tests/Test_Final_System.tscn) y su origen cae DENTRO de
## la CapsuleShape3D de colisión del jugador (Camera3D queda a Y=0.7
## local, bien dentro del rango -0.9/0.9 de esa cápsula). Este proyecto
## usa Jolt Physics (ver project.godot, 3d/physics_engine="Jolt
## Physics"), cuyo RayCast SÍ puede reportar colisión con la forma en la
## que se origina (a diferencia del motor de físicas por defecto de
## Godot, que normalmente no lo hace salvo hit_from_inside=true). El
## resultado real era que el RayCast detectaba SIEMPRE al propio Player
## como primer collider -que no implementa interact() ni take_damage()-
## y, al ser el primer objeto golpeado, el rayo nunca llegaba a ningún
## objeto real del mundo sin importar hacia dónde mirara el jugador. Se
## añade aquí una excepción explícita sobre el cuerpo físico antepasado
## del propio RayCast en vez de tocar collision layers/masks (que
## romperían la detección de objetos legítimos que comparten capa con el
## jugador).
func _exclude_owner_body() -> void:
	var node: Node = ray_cast.get_parent()
	while node != null:
		if node is CollisionObject3D:
			ray_cast.add_exception(node)
			return
		node = node.get_parent()

func _get_prompt() -> Node:
	if _prompt == null:
		_prompt = get_tree().get_first_node_in_group(PROMPT_GROUP)
	return _prompt

func _get_crosshair() -> Node:
	if _crosshair == null:
		_crosshair = get_tree().get_first_node_in_group(CROSSHAIR_GROUP)
	return _crosshair

func _physics_process(_delta: float) -> void:
	_update_target()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(interact_action):
		print("[020E] Se presionó E")
		print("[DEBUG_INTERACTION] E recibida")
		_try_interact()

func _update_target() -> void:
	# CORRECCIÓN (robustez del RayCast): por defecto, RayCast3D actualiza
	# su estado de colisión una vez por frame de físicas, ANTES de que se
	# ejecuten los _physics_process de los scripts, usando la transform
	# que tenía el nodo al momento de esa actualización interna. Si algo
	# mueve la cámara (o el propio RayCast) en el mismo frame -aquí,
	# camera_controller.gd aplica el balanceo de cámara (bob) en su propio
	# _physics_process, que corre antes que este porque Player aparece
	# antes que InteractionManager en el árbol- el resultado de
	# is_colliding() podía quedar un frame por detrás del apuntado real,
	# lo que se percibía como detección "inconsistente" (a veces sí, a
	# veces no, según en qué instante exacto se pulsara E). Forzar la
	# actualización aquí garantiza que is_colliding() siempre refleja la
	# transform actual del RayCast en este mismo frame.
	if ray_cast:
		ray_cast.force_raycast_update()

	var detected: Object = _get_interactable()

	if detected != _current_target:
		if _current_target != null:
			_on_target_lost()
		# _current_target se actualiza ANTES de _on_target_found() para que
		# show_interaction() (que consulta get_current_target()) ya vea el
		# nuevo objetivo y pida el texto correcto al objeto correcto.
		_current_target = detected
		if detected != null:
			_on_target_found(detected)

	_update_crosshair_state()

func _get_interactable() -> Object:
	if ray_cast == null:
		return null

	var colliding := ray_cast.is_colliding()
	print("[DEBUG_INTERACTION] is_colliding=", colliding)

	if not colliding:
		_current_combat_target = null
		return null

	var collider: Object = ray_cast.get_collider()
	print("[DEBUG_INTERACTION] collider=", collider)

	if collider == null:
		_current_combat_target = null
		return null

	if collider is Node:
		print("[020E] RayCast detectó: ", (collider as Node).name)

	var interactable := _find_ancestor_with_method(collider, "interact")
	if interactable != null:
		print("[020E] InteractionManager encontró: ", (interactable as Node).name)
		print("[DEBUG_INTERACTION] interactable encontrado")
		_current_combat_target = null
		return interactable

	# No hay interact() en la cadena de antepasados: comprobar si al menos
	# es un objetivo de combate (take_damage()), para que el crosshair lo
	# marque como OBJETIVO aunque E no haga nada sobre él.
	_current_combat_target = _find_ancestor_with_method(collider, "take_damage")
	return null

## Busca un método concreto en el propio collider y, si no lo tiene, en
## sus antepasados hasta MAX_ANCESTOR_SEARCH_DEPTH niveles.
func _find_ancestor_with_method(collider: Object, method_name: String) -> Object:
	var current := collider as Node
	if current == null:
		return null

	var depth := 0
	while current != null and depth <= MAX_ANCESTOR_SEARCH_DEPTH:
		if current.has_method(method_name):
			return current
		current = current.get_parent()
		depth += 1

	return null

func _on_target_found(target: Object) -> void:
	show_interaction()
	target_found.emit(target)

func _on_target_lost() -> void:
	var target: Object = _current_target
	hide_interaction()
	target_lost.emit(target)

func _try_interact() -> void:
	if _current_target != null and _current_target.has_method("interact"):
		_current_target.call("interact")
		print("[DEBUG_INTERACTION] interact ejecutado")
		interacted.emit(_current_target)

func show_interaction() -> void:
	var prompt := _get_prompt()
	if prompt == null or not prompt.has_method("show_prompt"):
		return

	var text := default_prompt_text
	var target := get_current_target()
	if target != null and target.has_method("get_interaction_prompt"):
		text = target.call("get_interaction_prompt")

	print("[020E] Prompt mostrado: ", text)
	print("[DEBUG_INTERACTION] prompt mostrado")
	prompt.call("show_prompt", text)

func hide_interaction() -> void:
	var prompt := _get_prompt()
	if prompt != null and prompt.has_method("hide_prompt"):
		prompt.call("hide_prompt")

## Calcula el estado actual del crosshair (NONE/INTERACT/COMBAT) a partir
## de _current_target y _current_combat_target, y solo notifica al
## Crosshair (por señal + grupo) cuando ese estado o su texto cambian,
## para no redibujar cada frame sin necesidad.
func _update_crosshair_state() -> void:
	var new_state: int
	var new_text: String

	if _current_target != null:
		new_state = CROSSHAIR_STATE_INTERACT
		new_text = default_prompt_text
		if _current_target.has_method("get_interaction_prompt"):
			new_text = _current_target.call("get_interaction_prompt")
	elif _current_combat_target != null:
		new_state = CROSSHAIR_STATE_COMBAT
		new_text = COMBAT_PROMPT_TEXT
		# El estado COMBAT no pasa por show_interaction() (eso solo ocurre
		# para _current_target, que requiere interact()), así que aquí es
		# donde el prompt "OBJETIVO" se muestra/oculta.
		var prompt := _get_prompt()
		if prompt != null and prompt.has_method("show_prompt"):
			prompt.call("show_prompt", new_text)
	else:
		new_state = CROSSHAIR_STATE_NONE
		new_text = ""

	if new_state == _crosshair_state:
		return

	# Solo se oculta el prompt aquí cuando el estado realmente cambia (no
	# cada frame): _on_target_lost() ya oculta el prompt para el caso
	# INTERACT -> NONE, así que esto cubre específicamente COMBAT -> NONE
	# (el prompt "OBJETIVO" no pasa por _current_target/_on_target_lost).
	if new_state == CROSSHAIR_STATE_NONE:
		hide_interaction()

	_crosshair_state = new_state
	print("[DEBUG_INTERACTION] crosshair actualizado -> estado=", new_state, " texto=", new_text)

	var crosshair := _get_crosshair()
	if crosshair != null and crosshair.has_method("set_state"):
		crosshair.call("set_state", new_state)

	crosshair_state_changed.emit(new_state, new_text)

func get_current_target() -> Object:
	return _current_target

func get_current_combat_target() -> Object:
	return _current_combat_target
