class_name FootIKController
extends SkeletonModifier3D
## PRIMERA VERSIÓN de locomoción procedural / Foot IK.
##
## Responsabilidad ÚNICA: partiendo de la animación de esqueleto ya
## reproducida por el AnimationPlayer existente (Idle_Loop, Walk_Loop,
## Sprint_Loop, y cualquier otra que use el mismo Skeleton3D, incluidas
## Crouch/Jump si en el futuro tienen su propio clip) ajustar en tiempo
## real la posición y orientación de CADA PIE para que se apoyen sobre el
## terreno real detectado con RayCast3D, en vez de sobre el suelo plano
## que asume la animación original. No sustituye ninguna animación, no
## reproduce clips distintos y no toca cámara, movimiento WASD ni
## retargeting: solo lee la pose ya calculada y la corrige un poco antes
## de que se dibuje este frame.
##
## CÓMO SE ENGANCHA (requisito de SkeletonModifier3D en Godot 4.3+):
## Este nodo debe añadirse como HIJO DIRECTO de un Skeleton3D; así es
## como Godot localiza qué hueso modificar, y GARANTIZA que esto se
## ejecuta DESPUÉS de que AnimationMixer haya aplicado Idle/Walk/Sprint/
## etc. y ANTES de que esa pose se use para el render de este frame (ver
## https://godotengine.org/article/design-of-the-skeleton-modifier-3d/).
## No se instala aquí, en la escena: ver character_variant.gd, que lo
## localiza e instala en tiempo de ejecución por TIPO de nodo (Skeleton3D),
## no por una ruta fija, precisamente porque el nombre exacto que Godot
## le da al Skeleton3D generado al importar el .gltf del jugador no se
## puede confirmar sin abrir el proyecto en el editor (ver notas de la
## entrega).
##
## HUESOS: los nombres por defecto de más abajo son los reales,
## verificados directamente en el glTF fuente del jugador actual
## (Superhero_Male_FullBody.gltf -> thigh_l/calf_l/foot_l/ball_l y su
## espejo _r). NO son un supuesto: se leyeron del archivo. Si este mismo
## componente se reutiliza en otro Skeleton3D con otros nombres de hueso
## (por ejemplo el rig PSX/Mixamo de los NPC, que usa nombres tipo
## "mixamorig:LeftUpLeg" - visto en el .fbx fuente pero SIN confirmar
## cómo los renombra el importador FBX de Godot), basta con cambiar los
## @export de más abajo en el Inspector: si un nombre no existe en el
## Skeleton3D de destino, esa pierna se desactiva sola (con un aviso en
## consola) en vez de deformar el modelo o fallar en silencio.
##
## LIMITACIONES CONOCIDAS DE ESTA PRIMERA VERSIÓN (deliberadas, para no
## ampliar el alcance más allá de lo pedido):
## - No hay ajuste de altura de cadera/pelvis: en un escalón muy alto la
##   pierna se estira hasta max_leg_stretch y se detiene ahí (límite
##   articular), no "agacha" el cuerpo entero. Es el siguiente paso
##   natural, pero toca la cadena de columna y se ha dejado fuera a
##   propósito de este primer commit.
## - No hay roll de la punta del pie (toe roll): el pie se inclina como
##   un bloque rígido según la normal del suelo bajo el tobillo, no
##   bisagra por separado en la puntera.
## - No se ha probado en el editor (ver notas de la entrega): la lógica
##   está escrita contra la documentación oficial de SkeletonModifier3D
##   y RayCast3D de Godot 4.5, pero no ha corrido en un Godot real.

@export_group("Huesos - pierna izquierda")
@export var left_thigh_bone: String = "thigh_l"
@export var left_calf_bone: String = "calf_l"
@export var left_foot_bone: String = "foot_l"
## Hueso de la punta del pie. Opcional: solo se usa como referencia
## adicional; si no existe, el pie se sigue colocando correctamente.
@export var left_toe_bone: String = "ball_l"

@export_group("Huesos - pierna derecha")
@export var right_thigh_bone: String = "thigh_r"
@export var right_calf_bone: String = "calf_r"
@export var right_foot_bone: String = "foot_r"
@export var right_toe_bone: String = "ball_r"

