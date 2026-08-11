extends Node3D
## Sistema de cámara FPS: rotación horizontal (aplicada al Player, nodo padre)
## y rotación vertical (Camera3D hijo).
## Responsabilidad única: traducir input de mouse en rotación de cámara,
## y gestionar captura/liberación del cursor.
##
## El yaw se aplica al padre (Player/CharacterBody3D) y no a este nodo,
## para que player_movement.gd (que mueve según su propio transform.basis)
## se mueva en la dirección hacia donde mira la cámara.
##
## CÁMARA EN TERCERA PERSONA (F5): reutiliza este mismo CameraPivot -no se
## crea ningún CameraRig independiente- añadiendo, como hermano de la
## Camera3D de primera persona ya existente, un SpringArm3D
## (ThirdPersonRig) con su propia Camera3D (ThirdPersonCamera). Cambiar de
## modo solo alterna qué Camera3D está "current" y la visibilidad de
## CharacterVisual: no se instancia ni se libera ningún nodo, así que
## pulsar F5 repetidamente no crea cámaras duplicadas. SpringArm3D calcula
## por sí solo la distancia real a la cámara (spring_length) acortándose
## automáticamente si hay una pared o el suelo en medio, así la cámara en
## tercera persona no atraviesa geometría sin tener que implementar ese
## chequeo a mano.
##
## CORRECCIÓN (estilo Resident Evil 4 clásico - cámara cercana, límites
## verticales normales, no se mete en el suelo al mirar hacia abajo):
## la versión anterior rotaba directamente el SpringArm3D (ThirdPersonRig)
## con un pitch INDEPENDIENTE (signo invertido y un límite propio, más
## estrecho, distinto al de primera persona). Eso causaba dos problemas:
## (1) los límites verticales de tercera persona no eran los "normales"
## (no coincidían con los de primera persona), y (2) al mirar hacia abajo,
## el brazo (con longitud 3.5, lejos del jugador) barría un arco amplio
## cuyo extremo caía por debajo del suelo real; SpringArm3D lo detectaba y
## acortaba la longitud casi a cero, dando la sensación de "cámara metida
## en el suelo".
##
## Se corrige con un nodo intermedio dedicado, ThirdPersonPitch (hijo de
## este CameraPivot, hermano de Camera3D), que rota en X con EXACTAMENTE
## el mismo ángulo y el mismo límite que la cámara de primera persona
## (_rotation_x / vertical_limit_degrees): "límites verticales normales".
## ThirdPersonRig (SpringArm3D) cuelga de ese nodo y conserva su rotación
## local fija de 180° en Y (para quedar detrás del jugador) sin rotar por
## sí mismo; solo hereda el pitch del nodo padre. Además:
## - spring_length se acorta a un valor cercano al jugador (estilo RE4
##   clásico, cámara pegada al hombro), en vez de los 3.5 anteriores.
## - se le añade un SphereShape3D pequeño como shape de colisión (en vez
##   de depender solo del rayo por defecto) y un margin mayor, para que
##   las paredes y el suelo bloqueen la cámara de forma robusta incluso en
##   esquinas o ángulos rasantes, sin que la lente atraviese la geometría.
## Con el pitch normal (mismo signo que la cámara: mirar abajo inclina el
## brazo hacia abajo igual que la cabeza), y con el brazo ya corto y con
## colisión robusta, SpringArm3D detiene la cámara justo antes del suelo
## en vez de dejarla hundida dentro de él.
##
## Player/CameraPivot/Camera3D (primera persona) NO se toca ni se mueve:
## WeaponManager/InteractionManager en las escenas de nivel siguen
## apuntando a esa misma ruta sin ningún cambio.
##
## REDISEÑO F5 (estilo Resident Evil 4 clásico, cámara al hombro):
## - Distancia: ThirdPersonRig.spring_length = 2.5 m detrás del jugador
##   (ver Player.tscn). CameraPivot ya está a ~1.6 m de altura (0.7 sobre
##   el centro de la cápsula, que a su vez está ~0.9 m sobre el suelo), así
##   que no hace falta tocar esa altura para cumplir "aprox. 1.6 metros".
## - Offset lateral (+0.45 m al hombro derecho): se aplica como el origin.x
##   de ThirdPersonRig (0.45, 0, 0) en vez de en ThirdPersonPitch, porque al
##   ser hijo de ThirdPersonPitch, ese desplazamiento se expresa en el
##   espacio del padre y una rotación en X (el pitch) no mueve puntos que
##   están sobre el propio eje X: el hombro se mantiene siempre a la
##   derecha del jugador sin importar cuánto se mire arriba/abajo.
## - Límites de pitch propios de tercera persona (+60° arriba / -45° abajo,
##   asimétricos, distintos de los ±vertical_limit_degrees de primera
##   persona): se guardan en third_person_pitch_up_limit_degrees /
##   third_person_pitch_down_limit_degrees y se aplican solo al asignar la
##   rotación a ThirdPersonPitch (ver _rotate_camera), sin tocar el
##   acumulador _rotation_x ni el límite de la cámara en primera persona.

