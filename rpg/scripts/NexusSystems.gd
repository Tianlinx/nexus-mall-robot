class_name NexusSystems
extends RefCounted
## 从 HTML 桌面版全量移植的经营 / RPG / 数据挖掘系统（无 UI 依赖）。
## Cost = w1·D + w2·C + w3·T + w4·R + w5·H，四类概念全部真正进入决策。

const DAY_LEN = 420.0
const W = {"D": 1.0, "C": 0.6, "T": 0.4, "R": 0.5, "H": 0.3}
## NEXUS v9.1 运行时避障口径（v9.0 消化说明 §2 + P0 两点已落地）：
## 立即局部 A* 绕障、让行实体侧移 0.7 m 并移出占用栅格，无路才短暂等待重试。
const REPLAN_RETRY_S = 0.6
const MAX_REPLAN_FAILURES = 5
const YIELD_SIDE_M = 0.7
const SKILL_DEF = [
	{"k": "battery", "n": "高密度电池", "d": "电量上限 +25%", "max": 3},
	{"k": "speed", "n": "伺服轮组", "d": "移动速度 +13%", "max": 3},
	{"k": "cargo", "n": "货舱扩展", "d": "货舱容量 +2 格", "max": 3},
	{"k": "bargain", "n": "议价协议", "d": "订单收入 +5%", "max": 3},
	{"k": "servo", "n": "精密机械臂", "d": "取货耗时 -22% / H -18%", "max": 3},
	{"k": "scanner", "n": "货位雷达", "d": "小地图显示目标指引线", "max": 1},
	{"k": "eco", "n": "节能固件", "d": "移动耗电 -14%", "max": 3},
	{"k": "chip", "n": "AI 路径芯片", "d": "解锁加权 Cost 导航与四算法对照", "max": 1},
]
const CLIENTS = ["北环 3 号公寓", "启明设计工作室", "LPL 训练基地", "云端网咖", "创客实验室",
		"南塔 12F 行政", "影像社 · 阿澄", "电竞社 · 老K", "数码巷 7 号", "联合办公 A 座",
		"实验室 B-204", "星海直播间"]

var map: Dictionary = {}
var by_id: Dictionary = {}
var stock: Dictionary = {}
var orders: Array = []
var cargo: Array = []
var money = 2600.0
var battery = 100.0
var rep = 3.0
var level = 1
var exp = 0.0
var pts = 0
var skills: Dictionary = {}
var day = 1
var clock = 0.0
var period = "正常"
var delivered = 0
var failed = 0
var revenue = 0.0
var cost = 0.0
var meters = 0.0
var risk = 0.0
var seq = 0
var today: Dictionary = {}
var quiz_done: Dictionary = {}
var logs: Array = []
var plan: Dictionary = {}
var weighted = false
var algo = "astar"
var day_summary: Dictionary = {}
var pending_day = false
## v9.1 运行时避障统计（对应界面「重规划次数 / 等待_s / 局部绕障次数」）
var replans = 0
var detours = 0
var wait_s = 0.0
var yield_count = 0
var last_avoid = ""
var leg_index = 0

class MinHeap:
	var a: Array = []
	func empty() -> bool: return a.is_empty()
	func push(f: float, i: int) -> void:
		a.append([f, i])
		var k = a.size() - 1
		while k > 0:
			var p = int((k - 1) / 2)
			if a[p][0] <= a[k][0]: break
			var tmp = a[p]; a[p] = a[k]; a[k] = tmp
			k = p
	func pop() -> Array:
		var top: Array = a[0]
		var last: Array = a.pop_back()
		if not a.is_empty():
			a[0] = last
			var k = 0
			while true:
				var l = k * 2 + 1
				var r = l + 1
				var m = k
				if l < a.size() and a[l][0] < a[m][0]: m = l
				if r < a.size() and a[r][0] < a[m][0]: m = r
				if m == k: break
				var tmp = a[m]; a[m] = a[k]; a[k] = tmp
				k = m
		return top

