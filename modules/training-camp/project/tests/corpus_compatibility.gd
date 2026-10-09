extends SceneTree
func _initialize():
	push_error("旧110局 own-window 快照不能证明双窗口结果；请执行 test_upgrade_battles.gd 重建对局。")
	quit(2)
