class_name FootIKTwoBoneSolver
extends RefCounted
## Utilidad de IK ANALÍTICA de dos huesos (cadera -> rodilla -> tobillo),
## resuelta con la ley de cosenos.
##
## POR QUÉ ESTE MÉTODO Y NO FABRIK:
## Godot 4.5.1 no trae ningún nodo de IK de piernas integrado todavía
## (TwoBoneIK3D/FABRIK3D/CCDIK3D llegan recién en Godot 4.6, ver
## godotengine/godot#110120; en 4.5 solo existen LookAtModifier3D,
## RetargetModifier3D, SpringBoneSimulator3D y BoneConstraint3D). Para una
## cadena de EXACTAMENTE dos huesos (como una pierna), la solución
## analítica por ley de cosenos es la técnica estándar del sector: es
## determinista, no itera y no puede oscilar ni "vibrar" como sí puede
## pasarle a FABRIK con cadenas muy cortas. FABRIK solo aporta ventajas
## reales en cadenas largas (3+ huesos), que no es el caso aquí. Por eso
## es "el método más adecuado" para esta primera versión, no una
## simplificación de recorte.
##
## ESPACIO DE TRABAJO:
## Todas las posiciones que recibe y devuelve esta función están en el
## mismo espacio: el espacio del Skeleton3D (el que usan de forma nativa
## Skeleton3D.get_bone_global_pose() / get_bone_global_rest()). No se
## asume NINGÚN eje local concreto de ningún hueso (ni "adelante",
## ni "arriba"): toda la orientación se deriva de posiciones reales,
## así que funciona igual para cualquier esqueleto cuyos huesos
## cadera/rodilla/tobillo formen una cadena padre-hijo simple, sin
## necesidad de conocer de antemano el convenio de ejes de ese rig
## concreto.

## Resuelve la posición de la rodilla que sitúa el tobillo en target_pos,
## respetando las longitudes reales del muslo/pantorrilla y doblando la
## rodilla hacia knee_pos_animated (la rodilla tal y como la dejó la
## animación base este mismo frame), para conservar la dirección de
## flexión natural que ya define la animación en vez de inventar una.
##
## Devuelve un Dictionary con:
##   "knee_pos": Vector3  -> nueva posición de la rodilla
##   "foot_pos": Vector3  -> posición final del tobillo (== target_pos,
##                           salvo que se haya recortado por max/min de
##                           estiramiento; ver más abajo)
##   "reached": bool      -> false si target_pos estaba fuera de alcance
##                           y se ha recortado (límite articular alcanzado)
static func solve(
		hip_pos: Vector3,
		knee_pos_animated: Vector3,
		target_pos: Vector3,
		upper_length: float,
		lower_length: float,
		max_stretch: float = 0.98,
		min_extension_ratio: float = 0.08
) -> Dictionary:
	var to_target := target_pos - hip_pos
	var dist := to_target.length()

	# --- Límites articulares (evitan bloquear la rodilla recta del todo
	# y evitan un plegado extremo antinatural) ---
	var max_len: float = (upper_length + lower_length) * max_stretch
	var min_len: float = max(abs(upper_length - lower_length), (upper_length + lower_length) * min_extension_ratio)
	var clamped_dist: float = clamp(dist, min_len, max_len)

	var dir_to_target: Vector3
	if dist > 0.0001:
		dir_to_target = to_target / dist
	else:
		dir_to_target = Vector3.DOWN

	var actual_target: Vector3 = hip_pos + dir_to_target * clamped_dist

	# --- Ley de cosenos: ángulo en la cadera entre (cadera->objetivo) y
	# (cadera->rodilla) ---
	var cos_hip: float = (upper_length * upper_length + clamped_dist * clamped_dist - lower_length * lower_length) / (2.0 * upper_length * clamped_dist)
	cos_hip = clamp(cos_hip, -1.0, 1.0)
	var angle_hip := acos(cos_hip)

	# --- Eje de flexión: hacia dónde debe doblar la rodilla. Se toma de
	# la rodilla ANIMADA (proyectada sobre el plano perpendicular a la
	# línea cadera->objetivo) para respetar la flexión que ya define la
	# animación base (Idle/Walk/Sprint/Crouch), en vez de asumir un eje
	# fijo del esqueleto. ---
	var pole_dir := knee_pos_animated - hip_pos
	var pole_proj := pole_dir - dir_to_target * pole_dir.dot(dir_to_target)

	var bend_dir: Vector3
	if pole_proj.length() > 0.0001:
		bend_dir = pole_proj.normalized()
	else:
		# Caso degenerado poco frecuente (rodilla animada casi en línea
		# recta con cadera y objetivo): eje de respaldo estable.
		bend_dir = dir_to_target.cross(Vector3.UP)
		if bend_dir.length() < 0.0001:
			bend_dir = dir_to_target.cross(Vector3.RIGHT)
		bend_dir = bend_dir.normalized()

	var knee_pos := hip_pos + dir_to_target * (upper_length * cos(angle_hip)) + bend_dir * (upper_length * sin(angle_hip))

	return {
		"knee_pos": knee_pos,
		"foot_pos": actual_target,
		"reached": clamped_dist >= dist - 0.0001,
	}
