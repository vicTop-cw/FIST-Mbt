# 2026-10-20 R21 汇报：`slave/fix/syntax-noise-sweep` —— 纯语法噪声三族合清（19 条）

- 分支：`slave/fix/syntax-noise-sweep`（stacked on `deprecated-not-operator`(#7) → `core-package-imports`(#6) → `unused-package-deps`(#5) → `moonc-0.10.16-result-api`）
- FIST：根任务 `T0`（清零 moon check 告警逐族）三叶全部已完成 → 上一单 `verify` 收口；本单承接在新根 `T0r2`（publish→claim→execute→submit→verify 全绿，deliverable 已落库）
- 台账：BUG-345（low，FIXED，轮次 R21）

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 1694 | **1675** |
| 同判据 errors | 0 | **0** |
| 0008 redundant_modifier | 12 | **0** |
| 0021 missing_pattern_arguments | 6 | **0** |
| 0013 unresolved_type_variable | 1 | **0** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| moonfmt 非漂移分歧（6 份文件） | — | **0** |
| `pkg.generated.mbti` 与 HEAD 的残留差（归一化 BUG-330 漂移后） | — | **0 行** |

改动 6 份 `.mbt`：删字段级冗余 `pub`（`src/hat/hat_report_build.mbt` 8、`src/router/router_caf.mbt` 4）、给 `Number(n)` 模式补 `..`（`src/server/selfdrive_round_tick.mbt` 4、`bugreport_status_wbtest.mbt:105`、`src/store/multi_store_test.mbt:128`）、`nobreak` 分支的 `ignore([])` → `()`（`src/server/supervisor_tools.mbt:420`）。零接口变更（`check_mbti_sync` 前后同 PASS）。

## 资源消耗

- 工具调用：约 18 次；`moon check --target js` 全量 2 次、`moon test` 全量 1 次、moonfmt 逐文件 1 轮 × 6 份、`moon info` 2 包 1 次、守卫 1 轮 13 格。
- 本机墙钟：本单约 12 分钟。
- 返工：2 次。① `git diff --name-only` 在 `.mbti` 未还原时把 18 份 mbti 也送进 moonfmt，报"unknown file type"，属测量面而非代码面；② `moon info` 顺带把 BUG-330 的 `Int`→`Int32`、`? :`→`~ :` 漂移写进两份 `.mbti`，需先归一化比对确认残留 0 行再还原，避免把另一单的改动夹进本单。

## 任务分配记录

- 指挥官亲自做：族选择（比过 0008/0021/0013/0067/0004 五档的风险）、`0013` 的改法判断（`()` 而非加类型标注）、终审判据（实跑 check/test/fmt 比对）、记忆沉淀。
- 子代理：未派（19 条改动用 loc 驱动脚本一次成型，派单成本高于收益）。
- FIST 自我迭代：`scripts/fist.py`（本机构建产物）驱动 `T0` 收口 + `T0r2` 全生命周期。

## 遗留风险

1. **0067 unused_async 未清**：`gitcode_execute_batch` 在 `src/server/github_gitcode_native.mbt`（native-only），删 `async` 会改公开 API 的箭头类型，而本机 native 面量不了（缺 core native bundle）。留待与 native 面一起处理。
2. **死代码三族（0009/0006/0001）未动**：需要读设计意图，且 0006 已被仓内 `warnings = "-6-35"` 豁免 —— 是否连豁免一起改属 owner 决策。
3. **stacked 合并顺序**：本支依赖 #7 → #6 → #5 → `moonc-0.10.16-result-api`（master 树当前不可编译，BUG-328 未合）。MR base 若为 master，diff 含祖先改动。
4. **6 处预存 CI 红**逐项与改前一致（badge 1108、test_sync 现状面缺 1302 声明、其 selftest 基准夹具、scripts_index 的 `run_check_t0r21.py`、doc_surface 的 USAGE 0.3.8、entry_paths 的 SOP.md:44），非本单引入。
5. **`fist.py` 新鲜度守卫与 mbti 还原相互打架**（BUG-32 + BUG-331 家族），每次收尾都要手工 `moon build cmd/cli --target js` 一次才能驱动 FIST 命令；这是机器级工序，不是仓库缺陷。

## 后续建议

1. 下一族建议 **0078 result_error_return**(13)：`src/server/mcpcf_embed.mbt` 9 + `server.mbt` 4，判据是"能把失败当普通值返回的 API 改成 `T raise E`"，属真语义改动，需要单独一轮且必须逐函数看调用面。
2. 或者 **0004 missing_priv**(11)：纯可见性收窄，编译器已证实这些类型不出现在包公开签名里，风险只在跨包/测试引用；改后 `check_mbti_sync` 会同步变化，值得作为"低风险第二单"。
3. 大块仍是 0025(803) 与 0020 的 `Json::value`(430)，建议先试点 3–5 份文件量测再批量。
4. BUG-330（Int/Int32、`? :`/`~ :`）需 owner 决策，否则本机 moonfmt 与仓库拼写永远是两套真源。

## 超额内容（本单边界之外做了什么、为什么）

- 顺带把 `T0` 根任务按 FIST 语义 `verify` 收口（三叶已全绿，根任务停在待验收会挡住后续 plan），并把本单挂到新根 `T0r2`，使"用 fist-mbt 命令自我迭代"这条要求连续三轮可证。
- 顺带量到 `fist.py` 自身两道守卫的实跑证据：① 入参白名单——`publish --priority/--importance` 被拒并回「实际接受：created_by, description, namespace, project_dir」（别名表 ns/desc 也一并回显）；② 权限面——`created_by=commander` 被拒 `publish 仅限人类指挥官（created_by=human_steward）`，故本单根任务按主机指令登记为 `human_steward` 发起。
- 未做：未加任何 `warnings = "-..."` 压制、未删任何"看起来没用"的类型或函数、未跑破坏性 `cleanup_artifacts.py`、未动 `.mbti` 拼写面。

## 来源

- 判据：`temp/chk11.json`（1694/0，改前）、`temp/chk12.json`（**1675/0**，改后，8/21/13 命中 0）、`temp/pt8.log`（`Total tests: 1302, passed: 1302, failed: 0`）。
- 守卫：`check_pkg_imports` / `check_mbti_sync` / `check_tools_sync` 均 PASS；moonfmt 逐行比对脚本输出（非漂移分歧 0、bare LF 0）。
- 台账：`memory/bugs.md` BUG-345 + `### FIXED(2026-10-20 轮次 R21 / BUG-345)`；ledger 329 → 330 条。
- 日志：`memory/2026-10-20.md` R21 小节。
- 既有结论：BUG-329（bundle-core 合成、`moon fmt`/`moonc` 的 `\?\` ICE 与 shim 绕法）、BUG-330（拼写漂移）、BUG-32（fist.py 入口产物新鲜度守卫）、BUG-342/343/344（依赖面两族 + `not()` 子族 + 同行同码去重的量法坑）。
- 仓库规范：`AGENTS.md` 金条四/五/八、`docs/SOP.md:33`（禁 `git add -A`，逐路径显式 staging）。