func setup(m: Dictionary) -> void:
	map = m
	by_id.clear()
	for p in map.products:
		by_id[p.id] = p
	reset()

func reset() -> void:
	stock.clear()
	for p in map.products:
		stock[p.id] = 2 if float(p.retail) > 6000.0 else 3
	orders.clear(); cargo.clear()
	money = 2600.0; battery = 100.0; rep = 3.0
	level = 1; exp = 0.0; pts = 0
	skills = {"battery": 0, "speed": 0, "cargo": 0, "bargain": 0,
			"servo": 0, "scanner": 0, "eco": 0, "chip": 0}
	day = 1; clock = 0.0; period = "正常"
	delivered = 0; failed = 0; revenue = 0.0; cost = 0.0; meters = 0.0; risk = 0.0
	seq = 0; quiz_done.clear(); logs.clear(); plan.clear()
	weighted = false; algo = "astar"; pending_day = false
	today = {"revenue": 0.0, "cost": 0.0, "done": 0, "failed": 0}
	for i in range(3):
		make_order()

func cap() -> int: return 6 + int(skills.cargo) * 2
func bat_max() -> float: return 100.0 + float(skills.battery) * 25.0
func need_exp() -> float: return 120.0 + (level - 1) * 95.0
func clock_str(t: float) -> String:
	var h = 9.0 + (t / DAY_LEN) * 9.0
	var mm = int(((t / DAY_LEN) * 9.0 - floor((t / DAY_LEN) * 9.0)) * 60.0)
	return "%02d:%02d" % [int(floor(h)), mm]
func fmt(v: float) -> String: return "¥%d" % int(round(v))

func add_log(msg: String, cls = "") -> void:
	logs.push_front({"t": clock_str(clock), "msg": msg, "cls": cls})
	if logs.size() > 8:
		logs.pop_back()

func find_product(id: String): return by_id.get(id, null)

# ---------------------------------------------------------------- 订单 / 经济
func order_pay(o: Dictionary) -> float:
	var v = 0.0
	for it in o.items:
		v += float(it.retail) * int(it.qty)
	return round(v * (1.0 + rep * .022 + float(skills.bargain) * .05) + float(o.tip))

func market(pid: String, near_gate_a = false) -> float:
	var p: Dictionary = by_id[pid]
	var heat = 0.0
	for r in map.rules:
		if r.b.has(pid):
			heat += .012
	var f = 1.0 + (0.14 if period == "高峰" else (-0.09 if period == "低峰" else 0.0)) + heat - rep * .008
	if near_gate_a:
		f -= .08
	return clampf(f, .74, 1.42)

func compat(items: Array) -> Array:
	var ids: Array = []
	for i in items:
		ids.append(i.id if i is Dictionary else str(i))
	var out: Array = []
	if ids.has("cpu") and ids.has("motherboard"):
		out.append({"t": "兼容", "s": "CPU(AM5) ↔ 主板(AM5)：插槽一致", "c": "g"})
	if ids.has("memory") and ids.has("motherboard"):
		out.append({"t": "兼容", "s": "DDR5 内存 ↔ 主板：代际一致", "c": "g"})
	if ids.has("gpu") and ids.has("power"):
		out.append({"t": "校验", "s": "显卡 320W + 平台 250W ≤ 电源 750W", "c": "g"})
	if ids.has("gpu") and ids.has("office_pc"):
		out.append({"t": "过滤", "s": "办公整机电源不可升级，共现 ≠ 兼容（§5.3）", "c": "r"})
	if ids.has("memory") and ids.has("macbook"):
		out.append({"t": "过滤", "s": "板载内存机型不可加装内存条（§5.3）", "c": "r"})
	return out

