# Round 6 收口 · cl7 插件投影失同步修复 + 发布载荷面 P1 发现

- **轮次**：2026-10-19 10:20 · FIST-Mbt 自驱迭代 Round 6/256 · bugfind+polish
- **角色**：fist-mbt-round6-lead
- **结论**：整树门禁基本全绿，但**本轮自己引入一处 cl7 失同步已修复**，另发现**发布载荷面 P1**（并发 agent 的未跟踪文件）。

---

## 结果摘要

| 事项 | 结果 |
|---|---|
| `moon test --target js` | **1333 passed / 1333 / 0 failed** |
| `scripts/check_test_sync.py` | **PASS**（16 声明==1333，must-carry 5 齐全，25 豁免有效） |
| `scripts/check_doc_surface.py` | **PASS**（170 工具、v0.3.9、J6~J15 全绿） |
| `scripts/check_tools_sync.py` | **PASS**（server.mbt 注册 170，四态对齐） |
| `scripts/check_plugin_sync.py`（cl7） | 首跑 **红 rc=1** → 再生 → **回绿 PASS** |
| `scripts/check_publish_payload.py`（BUG-127） | **红 P1 × 8**（并发 agent 未跟踪文件） |
| `issue_scan`（src/ 全量） | **medium=0 / high=0**（9852 条全 low/info 子串近似噪声） |

## 交付物

1. **cl7 插件投影再生**（提交 `82baa78`，9 文件 17+/17-）——根因是我上一轮 `415720b` 把 BUG-325/326/327 加进 `memory/bugs.md`，插件投影读缺陷账本停在 324。已 `gen_plugins.py` 再生回绿。
2. **Round 6 记忆**：`memory/2026-10-19.md` 追加 Round 6 段。
3. **本轮报告**：`reports/2026-10-19-fist-mbt-round6-gates-and-publish-finding-report.md`。

## 证据表

### cl7 失同步（已修复）

```
check_plugin_sync 首跑：rc=1
  - atomcode\skills\fist-mbt\SKILL.md：内容不一致
  - claude\skills\fist-commander\SKILL.md：内容不一致
  - claude\skills\fist-mbt\SKILL.md：内容不一致

git diff plugins\claude\skills\fist-mbt\SKILL.md：
-     ledger=BUG-1~324 共 324 条入账：11 条待修 / 292 条已修 …
+     ledger=BUG-1~327 共 327 条入账：13 条待修 / 292 条已修 …

python scripts\gen_plugins.py → OK 已生成四宿主插件态：170 工具 / v0.3.9 / BUG-1~327
check_plugin_sync 复跑 → PASS 插件态一致：4 宿主 / 64 个生成文件 / 170 工具 / v0.3.9
提交 82baa78：9 files changed, 17 insertions(+), 17 deletions(-)
```

### 发布载荷面 P1（待处置，非本轮擅动）

```
check_publish_payload → rc=1
VIOLATION P1 scripts/_gen.py                 未被 .gitignore 挡住又没被 git 跟踪
VIOLATION P1 scripts/fix_esm_require.py      同上
VIOLATION P1 scripts/pol_keeper_run.py       同上
VIOLATION P1 src/evidence/auto_repair.mbt    同上
VIOLATION P1 src/evidence/evidence_test.mbt  同上
VIOLATION P1 src/evidence/moon.pkg           同上
VIOLATION P1 src/evidence/spec.mbt           同上
VIOLATION P1 src/evidence/store.mbt          同上

凭据形状扫描（8 文件，~30058 bytes）：credential_hits = 0
⇒ 纯 P1 源码公开风险，非 P2 秘密泄漏；内容安全，仅未入库。
```

## 资源消耗

- 工具调用：`issue_scan` ×1、`bug_list` ×1、pwsh 命令 ×6（测试/判据/凭据扫描/提交）、`edit` ×1、`write` ×1。
- 临时文件：`temp/mt6.log`（1333 测试输出，check_test_sync 已用）、`temp/cred_scan.py`（凭据扫描）——**已删除**。
- 提交：`82baa78`（1 笔，仅插件再生，未卷入并发 agent 文件）。

## 任务分配记录

- 本轮为**指挥官自驱**，未分派子代理。所有工作由本轮 lead 直接完成（判据复跑 + 插件再生 + 凭据扫描）。

## 遗留风险

1. **check_publish_payload P1 × 8**：并发 agent 的 `src/evidence/` 与 3 个 `scripts/*.py` 仍未跟踪。凭据形状 0 命中，但 `moon publish` 会公开。**修法**：入库（若属正式 feature）或进 `.gitignore`（若属临时脚本）。属并发 agent 域，本轮未擅动。
2. **BUG-327 OPEN**（OCR 对 MoonBit 恒 `unsupported_ext`，`require_ocr` 门伪能力）——修复单 T0r588 待领取。
3. **守卫窄面**：安全写法 `substring(start = n - n % k, end = n)` / `start = p, end = p + 2` 仍被误报（本仓零实例）。
4. **仍等用户裁决 3 项**：15fe403 撤回 / BUG-268 标号错配 / `src/evidence/` 收编或清理。

## 后续建议

1. 请用户或并发 agent 就 P1 定夺：`src/evidence/` 是 feature 就**提交**，是临时探测就**进 `.gitignore`**；3 个 `scripts/*.py` 同理。
2. 下一轮可驱动 **BUG-327**（T0r588）：让 `require_ocr` 门对 `unsupported_ext` 采取 fail-closed，或给 `ocr_scan` 的 `.mbt` 结果加显式 notice（不再顶层 `ok=true` 假绿）。
3. 下一轮可补 **守卫窄面**：新增 `scan_guard_end_var_exact`（要求守卫比较变量 == end 变量）+ 正/负控锁，消除安全写法误报。
4. **流程沉淀**：加 bug 账必带 `gen_plugins.py` 再生，否则 cl7 红——已记入记忆。

## 超额内容

- 无未申报的 src/ 改动；本轮 0 处 src/server 逻辑改动。
- 顺手做了全量门禁巡检（doc/tools/plugin/publish/issue_scan），补全健康画像。

## 来源

- 判据输出：`check_test_sync.py` / `check_doc_surface.py` / `check_tools_sync.py` / `check_plugin_sync.py` / `check_publish_payload.py` / `gen_plugins.py`。
- 测试：`moon test --target js`（1333/1333）。
- 账本：`memory/bugs.md`（327 条，13 待修）。
- 提交：`415720b`（Round 5）、`82baa78`（Round 6 插件再生）。