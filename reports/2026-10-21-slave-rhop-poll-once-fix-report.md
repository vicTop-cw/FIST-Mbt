# 副机报告 · 同步基点编译红修复（T0r31 / BUG-374）

- 日期：2026-10-21
- 分支：`slave/fix/rhop-poll-once-missing`（基点 `68ae3a0`，强制 `slave/` 前缀，不开主干）
- 任务：T0r31 `修同步基点编译红（host master 68ae3a0）`
- 台账：BUG-374（FIXED）
- 交付面：`src/ops/rhop_poll.mbt`（新增 66 行）+ `src/ops/moon.pkg`（+1 行依赖）

## 结果摘要

1. **同步**：本地 `master` 由 `34ce658` 快进到 gitcode 的 `68ae3a0`（+34 个提交），另起 `slave/misc/sync-master-20261021` 记录同步点；旧的 R48 分支 `slave/guard/bug-reference-integrity`（`1492edc`）原样保留，未改写、未合并。
2. **发现**：同步后的基点是**编译红**的。`src/ops/rhop_native_wbtest.mbt` 在 51/57/72/101/131/146 六处调用 `rhop_poll_once`，而该符号在 `src/**` 与全部 git 历史（`git log --all -S 'rhop_poll_once'`）中都没有定义 ⇒ `moon check` 与 `moon check --target js` 均报 `6 × Error: [4021] The value identifier rhop_poll_once is unbound` + `Error: failed when checking project`。这是「测试先落库、实现漏提交」的缺口，不是回退；同步前本机旧树没有这份测试，所以此前轮次读数全绿。
3. **修复**：补最小实现（不改测试一行）。解码纪律对齐依赖真源 `.mooncakes/vicTop-cw/RX-MBT/rhop/rhop_js.mbt` 的 `from_filesystem_with`：只收 `.rhop` 且排除 `.rhop.tmp`，`RhopEnvelope::decode → v == 1 → cipher.decrypt → RhopPacket::from_json_text`，任一步失败静默跳过；去重键为**完整路径**，`seen` 由调用方以 `Ref[HashSet[String]]` 跨拍持有。
4. **读数**：`moon check --target js` → 578 warnings / **0 errors**；`moon test --target js` → `Total tests: 1340, passed: 1340, failed: 0`（`src/ops` 单包 200/200/0）；`check_mbti_sync` / `check_pkg_imports` / `check_publish_payload` PASS；`moonfmt.exe -w` 与落盘内容 CR 归一零差异。

## 证据（真实读数）

