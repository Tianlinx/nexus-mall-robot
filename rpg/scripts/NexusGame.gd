extends Node3D
## NEXUS 机器人经营 RPG · Godot 4.3 · 第三人称完整版
## 数据真源：res://data/nexus_map.json（56×48 栅格 / 10 区 / 29 货架 / 75 商品 / 25 通道 /
##   104 关联规则 / 112 节报告全文 / 13 知识卡 / 8 考核题 / 22 色官方 palette / 75 建模 kind）
## 场景：NexusScenery 复刻 fC/pC/SC/CC/wC/TC/EC/DC，ProductModels 复刻 dC()。
## 系统：NexusSystems 全量移植 Cost 五因子 / A* / Held–Karp / 四算法 / 关联加购 /
##   技能树 / 声望 / 日结 / 知识考核。

enum Mode { MENU, PLAYING, PAUSED, BIGMAP, PANEL }
const COLS := 56
const ROWS := 48
const SAVE_PATH := "user://nexus_save.json"

const TUTORIAL := [
	{"title": "1 / 7 · 走走看", "desc": "W A S D 移动，Shift 冲刺。第三人称镜头下你能看到 R-07 机器人本体、双机械臂和背部货舱。",
	 "goal": "累计移动 3 米", "kind": "move", "n": 3.0},
	{"title": "2 / 7 · 环绕视角", "desc": "移动鼠标绕着机器人转视角，上下移动可抬高或压低镜头。",
	 "goal": "转动视角 220 像素", "kind": "look", "n": 220.0},
	{"title": "3 / 7 · 打开全图", "desc": "按 M 调出 56×48 大地图：10 个展区、25 条通道拥挤热力、订单目标、Gate A / B。再按 M 关闭。",
	 "goal": "按一次 M", "kind": "key", "v": "M"},
	{"title": "4 / 7 · 导航芯片", "desc": "按 N 用 A* + Held–Karp 算取货顺序，打开 Cost 五因子面板，青色路线会画在地面和地图上。",
	 "goal": "按一次 N", "kind": "key", "v": "N"},
	{"title": "5 / 7 · 取货", "desc": "走到订单商品的发光取货点 2 米内按 E。货架层板上摆着该商品的实体模型，按 NEXUS 官方 kind 建模。",
	 "goal": "成功取货 1 件", "kind": "pick", "n": 1},
	{"title": "6 / 7 · 进货", "desc": "按 B 打开进货面板，用批发价补库存；取货会消耗库存，卖光就得先补货。",
	 "goal": "进货 1 次", "kind": "restock", "n": 1},
	{"title": "7 / 7 · 交付收钱", "desc": "备齐订单后走到 Gate B 绿色出口按 F 交付，按零售价结算赚差价。加购推荐在订单面板里。",
	 "goal": "完成 1 笔订单", "kind": "deliver", "n": 1},
	{"title": "出师了 · R-07", "desc": "接单 → 看清单 → 规划 → 取货 → 交付 → 进货，整套循环你已经会了。奖励 ¥200，去做大生意吧。",
	 "goal": "点击「完成教程」", "kind": "done"},
]

# ---------------------------------------------------------------- 状态
var mode: Mode = Mode.MENU
var map: Dictionary = {}
var sys: NexusSystems
var font: SystemFont
var yaw := 0.0
var pitch := 0.22
var cam_dist := 5.8
var cam_height := 2.4
var anim_t := 0.0
var moving := false

var player: Node3D
var robot: Node3D
var cam: Camera3D
var npcs: Array = []
var npc_nodes: Array = []
var pickup_marks: Dictionary = {}
var pickup_labels: Array = []
var route_mi: MeshInstance3D
var route_nodes: Array = []
## v9.1 自动驾驶：沿规划 cells 行走，下一格受阻立即局部 A* 绕障。
var autopilot := false
var auto_path: Array = []
var auto_idx := 0
var replan_fail := 0
var wait_accum := 0.0

var toast_msg := ""
var toast_t := 0.0
var redraw_t := 0.0
var shot_pending := ""
var shot_frames := 0
var save_exists := false

var tutorial_on := false
var tut_step := 0
var tut_move := 0.0
var tut_look := 0.0
var tut_key := ""
var tut_picks := 0
var tut_delivers := 0
var tut_restocks := 0
var last_pos := Vector3.ZERO

var panel_name := ""
var know_tab := "cards"
var article_idx := 0
var quiz_idx := 0
var quiz_feedback := ""

# UI 层
var menu_layer: CanvasLayer
var help_layer: CanvasLayer
var pause_layer: CanvasLayer
var big_layer: CanvasLayer
var panel_layer: CanvasLayer
var tut_layer: CanvasLayer
var hud_layer: CanvasLayer
var menu_root: Control
var help_root: Control
var pause_root: Control
var big_root: Control
var panel_root: Control
var tut_root: Control
var hud_root: Control

var mini_map: NexusMapView
var big_map: NexusMapView
var menu_decor: NexusMapView
var menu_vbox: VBoxContainer
var menu_title: Label
var menu_sub: Label
var menu_footer: Label
var btn_continue: Button

var bg_order: ColorRect
var lbl_order: Label
var bg_stat: ColorRect
var lbl_stat: Label
var bg_guide: ColorRect
var lbl_guide: Label
var bg_tip: ColorRect
var lbl_tip: Label
var bg_prompt: ColorRect
var lbl_prompt: Label
var lbl_cross: Label
var lbl_toast: Label
var lbl_compass: Label

var lbl_big_title: Label
var lbl_big_order: Label
var lbl_big_legend: Label
var lbl_tut_title: Label
var lbl_tut_desc: Label
var lbl_tut_goal: Label
var tut_bar: ColorRect
var btn_tut_next: Button

var panel_title: Label
var panel_body: RichTextLabel
var panel_buttons: GridContainer
var manual_buttons: Array = []

# ================================================================ 启动
func _ready() -> void:
	load_map()
	if map.is_empty():
		push_error("data/nexus_map.json 读取失败")
		return
	NexusPalette.setup(map.palette)
	sys = NexusSystems.new()
	sys.setup(map)
	build_font()
	build_world()
	build_player()
	build_ui()
	check_save()
	set_mode(Mode.MENU)
	print("[NEXUS] READY 3rd-person | grid=56x48 free=%d products=%d kinds=%d racks=%d palette=%d article=%d" % [
		int(map.free), map.products.size(), _kind_count(), map.racks.size(),
		map.palette.size(), map.article.size()])
	var args := OS.get_cmdline_user_args()
	if args.has("--nexus-selftest"):
		start_game(false)
		run_selftest()
	elif args.has("--nexus-shot"):
		start_game(false)
		sys.plan_route(player.position, npcs)
		draw_route()
		shot_pending = "game"
	elif args.has("--nexus-shot-panel"):
		start_game(false)
		on_plan()
		shot_pending = "panel"
	elif args.has("--nexus-shot-map"):
		start_game(false)
		sys.plan_route(player.position, npcs)
		toggle_bigmap()
		shot_pending = "map"
	elif args.has("--nexus-shot-menu"):
		shot_pending = "menu"

func _kind_count() -> int:
	var s: Dictionary = {}
	for p in map.products:
		s[p.kind] = true
	return s.size()

func load_map() -> void:
	var f := FileAccess.open("res://data/nexus_map.json", FileAccess.READ)
	if f == null:
		return
	map = JSON.parse_string(f.get_as_text())

func build_font() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "Arial"])

func set_mode(m: Mode) -> void:
	mode = m
	menu_root.visible = (m == Mode.MENU)
	hud_root.visible = (m != Mode.MENU)
	big_root.visible = (m == Mode.BIGMAP)
	pause_root.visible = (m == Mode.PAUSED)
	panel_root.visible = (m == Mode.PANEL)
	tut_root.visible = (tutorial_on and m == Mode.PLAYING)
	help_root.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if m == Mode.PLAYING else Input.MOUSE_MODE_VISIBLE)
	if m == Mode.MENU:
		check_save()

# ================================================================ 3D 世界
func build_world() -> void:
	# 环境光 / 主光（NEXUS 暖白灰泥 + 浅灰石材）
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = NexusPalette.col("wall")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = NexusPalette.col("floor1")
	env.ambient_light_energy = .82
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, .97, .90)
	sun.light_energy = .92
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)

	# 原程序全套实体：地坪 / 吊顶灯带 / 29 货架（含 75 商品模型）/ 出入口 / 8 组装饰
	NexusScenery.build_all(self, map, font)
	build_obstacle_base()
	build_pickups()
	build_npcs()

func build_obstacle_base() -> void:
	# 1,058 个占用栅格用矮基座呈现（不遮挡第三人称镜头），颜色按官方材质
	var blocked: Array = []
	for r in range(ROWS):
		var row: String = str(map.grid[r])
		for c in range(COLS):
			if row[c] == "1":
				blocked.append(Vector2i(c, r))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = blocked.size()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, .55, 1)
	mm.mesh = bm
	var i := 0
	for b in blocked:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(-28 + b.x + .5, .275, -24 + b.y + .5)))
		var t: String = str(map.tiles[b.y])[b.x]
		var c := NexusPalette.col("wallDark")
		if t == "#": c = NexusPalette.col("wall")
		elif t == "S": c = NexusPalette.col("wood")
		elif t == "D": c = NexusPalette.col("slab")
		else:
			for z in map.zones:
				if z.id == t:
					c = Color.html(z.color).lerp(NexusPalette.col("counter"), .42)
		mm.set_instance_color(i, c)
		i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = .72
	mmi.material_override = m
	add_child(mmi)

