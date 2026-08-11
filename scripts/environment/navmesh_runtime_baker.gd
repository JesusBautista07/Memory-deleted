class_name NavmeshRuntimeBaker
extends NavigationRegion3D
## Bakea el NavigationMesh de esta región en tiempo de ejecución, a partir de
## los StaticBody3D que cuelgan de ella (Floor, Stairs, Ramp, Platform),
## en vez de depender de un bakeo manual guardado desde el editor.
##
## Motivo: los NPC (NPCWanderer) necesitan un NavigationMesh real para poder
## subir las escaleras y esquivar el escenario en vez de solo moverse en un
## eje fijo (ver Ticket NPC-021). El NavigationMesh en sí (geometry_parsed_
## geometry_type = STATIC_COLLIDERS, source_geometry_mode = ROOT_NODE_
## CHILDREN) ya está configurado en el recurso NavigationMesh asignado a
## este nodo; este script solo dispara el bakeo real al cargar la escena.
##
## bake_navigation_mesh(false) = síncrono (no en hilo aparte). El
## escenario de prueba es pequeño, así que el costo es mínimo y evita
## condiciones de carrera con NPCSpawner, que empieza a spawnear NPC en el
## siguiente frame físico asumiendo que el navmesh ya existe.

signal navmesh_ready

func _ready() -> void:
	bake_navigation_mesh(false)
	# Un bakeo síncrono ya deja el NavigationMesh listo, pero el
	# NavigationServer3D todavía necesita sincronizar el mapa de navegación
	# (ocurre en el siguiente frame físico). NPCSpawner espera esta señal
	# antes de spawnear para que el primer NPC no se quede sin ruta.
	await get_tree().physics_frame
	await get_tree().physics_frame
	navmesh_ready.emit()