enum CameraMode { FIRST_PERSON, THIRD_PERSON }

@export var mouse_sensitivity: float = 0.15
@export var vertical_limit_degrees: float = 89.0

@export_group("Agacharse (cámara)")
## Cuánto baja la cámara (en el eje Y local del CameraPivot) cuando el
## jugador está agachado. Se resta sobre la altura de pie detectada
## automáticamente en _ready(), así que no depende de un valor fijo.
@export var crouch_camera_offset: float = 0.35
## Velocidad (unidades/segundo) a la que la cámara interpola entre la
## altura de pie y la altura agachada. Valores altos = transición más
## rápida; valores bajos = más suave.
@export var crouch_camera_speed: float = 8.0

## CORRECCIÓN (auditoría Test_Final_System): el checklist funcional pide
## explícitamente comprobar "balanceo de cámara al caminar y correr", pero
## no existía ninguna implementación en todo el proyecto (ni aquí ni en
## ningún otro script). Se añade aquí -no en player_movement.gd, que solo
## gestiona física- por ser, igual que la altura de agachado, una
## corrección puramente visual de la cámara.
@export_group("Balanceo de cámara (bob)")
@export var bob_enabled: bool = true
## Ciclos de balanceo por segundo caminando a walk_speed. run_speed escala
## esto proporcionalmente a la velocidad real, no a un valor fijo distinto.
@export var bob_frequency: float = 1.8
@export var bob_vertical_amount: float = 0.045
@export var bob_horizontal_amount: float = 0.03
## Velocidad a la que el balanceo se apaga al detenerse, para no dejar la
## cámara "saltando" a mitad de ciclo.
@export var bob_fade_speed: float = 6.0

@export_group("Tercera persona (F5)")
## Ruta al modelo visual del jugador (ver Player.tscn: hermano de
## CameraPivot) que se muestra en tercera persona y se oculta en primera
## persona -mismo comportamiento que ya tenía por defecto (visible=false)
## antes de que existiera este toggle-.
@export var character_visual_path: NodePath = NodePath("../CharacterVisual")
## Límite de pitch propio de la cámara en tercera persona (estilo RE4
## clásico), independiente de vertical_limit_degrees (que sigue rigiendo
## solo la cámara en primera persona). No afecta a _rotation_x, que sigue
## acumulando dentro de ±vertical_limit_degrees; solo recorta el valor que
## se aplica a ThirdPersonPitch.
@export var third_person_pitch_up_limit_degrees: float = 60.0
@export var third_person_pitch_down_limit_degrees: float = 45.0

@onready var camera: Camera3D = $Camera3D
@onready var _third_person_pitch: Node3D = $ThirdPersonPitch
@onready var _third_person_rig: SpringArm3D = $ThirdPersonPitch/ThirdPersonRig
@onready var _third_person_camera: Camera3D = $ThirdPersonPitch/ThirdPersonRig/ThirdPersonCamera
@onready var _character_visual: Node3D = get_node_or_null(character_visual_path) as Node3D
@onready var _yaw_target: Node3D = get_parent()
## Referencia tipada al PlayerMovement (script del nodo padre), para poder
## leer su estado is_crouching sin duplicar esa lógica aquí.
@onready var _player_movement: PlayerMovement = get_parent() as PlayerMovement

