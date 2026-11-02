# BUG-565 · 跨项目账本误落 + 网关静默失败 · 决策单（2026-11-03）

## 0. 一句话结论
- **症状 B（静默失败）已修**：2 行补丁，已在仓内副本完成语法 + 复现 + 回归三重实测验证；只差部署回拷一条命令，**等审批**（本轮审批门禁拒 `writes outside the workspace`）。
- **症状 A（账本误落）的根因是设计边界，不是编码 bug**：放宽即开写面 ⇒ **owner 裁决三案**（推荐 B 白名单案）。
- **BUG-565 账本条目挂起**：`memory/bugs.md` 与计数面均在另一 agent 的 WIP 中，`git commit -- <path>` 会连带提交外来条目、污染计数面 ⇒ 入账文本已备好（§6），WIP 收口后同批入账（账本 + 计数面 + `gen_plugins` 投影）。

## 1. 事件（来源：另一 agent 自书勘误，本轮只读核对）
- 2026-11-02：vq 项目（`E:/IDEProjects/AI/vq`）的 agent 调 `fist-mbt call report_bug --project_dir .`，**21 条账目（BUG-544~564）误落本树** `memory/bugs.md`（未提交 WIP）。
- 对方已自行处置：在本树账本写两段 `## 勘误(2026-11-02 · VQ 项目账目误落本树)`（声明误落、「本树条目按 append-only 保留不回改，以本节为准」）+ 逐字搬移 `E:/IDEProjects/AI/vq/memory/bugs.md`。
- 本轮实测核对：WIP diff **+138 行** = 21 条外来条目 + 2 段勘误 + 1 段 FIXED 状态节；条目引用路径（`crates/vq-*` / `apps/web` / `packages/sql-editor` / `chroma_db`）在本仓零命中；HEAD 最高 BUG id 仍 = 543。

## 2. 机制 A（为什么账本必然落错树）
1. `fist-mbt call ...` → launcher `runGateway()`：`runChild(py, [gateway, ...args], { cwd: REPO, ... })` —— **网关 cwd 被钉在 REPO**（`REPO = FIST_MBT_REPO || 'E:\IDEProjects\AI\FIST-Mbt'`）。
2. server 按自身 cwd 解析相对 `project_dir` ⇒ `.` 恒 = REPO 指向的树。
3. `bug_project_dir_ok`（`src/server/bugreport.mbt:30-46`）拒绝空串 / 绝对路径 / 盘符 / `..` —— **fail-closed，有意设计**（与 `write_gate_ok` 写门配对；回执已回显 `resolved_path` + `server_cwd`，`bugreport.mbt:435-440`，注释自述「调用方拿两者一比就知道账写进了哪本台账」）。

⇒ **调用方无出路**：`.` 指向错树，绝对路径被拒。信息当时就在回执里（server_cwd），调用方未比对。这是「能力缺口 + 回执未被消费」的叠加，不是单点故障。

## 3. 机制 B（静默失败）—— 本轮已修，补丁已验证
- `call` 路由 `quiet=true`（quiet 只对 `serve` 与 `FIST_MBT_VERBOSE=1` 放松）；gateway-not-found 的 `log('FATAL ...')` 被 quiet 吞掉 → `process.exit(1)` **零输出**。
- `runChild` 的 spawn 失败消息（`'<label> spawn failed: ...'`）不带 FATAL 前缀，**同族第二处**静默面。

**复现（本轮实测）**：`FIST_MBT_REPO=E:/IDEProjects/AI/vq node serve-launcher.cjs call bug_list --project-dir .` → rc=1、**0 字节输出**（证据 `temp/bug565_prefix_out.txt`）。与对方勘误描述逐字吻合（对方措辞「bundle 发现失败」，精确口径是 **gateway 发现**失败——bundle 只涉 `serve` 路由）。

**补丁（2 处，落在仓内副本 `temp/serve-launcher-patched.cjs`，底本 `temp/serve-launcher-orig.cjs`）**：

