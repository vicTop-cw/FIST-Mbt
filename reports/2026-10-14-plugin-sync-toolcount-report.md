# 2026-10-14 · 闭合插件态同族缺口报告（check_plugin_sync / gen_plugins 真源扩面）

## 结果摘要

**一句话**：上轮报告「后续建议 #1」落地——工具注册拆分后，`check_plugin_sync.py` 与 `gen_plugins.py`
的真源仍只扫 `server.mbt`（148），造成**生成器与守卫互相矛盾**（一个产 166、一个判 148）。
本轮把两处口径扩到与另三支一致（共五处同口径），并重生成四宿主投影。

| 项 | 修前 | 修后 |
|---|---|---|
| `check_plugin_sync` | **红**（`J1 漂移：gen_plugins --check 退出码 2，README 分组和 166 != 注册表 148`）| **PASS**（4 宿主 / 64 生成文件 / **166 工具** / v0.3.8）|
| `gen_plugins --check` | **红**（17 个投影与真源不一致）| 重生成后一致 |
| 真源口径 | 5 处中 2 处停在 148 | **5 处统一 166** |

提交 `6d330e2`（19 文件：2 脚本 + 17 插件投影），已推 origin + gitcode。

## 症状链（生成器与守卫互相矛盾）

这是本缺口最值得记的地方——**不是简单的"数不对"，而是两个工具互掐**：

```
$ python scripts/check_plugin_sync.py
FAIL 插件态（一源四态 cl7）不一致（真源 148 工具 / v0.3.8）：
- J1 插件态漂移：gen_plugins.py --check 退出码 2
  （FATAL 真源自证失败：README 分组和 166 != 注册表实测 148 ⇒ 拒绝投影（先修 README））
```

⇒ 守卫说"去修 README"，但 README 的 166 是**对的**（上轮已按运行态真值改过），错的是守卫自己
读的注册表（只扫 server.mbt）。**若不先修口径而照守卫提示去改 README，会把正确的文档改回错值**
——这正是"判据自己旧了比没有判据更危险"的实例（与上轮 `check_doc_surface` 假绿同族）。

修 `gen_plugins` 口径后重生成，守卫又报另一半：
```
- J6 plugins\atomcode\skills\fist-mbt\SKILL.md 有 1 处 tools= 声明，其中与实测 148 不符的是 ['166']
```
⇒ 生成器已产 166、守卫仍判 148。**两个方向的红都指向同一根因**（真源扫描面），
只有把两处口径一起改才收敛。

## 修法（五处统一口径）

与 `check_tools_sync` / `check_doc_surface` / `mcp_smoke` 同一实现：

```python
real_tools() = src/server/*.mbt（排除 _test/_wbtest）里
  ① instrumented_tool(<var>, "name", …)
  ② 链式 <var>.tool("name", …)        ← mcpcf_embed.mbt 的 7 个走这条
  两形态的并集
```

改动点：
- `gen_plugins.py`：新增 `RE_TOOL_CHAIN` / `SERVER_DIR` / `real_tools()`；`measure()` 改调 `real_tools()`
- `check_plugin_sync.py`：同样新增并改调（原 L109 单文件读）
- 重生成：`python scripts/gen_plugins.py` ⇒
  `OK 已生成四宿主插件态：166 工具 / v0.3.8 / BUG-1~154 共 152 条入账：0 条待修 / 138 条已修 / 9 条重复并入 / 5 条误报`

**生成前安全检查**：实测 `plugins/` + `README.md` 脏条目 = **0**（无人 WIP），故重生成不会覆盖他人改动。

## L4 实测（十支判据全跑）

| 判据 | 结果 |
|---|---|
| `check_plugin_sync` | **PASS** 4 宿主 / 64 生成文件 / 166 工具 / v0.3.8 / 启动参数真源 .mcp.dev.json |
| `check_tools_sync` | PASS 166 个，四份文档对齐 |
| `check_doc_surface` | PASS 166 逐个可查、分组和=166 |
| `check_scripts_index` | PASS |
| `check_pkg_imports` | PASS（23 份 moon.pkg / 30 条 import）|
| `check_mbti_sync` | PASS（23 份 .mbti / 597 条 pub 声明）|
| `check_py_stdout_encoding` | PASS（29/29）|
| `check_ps_encoding` | PASS（7 个 .ps1）|
| `check_test_sync` | PASS（1033，120 份文档 20 条声明一致）|
| `check_badge` | PASS（tests-1033%2F1033）|