@export_group("Detección de suelo (RayCast3D)")
## Distancia hacia abajo que busca cada rayo, medida desde
## ray_start_up_offset por encima del pie animado. Debe cubrir el
## escalón más alto que el jugador puede subir caminando (ver
## PlayerMovement.step_height = 0.32) más un margen para pendientes.
@export var ray_length_down: float = 0.6
## Cuánto por encima de la posición animada del pie empieza el rayo, para
## poder detectar también un escalón que SUBE respecto a la animación
## (no solo bajadas/pendientes hacia abajo).
@export var ray_start_up_offset: float = 0.35
## Máscara de colisión de los rayos. Por defecto la capa 1, que es la
## que usan el suelo/rampas/escalones de scenes/levels/PlayableDemo.tscn
## (no declaran collision_layer propio, así que heredan la capa 1 por
## defecto de Godot).
@export_flags_3d_physics var collision_mask: int = 1
## Cuerpo físico del propio personaje (el CharacterBody3D), para
## excluirlo de los rayos y que no se detecte a sí mismo como "suelo".
## character_variant.gd lo asigna automáticamente a partir de
## movement_node_path.
@export var body_to_exclude: NodePath

@export_group("Ajuste del pie")
## Separación vertical entre la suela del pie y el punto donde impacta
## el rayo (grosor aproximado del calzado).
@export var foot_ground_offset: float = 0.03
## Velocidad de suavizado (unidades/seg) de la altura del pie hacia el
## nuevo objetivo. Evita saltos bruscos al cruzar el borde de una rampa
## o escalón.
@export var position_smoothing_speed: float = 12.0
## Velocidad de suavizado (interpolación esférica por segundo) de la
## inclinación del pie.
@export var rotation_smoothing_speed: float = 10.0
## Inclinación máxima del pie respecto a la que ya trae la animación,
## en grados. Límite articular del tobillo: evita una deformación
## antinatural en pendientes muy pronunciadas o irregulares.
@export_range(0.0, 89.0, 1.0) var max_foot_tilt_deg: float = 45.0

@export_group("Límites articulares de la rodilla")
## % máximo de la longitud total de la pierna (muslo + pantorrilla) que
## se permite estirar. Por debajo de 1.0 para que la rodilla nunca
## llegue a quedar completamente recta/bloqueada al alcanzar el
## objetivo, que es lo que produce el típico "temblor" de IK barato.
@export_range(0.5, 1.0, 0.01) var max_leg_stretch: float = 0.98
## % mínimo de la longitud total de la pierna permitido al doblar la
## rodilla, para que no se pliegue de forma extrema si el suelo
## detectado está muy cerca de la cadera (p. ej. agachado, Crouch).
@export_range(0.0, 0.5, 0.01) var min_leg_extension: float = 0.08

@export_group("General")
@export var enabled: bool = true

var _left_ray: RayCast3D
var _right_ray: RayCast3D

var _left_thigh_idx := -1
var _left_calf_idx := -1
var _left_foot_idx := -1
var _left_toe_idx := -1
var _right_thigh_idx := -1
var _right_calf_idx := -1
var _right_foot_idx := -1
var _right_toe_idx := -1

# Estado suavizado por pierna (persiste entre frames para el lerp/slerp).
var _left_height_offset := 0.0
var _right_height_offset := 0.0
var _left_tilt := Quaternion.IDENTITY
var _right_tilt := Quaternion.IDENTITY

# _process_modification() lo llama Skeleton3D, no el bucle _process()
# normal de este nodo, así que get_process_delta_time() no está
# garantizado que refleje el frame real aquí; se mide a mano con Time.
var _last_update_usec: int = 0


func _ready() -> void:
	_left_ray = _make_ray()
	_right_ray = _make_ray()
	add_child(_left_ray)
	add_child(_right_ray)

	var exclude_body := get_node_or_null(body_to_exclude)
	if exclude_body is CollisionObject3D:
		_left_ray.add_exception(exclude_body as CollisionObject3D)
		_right_ray.add_exception(exclude_body as CollisionObject3D)

	_resolve_bones()


func _make_ray() -> RayCast3D:
	var ray := RayCast3D.new()
	ray.enabled = true
	ray.collision_mask = collision_mask
	ray.target_position = Vector3(0.0, -(ray_length_down + ray_start_up_offset), 0.0)
	return ray