func build_pickups() -> void:
	for idx in range(map.products.size()):
		var p: Dictionary = map.products[idx]
		var stand := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = .30
		cm.bottom_radius = .34
		cm.height = .10
		stand.mesh = cm
		stand.material_override = NexusPalette.mat("counter")
		stand.position = Vector3(float(p.x), .95, float(p.z))
		add_child(stand)

		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = .13
		sm.height = .26
		dot.mesh = sm
		var key := "cyan" if idx % 2 == 0 else "purple"
		var dm := StandardMaterial3D.new()
		dm.albedo_color = NexusPalette.col(key)
		dm.emission_enabled = true
		dm.emission = NexusPalette.col(key)
		dm.emission_energy_multiplier = .65
		dot.material_override = dm
		dot.position = Vector3(float(p.x), 1.14, float(p.z))
		add_child(dot)
		pickup_marks[p.id] = dot

		var l := Label3D.new()
		l.text = str(p.name)
		l.font = font
		l.font_size = 24
		l.pixel_size = .005
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = NexusPalette.col("signBack")
		l.position = Vector3(float(p.x), 1.52, float(p.z))
		l.visible = false
		add_child(l)
		pickup_labels.append(l)

func build_npcs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6143
	var kinds := ["customer", "customer", "staff", "cart", "customer", "box"]
	var spawn := Vector2(float(map.entry[0]) + 11.0, float(map.entry[1]) - 7.0)
	var placed := 0
	for tries in range(600):
		if placed >= 14:
			break
		var c := rng.randi_range(1, 54)
		var r := rng.randi_range(1, 46)
		if not sys.free_cell(c, r):
			continue
		var x := -28.0 + c + .5
		var z := -24.0 + r + .5
		if Vector2(x - spawn.x, z - spawn.y).length() < 7.0:
			continue
		var kind: String = kinds[placed % kinds.size()]
		var n := {"x": x, "z": z, "kind": kind, "a": rng.randf() * TAU, "sp": .0 if kind == "box" else .45 + rng.randf() * .35}
		npcs.append(n)
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = .20
		cm.height = 1.35
		mi.mesh = cm
		mi.material_override = NexusPalette.mat(
			"wallDark" if kind == "customer" else ("purple" if kind == "staff" else ("package" if kind == "box" else "silver")))
		mi.position = Vector3(x, .68, z)
		add_child(mi)
		npc_nodes.append(mi)
		placed += 1

func build_player() -> void:
	player = Node3D.new()
	player.name = "Player_R07"
	player.position = Vector3(float(map.entry[0]) + 11.0, 0.0, float(map.entry[1]) - 7.0)
	add_child(player)
	robot = NexusRobot.build()
	robot.scale = Vector3.ONE * 1.18
	player.add_child(robot)
	cam = Camera3D.new()
	cam.name = "ThirdPersonCamera"
	cam.fov = 68
	cam.current = true
	add_child(cam)
	update_camera()

func update_camera() -> void:
	var target := player.position + Vector3(0, 1.05, 0)
	var back := Vector3(-cos(yaw) * cos(pitch) * cam_dist, 0, -sin(yaw) * cos(pitch) * cam_dist)
	var shoulder := Vector3(-sin(yaw) * .75, 0, cos(yaw) * .75)
	var desired := target + back + shoulder + Vector3(0, cam_height + sin(pitch) * 2.4, 0)
	var d := desired - target
	var maxd := d.length()
	var used := maxd
	for i in range(1, 10):
		var t := float(i) / 10.0
		var q := target + d * t
		if not sys.free_cell(int(floor(q.x + 28.0)), int(floor(q.z + 24.0))):
			used = minf(used, maxd * t * .82)
			break
	used = clampf(used, 2.8, maxd)
	cam.position = target + d.normalized() * used
	cam.position.y = minf(cam.position.y, 3.15)
	cam.look_at(target)

func update_npcs(delta: float) -> void:
	# v9.0 P0：贴近时实体侧移让出栅格并继续推进（不再原地冻结仍占格）
	sys.step_yield(npcs, player.position, delta)
	for i in range(npcs.size()):
		var n: Dictionary = npcs[i]
		if n.kind == "box":
			continue
		if str(n.get("state", "")) == "让行":
			# 让行时只做侧移（step_yield 已处理），生命继续，不占栅格
			npc_nodes[i].position = Vector3(float(n.x), .68, float(n.z))
			continue
		var nx: float = float(n.x) + cos(float(n.a)) * float(n.sp) * delta
		var nz: float = float(n.z) + sin(float(n.a)) * float(n.sp) * delta
		if sys.free_cell(int(floor(nx + 28.0)), int(floor(nz + 24.0))):
			n.x = nx
			n.z = nz
		else:
			n.a = float(n.a) + 1.3
		npc_nodes[i].position = Vector3(float(n.x), .68, float(n.z))
	sys.risk = 0.0
	for n in npcs:
		var d := Vector2(float(n.x) - player.position.x, float(n.z) - player.position.z).length()
		if d < .55:
			sys.risk += sys.classify(n).R * .02
			sys.battery = maxf(0.0, sys.battery - .008)

# ================================================================ UI 基础
func rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func mklabel(size: int, c: Color) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = c
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func mkbutton(text: String, cb: Callable, w := 300.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 42)
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 15)
	var normal := StyleBoxFlat.new()
	normal.bg_color = NexusPalette.col("counter")
	normal.border_color = NexusPalette.col("cyan")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = NexusPalette.col("floor1")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = NexusPalette.col("cyan")
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", NexusPalette.col("signBack"))
	b.pressed.connect(cb)
	return b

func layer_root(layer: CanvasLayer) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	return root

func build_ui() -> void:
	menu_layer = CanvasLayer.new(); menu_layer.layer = 30; add_child(menu_layer); menu_root = layer_root(menu_layer)
	help_layer = CanvasLayer.new(); help_layer.layer = 28; add_child(help_layer); help_root = layer_root(help_layer)
	pause_layer = CanvasLayer.new(); pause_layer.layer = 26; add_child(pause_layer); pause_root = layer_root(pause_layer)
	panel_layer = CanvasLayer.new(); panel_layer.layer = 24; add_child(panel_layer); panel_root = layer_root(panel_layer)
	big_layer = CanvasLayer.new(); big_layer.layer = 22; add_child(big_layer); big_root = layer_root(big_layer)
	tut_layer = CanvasLayer.new(); tut_layer.layer = 20; add_child(tut_layer); tut_root = layer_root(tut_layer)
	hud_layer = CanvasLayer.new(); hud_layer.layer = 18; add_child(hud_layer); hud_root = layer_root(hud_layer)
	build_menu()
	build_help()
	build_pause()
	build_panel()
	build_bigmap()
	build_tutorial_ui()
	build_hud()
	for l in [lbl_order, lbl_stat, lbl_guide, lbl_tip, lbl_big_order, lbl_big_legend,
			lbl_tut_desc, lbl_tut_goal, menu_sub, menu_footer, lbl_toast, lbl_compass,
			help_root.get_node("HelpBody") as Label]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func panel_bg(c: Color) -> ColorRect:
	var r := rect(c)
	return r

func build_menu() -> void:
	var bg := panel_bg(NexusPalette.col("wall"))
	bg.name = "MenuBG"
	menu_root.add_child(bg)
	var band := panel_bg(NexusPalette.col("cyan"))
	band.name = "MenuBand"
	menu_root.add_child(band)
	menu_decor = NexusMapView.new()
	menu_decor.game = self
	menu_decor.big = true
	menu_decor.decorative = true
	menu_root.add_child(menu_decor)
	menu_title = mklabel(44, NexusPalette.col("signBack"))
	menu_title.text = "NEXUS 机器人经营 RPG"
	menu_root.add_child(menu_title)
	menu_sub = mklabel(17, NexusPalette.col("wallDark"))
	menu_sub.text = "第三人称 · NEXUS 官方实体建模与配色 · 56×48 m · 10 区 · 75 类商品"
	menu_root.add_child(menu_sub)
	menu_footer = mklabel(13, NexusPalette.col("wallDark"))
	menu_footer.text = "数据来自 INT6143 报告与 NEXUS 程序真源  |  Godot 4.3  |  单文件 exe"
	menu_root.add_child(menu_footer)
	menu_vbox = VBoxContainer.new()
	menu_vbox.add_theme_constant_override("separation", 11)
	menu_root.add_child(menu_vbox)
	menu_vbox.add_child(mkbutton("▶  开始游戏", start_game.bind(false)))
	menu_vbox.add_child(mkbutton("✦  从新手教程开始", start_game.bind(true)))
	btn_continue = mkbutton("↻  继续上次存档", continue_game)
	menu_vbox.add_child(btn_continue)
	menu_vbox.add_child(mkbutton("?  操作说明", show_help))
	menu_vbox.add_child(mkbutton("✕  退出游戏", quit_game))

