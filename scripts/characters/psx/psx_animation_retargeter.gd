class_name PSXAnimationRetargeter
extends RefCounted
## Genera, en tiempo de ejecución, una AnimationLibrary "retargeted" a partir
## de una AnimationLibrary de origen (esqueleto Unreal Mannequin, la que ya
## usa SharedAnimationLibrary) y un Skeleton3D de destino con nomenclatura
## Mixamo (cualquier personaje de Characters_psx).
##
## No modifica ni el AnimationLibrary de origen ni los archivos del
## personaje: trabaja siempre sobre copias (Animation.duplicate(true)) y
## solo escribe en la AnimationLibrary nueva que devuelve. Por eso es
## reutilizable para tantos personajes PSX como se quiera sin tocar nada
## de Characters_psx.
##
## USO TÍPICO (ver psx_character_controller.gd):
##   var result := PSXAnimationRetargeter.build_retargeted_library(
##       SharedAnimationLibrary.get_library(),
##       mi_skeleton_3d,
##       PSXBoneRetargetMap.UNREAL_TO_MIXAMO
##   )
##   mi_animation_player.add_animation_library("PSX_UAL", result.library)
##
## CORRECCIÓN DE REST POSE / BIND POSE (deformación visual al reproducir):
## Renombrar los tracks de hueso NO basta: el rig Unreal Mannequin (origen)
## y el rig Mixamo/PSX (destino) tienen la MISMA jerarquía corporal pero
## orientaciones locales de hueso distintas en su Rest Pose. Si se copia
## la rotación animada de origen tal cual sobre el hueso de destino, cada
## articulación gira alrededor de los ejes locales "equivocados" y el
## personaje se retuerce/deforma. Por eso, antes de renombrar cada track,
## _correct_pose_in_place() recalcula el valor de cada key de rotación (y
## de posición, cuando aplica) preservando el "delta respecto al bind"
## EXPRESADO EN LOS EJES LOCALES DE BIND DE CADA HUESO -no en ejes de
## mundo-, que es lo que generaliza correctamente entre dos rigs con
## Rest Pose distinta. Ver el comentario de _correct_pose_in_place() para
## el desarrollo completo de la fórmula.


## Resultado del retargeting: la librería generada + un informe diagnóstico
## para saber exactamente qué se perdió y por qué (nunca se "inventa" nada:
## si un hueso no existe en el destino, el track correspondiente se
## descarta y queda registrado aquí).
class RetargetResult:
	var library: AnimationLibrary = AnimationLibrary.new()
	## anim_name -> Array[String] de nombres de hueso (nomenclatura Unreal)
	## cuyo track se descartó por no tener mapeo o no existir en el
	## Skeleton3D de destino.
	var dropped_tracks_by_animation: Dictionary = {}
	## Huesos del bone_map que se intentaron usar pero el Skeleton3D de
	## destino no tiene (agregado de todas las animaciones, sin duplicados).
	var missing_bones: Array[String] = []


## CAUSA RAÍZ del bug de los ~55 huesos descartados (ver REPORTE del
## Ticket de animaciones NPC): el nombre de hueso "mixamorig:Hips" (y
## análogos) SÍ existe tal cual en el .fbx de origen (verificado
## directamente sobre Character_Monster.fbx), pero Godot construye el
## Skeleton3D a partir de los nombres de los NODOS internos del FBX
## durante la importación, y Node.name no admite ":" (es uno de los
## caracteres inválidos: . : @ / "). El importador sanea ese carácter
## (típicamente sustituyéndolo o eliminándolo), así que el hueso queda
## registrado en el Skeleton3D final como "mixamorig_Hips" (u otra
## variante saneada) en vez de "mixamorig:Hips" literal.
## Skeleton3D.find_bone() compara por nombre EXACTO, así que falla
## para prácticamente todos los huesos del mapa aunque "existan" en la
## práctica bajo un nombre saneado. Por eso se resuelve por nombre
## NORMALIZADO (solo alfanumérico, minúsculas) en vez de por igualdad
## estricta: así da igual qué saneado concreto haya aplicado el
## importador (sustitución por "_", eliminación del carácter, etc.).
static func _normalize_bone_name(bone_name: String) -> String:
	var result := ""
	for c in bone_name.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			result += c
	return result