⇒ **十支判据全绿**，工具计数口径在五个消费者间完全一致。

## 资源消耗

- `check_plugin_sync` 3 次（修前红 / 修 gen 后另一半红 / 修 sync 后 PASS）
- `gen_plugins --check` 1 次、`gen_plugins` 生成 1 次（19 文件）
- 十支判据各 1 次（含需参数的两支）
- 零 `.mbt` 逻辑改动、零网络请求（除 push）

## 任务分配记录

- 指挥官亲自：确认遗留缺口 → 跑守卫取症状 → 定位"生成器↔守卫互掐" → 两处口径同修 →
  安全检查（脏条目=0）→ 重生成 → 十支判据全跑 → 精确 add 提交。
- **未派子代理**：本链要害是"守卫的提示本身是错的"这一判断（照提示改会改坏文档），外包易被误导。
- 边界：只改 2 支脚本口径 + 17 个由其生成的投影；`git add` 精确列 `plugins/` + 2 脚本
  （并发会话的 `ci.yml`/`model_router.mbt`/`reports/*` 等未连带）。

## 遗留风险

1. **`fist help tools` 的分组表仍手写**（上轮已记）：工具增减需人工同步该表；
   本轮生成器只投影插件态，CLI 帮助表仍是手写面。
2. **真源口径已有五处复制实现**（check_tools_sync / check_doc_surface / check_plugin_sync /
   gen_plugins / mcp_smoke 各写一份 `real_tools`）：本轮把它们对齐了，但**下次拆分仍会漏**
   ⇒ 建议抽成 `scripts/_tool_registry.py` 单一实现（属重构，影响 5 个消费者，留 owner 决定）。
3. **`check_plugin_sync` 的 J1 提示语会误导**：它把"真源自证失败"的锅推给 README
   （`⇒ 拒绝投影（先修 README）`）。本轮实测该提示方向是错的。建议把提示改成
   "先核注册表真源扫描面是否跟上工具拆分"。

## 后续建议

1. **抽单一 `real_tools()` 实现**（价值最高）：现 5 处复制，本轮刚因漏改 2 处而红。
   抽成 `scripts/_tool_registry.py` 后 5 个消费者 import 它，从结构上消除"漏改"。
2. **修 `check_plugin_sync` J1 的提示语**：把"先修 README"改为"先核真源扫描面"，
   避免下一位读者照错方向改文档（本轮的真实陷阱）。
3. **`fist help tools` 分组表改真源生成**：消掉手写漂移面。
4. **给"五处口径一致"加一支交叉判据**（可选）：断言 5 个消费者的 `real_tools()` 结果集相同
   ⇒ 任何一处漏改立即红。

## 超额内容

- 顺带**实测出"生成器与守卫互掐"这一新形态**：不是单点数不对，而是两个工具各持一个口径、
  彼此把对方的正确输出判成错。本轮把两处一起改才收敛——单改任一处都只会换一个红。
- 顺带**发现守卫提示语方向错误**（"先修 README"）：照它改会把正确的 166 改回错值。
  这比"提示不清"更危险（是反向指引），已写入后续建议 #2。
- 顺带**把真源口径的复制面量化**（5 处），并给出抽单一实现的建议——本轮的红正是漏改 2 处造成的。

## 来源

- 症状：`check_plugin_sync` 红（`J1 … README 分组和 166 != 注册表实测 148`）；
  修 gen 口径后 `J6 … tools=166 与实测 148 不符`
- 改动：`scripts/gen_plugins.py`（+RE_TOOL_CHAIN/SERVER_DIR/real_tools，measure 改调）、
  `scripts/check_plugin_sync.py`（同）
- 重生成：`python scripts/gen_plugins.py` ⇒ `166 工具 / v0.3.8 / 152 条入账`
- 读数：`check_plugin_sync` PASS（4 宿主 / 64 文件 / 166 工具）；十支判据全 PASS
- 提交：`6d330e2`（19 文件）；三端同步 `6d330e2`
