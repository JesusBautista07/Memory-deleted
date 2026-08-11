extends CharacterBody3D
class_name PlayerMovement
## Sistema de movimiento del jugador en primera persona.
## Responsable ÚNICAMENTE de: input WASD, caminar/correr, agacharse,
## salto, gravedad, colisiones, movimiento en pendientes, subida de
## escalones pequeños y reinicio por caída.
## No gestiona cámara, mouse-look, inventario ni interacción.

# ---------------------------------------------------------------------------
# CONFIGURACIÓN EXPORTADA (ajustable desde el Inspector, sin tocar código)
# ---------------------------------------------------------------------------

@export_group("Velocidades")
@export var walk_speed: float = 4.0
@export var run_speed: float = 7.0
@export var crouch_speed: float = 2.0
@export var acceleration: float = 10.0   # suavizado de aceleración/frenado

@export_group("Salto y Gravedad")
@export var jump_velocity: float = 4.5
## Multiplicador de gravedad mientras el jugador SUBE (tras saltar).
## >1.0 controla el salto sin quitarle toda la altura.
@export var gravity_multiplier: float = 1.3
## Multiplicador de gravedad mientras el jugador CAE. Debe ser mayor que
## el de subida: es lo que da la sensación de "peso" y evita la flotación.
@export var fall_gravity_multiplier: float = 3.0
## Velocidad máxima de caída (positivo). Evita que a alta velocidad el
## jugador atraviese el suelo en un solo frame (tunneling).
@export var max_fall_speed: float = 22.0

@export_group("Agacharse (Ctrl)")
@export var can_crouch: bool = true
@export var crouch_height_scale: float = 0.5   # % de la altura original de la cápsula

@export_group("Pendientes")
@export var floor_max_angle_deg: float = 46.0   # ángulo máximo caminable

@export_group("Escalones (subida automática)")
## Alto máximo de escalón que el jugador sube caminando, sin saltar.
## Calibrado sobre los escalones de PlayableDemo.tscn (0.27 m).
@export var step_height: float = 0.32
## Distancia hacia delante que se comprueba para detectar un escalón.
@export var step_check_distance: float = 0.4

@export_group("Reinicio automático por caída")
@export var enable_fall_reset: bool = true
@export var fall_reset_y: float = -30.0

# ---------------------------------------------------------------------------
# ESTADO INTERNO
# ---------------------------------------------------------------------------

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_crouching: bool = false
var respawn_position: Vector3 = Vector3.ZERO

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _original_capsule_height: float = 0.0
var _original_capsule_pos_y: float = 0.0


# ---------------------------------------------------------------------------
# CICLO DE VIDA
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Guarda la posición inicial como punto de reinicio si el jugador cae del mapa.
	respawn_position = global_position

	# Traduce el ángulo máximo de pendiente (definido en grados por comodidad) a radianes,
	# que es lo que espera CharacterBody3D.
	floor_max_angle = deg_to_rad(floor_max_angle_deg)

	# --- Ajustes de CharacterBody3D para pendientes/escaleras estables ---
	# floor_snap_length: "pega" al jugador al suelo cuando baja pequeños
	# desniveles (bordes de escalón, irregularidades de la rampa) en vez
	# de dejarlo caer en caída libre en cada uno. Sin esto el jugador
	# "rebota" ligeramente al bajar escaleras.
	floor_snap_length = step_height + 0.05
	# Evita que el jugador se deslice solo por estar de pie en la rampa.
	floor_stop_on_slope = true
	# Mantiene la velocidad horizontal constante al subir/bajar pendientes,
	# en vez de perder velocidad artificialmente (lo que se sentía "raro").
	floor_constant_speed = true
	# No hay razón para considerar suelo lo que en realidad es una pared.
	floor_block_on_wall = true
	# Margen de seguridad un poco mayor al de por defecto: reduce las
	# micro-vibraciones contra escalones/paredes sin introducir huecos
	# perceptibles.
	safe_margin = 0.01

	# Guarda las medidas originales de la cápsula de colisión para poder
	# restaurarlas correctamente al dejar de agacharse.
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		_original_capsule_height = capsule.height
		_original_capsule_pos_y = collision_shape.position.y
	elif can_crouch:
		push_warning("PlayerMovement: se esperaba un CapsuleShape3D en CollisionShape3D para agacharse correctamente.")


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_crouch_input()
	_handle_jump_input()
	_handle_horizontal_movement(delta)

	# Antes de resolver el movimiento, comprueba si hay un escalón bajo
	# delante y, si lo hay, "teletransporta" verticalmente al jugador por
	# encima de él. move_and_slide() se encarga después de la parte
	# horizontal y de volver a asentarlo en el suelo (floor_snap_length).
	_try_step_up()

	# move_and_slide() ya gestiona colisiones y, junto con floor_max_angle,
	# el deslizamiento correcto sobre pendientes caminables.
	move_and_slide()

	_check_fall_reset()