| 项 | 命令 / 判据 | 读数 | 证据文件 |
|---|---|---|---|
| 编译面（修复后） | `moon check --target js` | rc=0，`ran 35 tasks … (578 warnings, 0 errors)` | `temp/t31_check_full.log` |
| 测试面 | `moon test --target js` | `Total tests: 1340, passed: 1340, failed: 0` | `temp/t31_test_full.log` |
| 包级 | `moon test --target js src/ops` | `200/200/0` | `temp/t31_test_ops.log` |
| 编译面（修复前） | `moon check` / `--target js` | `6 × [4021] rhop_poll_once is unbound` | `temp/sync_check.log:2937-3016` |
| 守卫电池 | `python scripts/run_guards.py` | 38 格 / 失败 5 / SKIP 5 / 缺执行面的尺 0 | `temp/t31_battery2.log` |
| 格式化 | `~/.moon/bin/moonfmt.exe -w` + CR 归一对比 | 零差异（裸 `moon fmt` 仍因 `\\?\` 路径 ICE） | `temp/t31_fmt.log` |
| 接口面 | `check_mbti_sync` | PASS（24 份 `.mbti` / 655 条声明） | 会话输出 |
| 打包面 | `check_publish_payload` | PASS（未跟踪 0） | 会话输出 |

### 预存红清单（本单未引入、未代修，按裁决「预存红不代修，但必须点名 rc 与成因」）

| 守卫 | rc | 成因 |
|---|---|---|
| `check_scripts_index.py` | 1 | `run_guards.py` 等脚本未登记进 `scripts/README.md`（同步基点既有） |
| `check_exit_code_contract.py --selftest` | 2 | 判据自检不通过（范围自述与实测天花板不一致），同步基点既有 |
| `check_plugin_sync.py` | 1 | 下游 `gen_plugins` 被账本重复编号挡住 ⇒ 生成器拒产，投影无法逐字节比对 |
| `gen_plugins.py --check` | 2 | 账本 5 个编号被重复使用：BUG-183×2 / BUG-192×2 / BUG-328×2 / BUG-329×2 / BUG-330×2 |
| `check_plan_landing.py --gate` | 1 | 历史计划面文档缺失/移动，超出声明上限（同步基点既有） |

另：`check_badge` / `check_test_sync` / `check_deprecated_*` 五格因本地 `temp/pt27.log`、`temp/chk47.json` 是上一轮的过期夹具（期望 1302，当前 1340）而 SKIP——已移到 `temp/stale-r48/`，与干净 CI 树同形，不构成绿证据。

## 分析

- **为什么是「补实现」而不是「改测试/删测试」**：四条用例断言的是协议行为（跨拍不重收、非 `.rhop` 与 `.rhop.tmp` 不收、坏信封/坏密文/版本不符静默跳过），与依赖包 `rhop_js.mbt` 的 `from_filesystem_with` 语义一致。测试是需求面，缺的是产品面；改测试等于把缺口藏起来。
- **为什么去重用完整路径**：测试 `rn_dir("dedupe")` 要求同一文件跨两拍只消费一次，同时不同目录的同名文件互不干扰；用文件名做键会把后者误判为重复。`seen` 由调用方持有是测试签名的一部分，做成局部量则第二拍重收。
- **为什么静默跳过**：轮询要能扛住「对端写了一半」「版本不同步」这类常态脏数据；一条坏文件把整拍打断，等于把单个发送方的错误放大成全信道停摆。
- **两个语法坑（moon 0.1.20261016）**：泛型约束写函数名前（`fn[T : @rhop.RhopCipher]`），`fn name[T]` 报 `[3002]`；`RhopEnvelope::decode` 返回 `Result` 而非 raise，对它用 `catch` 会同时吃 `[4028]` 与 `unused_try`，必须 `match`。
- **台账取号 374**：本分支基点最大编号 BUG-358，而本地未合并的 R47/R48 两条 MR 分支已占用 359..373，故跳开取 374，避免与在途 MR 撞号。

## 资源消耗

- 模型：本地副机 agent（无外部计费）；成本 0。
- 本单 token 估算：输入约 12 万 / 输出约 1.5 万（含同步取证、源码定位、实现与全量验证）。
- 本单耗时：约 15 分钟（同步段另计：快进 34 个提交 + 依赖/构建缓存重建）。
- 全量验证：`moon check --target js` 35 tasks；`moon test --target js` 1340 用例；电池 38 格。

## 任务分配记录

- T0r31（self-iteration root）：`publish` → `claim --assignee slave-agent` → 本单实现与验证 → `execute`（本报告读数入 deliverable）→ `submit` → `verify --verifier commander`。
- 全部代码/文档由副机 agent 直接执行，无二次分包；不可逆操作（合并、发布）未触碰。

## 遗留风险

1. **宿主基点的其余预存红仍未收口**（见上表 5 条）：其中账本 5 组重复编号会 FATAL `gen_plugins`，进而红 `check_plugin_sync`；scripts 索引与 exit-code 契约是独立缺口；plan_landing 是历史文档面。均需单独开单元，本单不代修。
2. **本机 `moon fmt` 不可用**：`Sys_error("\\\\?: Invalid argument")`（`\\?\` 路径前缀），只能逐件跑 `moonfmt.exe -w`。CI 的 fmt 门当前是 `continue-on-error`，本机绕法不能替代 CI 判定。
3. **`.mbti` 抖动（BUG-330）**：`moon check` 会刷出 24 份 Int→Int32 拼写抖动，本轮已证明纯拼写后 `git restore`，但下次跑 check 仍会复现，属工具链面缺陷。
4. **文档数字漂移**：README 徽章 1339/1339、AGENTS.md 1347/1347，本基点实测 1340/1340。本单不改文档（宿主 WIP 未收口，改了会与之冲突），留待文档同步单处理。
5. **同型缺口未全量核查**：本单只修了这一处「测试引用不存在符号」。建议对全仓 `_test/_wbtest` 做一次同型扫描（全量 `moon check` 已能覆盖，但值得确认是否还有被 `.gitignore` 挡掉的实现文件）。

## 后续建议

1. 宿主合并本单后，把「测试文件引用的符号必须与实现同批落库」补进提交前自检流程（全量 `moon check` 一次即可扫出）。
2. 账本重复编号收口（5 组）应单独立项，是 `gen_plugins` / `check_plugin_sync` 两格转绿的前置。
3. `scripts/README.md` 补齐 `run_guards.py` 等未登记脚本，让 `check_scripts_index` 转绿。
4. 换机或换钉版后复验 `moon fmt --check`，再考虑撤销 CI fmt 门的 `continue-on-error`。

## 超额内容

- 顺手定位并证明 `src/ops` 里 8 条 `0071 core_package_not_imported` 的根因是 `moon.pkg` 缺 `hashset` 依赖，补依赖后自然消失（578 vs 586 warnings），未额外改代码。
- 把上一轮遗留的过期夹具（`temp/pt27.log`、`temp/chk47.json`）移入 `temp/stale-r48/`，使电池 SKIP 语义与干净 CI 树一致，避免「拿旧日志当现状」。
- 记录了本机 `moon fmt` ICE 与 `moonfmt.exe -w` 绕法的完整证据链，供后续换机时复验。

## 来源

- 台账：`memory/bugs.md` BUG-374
- 日志：`memory/2026-10-21.md` R49 段
- 依赖真源：`.mooncakes/vicTop-cw/RX-MBT/rhop/rhop_js.mbt`、`packet.mbt`、`cipher.mbt`
- 测试面：`src/ops/rhop_native_wbtest.mbt`（未改动）
- 证据文件：`temp/sync_check.log`、`temp/sync_check_js.log`、`temp/t31_check_full.log`、`temp/t31_test_full.log`、`temp/t31_test_ops.log`、`temp/t31_battery2.log`、`temp/t31_fmt.log`
- 提交面：待本单 commit（`slave/fix/rhop-poll-once-missing`），推送 gitcode 后由 owner 开 MR
