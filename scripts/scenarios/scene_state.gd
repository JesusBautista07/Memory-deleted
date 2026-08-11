class_name GameSceneState
extends RefCounted

enum State {
	NOT_LOADED,
	LOADING,
	ACTIVE,
	PAUSED,
	UNLOADING,
	FINISHED,
}


static func to_string_name(state: State) -> String:
	match state:
		State.NOT_LOADED:
			return "not_loaded"
		State.LOADING:
			return "loading"
		State.ACTIVE:
			return "active"
		State.PAUSED:
			return "paused"
		State.UNLOADING:
			return "unloading"
		State.FINISHED:
			return "finished"
	return "unknown"