# ---------------------------------------------------------------------------
# DATOS DE REST POSE / BIND POSE DE UN ESQUELETO
# ---------------------------------------------------------------------------

## Snapshot ligero (solo datos, sin nodos vivos) de la jerarquía y la Rest
## Pose de un Skeleton3D, indexado por NOMBRE de hueso. Se usa tanto para
## el esqueleto de origen (Unreal Mannequin, extraído una sola vez de
## UAL1_Standard.glb) como para el esqueleto de destino (el del personaje
## PSX que se esté retargeteando en cada llamada).
class _SkeletonBindData:
	## bone_name -> nombre del hueso padre real ("" si es raíz).
	var parent_name: Dictionary = {}
	## bone_name -> Transform3D local de Rest Pose (relativo al padre),
	## tal como lo expone Skeleton3D.get_bone_rest().
	var rest_local: Dictionary = {}
	## Cache interno de _global_bind_cache: bone_name -> Transform3D global
	## de Rest Pose (acumulado desde la raíz). Evita recalcular la cadena
	## completa en cada consulta.
	var _global_bind_cache: Dictionary = {}

	## Transform3D global de Rest Pose de `bone_name`, acumulando
	## recursivamente Transform3D local * padre global. Memoizado.
	func global_bind(bone_name: String) -> Transform3D:
		if bone_name == "":
			return Transform3D.IDENTITY
		if _global_bind_cache.has(bone_name):
			return _global_bind_cache[bone_name]
		var parent: String = parent_name.get(bone_name, "")
		var local: Transform3D = rest_local.get(bone_name, Transform3D.IDENTITY)
		var result: Transform3D = global_bind(parent) * local
		_global_bind_cache[bone_name] = result
		return result


## Extrae un snapshot de datos (_SkeletonBindData) de un Skeleton3D real.
## No conserva ninguna referencia al nodo: solo copia nombres/transforms,
## por eso es seguro llamarlo sobre un Skeleton3D que se vaya a liberar
## justo después (ver _get_source_bind_data()).
static func _extract_bind_data(skeleton: Skeleton3D) -> _SkeletonBindData:
	var data := _SkeletonBindData.new()
	for bone_idx in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone_idx)
		var parent_idx := skeleton.get_bone_parent(bone_idx)
		data.parent_name[bone_name] = skeleton.get_bone_name(parent_idx) if parent_idx != -1 else ""
		data.rest_local[bone_name] = skeleton.get_bone_rest(bone_idx)
	return data


## Ruta al mismo archivo que ya usa SharedAnimationLibrary para las
## animaciones: aquí se usa solo para leer la Rest Pose del esqueleto
## Unreal Mannequin de ORIGEN (no las animaciones, esas las sigue
## sirviendo SharedAnimationLibrary). Es la misma fuente porque el rig
## sobre el que están hechas las animaciones de UAL1_Standard.glb es
## precisamente el que hay que usar como referencia de Rest Pose de
## origen para el retargeting.
const SOURCE_SKELETON_PATH := "res://assets/animations/UAL1_Standard.glb"

## No se cachea un resultado null "para siempre" (mismo motivo que ya
## documenta SharedAnimationLibrary.get_library(): un fallo transitorio de
## carga no debe dejar el retargeting roto el resto de la sesión), así que
## se reintenta en cada llamada hasta conseguir un resultado válido.
static var _source_bind_data: _SkeletonBindData = null

static func _get_source_bind_data() -> _SkeletonBindData:
	if _source_bind_data != null:
		return _source_bind_data

	var packed_scene: PackedScene = load(SOURCE_SKELETON_PATH)
	if packed_scene == null:
		push_warning("PSXAnimationRetargeter: no se pudo cargar '%s' para leer la Rest Pose de origen." % SOURCE_SKELETON_PATH)
		return null

	var temp_root: Node = packed_scene.instantiate()
	var source_skeleton := find_skeleton(temp_root)
	if source_skeleton == null:
		push_warning("PSXAnimationRetargeter: '%s' no contiene ningún Skeleton3D; no se puede corregir la Rest Pose." % SOURCE_SKELETON_PATH)
		temp_root.queue_free()
		return null

	_source_bind_data = _extract_bind_data(source_skeleton)
	temp_root.queue_free()
	return _source_bind_data