var _rotation_x: float = 0.0  # acumulador de rotación vertical, en grados
var _camera_mode: CameraMode = CameraMode.FIRST_PERSON

## Altura local (eje Y) del propio CameraPivot cuando el jugador está de
## pie. Se captura en _ready() a partir de la posición ya configurada en la
## escena (Player.tscn), así que cambiar esa posición en el Inspector sigue
## funcionando sin tocar código.
var _standing_camera_y: float = 0.0

## Posición local base de Camera3D (normalmente Vector3.ZERO). El bob se
## aplica como desplazamiento sobre esta base, nunca sobre CameraPivot
## (que ya lo usa el ajuste de agachado) para que ambos efectos convivan
## sin pisarse.
var _camera_base_position: Vector3 = Vector3.ZERO
var _bob_time: float = 0.0
var _bob_strength: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_standing_camera_y = position.y
	_camera_base_position = camera.position
	_exclude_player_from_third_person_collision()
	_apply_camera_mode()

## CORRECCIÓN (tercera persona "se mete por el suelo" / no se ve el
## personaje): ThirdPersonRig (SpringArm3D) es descendiente de CameraPivot,
## que está a la altura del pecho/cabeza DENTRO de la propia
## CapsuleShape3D del Player (ver Player.tscn: radius 0.4). Sin excluir esa
## cápsula, SpringArm3D choca contra el propio cuerpo del jugador nada más
## empezar su comprobación de colisión (ambos en la capa física 1 por
## defecto) y se acorta casi a cero en todo momento, dejando la cámara
## prácticamente pegada al pivote -dentro del propio personaje/junto al
## suelo- en vez de a spring_length. Se excluye aquí, en código
## (SpringArm3D no expone esto en el Inspector), igual que
## FootIKController ya excluye este mismo CharacterBody3D de sus
## RayCast3D (ver body_to_exclude en foot_ik_controller.gd) para no
## detectarse a sí mismo como suelo.
func _exclude_player_from_third_person_collision() -> void:
	var player_body := get_parent()
	if player_body is CollisionObject3D:
		_third_person_rig.add_excluded_object((player_body as CollisionObject3D).get_rid())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative)

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("toggle_camera_mode"):
		print("[CAMERA TEST] F5 RECIBIDO")
		print("[CAMERA TEST] ThirdPersonCamera encontrada: ", is_instance_valid(_third_person_camera))
		_toggle_camera_mode()
		get_viewport().set_input_as_handled()

## CORRECCIÓN TICKET 020E: antes la cápsula de colisión bajaba al agacharse
## (player_movement.gd) pero la cámara se quedaba fija en su altura de pie.
## Se sincroniza aquí, en _physics_process (mismo tick que
## PlayerMovement._physics_process, donde se decide is_crouching), moviendo
## solo la altura local del CameraPivot con un move_toward suave -no un
## salto instantáneo- tanto al agacharse como al levantarse. Al ser un
## ajuste sobre este mismo nodo (CameraPivot), afecta por igual a la
## Camera3D de primera persona y a ThirdPersonPitch/ThirdPersonRig (ambos
## descendientes suyos), así que la cámara en tercera persona también baja
## cuando el jugador se agacha, sin código adicional.
func _physics_process(delta: float) -> void:
	_update_crouch_camera(delta)
	_update_camera_bob(delta)

func _update_crouch_camera(delta: float) -> void:
	if _player_movement == null:
		return

	var target_y := _standing_camera_y
	if _player_movement.is_crouching:
		target_y -= crouch_camera_offset

	position.y = move_toward(position.y, target_y, crouch_camera_speed * delta)

