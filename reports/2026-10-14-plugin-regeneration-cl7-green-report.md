# 2026-10-14 · 重生成插件态修 check_plugin_sync——一源四态 cl7 归绿（Round 113）

## 结果摘要

**一句话**：并发 agent 提交 `927c14b`（P1.1 executor_run 备用模型自动切换）后工作树干净、工具数稳定 166、投影源全部干净，
**安全窗口出现**——重生成插件态（`gen_plugins.py`），**`check_plugin_sync` 从连续多轮红归绿**（commit `e8d04ec`）。
5 守卫（plugin_sync/doc_surface/tools_sync/template_ctrl/scripts_index）**全 PASS**。三端同步 `e8d04ec`。

## 实测证据

### 环境快照（重生成前）
| 项 | 读数 |
|---|---|
| 并发 agent 最新提交 | `927c14b`（P1.1 executor_run 备用模型自动切换） |
| 工作树未提交 | **0**（检查时） |
| `check_tools_sync` | PASS（工具数稳定 **166**，R3b/R7 扫现状面 137 份） |
| 投影源（plugins/source + server.mbt + moon.mod + bugs.md） | **全部干净** |
| `check_plugin_sync` | FAIL（9 文件漂移：README + 4 宿主 SKILL.md×2 + deepseek-harness instructions.append） |

### 重生成前判定链（为何此时安全）
1. **工作树干净** → 无并发 WIP 冲突
2. **投影源干净** → 重生成产物可确定
3. **工具数稳定 166** → 投影工具数确定
4. **BUG 账本含 BUG-156** → 重生成会同步入账（输出"BUG-1~156 共 154 条：2 待修/138 已修/9 其他"）

### 重生成结果
- `gen_plugins.py` 输出：`OK 已生成四宿主插件态：166 工具 / v0.3.8 / BUG-1~156 共 154 条入账`
- `check_plugin_sync`：**PASS** `插件态一致：4 宿主 / 64 个生成文件 / 166 工具 / v0.3.8 / 启动参数真源 .mcp.dev.json`
- 改动：**9 个插件投影文件**（README.md + atomcode/codearts/claude/deepseek-harness 的 SKILL.md + instructions.append.md），21 insertions / 17 deletions

### 并发 WIP 识别（关键）
重生成后 `git status` 显示 10 份改动，其中 **`src/router/model_router.mbt`** 被改——
`git diff` 确认是并发 agent 刚加的 **P1.1 cooldown_until**（`ModelQuota` 加 `mut cooldown_until : String` + `mark_failure` + `in_cooldown`）。
**检查工作树"干净"后并发 agent 又动了**——精确提交 9 个插件文件，**不碰 src/router/model_router.mbt**。

### 提交后守卫链
| 守卫 | 状态 |
|---|---|
| `check_plugin_sync` | **PASS**（此前连续多轮红） |
| `check_doc_surface` | PASS |
| `check_tools_sync` | PASS |
| `check_template_ctrl` | PASS |
| `check_scripts_index` | PASS |

**5 守卫全绿**，三端 `e8d04ec`。

## 交付（commit `e8d04ec`）

9 个插件投影文件重生成：`plugins/README.md` + `plugins/atomcode/skills/fist-commander/SKILL.md` +
`plugins/atomcode/skills/fist-mbt/SKILL.md` + `plugins/claude/skills/fist-commander/SKILL.md` +
`plugins/claude/skills/fist-mbt/SKILL.md` + `plugins/codearts/skills/fist-commander/SKILL.md` +
`plugins/codearts/skills/fist-mbt/SKILL.md` + `plugins/deepseek-harness/instructions.append.md` +
`plugins/deepseek-harness/skills/fist-mbt/SKILL.md`。未触碰 `src/router/model_router.mbt`（并发 WIP）。

## 资源消耗

- 1 个提交：`e8d04ec`（9 插件文件重生成）
- 1 次 `gen_plugins.py` + 1 次 `check_plugin_sync.py`
- 1 次全守卫链（5 守卫）
- 1 次 `git diff` 确认并发 WIP 边界

## 任务分配记录

指挥官亲自：
- **识别安全窗口**：先确认并发 agent 已提交、工作树干净、投影源干净、工具数稳定 166——四项齐全才重生成，
  避免"重生成又漂"的无效工作
- **并发 WIP 精准隔离**（金条纪律）：重生成后 `git status` 出现 `src/router/model_router.mbt` 改动，
  立即 `git diff` 确认是并发 agent 刚加的 P1.1 cooldown_until——**精确提交 9 插件文件，不碰 src/router**，
  用 `git add` 列明路径而非 `git add .`
- **实测验证而非自述**（金条八）：重生成后复跑 `check_plugin_sync` 确认 rc=0 + PASS，不凭"重生成成功"推断守卫绿
- **未触碰并发 WIP**：提交后剩余 1 份未提交（并发 agent 的 model_router.mbt），正确保留

## 遗留风险

1. **并发 agent 仍在改 `src/router/model_router.mbt`**：若再加工具，工具数 166 会变，插件态需再次重生成。
2. **`check_test_sync` 红**：文档 1033 vs 实测约 1048（并发 agent 加测试），等收口时连文档一起修。
3. **BUG-155 dist/、BUG-156 issue_scan 规则前提错误**：均 OPEN 待 owner/后续裁决。

## 后续建议

1. **并发 agent 收口 router 工作后**：跑一次全守卫链确认工具数若变则再重生成 plugins + 同步测试数文档，发权威 Release。
2. **修 BUG-156**：修正 `moonbit-map-set-no-rebind` 规则的 `why` 陈述（Map([]).set 原地生效）或收窄 pattern。
3. **监控 check_plugin_sync**：并发 agent 加工具后需重生成，可考虑把重生成纳入提交门禁脚本或 CI。

## 超额内容

- **「重生成又漂」的预防**：并发环境下重生成插件态最怕"刚重生成就又被加工具"。本轮的四项判定
  （工作树干净 / 投影源干净 / 工具数稳定 / 账本已更新）是重生成前必查清单——任一不满足就等，
  全满足才动。这是多 agent 并发下做"一源四态"投影的标准姿势。
- **守卫从"一直红"到"归绿"的价值**：`check_plugin_sync` 连续多轮红会让人误以为"插件态坏了"，
  实为并发 agent 加工具未重投影。本轮归绿说明守卫本身正确，只是需要"谁加工具谁重生成"的收口动作。
- **BUG 账本同步入账**：重生成自动把 BUG-1~156（154 条）投影进插件态 SKILL.md——一源四态的真价值：
  改账本一次，四个宿主全同步。

## 来源

- 重生成：`python scripts/gen_plugins.py`（输出 166 工具 / v0.3.8 / BUG-1~156）
- 守卫：`check_plugin_sync.py`（PASS）、`check_doc_surface.py`、`check_tools_sync.py`（166 工具稳定）
- 投影源：`plugins/source/` + `src/server/server.mbt` + `moon.mod` + `memory/bugs.md`
- 并发 WIP 识别：`git diff src/router/model_router.mbt`（P1.1 cooldown_until）
- 提交：`e8d04ec`（9 插件文件），三端同步
