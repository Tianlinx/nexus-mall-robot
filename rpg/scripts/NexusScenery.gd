class_name NexusScenery
extends RefCounted
## NEXUS 原程序场景建模的 Godot 复刻：fC 货架 / pC 出入口 / SC 服务台 / CC 收银台 /
## wC 组装台 / TC 装饰楼梯 / EC 中央双向楼梯 / DC 三边高排货架 / AC 地坪墙体。
## 所有材质走 NexusPalette（原程序 gC() 的 18 色）。

static var _by_id: Dictionary = {}

static func box(g: Node3D, sz: Vector3, pos: Vector3, key: String, glow := 0.0, rot := Vector3.ZERO, hexc := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.material_override = NexusPalette.hex(hexc, glow) if hexc != "" else NexusPalette.mat(key, glow)
	mi.position = pos
	mi.rotation = rot
	g.add_child(mi)
	return mi

static func label3d(g: Node3D, text: String, sub: String, w: float, y: float, z: float,
		hexc: String, font: Font, size := 30) -> void:
	var bw := minf(7.2, w - .3)
	box(g, Vector3(bw + .08, .70, .08), Vector3(0, y, z - .045), "signBack")
	box(g, Vector3(.13, .62, .095), Vector3(-bw / 2 + .10, y, z + .01), "", .9, Vector3.ZERO, hexc)
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = .0085
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color.html("#F3F7FA")
	l.position = Vector3(.25, y + .07, z + .02)
	g.add_child(l)
	if sub != "":
		var l2 := Label3D.new()
		l2.text = sub
		l2.font = font
		l2.font_size = 18
		l2.pixel_size = .0055
		l2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l2.modulate = Color.html(hexc)
		l2.position = Vector3(.25, y - .16, z + .02)
		g.add_child(l2)

static func build_all(root: Node3D, map: Dictionary, font: Font) -> void:
	_by_id.clear()
	for p in map.products:
		_by_id[p.id] = p
	build_ground(root)
	build_racks(root, map, font)
	build_gates(root, map, font)
	build_decor(root, map, font)

# ---------------------------------------------------------------- AC 地坪 / 吊顶 / 障碍格
static func build_ground(root: Node3D) -> void:
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(56, 48)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1, 1, 1)
	fm.roughness = .62
	var tex := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var seam: bool = x < 2 or y < 2
			tex.set_pixel(x, y, Color(.58, .64, .70) if seam else Color(.76, .80, .84))
	fm.albedo_texture = ImageTexture.create_from_image(tex)
	fm.uv1_scale = Vector3(56, 48, 1)
	floor.material_override = fm
	root.add_child(floor)

	var ceil_n := MeshInstance3D.new()
	var cm := PlaneMesh.new()
	cm.size = Vector2(56, 48)
	ceil_n.mesh = cm
	var cmm := StandardMaterial3D.new()
	cmm.albedo_color = NexusPalette.col("wall")
	cmm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ceil_n.material_override = cmm
	ceil_n.position = Vector3(0, 5.2, 0)
	root.add_child(ceil_n)

	# 吊顶灯带：青 / 紫交替（原程序一层导视灯带）
	for x in range(-24, 25, 12):
		for z in range(-18, 19, 12):
			box(root, Vector3(5, .08, .5), Vector3(x, 3.32, z),
					"cyan" if (x + z) % 24 == 0 else "purple", .65)

# ---------------------------------------------------------------- fC 29 组货架
static func build_racks(root: Node3D, map: Dictionary, font: Font) -> void:
	for k in map.racks:
		var g := Node3D.new()
		g.name = "Rack_" + str(k.id)
		g.position = Vector3(float(k.x), 0, float(k.z))
		root.add_child(g)
		var w: float = float(k.w)
		var d: float = float(k.d)
		var h: float = float(k.h)
		# 4 根深色拉丝金属立柱
		for x in [-w / 2 + .07, w / 2 - .07]:
			for z in [-d / 2 + .06, d / 2 - .06]:
				box(g, Vector3(.09, h, .09), Vector3(x, h / 2, z), "metal")
		# 3 层层板：首层浅橡木，其余暖白烤漆；每层摆该序号的商品实体（fC 的 productIds）
		var levels: Array = [.3, h * .45, h * .75]
		for i in range(3):
			box(g, Vector3(w, .075, d), Vector3(0, float(levels[i]), 0),
					"wood" if i == 0 else "counter")
			for j in range(k.productIds.size()):
				if j % 3 != i:
					continue
				var p: Dictionary = _by_id.get(k.productIds[j], {})
				if p.is_empty():
					continue
				var pd: Dictionary = p.duplicate()
				pd["idx"] = j
				var m := ProductModels.build(pd)
				m.position = Vector3(float(p.x) - float(k.x), float(levels[i]) + .38, .02)
				m.scale = Vector3.ONE * .62
				g.add_child(m)
		# 顶部一层导视青色灯带
		box(g, Vector3(w, .12, .08), Vector3(0, h - .08, d / 2), "cyan", .8)
		# 导视招牌
		label3d(g, str(k.id).to_upper() + " · " + str(map.zones[_zone_index(map, k.zone)].name),
				str(k.en), w, h + .38, d / 2 - .04, str(k.color), font)