## Distancia (en espacio de Rest Pose) entre "pelvis" y "Head" en el rig de
## origen frente a la misma distancia en el rig de destino. Se usa como
## factor de escala UNIFORME y genérico (no depende del personaje) para
## reescalar los pocos tracks de POSICIÓN que suele haber en mocap de
## locomoción (típicamente solo la cadera/pelvis, para el balanceo
## vertical al caminar/correr) y así no estirar ni encoger al personaje de
## destino al copiar desplazamientos pensados para las proporciones del
## Unreal Mannequin. "pelvis"/"Head" se usan porque son las dos claves que
## SIEMPRE están presentes en PSXBoneRetargetMap.UNREAL_TO_MIXAMO.
static func _compute_uniform_scale(
	source_bind: _SkeletonBindData,
	target_bind: _SkeletonBindData,
	resolved_target_by_source: Dictionary
) -> float:
	const REF_ROOT := "pelvis"
	const REF_TIP := "Head"
	if not (resolved_target_by_source.has(REF_ROOT) and resolved_target_by_source.has(REF_TIP)):
		return 1.0

	var source_span: float = source_bind.global_bind(REF_ROOT).origin.distance_to(
		source_bind.global_bind(REF_TIP).origin
	)
	if source_span < 0.0001:
		return 1.0

	var target_span: float = target_bind.global_bind(resolved_target_by_source[REF_ROOT]).origin.distance_to(
		target_bind.global_bind(resolved_target_by_source[REF_TIP]).origin
	)
	return target_span / source_span


# ---------------------------------------------------------------------------
# CORRECCIÓN DE POSE (rotación + posición) DE UNA ANIMACIÓN CONCRETA
# ---------------------------------------------------------------------------