func make_order() -> void:
	if orders.size() >= 3:
		return
	seq += 1
	var picks: Array = []
	if randf() < .62:
		var L: Dictionary = map.lists[randi() % map.lists.size()]
		var st = randi() % maxi(1, L.items.size() - 2)
		for i in range(st, mini(L.items.size(), st + 2 + (randi() % 2))):
			picks.append(L.items[i])
	else:
		var seed: String = map.products[randi() % map.products.size()].id
		picks.append(seed)
		var rs: Array = []
		for r in map.rules:
			if r.a.has(seed):
				rs.append(r)
		if not rs.is_empty() and randf() < .75:
			picks.append(rs[randi() % rs.size()].b[0])
		var guard = 0
		while picks.size() < 2 + (randi() % 2) and guard < 30:
			guard += 1
			var q: Dictionary = map.products[randi() % map.products.size()]
			if not picks.has(q.id) and (randf() < .45 or q.zone == by_id[seed].zone):
				picks.append(q.id)
	var uniq: Array = []
	for pid in picks:
		if not uniq.has(pid):
			uniq.append(pid)
	uniq = uniq.slice(0, 4)
	var items: Array = []
	for pid in uniq:
		var p: Dictionary = by_id[pid]
		items.append({"id": pid, "name": p.name, "zone": p.zone, "rack": p.rack,
				"retail": p.retail, "wholesale": p.wholesale, "method": p.method,
				"H": p.H, "x": p.x, "z": p.z, "col": p.col, "row": p.row,
				"qty": 2 if float(p.retail) < 400 and randf() < .35 else 1, "got": 0})
	var o = {"id": "#%03d" % seq, "client": CLIENTS[randi() % CLIENTS.size()],
			"items": items, "tip": 40.0 + randf() * 160.0,
			"deadline": clock + 135.0 + items.size() * 28.0 + randf() * 40.0,
			"upsells": [], "upsold": []}
	o.pay = order_pay(o)
	var cand: Array = []
	for r in map.rules:
		var hit = false
		for a in r.a:
			if uniq.has(a): hit = true
		if not hit: continue
		var b: String = r.b[0]
		if uniq.has(b) or float(by_id[b].retail) > 12000.0: continue
		if _has_hard_block(compat([{"id": b}] + items)):
			continue
		var exists = false
		for c in cand:
			if c.pid == b: exists = true
		if not exists:
			cand.append({"pid": b, "rule": r, "extra": round(float(by_id[b].retail) * .55), "done": false})
	cand.sort_custom(func(a, b): return a.rule.lift > b.rule.lift)
	o.upsells = cand.slice(0, 2)
	orders.append(o)
	add_log("新订单 " + o.id + " · " + str(items.size()) + " 件 → " + fmt(o.pay), "a")

func _has_hard_block(notes: Array) -> bool:
	for n in notes:
		if n.t == "过滤": return true
	return false

func sync_cargo() -> void:
	for o in orders:
		for it in o.items:
			it.got = 0
	for c in cargo:
		for o in orders:
			var found = false
			for it in o.items:
				if it.id == c and it.got < it.qty:
					it.got += 1
					found = true
					break
			if found: break

func pick(pid: String) -> Dictionary:
	var p: Dictionary = by_id[pid]
	if cargo.size() >= cap():
		return {"ok": false, "msg": "货舱已满，去 Gate B 交付或升级货舱"}
	if int(stock[pid]) <= 0:
		return {"ok": false, "msg": str(p.name) + " 缺货，按 B 批发进货"}
	stock[pid] = int(stock[pid]) - 1
	cargo.append(pid)
	battery = maxf(0.0, battery - .35 - float(p.H) * .06)
	exp += 3.0 + float(p.H)
	sync_cargo()
	add_log("取货 " + str(p.name) + " · 库存 " + str(stock[pid]), "g")
	check_level()
	return {"ok": true, "msg": "已取货 " + str(p.name) + " · " + str(p.method) + " · H=" + str(p.H)}