static func _zone_index(map: Dictionary, id: String) -> int:
	for i in range(map.zones.size()):
		if map.zones[i].id == id:
			return i
	return 0

# ---------------------------------------------------------------- pC 入口 / 出口
static func build_gates(root: Node3D, map: Dictionary, font: Font) -> void:
	_gate(root, map.entry, "入口 IN", "ROBOT START", "gateA", font)
	_gate(root, map.exit, "出口 EXIT", "ROBOT FINISH", "gateB", font)

static func _gate(root: Node3D, pos: Array, title: String, sub: String, key: String, font: Font) -> void:
	var g := Node3D.new()
	g.name = "Gate_" + key
	g.position = Vector3(float(pos[0]), 0, float(pos[1]) + 1.35)
	root.add_child(g)
	var hexc := str(NexusPalette.P.get(key, "#42dedd"))
	for x in [-.85, .85]:
		box(g, Vector3(.12, 2.45, .16), Vector3(x, 1.225, 0), "metal")
		box(g, Vector3(.16, .07, .22), Vector3(x, .07, 0), "", 1.0, Vector3.ZERO, hexc)
	box(g, Vector3(1.82, .13, .18), Vector3(0, 2.42, 0), "metal")
	label3d(g, title, sub, 2.0, 2.72, 0, hexc, font, 24)
	# 地面菱形箭头
	box(g, Vector3(.7, .02, .7), Vector3(0, .105, -.5), "", .7,
			Vector3(0, PI / 4, 0), hexc)

# ---------------------------------------------------------------- 装饰实体
static func build_decor(root: Node3D, map: Dictionary, font: Font) -> void:
	for o in map.obstacles:
		var id := str(o.id)
		if id == "service_desk":
			_service_desk(root, o)
		elif id == "checkout":
			_checkout(root, o, font)
		elif id == "assembly":
			_assembly(root, o, font)
		elif id == "stairs":
			_stairs(root, o, font)
		elif id == "grand_stairs":
			_grand_stairs(root, o, font)
		elif id.begins_with("high_rack_"):
			_high_rack(root, o)

static func _node(root: Node3D, o: Dictionary) -> Node3D:
	var g := Node3D.new()
	g.name = "Decor_" + str(o.id)
	g.position = Vector3(float(o.x), 0, float(o.z))
	root.add_child(g)
	return g

# SC 中央总服务台
static func _service_desk(root: Node3D, o: Dictionary) -> void:
	var g := _node(root, o)
	var w: float = float(o.w)
	box(g, Vector3(w, .86, 1.12), Vector3(0, .43, 0), "counter")
	box(g, Vector3(w + .12, .1, 1.2), Vector3(0, .89, 0), "wood")
	box(g, Vector3(w - .35, .07, .03), Vector3(0, .46, .575), "cyan", .8)
	for x in [-w * .28, w * .28]:
		box(g, Vector3(.48, .34, .035), Vector3(x, 1.19, -.1), "black")
		box(g, Vector3(.42, .27, .009), Vector3(x, 1.19, -.078), "screen", .5)
		box(g, Vector3(.06, .28, .06), Vector3(x, 1, -.1), "metal")

# CC 收银台
static func _checkout(root: Node3D, o: Dictionary, font: Font) -> void:
	var g := _node(root, o)
	box(g, Vector3(4.4, .82, 1.25), Vector3(0, .41, 0), "counter")
	box(g, Vector3(4.52, .1, 1.34), Vector3(0, .87, 0), "wood")
	box(g, Vector3(1.55, .055, .82), Vector3(-.95, .94, 0), "black")
	box(g, Vector3(.46, .36, .06), Vector3(1.25, 1.22, -.12), "black")
	box(g, Vector3(.39, .29, .012), Vector3(1.25, 1.22, -.085), "screen", .5)
	box(g, Vector3(.07, .28, .07), Vector3(1.25, 1, -.12), "metal")
	box(g, Vector3(.28, .1, .22), Vector3(.75, .99, .18), "wallDark")
	box(g, Vector3(3.95, .06, .025), Vector3(0, .43, .64), "cyan", .8)
	label3d(g, "收银台 CHECKOUT", "DISPLAY ONLY · 提货区交付", 3.2, 1.72, -.45, "#25C7D9", font, 22)