## Corrige, IN PLACE, los valores de las keys de rotación (y de posición,
## cuando existan) de `anim`. Debe llamarse ANTES de renombrar los tracks a
## nombres de hueso de destino: usa los nombres de hueso de ORIGEN -los que
## ya trae `anim` tal cual viene de UAL1_Standard.glb- tanto para recorrer
## la jerarquía real de origen como para consultar `resolved_target_by_source`.
##
## FÓRMULA (por cada hueso mapeado, en cada instante t de cada key):
##
##   Gs_bind  = rotación global de Rest Pose del hueso en el rig de ORIGEN
##   Gd_bind  = rotación global de Rest Pose del hueso en el rig de DESTINO
##   Gs_anim(t) = rotación global ANIMADA del hueso en el rig de origen en
##                el instante t, acumulando TODA la cadena real de padres
##                de origen (estén o no mapeados a destino: un padre sin
##                mapeo -como el hueso auxiliar "root"- igual contribuye a
##                la orientación de sus hijos y no puede ignorarse)
##
##   Gd_anim(t) = Gd_bind * Gs_bind^-1 * Gs_anim(t)
##
## Esto preserva el "delta respecto al bind" EXPRESADO EN LOS EJES LOCALES
## DE BIND DE CADA HUESO (Gs_bind^-1 * Gs_anim(t) es esa desviación, en el
## propio sistema de referencia del hueso), que es la parte que sí tiene
## sentido físico igual en los dos rigs (p. ej. "el codo se flexiona 90°
## alrededor de su propio eje de bisagra"), y luego se reexpresa en el
## sistema de Rest Pose de destino con Gd_bind. Aplicar el delta en
## ejes de MUNDO en cambio (fórmula alternativa Gd_bind * (Gs_anim * Gs_bind^-1))
## NO generaliza entre rigs con Rest Pose distinta y es la causa de la
## deformación visual que se estaba viendo.
##
## Por último, para poder escribir la rotación en el track de destino
## (que es relativa a SU padre real en target_skeleton, no al padre de
## origen), se reconvierte a local:
##
##   Ld_anim(t) = Gd_anim_padre(t)^-1 * Gd_anim(t)
##
## donde "padre" es el padre REAL de destino traducido de vuelta a su
## hueso de origen equivalente (si el mapa lo cubre); si no lo cubre -caso
## de la cadera/pelvis, cuyo padre real de destino es el nodo raíz del
## modelo, fuera del mapa- se asume identidad, tratando ese hueso como
## raíz de la corrección (igual que ya se descartaba el hueso "root" de
## origen por no tener equivalente en destino).
##
## Los tracks de POSICIÓN (normalmente solo la cadera, para el balanceo al
## caminar/correr) se corrigen de forma análoga: se preserva el desplaza-
## miento respecto al bind expresado en los ejes locales de bind del
## padre, y se reescala con el factor uniforme de _compute_uniform_scale().
##
## IMPORTANTE: todas las lecturas (rotation_track_interpolate /
## position_track_interpolate) se hacen sobre los valores ORIGINALES de
## `anim`. Los nuevos valores se calculan primero en listas separadas
## (`pending_rotation_writes` / `pending_position_writes`) y solo se
## escriben al final, en una segunda pasada: si se escribiera en el mismo
## track que todavía se está usando como referencia para calcular la
## cadena de huesos padre de OTRO hueso, esa lectura devolvería un valor ya
## corregido (en espacio de destino) en vez del original de origen,
## corrompiendo el cálculo.
static func _correct_pose_in_place(
	anim: Animation,
	source_bind: _SkeletonBindData,
	target_bind: _SkeletonBindData,
	resolved_target_by_source: Dictionary,
	source_by_resolved_target: Dictionary,
	uniform_scale: float
) -> void:
	var rotation_track_by_bone: Dictionary = {}
	var position_track_by_bone: Dictionary = {}
	for track_idx in anim.get_track_count():
		var bone_name: String = anim.track_get_path(track_idx).get_concatenated_subnames()
		if bone_name == "":
			continue
		match anim.track_get_type(track_idx):
			Animation.TYPE_ROTATION_3D:
				rotation_track_by_bone[bone_name] = track_idx
			Animation.TYPE_POSITION_3D:
				position_track_by_bone[bone_name] = track_idx

	# --- rotación global animada de ORIGEN (siempre sobre los valores
	#     originales de `anim`, memoizada por CADENA de huesos + tiempo).
	#
	# NOTA GDSCRIPT: se implementa como bucle explícito (subiendo la
	# cadena real de padres de origen) en vez de como lambda recursiva
	# que se llama a sí misma. Los closures de GDScript capturan el
	# valor de las variables locales en el momento en que se CREA la
	# lambda; una lambda que intentase invocarse a través de una
	# variable externa se capturaría a sí misma como null (la
	# asignación `x = func(): ... x.call() ...` todavía no se ha
	# completado cuando el cuerpo de la lambda se construye), así que la
	# recursión real hay que resolverla de forma iterativa aquí.
	var source_global_rot_cache: Dictionary = {}

	var get_source_global_rot: Callable = func(bone_name: String, t: float) -> Quaternion:
		var chain: Array = []
		var current := bone_name
		while current != "":
			chain.push_front(current)
			current = source_bind.parent_name.get(current, "")

		var g := Quaternion.IDENTITY
		var chain_key := ""
		for name in chain:
			chain_key += name + ">"
			var cache_key: String = "%s@%.6f" % [chain_key, t]
			if source_global_rot_cache.has(cache_key):
				g = source_global_rot_cache[cache_key]
				continue
			var local_rot: Quaternion
			if rotation_track_by_bone.has(name):
				local_rot = anim.rotation_track_interpolate(rotation_track_by_bone[name], t)
			else:
				local_rot = source_bind.rest_local.get(name, Transform3D.IDENTITY).basis.get_rotation_quaternion()
			g = g * local_rot
			source_global_rot_cache[cache_key] = g
		return g

	var get_dest_global_rot: Callable = func(source_bone_name: String, t: float) -> Quaternion:
		var gs_bind: Quaternion = source_bind.global_bind(source_bone_name).basis.get_rotation_quaternion()
		var gd_bind: Quaternion = target_bind.global_bind(resolved_target_by_source[source_bone_name]).basis.get_rotation_quaternion()
		var gs_anim: Quaternion = get_source_global_rot.call(source_bone_name, t)
		return gd_bind * gs_bind.inverse() * gs_anim

	# --- fase 1: calcular todos los valores nuevos, sin escribir todavía ---
	var pending_rotation_writes: Array = []  # [track_idx, key_idx, Quaternion]
	for source_bone_name in rotation_track_by_bone.keys():
		if not resolved_target_by_source.has(source_bone_name):
			continue  # sin equivalente en destino, se descarta en la 2ª pasada del llamador

		var track_idx: int = rotation_track_by_bone[source_bone_name]
		var resolved_name: String = resolved_target_by_source[source_bone_name]
		var dest_real_parent_name: String = target_bind.parent_name.get(resolved_name, "")
		var parent_source_name: String = source_by_resolved_target.get(dest_real_parent_name, "")

		for key_idx in anim.track_get_key_count(track_idx):
			var t: float = anim.track_get_key_time(track_idx, key_idx)
			var gd_anim: Quaternion = get_dest_global_rot.call(source_bone_name, t)
			var gd_anim_parent: Quaternion = Quaternion.IDENTITY
			if parent_source_name != "":
				gd_anim_parent = get_dest_global_rot.call(parent_source_name, t)
			var local_rot: Quaternion = gd_anim_parent.inverse() * gd_anim
			pending_rotation_writes.append([track_idx, key_idx, local_rot])

	# --- posición (normalmente solo la cadera/pelvis) ---
	var pending_position_writes: Array = []  # [track_idx, key_idx, Vector3]
	for source_bone_name in position_track_by_bone.keys():
		if not resolved_target_by_source.has(source_bone_name):
			continue

		var track_idx: int = position_track_by_bone[source_bone_name]
		var resolved_name: String = resolved_target_by_source[source_bone_name]
		var source_parent_name: String = source_bind.parent_name.get(source_bone_name, "")
		var dest_real_parent_name: String = target_bind.parent_name.get(resolved_name, "")

		var gs_bind_parent_basis: Basis = source_bind.global_bind(source_parent_name).basis
		var gd_bind_parent_basis: Basis = target_bind.global_bind(dest_real_parent_name).basis
		var rest_pos_source: Vector3 = source_bind.rest_local.get(source_bone_name, Transform3D.IDENTITY).origin
		var rest_pos_dest: Vector3 = target_bind.rest_local.get(resolved_name, Transform3D.IDENTITY).origin

		for key_idx in anim.track_get_key_count(track_idx):
			var t: float = anim.track_get_key_time(track_idx, key_idx)
			var ps: Vector3 = anim.position_track_interpolate(track_idx, t)
			var delta_source: Vector3 = ps - rest_pos_source
			var delta_dest: Vector3 = gd_bind_parent_basis.inverse() * (gs_bind_parent_basis * delta_source) * uniform_scale
			pending_position_writes.append([track_idx, key_idx, rest_pos_dest + delta_dest])

	# --- fase 2: escribir. A partir de aquí `anim` ya no se usa como
	#     fuente de lectura, así que es seguro mutarlo. ---
	for write in pending_rotation_writes:
		anim.track_set_key_value(write[0], write[1], write[2])
	for write in pending_position_writes:
		anim.track_set_key_value(write[0], write[1], write[2])


