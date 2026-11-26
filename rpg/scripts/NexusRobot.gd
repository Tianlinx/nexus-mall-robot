class_name NexusRobot
extends RefCounted
## 第三人称主角：R-07 零售机器人。沿用 NEXUS gC() palette（metal / silver / screen / cyan / package）。
## 玩家能看到本体：轮式底盘、屏幕脸、双机械臂、背部货舱、状态灯。

static func mesh(g: Node3D, m: Mesh, key: String, pos: Vector3, glow := 0.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = NexusPalette.mat(key, glow)
	mi.position = pos
	mi.rotation = rot
	g.add_child(mi)
	return mi

static func block(g: Node3D, sz: Vector3, key: String, pos: Vector3, glow := 0.0) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = sz
	return mesh(g, bm, key, pos, glow)

static func wheel(g: Node3D, x: float) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = .22
	cm.bottom_radius = .22
	cm.height = .12
	cm.radial_segments = 20
	return mesh(g, cm, "black", Vector3(x, .22, 0), 0.0, Vector3(0, 0, PI / 2))

static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "R-07 Robot"

	# 轮式底盘
	block(root, Vector3(.72, .18, .56), "metal", Vector3(0, .24, 0))
	block(root, Vector3(.60, .06, .48), "silver", Vector3(0, .35, 0))
	var wl := wheel(root, -.40)
	var wr := wheel(root, .40)
	for x in [-.22, .22]:
		block(root, Vector3(.10, .05, .03), "cyan", Vector3(x, .24, .30), .8)

	# 躯干与胸屏
	block(root, Vector3(.62, .62, .42), "silver", Vector3(0, .78, 0))
	block(root, Vector3(.50, .46, .03), "metal", Vector3(0, .78, -.22))
	block(root, Vector3(.42, .30, .02), "screen", Vector3(0, .82, .22), .45)
	block(root, Vector3(.30, .025, .025), "cyan", Vector3(0, .64, .235), .7)
	block(root, Vector3(.16, .05, .02), "purple", Vector3(0, .98, .235), .5)

	# 头 / 屏幕脸 / 天线
	block(root, Vector3(.38, .30, .34), "silver", Vector3(0, 1.26, 0))
	block(root, Vector3(.31, .19, .02), "screenPurple", Vector3(0, 1.28, .18), .5)
	for x in [-.09, .09]:
		var sm := SphereMesh.new()
		sm.radius = .035
		sm.height = .07
		mesh(root, sm, "cyan", Vector3(x, 1.30, .195), 1.0)
	var ant := CylinderMesh.new()
	ant.top_radius = .018
	ant.bottom_radius = .018
	ant.height = .30
	mesh(root, ant, "metal", Vector3(.13, 1.55, 0))
	var tip := SphereMesh.new()
	tip.radius = .045
	tip.height = .09
	mesh(root, tip, "cyan", Vector3(.13, 1.72, 0), 1.0)

	# 双机械臂（容器节点，便于摆动）
	var arms: Array = []
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * .44, 1.00, 0)
		root.add_child(shoulder)
		block(shoulder, Vector3(.16, .16, .16), "metal", Vector3.ZERO)
		block(shoulder, Vector3(.14, .34, .14), "silver", Vector3(0, -.22, 0))
		block(shoulder, Vector3(.12, .28, .12), "metal", Vector3(0, -.50, .02))
		for gx in [-.05, .05]:
			block(shoulder, Vector3(.045, .12, .05), "black", Vector3(gx, -.68, .05))
		block(shoulder, Vector3(.10, .03, .02), "cyan", Vector3(0, -.44, .09), .6)
		arms.append(shoulder)

	# 背部货舱 + 6 个货位指示灯
	block(root, Vector3(.52, .44, .22), "package", Vector3(0, .80, -.34))
	block(root, Vector3(.56, .05, .24), "metal", Vector3(0, 1.04, -.34))
	var boxes: Array = []
	for i in range(6):
		var bx := -0.17 + (i % 3) * .17
		var by := .90 - int(i / 3) * .16
		var b := block(root, Vector3(.12, .11, .03), "cyan", Vector3(bx, by, -.465), .5)
		b.visible = false
		boxes.append(b)

	# 脚下投影（一个简单的深灰圆盘，增强落地感）
	var shadow := CylinderMesh.new()
	shadow.top_radius = .42
	shadow.bottom_radius = .42
	shadow.height = .012
	var sh := mesh(root, shadow, "base", Vector3(0, .012, 0))
	sh.material_override = NexusPalette.mat("base")

	root.set_meta("wheels", [wl, wr])
	root.set_meta("arms", arms)
	root.set_meta("cargo_boxes", boxes)
	return root

static func animate(root: Node3D, moving: bool, t: float, cargo_n: int) -> void:
	var wheels: Array = root.get_meta("wheels")
	var arms: Array = root.get_meta("arms")
	var boxes: Array = root.get_meta("cargo_boxes")
	var swing: float = sin(t * 9.0) * .42 if moving else 0.0
	arms[0].rotation.x = swing
	arms[1].rotation.x = -swing
	if moving:
		wheels[0].rotation.x += .12
		wheels[1].rotation.x += .12
	root.position.y = sin(t * 9.0) * .018 if moving else 0.0
	for i in range(boxes.size()):
		boxes[i].visible = i < cargo_n
