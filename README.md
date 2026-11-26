# NEXUS · 电脑城机器人路径规划与数据挖掘演示

一个**单文件、可离线运行**的教学演示程序：在 56 × 48 m 的电脑城场景中规划机器人取货路线，把关联规则、聚类与回归等数据挖掘结果接进路径成本，并演示随机动态障碍下的局部重规划与取货停留。

---

## 🎮 下载 RPG 游戏（可玩）

仓库里还有一个**第三人称机器人模拟经营 RPG**，Godot 4.3 原生导出的 Windows 单文件 exe，免安装、双击即玩：

- **下载页（推荐）**：https://tianlinx.github.io/nexus-mall-robot/rpg.html —— 有截图、玩法与按键说明
- **直接下载**：https://github.com/Tianlinx/nexus-mall-robot/releases/latest —— 在 Assets 里点 `NEXUS-RPG-Windows-x64.exe`（约 85 MB）

你是 R-07 号零售机器人：接单 → 查库存、缺货批发进货 → 穿行电脑城到 75 个货位取货 → Gate B 交付结算 → 用差价升级机体。含主界面、7 步新手教程、左上小地图 + `M` 全屏大地图、清单指引、自动存档、暂停与退出。

按键：`WASD` 移动 · 鼠标环绕视角 · `Shift` 冲刺 · `E` 取货 · `F` 交付 · `B` 进货 · `N` 导航/Cost 面板 · `V` 自动导航 · `M` 大地图 · `Tab` 订单 · `K` 知识库 · `U` 技能 · `G` 关联加购 · `R` 充电 · `ESC` 暂停。

**v9.1 避障口径**：下一格或安全间距受阻立即局部 A\* 绕障；无可行绕路才等待 0.6 s 重试，连续 5 次失败上报路段阻塞；让行实体沿垂直方向侧移 0.7 m 并移出动态占用栅格；段切换重绘路线，终点不再连回中间点。几何、16 组基线、seed 20261113、服务时间 S 独立于 T、Cost 与 w₁–w₅ 均未改动。

> Releases 里的 exe 由维护者在本机用 Godot 4.3 导出并验证后上传；[`build-rpg.yml`](.github/workflows/build-rpg.yml) 提供可复现构建，在 Actions 页手动 Run workflow 即可重新生成。首次运行 Windows 可能提示「已保护你的电脑」，点「更多信息 → 仍要运行」即可（未签名的个人项目）。

---

## 直接运行

- 双击仓库根目录的 `index.html`，用较新版本的 Chrome / Edge 打开即可，**无需安装、无需联网、无需构建**。
- 或在本目录执行 `python -m http.server 8000`，再访问 `http://localhost:8000`。
- 在线演示：`https://tianlinx.github.io/nexus-mall-robot/`（GitHub Pages，浏览器直接打开即用）。

所有计算都在浏览器本地完成，不上传任何数据。演示页右上角有 RPG 下载入口。

## 功能

| 模块 | 内容 |
|---|---|
| 场景 | 10 区 A–J、29 组货架、75 类商品、37 个静态障碍；0.42 m 障碍膨胀与 1 m 占用栅格 |
| 路径 | A\*、Dijkstra、BFS、Greedy 四算法对比，输出路径长度、扩展节点与耗时 |
| 挖掘 | Apriori / ECLAT 关联规则、商品分类与兼容性校验、人流聚类、通行时间回归 |
| 决策 | `Cost = w₁D + w₂C + w₃T + w₄R + w₅H`，权重可调 |
| 运行时 | 固定种子的随机动态障碍、立即局部绕障、让行实体安全脱离、每点取货停留 S 与倒计时 |
| 导出 | 基线自检、实验 CSV（UTF-8 BOM）与扩展 JSON |

## 数据与口径

- 几何、客流与交易数据均为**教学合成数据**，不代表真实卖场，也不是真实机器人系统。
- 静态基线为程序实测；合成动态实体的结果单列为扩展实验，不回写基线。
- 取货服务时间 `S` 独立于通行时间 `T`，两者不混算。
- 程序不含真实传感器检测、机械抓取与机器人控制；动态实体是固定种子的可复现轨迹。

## 目录

| 路径 | 内容 |
|---|---|
| `index.html` | 单文件离线演示（Three.js 已内联） |
| `rpg.html` | 第三人称 RPG 下载页（GitHub Pages） |
| `rpg/` | Godot 4.3 工程源码：`scripts/` 7 个 GDScript、`data/nexus_map.json` 真源、`project.godot`、`export_presets.cfg` |
| `.github/workflows/build-rpg.yml` | 自动构建 Windows exe 并发布 Release |
| `data/NEXUS_几何摘要.json` | 场景几何摘要 |
| `data/NEXUS_通道清单.csv` | 通道清单 |
| `data/NEXUS_占用栅格_56x48.txt` | 占用栅格 |
| `LICENSE` | MIT 许可证与第三方许可声明 |

## 制作人员 / Contributors

- [@Tianlinx](https://github.com/Tianlinx) — 仓库维护与发布
- [@ifuowwww](https://github.com/ifuowwww) — 协作开发

## 第三方组件

Three.js（MIT License）已内联进 `index.html`，其许可全文见 `LICENSE` 末尾。Godot 引擎（MIT）用于构建 `rpg/`，exe 内嵌其运行时；课程场景与数据仅作教学用途。

## 许可证

MIT，详见 `LICENSE`。
