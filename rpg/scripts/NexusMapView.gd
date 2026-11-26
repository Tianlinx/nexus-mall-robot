class_name NexusMapView
extends Control
## 左上小地图 / M 大地图 / 主菜单装饰图共用。
## 配色全部取自 NEXUS 原程序 gC() palette（暖白地坪、深蓝灰框架、青紫灯带、木色展台）。

var game = null
var big := false
var decorative := false

func _draw() -> void:
	if game == null or game.map == null or game.map.is_empty():
		return
	var w := size.x
	var h := size.y
	var s: float = minf(w / 56.0, h / 48.0)
	var ox: float = (w - 56.0 * s) / 2.0
	var oy: float = (h - 48.0 * s) / 2.0
	var bg := NexusPalette.col("floor1")
	draw_rect(Rect2(0, 0, w, h), bg)

	# 栅格：障碍按官方材质上色，通道按 K-means 拥挤等级叠色
	for r in range(48):
		var row: String = str(game.map.grid[r])
		var trow: String = str(game.map.tiles[r])
		for c in range(56):
			var x: float = ox + c * s
			var y: float = oy + r * s
			if row[c] == "1":
				draw_rect(Rect2(x, y, s + 0.6, s + 0.6), cell_color(trow[c]))
			else:
				var cl: int = game.sys.eff_cong(c, r)
				if cl == 3:
					draw_rect(Rect2(x, y, s + 0.6, s + 0.6), Color(0.85, 0.32, 0.24, 0.30))
				elif cl == 2:
					draw_rect(Rect2(x, y, s + 0.6, s + 0.6), Color(0.95, 0.66, 0.35, 0.22))

	if big:
		for ch in game.map.channels:
			var x0: float = ox + (float(ch.x0) + 28.0) * s
			var z0: float = oy + (float(ch.z0) + 24.0) * s
			var ww: float = (float(ch.x1) - float(ch.x0)) * s
			var hh: float = (float(ch.z1) - float(ch.z0)) * s
			draw_rect(Rect2(x0, z0, ww, hh), Color(0.15, 0.78, 0.85, 0.25), false, 1.0)
			draw_string(game.font, Vector2(x0 + 3, z0 + 12), str(ch.id),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, NexusPalette.col("signBack"))
		for p in game.map.products:
			draw_circle(Vector2(ox + (float(p.col) + 0.5) * s, oy + (float(p.row) + 0.5) * s),
					maxf(1.5, s * 0.18), Color(0.39, 0.47, 0.55, 0.70))
		for z in game.map.zones:
			draw_string(game.font,
					Vector2(ox + (float(z.x) + 28.0) * s - 26, oy + (float(z.z) + 24.0) * s),
					"%s %s" % [z.id, z.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					NexusPalette.col("signBack"))

	if decorative:
		return

	# BFS / A* 规划路线
	if game.sys.plan.has("cells") and game.sys.plan.cells.size() > 1:
		var pts := PackedVector2Array()
		for cell in game.sys.plan.cells:
			pts.append(Vector2(ox + (cell.x + 0.5) * s, oy + (cell.y + 0.5) * s))
		draw_polyline(pts, NexusPalette.col("cyan"), 3.0 if big else 2.0, true)

	# 订单目标
	var oi := 0
	for it in game.sys.orders:
		var p = game.sys.find_product(it.id)
		if p == null:
			continue
		oi += 1
		var center := Vector2(ox + (float(p.col) + 0.5) * s, oy + (float(p.row) + 0.5) * s)
		var done: bool = game.sys.cargo.has(it.id)
		var col := Color(0.10, 0.58, 0.40) if done else NexusPalette.col("gateB")
		draw_circle(center, maxf(3.0, s * 0.42), col)
		if big:
			draw_string(game.font, center + Vector2(7, -5), "%d %s" % [oi, p.name],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, NexusPalette.col("signBack"))

	# 出入口
	var ga := Vector2(ox + (float(game.map.entry[0]) + 28.5) * s, oy + (float(game.map.entry[1]) + 24.5) * s)
	var gb := Vector2(ox + (float(game.map.exit[0]) + 28.5) * s, oy + (float(game.map.exit[1]) + 24.5) * s)
	draw_rect(Rect2(ga.x - 4, ga.y - 4, 8, 8), NexusPalette.col("gateA"))
	draw_rect(Rect2(gb.x - 4, gb.y - 4, 8, 8), NexusPalette.col("gateB"))
	if big:
		draw_string(game.font, ga + Vector2(7, 4), "Gate A 充电/进货", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, NexusPalette.col("signBack"))
		draw_string(game.font, gb + Vector2(7, 4), "Gate B 交付", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, NexusPalette.col("signBack"))

	# 玩家（第三人称下显示机器人位置与朝向）
	if game.player != null:
		var px: float = ox + (game.player.position.x + 28.0) * s
		var pz: float = oy + (game.player.position.z + 24.0) * s
		var a: float = game.yaw
		var f := Vector2(cos(a), sin(a))
		var r := Vector2(-sin(a), cos(a))
		var tip := Vector2(px, pz) + f * (9.0 if big else 6.0)
		var tri := PackedVector2Array([
			tip,
			Vector2(px, pz) - f * 5.0 + r * 4.0,
			Vector2(px, pz) - f * 5.0 - r * 4.0])
		draw_colored_polygon(tri, NexusPalette.col("metal"))
		draw_line(Vector2(px, pz), Vector2(px, pz) + f * 16.0,
				NexusPalette.col("cyan"), 1.0)

func cell_color(t: String) -> Color:
	if t == "#": return NexusPalette.col("wallDark")
	if t == "S": return NexusPalette.col("wood")
	if t == "D": return NexusPalette.col("slab")
	if t == ".": return NexusPalette.col("floor1")
	for z in game.map.zones:
		if z.id == t:
			return Color.html(z.color).lerp(NexusPalette.col("counter"), 0.25)
	return NexusPalette.col("wallDark")