func deliver() -> Dictionary:
	var ready: Array = []
	for o in orders:
		var ok = true
		for it in o.items:
			if it.got < it.qty: ok = false
		if ok: ready.append(o)
	if ready.is_empty():
		return {"ok": false, "msg": "没有齐货的订单，按清单补齐再交付"}
	ready.sort_custom(func(a, b): return a.pay > b.pay)
	var o: Dictionary = ready[0]
	var take: Array = []
	for it in o.items:
		for i in range(int(it.qty)):
			take.append(it.id)
	for pid in take:
		var idx = cargo.find(pid)
		if idx >= 0: cargo.remove_at(idx)
	money += o.pay; revenue += o.pay; today.revenue += o.pay
	delivered += 1; today.done += 1
	rep = clampf(rep + .045, 0.0, 5.0)
	exp += 24.0 + o.pay / 140.0
	orders.erase(o)
	sync_cargo()
	make_order()
	check_level()
	add_log("交付 " + o.id + " 收款 " + fmt(o.pay), "g")
	return {"ok": true, "msg": "订单 " + o.id + " 交付完成 +" + fmt(o.pay)}

func restock(pid: String, qty: int, near_gate_a = false) -> Dictionary:
	var p: Dictionary = by_id[pid]
	var price = ceil(float(p.wholesale) * float(qty) * market(pid, near_gate_a))
	if money < price:
		return {"ok": false, "msg": "资金不足，需要 " + fmt(price)}
	money -= price; cost += price; today.cost += price
	stock[pid] = int(stock[pid]) + qty
	add_log("进货 " + str(p.name) + " ×" + str(qty) + " " + fmt(price), "a")
	return {"ok": true, "msg": "进货 " + str(p.name) + " ×" + str(qty) + " · -" + fmt(price)}

func charge(near_gate_a: bool) -> Dictionary:
	if not near_gate_a:
		return {"ok": false, "msg": "请回到 Gate A 充电桩"}
	if money < 45.0:
		return {"ok": false, "msg": "资金不足，快充需 ¥45"}
	money -= 45.0; cost += 45.0; today.cost += 45.0
	battery = bat_max()
	return {"ok": true, "msg": "快速充电完成 · 电量 100%"}

func upsell(oid: String, idx: int) -> Dictionary:
	var o: Dictionary = {}
	for x in orders:
		if x.id == oid: o = x
	if o.is_empty() or idx >= o.upsells.size():
		return {"ok": false, "msg": "没有可用的关联推荐"}
	var u: Dictionary = o.upsells[idx]
	if u.done:
		return {"ok": false, "msg": "该推荐已加购"}
	var p: Dictionary = by_id[u.pid]
	if int(stock[u.pid]) <= 0:
		return {"ok": false, "msg": str(p.name) + " 缺货，先按 B 进货"}
	o.items.append({"id": u.pid, "name": p.name, "zone": p.zone, "rack": p.rack,
			"retail": p.retail, "wholesale": p.wholesale, "method": p.method,
			"H": p.H, "x": p.x, "z": p.z, "col": p.col, "row": p.row, "qty": 1, "got": 0})
	o.pay += u.extra
	o.upsold.append(u)
	u.done = true
	sync_cargo()
	add_log("关联加购 " + str(p.name) + " Lift=" + str(u.rule.lift), "g")
	return {"ok": true, "msg": "加购 " + str(p.name) + " +" + fmt(u.extra) + "（Lift " + str(u.rule.lift) + "）"}

func check_level() -> void:
	var guard = 0
	while exp >= need_exp() and guard < 20:
		guard += 1
		exp -= need_exp()
		level += 1
		pts += 1
		add_log("机体升级 → LV." + str(level) + " · 获得 1 技能点", "g")

func upgrade_skill(k: String) -> Dictionary:
	if pts < 1:
		return {"ok": false, "msg": "技能点不足"}
	var maxlv = 3
	for s in SKILL_DEF:
		if s.k == k: maxlv = int(s.max)
	if int(skills[k]) >= maxlv:
		return {"ok": false, "msg": "该技能已满级"}
	pts -= 1
	skills[k] = int(skills[k]) + 1
	if k == "battery": battery = bat_max()
	return {"ok": true, "msg": "升级成功：技能 " + k}

func quiz_answer(qi: int, oi: int) -> Dictionary:
	var q: Dictionary = map.quiz[qi]
	var right: bool = oi == int(q.a)
	if right and not quiz_done.has(qi):
		quiz_done[qi] = true
		exp += 25.0; money += 120.0
		check_level()
	return {"ok": right, "msg": q.e}