func _resolve_bones() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		push_warning("FootIKController: no se encontró un Skeleton3D padre. Este nodo debe añadirse como hijo directo de un Skeleton3D; ver character_variant.gd -> _setup_foot_ik().")
		return

	_left_thigh_idx = skeleton.find_bone(left_thigh_bone)
	_left_calf_idx = skeleton.find_bone(left_calf_bone)
	_left_foot_idx = skeleton.find_bone(left_foot_bone)
	_left_toe_idx = skeleton.find_bone(left_toe_bone)

	_right_thigh_idx = skeleton.find_bone(right_thigh_bone)
	_right_calf_idx = skeleton.find_bone(right_calf_bone)
	_right_foot_idx = skeleton.find_bone(right_foot_bone)
	_right_toe_idx = skeleton.find_bone(right_toe_bone)

	if _left_thigh_idx == -1 or _left_calf_idx == -1 or _left_foot_idx == -1:
		push_warning("FootIKController (%s): no se encontraron los huesos de la pierna izquierda ('%s'/'%s'/'%s') en '%s'. Foot IK deshabilitado para esa pierna, sin forzar nada." % [get_path(), left_thigh_bone, left_calf_bone, left_foot_bone, skeleton.name])
	if _right_thigh_idx == -1 or _right_calf_idx == -1 or _right_foot_idx == -1:
		push_warning("FootIKController (%s): no se encontraron los huesos de la pierna derecha ('%s'/'%s'/'%s') en '%s'. Foot IK deshabilitado para esa pierna, sin forzar nada." % [get_path(), right_thigh_bone, right_calf_bone, right_foot_bone, skeleton.name])


func _process_modification() -> void:
	if not enabled:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	var now_usec := Time.get_ticks_usec()
	var delta := 1.0 / 60.0
	if _last_update_usec > 0:
		delta = clamp(float(now_usec - _last_update_usec) / 1_000_000.0, 0.0001, 0.25)
	_last_update_usec = now_usec

	_update_leg(skeleton, _left_thigh_idx, _left_calf_idx, _left_foot_idx, _left_ray, delta, true)
	_update_leg(skeleton, _right_thigh_idx, _right_calf_idx, _right_foot_idx, _right_ray, delta, false)


