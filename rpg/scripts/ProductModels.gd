class_name ProductModels
extends RefCounted
## NEXUS 原程序 dC() 的 Godot 逐行复刻：按 75 类商品的官方 kind 建实体。
## 材质全部取自 gC() palette（pcb / silver / metal / cyan / purple / wood / counter / screen ...）。
## 尺寸沿用原程序单位（约 1 单位），由调用方统一缩放。

static func box(root: Node3D, sz: Vector3, pos: Vector3, key: String, glow := 0.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.material_override = NexusPalette.mat(key, glow)
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)
	return mi

static func cyl(root: Node3D, radius: float, height: float, pos: Vector3, key: String, glow := 0.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 18
	mi.mesh = m
	mi.material_override = NexusPalette.mat(key, glow)
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)
	return mi

static func ring(root: Node3D, radius: float, tube: float, pos: Vector3, key: String, glow := 0.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := TorusMesh.new()
	m.inner_radius = maxf(0.01, radius - tube)
	m.outer_radius = radius + tube
	m.rings = 8
	m.ring_segments = 24
	mi.mesh = m
	mi.material_override = NexusPalette.mat(key, glow)
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)
	return mi

static func build(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "NXModel_" + str(p.id)
	var k: String = str(p.get("kind", "package"))
	match k:
		"cpu":
			box(root, Vector3(.5, .08, .48), Vector3.ZERO, "pcb")
			box(root, Vector3(.3, .07, .3), Vector3(0, .07, 0), "silver")
			box(root, Vector3(.56, .22, .05), Vector3(0, .15, -.27), "package")
		"board", "gpu", "nic", "capture":
			box(root, Vector3(.82, .055, .58), Vector3.ZERO, "pcb")
			for x in [-.24, 0.0, .24]:
				box(root, Vector3(.13, .07, .17), Vector3(x, .065, 0), "black")
			if k == "gpu":
				ring(root, .17, .025, Vector3(0, .08, 0), "silver", 0.0, Vector3(PI / 2, 0, 0))
		"memory":
			for x in [-.22, .22]:
				box(root, Vector3(.12, .06, .66), Vector3(x, 0, 0), "pcb")
				for z in [-.2, 0.0, .2]:
					box(root, Vector3(.13, .04, .12), Vector3(x, .05, z), "black")
		"ssd", "hdd", "nvr", "dock", "mini", "switch":
			box(root, Vector3(.82, .28 if k == "nvr" else .16, .64), Vector3(0, .06, 0), "silver")
			box(root, Vector3(.52, .02, .22), Vector3(0, .16, .1), "package")
			if k == "switch" or k == "nvr":
				for x in [-.25, -.08, .09, .26]:
					box(root, Vector3(.11, .05, .02), Vector3(x, .07, .33), "cyan", .5)
		"power", "ups":
			box(root, Vector3(.72, .5, .62), Vector3(0, .2, 0), "black")
			ring(root, .18, .025, Vector3(0, .2, .32), "silver", 0.0, Vector3(PI / 2, 0, 0))
			box(root, Vector3(.3, .07, .02), Vector3(0, .35, .33), "cyan", .5)
		"cooling":
			box(root, Vector3(.62, .16, .62), Vector3.ZERO, "silver")
			ring(root, .24, .035, Vector3(0, .12, 0), "purple", .35)
			for i in range(4):
				box(root, Vector3(.07, .025, .25), Vector3(0, .12, 0), "black", 0.0, Vector3(0, i * PI / 2, 0))
		"case", "desktop", "workstation", "server", "console":
			var hh: float = .72 if k == "server" else .9
			box(root, Vector3(.62, hh, .64), Vector3(0, hh / 2, 0), "black")
			box(root, Vector3(.48, hh * .72, .018), Vector3(0, hh / 2, .33), "wallDark" if k == "console" else "glass")
			for y in [.25, .58]:
				ring(root, .11, .018, Vector3(0, y, .35), "cyan", .5, Vector3(PI / 2, 0, 0))
		"laptop", "aio", "monitor", "pos":
			if k == "laptop":
				box(root, Vector3(1.02, .06, .7), Vector3(0, 0, .12), "silver")
			box(root, Vector3(1.12, .68, .065), Vector3(0, .42, 0), "black")
			box(root, Vector3(1.02, .56, .012), Vector3(0, .43, .04),
					"screenPurple" if int(p.get("idx", 0)) % 2 == 1 else "screen", .3)
			if k != "laptop":
				box(root, Vector3(.08, .34, .08), Vector3(0, -.02, 0), "metal")
				box(root, Vector3(.52, .04, .3), Vector3(0, -.18, 0), "metal")
		"keyboard":
			box(root, Vector3(1.18, .07, .44), Vector3.ZERO, "black")
			for i in range(3):
				box(root, Vector3(1.03, .018, .07), Vector3(0, .045, -.13 + i * .13),
						"purple" if i == 1 else "wallDark", .2 if i == 1 else 0.0)
		"mouse":
			for x in [-.38, 0.0, .38]:
				box(root, Vector3(.25, .15, .42), Vector3(x, 0, 0), "silver")
		"headset":
			ring(root, .37, .045, Vector3(0, .28, 0), "black", 0.0, Vector3(PI / 2, 0, 0))
			for x in [-.37, .37]:
				box(root, Vector3(.16, .32, .22), Vector3(x, .06, 0), "wallDark")
		"webcam", "security":
			box(root, Vector3(.62, .28, .3), Vector3(0, .16, 0), "counter" if k == "security" else "black")
			cyl(root, .11, .08, Vector3(0, .16, .18), "screen", .3, Vector3(PI / 2, 0, 0))
			box(root, Vector3(.08, .25, .08), Vector3(0, -.05, 0), "metal")
		"printer":
			box(root, Vector3(1.18, .58, .82), Vector3(0, .25, 0), "counter")
			box(root, Vector3(.86, .08, .36), Vector3(0, .25, .43), "black")
			box(root, Vector3(.68, .025, .48), Vector3(0, .58, .18), "wall")
			box(root, Vector3(.22, .09, .02), Vector3(.34, .43, .42), "screen", .3)
		"scanner":
			box(root, Vector3(1.2, .18, .78), Vector3(0, .08, 0), "counter")
			box(root, Vector3(1.08, .025, .64), Vector3(0, .19, 0), "glass")
		"projector":
			box(root, Vector3(1.05, .3, .72), Vector3(0, .12, 0), "counter")
			cyl(root, .17, .09, Vector3(.25, .15, .39), "black", 0.0, Vector3(PI / 2, 0, 0))
			cyl(root, .12, .095, Vector3(.25, .15, .43), "screen", .3, Vector3(PI / 2, 0, 0))
		"phone", "tablet", "ereader":
			var w: float = .36 if k == "phone" else .72
			var ph: float = .68 if k == "phone" else .92
			box(root, Vector3(w, ph, .05), Vector3(0, ph / 2, 0), "black")
			box(root, Vector3(w * .86, ph * .82, .012), Vector3(0, ph / 2, .032),
					"wall" if k == "ereader" else "screen", 0.0 if k == "ereader" else .3)
		"watch":
			box(root, Vector3(.38, .42, .12), Vector3(0, .24, 0), "black")
			box(root, Vector3(.29, .31, .02), Vector3(0, .24, .07), "screen", .3)
			box(root, Vector3(.18, .75, .055), Vector3(0, .24, -.04), "wallDark")
		"powerbank", "charger", "plug", "card":
			box(root, Vector3(.52, .06 if k == "card" else .42, .5), Vector3(0, .15, 0), "counter")
			box(root, Vector3(.28, .025, .04), Vector3(0, .22, .26), "cyan", .5)
		"router", "mesh":
			box(root, Vector3(.92, .16, .58), Vector3.ZERO, "counter")
			for x in [-.34, .34]:
				box(root, Vector3(.035, .58, .035), Vector3(x, .32, -.18), "metal")
			box(root, Vector3(.62, .025, .025), Vector3(0, .1, .3), "cyan", .5)
		"cable":
			ring(root, .32, .035, Vector3(0, .08, 0), "black")
			for x in [-.4, .4]:
				box(root, Vector3(.16, .08, .12), Vector3(x, .08, 0), "silver")
		"speaker":
			box(root, Vector3(.52, .82, .48), Vector3(0, .38, 0), "wallDark")
			ring(root, .18, .02, Vector3(0, .79, 0), "cyan", .5)
		"vr":
			box(root, Vector3(.92, .42, .42), Vector3(0, .2, 0), "black")
			box(root, Vector3(.76, .28, .02), Vector3(0, .2, .22), "screenPurple", .3)
			ring(root, .47, .035, Vector3(0, .28, -.1), "wallDark", 0.0, Vector3(PI / 2, 0, 0))
		"camera":
			box(root, Vector3(.86, .58, .42), Vector3(0, .25, 0), "black")
			cyl(root, .22, .35, Vector3(0, .25, .35), "wallDark", 0.0, Vector3(PI / 2, 0, 0))
			cyl(root, .16, .02, Vector3(0, .25, .54), "screen", .3, Vector3(PI / 2, 0, 0))
		"drone":
			box(root, Vector3(.48, .18, .42), Vector3(0, .2, 0), "counter")
			for x in [-.48, .48]:
				for z in [-.4, .4]:
					box(root, Vector3(.65, .055, .07), Vector3(x / 2, .2, z / 2), "metal",
							0.0, Vector3(0, atan2(z, x), 0))
					ring(root, .22, .018, Vector3(x, .23, z), "black")
		"controller":
			box(root, Vector3(.88, .26, .5), Vector3(0, .12, 0), "black")
			for x in [-.22, .22]:
				cyl(root, .08, .06, Vector3(x, .28, 0), "wallDark")
			for x in [.22, .34]:
				box(root, Vector3(.07, .04, .07), Vector3(x, .29, .13), "cyan", .5)
		"bag":
			box(root, Vector3(.98, .68, .28), Vector3(0, .3, 0), "wallDark")
			ring(root, .23, .035, Vector3(0, .67, 0), "black", 0.0, Vector3(PI / 2, 0, 0))
			box(root, Vector3(.65, .035, .02), Vector3(0, .3, .15), "cyan", .5)
		"toner":
			box(root, Vector3(.92, .32, .36), Vector3(0, .15, 0), "black")
			cyl(root, .11, .72, Vector3(0, .36, 0), "wallDark", 0.0, Vector3(0, 0, PI / 2))
		"paper":
			for i in range(4):
				box(root, Vector3(.86, .1, .62), Vector3(0, i * .09, 0), "wall")
			box(root, Vector3(.88, .09, .12), Vector3(0, .16, .28), "package")
		"barcode":
			box(root, Vector3(.18, .48, .2), Vector3(0, .2, 0), "black", 0.0, Vector3(0, 0, -.28))
			box(root, Vector3(.54, .28, .34), Vector3(.08, .49, 0), "wallDark")
			box(root, Vector3(.32, .12, .02), Vector3(.08, .49, .18), "screen", .3)
		_:
			box(root, Vector3(.72, .45, .55), Vector3(0, .2, 0), "package")
	return root