# ---------------------------------------------------------------- 时间 / 日结
func tick(dt: float) -> void:
	clock += dt
	risk = maxf(0.0, risk - dt * .25)
	battery = maxf(0.0, battery - dt * .014)
	if battery <= 0.0:
		money = maxf(0.0, money - dt * .8)
	for o in orders.duplicate():
		if clock > o.deadline:
			orders.erase(o)
			failed += 1; today.failed += 1
			rep = clampf(rep - .22, 0.0, 5.0)
			add_log("订单 " + o.id + " 超时", "r")
			sync_cargo()
			make_order()
	if clock >= DAY_LEN:
		day_end()

func day_end() -> Dictionary:
	var rent = 180.0 + day * 20.0
	money -= rent; cost += rent; today.cost += rent
	var profit = today.revenue - today.cost
	var grade = "S" if profit > 2500 else ("A" if profit > 1200 else ("B" if profit > 300 else ("C" if profit > -300 else "D")))
	day_summary = {"day": day, "revenue": today.revenue, "cost": today.cost - rent,
			"rent": rent, "profit": profit, "grade": grade,
			"done": today.done, "failed": today.failed}
	day += 1
	clock = 0.0
	period = ["正常", "高峰", "低峰"][day % 3]
	today = {"revenue": 0.0, "cost": 0.0, "done": 0, "failed": 0}
	orders.clear()
	for c in cargo:
		stock[c] = int(stock[c]) + 1
	cargo.clear()
	plan.clear()
	for i in range(3):
		make_order()
	pending_day = true
	return day_summary

# ---------------------------------------------------------------- 四大概念 → Cost
func eff_cong(c: int, r: int) -> int:
	var shift = 1 if period == "高峰" else (-1 if period == "低峰" else 0)
	return clampi(int(map.cong[r][c]) + shift, 1, 3)

func regress_t(ch: Dictionary, C: int) -> float:
	var pf = 0.4 if period == "低峰" else (1.8 if period == "高峰" else 1.0)
	var n = float(ch.get("customers", 6.0)) * pf
	return maxf(3.0, -6.738 + 1.393 * float(ch.L) - .377 * float(ch.W)
			+ 1.303 * n + 5.293 * float(C))

func classify(npc: Dictionary) -> Dictionary:
	var k = str(npc.kind)
	if k == "box": return {"cls": "临时障碍·纸箱", "R": .5}
	if k == "cart": return {"cls": "可移动·购物车", "R": .8}
	if k == "staff": return {"cls": "可移动·员工", "R": .6}
	return {"cls": "可移动·顾客", "R": .7}

func risk_grid(npcs: Array) -> Array:
	var g: Array = []
	for r in range(48):
		g.append(PackedFloat32Array())
		g[r].resize(56)
	for n in npcs:
		var info = classify(n)
		var c = int(floor(float(n.x) + 28.0))
		var r = int(floor(float(n.z) + 24.0))
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var cc = c + dx
				var rr = r + dy
				if cc < 0 or rr < 0 or cc >= 56 or rr >= 48: continue
				var d = Vector2(dx, dy).length()
				g[rr][cc] += float(info.R) * maxf(0.0, 1.0 - d / 3.5) * .55
	return g

func channel_at(c: int, r: int) -> Dictionary:
	var wx = -28.0 + float(c) + .5
	var wz = -24.0 + float(r) + .5
	for ch in map.channels:
		if wx >= float(ch.x0) and wx <= float(ch.x1) and wz >= float(ch.z0) and wz <= float(ch.z1):
			return ch
	return {}

func edge_cost(c: int, r: int, rg: Array) -> float:
	if not weighted:
		return 1.0
	var C = float(eff_cong(c, r)) / 3.0
	var ch = channel_at(c, r)
	var t = 0.0
	if not ch.is_empty():
		t = regress_t(ch, eff_cong(c, r)) / maxf(1.0, float(ch.L))
	var R = 0.0
	if not rg.is_empty():
		R = minf(2.0, float(rg[r][c]))
	return 1.0 + W.C * C + W.T * t + W.R * R