static func build_retargeted_library(
	source_library: AnimationLibrary,
	target_skeleton: Skeleton3D,
	bone_map: Dictionary,
	skeleton_path_from_animation_root: NodePath
) -> RetargetResult:
	var result := RetargetResult.new()

	if source_library == null:
		push_warning("PSXAnimationRetargeter: source_library es null, no se puede retargetear.")
		return result
	if target_skeleton == null:
		push_warning("PSXAnimationRetargeter: target_skeleton es null, no se puede retargetear.")
		return result

	var source_bind := _get_source_bind_data()
	# Si por lo que sea no se pudo leer la Rest Pose de origen (archivo
	# movido, etc.), se sigue con el comportamiento antiguo -solo remapeo
	# de nombres, sin corrección de pose- en vez de dejar al personaje sin
	# ninguna animación; se avisa igual para que el fallo no pase inadvertido.
	var can_correct_pose := source_bind != null
	if not can_correct_pose:
		push_warning("PSXAnimationRetargeter: no se pudo leer la Rest Pose de origen, el retargeting solo remapeará nombres de hueso (puede seguir deformándose).")

	var target_bind := _extract_bind_data(target_skeleton)

	# Índice de nombre normalizado -> nombre REAL del hueso tal como
	# existe en target_skeleton. Se construye una sola vez por llamada
	# (no por hueso) para no recorrer el esqueleto en cada track.
	var normalized_target_bones: Dictionary = {}
	for bone_idx in target_skeleton.get_bone_count():
		var real_bone_name := target_skeleton.get_bone_name(bone_idx)
		normalized_target_bones[_normalize_bone_name(real_bone_name)] = real_bone_name

	# Resuelve, una sola vez por llamada (no por animación ni por key), el
	# nombre real de destino de cada hueso de origen del mapa, y su
	# inverso (para poder hallar, a partir del padre REAL de un hueso de
	# destino, cuál es su hueso de origen equivalente).
	var resolved_target_by_source: Dictionary = {}  # nombre origen -> nombre real en destino
	var source_by_resolved_target: Dictionary = {}  # nombre real en destino -> nombre origen
	var missing_bones_set := {}
	for source_name in bone_map.keys():
		var mixamo_bone_name: String = bone_map[source_name]

		# 1) intento exacto (cubre el caso en que el importador NO haya
		#    saneado el nombre, p. ej. otras versiones de Godot).
		# 2) fallback por nombre normalizado (cubre el saneado de ":"
		#    descrito arriba, que es el caso real en este proyecto).
		var resolved_bone_name: String = ""
		if target_skeleton.find_bone(mixamo_bone_name) != -1:
			resolved_bone_name = mixamo_bone_name
		else:
			var normalized := _normalize_bone_name(mixamo_bone_name)
			if normalized_target_bones.has(normalized):
				resolved_bone_name = normalized_target_bones[normalized]

		if resolved_bone_name == "":
			missing_bones_set[source_name] = true
			continue

		resolved_target_by_source[source_name] = resolved_bone_name
		source_by_resolved_target[resolved_bone_name] = source_name

	var uniform_scale := 1.0
	if can_correct_pose:
		uniform_scale = _compute_uniform_scale(source_bind, target_bind, resolved_target_by_source)

	for anim_name in source_library.get_animation_list():
		var source_anim: Animation = source_library.get_animation(anim_name)
		var new_anim: Animation = source_anim.duplicate(true)

		if can_correct_pose:
			_correct_pose_in_place(
				new_anim,
				source_bind,
				target_bind,
				resolved_target_by_source,
				source_by_resolved_target,
				uniform_scale
			)

		var dropped_for_this_anim: Array[String] = []
		# Se recorre de atrás hacia delante porque remove_track() desplaza
		# los índices posteriores; ir al revés evita saltarse tracks.
		var track_idx := new_anim.get_track_count() - 1
		while track_idx >= 0:
			var original_path: NodePath = new_anim.track_get_path(track_idx)
			# Reconstruye el nombre del hueso uniendo TODOS los subnombres
			# con ":" (necesario porque los huesos Mixamo ya contienen ":"
			# en su propio nombre, ej. "mixamorig:Hips", y NodePath separa
			# por ":" en cada subname).
			var bone_name := original_path.get_concatenated_subnames()

			if bone_name == "":
				# Track sin subname de hueso (no debería darse en estas
				# animaciones, pero se deja intacto por seguridad).
				track_idx -= 1
				continue

			if not resolved_target_by_source.has(bone_name):
				dropped_for_this_anim.append(bone_name)
				new_anim.remove_track(track_idx)
				track_idx -= 1
				continue

			var new_path := NodePath(
				String(skeleton_path_from_animation_root) + ":" + resolved_target_by_source[bone_name]
			)
			new_anim.track_set_path(track_idx, new_path)
			track_idx -= 1

		if not dropped_for_this_anim.is_empty():
			result.dropped_tracks_by_animation[anim_name] = dropped_for_this_anim

		result.library.add_animation(anim_name, new_anim)

	for bone_name in missing_bones_set.keys():
		result.missing_bones.append(bone_name)

	return result


