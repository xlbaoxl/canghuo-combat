extends "res://scripts/main.gd"
## Browser I/O only. The inherited controller, executor and AI remain authoritative.
var web_meta: Dictionary = {}
var web_elapsed: float = 0.0
var web_status_serial: int = 0
var web_commands: Array = []
var web_input_start: int = 0
var web_report_callback

func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://web/build.json"))
	if parsed is Dictionary: web_meta = parsed
	super._ready()
	if OS.has_feature("web"):
		web_report_callback = JavaScriptBridge.create_callback(_web_report_requested)
		var bridge = JavaScriptBridge.get_interface("CanghuoWeb")
		if bridge != null: bridge.requestReport = web_report_callback
		_publish_web_status()

func button(text: String, rect: Rect2, callback: Callable, key: String = "", parent: Control = null) -> Button:
	# Reuse the existing log window, replacing only its desktop file-folder action.
	return super.button(text, rect, export_web_review if key == "export_review" else callback, key, parent)

func save_settings() -> void:
	super.save_settings()
	if OS.has_feature("web"): JavaScriptBridge.force_fs_sync()

func start_snapshot() -> void:
	web_commands = []
	web_input_start = inputs.size()
	super.start_snapshot()
	if OS.has_feature("web") and is_instance_valid(stage):
		# Keep the same scene and assets; avoid an extra multisample resolve on WebGL.
		stage.viewport.msaa_3d = Viewport.MSAA_DISABLED

func toggle_pause() -> void:
	super.toggle_pause()
	if OS.has_feature("web") and is_instance_valid(stage):
		# A paused diorama does not need to redraw its full 3D scene every frame.
		stage.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if paused else SubViewport.UPDATE_ALWAYS

func submit(action: Dictionary) -> void:
	var before: String = battle.public_hash() if battle != null else ""
	var command: Dictionary = action.duplicate(true)
	if battle != null and not command.has("window_id"): command.window_id = battle.state.window_id
	super.submit(action)
	if battle != null and before != battle.public_hash():
		web_commands.append({"command": command, "before": before, "after": battle.public_hash()})

func _process(delta: float) -> void:
	super._process(delta)
	web_elapsed += delta
	if OS.has_feature("web") and web_elapsed >= 0.2:
		web_elapsed = 0.0
		_publish_web_status()

func _web_report_requested(_args: Array) -> void:
	export_web_review()

func export_web_review() -> void:
	if not OS.has_feature("web"): return
	var payload: Dictionary = {
		"format": "canghuo-web-review-1", "build": web_meta,
		"engine": Engine.get_version_info().string, "rules": Protocol.RULES,
		"content": catalog.data.version, "content_digest": catalog.digest,
		"page": page, "snapshot": snapshot, "human_commands": web_commands,
		"inputs": inputs.slice(web_input_start), "events": [], "AI": [],
		"replay_guaranteed": false,
		"replay_note": "诊断记录；包含人类已接受指令，但尚未验证完整AI指令重放。"
	}
	if battle != null:
		payload.events = battle.events
		payload.AI = battle.state.ai_traces
		payload.state = battle.state
		payload.accounting = battle.accounting()
	var bridge = JavaScriptBridge.get_interface("CanghuoWeb")
	if bridge != null:
		bridge.receiveReport(JSON.stringify(payload), "canghuo-" + str(web_meta.get("commit", "local")).left(8) + "-review.json")
	else:
		JavaScriptBridge.download_buffer(JSON.stringify(payload, "\t").to_utf8_buffer(), "canghuo-review.json", "application/json")

func _publish_web_status() -> void:
	# Read-only observation for diagnostics and real browser-input tests. No mutation API.
	web_status_serial += 1
	var info: Dictionary = {
		"sample": web_status_serial,
		"page": page, "character": char_id, "growth_profile": growth_profile,
		"slots": slots, "build": web_meta, "persistent": OS.is_userfs_persistent(),
		"paused": paused, "autoplay": autoplay, "speed": speed, "thinking": thinking(),
		"modal": modal != null, "controls": {}, "selected_action": selected_action,
		"snapshot": snapshot, "player_ready": false
	}
	for key in controls:
		var control = controls[key]
		if is_instance_valid(control) and control is Control and control.is_visible_in_tree():
			var rect: Rect2 = control.get_global_rect()
			info.controls[key] = {"x": rect.get_center().x, "y": rect.get_center().y,
				"disabled": control.disabled if control is BaseButton else false}
	if battle != null:
		info.battle_id = battle.state.battle_id
		info.hash = battle.public_hash()
		info.ended = battle.state.ended
		info.result = battle.state.result
		info.reason = battle.state.reason
		info.event_count = battle.events.size()
		info.window_id = battle.state.window_id
		info.window_kind = battle.state.window_kind
		info.player_ready = page == "battle" and modal == null and not paused and not thinking() and event_cursor >= battle.events.size() and playback_wait <= 0 and battle.state.current == "p" and battle.state.phase == "DECISION" and not battle.state.ended
		info.accounting_ok = battle.accounting().ok
		info.player = battle.unit("p").duplicate(true)
	if is_instance_valid(stage):
		info.targets = {}
		for id in ["p", "e"]:
			var point: Vector2 = stage.target_point(id)
			info.targets[id] = {"x": point.x, "y": point.y}
	if is_instance_valid(details) and details.visible:
		info.tooltip = {"title": details.model.get("title", ""), "effect": details.model.get("effect", "")}
	var bridge = JavaScriptBridge.get_interface("CanghuoWeb")
	if bridge != null: bridge.receiveStatus(JSON.stringify(info))
