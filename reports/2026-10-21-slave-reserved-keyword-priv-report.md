# 2026-10-21 R25 汇报：`slave/fix/reserved-keyword-and-priv` —— 0035/0004/0067 三族清零（25 条）

- 分支：`slave/fix/reserved-keyword-and-priv`（stacked on `unused-value-locals`(#11) → `deprecated-api-renames`(#10) → `test-qualified-imports`(#9) → `syntax-noise-sweep`(#8) → `deprecated-not-operator`(#7) → `core-package-imports`(#6) → `unused-package-deps`(#5) → `moonc-0.10.16-result-api`）
- FIST：根任务 `T0`/`T0r2`/`T0r3`/`T0r4`/`T0r5` 均已完成；本单挂新根 `T0r6` 走完整生命周期（publish→claim→execute→submit→verify）
- 台账：BUG-349（low，FIXED，轮次 R25）—— 本分支链上第一份动 `.mbti` 接口面的单

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 676 | **651** |
| 同判据 errors | 0 | **0** |
| `error_code` 0035 reserved_keyword | 13 | **0** |
| `error_code` 0004 missing_priv | 11 | **0** |
| `error_code` 0067 unused_async | 1 | **0** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| moonfmt 非漂移分歧（9 份 .mbt） | — | **0** |
| `check_mbti_sync` | PASS（641 条） | **PASS（642 条）** |

改动 12 份文件（9 份 `.mbt` + 3 份 `pkg.generated.mbti`）：11 个包内 `struct` 补 `priv` 并在接口里删除对应 11 条 `type X`；`namespace`→`ns_filter` 10 处、`local`→`bak_ver`/`bin_name` 4 处；`pub async fn gitcode_execute_batch` 去 `async`（源 + 接口各 1 行）。

## 资源消耗

- 工具调用：约 17 次；`moon check` 全量 1 次 + 包级试点 1 次（`src/server` 362/0）、`moon test` 全量 1 次、`moon build cmd/cli` 1 次、`moon info` 可行性量测 1 次、moonfmt 逐文件 1 轮 × 9 份、守卫 1 轮 × 13 例、FIST 生命周期 5 次调用。
- 本机墙钟：本单约 9 分钟。
- 返工：1 次 —— `temp/fix25.py` 首版按"前一行必为空"假设删 mbti 声明，撞上 `DebateRegistry` 是 `// Types and methods` 之后的首条（前行是注释）而中断；脚本改为"前行空则删前空行、否则删后空行"，并把整树 `git restore -- src cmd` 后从干净态重跑（试点 `ScanRule` 一并纳入脚本，避免脚本不可重入）。

## 任务分配记录

- 指挥官亲自做：三族合单的边界判断（哪些是零接口、哪些必须镜像 mbti）、`moon info` 可行性量测与结论、priv 镜像规则的试点与铺开、终审判据（check/test/build/fmt/守卫实跑）、记忆沉淀。
- 子代理：未派（25 处改动 loc 驱动一次成型，派单成本高于收益）。
- FIST 自我迭代：`scripts/fist.py`（本机构建产物）驱动 `T0r6` 全生命周期，连续第八轮。

## 遗留风险

1. **接口面收缩没有"生成器背书"**：`.mbti` 由手写镜像得出。虽然 `check_mbti_sync`、`moon check`、`moon test` 三面复验，但**用与仓库同源的工具链跑一次 `moon info` 才是最终背书**——本机 0.10.16 跑不了（242 行残留漂移）。建议 owner 在有匹配工具链的环境跑一次 `moon info` 确认 0 行差异。
2. **0079(63) 与 0078(13) 同样动接口面**，本单的"镜像 + keep 备份"工序是它们的前置知识；工序若漏掉 keep 备份，判据一跑就把手工镜像冲掉。
3. **0020 语义档 527 条未动**：`Json::value` 430 是最大单体，`as_bool`/`as_string` 22 条虽然编译器给全了替换文本，但内联形态可读性差，需要先定"是否引入包内 `priv fn` 辅助"。
4. **stacked 合并顺序**：本支依赖 #11 → #10 → #9 → #8 → #7 → #6 → #5 → `moonc-0.10.16-result-api`（master 树当前不可编译，BUG-328 未合）。MR base 若为 master，diff 含祖先改动。
5. **6 处预存 CI 红**逐项与改前一致（badge 1108、test_sync 现状面、其 selftest 基准夹具、scripts_index 的 `run_check_t0r21.py`、doc_surface 的 USAGE 0.3.8、entry_paths 的 SOP.md:44），非本单引入；`cleanup_artifacts --check` 仍 DIRTY(328) 属本机取证件累积。

## 后续建议

1. 下一单建议 **0079 implicit_impl_as_method**(63)：本单已把接口面工序跑通，0079 只是把"删行"换成"加 `pub extend` 行"，判据面可从 651 直接压到 588。
2. 或 **0020 的 `as_bool`/`as_string` 22 条**：先在 `src/server/server.mbt` 试点一个包内 `priv fn json_str(j : Json) -> String?`，看是否把 3 处重复的 `.as_string().unwrap_or("")` 一并收敛，再决定是否铺开。
3. **0004 的方法论建议写进 `docs/SOP.md`**：接口面单的"镜像 + keep 备份 + restore"三步是可复用工序，不该每轮重新发现。
4. BUG-330 仍是所有接口面单根因；本轮把它从"格式噪声"升级为"接口面无法用生成器背书"，优先级应提高。

## 超额内容（本单边界之外做了什么、为什么）

- 加做了 `moon info` 可行性量测与归一残留计算（242 行），把"接口面单能不能自动化"这个问题一次性钉死，避免后续 0079/0078 轮次重复试错。
- 加做了单点试点（`ScanRule` + `moon check src/server`）再铺开，用 1 处成本换 11 处零风险。
- 未做：未加 `warnings = "-..."` 压制、未删任何死码（0001/0006/0007/0009）、未改 `Json::value`/`as_bool`/`as_string` 语义档、未动 `Result[T,E]`→`raise` 签名、未跑破坏性 `cleanup_artifacts.py`。

## 来源

- 判据：`temp/chk24.json`（676/0，改前）、`temp/chk25.json`（**651/0**，终态，4/35/67 命中 0）、`temp/pilot_priv.json`（包级试点 362/0）、`temp/pt14.log`（`Total tests: 1302, passed: 1302, failed: 0`）。
- 接口面量测：干净树 `moon info` → 18 份 mbti / 237 行；按 BUG-330 归一后残留 242 行（本单正文 ①②）。
- 镜像备份：`temp/keep25/{engine,router,server}.mbti`。
- 守卫：`check_mbti_sync`（642）/ `check_pkg_imports` / `gen_plugins --check` / `gen_plugins --selftest` / `check_plugin_sync` PASS；`temp/run_guards12.py` 全 13 例输出。
- 台账：`memory/bugs.md` BUG-349 + `### FIXED(2026-10-21 轮次 R25 / BUG-349)`；`memory/2026-10-21.md` R25 小节。
- 改法脚本：`temp/fix25.py`（priv + mbti 镜像 + 0035 改名 + 0067 去 async）、`temp/show_family.py`、`temp/msg_census.py`、`temp/fmtverify2.py`、`temp/t6_drive.py`。
- 既有结论：BUG-346/348（check/test 重写 mbti 的工序，本单第四次确认）、BUG-347（0020 机械档与语义档边界）、BUG-330（拼写漂移，本单升级为接口面背书问题）、BUG-344（复跑命中才算收口）、BUG-32（fist.py 产物新鲜度守卫）。
- 仓库规范：`AGENTS.md` 金条四/五/八（含 `moon info` 后须审 `.mbti` diff 的要求）、`docs/SOP.md:33`（禁 `git add -A`，逐路径显式 staging）。