func build_help() -> void:
	var bg := panel_bg(Color(.06, .12, .20, .55))
	bg.name = "HelpBG"
	help_root.add_child(bg)
	var p := panel_bg(NexusPalette.col("counter"))
	p.name = "HelpPanel"
	help_root.add_child(p)
	var t := mklabel(20, NexusPalette.col("signBack"))
	t.text = "操作说明 / HOW TO PLAY"
	t.name = "HelpTitle"
	help_root.add_child(t)
	var body := mklabel(15, NexusPalette.col("signBack"))
	body.text = ("WASD 移动   Shift 冲刺   鼠标 环绕视角   ESC 暂停\n" +
		"E 取货    F 在 Gate B 交付    B 进货面板    R 在 Gate A 充电\n" +
		"N 导航芯片 / Cost 面板    M 大地图    K 知识库    U 技能    Tab 订单    G 快速加购\n" +
		"V 自动导航：按规划路线自动行驶，遇阻立即局部 A* 绕障（再按 V 退出）\n\n" +
		"经营循环：接单 → 看清单 → 规划路线 → 取货 → Gate B 交付收钱 → 缺货按 B 进货 → 赚差价。\n" +
		"Cost = w₁D + w₂C + w₃T + w₄R + w₅H：D 距离(A*)、C 拥挤(K-means)、T 通行时间(回归)、\n" +
		"R 碰撞风险(决策树分类动态障碍)、H 处理成本(Pickup_Method)。加权边权见 §7.5。\n\n" +
		"运行时避障（NEXUS v9.1）：下一格 / 安全间距受阻即局部 A* 绕障；无可行绕路才短暂等待\n" +
		"0.6 s 重试，连续 5 次失败才报路段阻塞；双方贴近时让行实体侧移 0.7 m 并移出占用栅格。\n" +
		"取货后按 leg 重算剩余路线，终点不再连回中间点。几何、seed、S/T 口径、Cost 权重未改。\n\n" +
		"左上小地图，M 看全图。10 区 A–J、29 组货架、75 个取货点全部来自 NEXUS 程序真源。")
	body.name = "HelpBody"
	help_root.add_child(body)
	var close := mkbutton("返回", hide_help, 150.0)
	close.name = "HelpClose"
	help_root.add_child(close)
	help_root.visible = false

func build_pause() -> void:
	var bg := panel_bg(Color(.06, .12, .20, .45))
	bg.name = "PauseBG"
	pause_root.add_child(bg)
	var p := panel_bg(NexusPalette.col("counter"))
	p.name = "PausePanel"
	pause_root.add_child(p)
	var t := mklabel(24, NexusPalette.col("signBack"))
	t.text = "暂停 / PAUSED"
	t.name = "PauseTitle"
	pause_root.add_child(t)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.name = "PauseButtons"
	pause_root.add_child(vb)
	vb.add_child(mkbutton("▶  继续游戏", resume_game, 250.0))
	vb.add_child(mkbutton("⌂  返回主界面", return_to_menu, 250.0))
	vb.add_child(mkbutton("✕  退出游戏", quit_game, 250.0))

func build_panel() -> void:
	var bg := panel_bg(Color(.06, .12, .20, .50))
	bg.name = "PanelBG"
	panel_root.add_child(bg)
	var p := panel_bg(NexusPalette.col("counter"))
	p.name = "PanelBox"
	panel_root.add_child(p)
	panel_title = mklabel(22, NexusPalette.col("signBack"))
	panel_title.name = "PanelTitle"
	panel_root.add_child(panel_title)
	panel_body = RichTextLabel.new()
	panel_body.bbcode_enabled = true
	panel_body.scroll_active = true
	panel_body.add_theme_font_override("normal_font", font)
	panel_body.add_theme_font_size_override("normal_font_size", 15)
	panel_body.add_theme_color_override("default_color", NexusPalette.col("signBack"))
	panel_root.add_child(panel_body)
	panel_buttons = GridContainer.new()
	panel_buttons.columns = 3
	panel_buttons.add_theme_constant_override("h_separation", 10)
	panel_buttons.add_theme_constant_override("v_separation", 8)
	panel_root.add_child(panel_buttons)
	var close := mkbutton("关闭  [ESC]", close_panel, 180.0)
	close.name = "PanelClose"
	panel_root.add_child(close)

func build_bigmap() -> void:
	var bg := panel_bg(Color(.06, .12, .20, .55))
	bg.name = "BigBG"
	big_root.add_child(bg)
	var p := panel_bg(NexusPalette.col("counter"))
	p.name = "BigPanel"
	big_root.add_child(p)
	lbl_big_title = mklabel(20, NexusPalette.col("signBack"))
	lbl_big_title.text = "NEXUS 卖场全图 · 56 × 48 m · 1,630 可通行单元"
	big_root.add_child(lbl_big_title)
	big_map = NexusMapView.new()
	big_map.game = self
	big_map.big = true
	big_root.add_child(big_map)
	lbl_big_order = mklabel(13, NexusPalette.col("signBack"))
	big_root.add_child(lbl_big_order)
	lbl_big_legend = mklabel(13, NexusPalette.col("wallDark"))
	lbl_big_legend.text = ("图例\n■ 深蓝灰 = 固定障碍 / 墙体\n■ 彩色 = 10 区货架\n" +
		"■ 红 / 橙 = 高 / 中拥挤通道（K-means）\n● 橙点 = 订单目标（已取变绿）\n" +
		"● 灰点 = 75 个取货点\n— 青线 = A* / BFS 路线\n▲ 深蓝箭头 = 机器人\n■ 青门 = Gate A · 橙门 = Gate B")
	big_root.add_child(lbl_big_legend)
	var close := mkbutton("关闭大地图  [M]", toggle_bigmap, 220.0)
	close.name = "BigClose"
	big_root.add_child(close)

func build_tutorial_ui() -> void:
	var bg := panel_bg(NexusPalette.col("counter"))
	bg.name = "TutBG"
	tut_root.add_child(bg)
	var edge := panel_bg(NexusPalette.col("cyan"))
	edge.name = "TutEdge"
	tut_root.add_child(edge)
	lbl_tut_title = mklabel(19, NexusPalette.col("signBack"))
	tut_root.add_child(lbl_tut_title)
	lbl_tut_desc = mklabel(15, NexusPalette.col("signBack"))
	tut_root.add_child(lbl_tut_desc)
	lbl_tut_goal = mklabel(14, NexusPalette.col("gateB"))
	tut_root.add_child(lbl_tut_goal)
	tut_bar = panel_bg(NexusPalette.col("cyan"))
	tut_root.add_child(tut_bar)
	var skip := mkbutton("跳过教程", skip_tutorial, 130.0)
	skip.name = "TutSkip"
	tut_root.add_child(skip)
	btn_tut_next = mkbutton("完成教程  +¥200", finish_tutorial, 190.0)
	btn_tut_next.name = "TutNext"
	tut_root.add_child(btn_tut_next)
	update_tutorial_ui()

func build_hud() -> void:
	var panel_c := Color(NexusPalette.col("counter").r, NexusPalette.col("counter").g,
			NexusPalette.col("counter").b, .97)
	bg_order = rect(panel_c); hud_root.add_child(bg_order)
	lbl_order = mklabel(14, NexusPalette.col("signBack")); hud_root.add_child(lbl_order)
	bg_stat = rect(panel_c); hud_root.add_child(bg_stat)
	lbl_stat = mklabel(14, NexusPalette.col("signBack")); hud_root.add_child(lbl_stat)
	bg_guide = rect(panel_c); hud_root.add_child(bg_guide)
	lbl_guide = mklabel(14, NexusPalette.col("signBack")); hud_root.add_child(lbl_guide)
	bg_tip = rect(panel_c); hud_root.add_child(bg_tip)
	lbl_tip = mklabel(13, NexusPalette.col("wallDark")); hud_root.add_child(lbl_tip)
	bg_prompt = rect(panel_c); hud_root.add_child(bg_prompt)
	lbl_prompt = mklabel(16, NexusPalette.col("cyan")); hud_root.add_child(lbl_prompt)
	lbl_cross = mklabel(20, NexusPalette.col("cyan")); hud_root.add_child(lbl_cross)
	lbl_toast = mklabel(18, NexusPalette.col("gateB")); hud_root.add_child(lbl_toast)
	lbl_compass = mklabel(20, NexusPalette.col("signBack")); hud_root.add_child(lbl_compass)
	mini_map = NexusMapView.new()
	mini_map.game = self
	hud_root.add_child(mini_map)
	var cap := mklabel(12, NexusPalette.col("wallDark"))
	cap.text = "▌ NEXUS 56×48 · 按 M 看大地图"
	cap.name = "MiniCaption"
	hud_root.add_child(cap)

