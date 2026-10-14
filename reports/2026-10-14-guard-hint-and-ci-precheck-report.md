# 2026-10-14 · 修误导提示语 + 收口自检挂 CI 报告

## 结果摘要

**一句话**：落地上轮报告「后续建议 #2 与 #4」——① 修 `gen_plugins` 那条**方向错误**的提示语
（"先修 README"会把正确值改回错值）；② 把工具真源收口自检挂进 CI 现有步
（**避开并发会话正在编辑的 `ci.yml`**）。

| 项 | 读数 |
|---|---|
| 提示语方向 | 原"⇒ 拒绝投影（先修 README）"→ 改为"**先核真源扫描面**"并点名 `_tool_registry` |
| 收口自检挂 CI | 挂在 `check_plugin_sync.main()` 开头（该守卫**已在** CI Plugin-form guard 步）|
| 正常态 | `check_plugin_sync` **PASS**（4 宿主 / 64 文件 / 166 工具 / v0.3.8）|
| **变异实测** | 破坏收口 ⇒ `check_plugin_sync` **rc=2** 且首行报"工具真源模块自检失败"；还原后 rc=0 |
| 九项守卫链 | 全 PASS + `_tool_registry --selftest` 9 格全过 |
| **HEAD 干净树 moon check** | **rc=0**（104 tasks, 0 errors）|

提交 `1d20fb9`（2 文件），已推 origin + gitcode。

## ① 修误导提示语（建议 #4）

**原提示**（`gen_plugins.py`）：
```
die(f"README 分组和 {total} != 注册表实测 {n} ⇒ 拒绝投影（先修 README）")
```

**为什么这是反向指引**：2026-10-14 实测的真实场景是 **README 对、注册表真源读错**——
工具注册拆到多文件后真源扫描面没跟上（README 写 166、真源只扫 `server.mbt` 得 148）。
照原提示去改 README，会把**正确的 166 改回错值**。