## Busca recursivamente el primer Skeleton3D bajo `root`. Se usa para no
## depender de conocer de antemano la jerarquía exacta que genera el
## importador de Godot para cada .fbx de Characters_psx (y también para
## UAL1_Standard.glb al leer la Rest Pose de origen).
static func find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var found := find_skeleton(child)
		if found != null:
			return found
	return null


## Bootstrap completo reutilizable: localiza el Skeleton3D bajo `model`,
## genera la librería retargeted a partir de SharedAnimationLibrary y la
## añade a `anim_player` bajo el nombre RETARGET_LIBRARY_NAME. Pensado para
## usarse igual desde el personaje del jugador (psx_character_controller.gd)
## y desde NPCs de prueba (psx_npc_test_walker.gd), sin duplicar esta
## lógica en cada script.
## `context_name` es solo una etiqueta para los mensajes de aviso/diagnóstico
## (normalmente el nombre del nodo que llama a esta función).
## Devuelve el Skeleton3D encontrado, o null si el retargeting no pudo
## aplicarse (en cuyo caso ya se ha emitido un push_warning explicando por qué).
const RETARGET_LIBRARY_NAME := "PSX_UAL"

static func apply_to(model: Node, anim_player: AnimationPlayer, context_name: String) -> Skeleton3D:
	var skeleton := find_skeleton(model)
	if skeleton == null:
		push_warning("PSXAnimationRetargeter (%s): no se encontró ningún Skeleton3D bajo el modelo. No se puede aplicar el retargeting." % context_name)
		return null

	var source_library := SharedAnimationLibrary.get_library()
	if source_library == null:
		push_warning("PSXAnimationRetargeter (%s): SharedAnimationLibrary.get_library() devolvió null." % context_name)
		return skeleton

	# CAUSA RAÍZ (confirmada en consola: cientos de avisos "couldn't resolve
	# track" tras corregir los nombres de animación): Godot resuelve los
	# NodePath de los tracks de una Animation relativos a
	# AnimationPlayer.root_node (por defecto NodePath(".."), o sea el PADRE
	# del AnimationPlayer), NO relativos al AnimationPlayer mismo. Como aquí
	# el AnimationPlayer y el Model (que contiene el Skeleton3D) son
	# hermanos, `anim_player.get_path_to(skeleton)` devolvía una ruta
	# ("../Model/Skeleton3D") pensada para partir del AnimationPlayer, pero
	# el motor la interpretaba partiendo de root_node (que ya es el padre),
	# subiendo un nivel de más y sin encontrar nunca el Skeleton3D. Se
	# calcula el path desde el nodo raíz real de reproducción
	# (get_node(root_node)), que es el punto de referencia correcto.
	var animation_root: Node = anim_player.get_node(anim_player.root_node)
	var skeleton_path := animation_root.get_path_to(skeleton)
	var result := build_retargeted_library(
		source_library,
		skeleton,
		PSXBoneRetargetMap.UNREAL_TO_MIXAMO,
		skeleton_path
	)

	# AnimationPlayer.add_animation_library() falla (error de Godot, sin
	# excepción capturable) y NO añade nada si ya existe una librería con
	# ese mismo nombre. Si apply_to() se llegara a invocar dos veces sobre
	# el mismo AnimationPlayer (reinicio del NPC, reingreso a la escena,
	# etc.), la segunda llamada dejaría el AnimationPlayer sin "PSX_UAL" y
	# _play_state() reportaría animaciones "no disponibles" pese a que el
	# retargeting se ejecutó correctamente. Se sustituye la librería previa
	# en vez de intentar añadir sobre una ya existente.
	if anim_player.has_animation_library(RETARGET_LIBRARY_NAME):
		anim_player.remove_animation_library(RETARGET_LIBRARY_NAME)
	anim_player.add_animation_library(RETARGET_LIBRARY_NAME, result.library)

	if not result.missing_bones.is_empty():
		push_warning(
			"PSXAnimationRetargeter (%s): %d hueso(s) del mapa Unreal->Mixamo no existen en este esqueleto PSX y se omitieron: %s"
			% [context_name, result.missing_bones.size(), ", ".join(result.missing_bones)]
		)
	for anim_name in result.dropped_tracks_by_animation.keys():
		var dropped: Array = result.dropped_tracks_by_animation[anim_name]
		print(
			"[PSXAnimationRetargeter:%s] Animación '%s' retargeted con %d track(s) descartado(s) (huesos: %s)."
			% [context_name, anim_name, dropped.size(), ", ".join(dropped)]
		)

	return skeleton