func _update_camera_bob(delta: float) -> void:
	if not bob_enabled or _player_movement == null:
		camera.position = _camera_base_position
		return

	var horizontal_speed := Vector2(_player_movement.velocity.x, _player_movement.velocity.z).length()
	var is_moving := horizontal_speed > 0.1 and _player_movement.is_on_floor()

	# La intensidad del balanceo escala con la velocidad real (caminar,
	# correr o agachado-lento producen un bob distinto sin tener que leer
	# qué acción está pulsada, solo la velocidad resultante).
	var target_strength := clampf(horizontal_speed / _player_movement.walk_speed, 0.0, 2.0) if is_moving else 0.0
	_bob_strength = move_toward(_bob_strength, target_strength, bob_fade_speed * delta)

	if _bob_strength <= 0.001:
		_bob_time = 0.0
		camera.position = _camera_base_position
		return

	_bob_time += delta * bob_frequency * (1.0 + _bob_strength)

	var vertical_offset := sin(_bob_time * TAU) * bob_vertical_amount * _bob_strength
	# El eje horizontal va al doble de frecuencia (patrón en "8" clásico de
	# head-bob: un paso por pie, dos por ciclo vertical completo).
	var horizontal_offset := cos(_bob_time * TAU * 0.5) * bob_horizontal_amount * _bob_strength

	camera.position = _camera_base_position + Vector3(horizontal_offset, vertical_offset, 0.0)

func _rotate_camera(mouse_delta: Vector2) -> void:
	# Rotación horizontal: rota al Player (padre) en Y, no a este nodo,
	# para que el movimiento WASD siga la orientación de la cámara. Al
	# rotar el Player, tanto Camera3D como ThirdPersonPitch (ambos hijos de
	# este CameraPivot) heredan el mismo giro, así que la cámara en
	# tercera persona también acompaña el giro del jugador sin lógica
	# adicional.
	_yaw_target.rotate_y(-mouse_delta.x * mouse_sensitivity * 0.01)

	# Rotación vertical: un único acumulador (_rotation_x), recortado con el
	# límite de primera persona (vertical_limit_degrees, ±89° por defecto)
	# y aplicado directamente a la Camera3D de primera persona.
	_rotation_x -= mouse_delta.y * mouse_sensitivity
	_rotation_x = clamp(_rotation_x, -vertical_limit_degrees, vertical_limit_degrees)
	camera.rotation_degrees.x = _rotation_x

	# ThirdPersonPitch usa el mismo acumulador pero con su propio recorte
	# (+60° arriba / -45° abajo, estilo RE4 clásico), distinto e
	# independiente del límite de primera persona: así la cámara al hombro
	# respeta sus propios topes sin alterar en nada la cámara en primera
	# persona ni su rango de mirada.
	_third_person_pitch.rotation_degrees.x = clamp(
		_rotation_x, -third_person_pitch_down_limit_degrees, third_person_pitch_up_limit_degrees
	)

# ---------------------------------------------------------------------------
# TERCERA PERSONA (F5)
# ---------------------------------------------------------------------------

func _toggle_camera_mode() -> void:
	if _camera_mode == CameraMode.FIRST_PERSON:
		_camera_mode = CameraMode.THIRD_PERSON
	else:
		_camera_mode = CameraMode.FIRST_PERSON
	_apply_camera_mode()

## Solo cambia qué Camera3D está activa y si CharacterVisual es visible;
## no instancia ni libera ningún nodo, así que alternar F5 repetidamente
## no crea cámaras duplicadas ni nodos nuevos.
func _apply_camera_mode() -> void:
	var is_third_person := _camera_mode == CameraMode.THIRD_PERSON

	camera.current = not is_third_person
	_third_person_camera.current = is_third_person
	print("[CAMERA TEST] Tercera persona: ", is_third_person)
	print("[CAMERA TEST] Camera3D.current: ", camera.current)
	print("[CAMERA TEST] ThirdPersonCamera.current: ", _third_person_camera.current)

	if _character_visual != null:
		_character_visual.visible = is_third_person
	else:
		push_warning("CameraController: no se encontró CharacterVisual en '%s'; el cuerpo no se mostrará en tercera persona." % str(character_visual_path))