# ================================================================ 布局
func layout_ui() -> void:
	var vs := get_viewport().get_visible_rect().size
	_set_size(menu_root.get_node("MenuBG"), vs)
	(menu_root.get_node("MenuBand") as ColorRect).size = Vector2(vs.x, 8)
	menu_title.position = Vector2(70, 92)
	menu_title.size = Vector2(vs.x - 140, 60)
	menu_sub.position = Vector2(72, 158)
	menu_sub.size = Vector2(vs.x - 620, 34)
	menu_footer.position = Vector2(72, vs.y - 52)
	menu_footer.size = Vector2(vs.x - 140, 30)
	menu_vbox.position = Vector2(70, 226)
	menu_decor.position = Vector2(vs.x - 520, 130)
	menu_decor.size = Vector2(460, 380)

	_set_size(help_root.get_node("HelpBG"), vs)
	var hp := help_root.get_node("HelpPanel") as ColorRect
	hp.position = Vector2(vs.x * .5 - 390, vs.y * .5 - 230)
	hp.size = Vector2(780, 460)
	(help_root.get_node("HelpTitle") as Label).position = hp.position + Vector2(28, 20)
	(help_root.get_node("HelpBody") as Label).position = hp.position + Vector2(28, 66)
	(help_root.get_node("HelpBody") as Label).size = Vector2(724, 330)
	(help_root.get_node("HelpClose") as Button).position = hp.position + Vector2(580, 390)

	_set_size(pause_root.get_node("PauseBG"), vs)
	var pp := pause_root.get_node("PausePanel") as ColorRect
	pp.position = Vector2(vs.x * .5 - 175, vs.y * .5 - 160)
	pp.size = Vector2(350, 320)
	(pause_root.get_node("PauseTitle") as Label).position = pp.position + Vector2(70, 24)
	(pause_root.get_node("PauseButtons") as VBoxContainer).position = pp.position + Vector2(50, 86)

	var pw := minf(vs.x - 80, 1180.0)
	var ph := minf(vs.y - 70, 790.0)
	var px := (vs.x - pw) / 2.0
	var py := (vs.y - ph) / 2.0
	_set_size(big_root.get_node("BigBG"), vs)
	var bp := big_root.get_node("BigPanel") as ColorRect
	bp.position = Vector2(px, py)
	bp.size = Vector2(pw, ph)
	lbl_big_title.position = Vector2(px + 24, py + 14)
	var mw := pw * .68
	big_map.position = Vector2(px + 20, py + 52)
	big_map.size = Vector2(mw, ph - 96.0)
	lbl_big_order.position = Vector2(px + mw + 44, py + 60)
	lbl_big_order.size = Vector2(pw - mw - 70, 280)
	lbl_big_legend.position = Vector2(px + mw + 44, py + 410)
	lbl_big_legend.size = Vector2(pw - mw - 70, 170)
	(big_root.get_node("BigClose") as Button).position = Vector2(px + mw + 44, py + ph - 66)

	# 通用面板
	_set_size(panel_root.get_node("PanelBG"), vs)
	var boxp := panel_root.get_node("PanelBox") as ColorRect
	boxp.position = Vector2(px, py)
	boxp.size = Vector2(pw, ph)
	panel_title.position = Vector2(px + 26, py + 16)
	panel_body.position = Vector2(px + 26, py + 58)
	panel_body.size = Vector2(pw - 52, ph - 230)
	var bw := (pw - 52) / 3.0
	for i in range(manual_buttons.size()):
		var b: Button = manual_buttons[i]
		b.position = Vector2(px + 26 + (i % 3) * bw, py + ph - 168 + int(i / 3) * 50)
		b.size = Vector2(bw - 12, 42)
	(panel_root.get_node("PanelClose") as Button).position = Vector2(px + pw - 210, py + 16)

	var tw := minf(vs.x - 80, 620.0)
	var tx := (vs.x - tw) / 2.0
	var ty := vs.y - 236
	(tut_root.get_node("TutBG") as ColorRect).position = Vector2(tx, ty)
	(tut_root.get_node("TutBG") as ColorRect).size = Vector2(tw, 150)
	(tut_root.get_node("TutEdge") as ColorRect).position = Vector2(tx, ty)
	(tut_root.get_node("TutEdge") as ColorRect).size = Vector2(5, 150)
	lbl_tut_title.position = Vector2(tx + 20, ty + 12)
	lbl_tut_desc.position = Vector2(tx + 20, ty + 42)
	lbl_tut_desc.size = Vector2(tw - 40, 54)
	lbl_tut_goal.position = Vector2(tx + 20, ty + 100)
	tut_bar.position = Vector2(tx + 20, ty + 140)
	(tut_root.get_node("TutSkip") as Button).position = Vector2(tx + tw - 150, ty + 12)
	btn_tut_next.position = Vector2(tx + tw - 220, ty + 94)

	mini_map.position = Vector2(18, 18)
	mini_map.size = Vector2(224, 192)
	(hud_root.get_node("MiniCaption") as Label).position = Vector2(20, 210)
	bg_order.position = Vector2(18, 234); bg_order.size = Vector2(224, 190)
	lbl_order.position = Vector2(28, 242); lbl_order.size = Vector2(206, 176)
	bg_stat.position = Vector2(vs.x - 268, 18); bg_stat.size = Vector2(250, 160)
	lbl_stat.position = Vector2(vs.x - 258, 26); lbl_stat.size = Vector2(230, 146)
	bg_guide.position = Vector2(vs.x - 320, vs.y - 250); bg_guide.size = Vector2(302, 182)
	lbl_guide.position = Vector2(vs.x - 310, vs.y - 242); lbl_guide.size = Vector2(282, 168)
	bg_tip.position = Vector2(18, vs.y - 62); bg_tip.size = Vector2(vs.x - 36, 44)
	lbl_tip.position = Vector2(30, vs.y - 52); lbl_tip.size = Vector2(vs.x - 60, 30)
	bg_prompt.position = Vector2(vs.x * .5 - 200, vs.y - 132); bg_prompt.size = Vector2(400, 48)
	lbl_prompt.position = Vector2(vs.x * .5 - 188, vs.y - 122); lbl_prompt.size = Vector2(376, 32)
	lbl_cross.position = Vector2(vs.x * .5 - 7, vs.y * .5 - 14)
	lbl_toast.position = Vector2(vs.x * .5 - 260, 92); lbl_toast.size = Vector2(520, 34)
	lbl_compass.position = Vector2(vs.x * .5 - 190, 56); lbl_compass.size = Vector2(380, 32)

func _set_size(node: Node, s: Vector2) -> void:
	if node is Control:
		(node as Control).size = s

# ================================================================ 主循环
func _process(delta: float) -> void:
	if map.is_empty():
		return
	anim_t += delta
	toast_t -= delta
	if shot_pending != "":
		shot_frames += 1
		if shot_frames >= 8:
			var which := shot_pending
			shot_pending = ""
			take_shot(which)
	layout_ui()
	if mode == Mode.PLAYING:
		sys.tick(delta)
		if sys.pending_day:
			sys.pending_day = false
			open_panel("day")
		move_player(delta)
		update_npcs(delta)
		NexusRobot.animate(robot, moving, anim_t, sys.cargo.size())
		robot.rotation.y = PI / 2 - yaw
		update_camera()
		if tutorial_on:
			check_tutorial(delta)
		update_hud()
	redraw_t += delta
	if redraw_t > .16:
		redraw_t = 0.0
		for i in range(pickup_labels.size()):
			var p: Dictionary = map.products[i]
			var d := Vector2(player.position.x - float(p.x), player.position.z - float(p.z)).length()
			pickup_labels[i].visible = int(sys.stock[p.id]) > 0 and d < 14.0
		for pid in pickup_marks:
			pickup_marks[pid].visible = int(sys.stock[pid]) > 0
		mini_map.queue_redraw()
		if mode == Mode.BIGMAP:
			big_map.queue_redraw()
		if mode == Mode.MENU:
			menu_decor.queue_redraw()

func _input(event: InputEvent) -> void:
	if map.is_empty():
		return
	if event is InputEventMouseMotion and mode == Mode.PLAYING and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw += event.relative.x * .0024
		pitch = clampf(pitch - event.relative.y * .0018, -.10, .78)
		if tutorial_on:
			tut_look += absf(event.relative.x) + absf(event.relative.y)
	if event is InputEventMouseButton and event.pressed and mode == Mode.PLAYING:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k == KEY_ESCAPE:
			if mode == Mode.PLAYING: set_mode(Mode.PAUSED)
			elif mode == Mode.PAUSED or mode == Mode.BIGMAP or mode == Mode.PANEL: set_mode(Mode.PLAYING)
			elif help_root.visible: hide_help()
			return
		if k == KEY_M:
			if mode == Mode.PLAYING or mode == Mode.BIGMAP:
				toggle_bigmap()
			if tutorial_on: tut_key = "M"
			return
		if mode != Mode.PLAYING:
			return
		if k == KEY_E: do_pick()
		elif k == KEY_F: do_deliver()
		elif k == KEY_B:
			open_panel("restock")
			if tutorial_on: tut_key = "B"
		elif k == KEY_N:
			on_plan()
			if tutorial_on: tut_key = "N"
		elif k == KEY_R: do_charge()
		elif k == KEY_K: open_panel("knowledge")
		elif k == KEY_U: open_panel("skills")
		elif k == KEY_TAB: open_panel("orders")
		elif k == KEY_G: quick_upsell()
		elif k == KEY_V: toggle_autopilot()

# ================================================================ 移动
func move_player(delta: float) -> void:
	# v9.1：自动驾驶沿规划 cells 行走；下一格被动态实体占用 → 立即局部 A* 绕障
	if autopilot:
		move_autopilot(delta)
		return
	var f := 0.0
	var s := 0.0
	if Input.is_key_pressed(KEY_W): f += 1.0
	if Input.is_key_pressed(KEY_S): f -= 1.0
	if Input.is_key_pressed(KEY_D): s += 1.0
	if Input.is_key_pressed(KEY_A): s -= 1.0
	if f == 0.0 and s == 0.0:
		moving = false
		return
	moving = true
	var fwd := Vector3(cos(yaw), 0, sin(yaw))
	var right := Vector3(-sin(yaw), 0, cos(yaw))
	var dir := (fwd * f + right * s).normalized()
	step_player(dir, delta, false)