**改为**：
```
README 分组和 {total} != 注册表实测 {n} ⇒ 拒绝投影。
**先核真源扫描面**：`scripts/_tool_registry.real_tools()` 是否覆盖了
`src/server/*.mbt` 全部注册点（含链式 `.tool(...)` 形态）——
若真源读少了，错的是真源不是 README（此时改 README 会把正确值改回错值）。
确认真源无误后，才轮到核 README 分组和。
```

⇒ 从"直接指路到错方向"改为"先给出两侧数字 + 点名先核真源"，
让读者能自己判断哪边错（并显式警告"改 README 可能改错"）。

## ② 收口自检挂 CI（建议 #2）

**问题**：上轮把"工具数真源怎么读"收口到 `scripts/_tool_registry.py`，但收口检查只在它自己的
`--selftest` 里 —— 若有人不跑该自检就改，收口仍可能被破坏（本轮的红正是漏改造成的）。

**挂法（关键：避开并发面）**：`ci.yml` 当时是并发会话的 ` M` 面（不宜改）。发现
**`check_plugin_sync.py` 已在 CI 的 Plugin-form guard 步里**，故在其 `main()` 开头加一步：
先跑 `_tool_registry.py --selftest`，红了直接 `return 2` 并打印
「FATAL 工具真源模块自检失败（`scripts/_tool_registry.py --selftest`）——
插件态比对的真源口径不可信，先修收口再读本守卫的结论」。

⇒ **零改动 `ci.yml`**，收口检查自动进 CI；且红面语义更准（不再让收口问题看起来像"插件漂移"）。

## L4 实测

**正常态**：
```
PASS 插件态一致：4 宿主 / 64 个生成文件 / 166 工具 / v0.3.8 / 启动参数真源 .mcp.dev.json
```

**变异实测（破坏收口）**：往 `mcp_smoke.py` 塞回本地实现 ⇒
```
rc=2
FATAL 工具真源模块自检失败（`scripts/_tool_registry.py --selftest`）——
      插件态比对的真源口径不可信，先修收口再读本守卫的结论：
      ...
还原后 rc=0
```
⇒ 预检真会红，且**红面直接指向收口**（而非误导到插件面）。

**九项守卫链全 PASS**：
```
check_plugin_sync         PASS 4 宿主 / 64 文件 / 166 工具
gen_plugins --check       OK 插件态与真源一致（166 工具 / v0.3.8）
check_tools_sync          PASS 166
check_doc_surface         PASS 166 逐个可查、分组和=166
check_scripts_index       PASS
check_pkg_imports         PASS
check_mbti_sync           PASS 597
check_py_stdout_encoding  PASS 29/29
check_ps_encoding         PASS 7 个 .ps1
_tool_registry --selftest 9 格全过
```

## 并发归因（本轮一次重要取证）

跑 `moon check --target js` 时工作树报 **10 errors**，而本轮**只改了 2 个 Python 脚本**。
取证：
1. `git status` 显示并发会话正在改 `src/router/model_router.mbt`、`router_state.mbt`、
   `model_router_ops.mbt`（均 ` M`）
2. **HEAD 干净树**（`git archive HEAD`）`moon check` = **rc=0（104 tasks, 0 errors）**

⇒ 工作树 10 errors 是**并发 WIP**，与本轮改动无关。**不据此改任何东西**（既不改他们的文件，
也不把自己的改动当"引发错误"回退）。

## 资源消耗

- `check_plugin_sync` 跑 3 次（正常 / 变异 / 还原）；九项守卫链 1 轮
- `moon check` 2 次（工作树 1 + HEAD 干净树 1）
- `git archive` 建树 1 次
- 零 `.mbt` 改动、零 `ci.yml` 改动（并发面）

## 任务分配记录

- 指挥官亲自：定位提示语 → 改方向（含显式警告）→ 找 CI 挂点（发现无需改 ci.yml）→
  加预检 → 变异实测 → 九项守卫链 → 并发归因（干净树对照）→ 精确 add 提交。
- **未派子代理**：本链要害是"提示语方向"与"并发 WIP 归因"，误判会改坏文档或误改他人文件。
- 边界：只改 2 个 Python 脚本；**未动 `ci.yml`**（并发面）、未动任何 `.mbt`。

## 遗留风险

1. **收口检查依赖 `check_plugin_sync` 被跑到**：若未来 CI 步序调整把它挪到硬门之后（被 skip），
   收口检查也会跟着失效（与本会话多次踩到的"判据挂了但没跑到"同型）。**建议**：
   长期应把 `_tool_registry --selftest` 直接作为 CI 独立一步（等 `ci.yml` 并发面收口后再加）。
2. **工作树 10 errors 属并发 WIP**：若他们提交前未修，CI 会红在 `Check (js)`。
   本报告已取证（干净树 rc=0），不代改他们的文件。
3. **提示语仍是字符串拼接**：`_tool_registry` 的模块名硬写在文案里；若模块改名需同步改文案
   （属低风险，且收口格会先红）。

## 后续建议

1. **`ci.yml` 并发面收口后，把 `_tool_registry --selftest` 提为独立 CI 步**（现在挂在
   `check_plugin_sync` 里是权宜，避免动并发面）。
2. **`fist help tools` 分组表改真源生成**（连续三轮已记，仍未做）：`real_tools()` 已可直接喂。
3. **给 `check_plugin_sync` 的预检加一格 selftest**（可选）：现在预检本身没有自证格
   （它的"会红"靠变异实测证明），可加"合成破坏 ⇒ 预检红"的格子。
4. **收口格的字符串匹配加容忍**（上轮已记）：支持 `from _tool_registry import ...` 写法。

## 超额内容

- 顺带**发现并利用了"无需改并发 ci.yml"的挂点**：通过"在已在 CI 的守卫里加预检"实现同样的
  CI 覆盖——这是在并发编辑约束下达成目标的实用手法（把改动放在自己能独占的文件里）。
- 顺带**做了一次干净的并发归因**：工作树 10 errors vs HEAD 干净树 0 errors ⇒ 证据指向并发 WIP，
  既不误改他人文件也不误回退自己的改动。
- 顺带**把提示语的"反向指引"问题显式化**：不只是改措辞，而是在提示里写明
  "改 README 可能把正确值改回错值"——把本轮踩过的坑写进工具输出，防下一位读者再踩。

## 来源

- 改动：`scripts/gen_plugins.py`（提示语方向）、`scripts/check_plugin_sync.py`（main 开头加预检）
- 正常态读数：`PASS 插件态一致：4 宿主 / 64 个生成文件 / 166 工具 / v0.3.8`
- 变异读数：破坏收口 ⇒ `rc=2` + `FATAL 工具真源模块自检失败…先修收口再读本守卫的结论`；还原 rc=0
- 并发归因：工作树 `Failed with 1643 warnings, 10 errors` vs HEAD 干净树
  `Finished. moon: ran 104 tasks … 0 errors`（rc=0）
- 提交：`1d20fb9`（2 文件，+27/-1）；三端同步 `1d20fb9`
