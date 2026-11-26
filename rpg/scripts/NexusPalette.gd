class_name NexusPalette
extends RefCounted
## NEXUS 原程序 gC() 材质表 + xC() 招牌 + pC() 门颜色的 Godot 复刻。
## 由主脚本 setup(map.palette) 注入真源，所有建模共用同一套材质缓存。

static var P: Dictionary = {}
static var _mats: Dictionary = {}

static func setup(p: Dictionary) -> void:
	P = p
	_mats.clear()

static func col(key: String) -> Color:
	return Color.html(str(P.get(key, "#D9DDE2")))

static func mat(key: String, glow := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var k := "%s|%s|%s" % [key, str(glow), str(alpha)]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col(key).r, col(key).g, col(key).b, alpha)
	m.roughness = 0.55
	m.metallic = 0.05
	if key == "metal" or key == "silver" or key == "base":
		m.metallic = 0.7
		m.roughness = 0.32
	if key == "glass":
		m.albedo_color.a = 0.28
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.08
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col(key)
		m.emission_energy_multiplier = glow
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[k] = m
	return m

## 直接用十六进制（区色、门色）建材质
static func hex(hexstr: String, glow := 0.0) -> StandardMaterial3D:
	var k := "hex|" + hexstr + "|" + str(glow)
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.html(hexstr)
	m.roughness = 0.42
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color.html(hexstr)
		m.emission_energy_multiplier = glow
	_mats[k] = m
	return m