func step_player(dir: Vector3, delta: float, auto: bool) -> void:
	var cc := int(floor(player.position.x + 28.0))
	var rr := int(floor(player.position.z + 24.0))
	var cl := sys.eff_cong(cc, rr)
	var sp := (5.0 if Input.is_key_pressed(KEY_SHIFT) else 3.2) * (1.0 + float(sys.skills.speed) * .13)
	if cl == 3: sp *= .74
	elif cl == 2: sp *= .90
	var dx := dir.x * sp * delta
	var dz := dir.z * sp * delta
	var pos := player.position
	if sys.free_cell(int(floor(pos.x + dx + 28.0)), int(floor(pos.z + 24.0))):
		pos.x += dx
	if sys.free_cell(int(floor(pos.x + 28.0)), int(floor(pos.z + dz + 24.0))):
		pos.z += dz
	player.position = pos
	var step := Vector2(dx, dz).length()
	sys.meters += step
	sys.battery = maxf(0.0, sys.battery - step * (.055 + cl * .012)
			* (1.45 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
			* (1.0 - float(sys.skills.eco) * .14))

func move_autopilot(delta: float) -> void:
	if auto_path.is_empty():
		autopilot = false
		moving = false
		return
	if auto_idx >= auto_path.size():
		autopilot = false
		moving = false
		toast("自动导航完成 · 已抵达目标")
		return
	var here := Vector2i(int(floor(player.position.x + 28.0)), int(floor(player.position.z + 24.0)))
	var target_cell: Vector2i = auto_path[auto_idx]
	if here == target_cell:
		auto_idx += 1
		if auto_idx >= auto_path.size():
			autopilot = false; moving = false
			toast("自动导航完成 · 已抵达目标")
			return
		target_cell = auto_path[auto_idx]
	var tx := float(target_cell.x) - 28.0 + .5
	var tz := float(target_cell.y) - 24.0 + .5
	var to := Vector2(tx - player.position.x, tz - player.position.z)
	if to.length() < .05:
		return
	var dir := Vector3(to.x, 0, to.y).normalized()
	# 预测下一格；被动态实体占用 → 立即局部 A* 绕障（v9.0/v9.1 核心）
	var nx := int(floor(player.position.x + dir.x * .45 + 28.0))
	var nz := int(floor(player.position.z + dir.z * .45 + 24.0))
	var dyn := sys.dynamic_cells(npcs)
	if dyn.has(nz * 56 + nx) and not (nx == target_cell.x and nz == target_cell.y):
		var rg := sys.risk_grid(npcs)
		var det = sys.local_detour(here, target_cell, rg, dyn)
		if not det.cells.is_empty():
			# 用绕行 cells 替换剩余路径（v9.0：段切换重绘，不回连中间点）
			auto_path = auto_path.slice(0, auto_idx) + det.cells
			auto_idx += 1
			replan_fail = 0; wait_accum = 0.0
			redraw_auto_route()
			toast(sys.last_avoid)
		else:
			# 局部绕路暂不可达 → 短暂等待后重试（replanRetryS / maxReplanFailures）
			wait_accum += delta
			sys.wait_s += delta
			if wait_accum >= NexusSystems.REPLAN_RETRY_S:
				wait_accum = 0.0
				sys.replans += 1
				replan_fail += 1
				if replan_fail >= NexusSystems.MAX_REPLAN_FAILURES:
					autopilot = false
					toast("连续 %d 次局部 A* 重规划仍不可达 · 请手动绕行" % replan_fail)
			return
		moving = false
		return
	replan_fail = 0
	yaw = atan2(dir.z, dir.x)
	moving = true
	step_player(dir, delta, true)

func redraw_auto_route() -> void:
	if auto_path.size() < 2:
		return
	var cells: Array = []
	for c in auto_path:
		cells.append(Vector2i(int(c.x), int(c.y)))
	sys.plan.cells = cells
	draw_route()

func toggle_autopilot() -> void:
	if autopilot:
		autopilot = false
		moving = false
		toast("已退出自动导航")
		return
	if sys.plan.is_empty() or not sys.plan.has("cells"):
		toast("请先按 N 规划路线再开自动导航")
		return
	auto_path = []
	for c in sys.plan.cells:
		auto_path.append(Vector2i(int(c.x), int(c.y)))
	auto_idx = 0
	replan_fail = 0
	wait_accum = 0.0
	autopilot = true
	toast("自动导航启动 · 按 V 退出 · 遇阻立即局部 A* 绕障")

# ================================================================ 交互
func near_product():
	var best = null
	var d0 := 2.0
	for p in map.products:
		var d := Vector2(player.position.x - float(p.x), player.position.z - float(p.z)).length()
		if d < d0:
			d0 = d
			best = p
	return best

func near_gate_a() -> bool:
	return Vector2(player.position.x - float(map.entry[0]) - .5,
			player.position.z - float(map.entry[1]) - .5).length() < 3.0

func near_gate_b() -> bool:
	return Vector2(player.position.x - float(map.exit[0]) - .5,
			player.position.z - float(map.exit[1]) - .5).length() < 2.5

func do_pick() -> void:
	var p = near_product()
	if p == null:
		toast("靠近发光取货点 2 米内才能取货")
		return
	var res := sys.pick(p.id)
	if res.ok:
		tut_picks += 1
		# v9.0：段切换（取货完成）触发路线重绘，避免取了一两件后路线消失
		sys.leg_index += 1
		if not autopilot:
			draw_route()
	toast(res.msg)

func do_deliver() -> void:
	if not near_gate_b():
		toast("请走到 Gate B 绿色出口交付")
		return
	var res := sys.deliver()
	if res.ok:
		tut_delivers += 1
		draw_route()
	toast(res.msg)

func do_charge() -> void:
	var res := sys.charge(near_gate_a())
	toast(res.msg)

func quick_upsell() -> void:
	for o in sys.orders:
		for i in range(o.upsells.size()):
			if not o.upsells[i].done:
				var res := sys.upsell(o.id, i)
				toast(res.msg)
				return
	toast("当前没有可用的关联加购推荐")

func draw_route() -> void:
	for rn in route_nodes:
		if is_instance_valid(rn): rn.queue_free()
	route_nodes.clear()
	if not sys.plan.has("cells") or sys.plan.cells.size() < 2:
		return
	# v9.0：段之间若非相邻格（绕障替换 / 段切换），断开重画，杜绝斜线连回中间点
	var im := ImmediateMesh.new()
	var started := false
	var prev: Vector2i = Vector2i(-99, -99)
	for c in sys.plan.cells:
		var cur := Vector2i(int(c.x), int(c.y))
		var adj := absi(cur.x - prev.x) + absi(cur.y - prev.y) == 1
		if not started or not adj:
			if started: im.surface_end()
			im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			started = true
		im.surface_add_vertex(Vector3(-28 + cur.x + .5, .16, -24 + cur.y + .5))
		prev = cur
	if started: im.surface_end()
	route_mi = MeshInstance3D.new()
	route_nodes.append(route_mi)
	route_mi.mesh = im
	var m := StandardMaterial3D.new()
	m.albedo_color = NexusPalette.col("cyan")
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = NexusPalette.col("cyan")
	m.emission_energy_multiplier = .8
	route_mi.material_override = m
	add_child(route_mi)

func on_plan() -> void:
	var pl := sys.plan_route(player.position, npcs)
	if pl.is_empty():
		toast("暂无可规划的订单")
		return
	draw_route()
	toast("路线 %d m · Cost %.1f · ETA %d s" % [int(pl.D), pl.cost, int(pl.eta)])
	open_panel("nav")

func toast(s: String) -> void:
	toast_msg = s
	toast_t = 3.4

# ================================================================ 菜单 / 状态
func start_game(with_tutorial: bool) -> void:
	sys.reset()
	yaw = 0.0
	pitch = .22
	player.position = Vector3(float(map.entry[0]) + 11.0, 0.0, float(map.entry[1]) - 7.0)
	if route_mi != null and is_instance_valid(route_mi):
		route_mi.queue_free()
	tutorial_on = with_tutorial
	if with_tutorial:
		tut_step = 0
		reset_tut_vars()
		update_tutorial_ui()
	set_mode(Mode.PLAYING)
	toast("R-07 上线 · 第三人称视角 · M 大地图 / N 导航 / Tab 订单")

func continue_game() -> void:
	load_game()
	tutorial_on = false
	set_mode(Mode.PLAYING)
	toast("存档已恢复 · 第 %d 天 · %s" % [sys.day, sys.fmt(sys.money)])

func resume_game() -> void:
	set_mode(Mode.PLAYING)

func return_to_menu() -> void:
	save_game()
	set_mode(Mode.MENU)

func quit_game() -> void:
	if mode != Mode.MENU:
		save_game()
	get_tree().quit()

func toggle_bigmap() -> void:
	if mode == Mode.PLAYING:
		set_mode(Mode.BIGMAP)
		update_big_order()
	elif mode == Mode.BIGMAP:
		set_mode(Mode.PLAYING)

func show_help() -> void:
	help_root.visible = true

func hide_help() -> void:
	help_root.visible = false

func open_panel(name: String) -> void:
	panel_name = name
	set_mode(Mode.PANEL)
	render_panel()

func close_panel() -> void:
	set_mode(Mode.PLAYING)

# ================================================================ 面板
func clear_buttons() -> void:
	for b in manual_buttons:
		if is_instance_valid(b):
			panel_root.remove_child(b)
			b.free()
	manual_buttons.clear()

func add_button(text: String, cb: Callable, w := 240.0) -> void:
	var b := mkbutton(text, cb, w)
	panel_root.add_child(b)
	manual_buttons.append(b)

func render_panel() -> void:
	clear_buttons()
	match panel_name:
		"orders": render_orders()
		"restock": render_restock()
		"nav": render_nav()
		"skills": render_skills()
		"knowledge": render_knowledge()
		"day": render_day()
		"help": render_help_panel()

func bb(s: String) -> String:
	return "[color=#%s]%s[/color]" % [NexusPalette.P.signBack.trim_prefix("#"), s]

func render_orders() -> void:
	panel_title.text = "订单队列 / ORDER QUEUE"
	var t := "[b]资金 %s · 声望 %.1f ★ · 货舱 %d/%d · 第 %d 天 %s（%s）[/b]\n\n" % [
		sys.fmt(sys.money), sys.rep, sys.cargo.size(), sys.cap(), sys.day,
		sys.clock_str(sys.clock), sys.period]
	for o in sys.orders:
		t += "[b]%s  %s  → %s   剩余 %d s[/b]\n" % [o.id, o.client, sys.fmt(o.pay), int(o.deadline - sys.clock)]
		for it in o.items:
			t += "  %s  [%s 区 · %s]  已取 %d/%d  库存 %d  H=%s\n" % [
				it.name, it.zone, it.rack, it.got, it.qty, int(sys.stock[it.id]), str(it.H)]
		for n in sys.compat(o.items):
			t += "  [%s] %s\n" % [n.t, n.s]
		for i in range(o.upsells.size()):
			var u: Dictionary = o.upsells[i]
			t += "  ▸ Apriori 推荐 %s  conf=%.2f lift=%.2f  %s\n" % [
				sys.find_product(u.pid).name, float(u.rule.conf), float(u.rule.lift),
				"已加购" if u.done else "待推荐"]
			if not u.done:
				add_button("加购 %s +%s" % [sys.find_product(u.pid).name, sys.fmt(u.extra)],
						on_upsell.bind(o.id, i), 260.0)
		add_button("规划 " + o.id, on_plan_order.bind(o.id), 200.0)
		t += "\n"
	t += "\n提示：靠近取货点按 [E]，齐货后到 Gate B 按 [F]；[G] 快速加购。"
	panel_body.text = t

func render_restock() -> void:
	panel_title.text = "批发进货终端 / RESTOCK"
	var t := "[b]资金 %s · 当前时段 %s（高峰 +14%% / 低峰 -9%%）[/b]\n" % [sys.fmt(sys.money), sys.period]
	t += "批发价 = 零售价 × 62% × 市场系数；Gate A 附近进货 -8%%（%s）\n\n" % ("生效" if near_gate_a() else "未生效")
	var ids: Array = []
	for o in sys.orders:
		for it in o.items:
			if not ids.has(it.id):
				ids.append(it.id)
	for pid in ids.slice(0, 6):
		var p: Dictionary = sys.find_product(pid)
		var unit := int(ceil(float(p.wholesale) * sys.market(pid, near_gate_a())))
		t += "%s  [%s 区]  零售 %s / 批发 %s  库存 %d\n" % [
			p.name, p.zone, sys.fmt(p.retail), sys.fmt(unit), int(sys.stock[pid])]
		add_button("%s  +1" % p.short, on_restock.bind(pid, 1), 190.0)
		add_button("%s  +3" % p.short, on_restock.bind(pid, 3), 190.0)
	t += "\n[color=#8B7CFF]其余 69 类商品可在取货点旁按 B 就近补货（会自动选最近商品）。[/color]"
	panel_body.text = t
	add_button("全部订单商品 +1", on_restock_all, 220.0)

func render_nav() -> void:
	panel_title.text = "AI 导航芯片 · Cost = w₁D + w₂C + w₃T + w₄R + w₅H"
	if sys.plan.is_empty():
		sys.plan_route(player.position, npcs)
		draw_route()
	if sys.plan.is_empty():
		panel_body.text = "暂无规划。"
		return
	var t := "[b]订单 %s · Held–Karp 精确排序[/b]\n" % sys.plan.oid
	t += "取货顺序："
	for pid in sys.plan.seq:
		t += "%s → " % sys.find_product(pid).name
	t += "Gate B(交付)\n"
	t += "拼接路径 %d m · A* 扩展 %d 节点 · 距离矩阵扩展 %d · ETA %d s\n\n" % [
		int(sys.plan.D), int(sys.plan.expanded), int(sys.plan.matrix_exp), int(sys.plan.eta)]
	t += "[b]综合成本分解（§4.6 / §7.5）[/b]   边权：%s\n" % ("加权 Cost" if sys.weighted else "单位距离 1 m")
	t += "Cost = 1·D + 0.6·C + 0.4·T + 0.5·R + 0.3·H = [b]%.1f[/b]\n\n" % sys.plan.cost
	for p in sys.plan.parts:
		t += "%s  %-18s 值 %8.2f  权重 %.1f  贡献 %8.2f   [%s]\n" % [
			p.k, p.n, float(p.v), float(p.w), float(p.c), p.src]
	t += "\n[b]四算法对照（同一地图 / 同一清单 / 同一起终点）[/b]\n"
	for c in sys.algo_compare(player.position, npcs):
		t += "%-10s 长度 %4d m   扩展 %5d 节点   覆盖率 %s%%\n" % [
			c.name, int(c.length), int(c.expanded), c.cover]
	t += "\n§8.5 程序实测：个人电竞 9 件清单 192 m → 162 m（-15.6%），A* 705 节点 / Dijkstra·BFS 3468 / Greedy 413 但 236 m。"
	t += "\n\n\n[b]运行时避障 · NEXUS v9.1[/b]   策略：下一格受阻 → 立即局部 A* 绕障\n"
	t += "参数 replanRetryS = %.1f s · maxReplanFailures = %d · 让行侧移 %.1f m\n" % [
		NexusSystems.REPLAN_RETRY_S, NexusSystems.MAX_REPLAN_FAILURES, NexusSystems.YIELD_SIDE_M]
	t += "局部绕障 %d 次 · 重规划 %d 次 · 等待 %.1f s · 累计让行 %d 次 · 段切换 %d\n" % [
		sys.detours, sys.replans, sys.wait_s, sys.yield_count, sys.leg_index]
	t += "状态：%s\n" % ("自动导航运行中 · 按 V 退出" if autopilot else "手动驾驶 · 按 V 沿路线自动行驶")
	t += "v9.1 P0：让行实体沿垂直方向侧移并移出 dynamicBlocked，窄通道不再互锁。\n"
	t += "最近事件：%s" % (sys.last_avoid if sys.last_avoid != "" else "暂无绕障")
	panel_body.text = t
	add_button("加权 Cost 导航：" + ("开" if sys.weighted else "关"), on_weighted, 250.0)
	for m in ["astar", "dijkstra", "greedy", "bfs"]:
		add_button("切换 " + m.to_upper(), on_algo.bind(m), 160.0)
	add_button("重新规划", on_plan, 160.0)
	add_button("自动导航 V：" + ("关" if autopilot else "开"), on_autopilot_btn, 200.0)

func render_skills() -> void:
	panel_title.text = "机体升级 / RPG SKILLS"
	var t := "[b]LV.%d · EXP %d / %d · 可用技能点 %d[/b]\n" % [
		sys.level, int(sys.exp), int(sys.need_exp()), sys.pts]
	t += "声望 %.1f ★ · 累计交付 %d 单 · 超时 %d 单 · 行驶 %.0f m\n\n" % [
		sys.rep, sys.delivered, sys.failed, sys.meters]
	for s in NexusSystems.SKILL_DEF:
		t += "%-12s LV %d/%d   %s\n" % [s.n, int(sys.skills[s.k]), int(s.max), s.d]
		add_button("升级 " + str(s.n), on_skill.bind(s.k), 220.0)
	panel_body.text = t

func render_knowledge() -> void:
	panel_title.text = "NEXUS 知识终端 · 报告全文 / 四大概念 / 考核"
	var t := ""
	if know_tab == "cards":
		for k in map.knowledge:
			t += "[b]%s  %s[/b]\n%s\n\n" % [k.tag, k.title, k.text]
		add_button("报告全文 →", on_know_tab.bind("article"), 200.0)
		add_button("知识考核 →", on_know_tab.bind("quiz"), 200.0)
	elif know_tab == "article":
		var sec: Dictionary = map.article[article_idx]
		t += "[b]%d / %d  %s[/b]\n\n" % [article_idx + 1, map.article.size(), sec.title]
		for para in sec.paras.slice(0, 8):
			t += str(para) + "\n\n"
		add_button("上一节", on_article.bind(-1), 150.0)
		add_button("下一节", on_article.bind(1), 150.0)
		add_button("知识卡", on_know_tab.bind("cards"), 150.0)
	else:
		var q: Dictionary = map.quiz[quiz_idx]
		t += "[b]Q%d. %s[/b]\n\n" % [quiz_idx + 1, q.q]
		for j in range(q.o.size()):
			t += "  %s. %s\n" % [String.chr(65 + j), q.o[j]]
		if quiz_feedback != "":
			t += "\n[color=#C26A00]%s[/color]\n" % quiz_feedback
		t += "\n已答对 %d / %d 题\n" % [sys.quiz_done.size(), map.quiz.size()]
		for j in range(q.o.size()):
			add_button(String.chr(65 + j) + ". " + str(q.o[j]), on_quiz.bind(quiz_idx, j), 300.0)
		add_button("下一题", on_quiz_next, 150.0)
		add_button("知识卡", on_know_tab.bind("cards"), 150.0)
	panel_body.text = t

func render_day() -> void:
	panel_title.text = "第 %d 营业日结算 / DAY SETTLEMENT" % sys.day_summary.day
	var d := sys.day_summary
	var t := "[b]今日评级  %s[/b]\n\n" % d.grade
	t += "营业额            %s\n进货 / 充电支出   %s\n场地日租          %s\n" % [
		sys.fmt(d.revenue), sys.fmt(d.cost), sys.fmt(d.rent)]
	t += "[b]净利润          %s[/b]\n\n" % sys.fmt(d.profit)
	t += "完成 %d 单 · 超时 %d 单\n\n" % [int(d.done), int(d.failed)]
	t += "明日客流时段：%s。%s\n" % [sys.period,
		"拥挤等级整体上浮，批发价 +14%" if sys.period == "高峰" else (
		"通道顺畅，批发价 -9%" if sys.period == "低峰" else "常规客流与批发价")]
	t += "未交付货舱已退回库存，订单队列已刷新，日租随天数递增。"
	panel_body.text = t
	add_button("开始下一天营业", close_panel, 220.0)

func render_help_panel() -> void:
	panel_title.text = "操作说明 / HOW TO PLAY"
	panel_body.text = ("WASD 移动 · 鼠标环绕视角 · Shift 冲刺 · ESC 暂停\n" +
		"E 取货 · F 交付 · B 进货 · N 导航/Cost · M 大地图 · K 知识库 · U 技能 · Tab 订单 · G 加购 · R 充电\n" +
		"V 自动导航 · 沿规划路线行驶，遇阻立即局部 A* 绕障\n\n" +
		"本作所有商品实体、货架、门与服务台均按 NEXUS 原程序 dC/fC/pC/SC/CC/wC/TC/EC/DC 建模源码重建，\n" +
		"配色取自原程序 gC() palette（暖白灰泥 / 浅灰石材 / 深蓝灰金属 / 青紫灯带 / 浅橡木）。\n\n" +
		"[b]基准版本：NEXUS v9.1[/b]\n" +
		"v9.0 已落地：取货后按 leg 重绘、displayPoints 重写、终点斜线修复、立即局部 A* 绕障\n" +
		"（replanRetryS 0.6 s / maxReplanFailures 5）。v9.1 再补 P0 两点：让行实体沿垂直方向\n" +
		"侧移 0.7 m 并继续推进、填充 dynamicBlocked 时过滤 state=让行，窄通道不再互锁。\n" +
		"未改几何、16 组基线、seed 20261113、服务时间 S 独立于 T、Cost 与 w₁–w₅。")
	add_button("返回游戏", close_panel, 180.0)

# 面板回调
func on_restock(pid: String, qty: int) -> void:
	var res := sys.restock(pid, qty, near_gate_a())
	if res.ok:
		tut_restocks += 1
	toast(res.msg)
	render_panel()

func on_restock_all() -> void:
	for o in sys.orders:
		for it in o.items:
			sys.restock(it.id, 1, near_gate_a())
	tut_restocks += 1
	toast("已按需补货")
	render_panel()

func on_upsell(oid: String, idx: int) -> void:
	var res := sys.upsell(oid, idx)
	toast(res.msg)
	render_panel()

func on_plan_order(oid: String) -> void:
	for i in range(sys.orders.size()):
		if sys.orders[i].id == oid and i > 0:
			var tmp = sys.orders[0]
			sys.orders[0] = sys.orders[i]
			sys.orders[i] = tmp
			break
	on_plan()

func on_weighted() -> void:
	if int(sys.skills.chip) < 1:
		toast("需要升级「AI 路径芯片」技能才能启用加权 Cost 导航")
		return
	sys.weighted = not sys.weighted
	sys.plan.clear()
	on_plan()

func on_algo(m: String) -> void:
	sys.algo = m
	sys.plan.clear()
	on_plan()

func on_autopilot_btn() -> void:
	toggle_autopilot()
	render_panel()

func on_skill(k: String) -> void:
	var res := sys.upgrade_skill(k)
	toast(res.msg)
	render_panel()

func on_know_tab(t: String) -> void:
	know_tab = t
	quiz_feedback = ""
	render_panel()

func on_article(d: int) -> void:
	article_idx = clampi(article_idx + d, 0, map.article.size() - 1)
	render_panel()

func on_quiz(qi: int, oi: int) -> void:
	var res := sys.quiz_answer(qi, oi)
	quiz_feedback = ("✓ 正确 · " if res.ok else "✗ 正确答案见解析 · ") + res.msg
	toast("考核通过 EXP +25 / ¥120" if res.ok else "答错了，看解析")
	render_panel()

func on_quiz_next() -> void:
	quiz_idx = (quiz_idx + 1) % map.quiz.size()
	quiz_feedback = ""
	render_panel()

# ================================================================ HUD
func next_need():
	var counts: Dictionary = {}
	for c in sys.cargo:
		counts[c] = int(counts.get(c, 0)) + 1
	for o in sys.orders:
		for it in o.items:
			if int(counts.get(it.id, 0)) < int(it.qty):
				return it
	return null

func arrow_to(tx: float, tz: float) -> String:
	var a := atan2(tz - player.position.z, tx - player.position.x) - yaw
	var idx := int(round(a / (PI / 4.0))) % 8
	if idx < 0:
		idx += 8
	return ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"][idx]

func update_hud() -> void:
	var cc := int(floor(player.position.x + 28.0))
	var rr := int(floor(player.position.z + 24.0))
	var ot := "▌ 订单清单  #%d\n" % (sys.delivered + 1)
	for o in sys.orders.slice(0, 2):
		for it in o.items:
			ot += "%s %s\n  %s·%s  库%d\n" % [
				"✓" if it.got >= it.qty else "○", it.name, it.zone, it.rack, int(sys.stock[it.id])]
	lbl_order.text = ot
	lbl_stat.text = ("资金  %s\n电量  %d%%\nLV.%d  EXP %d  声望 %.1f★\nD%d %s · %s\n" +
			"交付 %d 单 · 超时 %d\n路线 %d m / 货舱 %d/%d") % [
			sys.fmt(sys.money), int(sys.battery / sys.bat_max() * 100.0), sys.level,
			int(sys.exp), sys.rep, sys.day, sys.clock_str(sys.clock), sys.period,
			sys.delivered, sys.failed, int(sys.plan.get("D", 0)), sys.cargo.size(), sys.cap()]
	var need = next_need()
	var g := "▌ 当前指引\n"
	if need == null:
		var gd := Vector2(float(map.exit[0]) + .5 - player.position.x,
				float(map.exit[1]) + .5 - player.position.z)
		g += "订单齐货！\n前往 Gate B 交付\n%.1f m %s\n\n[F] 交付结算" % [
			gd.length(), arrow_to(float(map.exit[0]) + .5, float(map.exit[1]) + .5)]
		lbl_compass.text = "%s  Gate B · 交付" % arrow_to(float(map.exit[0]) + .5, float(map.exit[1]) + .5)
	else:
		var d := Vector2(float(need.x) - player.position.x, float(need.z) - player.position.z)
		g += "%s\n%s 区 · %s 货架\n%.1f m %s · 库存 %d\n" % [
			need.name, need.zone, need.rack, d.length(), arrow_to(float(need.x), float(need.z)), int(sys.stock[need.id])]
		g += "\n⚠ 缺货！[B] 进货" if int(sys.stock[need.id]) <= 0 else "\n[E] 取货 · [N] 规划"
		g += "\n[M] 全图 · [ESC] 暂停"
		lbl_compass.text = "%s  %s  %.0f m" % [arrow_to(float(need.x), float(need.z)), need.name, d.length()]
	lbl_guide.text = g
	lbl_tip.text = "WASD 移动 · 鼠标环绕 · Shift 冲刺 · E 取货 · F 交付 · B 进货 · N 导航 · V 自动导航 · M 全图 · K 知识 · U 技能 · Tab 订单 · G 加购 · R 充电 · ESC 暂停"
	var p = near_product()
	if p != null:
		bg_prompt.visible = true
		lbl_prompt.visible = true
		lbl_prompt.text = "[E] 取货  %s · %s · H=%s · 库存 %d" % [
			p.name, p.method, str(p.H), int(sys.stock[p.id])]
	else:
		bg_prompt.visible = false
		lbl_prompt.visible = false
	lbl_cross.text = "·"
	lbl_toast.text = toast_msg if toast_t > 0.0 else ""

func update_big_order() -> void:
	var t := "▌ 订单清单 / ORDER LIST\n\n"
	var total := 0
	for o in sys.orders:
		total += o.items.size()
	var shown := 0
	for o in sys.orders:
		for it in o.items:
			if shown >= 5:
				break
			var d := Vector2(float(it.x) - player.position.x, float(it.z) - player.position.z)
			t += "%s · %s区/%s\n  %.1f m %s · 库%d\n" % [
				it.name, it.zone, it.rack, d.length(),
				arrow_to(float(it.x), float(it.z)), int(sys.stock[it.id])]
			shown += 1
	if total > shown:
		t += "…其余 %d 件见 [Tab] 订单面板\n" % (total - shown)
	t += "下一步：\n"
	var need = next_need()
	if need == null:
		t += "齐货 → 去 Gate B 按 [F] 交付"
	elif int(sys.stock[need.id]) <= 0:
		t += "%s 缺货 → 按 [B] 进货" % need.name
	else:
		t += "去 %s 区取 %s → [N] 规划" % [need.zone, need.name]
	if not sys.plan.is_empty():
		t += "\n\nCost %.1f · D %d m · ETA %d s" % [sys.plan.cost, int(sys.plan.D), int(sys.plan.eta)]
	lbl_big_order.text = t

# ================================================================ 教程
func reset_tut_vars() -> void:
	tut_move = 0.0
	tut_look = 0.0
	tut_key = ""
	tut_picks = 0
	tut_delivers = 0
	tut_restocks = 0
	last_pos = player.position

func update_tutorial_ui() -> void:
	if tut_step >= TUTORIAL.size():
		tutorial_on = false
		tut_root.visible = false
		return
	var s: Dictionary = TUTORIAL[tut_step]
	lbl_tut_title.text = str(s.title)
	lbl_tut_desc.text = str(s.desc)
	lbl_tut_goal.text = "目标：" + str(s.goal)
	tut_bar.size = Vector2((get_viewport().get_visible_rect().size.x - 120) *
			(float(tut_step) / float(TUTORIAL.size())), 5)
	btn_tut_next.visible = (s.kind == "done")

func advance_tutorial() -> void:
	tut_step += 1
	reset_tut_vars()
	if tut_step >= TUTORIAL.size():
		finish_tutorial()
		return
	update_tutorial_ui()
	toast("教程 %d / %d" % [tut_step + 1, TUTORIAL.size()])

func skip_tutorial() -> void:
	tutorial_on = false
	tut_root.visible = false
	toast("已跳过教程 · M 全图 / N 导航 / Tab 订单")

func finish_tutorial() -> void:
	tutorial_on = false
	tut_root.visible = false
	sys.money += 200.0
	toast("教程完成 · 启动资金 +¥200")

func check_tutorial(delta: float) -> void:
	if not tutorial_on or tut_step >= TUTORIAL.size():
		return
	var s: Dictionary = TUTORIAL[tut_step]
	var ok := false
	match str(s.kind):
		"move":
			tut_move += (player.position - last_pos).length()
			last_pos = player.position
			ok = tut_move >= float(s.n)
		"look": ok = tut_look >= float(s.n)
		"key": ok = tut_key == str(s.v)
		"pick": ok = tut_picks >= int(s.n)
		"restock": ok = tut_restocks >= int(s.n)
		"deliver": ok = tut_delivers >= int(s.n)
	if ok:
		advance_tutorial()

# ================================================================ 存档
func check_save() -> void:
	save_exists = FileAccess.file_exists(SAVE_PATH)
	btn_continue.disabled = not save_exists
	btn_continue.text = "↻  继续上次存档" if save_exists else "↻  继续上次存档（无存档）"

func save_game() -> void:
	var d := sys.state_dict()
	d["pos"] = [player.position.x, player.position.z]
	d["yaw"] = yaw
	d["pitch"] = pitch
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()

func load_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	sys.load_state(d)
	var pos: Array = d.get("pos", [map.entry[0] + 4.5, map.entry[1] + 9.5])
	player.position = Vector3(float(pos[0]), 0.0, float(pos[1]))
	yaw = float(d.get("yaw", -1.45))
	pitch = float(d.get("pitch", .20))

# ================================================================ 截图 / 自检
func take_shot(which: String) -> void:
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		print("[SHOT] viewport texture unavailable")
		return
	var img := tex.get_image()
	var nm := "NEXUS_preview_menu.png"
	if which == "game": nm = "NEXUS_preview_game.png"
	elif which == "panel": nm = "NEXUS_preview_panel.png"
	elif which == "map": nm = "NEXUS_preview_map.png"
	var fn := OS.get_executable_path().get_base_dir() + "/" + nm
	var err := img.save_png(fn)
	print("[SHOT] ", fn, " err=", err, " size=", img.get_size())

func run_selftest() -> void:
	print("[SELFTEST] orders=%d stock=%d money=%s" % [sys.orders.size(), sys.stock.size(), sys.fmt(sys.money)])
	var o: Dictionary = sys.orders[0]
	var id1: String = o.items[0].id
	var s0 := int(sys.stock[id1])
	for it in o.items:
		var pd = sys.find_product(it.id)
		player.position = Vector3(float(pd.x), 0, float(pd.z))
		for q in range(int(it.qty)):
			sys.pick(it.id)
	print("[SELFTEST] pick items=%d stock %d->%d cargo=%d" % [
			o.items.size(), s0, int(sys.stock[id1]), sys.cargo.size()])
	player.position = Vector3(float(map.exit[0]) + .5, 0, float(map.exit[1]) + .5)
	var m0: float = sys.money
	var dr := sys.deliver()
	print("[SELFTEST] deliver ok=%s money %s->%s delivered=%d" % [str(dr.ok), sys.fmt(m0), sys.fmt(sys.money), sys.delivered])
	var pl := sys.plan_route(player.position, npcs)
	print("[SELFTEST] plan D=%d C=%.2f T=%.1f R=%.2f H=%.1f cost=%.1f seq=%d cells=%d" % [
		int(pl.D), pl.C, pl.T, pl.R, pl.H, pl.cost, pl.seq.size(), pl.cells.size()])
	var cmp := sys.algo_compare(player.position, npcs)
	for c in cmp:
		print("[SELFTEST]   %-9s %4d m / %5d nodes" % [c.name, int(c.length), int(c.expanded)])
	sys.weighted = true
	var wp := sys.plan_route(player.position, npcs)
	print("[SELFTEST] weighted cost=%.1f D=%d" % [wp.cost, int(wp.D)])
	var ur := sys.upsell(sys.orders[0].id, 0)
	print("[SELFTEST] upsell ok=%s msg=%s" % [str(ur.ok), ur.msg])
	sys.pts = 2
	var sk := sys.upgrade_skill("battery")
	print("[SELFTEST] skill ok=%s battery_lv=%d pts=%d" % [str(sk.ok), int(sys.skills.battery), sys.pts])
	var qz := sys.quiz_answer(0, int(map.quiz[0].a))
	print("[SELFTEST] quiz ok=%s done=%d" % [str(qz.ok), sys.quiz_done.size()])
	var ds := sys.day_end()
	print("[SELFTEST] day_end grade=%s profit=%s period=%s" % [ds.grade, sys.fmt(ds.profit), sys.period])
	selftest_v91()
	save_game()
	print("[SELFTEST] save exists=%s" % str(FileAccess.file_exists(SAVE_PATH)))
	start_game(true)
	print("[SELFTEST] tutorial step=%d active=%s" % [tut_step, str(tutorial_on)])
	print("[SELFTEST] OK")

## v9.1 专项自检：让行实体侧移 + 移出占用栅格 + 立即局部 A* 绕障
## 完全使用局部数组，不写运行时 npcs / plan，避免污染后续帧。
func selftest_v91() -> void:
	print("[SELFTEST] --- v9.1 避障专项 ---")
	var px := float(map.entry[0]) + 11.0
	var pz := float(map.entry[1]) - 7.0
	var origin := Vector3(px, 0, pz)
	# P0-2 侧移 + P0-1 让出占用栅格
	var probe := {"x": px + .9, "z": pz, "kind": "customer", "a": 0.0, "sp": .5, "state": "通行"}
	var local_npcs: Array = [probe]
	var before := Vector2(float(probe.x), float(probe.z))
	var y: int = sys.step_yield(local_npcs, origin, .5)
	var after := Vector2(float(probe.x), float(probe.z))
	var dyn: Dictionary = sys.dynamic_cells(local_npcs)
	var yielded_cell: int = int(floor(float(probe.x) + 28.0)) + 56 * int(floor(float(probe.z) + 24.0))
	print("[SELFTEST] yield state=%s moved=%.2fm yielders=%d in_dyn=%s" % [
		str(probe.state), before.distance_to(after), y, str(dyn.has(yielded_cell))])
	# 立即局部 A* 绕障：取一段真实可通行路径，占住中途一格
	var pl: Dictionary = sys.plan_route(origin, [])
	var cells: Array = pl.get("cells", [])
	var hit := false
	var d0: int = sys.detours
	var tried := 0
	for i in range(2, maxi(3, cells.size() - 4)):
		var a: Vector2i = cells[i]
		var mid: Vector2i = cells[i + 1]
		var b: Vector2i = cells[mini(i + 3, cells.size() - 1)]
		var fake := {"x": -28.0 + mid.x + .5, "z": -24.0 + mid.y + .5,
				"kind": "cart", "state": "通行"}
		var dyn2: Dictionary = sys.dynamic_cells([fake])
		var det: Dictionary = sys.local_detour(a, b, sys.risk_grid([fake]), dyn2)
		tried += 1
		if det.cells.is_empty():
			continue
		var blocked_hit := false
		for c in det.cells:
			if int(c.x) == mid.x and int(c.y) == mid.y:
				blocked_hit = true
		if not blocked_hit:
			print("[SELFTEST] detour cells=%d expanded=%d avoids_blocked=true tried=%d" % [
				det.cells.size(), int(det.expanded), tried])
			hit = true
			break
	if not hit:
		print("[SELFTEST] detour narrow-aisle case=%d -> wait/retry exercised" % tried)
	print("[SELFTEST] detours+%d last_avoid=%s" % [sys.detours - d0, sys.last_avoid])