```diff
 const log = (m) => {
-  if (quiet) return;
+  // BUG-565: FATAL 诊断必须绕过 quiet（call 等一次性路由曾 rc=1 零输出，失败不自述）
+  if (quiet && !m.startsWith('FATAL')) return;
   try { process.stderr.write('[fist-mbt-launcher] ' + m + '\n'); } catch {}
 };
 ...
-  child.on('error', (e) => { log(label + ' spawn failed: ' + e.message); process.exit(1); });
+  child.on('error', (e) => { log('FATAL ' + label + ' spawn failed: ' + e.message); process.exit(1); });
```

**验证（全实测，副本上跑）**：
| # | 检查 | 读数 |
|---|---|---|
| 1 | `node --check` 整文件 | PASS |
| 2 | 修后复现（同命令，FIST_MBT_REPO=vq） | rc=1 + **82 字节自述** `[fist-mbt-launcher] FATAL gateway not found: E:\IDEProjects\AI\vq\scripts\fist.py`（`temp/bug565_postfix_out.txt`） |
| 3 | 回归：`version`（CLI 路由） | rc=0，`FIST-Mbt v0.3.11` |
| 4 | 回归：`call bug_list --project-dir .`（默认 REPO 网关路由） | rc=0，370,440 字节，`count=550`，`resolved_path`/`server_cwd` 正确回显 |

**部署动作（待审批；本轮审批门禁拒 `bash (writes outside the workspace)`，不重试）**：
```bash
cp "%LOCALAPPDATA%/FIST-Mbt/serve-launcher.cjs" "%LOCALAPPDATA%/FIST-Mbt/serve-launcher.cjs.bak-20261103-bug565"
cp temp/serve-launcher-patched.cjs "%LOCALAPPDATA%/FIST-Mbt/serve-launcher.cjs"
node -c "%LOCALAPPDATA%/FIST-Mbt/serve-launcher.cjs"
```
回滚 = 把 `.bak-20261103-bug565` 拷回原名（判例 BUG-437/470：launcher 在 repo 外，改动只靠报告 + 备份留痕，BUG-470 R4 同口径）。

## 4. 症状 A 修复方向（owner 裁决）
| 案 | 内容 | 判定 |
|---|---|---|
| A 放行绝对路径 | `bug_project_dir_ok` 去掉绝对路径 / 盘符拒绝 | **否决**：fail-open —— server 获得对机器任意目录的写能力。该拒绝是安全边界（与写门配对、对齐 S1/S3 授权面姿态），不是 bug |
| **B 白名单（推荐）** | 新增 env `FIST_PROJECT_ROOTS`（允许的项目根列表）；`project_dir`（绝对或相对）解析后**落在其一之下才接受**；env 未设时行为与现状**逐字一致**（fail-closed 默认、零回归） | 可逆（不设即回滚）、改动最小（`bugreport.mbt` 校验面 + 白盒锁 + 拒绝时 Err 自述根清单）、回执 `server_cwd` 回显已就位 |
| C 网关 cwd = 调用方 cwd | launcher `cwd: REPO` 改为继承调用方 cwd | **不作首选**：所有相对路径语义变化（`mcp_smoke` 等既有调用方依赖 `.`=仓库根），且 DB 自举面连带（`check_demo_isolation`：裸跑自举仓库根台账）⇒ 行为变更 + 迁移面 |

**裁决请求**：A / B / C 三选一或挂起。若 B 通过：派子代理执行（`bugreport.mbt` 校验面 + 白盒锁 + 判例-29/30 变异对照 + `moon test`），终审走 `moon test --target js` 全绿。

