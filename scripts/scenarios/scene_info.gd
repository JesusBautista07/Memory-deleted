class_name SceneInfo
extends Resource

@export var scene_id: String = ""
@export var scene_name: String = ""
@export var description: String = ""
@export var scene_type: String = ""
@export var state: GameSceneState.State = GameSceneState.State.NOT_LOADED


static func from_scene_data(data: SceneData, current_state: GameSceneState.State) -> SceneInfo:
	var info := SceneInfo.new()
	info.scene_id = data.scene_id
	info.scene_name = data.scene_name
	info.description = data.description
	info.scene_type = data.scene_type
	info.state = current_state
	return info