func free_cell(c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= 56 or r >= 48: return false
	var row: String = str(map.grid[r])
	return row[c] == "0"

## ---------------------------------------------------------------- v9.1 动态避障
## 动态占用格：让行实体按消化说明 P0 让出栅格（不进 dyn），其余实体仍占位。
func dynamic_cells(npcs: Array) -> Dictionary:
	var dyn: Dictionary = {}
	for n in npcs:
		if str(n.get("state", "")) == "让行":
			continue
		var c = int(floor(float(n.x) + 28.0))
		var r = int(floor(float(n.z) + 24.0))
		dyn[r * 56 + c] = true
	return dyn

## 双方贴近时优先安全脱离：实体沿垂直于机器人连线的方向侧移约 0.7 m，继续推进，不再原地冻结。
func step_yield(npcs: Array, robot_pos: Vector3, delta: float) -> int:
	var yielded := 0
	for n in npcs:
		if str(n.kind) == "box":
			continue
		var v := Vector2(float(n.x) - robot_pos.x, float(n.z) - robot_pos.z)
		var d := v.length()
		if d < 1.5 and d > .001:
			if str(n.get("state", "")) != "让行":
				yield_count += 1
			n.state = "让行"
			# 垂直方向（两侧任选，取更靠近可通行格的一侧）
			var side := Vector2(-v.y, v.x).normalized()
			var sx = float(n.x) + side.x * YIELD_SIDE_M * delta * 3.0
			var sz = float(n.z) + side.y * YIELD_SIDE_M * delta * 3.0
			if free_cell(int(floor(sx + 28.0)), int(floor(sz + 24.0))):
				n.x = sx; n.z = sz
			yielded += 1
		else:
			n.state = "通行"
	return yielded

## 下一格受阻 / 安全间距受阻 → 立即局部 A* 绕障（不等待）。返回绕行 cells。
func local_detour(a: Vector2i, b: Vector2i, rg: Array, dyn: Dictionary) -> Dictionary:
	var s = search(a, b, "astar", rg, dyn)
	if not s.cells.is_empty():
		detours += 1
		last_avoid = "下一格受阻 · 立即局部 A* 绕障"
	else:
		last_avoid = "局部绕路暂不可达 · 短暂等待后重试"
	return s

func search(a: Vector2i, b: Vector2i, mode: String, rg: Array, dyn: Dictionary = {}) -> Dictionary:
	var n = 56 * 48
	var dist = PackedFloat64Array(); dist.resize(n); dist.fill(INF)
	var prev = PackedInt32Array(); prev.resize(n); prev.fill(-1)
	var done = PackedByteArray(); done.resize(n)
	var s = a.y * 56 + a.x
	var g = b.y * 56 + b.x
	var h = MinHeap.new()
	var queue = PackedInt32Array()
	var head = 0
	var expanded = 0
	dist[s] = 0.0
	if mode == "bfs":
		queue.append(s)
	else:
		h.push(0.0 if mode == "dijkstra" else (float(abs(a.x - b.x) + abs(a.y - b.y)) * (3.0 if mode == "greedy" else 1.0)), s)
	var dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while true:
		if mode == "bfs":
			if head >= queue.size(): break
		elif h.empty():
			break
		var cur = 0
		if mode == "bfs":
			cur = queue[head]; head += 1
		else:
			cur = int(h.pop()[1])
		if done[cur] == 1: continue
		done[cur] = 1
		expanded += 1
		if cur == g: break
		var c = cur % 56
		var r = int(cur / 56)
		for d in dirs:
			var nc = c + d.x
			var nr = r + d.y
			if not free_cell(nc, nr): continue
			var ni = nr * 56 + nc
			# v9.1：动态占用格视为墙；让行实体已让出栅格，不在 dyn 中，故可绕行
			if dyn.has(ni) and ni != g: continue
			var nd = dist[cur] + edge_cost(nc, nr, rg)
			if nd < dist[ni]:
				dist[ni] = nd
				prev[ni] = cur
				if mode == "bfs":
					queue.append(ni)
				else:
					var hh = float(abs(nc - b.x) + abs(nr - b.y))
					var f = nd if mode == "dijkstra" else (hh * 3.0 if mode == "greedy" else nd + hh)
					h.push(f, ni)
	var cells: Array = []
	if done[g] == 1 or s == g:
		var i = g
		while i != -1:
			cells.append(Vector2i(i % 56, int(i / 56)))
			if i == s: break
			i = prev[i]
		cells.reverse()
	return {"cells": cells, "expanded": expanded, "dist": dist[g]}

func held_karp(D: Array, n: int) -> Dictionary:
	var full = (1 << n) - 1
	var dp: Array = []
	var par: Array = []
	for i in range(1 << n):
		var row = PackedFloat64Array(); row.resize(n); row.fill(INF)
		var prow = PackedInt32Array(); prow.resize(n); prow.fill(-1)
		dp.append(row); par.append(prow)
	for j in range(n):
		dp[1 << j][j] = D[0][j + 1]
	for mask in range(1, full + 1):
		for j in range(n):
			if (mask & (1 << j)) == 0 or is_inf(dp[mask][j]): continue
			for k in range(n):
				if (mask & (1 << k)) != 0: continue
				var nm = mask | (1 << k)
				var v = dp[mask][j] + D[j + 1][k + 1]
				if v < dp[nm][k]:
					dp[nm][k] = v
					par[nm][k] = j
	var best = INF
	var last = -1
	for j in range(n):
		var v = dp[full][j] + D[j + 1][n + 1]
		if v < best:
			best = v; last = j
	var seq: Array = []
	var mask = full
	while last >= 0:
		seq.append(last)
		var p = int(par[mask][last])
		mask ^= 1 << last
		last = p
	seq.reverse()
	return {"seq": seq, "length": best}

func plan_route(player_pos: Vector3, npcs: Array) -> Dictionary:
	if orders.is_empty(): return {}
	var o: Dictionary = orders[0]
	var pids: Array = []
	for it in o.items:
		if not pids.has(it.id): pids.append(it.id)
	pids = pids.slice(0, 8)
	var pts: Array = [Vector2i(int(floor(player_pos.x + 28.0)), int(floor(player_pos.z + 24.0)))]
	for pid in pids:
		var p: Dictionary = by_id[pid]
		pts.append(Vector2i(int(p.col), int(p.row)))
	pts.append(Vector2i(54, 46))
	var n = pids.size()
	var rg = risk_grid(npcs)
	var dyn = dynamic_cells(npcs)
	var D: Array = []
	for i in range(n + 2):
		var row = PackedFloat64Array(); row.resize(n + 2); row.fill(0.0)
		D.append(row)
	var matrix_exp = 0
	for i in range(n + 2):
		for j in range(i + 1, n + 2):
			var s = search(pts[i], pts[j], "astar", rg, dyn)
			var v = float(s.cells.size() - 1) if s.cells.size() > 0 else 999.0
			D[i][j] = v; D[j][i] = v
			matrix_exp += int(s.expanded)
	var hk = held_karp(D, n)
	var visit: Array = [0]
	for i in hk.seq: visit.append(i + 1)
	visit.append(n + 1)
	var cells: Array = []
	var expanded = 0
	for k in range(visit.size() - 1):
		var s = search(pts[visit[k]], pts[visit[k + 1]], algo, rg, dyn)
		expanded += int(s.expanded)
		for i in range(s.cells.size()):
			if k > 0 and i == 0: continue
			cells.append(s.cells[i])
	var Dm = maxi(0, cells.size() - 1)
	var Csum = 0.0
	var Rsum = 0.0
	var ch_cells: Dictionary = {}
	for cell in cells:
		Csum += float(eff_cong(cell.x, cell.y))
		if not rg.is_empty(): Rsum += minf(2.0, float(rg[cell.y][cell.x]))
		var ch = channel_at(cell.x, cell.y)
		if not ch.is_empty():
			ch_cells[ch.id] = int(ch_cells.get(ch.id, 0)) + 1
	var Tsum = 0.0
	for cid in ch_cells:
		var ch = channel_at(-1, -1)
		for c in map.channels:
			if c.id == cid: ch = c
		if ch.is_empty(): continue
		Tsum += regress_t(ch, 2) * minf(1.0, float(ch_cells[cid]) / maxf(1.0, float(ch.L)))
	var Cavg = Csum / maxf(1.0, float(cells.size()))
	var Ravg = Rsum / maxf(1.0, float(cells.size()))
	var Hsum = 0.0
	for it in o.items:
		Hsum += float(it.H) * (1.0 - float(skills.servo) * .18)
	var parts = [
		{"k": "D", "n": "距离 (m)", "v": float(Dm), "w": W.D, "src": "A* 栅格距离 §8"},
		{"k": "C", "n": "通道拥挤 (K-means)", "v": Cavg, "w": W.C, "src": "聚类 §7"},
		{"k": "T", "n": "通行时间 (回归, s)", "v": Tsum, "w": W.T, "src": "回归 §7"},
		{"k": "R", "n": "碰撞风险 (决策树)", "v": Ravg, "w": W.R, "src": "分类 §6"},
		{"k": "H", "n": "处理成本 (Pickup_Method)", "v": Hsum, "w": W.H, "src": "关联规则/取货 §5"},
	]
	var total = 0.0
	for p in parts:
		p.c = p.v * p.w
		total += p.c
	plan = {"oid": o.id, "seq": [], "cells": cells, "D": Dm, "C": Cavg, "T": Tsum,
			"R": Ravg, "H": Hsum, "parts": parts, "cost": total, "expanded": expanded,
			"matrix_exp": matrix_exp, "algo": algo, "weighted": weighted,
			"eta": int(round(Tsum * .55 + float(Dm) / 3.15 + Hsum * 1.5))}
	for i in hk.seq:
		plan.seq.append(pids[i])
	return plan

func algo_compare(player_pos: Vector3, npcs: Array) -> Array:
	if orders.is_empty(): return []
	var p: Dictionary = by_id[orders[0].items[0].id]
	var a = Vector2i(int(floor(player_pos.x + 28.0)), int(floor(player_pos.z + 24.0)))
	var b = Vector2i(int(p.col), int(p.row))
	var rg = risk_grid(npcs)
	var out: Array = []
	for m in ["astar", "dijkstra", "greedy", "bfs"]:
		var s = search(a, b, m, rg)
		out.append({"mode": m, "name": {"astar": "A*", "dijkstra": "Dijkstra", "greedy": "Greedy", "bfs": "BFS"}[m],
				"length": maxi(0, s.cells.size() - 1), "expanded": int(s.expanded),
				"cover": "%.1f" % (float(s.expanded) / 1630.0 * 100.0)})
	return out

# ---------------------------------------------------------------- 存档
func state_dict() -> Dictionary:
	return {"money": money, "battery": battery, "rep": rep, "level": level,
			"exp": exp, "pts": pts, "skills": skills, "day": day, "clock": clock,
			"period": period, "delivered": delivered, "failed": failed,
			"revenue": revenue, "cost": cost, "meters": meters, "seq": seq,
			"stock": stock, "orders": orders, "cargo": cargo, "quiz_done": quiz_done,
			"today": today, "weighted": weighted, "algo": algo}

func load_state(d: Dictionary) -> void:
	var allowed = ["money", "battery", "rep", "level", "exp", "pts", "skills",
			"day", "clock", "period", "delivered", "failed", "revenue", "cost",
			"meters", "seq", "weighted", "algo"]
	for k in allowed:
		if d.has(k):
			set(k, d[k])
	orders = d.get("orders", [])
	cargo = d.get("cargo", [])
	stock = d.get("stock", stock)
	quiz_done = d.get("quiz_done", {})
	today = d.get("today", today)
	sync_cargo()