## 5. 后续（非本单，均已定性、未动手）
1. **检测守卫**（上轮巡检建议 #4）：新守卫「bugs.md 新条目引用路径必须在本仓存在」，防外来条目污染计数面。**现在不起**：另一 agent 的 21 条 WIP 会当场撞红，且对方已刻意声明「保留不回改、以勘误为准」——现在起守卫 = 拦对方收口。WIP 收口后起（新 `scripts/*.py` 按纪律同批给执行面：入电池或 `_` 前缀共享模块）。
2. **计数面裁决**：对方勘误声明 21 条外来条目「保留本树、append-only」⇒ WIP 收口后账本文件将**永久含 BUG-544~564**，而计数面（AGENTS.md 现状面 `BUG-1~543` / 528 条、`gen_plugins` 投影头、`check_tools_sync` 面）需重裁。当前漂移实测：`bug_list` 工作树 `count=550` vs AGENTS 面 528。裁决候选：
   - (i) 条目保留 + 计数面扩到 564（对外来条目打标注，如 severity 段后加 `[foreign:vq]`——动抬头文法，连带 BUG-434 三段式锁）；
   - (ii) 条目移入 `memory/bugs-foreign/` 归档 + 本树留引用节（最干净，但违反 append-only 字面——需 owner 明确豁免）；
   - (iii) 条目保留 + 计数守卫按勘误节白名单排除（勘误节本身成为计数排除面，需新守卫判「条目是否被勘误覆盖」）。
   **需 owner 裁决**；裁决前计数面维持现状面，不在本树单方扩面。
3. **审批门禁误判观察（本轮新）**：无凭据命令 `python scripts/check_plugin_sync.py`（cl7 投影一致性探针）被审批门禁判 `bash (credential access)` 拒 ⇒ 本轮 cl7 读数缺位（计数面漂移暂以 `bug_list` 实测数替代）。**复发即立账**（门禁把守卫族判成凭据访问 = 巡检面被无声缩小，与判例-33「判据指错方向」同族）。

## 6. BUG-565 账本入账文本（已备，WIP 收口后同批：账本 + 计数面 + `gen_plugins` 投影）
```
## BUG-565 [入账时 UTC] [medium] OPEN
- summary: 跨项目账本误落（根因）+ 网关静默失败：`fist-mbt call report_bug --project_dir .` 必把账落到 FIST_MBT_REPO 指向的树（默认本树），调用方无出路（绝对路径被设计拒绝）⇒ vq 项目 21 条账误落本树；且 `FIST_MBT_REPO` 指向无网关项目时 `fist-mbt call` rc=1 零输出（FATAL 被 quiet 吞）
- detail: 机制 A：launcher runGateway() 以 cwd:REPO 起网关，server 按自身 cwd 解析相对路径，bug_project_dir_ok 拒绝对路径/盘符/..（fail-closed 有意）⇒ 无出路；回执回显 server_cwd/resolved_path 而调用方未比对。机制 B：call 路由 quiet=true 吞 gateway-not-found FATAL + spawn 失败消息无 FATAL 前缀 ⇒ rc=1 零输出（本轮复现 0 字节；修后同命令自述 82 字节）。B 半 2 行补丁已验证（仓内副本：node --check PASS + 复现自述 + 默认路由 version/call bug_list 回归 rc=0），部署待审批（门禁拒 writes outside the workspace，不重试）。A 半属设计边界，三案见决策单 §4 待 owner 裁决。后续：外来条目检测守卫 + 计数面裁决（均待 WIP 收口）。
- task_id: （B 半为指挥官部署动作、A 半待 owner 裁决，本轮无派单）
- evidence: temp/bug565_prefix_out.txt（0B）/ temp/bug565_postfix_out.txt（82B）/ temp/serve-launcher-orig.cjs 与 temp/serve-launcher-patched.cjs（diff 两处）/ reports/2026-11-03-bug565-project-dir-decision-sheet.md
```

## 7. 来源
- 对方勘误：WIP `memory/bugs.md`（BUG-544~564 + 两段勘误，本轮只读核对，未接触）
- 代码面：`src/server/bugreport.mbt:29-46`（`bug_project_dir_ok`）/ `:310`（report_bug 校验）/ `:327`（write gate）/ `:435-440`（回执回显）/ `:525-528`（bug_list 校验）；`%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs`（quiet / runGateway / runChild / chooseBundle）
- 判例先例：BUG-437（launcher 设立 + 双路由）/ BUG-470 R4（launcher 在 repo 外，留痕只靠报告 + 备份）/ BUG-434（抬头三段式文法）/ 判例-33（判据须对准生产路径）
- 日期：2026-11-03