# wC 组装台
static func _assembly(root: Node3D, o: Dictionary, font: Font) -> void:
	var g := _node(root, o)
	for x in [-2.25, 2.25]:
		for z in [-.63, .63]:
			box(g, Vector3(.12, .88, .12), Vector3(x, .44, z), "metal")
	box(g, Vector3(5.2, .14, 1.7), Vector3(0, .92, 0), "wood")
	box(g, Vector3(5, 1.05, .1), Vector3(0, 1.48, -.77), "wallDark")
	for x in range(-2, 3):
		for y in [1.2, 1.5, 1.8]:
			box(g, Vector3(.035, .035, .018), Vector3(float(x) * .42, float(y), -.71), "silver")
	box(g, Vector3(.68, .82, .65), Vector3(-1.55, 1.4, .05), "black")
	box(g, Vector3(.54, .64, .018), Vector3(-1.55, 1.4, .385), "glass")
	box(g, Vector3(1.05, .64, .06), Vector3(.2, 1.47, -.05), "black")
	box(g, Vector3(.96, .55, .012), Vector3(.2, 1.47, -.012), "screenPurple", .4)
	box(g, Vector3(.08, .42, .08), Vector3(.2, 1.08, -.05), "metal")
	label3d(g, "组装台 PC ASSEMBLY", "DISPLAY ONLY", 3.4, 2.35, -.72, "#8B7CFF", font, 22)

# TC 装饰楼梯
static func _stairs(root: Node3D, o: Dictionary, font: Font) -> void:
	var g := _node(root, o)
	for i in range(7):
		var h := .14 * (i + 1)
		var z := -1.2 + i * .4
		box(g, Vector3(2.7, h, .42), Vector3(0, h / 2, z), "slab")
		box(g, Vector3(2.66, .025, .055), Vector3(0, h + .012, z + .18), "cyan", .7)
	box(g, Vector3(2.7, .14, .55), Vector3(0, .91, 1.32), "slab")
	for x in [-1.32, 1.32]:
		for z in [-1.2, -.4, .4, 1.2]:
			box(g, Vector3(.055, .85, .055), Vector3(x, .56, z), "metal")
		box(g, Vector3(.065, .065, 3.05), Vector3(x, 1.55, 0), "metal", 0.0, Vector3(-.32, 0, 0))
	label3d(g, "装饰楼梯", "ARCHITECTURAL DISPLAY", 2.8, 2.15, 1.25, "#F2B86B", font, 20)

# EC 中央双向楼梯
static func _grand_stairs(root: Node3D, o: Dictionary, font: Font) -> void:
	var g := _node(root, o)
	for side in [-1.75, 1.75]:
		var c := "#25C7D9" if side < 0.0 else "#F2B86B"
		for i in range(12):
			var h := .2 * (i + 1)
			var z := -2.85 + i * .42
			box(g, Vector3(3.05, h, .445), Vector3(side, h / 2, z), "slab")
			box(g, Vector3(2.98, .025, .055), Vector3(side, h + .012, z + .21), "", .6, Vector3.ZERO, c)
		for x in [side - 1.48, side + 1.48]:
			for i in [0, 3, 6, 9, 11]:
				box(g, Vector3(.055, .82, .055), Vector3(x, .2 * (i + 1) + .41, -2.85 + i * .42), "metal")
	box(g, Vector3(6.65, .18, 1.15), Vector3(0, 2.31, 2.35), "slab")
	box(g, Vector3(6.55, .035, .08), Vector3(0, 2.42, 1.79), "cyan", .8)
	for x in [-3.05, 3.05]:
		box(g, Vector3(.18, 2.3, .18), Vector3(x, 1.15, 2.35), "metal")
	label3d(g, "中央双向楼梯", "UP / DOWN · DISPLAY ONLY", 5.0, 3.72, 2.5, "#F2B86B", font, 22)

# DC 三边高排货架
static func _high_rack(root: Node3D, o: Dictionary) -> void:
	var g := _node(root, o)
	var w: float = float(o.w)
	var d: float = float(o.d)
	var long: float = maxf(w, d)
	var short: float = minf(w, d)
	var h: float = 3.5
	var cols: int = maxi(3, int(round(long / 3.6)))
	var step: float = long / float(cols)
	var keys: Array = ["package", "wallDark", "counter", "screenPurple", "wood", "silver"]
	for i in range(cols + 1):
		var x := -long / 2 + i * step
		for z in [-short / 2 + .035, short / 2 - .035]:
			box(g, Vector3(.075, h, .075), Vector3(x, h / 2, z), "metal")
	for li in range(5):
		var ly: float = [.27, 1.02, 1.77, 2.52, 3.27][li]
		box(g, Vector3(long, .075, short), Vector3(0, ly, 0), "wood" if li == 0 else "counter")
		if li < 4:
			for i in range(cols):
				for j in range(3):
					var x := -long / 2 + i * step + (j + .62) * step / 3.25
					var hh := .34 + float((i + j + li) % 3) * .07
					box(g, Vector3(step * .21, hh, short * .72), Vector3(x, ly + .06 + hh / 2, 0),
							str(keys[(i * 2 + j + li) % keys.size()]))
	box(g, Vector3(long, .08, .06), Vector3(0, h - .04, short / 2), "cyan", .8)
	if d > w:
		g.rotation.y = -PI / 2