# ---------------------------------------------------------------------------
# GRAVEDAD
# ---------------------------------------------------------------------------
# Se usan dos multiplicadores distintos según el jugador esté subiendo o
# bajando: una caída más pesada que la subida es lo que da la sensación de
# "peso" real y evita la sensación de flotar tras el salto (técnica estándar
# de "fall multiplier"). Además se limita la velocidad máxima de caída para
# que a alta velocidad no llegue a atravesar el suelo en un solo frame.

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return

	var effective_gravity := gravity * (gravity_multiplier if velocity.y > 0.0 else fall_gravity_multiplier)
	velocity.y -= effective_gravity * delta
	velocity.y = max(velocity.y, -max_fall_speed)


# ---------------------------------------------------------------------------
# SALTO
# ---------------------------------------------------------------------------

func _handle_jump_input() -> void:
	# No se permite saltar estando agachado (comportamiento típico de terror/exploración).
	if is_on_floor() and not is_crouching and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity


# ---------------------------------------------------------------------------
# AGACHARSE (Ctrl) — funcional y preparado para ampliarse (ej. sigilo)
# ---------------------------------------------------------------------------

func _handle_crouch_input() -> void:
	if not can_crouch:
		return

	var wants_crouch := Input.is_action_pressed("crouch")

	if wants_crouch and not is_crouching:
		is_crouching = true
		_resize_collision_shape(true)
	elif not wants_crouch and is_crouching:
		is_crouching = false
		_resize_collision_shape(false)


func _resize_collision_shape(crouching: bool) -> void:
	if collision_shape == null or not (collision_shape.shape is CapsuleShape3D):
		return

	var capsule := collision_shape.shape as CapsuleShape3D

	if crouching:
		capsule.height = _original_capsule_height * crouch_height_scale
	else:
		capsule.height = _original_capsule_height

	# Reposiciona la cápsula para que "crezca hacia abajo" (los pies no flotan).
	collision_shape.position.y = _original_capsule_pos_y - (_original_capsule_height - capsule.height) / 2.0


# ---------------------------------------------------------------------------
# MOVIMIENTO HORIZONTAL (WASD, caminar/correr, pendientes)
# ---------------------------------------------------------------------------

func _handle_horizontal_movement(delta: float) -> void:
	var target_speed := walk_speed
	if is_crouching:
		target_speed = crouch_speed
	elif Input.is_action_pressed("sprint"):
		target_speed = run_speed

	# Vector de input normalizado en el plano XZ.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# La dirección se calcula respecto a la orientación (yaw) del propio CharacterBody3D.
	# Esto asume que el giro horizontal del jugador (mouse-look) se aplica a este mismo
	# nodo desde el sistema de cámara, que queda fuera de este script.
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var target_velocity_x := direction.x * target_speed
	var target_velocity_z := direction.z * target_speed

	# Suaviza la aceleración/frenado en vez de aplicar velocidad instantánea:
	# se siente más natural y evita "teletransportes" de velocidad.
	velocity.x = move_toward(velocity.x, target_velocity_x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity_z, acceleration * delta)


# ---------------------------------------------------------------------------
# SUBIDA AUTOMÁTICA DE ESCALONES PEQUEÑOS (subir escaleras caminando)
# ---------------------------------------------------------------------------
# CharacterBody3D no sube por sí solo un escalón vertical (no es una
# pendiente, así que floor_max_angle no aplica). La técnica estándar es:
# 1) Comprobar, sin mover realmente al cuerpo, si el movimiento horizontal
#    previsto para este frame chocaría con algo.
# 2) Si choca, repetir la misma comprobación pero partiendo de una posición
#    "step_height" más arriba.
# 3) Si desde ahí el camino queda libre, es un escalón bajo: se sube al
#    jugador esa altura y move_and_slide() + floor_snap_length hacen el
#    resto (avanzar y volver a asentarlo en el nuevo nivel).
# Si el camino sigue bloqueado incluso más arriba, es una pared real y no
# se hace nada (así no se "escala" ni se atraviesan muros).

func _try_step_up() -> void:
	if not is_on_floor() or is_crouching:
		return

	# No interferir con el salto: solo aplica a movimiento a ras de suelo.
	if velocity.y > 0.0:
		return

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length() < 0.1:
		return

	var motion := horizontal_velocity.normalized() * step_check_distance

	var params := PhysicsTestMotionParameters3D.new()
	params.from = global_transform
	params.motion = motion
	params.margin = safe_margin

	var result := PhysicsTestMotionResult3D.new()
	var blocked_at_feet := PhysicsServer3D.body_test_motion(get_rid(), params, result)

	if not blocked_at_feet:
		return  # No hay obstáculo delante: no es necesario subir nada.

	# Repite la comprobación como si el jugador ya estuviera "step_height"
	# más arriba, para distinguir un escalón bajo de una pared real.
	var raised_transform := global_transform
	raised_transform.origin.y += step_height
	params.from = raised_transform

	var result_raised := PhysicsTestMotionResult3D.new()
	var blocked_above := PhysicsServer3D.body_test_motion(get_rid(), params, result_raised)

	if not blocked_above:
		global_position.y += step_height


# ---------------------------------------------------------------------------
# REINICIO AUTOMÁTICO SI EL JUGADOR CAE FUERA DEL MAPA
# ---------------------------------------------------------------------------

func _check_fall_reset() -> void:
	if enable_fall_reset and global_position.y < fall_reset_y:
		print("[020E] Respawn ejecutado")
		velocity = Vector3.ZERO
		global_position = respawn_position