func _update_leg(skeleton: Skeleton3D, thigh_idx: int, calf_idx: int, foot_idx: int, ray: RayCast3D, delta: float, is_left: bool) -> void:
	if thigh_idx == -1 or calf_idx == -1 or foot_idx == -1:
		return

	# Pose ANIMADA de este frame (antes de que este script toque nada):
	# la que ya calcularon Idle/Walk/Sprint/Crouch/Jump vía AnimationPlayer.
	var hip_pose := skeleton.get_bone_global_pose(thigh_idx)
	var knee_pose := skeleton.get_bone_global_pose(calf_idx)
	var foot_pose := skeleton.get_bone_global_pose(foot_idx)
	var foot_pos_world := skeleton.global_transform * foot_pose.origin

	# --- 1. Detección de suelo con RayCast3D ---
	ray.global_position = foot_pos_world + Vector3(0.0, ray_start_up_offset, 0.0)
	ray.force_raycast_update()

	var hit := ray.is_colliding()
	var target_offset := 0.0
	var tilt := Quaternion.IDENTITY

	if hit:
		var hit_point := ray.get_collision_point()
		var hit_normal := ray.get_collision_normal()
		target_offset = (hit_point.y + foot_ground_offset) - foot_pos_world.y

		if abs(target_offset) > ray_length_down:
			# Desnivel mayor de lo que este primer sistema está pensado
			# para cubrir (borde/precipicio): se ignora, se deja el pie
			# tal y como lo dejó la animación en vez de forzar un
			# estiramiento irreal.
			hit = false
		else:
			var basis_inv := skeleton.global_transform.basis.inverse()
			var local_up := (basis_inv * Vector3.UP).normalized()
			var local_normal := (basis_inv * hit_normal).normalized()

			var max_tilt := deg_to_rad(max_foot_tilt_deg)
			var angle := local_up.angle_to(local_normal)
			if angle > max_tilt and angle > 0.0001:
				# Límite articular del tobillo: no inclinar más de
				# max_foot_tilt_deg aunque el suelo real sea más
				# vertical que eso.
				local_normal = local_up.slerp(local_normal, max_tilt / angle)
			tilt = Quaternion(local_up, local_normal)

	# --- 2. Suavizado por pierna (independiente izquierda/derecha) ---
	var height_offset: float
	var foot_tilt: Quaternion
	if is_left:
		_left_height_offset = move_toward(_left_height_offset, target_offset if hit else 0.0, position_smoothing_speed * delta)
		_left_tilt = _left_tilt.slerp(tilt, clamp(rotation_smoothing_speed * delta, 0.0, 1.0))
		height_offset = _left_height_offset
		foot_tilt = _left_tilt
	else:
		_right_height_offset = move_toward(_right_height_offset, target_offset if hit else 0.0, position_smoothing_speed * delta)
		_right_tilt = _right_tilt.slerp(tilt, clamp(rotation_smoothing_speed * delta, 0.0, 1.0))
		height_offset = _right_height_offset
		foot_tilt = _right_tilt

	if abs(height_offset) < 0.0005 and foot_tilt.is_equal_approx(Quaternion.IDENTITY):
		return  # Nada que ajustar todavía (suavizado en curso hacia 0): se deja la animación tal cual.

	# --- 3. IK analítica de dos huesos: dónde debe quedar la rodilla
	# para que el tobillo llegue al objetivo ---
	var rest_hip := skeleton.get_bone_global_rest(thigh_idx)
	var rest_knee := skeleton.get_bone_global_rest(calf_idx)
	var rest_foot := skeleton.get_bone_global_rest(foot_idx)

	var upper_length := (rest_knee.origin - rest_hip.origin).length()
	var lower_length := (rest_foot.origin - rest_knee.origin).length()
	if upper_length < 0.001 or lower_length < 0.001:
		return

	var target_pos := foot_pose.origin + Vector3(0.0, height_offset, 0.0)

	var result := FootIKTwoBoneSolver.solve(hip_pose.origin, knee_pose.origin, target_pos, upper_length, lower_length, max_leg_stretch, min_leg_extension)
	var new_knee_pos: Vector3 = result["knee_pos"]
	var new_foot_pos: Vector3 = result["foot_pos"]

	# --- 4. Rotaciones necesarias, derivadas de posiciones reales (sin
	# asumir ningún eje local concreto de los huesos de este rig) ---

	# Muslo: de la dirección cadera->rodilla ANIMADA a la nueva.
	var new_global_rot_thigh := hip_pose.basis.get_rotation_quaternion()
	var cur_dir_upper := knee_pose.origin - hip_pose.origin
	if cur_dir_upper.length() > 0.0001:
		var new_dir_upper := (new_knee_pos - hip_pose.origin).normalized()
		var delta_rot_upper := Quaternion(cur_dir_upper.normalized(), new_dir_upper)
		new_global_rot_thigh = delta_rot_upper * hip_pose.basis.get_rotation_quaternion()
		var parent_idx := skeleton.get_bone_parent(thigh_idx)
		var parent_rot := Quaternion.IDENTITY
		if parent_idx >= 0:
			parent_rot = skeleton.get_bone_global_pose(parent_idx).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(thigh_idx, parent_rot.inverse() * new_global_rot_thigh)

	# Pantorrilla: de la dirección rodilla->tobillo ANIMADA a la nueva,
	# aplicada sobre la rotación global YA actualizada del muslo (padre).
	var new_global_rot_calf := knee_pose.basis.get_rotation_quaternion()
	var cur_dir_lower := foot_pose.origin - knee_pose.origin
	if cur_dir_lower.length() > 0.0001:
		var new_dir_lower := (new_foot_pos - new_knee_pos).normalized()
		var delta_rot_lower := Quaternion(cur_dir_lower.normalized(), new_dir_lower)
		new_global_rot_calf = delta_rot_lower * knee_pose.basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(calf_idx, new_global_rot_thigh.inverse() * new_global_rot_calf)

	# Pie: se conserva la rotación animada (paso/orientación del pie tal
	# y como lo definió Idle/Walk/Sprint) y se le aplica ENCIMA solo la
	# inclinación extra (tilt) medida en espacio de mundo entre "arriba"
	# y la normal real del suelo. Al ser una rotación relativa (delta) y
	# no una orientación absoluta, funciona sin necesidad de conocer qué
	# eje local del hueso "foot" es el que apunta hacia arriba en este
	# rig concreto.
	var new_global_rot_foot := foot_tilt * foot_pose.basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(foot_idx, new_global_rot_calf.inverse() * new_global_rot_foot)
